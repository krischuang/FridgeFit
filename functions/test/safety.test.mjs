//
// Guard rails that do not need an emulator.
//
// Two jobs:
//
//  1. Prove the test suite cannot reach the production Firebase project.
//  2. Prove the server's collection list has not drifted from
//     `firestore.rules` or from the iOS client's list - a collection in one
//     and not the others would survive "delete my account" silently.
//

import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  ALL_USER_COLLECTIONS,
  CANDIDATE_COLLECTIONS,
  FLAT_USER_COLLECTIONS,
  SESSION_COLLECTION,
} from "../lib/paths.js";
import {
  AUTH_HOST,
  FIRESTORE_HOST,
  FUNCTIONS_HOST,
  PRODUCTION_PROJECT_ID,
  PROJECT_ID,
  SEEDED_COLLECTIONS,
  assertEmulatorOnly,
} from "./support/harness.mjs";

const repoRoot = new URL("../../", import.meta.url);
const read = (relative) => readFileSync(new URL(relative, repoRoot), "utf8");

describe("no production access", () => {
  it("uses a demo project, which firebase-tools refuses to take online", () => {
    assert.ok(PROJECT_ID.startsWith("demo-"));
    assert.notEqual(PROJECT_ID, PRODUCTION_PROJECT_ID);
  });

  it("points every client at a loopback emulator port", () => {
    for (const host of [AUTH_HOST, FIRESTORE_HOST, FUNCTIONS_HOST]) {
      assert.ok(host.startsWith("127.0.0.1:"), `${host} is not loopback`);
    }
    assert.doesNotThrow(assertEmulatorOnly);
  });

  it("never names the production project anywhere in the test sources", () => {
    for (const file of ["functions/test/deletion.e2e.test.mjs", "functions/test/support/harness.mjs"]) {
      const source = read(file);
      const mentions = source.split(PRODUCTION_PROJECT_ID).length - 1;
      // `harness.mjs` names it once, only to assert it is never used.
      assert.ok(
        mentions === 0 || file.endsWith("harness.mjs"),
        `${file} references the production project`,
      );
    }
  });

  it("the emulator run script pins the demo project", () => {
    const pkg = JSON.parse(read("functions/package.json"));
    for (const [name, script] of Object.entries(pkg.scripts)) {
      if (!script.includes("firebase emulators")) continue;
      assert.ok(
        script.includes("--project demo-fridgefit"),
        `script "${name}" does not pin the demo project`,
      );
    }
  });
});

describe("deletion path coverage", () => {
  const rules = read("firestore.rules");

  /** Collection names appearing as `users/{uid}/<name>/` in a match path. */
  const declaredInRules = new Set(
    [...rules.matchAll(/match \/users\/\{uid\}\/([A-Za-z]+)\//g)].map((m) => m[1]),
  );

  // Wildcard variables in the rules, not real collection names.
  const wildcards = new Set(["fundsCollection", "candidateCollection"]);

  it("parsed something, so an empty result cannot pass by accident", () => {
    assert.ok(declaredInRules.size > 0, "the rules parse found no collections");
  });

  it("covers every per-user collection the rules declare", () => {
    const covered = new Set(ALL_USER_COLLECTIONS);
    const missing = [...declaredInRules].filter((c) => !covered.has(c) && !wildcards.has(c));

    assert.deepEqual(
      missing,
      [],
      `these collections are in firestore.rules but the server would not delete them: ${missing}`,
    );
  });

  it("includes all five FridgeFunds collections", () => {
    const funds = FLAT_USER_COLLECTIONS.filter((c) => c.startsWith("funds"));
    assert.deepEqual(
      [...funds].sort(),
      ["fundsBudget", "fundsItemPrices", "fundsPriceBook", "fundsSpends", "fundsWaste"],
      "the FridgeFunds collection list has drifted",
    );
  });

  it("handles webrtcSessions recursively rather than as a flat collection", () => {
    assert.ok(
      !FLAT_USER_COLLECTIONS.includes(SESSION_COLLECTION),
      "webrtcSessions must not be treated as flat - its documents own subcollections",
    );
    assert.ok(ALL_USER_COLLECTIONS.includes(SESSION_COLLECTION));
  });

  it("names exactly the candidate subcollections the iOS app writes", () => {
    const swift = read("FridgeFit/Domain/Models/RemoteCamera/WebRTCSignalingModels.swift");
    for (const collection of CANDIDATE_COLLECTIONS) {
      assert.ok(
        swift.includes(`"${collection}"`),
        `${collection} is not the name the app writes`,
      );
    }
  });

  it("agrees with the iOS client's own collection list", () => {
    // The client still performs a best-effort delete, so the two lists must
    // not diverge - a collection the client knows about and the server does
    // not would be deleted only when the client path runs.
    const swift = read("FridgeFit/Data/FirestoreAccountDataDeleter.swift");
    for (const collection of FLAT_USER_COLLECTIONS) {
      assert.ok(
        swift.includes(`"${collection}"`),
        `${collection} is missing from the iOS deleter`,
      );
    }
  });

  it("the test harness seeds every collection the server deletes", () => {
    // Otherwise the end-to-end tests would pass over collections that were
    // never populated, which proves nothing.
    for (const collection of FLAT_USER_COLLECTIONS) {
      assert.ok(
        SEEDED_COLLECTIONS.includes(collection),
        `${collection} is never seeded, so its deletion is untested`,
      );
    }
  });
});
