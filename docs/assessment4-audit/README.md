# Assessment 4 — Persistence Architecture Audit

Audit and design only. **No production code has been modified.**
Implementation awaits explicit approval.

- **Date:** 17 October 2026
- **Branch:** `docs/assessment4-persistence-audit`, cut from `main` at `34a9b85`
- **Verified toolchain:** Xcode 26.1 (17B55), iOS deployment target 26.0, Swift 5 mode

---

## The documents

| # | Document | Answers |
|---|---|---|
| 1 | [PERSISTENCE_ARCHITECTURE_AUDIT.md](PERSISTENCE_ARCHITECTURE_AUDIT.md) | What is actually built today, with file and line evidence |
| 2 | [ASSESSMENT4_RUBRIC_GAP_ANALYSIS.md](ASSESSMENT4_RUBRIC_GAP_ANALYSIS.md) | Where the marks are now, and after the work |
| 3 | [COREDATA_VS_SWIFTDATA_DECISION.md](COREDATA_VS_SWIFTDATA_DECISION.md) | Which backend, and why — weighted matrix |
| 4 | [RECOMMENDED_ADAPTER_ARCHITECTURE.md](RECOMMENDED_ADAPTER_ARCHITECTURE.md) | The design, and what changes |
| 5 | [DATA_MODEL_AND_RELATIONSHIPS.md](DATA_MODEL_AND_RELATIONSHIPS.md) | Entities, relationships, delete rules, queries |
| 6 | [FIREBASE_COMPATIBILITY_AND_ROLLBACK.md](FIREBASE_COMPATIBILITY_AND_ROLLBACK.md) | What stays on Firebase, and how to go back |
| 7 | [IMPLEMENTATION_AND_TEST_PLAN.md](IMPLEMENTATION_AND_TEST_PLAN.md) | Prioritised roadmap and test design |
| 8 | [PRESENTATION_EVIDENCE_PLAN.md](PRESENTATION_EVIDENCE_PLAN.md) | Demo script, diagrams, hurdle narrative |

Each distinguishes **[Verified]** (read from the repository or produced by a
command that was run), **[Proposal]** (design, not current behaviour) and
**[Assumption]** (inference, unproven).

---

## Executed evidence

| Command | Result |
|---|---|
| `xcodebuild build-for-testing -scheme FridgeFit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` | `EXIT=0` — **0 errors, 17 warnings** |
| `xcodebuild test-without-building` (same destination) | `EXIT=0` — **1114 tests, 0 failures, 4 skipped, 55.368 s** |

The `firestore-tests/` emulator suite was **not** run.

---

## The finding in one paragraph

FridgeFit has no native persistence of any kind — no SwiftData, no Core Data,
no CloudKit. It does already have MVVM, a use-case layer, domain-shaped
repository protocols, 13 domain error types, framework-free domain models, and
1,114 passing tests. So the gap is a **missing implementation behind
abstractions that already exist**, not a missing architecture. The recommended
change is additive: add SwiftData implementations of the protocols, select the
backend at the composition root, and leave every Firebase path intact.

---

# 中文摘要（繁體）

## A. 現行架構評估

**已驗證：** FridgeFit 目前**完全沒有原生持久化**——整個專案找不到 SwiftData、
Core Data 或 CloudKit 的任何一行。使用者的所有資料（食材庫、廚房活動紀錄、
收藏食譜）只存在 Firestore。

但架構本身**比這份評分表預期的還要好**：

- MVVM、Use Case 層、Repository Pattern 都是**真的實作**，不是只有資料夾名稱。
- 領域模型（`PantryItem`、`InventoryEvent`、`Recipe`）是**純 Swift struct**，
  只 import Foundation，完全不依賴任何框架。
- 四個 Repository protocol 帶有真正的領域語意，例如 `InventoryEventRepository`
  刻意只能新增不能修改，因為「可以被改寫的歷史不是歷史」。
- 13 個領域錯誤型別，訊息都是寫給使用者看的。
- 測試套件**實測 1114 個測試全數通過**（4 個略過），耗時 55 秒。

**結論：缺的是抽象層底下的實作，不是缺架構。**

## B. 建議 SwiftData 還是 Core Data

**建議 SwiftData。** 加權評分 94% 對 84%。

兩者的評分貢獻、可逆性、回歸風險**完全相同**，差別只在成本：Core Data 需要
`.xcdatamodeld` 編輯器檔案、`NSManagedObject` 子類別、容器設定，以及編譯器**無法
檢查**的字串式 `NSPredicate`。SwiftData 只需要加註解的 Swift 型別和型別安全的
`#Predicate` 巨集。

**相容性已驗證：** 部署目標是 **iOS 26.0**，SwiftData 需要 iOS 17+，超出九個大版本，
完全不需要任何 `@available` 判斷。

## C. 雙 Adapter 是否值得

**值得——但只因為基礎已經存在。**

Repository protocol 已經有了，組合根（`ContentView.init()`）已經有了，領域模型
已經與儲存無關。所以這不是重構，是**新增**：約 30,800 行程式碼完全不動，新增 9 個
檔案、修改 3 個檔案。

**同時明確建議不要做同步。** 評分表要的是原生持久化，不是同步；而且已驗證食材庫
的三個 repository **完全沒有使用任何 snapshot listener**，沒有即時需求要保留。
同步拿不到任何分數，卻會帶來資料遺失與重複寫入的風險。

## D. 符合評分表所需的最小改動

1. **清掉 17 個編譯警告**（最便宜的分數，且與持久化完全無關）。
2. 新增 `Data/SwiftData/`：entity、mapper、兩個 repository、容器。
3. 新增 `AppDependencies` 與 `PersistenceConfiguration`，並修改
   `ContentView.swift:41,82` 與 **`PantryRepositoryEnvironment.swift:21`**。
4. protocol 加上 `fetch(id:)` 與 `fetchExpiring(before:)`，讓「領域查詢」有地方存在。
5. 補上 contract 測試、SwiftData 整合測試，以及**重啟後資料仍在**的測試。

## E. 分數落差

| 評分項目 | 配分 | 目前 | 改動後 |
|---|---:|---:|---:|
| 架構、平台整合與持久化 | 4 | **2.0** | **4.0** |
| 自動化測試與程式碼品質 | 3 | **2.0** | **3.0** |
| 上架準備與 HIG | 4 | **2.0** | **3.5** |
| **可由程式碼驗證小計** | **11** | **6.0** | **10.5** |

誠實的部分：**30 分裡有 19 分是簡報與非程式碼產出**，持久化重構完全碰不到。
其中 9 分的產出**根本不在這個 repository 裡**，建議儘早確認放在哪裡。

上架準備是唯一**無法完全補滿**的項目（3.5/4），因為完整在地化工作量太大，刻意排除。

⚠️ **重要警告：這個 repository 裡沒有任何評分表或作業說明文件。** 以上所有配分
都是根據你提供的描述轉述，**沒有對照過任何原始文件**。請務必把真正的作業說明
加進 repo 再重新核對。

## F. 風險最高的部分

1. **`PantryRepositoryEnvironment.swift:21` 的預設值**——這裡直接 new 了一個
   `FirestorePantryRepository()`。如果只改 `ContentView` 而漏掉這裡，SwiftData 模式下
   遠端相機確認的食材會**寫進 Firestore**，而廚房頁面讀的是本機資料庫。這個錯誤
   **不會報錯**，現場看起來就是「我剛確認的食材不見了」。
2. **組合根改動**——五個分頁全部經過 `ContentView.init()`，是整份計畫唯一的中風險步驟。
   因此排序上**刻意放在 SwiftData 層已經獨立測試完成之後**。
3. **遠端相機 / WebRTC**——完全不要碰。signalling 是兩支手機之間的會合，本機資料庫
   不是「不適合」，是**根本做不到**，因為兩台裝置沒有共用的本機儲存。
4. **本機儲存沒有使用者隔離**——Firestore 用 `users/{uid}` 隔離，本機 SQLite 檔案
   沒有這種邊界。建議誠實說明，不要假裝有。

## G. 分階段實施步驟

```
P0-2  清掉 17 個警告（S，完全獨立）
  ↓
P0-1  SwiftData entity / mapper / repository（M，純新增，零風險）
  ↓
P2-1  Repository contract 測試（M）
P2-2  SwiftData 整合測試（M）
P2-3  重啟持久化測試（S，最有說服力的一個）
  ↓
P0-3  組合根接線（M，風險最高，所以放在這裡）
  ↓
P1-1  領域查詢 predicate（S-M）
P1-2  辨識紀錄 entity（M，可選，缺時間優先砍這個）
  ↓
P3    隱私清單、無障礙標籤、文件（S/M）
```

**排序原則：風險最高的 P0-3 一定要等 SwiftData 層獨立測試過才做。**

## H. 日後把 Firebase 改回主要後端

**改一行：**

```swift
private static let compiledDefault: PersistenceBackend = .firebase
```

重新編譯即可。所有 Firestore 程式碼路徑都還活著，因為**從頭到尾沒有刪掉任何一行**，
而且 contract 測試每次 CI 都會對它跑一遍。

**不需要資料遷移**——Firestore 的文件從來沒有被刪除或修改過。

若要完全移除 SwiftData：刪掉 `Data/SwiftData/`、刪掉設定檔、還原三個被修改的檔案、
刪掉新增的測試。全部都是刪除動作。

## I. GO / NO-GO 建議

### ✅ **GO**

四個理由：

1. **這是新增，不是重構。** 約 30,800 行程式碼完全不動；風險集中在單一個檔案的接線。
2. **補的是唯一結構性失分項。** 原生持久化是評分表點名的要求，目前完全沒有。
3. **可逆性是設計出來的，不是事後補的。** 回退最便宜的方式是改一個列舉值。
4. **對現場演示反而更安全。** SwiftData 模式把網路和登入從示範的關鍵路徑上拿掉了。

### 三個前提條件

1. **先做 P0-2**（清警告）。它獨立、便宜，而且評審十秒內就能驗證。
2. **P0-3 必須等 SwiftData 層測試完成**後才動。把未驗證的儲存層接進每個分頁，
   然後同時 debug 兩邊，是示範前一週把能動的 app 弄壞的標準流程。
3. **完全不要碰遠端相機、WebRTC、認證與 Firestore 規則。**

### ⛔ 明確不做

- 雙向同步（0 分，高風險）
- 同時實作 SwiftData 和 Core Data（分數一樣，風險加倍）
- CloudKit（`@Attribute(.unique)` 不相容，且會變成第二套雲端同步）
- 完整在地化（工作量太大，超出範圍）

---

**等待明確核准後，才會動到任何正式程式碼。**
