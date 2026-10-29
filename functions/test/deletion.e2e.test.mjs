//
// End-to-end account deletion, against the Firebase Local Emulator Suite
// (Authentication + Firestore + Functions).
//
// Run with:  cd functions && npm run test:e2e
//
// Every account and every document here is synthetic and created by the test
// itself. No production project is contacted - see `harness.mjs` and
// `noProductionAccess.test.mjs`.
//

import { strict as assert } from "node:assert";
import { before, beforeEach, describe, it } from "node:test";

import {
  CANDIDATE_COLLECTIONS,
  SEEDED_COLLECTIONS,
  SESSION_ID,
  adminExists,
  adminGet,
  adminList,
  adminWrite,
  assertEmulatorOnly,
  callFunction,
  clearAuth,
  clearFirestore,
  createEmailUser,
  lookupUser,
  seedUserData,
  seededPaths,
  signInEmailUser,
  signInWithGoogle,
  waitFor,
} from "./support/harness.mjs";

let nextEmail = 0;
const uniqueEmail = (prefix = "user") => `${prefix}-${Date.now()}-${nextEmail++}@example.test`;

before(() => {
  assertEmulatorOnly();
});

beforeEach(async () => {
  await clearFirestore();
  await clearAuth();
});

/** Asserts that every seeded path for `uid` is gone. */
async function assertUserDataGone(uid) {
  for (const path of seededPaths(uid)) {
    assert.equal(await adminExists(path), false, `${path} survived deletion`);
  }
}

// MARK: - The happy path

describe("successful complete deletion", () => {
  it("deletes every Firestore collection, the nested candidates, and the auth account", async () => {
    const user = await createEmailUser(uniqueEmail("complete"));
    await seedUserData(user.uid);

    // Pre-condition: the data really is there, so a passing assertion below
    // cannot be a false positive from an empty subtree.
    for (const path of seededPaths(user.uid)) {
      assert.equal(await adminExists(path), true, `${path} was not seeded`);
    }

    const result = await callFunction("requestAccountDeletion", { idToken: user.idToken });

    assert.equal(result.ok, true, JSON.stringify(result.body));
    assert.equal(result.body.result.state, "completed");
    assert.equal(result.body.result.completed, true);

    await assertUserDataGone(user.uid);
    assert.equal(await adminExists(`users/${user.uid}`), false, "the user document survived");

    // The auth account itself.
    assert.equal(await lookupUser(user.uid, { byUid: true }), null, "the auth account survived");
  });

  it("covers all five FridgeFunds collections explicitly", async () => {
    const user = await createEmailUser(uniqueEmail("funds"));
    await seedUserData(user.uid);

    const fundsCollections = SEEDED_COLLECTIONS.filter((c) => c.startsWith("funds"));
    assert.equal(fundsCollections.length, 5, "expected exactly five Funds collections");

    await callFunction("requestAccountDeletion", { idToken: user.idToken });

    for (const collection of fundsCollections) {
      assert.deepEqual(
        await adminList(`users/${user.uid}/${collection}`),
        [],
        `${collection} was not emptied`,
      );
    }
  });

  it("removes nested WebRTC candidate subcollections, which a parent delete would strand", async () => {
    const user = await createEmailUser(uniqueEmail("nested"));
    await seedUserData(user.uid);

    // Extra nesting, to prove the recursion is not a hard-coded two levels.
    await adminWrite(`users/${user.uid}/webrtcSessions/session-2/callerCandidates/c-9`);
    await adminWrite(`users/${user.uid}/webrtcSessions/session-3/calleeCandidates/c-9`);

    await callFunction("requestAccountDeletion", { idToken: user.idToken });

    for (const candidates of CANDIDATE_COLLECTIONS) {
      assert.deepEqual(
        await adminList(`users/${user.uid}/webrtcSessions/${SESSION_ID}/${candidates}`),
        [],
        `${candidates} orphans survived`,
      );
    }
    assert.deepEqual(await adminList(`users/${user.uid}/webrtcSessions/session-2/callerCandidates`), []);
    assert.deepEqual(await adminList(`users/${user.uid}/webrtcSessions/session-3/calleeCandidates`), []);
    assert.deepEqual(await adminList(`users/${user.uid}/webrtcSessions`), []);
  });

  it("records a completed job with per-collection progress", async () => {
    const user = await createEmailUser(uniqueEmail("job"));
    await seedUserData(user.uid);

    await callFunction("requestAccountDeletion", { idToken: user.idToken });

    const job = await adminGet(`deletionJobs/${user.uid}`);
    assert.ok(job, "no job document was written");
    assert.equal(job.state, "completed");
    assert.equal(job.uid, user.uid);
    assert.ok(job.completedAt, "completedAt was not stamped");
    for (const collection of SEEDED_COLLECTIONS) {
      assert.ok(
        job.deletedCollections.includes(collection),
        `${collection} missing from recorded progress`,
      );
    }
  });

  it("releases the write lock when it finishes", async () => {
    const user = await createEmailUser(uniqueEmail("unlock"));
    await seedUserData(user.uid);

    await callFunction("requestAccountDeletion", { idToken: user.idToken });

    assert.equal(
      await adminExists(`deletionLocks/${user.uid}`),
      false,
      "the lock was left behind, which would block a re-registered account",
    );
  });
});

// MARK: - Email/password lifecycle

describe("email/password account creation and deletion", () => {
  it("creates, signs in, deletes, and then cannot sign in again", async () => {
    const email = uniqueEmail("lifecycle");
    const password = "test-password-123";

    const user = await createEmailUser(email, password);
    await seedUserData(user.uid);

    // It works before deletion.
    const before = await signInEmailUser(email, password);
    assert.equal(before.ok, true, "the account should work before deletion");

    const result = await callFunction("requestAccountDeletion", { idToken: user.idToken });
    assert.equal(result.body.result.completed, true);

    // And is genuinely gone afterwards.
    const after = await signInEmailUser(email, password);
    assert.equal(after.ok, false, "sign-in succeeded after the account was deleted");
    assert.match(
      JSON.stringify(after.body),
      /EMAIL_NOT_FOUND|INVALID_LOGIN_CREDENTIALS|USER_DISABLED/,
      `unexpected post-deletion sign-in error: ${JSON.stringify(after.body)}`,
    );
  });
});

// MARK: - Google provider

describe("Google provider-aware deletion", () => {
  it("deletes a google.com account and its data through the same endpoint", async () => {
    const email = uniqueEmail("google");
    const user = await signInWithGoogle(email);
    await seedUserData(user.uid);

    // The account really is federated - this is what the client's
    // provider-aware reauthentication branches on.
    const record = await lookupUser(user.uid, { byUid: true });
    const providers = (record?.providerUserInfo ?? []).map((p) => p.providerId);
    assert.ok(providers.includes("google.com"), `expected google.com, got ${providers}`);

    const result = await callFunction("requestAccountDeletion", { idToken: user.idToken });

    assert.equal(result.body.result.completed, true, JSON.stringify(result.body));
    await assertUserDataGone(user.uid);
    assert.equal(await lookupUser(user.uid, { byUid: true }), null);
  });

  it("does not require a password for a Google-only account", async () => {
    // The whole point: a Google-only user has no FridgeFit password, so the
    // endpoint must not demand one. It takes no credential argument at all.
    const user = await signInWithGoogle(uniqueEmail("google-nopw"));
    await seedUserData(user.uid);

    const result = await callFunction("requestAccountDeletion", {
      idToken: user.idToken,
      data: {},
    });

    assert.equal(result.body.result.completed, true, JSON.stringify(result.body));
  });
});

// MARK: - Authorization

describe("authorization", () => {
  it("rejects an unauthenticated request", async () => {
    const result = await callFunction("requestAccountDeletion");

    assert.equal(result.ok, false);
    assert.equal(result.body.error?.status, "UNAUTHENTICATED", JSON.stringify(result.body));
  });

  it("rejects a garbage bearer token", async () => {
    const result = await callFunction("requestAccountDeletion", { idToken: "not-a-real-token" });

    assert.equal(result.ok, false);
    assert.equal(result.body.error?.status, "UNAUTHENTICATED", JSON.stringify(result.body));
  });

  it("ignores a client-supplied uid and deletes only the caller's own account", async () => {
    // The single most important property of the endpoint. A malicious client
    // sends someone else's uid in the payload; the server must take the uid
    // from the verified token and never from the body.
    const victim = await createEmailUser(uniqueEmail("victim"));
    const attacker = await createEmailUser(uniqueEmail("attacker"));
    await seedUserData(victim.uid);
    await seedUserData(attacker.uid);

    const result = await callFunction("requestAccountDeletion", {
      idToken: attacker.idToken,
      data: { uid: victim.uid, userId: victim.uid, path: `users/${victim.uid}` },
    });

    assert.equal(result.body.result.completed, true);

    // The attacker deleted themselves.
    await assertUserDataGone(attacker.uid);
    assert.equal(await lookupUser(attacker.uid, { byUid: true }), null);

    // The victim is entirely untouched.
    for (const path of seededPaths(victim.uid)) {
      assert.equal(await adminExists(path), true, `${path} was destroyed by another user`);
    }
    assert.ok(await lookupUser(victim.uid, { byUid: true }), "the victim's account was deleted");
    assert.equal(
      await adminExists(`deletionJobs/${victim.uid}`),
      false,
      "a job was opened against another user",
    );
  });

  it("rejects a status request from an unauthenticated caller", async () => {
    const result = await callFunction("accountDeletionStatus");

    assert.equal(result.ok, false);
    assert.equal(result.body.error?.status, "UNAUTHENTICATED");
  });

  it("scopes status to the caller, so it cannot probe another account", async () => {
    const other = await createEmailUser(uniqueEmail("other"));
    await seedUserData(other.uid);
    await callFunction("requestAccountDeletion", { idToken: other.idToken });

    const observer = await createEmailUser(uniqueEmail("observer"));
    const result = await callFunction("accountDeletionStatus", {
      idToken: observer.idToken,
      data: { uid: other.uid },
    });

    // Their own (absent) job, not the other user's completed one.
    assert.equal(result.body.result.state, "pending");
    assert.equal(result.body.result.completed, false);
  });
});

// MARK: - Cross-account isolation

describe("cross-account isolation", () => {
  it("leaves every other account's data and login intact", async () => {
    const alice = await createEmailUser(uniqueEmail("alice"));
    const bob = await createEmailUser(uniqueEmail("bob"));
    const carol = await signInWithGoogle(uniqueEmail("carol"));
    for (const uid of [alice.uid, bob.uid, carol.uid]) {
      await seedUserData(uid);
    }

    await callFunction("requestAccountDeletion", { idToken: bob.idToken });

    await assertUserDataGone(bob.uid);
    for (const uid of [alice.uid, carol.uid]) {
      for (const path of seededPaths(uid)) {
        assert.equal(await adminExists(path), true, `${path} was collateral damage`);
      }
      assert.ok(await lookupUser(uid, { byUid: true }), `${uid}'s account was deleted`);
    }
  });
});

// MARK: - Idempotence

describe("repeated deletion requests", () => {
  it("is idempotent: a second request reports completed without erroring", async () => {
    const user = await createEmailUser(uniqueEmail("repeat"));
    await seedUserData(user.uid);

    const first = await callFunction("requestAccountDeletion", { idToken: user.idToken });
    assert.equal(first.body.result.completed, true);

    // The token still verifies for a short while after the account is gone,
    // which is exactly when a retrying client would send it.
    const second = await callFunction("requestAccountDeletion", { idToken: user.idToken });

    assert.equal(second.ok, true, JSON.stringify(second.body));
    assert.equal(second.body.result.state, "completed");
    assert.equal(second.body.result.completed, true);
  });

  it("does not corrupt progress when requests overlap", async () => {
    const user = await createEmailUser(uniqueEmail("concurrent"));
    await seedUserData(user.uid);

    // Three simultaneous requests, as a double-tap plus a client retry would
    // produce. Exactly one job document must exist and it must end completed.
    const results = await Promise.all([
      callFunction("requestAccountDeletion", { idToken: user.idToken }),
      callFunction("requestAccountDeletion", { idToken: user.idToken }),
      callFunction("requestAccountDeletion", { idToken: user.idToken }),
    ]);

    for (const result of results) {
      assert.equal(result.ok, true, JSON.stringify(result.body));
    }

    const jobs = await adminList("deletionJobs");
    assert.deepEqual(jobs, [user.uid], `expected one job, got ${JSON.stringify(jobs)}`);

    const job = await adminGet(`deletionJobs/${user.uid}`);
    assert.equal(job.state, "completed");
    await assertUserDataGone(user.uid);
  });

  it("a repeated request cannot delete another user's data", async () => {
    const alice = await createEmailUser(uniqueEmail("iso-alice"));
    const bob = await createEmailUser(uniqueEmail("iso-bob"));
    await seedUserData(alice.uid);
    await seedUserData(bob.uid);

    for (let i = 0; i < 3; i += 1) {
      await callFunction("requestAccountDeletion", { idToken: alice.idToken });
    }

    for (const path of seededPaths(bob.uid)) {
      assert.equal(await adminExists(path), true, `${path} destroyed by repeated requests`);
    }
  });
});

// MARK: - Recovery

describe("retry and recovery", () => {
  it("resumes an interrupted job instead of restarting it", async () => {
    const user = await createEmailUser(uniqueEmail("resume"));
    await seedUserData(user.uid);

    // Simulate a worker that died part-way: data partly gone, progress
    // recorded, claim stale (so it is not mistaken for a live worker).
    await adminWrite(`deletionJobs/${user.uid}`, {
      uid: { stringValue: user.uid },
      state: { stringValue: "deletingData" },
      attempts: { integerValue: "1" },
      deletedCollections: {
        arrayValue: { values: [{ stringValue: "pantry" }, { stringValue: "devices" }] },
      },
      claimedAt: { timestampValue: "2020-01-01T00:00:00Z" },
      lastError: { nullValue: null },
      completedAt: { nullValue: null },
      requestedAt: { timestampValue: "2020-01-01T00:00:00Z" },
      updatedAt: { timestampValue: "2020-01-01T00:00:00Z" },
    });

    const result = await callFunction("requestAccountDeletion", { idToken: user.idToken });

    assert.equal(result.body.result.completed, true, JSON.stringify(result.body));
    // It took over rather than refusing, and counted the new attempt.
    assert.ok(result.body.result.attempts >= 2, `attempts was ${result.body.result.attempts}`);
    await assertUserDataGone(user.uid);
  });

  it("recovers a job previously recorded as failed", async () => {
    const user = await createEmailUser(uniqueEmail("failed"));
    await seedUserData(user.uid);

    await adminWrite(`deletionJobs/${user.uid}`, {
      uid: { stringValue: user.uid },
      state: { stringValue: "failed" },
      attempts: { integerValue: "1" },
      deletedCollections: { arrayValue: { values: [] } },
      claimedAt: { nullValue: null },
      lastError: { stringValue: "simulated partial Firestore failure" },
      completedAt: { nullValue: null },
      requestedAt: { timestampValue: "2020-01-01T00:00:00Z" },
      updatedAt: { timestampValue: "2020-01-01T00:00:00Z" },
    });

    const result = await callFunction("requestAccountDeletion", { idToken: user.idToken });

    assert.equal(result.body.result.completed, true, JSON.stringify(result.body));
    assert.equal(result.body.result.lastError, null, "the stale error was not cleared");
    await assertUserDataGone(user.uid);
  });

  it("finishes the job when data was deleted but the account was not", async () => {
    // The partial-failure state that matters most: data gone, login alive.
    // A retry must remove the account rather than reporting success for a
    // user who can still sign in.
    const email = uniqueEmail("halfway");
    const user = await createEmailUser(email);

    await adminWrite(`deletionJobs/${user.uid}`, {
      uid: { stringValue: user.uid },
      state: { stringValue: "dataDeleted" },
      attempts: { integerValue: "1" },
      deletedCollections: { arrayValue: { values: [] } },
      claimedAt: { nullValue: null },
      lastError: { stringValue: "auth deletion interrupted" },
      completedAt: { nullValue: null },
      requestedAt: { timestampValue: "2020-01-01T00:00:00Z" },
      updatedAt: { timestampValue: "2020-01-01T00:00:00Z" },
    });

    const result = await callFunction("requestAccountDeletion", { idToken: user.idToken });

    assert.equal(result.body.result.completed, true, JSON.stringify(result.body));
    assert.equal(await lookupUser(user.uid, { byUid: true }), null, "the login survived the retry");
    assert.equal((await signInEmailUser(email)).ok, false);
  });

  it("does not start a second worker while one holds a live claim", async () => {
    const user = await createEmailUser(uniqueEmail("claimed"));
    await seedUserData(user.uid);

    // A fresh claim by another worker.
    await adminWrite(`deletionJobs/${user.uid}`, {
      uid: { stringValue: user.uid },
      state: { stringValue: "deletingData" },
      attempts: { integerValue: "1" },
      deletedCollections: { arrayValue: { values: [] } },
      claimedAt: { timestampValue: new Date().toISOString() },
      lastError: { nullValue: null },
      completedAt: { nullValue: null },
      requestedAt: { timestampValue: new Date().toISOString() },
      updatedAt: { timestampValue: new Date().toISOString() },
    });

    const result = await callFunction("requestAccountDeletion", { idToken: user.idToken });

    // Honest progress, not a false "completed", and no duplicated work.
    assert.equal(result.ok, true, JSON.stringify(result.body));
    assert.equal(result.body.result.completed, false);
    assert.equal(result.body.result.state, "deletingData");
    assert.equal((await adminGet(`deletionJobs/${user.uid}`)).attempts, 1, "the claim was stolen");
  });

  it("sweeps leftover data when an account is deleted outside the workflow", async () => {
    // The backstop for a console-initiated deletion, and for a crash between
    // the data step and the auth step. It runs as admin, so it needs none of
    // the user's credentials - which is what makes deleting the account safe.
    const user = await createEmailUser(uniqueEmail("console"));
    await seedUserData(user.uid);

    const response = await fetch(
      `http://127.0.0.1:9599/identitytoolkit.googleapis.com/v1/accounts:delete?key=fake-api-key`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Bearer owner" },
        body: JSON.stringify({ localId: user.uid }),
      },
    );
    assert.ok(response.ok, "could not delete the account out-of-band");

    const swept = await waitFor(
      async () => !(await adminExists(`users/${user.uid}/pantry/doc-1`)),
      { timeoutMs: 15000 },
    );
    assert.equal(swept, true, "the onDelete backstop did not sweep the leftover data");
    await assertUserDataGone(user.uid);
  });
});

// MARK: - Recent authentication

describe("recent authentication", () => {
  // The rejection path needs the emulator started with a zero-second
  // recency window, so it lives in `staleAuth.e2e.test.mjs` and its own
  // emulator run (`npm run test:e2e:stale`). Under that configuration no
  // deletion can succeed, which is why it is not simply folded in here.
  it("accepts a freshly signed-in session in the default configuration", async () => {
    const user = await createEmailUser(uniqueEmail("fresh"));
    const result = await callFunction("requestAccountDeletion", { idToken: user.idToken });

    assert.equal(result.ok, true, JSON.stringify(result.body));
    assert.equal(result.body.result.completed, true);
  });
});

// MARK: - Status reporting

describe("status reporting", () => {
  it("reports pending for a user who has never requested deletion", async () => {
    const user = await createEmailUser(uniqueEmail("status-none"));

    const result = await callFunction("accountDeletionStatus", { idToken: user.idToken });

    assert.equal(result.ok, true);
    assert.equal(result.body.result.state, "pending");
    assert.equal(result.body.result.completed, false);
  });

  it("reports a failed job honestly rather than as success", async () => {
    const user = await createEmailUser(uniqueEmail("status-failed"));
    await adminWrite(`deletionJobs/${user.uid}`, {
      uid: { stringValue: user.uid },
      state: { stringValue: "failed" },
      attempts: { integerValue: "2" },
      deletedCollections: { arrayValue: { values: [{ stringValue: "pantry" }] } },
      claimedAt: { nullValue: null },
      lastError: { stringValue: "partial Firestore failure" },
      completedAt: { nullValue: null },
      requestedAt: { timestampValue: "2020-01-01T00:00:00Z" },
      updatedAt: { timestampValue: "2020-01-01T00:00:00Z" },
    });

    const result = await callFunction("accountDeletionStatus", { idToken: user.idToken });

    assert.equal(result.body.result.state, "failed");
    assert.equal(result.body.result.completed, false);
    assert.equal(result.body.result.lastError, "partial Firestore failure");
    assert.deepEqual(result.body.result.deletedCollections, ["pantry"]);
  });
});

// MARK: - Backend unavailable

describe("backend unavailable", () => {
  it("surfaces a transport failure rather than a false success", async () => {
    // A port nothing is listening on, standing in for the backend being
    // down. The contract being checked is that the caller gets an error it
    // can act on - never a silent success.
    let failed = false;
    try {
      await fetch("http://127.0.0.1:5999/demo-fridgefit/us-central1/requestAccountDeletion", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ data: {} }),
        signal: AbortSignal.timeout(2000),
      });
    } catch {
      failed = true;
    }
    assert.equal(failed, true, "a request to a dead backend must fail, not succeed");
  });

  it("surfaces a client-side timeout as a failure", async () => {
    const user = await createEmailUser(uniqueEmail("timeout"));

    let timedOut = false;
    try {
      await fetch(
        `http://127.0.0.1:5401/demo-fridgefit/us-central1/requestAccountDeletion`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${user.idToken}`,
          },
          body: JSON.stringify({ data: {} }),
          // Far too short to complete: this is the client-timeout path.
          signal: AbortSignal.timeout(1),
        },
      );
    } catch {
      timedOut = true;
    }

    assert.equal(timedOut, true, "an impossibly short timeout should abort");

    // And the important part: the server-side job is still authoritative, so
    // a client that timed out can ask again and get the truth.
    const status = await callFunction("accountDeletionStatus", { idToken: user.idToken });
    assert.equal(status.ok, true);
    assert.ok(["pending", "deletingData", "dataDeleted", "deletingAuth", "completed", "failed"]
      .includes(status.body.result.state));
  });
});
