//
// Shared harness for the FridgeFit account-deletion end-to-end tests.
//
// ## Emulator only — never production
//
// Every client here is pointed at 127.0.0.1 emulator ports, and the project
// id is `demo-fridgefit`. The `demo-` prefix is not cosmetic: firebase-tools
// treats such a project as a **demo project**, refuses to contact Google
// servers for it, and requires no credentials. A misconfiguration therefore
// fails loudly rather than quietly reaching the real `fridgefit-app`
// project. `assertEmulatorOnly()` below re-checks this at run time, and
// `noProductionAccess.test.mjs` asserts it as a test in its own right.
//

import { strict as assert } from "node:assert";

export const PROJECT_ID = "demo-fridgefit";
export const AUTH_HOST = "127.0.0.1:9599";
export const FIRESTORE_HOST = "127.0.0.1:8575";
export const FUNCTIONS_HOST = "127.0.0.1:5401";
export const REGION = "us-central1";

/** The real project, which must never be touched by these tests. */
export const PRODUCTION_PROJECT_ID = "fridgefit-app";

/**
 * Fails fast if anything is pointed somewhere other than the local
 * emulators.
 */
export function assertEmulatorOnly() {
  assert.notEqual(PROJECT_ID, PRODUCTION_PROJECT_ID, "tests must not use the production project");
  assert.ok(PROJECT_ID.startsWith("demo-"), "project id must be a demo- project");
  for (const host of [AUTH_HOST, FIRESTORE_HOST, FUNCTIONS_HOST]) {
    assert.ok(
      host.startsWith("127.0.0.1:"),
      `${host} is not a loopback emulator address`,
    );
  }
}

// MARK: - Auth emulator

/**
 * Creates a user in the Auth emulator and returns a freshly minted ID token.
 *
 * Uses the emulator's Identity Toolkit REST surface directly rather than a
 * client SDK: it is the documented interface, it needs no bundler, and it
 * lets a test control exactly when a sign-in happens (which matters for the
 * recent-auth checks).
 */
export async function createEmailUser(email, password = "test-password-123") {
  const response = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = await response.json();
  assert.ok(response.ok, `sign-up failed: ${JSON.stringify(body)}`);
  return { uid: body.localId, idToken: body.idToken, refreshToken: body.refreshToken, email };
}

/** Signs an existing user in again, producing a token with a fresh auth_time. */
export async function signInEmailUser(email, password = "test-password-123") {
  const response = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = await response.json();
  return { ok: response.ok, body };
}

/**
 * Signs in with a **Google** credential, through the emulator's
 * sign-in-with-IdP endpoint.
 *
 * This is the supported emulator strategy for federated providers: the
 * emulator accepts an unsigned JSON assertion in place of a real Google ID
 * token, so a test can exercise the `google.com` provider end to end without
 * contacting Google, embedding OAuth secrets, or driving a browser. The
 * resulting account carries `providerId: google.com`, which is what the
 * client's provider-aware reauthentication branches on.
 */
export async function signInWithGoogle(email, sub = `google-${email}`) {
  const response = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        postBody: new URLSearchParams({
          id_token: JSON.stringify({ sub, email, email_verified: true }),
          providerId: "google.com",
        }).toString(),
        requestUri: "http://localhost",
        returnSecureToken: true,
      }),
    },
  );
  const body = await response.json();
  assert.ok(response.ok, `Google sign-in failed: ${JSON.stringify(body)}`);
  return {
    uid: body.localId,
    idToken: body.idToken,
    email,
    providerId: body.providerId ?? "google.com",
  };
}

/** Looks an account up by uid. `null` when it does not exist. */
export async function lookupUser(idTokenOrUid, { byUid = false } = {}) {
  const payload = byUid ? { localId: [idTokenOrUid] } : { idToken: idTokenOrUid };
  const response = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:lookup?key=fake-api-key`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer owner",
      },
      body: JSON.stringify(payload),
    },
  );
  if (!response.ok) return null;
  const body = await response.json();
  return body.users?.[0] ?? null;
}

// MARK: - Callable functions

/**
 * Invokes a callable function over its documented HTTPS protocol.
 *
 * Deliberately raw `fetch` rather than the Functions client SDK, because
 * this is the exact wire format the iOS app uses
 * (`CallableAccountDeletionClient` posts the same shape), so these tests
 * exercise the same contract the app depends on.
 */
export async function callFunction(name, { idToken, data = {} } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;

  const response = await fetch(
    `http://${FUNCTIONS_HOST}/${PROJECT_ID}/${REGION}/${name}`,
    { method: "POST", headers, body: JSON.stringify({ data }) },
  );

  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { raw: text };
  }
  return { status: response.status, ok: response.ok, body };
}

// MARK: - Firestore (admin REST, bypassing rules)

const FIRESTORE_BASE =
  `http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

/** Writes a document as an administrator, bypassing security rules. */
export async function adminWrite(path, fields = { seeded: { booleanValue: true } }) {
  const response = await fetch(`${FIRESTORE_BASE}/${path}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", Authorization: "Bearer owner" },
    body: JSON.stringify({ fields }),
  });
  assert.ok(response.ok, `admin write to ${path} failed: ${await response.text()}`);
}

/** True when a document exists. Administrative read, bypassing rules. */
export async function adminExists(path) {
  const response = await fetch(`${FIRESTORE_BASE}/${path}`, {
    headers: { Authorization: "Bearer owner" },
  });
  return response.status === 200;
}

/** Document ids in a collection. Administrative read. */
export async function adminList(path) {
  const response = await fetch(`${FIRESTORE_BASE}/${path}?pageSize=300`, {
    headers: { Authorization: "Bearer owner" },
  });
  if (!response.ok) return [];
  const body = await response.json();
  return (body.documents ?? []).map((d) => d.name.split("/").pop());
}

/** Reads a document's decoded fields, or `null`. Administrative read. */
export async function adminGet(path) {
  const response = await fetch(`${FIRESTORE_BASE}/${path}`, {
    headers: { Authorization: "Bearer owner" },
  });
  if (!response.ok) return null;
  const body = await response.json();
  const out = {};
  for (const [key, value] of Object.entries(body.fields ?? {})) {
    out[key] = decodeValue(value);
  }
  return out;
}

function decodeValue(value) {
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("booleanValue" in value) return value.booleanValue;
  if ("nullValue" in value) return null;
  if ("timestampValue" in value) return value.timestampValue;
  if ("arrayValue" in value) return (value.arrayValue.values ?? []).map(decodeValue);
  if ("mapValue" in value) {
    const out = {};
    for (const [k, v] of Object.entries(value.mapValue.fields ?? {})) out[k] = decodeValue(v);
    return out;
  }
  return value;
}

/** Wipes all Firestore data between tests. */
export async function clearFirestore() {
  const response = await fetch(
    `http://${FIRESTORE_HOST}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  assert.ok(response.ok, "failed to clear the Firestore emulator");
}

/** Deletes every account between tests. */
export async function clearAuth() {
  await fetch(
    `http://${AUTH_HOST}/emulator/v1/projects/${PROJECT_ID}/accounts`,
    { method: "DELETE", headers: { Authorization: "Bearer owner" } },
  );
}

// MARK: - Seeding

/**
 * Every collection one FridgeFit user owns, including the five FridgeFunds
 * collections and the nested WebRTC candidate subcollections that a
 * non-recursive delete would strand.
 */
export const SEEDED_COLLECTIONS = [
  "pantry",
  "inventoryEvents",
  "savedRecipes",
  "devices",
  "fundsBudget",
  "fundsSpends",
  "fundsWaste",
  "fundsItemPrices",
  "fundsPriceBook",
];

export const SESSION_ID = "session-1";
export const CANDIDATE_COLLECTIONS = ["callerCandidates", "calleeCandidates"];

/** Fills a user's subtree with one document per collection, plus nesting. */
export async function seedUserData(uid) {
  for (const collection of SEEDED_COLLECTIONS) {
    await adminWrite(`users/${uid}/${collection}/doc-1`, {
      owner: { stringValue: uid },
    });
  }
  await adminWrite(`users/${uid}/webrtcSessions/${SESSION_ID}`, {
    owner: { stringValue: uid },
  });
  for (const candidates of CANDIDATE_COLLECTIONS) {
    await adminWrite(`users/${uid}/webrtcSessions/${SESSION_ID}/${candidates}/candidate-1`, {
      owner: { stringValue: uid },
    });
  }
}

/** Every path seeded by `seedUserData`, for exhaustive assertions. */
export function seededPaths(uid) {
  return [
    ...SEEDED_COLLECTIONS.map((c) => `users/${uid}/${c}/doc-1`),
    `users/${uid}/webrtcSessions/${SESSION_ID}`,
    ...CANDIDATE_COLLECTIONS.map(
      (c) => `users/${uid}/webrtcSessions/${SESSION_ID}/${c}/candidate-1`,
    ),
  ];
}

/** Waits for `predicate` to hold, polling. Returns false on timeout. */
export async function waitFor(predicate, { timeoutMs = 8000, intervalMs = 100 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return true;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return false;
}
