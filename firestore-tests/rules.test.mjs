//
//  rules.test.mjs
//  FridgeFit — Firestore security rules tests
//
// Runs ../firestore.rules against the Firestore emulator. No live project is
// touched. Start with:
//
//     cd firestore-tests && npm test
//
// Every path asserted here is one the app actually uses; see the path list at
// the top of ../firestore.rules.

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";

const ALICE = "alice-uid";
const BOB = "bob-uid";
const DEVICE_A = "device-a";
const DEVICE_B = "device-b";
const SESSION = "session-1";

let testEnv;

/** Firestore handle for a signed-in user. */
const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
/** Firestore handle for a signed-out caller. */
const asAnonymous = () => testEnv.unauthenticatedContext().firestore();

const devicePath = (uid, deviceId) => `users/${uid}/devices/${deviceId}`;
const sessionPath = (uid, sessionId) => `users/${uid}/webrtcSessions/${sessionId}`;
const candidatesPath = (uid, sessionId, role) =>
  `${sessionPath(uid, sessionId)}/${role}`;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "fridgefit-rules-test",
    firestore: {
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  // Seed through the rules-bypassing context so "can Bob read Alice's data"
  // tests are about reading, not about whether the data exists.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, devicePath(ALICE, DEVICE_A)), {
      deviceId: DEVICE_A,
      deviceName: "Kitchen iPhone",
      deviceRole: "camera",
      connectionStatus: "available",
    });
    await setDoc(doc(db, sessionPath(ALICE, SESSION)), {
      callerDeviceId: DEVICE_B,
      calleeDeviceId: DEVICE_A,
      state: "offering",
    });
    await setDoc(
      doc(db, candidatesPath(ALICE, SESSION, "callerCandidates"), "candidate-1"),
      { candidate: "candidate:1 1 udp 2130706431 192.168.1.9 50000 typ host", sdpMLineIndex: 0 }
    );
  });
});

// ---------------------------------------------------------------------------
// Device registry — users/{uid}/devices/{deviceId}
// ---------------------------------------------------------------------------

describe("device registry", () => {
  it("lets a user register their own device", async () => {
    const db = asUser(ALICE);
    await assertSucceeds(
      setDoc(doc(db, devicePath(ALICE, DEVICE_B)), {
        deviceId: DEVICE_B,
        deviceName: "Pocket iPhone",
        deviceRole: "controller",
        connectionStatus: "available",
        lastSeenAt: serverTimestamp(),
        createdAt: serverTimestamp(),
      })
    );
  });

  it("lets a user read back their own device", async () => {
    await assertSucceeds(getDoc(doc(asUser(ALICE), devicePath(ALICE, DEVICE_A))));
  });

  it("lets a user list their own devices (this is discovery)", async () => {
    await assertSucceeds(getDocs(collection(asUser(ALICE), `users/${ALICE}/devices`)));
  });

  it("lets a user update their own heartbeat", async () => {
    const db = asUser(ALICE);
    await assertSucceeds(
      updateDoc(doc(db, devicePath(ALICE, DEVICE_A)), {
        lastSeenAt: serverTimestamp(),
        connectionStatus: "connected",
      })
    );
  });

  it("lets a user re-register an existing device with merge", async () => {
    const db = asUser(ALICE);
    await assertSucceeds(
      setDoc(
        doc(db, devicePath(ALICE, DEVICE_A)),
        { lastSeenAt: serverTimestamp(), deviceRole: "controller" },
        { merge: true }
      )
    );
  });

  it("lets a user delete their own device", async () => {
    await assertSucceeds(deleteDoc(doc(asUser(ALICE), devicePath(ALICE, DEVICE_A))));
  });

  it("denies reading another user's device", async () => {
    await assertFails(getDoc(doc(asUser(BOB), devicePath(ALICE, DEVICE_A))));
  });

  it("denies listing another user's devices", async () => {
    await assertFails(getDocs(collection(asUser(BOB), `users/${ALICE}/devices`)));
  });

  it("denies writing into another user's device registry", async () => {
    await assertFails(
      setDoc(doc(asUser(BOB), devicePath(ALICE, "intruder")), { deviceName: "Nope" })
    );
  });

  it("denies deleting another user's device", async () => {
    await assertFails(deleteDoc(doc(asUser(BOB), devicePath(ALICE, DEVICE_A))));
  });

  it("denies unauthenticated reads", async () => {
    await assertFails(getDoc(doc(asAnonymous(), devicePath(ALICE, DEVICE_A))));
  });

  it("denies unauthenticated writes", async () => {
    await assertFails(
      setDoc(doc(asAnonymous(), devicePath(ALICE, "anon")), { deviceName: "Nope" })
    );
  });
});

// ---------------------------------------------------------------------------
// WebRTC sessions — users/{uid}/webrtcSessions/{sessionId}
// ---------------------------------------------------------------------------

describe("webrtc sessions", () => {
  it("lets the controller create a session", async () => {
    const db = asUser(ALICE);
    await assertSucceeds(
      setDoc(doc(db, sessionPath(ALICE, "session-2")), {
        callerDeviceId: DEVICE_B,
        callerDeviceName: "Pocket iPhone",
        calleeDeviceId: DEVICE_A,
        calleeDeviceName: "Kitchen iPhone",
        state: "creating",
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 120_000),
      })
    );
  });

  it("lets the controller write an SDP offer", async () => {
    const db = asUser(ALICE);
    await assertSucceeds(
      updateDoc(doc(db, sessionPath(ALICE, SESSION)), {
        offer: { type: "offer", sdp: "v=0\r\n" },
        state: "offering",
      })
    );
  });

  it("lets the camera read the SDP offer", async () => {
    await assertSucceeds(getDoc(doc(asUser(ALICE), sessionPath(ALICE, SESSION))));
  });

  it("lets the camera write an SDP answer", async () => {
    const db = asUser(ALICE);
    await assertSucceeds(
      updateDoc(doc(db, sessionPath(ALICE, SESSION)), {
        answer: { type: "answer", sdp: "v=0\r\n" },
        state: "answering",
      })
    );
  });

  it("lets a camera query for sessions addressed to it", async () => {
    const db = asUser(ALICE);
    await assertSucceeds(
      getDocs(
        query(
          collection(db, `users/${ALICE}/webrtcSessions`),
          where("calleeDeviceId", "==", DEVICE_A)
        )
      )
    );
  });

  it("lets the controller sweep expired sessions", async () => {
    const db = asUser(ALICE);
    await assertSucceeds(
      getDocs(
        query(
          collection(db, `users/${ALICE}/webrtcSessions`),
          where("expiresAt", "<", new Date())
        )
      )
    );
  });

  it("lets a user delete their own session", async () => {
    await assertSucceeds(deleteDoc(doc(asUser(ALICE), sessionPath(ALICE, SESSION))));
  });

  it("denies reading another user's session", async () => {
    await assertFails(getDoc(doc(asUser(BOB), sessionPath(ALICE, SESSION))));
  });

  it("denies querying another user's sessions", async () => {
    await assertFails(
      getDocs(
        query(
          collection(asUser(BOB), `users/${ALICE}/webrtcSessions`),
          where("calleeDeviceId", "==", DEVICE_A)
        )
      )
    );
  });

  it("denies injecting an offer into another user's session", async () => {
    await assertFails(
      updateDoc(doc(asUser(BOB), sessionPath(ALICE, SESSION)), {
        offer: { type: "offer", sdp: "hijack" },
      })
    );
  });

  it("denies unauthenticated session access", async () => {
    await assertFails(getDoc(doc(asAnonymous(), sessionPath(ALICE, SESSION))));
  });
});

// ---------------------------------------------------------------------------
// ICE candidates — the subcollections a parent rule does NOT cover
// ---------------------------------------------------------------------------

describe("ICE candidate subcollections", () => {
  for (const role of ["callerCandidates", "calleeCandidates"]) {
    it(`lets a user append to their own ${role}`, async () => {
      const db = asUser(ALICE);
      await assertSucceeds(
        addDoc(collection(db, candidatesPath(ALICE, SESSION, role)), {
          candidate: "candidate:2 1 udp 2130706431 192.168.1.10 50001 typ host",
          sdpMid: "0",
          sdpMLineIndex: 0,
        })
      );
    });

    it(`lets a user list their own ${role} (this is the ICE listener)`, async () => {
      await assertSucceeds(
        getDocs(collection(asUser(ALICE), candidatesPath(ALICE, SESSION, role)))
      );
    });

    it(`denies another user reading ${role}`, async () => {
      await assertFails(
        getDocs(collection(asUser(BOB), candidatesPath(ALICE, SESSION, role)))
      );
    });

    it(`denies another user writing ${role}`, async () => {
      await assertFails(
        addDoc(collection(asUser(BOB), candidatesPath(ALICE, SESSION, role)), {
          candidate: "hijack",
          sdpMLineIndex: 0,
        })
      );
    });

    it(`denies unauthenticated access to ${role}`, async () => {
      await assertFails(
        getDocs(collection(asAnonymous(), candidatesPath(ALICE, SESSION, role)))
      );
    });
  }

  it("lets a user delete a candidate during session cleanup", async () => {
    await assertSucceeds(
      deleteDoc(
        doc(asUser(ALICE), candidatesPath(ALICE, SESSION, "callerCandidates"), "candidate-1")
      )
    );
  });

  it("denies an unrelated subcollection under a session", async () => {
    // The rule names the two candidate collections rather than using a
    // recursive wildcard, so nothing else under a session is writable.
    await assertFails(
      addDoc(collection(asUser(ALICE), `${sessionPath(ALICE, SESSION)}/videoFrames`), {
        blob: "x",
      })
    );
  });
});

// ---------------------------------------------------------------------------
// Pre-existing functionality must keep working
// ---------------------------------------------------------------------------

describe("pantry (pre-existing)", () => {
  const pantryPath = (uid, id) => `users/${uid}/pantry/${id}`;

  it("lets a user write their own pantry item", async () => {
    await assertSucceeds(
      setDoc(doc(asUser(ALICE), pantryPath(ALICE, "item-1")), {
        ingredientName: "Chicken",
        ingredientCategory: "meat",
        quantity: 400,
        unit: "grams",
      })
    );
  });

  it("lets a user list their own pantry", async () => {
    await assertSucceeds(getDocs(collection(asUser(ALICE), `users/${ALICE}/pantry`)));
  });

  it("denies reading another user's pantry", async () => {
    await assertFails(getDoc(doc(asUser(BOB), pantryPath(ALICE, "item-1"))));
  });

  it("denies unauthenticated pantry access", async () => {
    await assertFails(getDoc(doc(asAnonymous(), pantryPath(ALICE, "item-1"))));
  });
});

// ---------------------------------------------------------------------------
// Kitchen activity history — users/{uid}/inventoryEvents/{eventId}
// ---------------------------------------------------------------------------

describe("inventory events", () => {
  const eventPath = (uid, id) => `users/${uid}/inventoryEvents/${id}`;
  const sampleEvent = {
    pantryItemId: "11111111-1111-1111-1111-111111111111",
    itemName: "Milk",
    kind: "used",
    note: "Used 200 ml",
    date: new Date("2026-06-15T09:00:00Z"),
  };

  it("lets a user append their own activity event", async () => {
    await assertSucceeds(
      setDoc(doc(asUser(ALICE), eventPath(ALICE, "event-1")), sampleEvent)
    );
  });

  it("lets a user read their own activity history", async () => {
    await assertSucceeds(
      getDocs(collection(asUser(ALICE), `users/${ALICE}/inventoryEvents`))
    );
  });

  it("lets a user delete their own event, which is what undo does", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), eventPath(ALICE, "event-1")), sampleEvent);
    });

    await assertSucceeds(deleteDoc(doc(asUser(ALICE), eventPath(ALICE, "event-1"))));
  });

  it("denies reading another user's activity history", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), eventPath(ALICE, "event-1")), sampleEvent);
    });

    await assertFails(getDoc(doc(asUser(BOB), eventPath(ALICE, "event-1"))));
    await assertFails(getDocs(collection(asUser(BOB), `users/${ALICE}/inventoryEvents`)));
  });

  it("denies writing into another user's activity history", async () => {
    await assertFails(
      setDoc(doc(asUser(BOB), eventPath(ALICE, "event-2")), sampleEvent)
    );
  });

  it("denies deleting another user's event", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), eventPath(ALICE, "event-1")), sampleEvent);
    });

    await assertFails(deleteDoc(doc(asUser(BOB), eventPath(ALICE, "event-1"))));
  });

  it("denies unauthenticated access to activity history", async () => {
    await assertFails(getDoc(doc(asAnonymous(), eventPath(ALICE, "event-1"))));
    await assertFails(
      setDoc(doc(asAnonymous(), eventPath(ALICE, "event-3")), sampleEvent)
    );
  });

  it("does not open a subcollection beneath an event", async () => {
    // Nothing nests under an event; the grant stops at the document.
    await assertFails(
      setDoc(doc(asUser(ALICE), `${eventPath(ALICE, "event-1")}/extra/doc-1`), { a: 1 })
    );
  });
});

// ---------------------------------------------------------------------------
// Recipes saved from Discover — users/{uid}/savedRecipes/{recipeId}
// ---------------------------------------------------------------------------

describe("saved recipes", () => {
  // Matches FirestoreSavedRecipeRepository.encode: the Recipe travels as one
  // JSON string, with title and sourceRecipeID beside it for reference and
  // savedAt for the ordered query the Recipes tab runs.
  const RECIPE_ID = "00000000-0000-4000-8000-00000000a1b2";
  const savedRecipePath = (uid, recipeId) => `users/${uid}/savedRecipes/${recipeId}`;
  const sampleSavedRecipe = {
    title: "Tomato Pasta",
    sourceRecipeID: 41394,
    recipeJSON: JSON.stringify({
      id: RECIPE_ID,
      title: "Tomato Pasta",
      summary: "Saved from Discover, via Spoonacular.",
      ingredients: [],
      instructions: ["Boil the pasta."],
    }),
    savedAt: serverTimestamp(),
  };

  it("lets a user save a recipe of their own", async () => {
    await assertSucceeds(
      setDoc(doc(asUser(ALICE), savedRecipePath(ALICE, RECIPE_ID)), sampleSavedRecipe)
    );
  });

  it("lets a user overwrite the same recipe, which is what re-saving does", async () => {
    await assertSucceeds(
      setDoc(doc(asUser(ALICE), savedRecipePath(ALICE, RECIPE_ID)), sampleSavedRecipe)
    );
    await assertSucceeds(
      setDoc(doc(asUser(ALICE), savedRecipePath(ALICE, RECIPE_ID)), sampleSavedRecipe)
    );
  });

  it("lets a user read back a saved recipe", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), savedRecipePath(ALICE, RECIPE_ID)),
        { ...sampleSavedRecipe, savedAt: new Date() }
      );
    });

    await assertSucceeds(getDoc(doc(asUser(ALICE), savedRecipePath(ALICE, RECIPE_ID))));
  });

  it("lets a user run the ordered list query the Recipes tab uses", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), savedRecipePath(ALICE, RECIPE_ID)),
        { ...sampleSavedRecipe, savedAt: new Date() }
      );
    });

    await assertSucceeds(
      getDocs(
        query(
          collection(asUser(ALICE), `users/${ALICE}/savedRecipes`),
          orderBy("savedAt", "desc")
        )
      )
    );
  });

  it("lets a user remove their own saved recipe", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), savedRecipePath(ALICE, RECIPE_ID)),
        { ...sampleSavedRecipe, savedAt: new Date() }
      );
    });

    await assertSucceeds(deleteDoc(doc(asUser(ALICE), savedRecipePath(ALICE, RECIPE_ID))));
  });

  it("denies reading another user's saved recipes", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), savedRecipePath(ALICE, RECIPE_ID)),
        { ...sampleSavedRecipe, savedAt: new Date() }
      );
    });

    await assertFails(getDoc(doc(asUser(BOB), savedRecipePath(ALICE, RECIPE_ID))));
    await assertFails(getDocs(collection(asUser(BOB), `users/${ALICE}/savedRecipes`)));
  });

  it("denies writing into another user's saved recipes", async () => {
    await assertFails(
      setDoc(doc(asUser(BOB), savedRecipePath(ALICE, RECIPE_ID)), sampleSavedRecipe)
    );
  });

  it("denies deleting another user's saved recipe", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), savedRecipePath(ALICE, RECIPE_ID)),
        { ...sampleSavedRecipe, savedAt: new Date() }
      );
    });

    await assertFails(deleteDoc(doc(asUser(BOB), savedRecipePath(ALICE, RECIPE_ID))));
  });

  it("denies unauthenticated access to saved recipes", async () => {
    await assertFails(getDoc(doc(asAnonymous(), savedRecipePath(ALICE, RECIPE_ID))));
    await assertFails(
      setDoc(doc(asAnonymous(), savedRecipePath(ALICE, RECIPE_ID)), sampleSavedRecipe)
    );
  });

  it("does not open a subcollection beneath a saved recipe", async () => {
    // Nothing nests under a saved recipe; the grant stops at the document.
    await assertFails(
      setDoc(
        doc(asUser(ALICE), `${savedRecipePath(ALICE, RECIPE_ID)}/extra/doc-1`),
        { a: 1 }
      )
    );
  });
});

// ---------------------------------------------------------------------------
// Default deny
// ---------------------------------------------------------------------------

describe("default deny", () => {
  it("denies an unmatched top-level collection", async () => {
    await assertFails(setDoc(doc(asUser(ALICE), "someOtherCollection/doc-1"), { a: 1 }));
  });

  it("denies writing the user document itself", async () => {
    // Nothing in the app writes users/{uid}, so it stays closed.
    await assertFails(setDoc(doc(asUser(ALICE), `users/${ALICE}`), { a: 1 }));
  });

  it("denies an unmatched subcollection under the user", async () => {
    await assertFails(setDoc(doc(asUser(ALICE), `users/${ALICE}/secrets/doc-1`), { a: 1 }));
  });
});

// FridgeFunds (Budget tab): budget, spends, waste and item prices all sit under
// the user next to the pantry, same own-data-only rule.
describe("FridgeFunds", () => {
  const fundsDocs = [
    ["fundsBudget", "current", { limitAmount: "120", currency: "AUD", cadence: "weekly" }],
    ["fundsSpends", "spend-1", { amount: "35", currency: "AUD", store: "Coles" }],
    ["fundsWaste", "waste-1", { lostAmount: "2.25", currency: "AUD", reason: "expired" }],
    ["fundsItemPrices", "pantry-item-1", { unitCost: "0.5", currency: "AUD" }],
  ];

  for (const [col, id, data] of fundsDocs) {
    it(`lets a user write and read their own ${col}`, async () => {
      const db = asUser(ALICE);
      await assertSucceeds(setDoc(doc(db, `users/${ALICE}/${col}/${id}`), data));
      await assertSucceeds(getDoc(doc(db, `users/${ALICE}/${col}/${id}`)));
      await assertSucceeds(getDocs(collection(db, `users/${ALICE}/${col}`)));
    });

    it(`denies another user's ${col}`, async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), `users/${ALICE}/${col}/${id}`), data);
      });
      const db = asUser(BOB);
      await assertFails(getDoc(doc(db, `users/${ALICE}/${col}/${id}`)));
      await assertFails(setDoc(doc(db, `users/${ALICE}/${col}/${id}`), data));
    });

    it(`denies signed-out access to ${col}`, async () => {
      await assertFails(getDoc(doc(asAnonymous(), `users/${ALICE}/${col}/${id}`)));
    });
  }

  // the rule lists the four names on purpose - it isn't a free-for-all under users/{uid}
  it("denies a collection name FridgeFunds doesn't use", async () => {
    await assertFails(setDoc(doc(asUser(ALICE), `users/${ALICE}/fundsAnythingElse/x`), { a: 1 }));
  });
});
