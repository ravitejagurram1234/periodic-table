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
