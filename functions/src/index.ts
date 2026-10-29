/**
 * FridgeFit Cloud Functions.
 *
 * One feature: server-side account deletion. See `deletion.ts` for the
 * workflow and why the ordering is what it is.
 */

import { initializeApp } from "firebase-admin/app";
import { HttpsError, onCall, CallableRequest } from "firebase-functions/v2/https";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import * as functionsV1 from "firebase-functions/v1";

import { DeletionOutcome, deleteUserData, readJob, runDeletion, unlockUser } from "./deletion";

initializeApp();

setGlobalOptions({
  region: "us-central1",
  // Deletion walks every collection a user owns. The default 60s is not
  // enough for a large pantry plus a long signalling history, and a timeout
  // mid-delete is the case the resume logic exists to recover from - better
  // to make it rare.
  timeoutSeconds: 540,
  memory: "512MiB",
  // One deletion at a time per instance. These are rare, long, and
  // write-heavy; packing them onto one instance only increases the chance of
  // a timeout taking several users' jobs down together.
  concurrency: 1,
  maxInstances: 10,
});

/**
 * How recently the caller must have signed in, in seconds.
 *
 * Account deletion is irreversible, so a token minted hours ago on an
 * unattended phone is not good enough - this is the server-side equivalent
 * of Firebase's own `requiresRecentLogin`, and it is enforced here rather
 * than trusted to the client.
 *
 * Configurable so the emulator suite can drive the rejection path: a test
 * sets it to 0 and every request is "too old". There is no way for a client
 * to influence it.
 */
const maxAuthAgeSeconds = (): number => {
  const configured = Number(process.env.DELETION_MAX_AUTH_AGE_SECONDS);
  return Number.isFinite(configured) && configured >= 0 ? configured : 300;
};

/**
 * Establishes *who is calling*, from the verified token only.
 *
 * The uid is taken from `request.auth.uid`, which the Functions runtime
 * derives from a cryptographically verified Firebase ID token. No uid, path,
 * or collection name is ever read from the request payload - a client that
 * sends `{ uid: "someone-else" }` is ignored, because nothing looks at it.
 * That is the single most important property of this endpoint and it is
 * asserted directly in `deletion.e2e.test.mjs`.
 */
function requireRecentlyAuthenticatedUid(request: CallableRequest): string {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "Sign in before deleting your account.");
  }

  // `auth_time` is when the user actually authenticated, not when the token
  // was last refreshed - a refreshed token does not reset it, which is
  // exactly the property this check needs.
  const authTimeSeconds = Number(auth.token?.auth_time);
  if (!Number.isFinite(authTimeSeconds)) {
    throw new HttpsError("failed-precondition", "Sign in again before deleting your account.");
  }

  const ageSeconds = Date.now() / 1000 - authTimeSeconds;
  if (ageSeconds > maxAuthAgeSeconds()) {
    throw new HttpsError(
      "failed-precondition",
      "For your security, sign in again before deleting your account.",
    );
  }

  return auth.uid;
}

/**
 * Starts or resumes deletion of the **caller's own** account, and waits for
 * it to finish.
 *
 * Awaited rather than fire-and-forget so the client receives a definitive
 * answer: the app must not say "deleted" until the backend says so, and a
 * "we've queued it" response would make that impossible to honour. Callers
 * that time out can poll `accountDeletionStatus`, and a retry resumes rather
 * than restarts.
 */
export const requestAccountDeletion = onCall(async (request): Promise<DeletionOutcome> => {
  const uid = requireRecentlyAuthenticatedUid(request);
  logger.info("account deletion requested", { uid });
  return runDeletion(uid);
});

/**
 * Reports progress for the caller's own job, for a client that lost the
 * connection mid-deletion or is resuming after a relaunch.
 *
 * Read-only, and - like the endpoint above - scoped to `request.auth.uid`,
 * so it cannot be used to probe anyone else's account.
 */
export const accountDeletionStatus = onCall(async (request): Promise<DeletionOutcome> => {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "Sign in to check deletion status.");
  }

  const job = await readJob(auth.uid);
  if (!job) {
    return {
      state: "pending",
      completed: false,
      deletedCollections: [],
      lastError: null,
      attempts: 0,
    };
  }

  return {
    state: job.state,
    completed: job.state === "completed",
    deletedCollections: job.deletedCollections ?? [],
    lastError: job.lastError ?? null,
    attempts: job.attempts ?? 0,
  };
});

/**
 * Backstop for an account that was deleted *without* going through
 * `requestAccountDeletion` - from the Firebase console, from the Admin SDK,
 * or by this workflow crashing between the data step and the auth step.
 *
 * This is what makes requirement 9 hold: once the auth account is gone the
 * user has no credentials and can never ask for cleanup again, so the
 * cleanup has to be able to run without them. This runs as admin and takes
 * the uid from the deletion event itself.
 *
 * A v1 trigger because `auth.user().onDelete` has no v2 equivalent that
 * works without Identity Platform. Mixing generations in one codebase is
 * supported.
 */
export const onAuthUserDeleted = functionsV1.auth.user().onDelete(async (user) => {
  const uid = user.uid;
  logger.info("auth account deleted; sweeping any remaining data", { uid });

  try {
    // Idempotent: on the normal path the data is already gone and this is a
    // handful of empty reads.
    //
    // `recordProgress: false` matters here. This runs for accounts that
    // never had a deletion job (console-initiated removals), and the
    // progress write would otherwise *create* a job document for a user who
    // no longer exists.
    await deleteUserData(uid, [], { recordProgress: false });
    await unlockUser(uid);
  } catch (error) {
    // Deliberately swallowed. Throwing would retry the trigger, and the
    // failure is already recorded; a user whose account is gone cannot be
    // shown an error anyway.
    logger.error("post-deletion sweep failed", {
      uid,
      message: error instanceof Error ? error.message : String(error),
    });
  }
});
