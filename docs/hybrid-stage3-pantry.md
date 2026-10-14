# Stage 3 — Confirmed Ingredients into the Pantry

Stage 2 ended with a local list of confirmed ingredients. Stage 3 writes them
to Firestore, through the pantry path that already existed.

- **Date:** 13 October 2026
- **Status:** implemented; **no physical-device testing**
- **Tests:** 680 passing, 4 expected skips, Debug and Release device builds clean

---

## 1. What was reused, and what was added

The pantry already had a complete write path, built for the receipt scanner:

```
AddDetectedIngredientsUseCase   batch, per-item outcomes, never aborts early
      └── AddPantryItemUseCase  validation, duplicate rule, one item
            └── PantryRepository ── FirestorePantryRepository
                                     users/{uid}/pantry/{itemId}
```

**None of it was rewritten.** `AddPantryItemUseCase`, `PantryRepository`,
`FirestorePantryRepository`, `PantryItem`, `Ingredient`, `IngredientCategory`
and `MeasurementUnit` are untouched. `AddDetectedIngredientsUseCase` gained one
overload and kept its existing behaviour.

### The one new domain type

`AddDetectedIngredientsUseCase.execute(drafts:)` took `[ReceiptItemDraft]`,
which cannot exist without a `ReceiptIngredientCandidate`. A recognised
ingredient has no receipt line, and fabricating an empty candidate to satisfy
the type would be a lie about where the data came from.

So `ConfirmedIngredientDraft` was added — a storage-shaped value with no
knowledge of its origin — and both paths now funnel through
`execute(confirmed:)`:

```swift
execute(drafts:)     // receipt scanner  ─┐
                                          ├─► execute(confirmed: [ConfirmedIngredientDraft])
IngredientReviewItem.pantryDraft         ─┘
```

The receipt path maps to the same type, so there is one implementation, one
set of per-item outcomes and one duplicate rule. `AddDetectedIngredientsUseCaseTests`
passes unchanged, which is the evidence the refactor preserved behaviour.

One subtlety worth recording: the original passed the *trimmed* name to
storage (so a blanked row fails validation) while using a fallback display
name only for reporting. Collapsing those two into one field would have
quietly stored the fallback instead. `ConfirmedIngredientDraft` keeps `name`
and `reportingName` separate for that reason.

---

## 2. What is allowed to reach the pantry

Three gates, none of which recognition can open on its own.

**1. Explicit acceptance.** Only rows with `isAccepted` are sent.
Preselection requires `tier == .agreed` **and** `assertsIngredient`, so a
disagreement between the detector and the classifier is never pre-ticked — the
user has to tick it themselves. Measured precision of the hybrid pipeline is
56.4%; human confirmation is the only thing between a guess and the pantry.

**2. An amount the user supplied.** `quantityText` starts **empty** and is
never defaulted. This follows the rule `ReceiptItemDraft` already documents:
the old fridge-scan flow defaulted every row to `1 pcs`, which silently put a
made-up number into the pantry whenever the user did not notice. Recognition
can see that a thing is there, not how much of it.

Save is refused until every accepted row has a usable amount, and the sheet
says which rows are missing one rather than leaving the button inert. Zero,
negative and non-numeric values are all rejected.

**3. The existing validation.** `AddPantryItemUseCase` still rejects empty
names and negative quantities, and still refuses duplicates rather than
merging quantities or adding a second row.

---

## 3. Duplicate and double-write handling

| Risk | Handling |
|---|---|
| Ingredient already in the pantry | `AddPantryItemUseCase`'s existing rule rejects it; reported as a duplicate, the existing item is untouched |
| Repeated Save taps | `saveToPantry()` returns immediately if `saveState.isSaving`; the toolbar shows a spinner instead of the button |
| Retry after a partial failure | Rows that were added *or* rejected as duplicates are deselected before retrying |

The re-entrancy guard is at the top of the method, not only on the button.
A second tap landing between the first tap and the next render would otherwise
write everything twice. `AddPantryItemUseCase`'s duplicate rule would catch
most of it, but relying on that means depending on a Firestore *read*
completing before the second write starts — not something to depend on.
`test_concurrentSavesDoNotWriteTwice` fires two overlapping saves and asserts
one write.

---

## 4. States

`PantrySaveState` is `idle` / `saving` / `succeeded` / `partial` / `failed`.

`partial` is a distinct case, not a flavour of success, because "three added,
two already there, one had no quantity" is the normal outcome of a real basket
and collapsing it to a tick would hide what the user needs to read.

| State | Sheet behaviour |
|---|---|
| `saving` | Spinner replaces Save; Cancel disabled |
| `succeeded` | Closes, Controller shows "Saved N to your pantry" |
| `partial` | **Stays open**, lists each failure, offers Retry |
| `failed` | **Stays open**, shows the reason, offers Try again |

The review list is never cleared on failure — the user's selections, edits and
amounts all survive, because they are the only record of what was chosen.
Only a clean success dismisses automatically; anything else waits for the user.

---

## 5. Wiring and ownership

The review sheet sits four levels below the composition root:

```
ContentView → ProfileView → ConnectedDevicesView → RemoteCameraView → review sheet
```

None of the intervening screens has anything to do with the pantry, so the
repository travels by environment (`\.pantryRepository`) rather than as a
parameter added to three unrelated views. `ContentView` injects the same
instance every other tab uses.

The environment default is the real `FirestorePantryRepository`, not an
in-memory one: if the injection is ever missed, the failure should be a
visible auth or network error, not a silent write into a dictionary that
disappears.

**Ownership and rules are unchanged.** `FirestorePantryRepository` resolves
`Auth.auth().currentUser?.uid` per call and writes to `users/{uid}/pantry`.
The existing rule still applies verbatim:

```
match /users/{uid}/pantry/{pantryItemId} {
  allow read, write: if isOwner(uid);
}
```

`firestore.rules` was not modified in this stage, and the review sheet has no
Firestore access of its own.

---

## 6. Category mapping

The detection taxonomy (`IngredientGroup`) and the pantry's
(`IngredientCategory`) are different axes, and the mapping is lossy:

| IngredientGroup | → pantryCategory |
|---|---|
| fruit, vegetable | `.produce` |
| meat, seafood | `.meat` |
| dairy | `.dairy` |
| pantry, decoy | `.other` |

Fruit and vegetable collapse to one category, and the detection side has no
`.grain` or `.spice` at all. So `IngredientReviewItem.pantryCategoryOverride`
exists: `nil` follows the mapping, and setting it wins. A bag of rice can be
filed as `.grain` even though recognition only knows it as "pantry".

---

## 7. Tests

| Suite | Tests | Covers |
|---|---|---|
| `IngredientReviewPantrySaveTests` | 20 | the whole of Stage 3 |
| `AddDetectedIngredientsUseCaseTests` | unchanged | proves the refactor preserved behaviour |

What `IngredientReviewPantrySaveTests` pins:

- only accepted rows are written; rejected rows never are
- a conflicting prediction starts unticked and so is not saved
- edited names, categories, quantities and units are what get stored
- a pantry category override beats the derived mapping
- manually added ingredients are stored
- save is refused until every accepted row has an amount
- a missing amount is never defaulted to `1 pcs`
- zero, negative and non-numeric amounts are unusable
- two overlapping saves produce one write
- an existing ingredient is reported as a duplicate, not written twice
- clean / partial / total failure states, and which allow dismissal
- the review list survives a failed save with selections intact
- retry sends only what did not get stored, including skipping duplicates
- retry after a total failure resends everything
- a missing use case fails loudly rather than silently succeeding

The repository double counts `add` calls and can be told to fail for specific
names, so partial outcomes are produced deliberately rather than hoped for.

```bash
xcodebuild -project FridgeFit.xcodeproj -scheme FridgeFit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

**680 tests, 4 expected skips, 0 failures.** The 4 skips are unchanged — the
`HybridRecognitionEvaluationTests` cases that need `VNClassifyImageRequest`,
which cannot run in the iOS simulator.

---

## 8. Remaining physical-device verification

**No compatible devices are connected, so nothing below has been run.**

```
$ xcrun devicectl list devices
K's Apple Vision Pro   …   unavailable
iPhone                 …   unavailable   iPhone 15 Pro
```

Both are paired but unavailable, and the flow needs *two* iPhones where only
one is known to this machine at all.

**Apple Vision has still never executed on a physical iPhone.** It cannot run
in the simulator, and the Mac Catalyst harness is macOS, not iOS. Every
accuracy figure quoted anywhere in these documents comes from Mac Catalyst or
Python. That claim is not made and should not be made until it has been run.

### Stage 3 checklist

Requires two iPhones on iOS 26.0+, signed into the same FridgeFit account,
plus a Firestore project the account can write to.

**The end-to-end flow**
- [ ] Analyse a captured image on the Controller
- [ ] Review suggestions; confirm the tiers render correctly
- [ ] Correct a name, a category, a quantity and a unit
- [ ] Save, and watch the spinner appear
- [ ] Open the Pantry tab and see exactly those ingredients, with the edited
      names, categories, quantities and units

**Ownership and rules**
- [ ] Items land at `users/{uid}/pantry` for the signed-in account
- [ ] Sign out, sign in as a second account, confirm the first account's
      ingredients are not visible
- [ ] Confirm a write is rejected when signed out (rules, not client checks)

**Duplicates and double-writes**
- [ ] Save an ingredient already in the pantry; confirm it is reported as a
      duplicate and the existing quantity is unchanged
- [ ] Double-tap Save rapidly; confirm one write, on real touch timing rather
      than a test fixture
- [ ] Save the same analysis twice; confirm the second run reports duplicates

**Failure and retry**
- [ ] Turn off networking mid-save; confirm the failure state, the review list
      surviving intact, and Try again working once connectivity returns
- [ ] Produce a partial failure (one valid row, one with a name the pantry
      rejects); confirm the sheet stays open and lists which failed
- [ ] Retry after a partial failure; confirm the already-saved rows are not
      written a second time

**Interaction with the rest of the app**
- [ ] Pantry list refreshes to include the new items
- [ ] Receipt scanning still writes correctly (shared use case)
- [ ] Recipe suggestions pick up the newly added ingredients
- [ ] Disconnect and reconnect the WebRTC session, then save again

Record results here under a new "On-device measurements" heading. Until that
section exists, device behaviour is unverified and should be described that
way.
