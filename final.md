# EOS Quark — Build Warnings Fix #2: `DocumentDomain` Lombok `@Builder` defaults

**Date:** 2026-08-07
**Repo:** `14-07 engine service repo/quark-engine`
**File changed:** `src/main/java/com/socgen/sgs/api/quark/engine/domain/DocumentDomain.java` (1 file)
**Status of the local Mac copy before this change:** change was **NOT** present — the Copilot edit exists only on your work laptop (if at all). Applied here now.

---

## 1. What the build warned about

```
DocumentDomain.java:[51,21] @Builder will ignore the initializing expression entirely.
DocumentDomain.java:[70,26] @Builder will ignore the initializing expression entirely.
```

Two fields with inline defaults that `@Builder` silently discards:

| Line | Field | Real impact |
|---|---|---|
| 51 | `private boolean modeDegrade = false;` | **None.** `false` is already the JVM default for a primitive `boolean`. Cosmetic — silences the warning, behaviour identical on every path. |
| 70 | `private List<String> pdfFiles = new ArrayList<>();` | **Real NPE risk.** Objects built via `DocumentDomain.builder()` get `pdfFiles == null`. |

### The `pdfFiles` NPE path is live in this codebase

- **Builder is used:** `infra/dao/impl/GetGabaritTemplateDaoImpl.java:42` builds `DocumentDomain` via `.builder()`.
- **Getter is called unguarded:** `service/task/impl/DocumentTaskProcessStrategy.java:221`
  → `if (doc == null || doc.getPdfFiles().isEmpty())` — NPE if `pdfFiles` is null.
  Also `:242` (`.size()`) and `:278` (`.get(i)`).

---

## 2. Why `@Builder.Default` **alone** is not enough — verified regression

Lombok does not just annotate the field: it **removes the initializer** and moves it into a generated
`$default$pdfFiles()` helper, which it can inject **only into the constructors Lombok itself generates**.
Any **hand-written** constructor is left untouched — so the field becomes `null` there.

`DocumentDomain` **has** a hand-written 5-arg constructor
(`DocumentDomain(Integer id, String name, String format, String prefix, byte[] data)`),
used at `service/impl/ProcessRunServiceImpl.java:147, 152, 157` (finalJpg / finalPdf / finalQxp).

**Empirically verified against the exact pinned Lombok version (1.18.30):**

| Construction path | `@Builder.Default` only | `@Builder.Default` + null-safe getter |
|---|---|---|
| `new DocumentDomain()` — used by 6 DAOs | `[]` ✅ | `[]` ✅ |
| `DocumentDomain.builder().build()` — GetGabaritTemplateDaoImpl | `[]` ✅ (this is the fix) | `[]` ✅ |
| **hand-written 5-arg ctor** — ProcessRunServiceImpl | **`null` ❌ REGRESSION** | `[]` ✅ |
| `@AllArgsConstructor` with `null` | `null` ❌ | `[]` ✅ |
| `setPdfFiles(null)` | `null` ❌ | `[]` ✅ |

Applying `@Builder.Default` on its own would have **fixed one null path and created another.**
Hence the extra null-safe guard in the hand-written `getPdfFiles()`.

---

## 3. .NET parity check

`QXP.Engine.Core/BusinessObject/Document/Document.cs`:
- `_pdfs` (line 32) has **no initializer** → `PDFFiles` is `null` by default in .NET.
- `PDFFiles` (line 342) is declared but **never read or written anywhere else in `QXP.Engine.Core`** — it is dead code in the .NET engine.

The Java `pdfFiles` list is a Java-side reimplementation (populated by
`LoadTaskDocumentsBusiness.loadPdfPages`), so **.NET imposes no parity constraint here.**
Empty-list-never-null is therefore a free robustness win, not a behaviour divergence.

`Mode_Degrade` in .NET is a lazily-evaluated `bool?` (`_mode_degrade = null` until
`Evaluate_Mode_Degrade()` runs). The Java `modeDegrade` field is only a cached flag; the real
evaluation lives in `evaluateModeDegrade(long)`. Unchanged by this fix.

---

## 4. Changes to apply (3 edits)

### Edit 1 — line ~51: add `@Builder.Default` to `modeDegrade`

**Find:**
```java
    private boolean gabarit;
    private boolean modeDegrade = false;
    private DocumentIdentity documentIdentity;
```

**Replace with:**
```java
    private boolean gabarit;
    @Builder.Default
    private boolean modeDegrade = false;
    private DocumentIdentity documentIdentity;
```

---

### Edit 2 — line ~70: add `@Builder.Default` to `pdfFiles`

**Find:**
```java
    /** List of PDF page file paths (for multi-page PDF documents). */
    private List<String> pdfFiles = new ArrayList<>();
```

**Replace with:**
```java
    /**
     * List of PDF page file paths (for multi-page PDF documents).
     *
     * <p>{@code @Builder.Default} makes the builder honour the empty-list default. Note that Lombok
     * moves the initializer out of the field into a generated {@code $default$pdfFiles()} helper,
     * which it can only inject into the constructors <em>it</em> generates — the hand-written
     * 5-arg constructor below would therefore leave this field null. {@link #getPdfFiles()} is
     * lazily null-safe to cover that path.
     */
    @Builder.Default
    private List<String> pdfFiles = new ArrayList<>();
```

---

### Edit 3 — line ~178: make the hand-written `getPdfFiles()` null-safe

**Find:**
```java
    /**
     * Get the list of PDF page file paths.
     *
     * @return the list of PDF file paths
     */
    public List<String> getPdfFiles() {
        return this.pdfFiles;
    }
```

**Replace with:**
```java
    /**
     * Get the list of PDF page file paths, never null.
     *
     * <p>Lazily initialises the list so every construction path yields an empty list rather than
     * null: the hand-written 5-arg constructor (which Lombok cannot inject the {@code @Builder.Default}
     * initializer into) and {@code setPdfFiles(null)} both leave the field null otherwise.
     * DocumentTaskProcessStrategy.processFilePdf calls {@code getPdfFiles().isEmpty()} unguarded.
     *
     * @return the list of PDF file paths (empty when none)
     */
    public List<String> getPdfFiles() {
        if (this.pdfFiles == null) {
            this.pdfFiles = new ArrayList<>();
        }
        return this.pdfFiles;
    }
```

No import changes needed — `Builder` and `ArrayList` are already imported.

---

## 5. Expected result after rebuild

- The two `@Builder will ignore the initializing expression entirely` warnings disappear.
- `pdfFiles` is guaranteed non-null on all five construction paths.
- No behaviour change for `modeDegrade` (was and remains `false` by default everywhere).
- No test changes required — all 308 tests should still pass.

---

## 6. Side note found while checking (not fixed here)

Your **local Mac copy** of `pom.xml` still has `<spring-boot.version>2.7.18</spring-boot.version>`
(line 27) — i.e. **issue #1 is also not present in the copy on this machine**, only on your work
laptop. Also note the parent version differs between the two copies:

| | parent `sgs-api-core` |
|---|---|
| Local Mac copy | `11.0.1` |
| Work laptop (per your build log) | `11.5.1` |

So the Mac copy is genuinely older, as you said. I could not verify the issue-#1 fix locally:
`sgs-api-core` is an internal SocGen artifact and is not resolvable from this machine, so I cannot
confirm what `spring-boot.version` the `11.0.1` parent defaults to. On the work laptop your
verification (plugin now resolving to `3.5.15`) is the authoritative check — that one looked correct.

**When you next paste code over, please paste the current work-laptop `pom.xml` and `DocumentDomain.java`**
so the two copies stop drifting.

---
---

# APPENDED 2026-08-10 — Change #3: `TaskAnchor.evaluateInfo()` was a no-op

**Repo:** `14-07 engine service repo/quark-engine 2`
**File changed:** `src/main/java/com/socgen/sgs/api/quark/engine/domain/task/TaskAnchor.java` — **1 file, 56 insertions, 3 deletions**
**Nothing else in the repo was touched.** Confirmed with `git status --porcelain` (only this file's mtime
moved) — every other modified file in that listing is pre-existing port work, unchanged by me.

> This section is unrelated to the DocumentDomain build warnings above. It is appended here because this
> is the file you carry to the work laptop.

---

## 7.1 What was wrong

`TaskAnchor` overrode `evaluateInfo()` with an **empty body**:

```java
    /** Evaluates pageNum and layoutName from the start anchor — resolved via gabarit XML in the business layer. */
    @Override
    public void evaluateInfo() {
        // pageNum and layoutName are set by the business layer using getAnchorName(true)
    }
```

The comment was wrong — no business-layer code ever set them. Because the override existed, it also
**suppressed** `TaskBase.evaluateInfo()`, which does set them (from the raw `destinationBlocName`).
So for the two anchor task types — `TaskDynamique` and `TaskCompartiment` — both properties stayed at
their initial values (`pageNum = 0`, `layoutName = null`) for the entire run.

### Three consumers were reading those values

| Consumer | Evidence | Effect of the unset value |
|---|---|---|
| `QxpsModifier.addGetLayout` | `QxpsModifier.java:167-172` | `layoutName == null` → returns `null` → `addGetSpread` (`:183-190`) records a `RunError` "Layout ou Spread NULL pour le bloc …" and **drops the bloc** |
| `TaskBase.getPageIdFromRelative` | `TaskBase.java:75` | start page treated as `0`, so every relative page offset is computed from the wrong base |
| `RunTaskStep.updateBlocPagination` | `RunTaskStep.java:217-219` | tasks are sorted by `properties.getPageNum()`; every anchor task tied at `0`, so the sort collapsed to insertion order |

There is a fourth, indirect effect: `QxpsModifier.empty` is only cleared inside `addGetSpread`
(`QxpsModifier.java:192`), and `QxpsCallerBusiness.java:148,182` skip sending the Modify command
entirely when `modifier.isEmpty()`. So a step containing **only** anchor-task blocs sent **nothing at
all** to QuarkXPress. The run still finished `Generated`.

**Net symptom:** every DYNAMIQUE and COMPARTIMENT bloc silently vanished. The document rendered, the
run reported success, and the dynamic content was simply absent.

---

## 7.2 The .NET source of truth

`QXP.Engine.Core/BusinessObject/Run/Task/Task_Anchor.cs:53-60`:

```csharp
public override void Evaluate_Info()
{
    string __destination_Ancre = this.Get_Anchor_Name(true);      // "{0}_START"

    //this.Properties.SpreadID = this.Run.Gabarit.XML.GetSpreadId(__destination_Ancre);   // commented out in .NET
    this.Properties.PageNum    = this.Run.Gabarit.XML.GetPageNum(__destination_Ancre);
    this.Properties.LayoutName = this.Run.Gabarit.XML.GetLayoutName(__destination_Ancre);
}
```

Supporting facts, all verified in the .NET tree:

| Fact | Evidence |
|---|---|
| The anchor used is **START**, not END | `Task_Anchor.cs:55` + pattern at `:26` (`"{0}_START"`) |
| Exactly **two** properties, in this order; SpreadID is commented out | `Task_Anchor.cs:57-59` |
| The override does **not** call `base` and **drops** the base's `IsSet(DestinationBlocName)` guard | compare `Task_Base.cs:89-98` |
| A missing anchor does **not** throw here — the throwing path is `Get_Anchor_Info`, which `Evaluate_Info` never calls | `Task_Anchor.cs:90-102` |
| `GetPageNum` not-found → **`int.MinValue`** | `QXP_XML.cs:284-290` → `ConversionInvariante.ToInt(string)` → `ToInt(value, int.MinValue)` |
| `GetLayoutName` not-found → `string.Empty` | `QXP_XML.cs:276` |
| `Evaluate_Info` is fired as a **C# event** from `Prepare` | `Run_Task_Step.cs:34` (declaration), `:81-83` (fire), subscriptions at `Run_Task.cs:166,168,183,190,192` |
| .NET **also sorts tasks by `Properties.PageNum`** in the pagination pass | `Run_Task_Step.cs:251` |
| Only `Task_Compartiment` and `Task_Dynamique` derive from `Task_Anchor`; **neither overrides** `Evaluate_Info` | `Task_Compartiment.cs:15`, `Task_Dynamique.cs:15` |

> **Note on greps.** Several `.cs` files in this tree are ISO-8859-1 and `grep` treats them as binary,
> returning **no matches silently**. `Run_Task_Step.cs` and `QXP_XML.cs` are both affected. Use
> `grep -a` for anything in the .NET tree, or you will conclude a method has no callers when it does.

---

## 7.3 The change to apply

The file is 146 lines, so the **whole file after the change** is given below. Overwrite
`src/main/java/com/socgen/sgs/api/quark/engine/domain/task/TaskAnchor.java` with it.

Structurally there are only three edits:
1. add the import `com.socgen.sgs.api.quark.engine.domain.xml.QxpXml`;
2. extract the existing null-guard out of `getBlocInfo` into a new private `requireGabaritXml(String)`
   that returns the `QxpXml` — `getBlocInfo`'s behaviour is **unchanged** (same condition, same message,
   same return);
3. implement `evaluateInfo()`.

```java
package com.socgen.sgs.api.quark.engine.domain.task;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBlocInfo;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import lombok.Setter;

/** Abstract base for tasks that manipulate start/end anchors in the document. */
@Setter
public abstract class TaskAnchor extends TaskBase {

    private static final String START_ANCHOR_PATTERN = "%s_START";
    private static final String END_ANCHOR_PATTERN   = "%s_END";

    private DBlocInfo startAnchor;
    private DBlocInfo endAnchor;

    protected TaskAnchor(int id, Run run) {
        super(id, run);
        this.setSubTaskType(SubTaskTypeEnum.FILE_QXP_DATA);
    }

    /** Returns the anchor bloc name (start or end) derived from the destinationBlocName. */
    public String getAnchorName(boolean start) {
        String pattern = start ? START_ANCHOR_PATTERN : END_ANCHOR_PATTERN;
        return String.format(pattern, this.getDestinationBlocName());
    }

    /**
     * Fetches anchor info for the given anchor name via getBlocInfo.
     * Throws IllegalStateException if the anchor UID is not found in the document.
     */
    public DBlocInfo getAnchorInfo(boolean start) {
        String anchorName  = this.getAnchorName(start);
        DBlocInfo dblocInfo = this.getBlocInfo(anchorName);

        if (dblocInfo == null || dblocInfo.getUid() == null || dblocInfo.getUid().isBlank()) {
            throw new IllegalStateException("Anchor not found in document: " + anchorName);
        }
        return dblocInfo;
    }

    /**
     * Resolves bloc info for the given box name from the parent run's gabarit XML.
     * Parity: .NET Task_Base.Get_Bloc_Info → {@code this.Run.Gabarit.XML.GetBlocInfo(boxName)}
     * (Task_Base.cs:177). The gabarit XML is populated during Run.prepareGabarit (see Batch 1),
     * so a real UID is returned here; {@link #getAnchorInfo(boolean)} then throws only when the
     * lookup yields no UID — matching .NET's "Ancre Introuvable" behaviour (Task_Anchor.cs:95-98).
     */
    protected DBlocInfo getBlocInfo(String blocName) {
        return requireGabaritXml(blocName).getBlocInfo(blocName);
    }

    /**
     * The parent run's gabarit XML.
     *
     * <p>Java-only defensive guard with no .NET counterpart — .NET {@code Task_Base.Get_Bloc_Info}
     * (Task_Base.cs:175-179) dereferences {@code Run.Gabarit.XML} bare. It is kept because it
     * predates this method (it was already inside {@link #getBlocInfo(String)}) and can only fire
     * where .NET would fault too.
     *
     * <p>Only the {@code run}/{@code gabarit} clauses are reachable: {@code DocumentDomain.getQxpXml()}
     * returns {@code QxpXml.EMPTY} rather than null (DocumentDomain.java:110-115), mirroring .NET's
     * {@code Document.XML} which returns {@code QXP_XML.Empty} (Document.cs:421-446). A gabarit whose
     * XML never loaded therefore yields the sentinels below, it does not throw.
     */
    private QxpXml requireGabaritXml(String blocName) {
        if (this.getRun() == null || this.getRun().getGabarit() == null
                || this.getRun().getGabarit().getQxpXml() == null) {
            throw new IllegalStateException(
                    "Gabarit XML is not loaded; cannot resolve bloc '" + blocName
                            + "' for task " + this.getId()
                            + " — Run.prepareGabarit must run before anchor resolution");
        }
        return this.getRun().getGabarit().getQxpXml();
    }

    /**
     * Re-evaluates this task's page and layout from the START anchor against the CURRENT gabarit XML.
     *
     * <p>Called by {@code RunTaskStep.prepare()} before every step, so the values track the document
     * as earlier steps add and remove pages.
     *
     * <p>Parity: .NET {@code Task_Anchor.Evaluate_Info()} (Task_Anchor.cs:53-60) — same anchor
     * ({@code <destination>_START}), same two properties, same lookups.
     *
     * <p>Three consumers read these two properties, and all three were wrong while this method was a
     * no-op:
     * <ul>
     *   <li>{@code QxpsModifier.addGetLayout} reads {@code properties.layoutName}; a blank name made
     *       it return null, so {@code addGetSpread} recorded "Layout ou Spread NULL" and dropped the
     *       bloc — every DYNAMIQUE and COMPARTIMENT bloc, silently;</li>
     *   <li>{@code TaskBase.getPageIdFromRelative} reads {@code properties.pageNum} as the task's
     *       start page;</li>
     *   <li>{@code RunTaskStep.updateBlocPagination} sorts tasks by {@code properties.pageNum} before
     *       computing page offsets — matching .NET Run_Task_Step.cs:251. With the value unset, every
     *       anchor task tied at 0 and the sort degenerated to insertion order.</li>
     * </ul>
     *
     * <p>Note this override deliberately does <em>not</em> keep {@code TaskBase.evaluateInfo}'s
     * blank-name guard, because .NET's override drops it too: a null destination yields a
     * non-matching anchor name and the properties are overwritten with the sentinels rather than
     * left at their previous values.
     *
     * <p>When the anchor is absent, both sides yield the same "not set" sentinels — page
     * {@code Integer.MIN_VALUE} (.NET: {@code ConversionInvariante.ToInt} defaults to
     * {@code int.MinValue}) and an empty layout name. Only the empty <em>layout</em> causes the
     * Modifier to skip the bloc; {@code pageNum} is never range-checked on either side.
     */
    @Override
    public void evaluateInfo() {
        String startAnchorName = this.getAnchorName(true);
        QxpXml gabaritXml      = requireGabaritXml(startAnchorName);

        this.getProperties().setPageNum(gabaritXml.getPageNum(startAnchorName));
        this.getProperties().setLayoutName(gabaritXml.getLayoutName(startAnchorName));
    }

    @Override
    public void resetProcess() {
        super.resetProcess();
        this.startAnchor = null;
        this.endAnchor   = null;
    }

    /** Lazily loads and returns the start anchor info. */
    public DBlocInfo getStartAnchor() {
        if (this.startAnchor == null) {
            this.startAnchor = this.getAnchorInfo(true);
        }
        return this.startAnchor;
    }

    /** Lazily loads and returns the end anchor info. */
    public DBlocInfo getEndAnchor() {
        if (this.endAnchor == null) {
            this.endAnchor = this.getAnchorInfo(false);
        }
        return this.endAnchor;
    }

    /** Returns the number of existing pages between the two anchors. */
    public int getNbAnciennePage() {
        return this.getEndAnchor().getPage() - this.getStartAnchor().getPage() + 1;
    }
}
```

---

## 7.4 Impact review — what else this touches

Everything below was checked against the repo, with file:line evidence.

### Callers

**One call site in the whole repo**: `RunTaskStep.java:78-79`, inside `prepare(boolean)`, looping
`evaluateInfoTasks`. Registration at `RunTask.java:148-149, 163, 168-169` — only for tasks that
produced modify or pagination blocs, exactly like the .NET `+=` / `-=` subscriptions.

### Is the gabarit XML always loaded first?

Yes, on three independent grounds:

1. **Ordering.** `ProcessRunServiceImpl.launch` → `load(run)` (`:67`) → `run.prepareGabarit(...)`
   (`:174`) → `loadTasksService.loadTasks` (`:186`); step execution only starts later at
   `qxpsCallerService.process(run)` (`:86`) → `QxpsCallerBusiness.process` → `step.prepare(...)`
   (`QxpsCallerBusiness.java:71`).
2. **Degrade mode is double-guarded.** `ProcessRunServiceImpl.java:181` skips `loadTasks` (so no steps
   exist at all) and `QxpsCallerBusiness.java:57` returns early.
3. **`getQxpXml()` never returns null** — `DocumentDomain.java:110-115` returns `QxpXml.EMPTY`.

So the new `IllegalStateException` cannot fire in any reachable path. It is belt-and-braces only.

### Subclasses

`TaskDynamique` (`TaskDynamique.java:17`) and `TaskCompartiment` (`TaskCompartiment.java:13`).
Neither overrides `evaluateInfo()`. Same shape as .NET.

### Null / type safety

- `QxpXml.getPageNum(String)` returns primitive `int` (`QxpXml.java:309`); not-found →
  `Integer.MIN_VALUE` via `parseIntSafe` (`:670-677`).
- `QxpXml.getLayoutName(String)` returns `""` when not found (`:334-337`).
- Neither can throw: `XPathExpressionException` is caught in `evaluateString` (`:583-585`),
  `NumberFormatException` in `parseIntSafe` (`:675`).
- `TaskProperties.pageNum` is a primitive `int` (`TaskProperties.java:12`) → `int` to `int`,
  **no unboxing, no NPE possible**.

### Tests

No test fails. Verified individually:

| Test | Why it is unaffected |
|---|---|
| `TaskPropertiesTest.java:23-24` | asserts defaults on a bare `new TaskProperties()`; never calls `evaluateInfo` |
| `TaskMapperTest.java:152-153, 182, 203, 220-221, 238` | builds anchor tasks but never calls `evaluateInfo` |
| `BlocBaseTest.java:27-29` | stubs an anonymous `TaskBase`, not `TaskAnchor` |
| `TaskCompartimentModeTest.java` | an enum test, unrelated despite the name |
| `CleanArchitectureLayersTest.java:16-20` | the new import is `domain` → `domain`, allowed |

There is no `TaskAnchor`, `QxpXml` or `RunTaskStep` test class at all — so **no test covers this
change either**. See §7.6.

### Compilation

Every symbol verified present: `QxpXml`'s package declaration matches the import
(`QxpXml.java:1`); `getProperties()` from Lombok `@Getter` on `TaskBase` (`:14, 32`);
`setPageNum(int)` / `setLayoutName(String)` from `@Setter` on `TaskProperties` (`:8`);
`getAnchorName(boolean)` is public in the same class; `getRun()` / `getId()` from `@Getter` on
`TaskBase` final fields (`:19-20`). No checkstyle/spotbugs/pmd configured in `pom.xml`, so no style
gate to trip.

**`javac` syntax check passes** — compiling the file standalone produces only `cannot find symbol` /
`package does not exist` errors from the absent classpath, and **zero syntax errors**.

---

## 7.5 What is NOT verified — read before you trust this

1. **It has never been compiled.** There is no `mvnw` in the repo and no `mvn` on the Mac.
   **Run `mvn clean verify` on the work laptop before trusting any of this.**
2. **It has never been run.** No run has exercised a Dynamique or Compartiment task with the fix in
   place.
3. **This activates a code path that has never executed.** Because `QxpsModifier.empty` previously
   stayed `true` for anchor-only steps, those steps sent no Modify command at all. This change makes
   the full modify path go live for DYNAMIQUE/COMPARTIMENT for the first time. It is correct per .NET,
   but it is not a two-line behavioural delta — treat the first run as a real test.
4. **The pagination sort order changes.** Anchor tasks previously all tied at `0`; they now sort by
   real start page. .NET does the same (`Run_Task_Step.cs:251`), so this is a second bug being fixed —
   but `updateBlocPagination`'s offset/lagSpread algorithm (`RunTaskStep.java:225-315`) is
   order-sensitive, so **a multi-Dynamique document is the case to test.**

### Two cosmetic divergences, deliberately left alone

| # | Divergence | Why it is left |
|---|---|---|
| 1 | With a null `destinationBlocName`, Java's `String.format("%s_START", null)` yields `"null_START"`; C#'s `string.Format` yields `"_START"`. | Both fail the lookup and produce identical sentinels. Only observable if a gabarit contains a box literally named `_START`. Fixing it would mean touching `getAnchorName`, which also feeds the "Anchor not found" message. |
| 2 | `QxpXml.java:307` javadoc still says "or 0 if not found"; the method returns `Integer.MIN_VALUE`. | Pre-existing, in a different file, and the code comment immediately below it (`:310`) is correct. Not in scope for this change. |

---

## 7.6 Recommended next steps (NOT done — awaiting your go-ahead)

1. **Add a unit test for `TaskAnchor.evaluateInfo()`.** There is currently no coverage. A test that
   feeds a small gabarit XML containing `X_START` and asserts `pageNum` / `layoutName` would have
   caught the original no-op and will protect the fix.
2. **Same defect exists in two more task types.** `Task_Document.Evaluate_Info` (`Task_Document.cs:145`)
   and `Task_QXP_Previous.Evaluate_Info` (`Task_QXP_Previous.cs:102`) were **never ported**. On the
   Java side, `TaskDocument.resolveTargetBlocName()` (`TaskDocument.java:71`) and
   `TaskQxpPrevious.resolveTargetBlocName()` (`TaskQxpPrevious.java:29`) exist but have **zero
   callers** — both classes fall through to `TaskBase.evaluateInfo`, which uses the raw
   `destinationBlocName`. For these task types that value is a pipe-joined list or needs a `_1` suffix,
   so the XPath misses and page/layout stay unset. **Same silent-bloc-drop symptom as this fix just
   repaired.** I have not touched it — say the word and it becomes the next change.
