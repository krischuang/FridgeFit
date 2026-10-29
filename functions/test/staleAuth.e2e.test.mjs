//
// The recent-authentication gate, exercised by running the Functions
// emulator with `DELETION_MAX_AUTH_AGE_SECONDS=0` so that every token counts
// as too old.
//
// Run with:  cd functions && npm run test:e2e:stale
//
// This lives in its own file, and its own emulator run, deliberately. Under
// a zero-second window *no* deletion can succeed, so running the main suite
// in this configuration would fail almost every test for reasons that have
// nothing to do with what they assert. Only the checks that belong to the
// rejection path are here.
//

import { strict as assert } from "node:assert";
import { before, beforeEach, describe, it } from "node:test";

import {
  adminExists,
  assertEmulatorOnly,
  callFunction,
  clearAuth,
  clearFirestore,
  createEmailUser,
  lookupUser,
  seedUserData,
  seededPaths,
  signInWithGoogle,
} from "./support/harness.mjs";

let nextEmail = 0;
const uniqueEmail = (prefix = "stale") => `${prefix}-${Date.now()}-${nextEmail++}@example.test`;

before(() => {
  assertEmulatorOnly();
  assert.equal(
    process.env.DELETION_MAX_AUTH_AGE_SECONDS,
    "0",
    "this file must run with DELETION_MAX_AUTH_AGE_SECONDS=0 (use npm run test:e2e:stale)",
  );
});

beforeEach(async () => {
  await clearFirestore();
  await clearAuth();
});

describe("recent authentication is required", () => {
  it("rejects the request with FAILED_PRECONDITION", async () => {
    const user = await createEmailUser(uniqueEmail());

    const result = await callFunction("requestAccountDeletion", { idToken: user.idToken });

    assert.equal(result.ok, false, "a stale session must not be accepted");
    assert.equal(result.body.error?.status, "FAILED_PRECONDITION", JSON.stringify(result.body));
    assert.match(result.body.error?.message ?? "", /sign in again/i);
  });

  it("deletes nothing when it rejects", async () => {
    // The property that matters: a rejected request is not a partial
    // deletion. Everything must be exactly as it was.
    const user = await createEmailUser(uniqueEmail());
    await seedUserData(user.uid);

    await callFunction("requestAccountDeletion", { idToken: user.idToken });

    for (const path of seededPaths(user.uid)) {
      assert.equal(await adminExists(path), true, `${path} was deleted by a rejected request`);
    }
    assert.ok(await lookupUser(user.uid, { byUid: true }), "the account was deleted anyway");
    assert.equal(
      await adminExists(`deletionJobs/${user.uid}`),
      false,
      "a job was opened for a rejected request",
    );
    assert.equal(
      await adminExists(`deletionLocks/${user.uid}`),
      false,
      "a rejected request left the user's writes locked",
    );
  });

  it("applies to Google accounts too", async () => {
    const user = await signInWithGoogle(uniqueEmail("google-stale"));

    const result = await callFunction("requestAccountDeletion", { idToken: user.idToken });

    assert.equal(result.ok, false);
    assert.equal(result.body.error?.status, "FAILED_PRECONDITION");
  });

  it("still allows reading status, which needs no recent login", async () => {
    // Checking progress is not destructive, so it is gated on being signed
    // in and nothing more. A user whose deletion half-finished must be able
    // to find that out without re-authenticating first.
    const user = await createEmailUser(uniqueEmail("status"));

    const result = await callFunction("accountDeletionStatus", { idToken: user.idToken });

    assert.equal(result.ok, true, JSON.stringify(result.body));
    assert.equal(result.body.result.state, "pending");
  });

  it("still rejects an unauthenticated caller with UNAUTHENTICATED, not FAILED_PRECONDITION", async () => {
    // Ordering check: "not signed in" must be distinguishable from
    // "signed in too long ago", or the client cannot tell the user which of
    // the two to do something about.
    const result = await callFunction("requestAccountDeletion");

    assert.equal(result.body.error?.status, "UNAUTHENTICATED");
  });
});
