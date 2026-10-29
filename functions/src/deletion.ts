/**
 * Server-side account deletion.
 *
 * ## Why this exists at all
 *
 * The iOS client can already delete a user's Firestore data, and still does
 * (see `FirestoreAccountDataDeleter`). What it cannot do is finish:
 *
 *  - Firestore offers **no recursive delete on the client**. The client loops
 *    over a hard-coded list of collections, so a collection added later and
 *    forgotten here survives "delete my account" silently.
 *  - If the app is killed, loses the network, or the user force-quits
 *    part-way through, the client cannot resume - and after the auth account
 *    is gone it can never authenticate to try again.
 *  - Nothing stops the app writing *new* documents into a subtree that is
 *    mid-deletion.
 *
 * The Admin SDK fixes all three: `recursiveDelete` walks subcollections the
 * server does not have to know about, the job document survives process
 * death, and a lock document makes the security rules reject user writes
 * while a deletion is in flight.
 *
 * ## The ordering rule, and why it is not negotiable
 *
 * **Data first, auth last.** `firestore.rules` grants `users/{uid}/**` only
 * while `request.auth.uid == uid`. That constrains the *client*; the Admin
 * SDK bypasses rules entirely, so the server could delete in either order.
 * It still deletes data first, for a different reason: if the auth account
 * goes first and data cleanup then fails, the user can no longer
 * authenticate to ask for a retry, and the only thing that could finish the
 * job is a backstop running without their credentials. That backstop exists
 * (`onAuthUserDeleted`), but depending on it as the primary path would mean
 * routinely leaving orphaned data behind and hoping a trigger fires.
 *
 * So: delete data, verify it is gone, then delete the account. Requirement 9
 * - "delete the auth account only when the workflow can safely complete or
 * recover remaining cleanup without the user's credentials" - is satisfied
 * twice over: the data is already gone by then, and if anything is somehow
 * left, `onAuthUserDeleted` runs as admin and needs no credentials.
 *
 * ## What is NOT claimed
 *
 * There is **no cross-service atomicity**. Firestore and Firebase
 * Authentication are separate systems with no shared transaction. A crash
 * between step 4 and step 5 leaves data deleted and the account alive; a
 * crash during step 5 leaves an account that may or may not exist. Both are
 * recoverable and neither is silent - see `RECOVERY` below and
 * `docs/assessment4-final-production-verification.md`.
 */

import { getAuth } from "firebase-admin/auth";
import { FieldValue, Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

import {
  ALL_USER_COLLECTIONS,
  CANDIDATE_COLLECTIONS,
  FLAT_USER_COLLECTIONS,
  SESSION_COLLECTION,
  deletionJobPath,
  deletionLockPath,
  userDocumentPath,
} from "./paths";

// MARK: - Job model

/**
 * Where a deletion job has got to.
 *
 * Explicit states rather than a pair of booleans, because the difference
 * between "nothing has happened", "your data is gone but your login is not"
 * and "it is done" is exactly what the user needs to be told, and a boolean
 * pair can represent combinations that mean nothing.
 */
export type DeletionState =
  /** Accepted, not yet started. */
  | "pending"
  /** Firestore data is being removed. Nothing irreversible to auth yet. */
  | "deletingData"
  /** All Firestore data is gone. The auth account still exists. */
  | "dataDeleted"
  /** The auth account is being removed. */
  | "deletingAuth"
  /** Finished. Data and account are both gone. */
  | "completed"
  /** Stopped. `lastError` says where. Retryable unless stated otherwise. */
  | "failed";

/** Terminal states - a job in one of these is not picked up again. */
const TERMINAL_STATES: ReadonlySet<DeletionState> = new Set(["completed"]);

export interface DeletionJob {
  uid: string;
  state: DeletionState;
  requestedAt: Timestamp;
  updatedAt: Timestamp;
  /** How many times processing has been started for this job. */
  attempts: number;
  /**
   * Collections already confirmed empty, so a resumed job skips them. This
   * is what makes an interrupted job cheap to finish rather than a full
   * re-run.
   */
  deletedCollections: string[];
  /** Set while a worker is processing, so two workers do not overlap. */
  claimedAt: Timestamp | null;
  lastError: string | null;
  completedAt: Timestamp | null;
}

/**
 * A claim older than this is assumed dead - the function timed out, the
 * instance was recycled, the deploy rolled. The next request takes over.
 *
 * Deliberately longer than the function's own timeout, so a slow-but-alive
 * worker is never stolen from.
 */
const STALE_CLAIM_MS = 10 * 60 * 1000;

/** Bounded in-process retries for transient Firestore failures. */
const MAX_DELETE_ATTEMPTS = 3;

// MARK: - Public result

export interface DeletionOutcome {
  state: DeletionState;
  /** True only when the account and all of its data are gone. */
  completed: boolean;
  deletedCollections: string[];
  lastError: string | null;
  attempts: number;
}

const outcomeOf = (job: DeletionJob): DeletionOutcome => ({
  state: job.state,
  completed: job.state === "completed",
  deletedCollections: job.deletedCollections,
  lastError: job.lastError,
  attempts: job.attempts,
});

// MARK: - Job lifecycle

const db = (): Firestore => getFirestore();

/**
 * Creates the job if there is none, resumes it if it stalled, and refuses to
 * start a second worker over a live one.
 *
 * Idempotence lives here. Repeated requests - a user tapping twice, a client
 * retrying after a dropped connection - converge on one job document rather
 * than racing. The transaction is what makes that true under concurrency:
 * two simultaneous calls cannot both claim.
 *
 * @returns the job to process, or `null` when another worker already holds
 *   a live claim (the caller should report progress, not duplicate work).
 */
export async function claimJob(uid: string, now: Date): Promise<DeletionJob | null> {
  const reference = db().doc(deletionJobPath(uid));

  return db().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const nowStamp = Timestamp.fromDate(now);

    if (!snapshot.exists) {
      const job: DeletionJob = {
        uid,
        state: "deletingData",
        requestedAt: nowStamp,
        updatedAt: nowStamp,
        attempts: 1,
        deletedCollections: [],
        claimedAt: nowStamp,
        lastError: null,
        completedAt: null,
      };
      transaction.set(reference, job);
      return job;
    }

    const existing = snapshot.data() as DeletionJob;

    // Already done. Repeated requests are answered from the record rather
    // than re-running anything.
    if (TERMINAL_STATES.has(existing.state)) {
      return null;
    }

    // Someone else is working on it and is still alive.
    const claimedAtMs = existing.claimedAt?.toMillis() ?? 0;
    const claimIsLive = claimedAtMs > 0 && now.getTime() - claimedAtMs < STALE_CLAIM_MS;
    if (claimIsLive) {
      return null;
    }

    // Stale or never claimed: take it over, keeping the progress already
    // made so this is a resume rather than a restart.
    const resumed: DeletionJob = {
      ...existing,
      uid,
      state: existing.state === "failed" ? "deletingData" : existing.state,
      updatedAt: nowStamp,
      attempts: (existing.attempts ?? 0) + 1,
      deletedCollections: existing.deletedCollections ?? [],
      claimedAt: nowStamp,
      lastError: null,
    };
    transaction.set(reference, resumed, { merge: true });
    return resumed;
  });
}

/** Reads the job document, or `null` if there has never been one. */
export async function readJob(uid: string): Promise<DeletionJob | null> {
  const snapshot = await db().doc(deletionJobPath(uid)).get();
  return snapshot.exists ? (snapshot.data() as DeletionJob) : null;
}

async function updateJob(uid: string, patch: Partial<DeletionJob>): Promise<void> {
  await db()
    .doc(deletionJobPath(uid))
    .set({ ...patch, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
}

// MARK: - The write lock

/**
 * Blocks the user's own writes for the duration.
 *
 * Without this, the app could add a pantry item into a subtree that is
 * halfway through being deleted, and the item would survive the deletion
 * that was supposed to remove everything. `firestore.rules` checks for this
 * document on every user write; see `isNotBeingDeleted`.
 *
 * Written by the server only - the rules give the user read access so the
 * app can explain the state, and no write access at all, so a client cannot
 * unlock itself.
 */
export async function lockUser(uid: string): Promise<void> {
  await db().doc(deletionLockPath(uid)).set({
    uid,
    lockedAt: FieldValue.serverTimestamp(),
    reason: "accountDeletion",
  });
}

export async function unlockUser(uid: string): Promise<void> {
  await db().doc(deletionLockPath(uid)).delete();
}

// MARK: - Data deletion

/**
 * Removes every document under `users/{uid}`, including subcollections.
 *
 * `recursiveDelete` is the whole reason this is worth doing server-side: it
 * walks subcollections the server was never told about, so a WebRTC session's
 * `callerCandidates`/`calleeCandidates` - and anything a future feature adds
 * - go with it. The explicit collection list is still used, but only to
 * record *progress* and to verify afterwards, not to decide what to delete.
 *
 * @returns the collections confirmed empty.
 */
export async function deleteUserData(
  uid: string,
  alreadyDeleted: readonly string[] = [],
  options: { recordProgress?: boolean } = {},
): Promise<string[]> {
  // `recordProgress: false` is used by the post-deletion sweep. `updateJob`
  // writes with `merge: true`, which **creates** the document when it is
  // absent - so a sweep for an account that never had a job (deleted from
  // the console) would resurrect a half-filled job document for a user who
  // no longer exists, and leave it there forever. Found by
  // `does not corrupt progress when requests overlap`, which saw the
  // resurrected document appear after the collection had been cleared.
  const recordProgress = options.recordProgress ?? true;
  const firestore = db();
  const done = new Set(alreadyDeleted);
  const userDocument = firestore.doc(userDocumentPath(uid));

  for (const collection of ALL_USER_COLLECTIONS) {
    if (done.has(collection)) {
      continue;
    }

    await withRetries(`delete ${collection} for ${uid}`, async () => {
      await firestore.recursiveDelete(
        userDocument.collection(collection),
        firestore.bulkWriter({ throttling: true }),
      );
    });

    done.add(collection);
    if (recordProgress) {
      // Progress is persisted per collection, so an interruption costs at
      // most one collection's work rather than the whole job.
      await updateJob(uid, { deletedCollections: [...done] });
    }
  }

  // The user document itself, plus anything beneath it that the explicit
  // list above does not name. Deleting a document that does not exist is a
  // no-op in Firestore, not an error.
  await withRetries(`delete user document for ${uid}`, async () => {
    await firestore.recursiveDelete(userDocument);
  });

  return [...done];
}

/**
 * Proves the subtree is actually empty before the account is deleted.
 *
 * Deliberately a real read, not an assumption that the delete above worked.
 * This is the gate on an irreversible step, and the whole point of the
 * exercise is not to report a deletion that did not happen.
 */
export async function findRemainingData(uid: string): Promise<string[]> {
  const firestore = db();
  const userDocument = firestore.doc(userDocumentPath(uid));
  const remaining: string[] = [];

  for (const collection of FLAT_USER_COLLECTIONS) {
    const snapshot = await userDocument.collection(collection).limit(1).get();
    if (!snapshot.empty) {
      remaining.push(collection);
    }
  }

  // Sessions and their candidate subcollections, which are the ones a
  // non-recursive delete would strand.
  const sessions = await userDocument.collection(SESSION_COLLECTION).limit(1).get();
  if (!sessions.empty) {
    remaining.push(SESSION_COLLECTION);
  } else {
    for (const session of (await userDocument.collection(SESSION_COLLECTION).listDocuments())) {
      for (const candidates of CANDIDATE_COLLECTIONS) {
        const orphans = await session.collection(candidates).limit(1).get();
        if (!orphans.empty) {
          remaining.push(`${SESSION_COLLECTION}/${session.id}/${candidates}`);
        }
      }
    }
  }

  return remaining;
}

// MARK: - The workflow

/**
 * Runs (or resumes) deletion for `uid` to completion.
 *
 * Every step is idempotent, so calling this again after any failure is safe
 * and picks up where it stopped.
 */
export async function runDeletion(uid: string, now: Date = new Date()): Promise<DeletionOutcome> {
  const existing = await readJob(uid);
  if (existing && TERMINAL_STATES.has(existing.state)) {
    return outcomeOf(existing);
  }

  const job = await claimJob(uid, now);
  if (!job) {
    // Either it finished between the two reads, or another worker holds a
    // live claim. Report what the record says rather than starting a second
    // pass over the same data.
    const current = await readJob(uid);
    return current
      ? outcomeOf(current)
      : {
          state: "pending",
          completed: false,
          deletedCollections: [],
          lastError: null,
          attempts: 0,
        };
  }

  try {
    // 1. Stop new user writes landing behind the deletion.
    await lockUser(uid);
    await updateJob(uid, { state: "deletingData" });

    // 2. Remove the data, resuming from recorded progress.
    const deleted = await deleteUserData(uid, job.deletedCollections);

    // 3. Prove it is gone. Never delete the account on an assumption.
    const remaining = await findRemainingData(uid);
    if (remaining.length > 0) {
      throw new Error(`data still present after deletion: ${remaining.join(", ")}`);
    }

    await updateJob(uid, { state: "dataDeleted", deletedCollections: deleted });

    // 4. Only now the irreversible step. If this fails the data is gone and
    //    the login is not - reported honestly as `failed`, and retryable.
    await updateJob(uid, { state: "deletingAuth" });
    await deleteAuthUser(uid);

    // 5. Release the lock and record completion.
    await unlockUser(uid);
    await updateJob(uid, {
      state: "completed",
      claimedAt: null,
      lastError: null,
      completedAt: FieldValue.serverTimestamp() as unknown as Timestamp,
    });

    logger.info("account deletion completed", { uid, attempts: job.attempts });
    const finished = await readJob(uid);
    return finished
      ? outcomeOf(finished)
      : { state: "completed", completed: true, deletedCollections: deleted, lastError: null, attempts: job.attempts };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logger.error("account deletion failed", { uid, message });

    // The claim is released so a retry can take over immediately rather than
    // waiting out the stale window. The lock deliberately stays: data is
    // partially gone, and letting the app write into that subtree again
    // would leave a half-deleted account looking usable.
    await updateJob(uid, { state: "failed", lastError: message, claimedAt: null });

    const failed = await readJob(uid);
    return failed
      ? outcomeOf(failed)
      : {
          state: "failed",
          completed: false,
          deletedCollections: [],
          lastError: message,
          attempts: job.attempts,
        };
  }
}

/**
 * Deletes the Firebase Authentication account.
 *
 * An already-absent account is success, not failure - that is what makes a
 * retry after a partial failure converge instead of erroring forever.
 */
async function deleteAuthUser(uid: string): Promise<void> {
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "auth/user-not-found") {
      return;
    }
    throw error;
  }
}

/**
 * Retries a transient failure a bounded number of times.
 *
 * Bounded on purpose: an unbounded retry on a permission or quota error
 * burns the function's whole timeout and reports nothing useful.
 */
async function withRetries(description: string, operation: () => Promise<void>): Promise<void> {
  let lastError: unknown;

  for (let attempt = 1; attempt <= MAX_DELETE_ATTEMPTS; attempt += 1) {
    try {
      await operation();
      return;
    } catch (error) {
      lastError = error;
      logger.warn("retrying after failure", {
        description,
        attempt,
        message: error instanceof Error ? error.message : String(error),
      });
      if (attempt < MAX_DELETE_ATTEMPTS) {
        await new Promise((resolve) => setTimeout(resolve, 100 * attempt));
      }
    }
  }

  throw lastError instanceof Error ? lastError : new Error(String(lastError));
}

/** Exposed so the emulator suite can assert on the real values. */
export const INTERNALS_FOR_TESTS = {
  STALE_CLAIM_MS,
  MAX_DELETE_ATTEMPTS,
};
