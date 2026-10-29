/**
 * The shape of one FridgeFit user's data in Firestore.
 *
 * This is the server's copy of the list that `FirestoreAccountDataDeleter`
 * keeps on the client and that `firestore.rules` declares. All three must
 * agree, or a collection the app writes will survive "delete my account".
 * `deletionPaths.test.mjs` parses `firestore.rules` and fails if this list
 * drifts from it.
 */

/**
 * Per-user collections whose documents own no subcollections, so deleting
 * the documents is the whole job.
 */
export const FLAT_USER_COLLECTIONS = [
  "pantry",
  "inventoryEvents",
  "savedRecipes",
  "devices",
  // The five FridgeFunds collections.
  "fundsBudget",
  "fundsSpends",
  "fundsWaste",
  "fundsItemPrices",
  "fundsPriceBook",
] as const;

/**
 * Handled separately, because its documents own subcollections.
 *
 * Deleting a Firestore *document* does not delete its subcollections: the
 * document disappears from queries and its children carry on existing as
 * orphans at a path whose parent is gone. `recursiveDelete` handles this
 * correctly, which is one of the main reasons the server-side path exists.
 */
export const SESSION_COLLECTION = "webrtcSessions";

/**
 * The subcollections a `webrtcSessions` document owns. Matches
 * `SignalingRole.candidateCollectionName` in the iOS app and the
 * candidate-collection allowlist in `firestore.rules`.
 */
export const CANDIDATE_COLLECTIONS = ["callerCandidates", "calleeCandidates"] as const;

/** Every per-user collection, for progress tracking and verification. */
export const ALL_USER_COLLECTIONS: readonly string[] = [
  ...FLAT_USER_COLLECTIONS,
  SESSION_COLLECTION,
];

/**
 * Where a deletion job's durable state lives.
 *
 * Top-level rather than under `users/{uid}`, deliberately: it has to outlive
 * everything beneath `users/{uid}`, including the parent document, and it
 * must not be deletable by the thing it is tracking.
 */
export const deletionJobPath = (uid: string): string => `deletionJobs/${uid}`;

/**
 * Presence of this document makes `firestore.rules` reject every write the
 * user makes to their own subtree, so new data cannot appear behind an
 * in-flight deletion.
 *
 * Separate from the job document because the rules need the cheapest
 * possible check - a single `exists()` - on the write path of every
 * document in the app.
 */
export const deletionLockPath = (uid: string): string => `deletionLocks/${uid}`;

/** The user's root document. */
export const userDocumentPath = (uid: string): string => `users/${uid}`;
