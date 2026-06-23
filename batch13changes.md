# EOS Quark Engine — Batch 13 Changes
**Theme: cleanup / cosmetic parity (the tail of the list)**

_Small snippets across 6 files. Four LOW findings deferred (flow/feature changes) — see flags._

## Findings fixed (6)
| # | File | Fix |
|---|---|---|
| #59 | `CheckServiceImpl` | Removed the redundant `run.setRunTask(new RunTask(run))` before re-processing — `processTasks()` is the sole creator (matches .NET). (unused import also removed) |
| #71 | `DocumentIdentityHelper` | Null due-date now renders `01/01/0001 00:00:00` (DateTime.MinValue), not an empty field. |
| #74 | `TElementHelper` | `newBlocName()` wraps the id in `[...]` to byte-match .NET HookString. |
| #75 | `TElementHelper` | `parseDecimal` returns `decimal.MinValue` (not 0) on null/blank/unparseable — matches ConversionInvariante.ToDecimal (scoped to updatePosition). |
| #76 | `BlocPage` | `getNbBox()` REMOVE path returns the XML box-count directly (no try/catch that silently returned 1 and corrupted the count). |
| #94 | `ProcessSqlBusiness` | Corrected the misleading severity comment (1=Unspecified, 2=Critique, 3=Bloquante) and reused `RunError.CRITIQUE`. |

## ⏸️ Deferred (LOW — intentionally not done)
- **#60** (double gabarit-XML refresh in Check): the *parity-correct* fix means deliberately reading the **stale, pre-reprocess** XML for the DOCUMENT data drawer (because .NET does one lazy `Get_XML` and never invalidates it). That's a counterintuitive change to data-collection behavior — flagged for review rather than blindly applied.
- **#61** (checkOverflow Todo=false sweep should run unconditionally): a flow change in the overflow branch that interacts with the subsequent data-collection phase. Worth doing, but needs a careful trace of `collectSqlData`/`collectDocumentData` first — deferred to avoid an unintended interaction.
- **#70** (date/datetime patterns run-configurable): a **feature** that changes `DataTypeHelper.outputToString`'s inputs across all callers. The current hardcoded patterns already match the .NET defaults (`dd/MM/yyyy[ HH:mm:ss]`), so this is configurability, not a correctness gap.
- **#72** (preserve raw `id_type_rapport` for previous-report-type): needs a new `RunProperties` raw-int field + mapper + `resolvePreviousTypeRapport` rework. Deferred with the other RunProperties-shape changes.

---

## `CheckServiceImpl` (#59) — delete the redundant line
```java
// BEFORE:
//   // Re-create RunTask for re-processing
//   run.setRunTask(new RunTask(run));
//   processTasksService.processTasks(run);
// AFTER: just
processTasksService.processTasks(run);   // creates+configures RunTask itself
// (also remove the now-unused `import ...domain.RunTask;`)
```

---

## `DocumentIdentityHelper` (#71)
```java
joiner.add((props.getDateEcheance() != null ? props.getDateEcheance() : java.time.LocalDate.of(1, 1, 1))
        .atStartOfDay().format(DATE_TIME_FORMATTER));
```

---

## `TElementHelper.newBlocName` (#74)
```java
String body = uuid.length() > NEW_BLOC_NAME_SIZE ? uuid.substring(0, NEW_BLOC_NAME_SIZE) : uuid;
return "[" + body + "]";
```

---

## `TElementHelper.parseDecimal` (#75)
```java
private static final BigDecimal DECIMAL_MIN_VALUE = new BigDecimal("-79228162514264337593543950335");
// ... return DECIMAL_MIN_VALUE (instead of BigDecimal.ZERO) on null/blank/NumberFormatException
```

---

## `BlocPage.getNbBox` (#76)
```java
if (getAction() == BlocActionEnum.REMOVE) {
    return getTask().getRun().getGabarit().getQxpXml().getProjectInfo().getNbBoxOnPage(getPageId());
}
return super.getNbBox();
```

---

## `ProcessSqlBusiness` (#94)
```java
/** RunError categories (see RunError / .NET Error_Type): 1=Unspecified, 2=Critique, 3=Bloquante. */
private static final int CRITIQUE = RunError.CRITIQUE;
```

## Apply checklist
- [ ] CheckServiceImpl · DocumentIdentityHelper · TElementHelper · BlocPage · ProcessSqlBusiness
- [ ] `mvn compile` + `mvn test`
- [ ] (deferred) #60/#61/#70/#72 in a focused follow-up
