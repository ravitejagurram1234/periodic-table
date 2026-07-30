# EOS Quark Java Engine — Consolidated Validation Issue List

## Executive Summary

95 verified parity/correctness issues, deduplicated to ~40 distinct defects: **9 CRITICAL, 17 HIGH, 18 MEDIUM, ~16 LOW**. Three systemic themes dominate: (1) **gabarit pool-key / mode-degrade / gabarit_template load chain** — the gabarit is uploaded under `getFileName()` instead of `getFilePoolPath()`, degrade mode returns before the upload, the full gabarit XML is never loaded before Process, and the template gabarit document is never loaded at all; (2) **[Flags] enums collapsed to single-value enums** (`StoreDataType`, `AbsoluteRepeatType`) so combined bit values silently lose data or crash; (3) **errors downgraded from throw/RunError to log-only**, so structurally-wrong output completes "clean" with no operator-visible failure (TGroup, ProcessSql, Document/System/DID tasks, compartiment-mode).

**Runtime-readiness by flow:** Standard/SQL/System/DID render is **broken on every non-degraded run** (gabarit pool-key mismatch → render targets a non-existent pooled doc). DOC_EOS PDF/IMG works only for QXP-format references ≤ size limit (non-QXP large docs silently dropped; multi-page PDF pages 2..N mis-positioned when POSITION_IMAGE is NULL). RTF/Word: shares the document-task strategy; same caveats. QXP_DATA: depends on style-preserve project fetch (degrade-on-failure missing, LOW). QXP_Previous: works (the only path that "works by coincidence"). **Dynamique: broken** (template gabarit never loaded → blocs cloned from wrong/empty source; combined ABSOLUTE_REPEAT crashes load). **Compartiment INCORPORATE/GENERATE: broken** (anchor resolution is a stub → "Anchor not found"; addRunBlocs reads template instead of generated QXP). **mode-degrade: broken** (no gabarit in pool → degraded render produces no output). **Persistence: store_data and run-error writes throw at runtime** (PL/SQL associative arrays bound as SQL ARRAY).

---

## CRITICAL

### Theme A — Gabarit pool key & mode-degrade (the single most damaging cluster)

The following issues all stem from `Run.prepareGabarit` (`domain/Run.java:158-176`) and together break **every** render. Fix them as one coordinated change.

**C1. Gabarit uploaded under `getFileName()` instead of `getFilePoolPath()` — every render targets a non-existent pooled document**
*(merges issues at Run.java:167, Run.java:170, and the duplicate "process steps modify a non-existent document")*
- **File:** `domain/Run.java:167` (upload) and `:170` (DID fetch)
- **Scenario:** Every run, all gabarit sources, non-degraded path.
- **Root cause:** Upload keys on `getFileName()` (pool root, `G_45_1.qxp`) but every downstream consumer — `QxpsCallerBusiness.executeStep:106`/`render:197`, `CheckServiceImpl:89`, dedup/inform — addresses the gabarit by `getFilePoolPath()` (`R_<id>/G_45_1.qxp`). QXPS cannot find the document during Process/Render → no output. .NET keys both upload and XML/DID load on `FilePoolPath` (Run.cs:92, Document.cs:430).
- **Fix:** Change line 167 to `filePoolPort.addFile(this.gabarit.getFilePoolPath(), this.gabarit.getData())` and line 170 to `documentIdentityPort.fetchXmlForBox(this.gabarit.getFilePoolPath(), "DID")`. Both must change together. `getFilePoolPath()` is already populated by `GetGabaritBusiness.preparePaths`.

**C2. Mode-degrade returns before the gabarit pool upload — degraded render has no document**
*(merges the four duplicate degrade/upload findings on Run.java:158-167)*
- **File:** `domain/Run.java:158-167`
- **Scenario:** Gabarit byte-size > `engine.gabarit.size-limit-before-fail-soft`. `prepareGabarit` sets `modeDegrade=true` and returns at ~line 163, before `filePoolPort.addFile` at 167. `ProcessRunServiceImpl` still calls `qxpsCallerService.render()` unconditionally (outside the `!isModeDegrade()` guard), which targets `gabarit.getFilePoolPath()` → empty/error output.
- **Root cause:** Early return short-circuits the mandatory upload. .NET `Run.cs:92` calls `Addfile` **unconditionally** before the degrade check; degrade only gates the DID fetch/parse (and a trace log).
- **Fix:** Move the upload above the size-limit check (using `getFilePoolPath()` per C1), then for the oversized branch set `modeDegrade=true` and `return` (skipping only the DID fetch/parse):
  ```java
  if (this.gabarit == null) return;
  filePoolPort.addFile(this.gabarit.getFilePoolPath(), this.gabarit.getData());
  if (this.gabarit.getData().length > sizeLimitBeforeFailSoft) {
      log.warn(...); this.runProperties.setModeDegrade(true); return;
  }
  String xml = documentIdentityPort.fetchXmlForBox(this.gabarit.getFilePoolPath(), "DID");
  ...
  ```

### Theme B — Compartiment & Dynamique task structure

**C3. Anchor resolution is a stub returning empty `DBlocInfo` — every INCORPORATE render throws "Anchor not found"**
- **File:** `domain/task/TaskAnchor.java:45-47` (`getBlocInfo` stub); reached via `:63-76` and `CompartimentTaskProcessStrategy.java:283-284`, `DynamiqueTaskProcessStrategy.java:596/1106/1118`
- **Scenario:** Any `TaskCompartiment` in INCORPORATE / GENERATE_AND_INCORPORATE, and dynamic-report rendering. `getStartAnchor()` → `getBlocInfo(name)` returns `new DBlocInfo()` (uid=""), then `getAnchorInfo` throws `IllegalStateException("Anchor not found in document")`.
- **Root cause:** `getBlocInfo` is a placeholder never overridden by any subclass. .NET `Task_Base.Get_Bloc_Info` delegates to `this.Run.Gabarit.XML.GetBlocInfo(boxName)`.
- **Fix:** Implement in `TaskAnchor`:
  ```java
  protected DBlocInfo getBlocInfo(String blocName) {
      return this.getRun().getGabarit().getQxpXml().getBlocInfo(blocName);
  }
  ```
  Add a null-guard on `getGabarit()`/`getQxpXml()` for a diagnosable error. (Note: depends on the gabarit XML being loaded — see H10.)

**C4. `addRunBlocs` reads the child's TEMPLATE gabarit instead of the generated final QXP**
- **File:** `service/task/impl/CompartimentTaskProcessStrategy.java:322-323, 332`
- **Scenario:** GENERATE / GENERATE_AND_INCORPORATE. `runProcessor()` returns a Run whose `getGabarit()` is the input template and whose `getResult().getFinalQxp()` is the generated output. `addRunBlocs` fetches the project from `childRun.getGabarit().getFilePoolPath()` → parses the template (no dynamic data, original anchors).
- **Root cause:** .NET uses `child_Run.Result.Final_QXP.QXPProject`; the Java port substituted the template path, and the guard wrongly requires `getGabarit()!=null`.
- **Fix:** Change the guard (322-323) to validate `childRun.getResult().getFinalQxp().getFilePoolPath()` only (drop the gabarit requirement), and change line 332 to `getDocumentProjectBusiness.getProject(childRun.getResult().getFinalQxp().getFilePoolPath())`. Verify the generated DF_ QXP bytes are added to the pool before `getProject` (mirror `loadPreviousChild`'s `filePool.addFile` at line 243).

### Theme C — Load chain: gabarit_template

**C5. `Gabarit_Template` document never loaded; dynamic tasks clone from the wrong/empty source**
*(merges the LoadTemplatesBusiness gap with TaskDynamique.prepare uploading the wrong document — see also H8)*
- **File:** `business/LoadTemplatesBusiness.java:32-55`; `domain/task/TaskDynamique.java:40-41`
- **Scenario:** Any run with a dynamic task in TODO.
- **Root cause:** `LoadTemplatesBusiness` calls only `getTemplates()` (the list); `getGabaritTemplate()` is implemented but has **zero callers**, and `Run` has no `gabaritTemplate` field. `TaskDynamique.prepare()` then uploads `getRun().getGabarit()` (the source doc), not the template. .NET loads both `Get_Gabarit_Template` and `Load_Templates` and `Task_Dynamique.Prepare` uploads `Gabarit_Template.FilePoolPath`.
- **Fix:** (1) Add `DocumentDomain gabaritTemplate` to `Run`. (2) In `LoadTemplatesBusiness.execute`, when `idGabaritTemplate != Integer.MIN_VALUE`, call `getGabaritTemplateDao.getGabaritTemplate(idGabaritTemplate)` and `run.setGabaritTemplate(...)`. (3) Fix `TaskDynamique.prepare()` to upload `getRun().getGabaritTemplate()` (with a null-guard mirroring .NET `MSG_Gabarit_Template_NULL`). (4) Ensure `filePoolPath` is populated on the template document.

### Theme D — DAO runtime (PL/SQL associative arrays)

**C6. `Insert_Data` array params bound as `OracleTypes.ARRAY` against PL/SQL `INDEX BY` associative arrays — binding fails at runtime**
- **File:** `infra/dao/impl/InsertDataStorageDaoImpl.java:43-46, 55-58`
- **Scenario:** Any run with store_data enabled (SQL or DOCUMENT).
- **Root cause:** `QXP_PK_COMMON.VarCharArray` is `TABLE OF VARCHAR2(4000) INDEX BY BINARY_INTEGER` (package associative array), not a schema-level SQL collection. `OracleTypes.ARRAY`/`createOracleArray` cannot bind it (ORA-00902 / PLS-00306). .NET bound via ODP.NET `PLSQLAssociativeArray`.
- **Fix:** Bind via the Oracle PL/SQL index-table API. Drop `SimpleJdbcCall` for these calls; use a `CallableStatementCreator` unwrapping to `OraclePreparedStatement.setPlsqlIndexTable(idx, arr, maxLen, curLen, OracleTypes.VARCHAR, 4000)` per VARCHARARRAY param. Keep the length-0/null guard.

**C7. `Insert_Run_Errors` p_messages/p_categories — same associative-array binding failure**
- **File:** `infra/dao/impl/EndRunDaoImpl.java:88-105`
- **Scenario:** Run finalization when errors exist — the entire error-persistence path (QXP_RUN_ERROR) throws, masking the original failure.
- **Root cause:** Same as C6; additionally `p_categories` is an `int[]` primitive which cannot be passed as an Oracle ARRAY even for a real collection type.
- **Fix:** Same `setPlsqlIndexTable` approach — VARCHAR for messages, NUMERIC for categories (convert `int[]`→`Integer[]`/`Number[]`). Mirror .NET's null→"aucun" sentinel handling.

> **Batch C6/C7 together** — identical root cause, shared fix pattern.

---

## HIGH

### Degrade-mode / load-chain gaps (companions to C2)

**H1. `load()` runs InParams/Tasks/Templates even in degrade mode — wasted work + spurious ERROR**
*(merges the two duplicate findings on ProcessRunServiceImpl load + degrade)*
- **File:** `service/impl/ProcessRunServiceImpl.java:162-183`
- **Scenario:** Oversized gabarit sets `modeDegrade` during `prepareGabarit`; `load()` still calls `getInParamsBusiness.execute`, `loadTasksService.loadTasks`, `loadTemplatesBusiness.execute`. Any throw (e.g. missing ID_Gabarit_Template) flips the run to ERROR instead of completing as a degraded render.
- **Root cause:** Missing degrade guard. .NET `Run_Base.Load` wraps these in `if (!Mode_Degrade)`.
- **Fix:** Wrap the three steps after `prepareGabarit` in `if (!run.getRunProperties().isModeDegrade()) { ... }`.

**H2. Mode_Degrade skips the gabarit pool upload but Render still needs the pooled document**
- Duplicate of **C2** from the load-chain area; resolved by the same fix.

**H3. Full gabarit XML never loaded during load; only box-scoped DID XML is fetched**
- **File:** `domain/Run.java:170-176`
- **Scenario:** `prepareGabarit` fetches only the DID box fragment; `gabarit.qxpXml` stays `QxpXml.EMPTY` until `CheckServiceImpl` loads it much later. Every Prepare/Process consumer of `getQxpXml()` (TaskBase getPageNum/getLayoutName, BlocPage getNbBox, RunTaskStep, QxpsModifier, DocumentTaskProcessStrategy, DidTaskPostProcessStrategy, ProcessSqlBusiness) gets EMPTY → silent wrong page/layout/box-count math.
- **Root cause:** .NET `Document.XML` lazily loads and caches the **full** doc XML; Java loads only a DID fragment and `getQxpXml()` returns EMPTY (non-lazy) when null.
- **Fix:** After the pool upload in `prepareGabarit`, fetch and set the full XML (e.g. `gabarit.initXmlFromContent(getGabaritXmlBusiness.fetchXml(gabarit.getFilePoolPath()))`), passing the capability in as a port. Respect mode-degrade (skip when degraded). Keep `CheckServiceImpl.refreshGabaritXml` for the post-execution refresh.

**H4. GABARIT source / missing DID throws NPE/IllegalArgument; .NET tolerates an empty identity**
*(merges the two DocumentIdentityService NPE-on-missing-DID findings)*
- **File:** `infra/interop/qxps/identity/DocumentIdentityService.java:123, 139-154`; called from `Run.java:171-172`
- **Scenario:** A fresh template (no DID box) or any gabarit whose DID box is absent/empty/short. `getElementValueByIdName` returns null → `parseDocumentIdentity` fails `requireNonNull` / empty / `<6 parts` → run preparation aborts.
- **Root cause:** .NET `GetValue` returns `string.Empty` (never null) and `Document_Identity(string)` populates fields only when `Split('|').Length >= 6`, otherwise leaves defaults with no throw (`Is_Defined=false`).
- **Fix:** (1) `getElementValueByIdName` returns `""` not null when no match. (2) Make `parseDocumentIdentity` lenient: no throw on null/empty/`<6` parts; populate fields only when `parts.length >= 6` (unit code at `>= 7`); make `parseDateTime` tolerant (return null/default). Add an `isDefined()` flag to mirror `Is_Defined`.

### Pool-path / per-run isolation

**H5. Modify XML uploaded to pool ROOT without `R_<id>/` scoping — cross-run collision**
*(merges the two QxpsCallerBusiness modify-path findings; the MEDIUM duplicate folds in here)*
- **File:** `business/QxpsCallerBusiness.java:150-157`
- **Scenario:** Any directCall step with structural modifications (PAGINATION/MODIFY). Modify file named `Modify_<HHmmssSSS>.xml` with no `R_<id>/` prefix → two concurrent runs colliding on the same millisecond overwrite each other's modify file.
- **Root cause:** .NET uses `QXPS_File_Manager.GetPoolPath(...)` to prepend `R_<id>/`.
- **Fix:** `String modifyFileName = run.getRunProperties().getPoolPath(String.format(MODIFY_NAME_PATTERN, ...));` used for both the upload and the `ModifyMessage` reference. (`run` is already a parameter.)

### Number/date formatting (output correctness)

**H6. INT value formatting drops thousands separators**
- **File:** `domain/helper/DataTypeHelper.java:35-36, 50-58`
- **Scenario:** VALUE mode, dataType=INT, e.g. 1234567.
- **Root cause:** .NET `GetStringInt` uses `"n"` format (grouped, `1 234 567` fr-FR); Java `formatInteger` returns `String.valueOf(val)`.
- **Fix:** Format with `new DecimalFormat("#,##0", new DecimalFormatSymbols(Locale.FRANCE))`. Keep the `(val==0 && !showZero)→nullString` guard.

**H7. `decimal_significative=false` does not suppress trailing zeros**
*(merges the HIGH sql-task finding with the MEDIUM duplicates; rounding sub-claim is a false alarm — keep HALF_EVEN)*
- **File:** `domain/helper/DataTypeHelper.java:60-81`
- **Scenario:** DECIMAL/CURRENCY/POURCENTAGE with `decimalSignificative=false`, nbDecimal=2, value 12.50 → expected `12,5`.
- **Root cause:** .NET passes the flag as `fixedPattern`: true→`#,##0.00`, false→`#,##0.##`. Java always builds `'0'*nbDecimal`.
- **Fix:** Build `DecimalFormat(Locale.FRANCE)`; `setMaximumFractionDigits(nbDecimal)`, `setMinimumFractionDigits(decimalSignificative ? nbDecimal : 0)`. **Leave default HALF_EVEN rounding** (matches .NET `Decimal.ToString`); do NOT switch to HALF_UP.

**H8. CURRENCY / POURCENTAGE output omit the currency symbol and the ` %` suffix**
*(merges the HIGH sql-task finding with the two MEDIUM system-task duplicates)*
- **File:** `domain/helper/DataTypeHelper.java:37-40, 60-81`
- **Scenario:** dataType=CURRENCY or POURCENTAGE.
- **Root cause:** All three types route to bare `formatDecimal`. .NET `GetStringCurrency` appends ` <CurrencySymbol>`; `GetStringPourcentage` multiplies by 100 (the `%` specifier) and appends a literal ` %` (yielding the quirky `15,00 % %`).
- **Fix:** Split the switch. CURRENCY: `formatDecimal(...) + " " + currencySymbol` (from `DecimalFormatSymbols(Locale.FRANCE)` or run culture); guard nullString. POURCENTAGE: decide with stakeholders whether to reproduce .NET's verbatim x100 + double-`%` or the corrected single ` %`. Keep DECIMAL bare.

### Pagination / template structure

**H9. Double-page "prepare step" creation branch is missing — multi-task page creation without deletion is mis-paginated**
- **File:** `domain/RunTaskStep.java:206-321` (dead at 222 and 318-320)
- **Scenario:** `nbPageBySpread == PAGINATION_DOUBLE`, `minCreationPageId > 1`, first created page on the wrong side, and the task removes **no** pages.
- **Root cause:** Java collapsed `.NET`'s nested branch to `if (minCreationPageId>1 && nbPageSupprimer>0)` and dropped the no-deletion `else`. `localPrepareStep` is built but never assigned to `this.prepareStep`, so `getPrepareStep()` is always null and `QxpsCallerBusiness.process:79` is dead.
- **Fix:** Port the full nested structure (see issue body for the exact block): build the PA page (CREATE, `createNextDummyPage=true`) into `prepareStep.getBlocsModify()`, assign `this.prepareStep = localPrepareStep`, add the PR page (REMOVE) to `this.getBlocsModify()`, shift blocs, `nbPageCreer++`. Add method-scope `preprareOffsetTotal`. Delete the dead no-op at 317-320.

**H10. Unknown boxRef / sub-group in a TGroup is logged-and-skipped, never recorded as a Run error**
*(merges TGroup.java:142-145 unknown-boxRef, the QxpProject "dead logError path" finding, and the TGroup sub-group MEDIUM)*
- **File:** `domain/element/TGroup.java:142-145, 158-176`; `domain/project/QxpProject.java:211-226`
- **Scenario:** A template TGroup whose boxRef is unknown, or that contains a nested sub-group. Java only `log.error`/`log.warn` and continues → wrong geometry / missing boxes, run completes "clean". The caller's `RunError(2, ...)` recording in `evaluatePendingGroups` is dead code because `evaluate()` never throws.
- **Root cause:** .NET `EvaluateBoxes` throws `Exception_TElement(TGroupUnKnownSubGroup)` / `(TGroupSubGroupProblem)`, which `QXP_Project.Analyse` converts to a Critique run error.
- **Fix:** Introduce a `ExceptionTElement` runtime type. Throw it for the unknown-boxRef case (aborting the group, matching .NET) and for `if (subGroup)` after the loop. `evaluatePendingGroups`' existing catch then records the CRITIQUE RunError.

### Timeouts, type guards, mappers, enums

**H11. QXPSM request timeout defaults to 30s vs .NET's effective 1 hour**
- **File:** `infra/interop/qxpsm/QxpsmSoapClient.java:95-96`; `application.yaml:65`
- **Scenario:** Any directCall=false UPDATE step whose modifier/render chain exceeds 30s.
- **Root cause:** `application.yaml` sets `qxpsm.soap.timeout: 30000` (>0), so the 1h fallback at line 96 is dead. .NET leaves `RequestTimeout` unset → 3600000 plus `service.Timeout = Infinite`.
- **Fix:** Set `application.yaml` `timeout: 3600000`. Companion: ensure the Axis stub socket/read timeout is unbounded or ≥ 1h.

**H12. Mode-degrade flagged for ALL document types; .NET only flags QXP**
- **File:** `business/LoadTaskDocumentsBusiness.java:195-201` (called at 97, 153)
- **Scenario:** A large PDF/IMG reference document over the size limit → task skipped with a CRITIQUE fail-soft, no insertion produced.
- **Root cause:** `markModeDegradeIfTooBig` has no type guard. .NET `Document.Evaluate_Mode_Degrade` returns the size check only when `Type==QXP`.
- **Fix:** `if ("QXP".equalsIgnoreCase(doc.getFormat()) && doc.getData()!=null && doc.getData().length > sizeLimit) { doc.setModeDegrade(true); ... }`.

**H13. Multi-page PDF pages 2..N get no position when POSITION_IMAGE is NULL**
- **File:** `service/task/impl/DocumentTaskProcessStrategy.java:250-254, 308-314`
- **Scenario:** Multi-page FILE_PDF task with `POSITION_IMAGE` NULL (common). `imagePosition` stays null → per-page position block skipped → pages render at wrong location.
- **Root cause:** Java lazy-inits `imagePosition` only when `positionValues != null`. .NET always constructs `Task_Image_Position(task.Position_Values)`, whose ctor falls back to the default `"42,52;56,693;552,756;785,197"`.
- **Fix:** Construct `imagePosition` unconditionally (the ctor already maps null→DEFAULT) and drop the `imagePosition != null` clause from the loop guard. (The offset path is behavior-neutral — optional cleanup.)

**H14. `Insert_Data` array binding (DAO)** — duplicate of **C6** (the HIGH-rated copy); resolve once.

**H15. DATE_TIME (type 5) in-param bound as date-truncated `java.sql.Date` instead of raw string**
*(merges the HIGH InParamSqlMapper finding with the MEDIUM DATE_TIME and DATE duplicates)*
- **File:** `mapper/InParamSqlMapper.java:28-33, 43-46`
- **Scenario:** DATE_TIME (5) or DATE (4) in-param with a non-midnight time fed into Task_SQL.
- **Root cause:** .NET converts only INT/DECIMAL/Date(4) typed; DateTime(5) binds the raw string. Java converts both 4 and 5 to `java.sql.Date`, dropping time. Even DATE(4) loses time (.NET keeps full DateTime).
- **Fix:** DATE(4) → `java.sql.Timestamp` (parse `M/d/yyyy HH:mm:ss`, time-preserving). DATE_TIME(5) → bind the raw string (.NET default branch) or `Timestamp`. Change the condition at line 28 to `type == DATE` only; do not special-case DATE_TIME with `toSqlDate`.

**H16. `Absolute_Repeat_Type` modeled as fixed enum instead of [Flags] — combined values crash template load**
- **File:** `enums/AbsoluteRepeatType.java:9-67`; `TemplateMapper.java:37`; `DynamiqueTaskProcessStrategy.java:699-726`
- **Scenario:** ABSOLUTE_REPEAT = 3/5/6/7 (combined flags). `fromValue` throws `IllegalArgumentException` → template load crashes; even without the throw, a cell can't report both `hasFirstPage()` and `hasOtherPage()`.
- **Root cause:** .NET is `[Flags]`, parsed with `ToEnum` (accepts any bit combo), consumed bitwise.
- **Fix:** Store the raw int bit-field; `fromValue` must not throw on unmatched values; route `has*()` through `(value & 0x01/0x02/0x04)`; replace the consumer's `== DEFAULT` checks with `value==0`. Add a unit test for `fromValue(0..7,255)`.

---

## MEDIUM

### Mode-degrade edge cases & template degrade

**M1. gabarit_template size never triggers degrade**
- **File:** `domain/Run.java:159`
- **Root cause:** Java computes degrade from the gabarit only; .NET ORs over gabarit + gabarit_template. (Depends on C5 loading the template document.)
- **Fix:** After loading the template (C5), OR its size check into `setModeDegrade` before the degrade gates in `load()`.

**M2. NPE when fetched gabarit has null `data` at the degrade size check**
*(merges the two null-data findings on Run.java:159)*
- **File:** `domain/Run.java:159`
- **Scenario:** Gabarit row with NULL `contenu` BLOB → `getData().length` NPEs → run flips to BLOQUANTE ERROR.
- **Root cause:** Unguarded dereference. .NET guards with `Validation.IsSet(this.Data)` (returns false → not degraded).
- **Fix:** `if (gabaritData != null && gabaritData.length > sizeLimit) {...}` (optionally with the `"QXP".equalsIgnoreCase(format)` guard per L-enums).

**M3. `load()` runs in-params/tasks/templates in degrade mode** — duplicate of **H1** (load-chain copy); resolve once.

### QXPSM / SOAP wire parity

**M4. QXPSM `maxRetries` always forced to 3; .NET leaves the SDK default (0)**
- **File:** `infra/interop/qxpsm/QxpsmSoapClient.java:93`
- **Fix:** Default `maxRetries` to 0 in `QxpsmProperties`/`application.yaml` AND guard `if (getMaxRetries() > 0) context.setMaxRetries(...)`.

### Number formatting (system-task duplicates of H7/H8)

**M5/M6/M7.** CURRENCY symbol omitted, POURCENTAGE ` %` omitted, `decimal_significative=false` trailing zeros — all **duplicates of H7/H8**. Fix in the same `DataTypeHelper` edit.

### SQL-task error observability

**M8. Duplicate bloc in SQL result only logged, not recorded as a Run error**
- **File:** `business/ProcessSqlBusiness.java:77-80`
- **Fix:** `task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED, "ErrorDuplicateBlocInTask: ..."))` then `continue`. **Use UNSPECIFIED (1), not CRITIQUE** (matches .NET `Errors.Add(string)` and the sibling `QxpPreviousTaskProcessStrategy` port).

**M9. Per-row exception logged but not recorded as a Run error**
- **File:** `business/ProcessSqlBusiness.java:92-94`
- **Fix:** In the catch, add `RunError(RunError.UNSPECIFIED, "ErrorAddingBlocSQLInTask: ...")`. (Fix M8/M9 together.)

### Document/system/DID/compartiment error observability

**M10. PDF with no existing gabarit blocs returns silently; .NET records a run error**
- **File:** `service/task/impl/DocumentTaskProcessStrategy.java:231-235`
- **Fix:** Before the silent return, add `RunError(RunError.UNSPECIFIED, "...MissingDestinationBlocNameInTask")`. Also apply to the blank-destinationBlocName guard at 65-67.

**M11. Unknown compartiment mode logs and returns instead of raising a task exception**
- **File:** `service/task/impl/CompartimentTaskProcessStrategy.java:104-107`
- **Fix:** Throw (e.g. `IllegalStateException`) so `ProcessTasksServiceImpl`'s try/catch records a CRITIQUE RunError + `setInError(true)`; or record CRITIQUE + `setInError(true)` directly.

**M12. Group containing a sub-group only warns** — folded into **H10**.

**M13. SystemTask missing destinationBlocName does not register a Run error** — see **L8** (LOW); but if grouped with M10, same UNSPECIFIED-RunError fix.

### Dynamique store flag

**M14. `storeData` uses enum equality instead of bitwise flag test**
- **File:** `service/task/impl/DynamiqueTaskProcessStrategy.java:251-254`
- **Fix:** `task.isStoreData() && task.getRun().getRunProperties().getStoreDataType().hasFlag(StoreDataType.SQL)`. **Requires the `StoreDataType.fromCode` fix (C-combined) so 0x03 doesn't collapse to NONE.** (Same root family as the CRITICAL StoreDataType issue below.)

### DID lenient parsing (companions to H4)

**M15. `parseDocumentIdentity` throws on `<6` parts** — covered by **H4**.

**M16. Strict `MM/dd/yyyy HH:mm:ss` date parsing throws where .NET falls back to MinValue**
- **File:** `infra/interop/qxps/identity/DocumentIdentityService.java:185-197`
- **Fix:** Make `parseDateTime` non-throwing and lenient: empty/null → MinValue sentinel; tolerant formatter (`M/d/yyyy H:mm:ss`); parse failure → sentinel, log debug. Treat the sentinel as "unset" downstream.

### XML / xpath counting & sentinels

**M17. Table-cell boxes never counted in `getProjectInfo` (`Attr.getParentNode()` is always null)**
- **File:** `domain/xml/QxpXml.java:483-499`
- **Fix:** Reach the TABLE element via `((Attr) pageAttr).getOwnerElement()` (the GEOMETRY element) then `getParentNode()`, or select `//TABLE/GEOMETRY` (element) and read `@PAGE`. Makes `findCellIds` execute. Remove the unused constant at 105-107.

**M18. `getPageNum` returns 0 for a not-found bloc; .NET returns `int.MinValue`**
- **File:** `domain/xml/QxpXml.java:309-322`
- **Fix:** Return `Integer.MIN_VALUE` (not 0) when the cleaned pageID is blank/unparseable, to preserve downstream arithmetic and the missing-bloc signal. Update the javadoc.

### DAO robustness / mappers / persistence

**M19. Insert_Document / EndRun / InsertDataStorage SimpleJdbcCalls omit `withoutProcedureColumnMetaDataAccess()` and rebuild per call**
*(merges InsertDocumentDaoImpl, EndRunDaoImpl, and the LOW DAO copies)*
- **File:** `infra/dao/impl/InsertDocumentDaoImpl.java:36-53`; `EndRunDaoImpl.java:32-45,65-74,91-98`; `InsertDataStorageDaoImpl.java`
- **Root cause:** Metadata access enabled → dictionary query per call (fails in locked-down prod accounts; FUNCTION return-param risk). All read DAOs and `AuditDaoImpl` disable it.
- **Fix:** Add `.withoutProcedureColumnMetaDataAccess()` to every SimpleJdbcCall; move construction to a `@PostConstruct`/constructor field. Keep explicit `declareParameters`.

**M20. `Get_Compartiment_Runs` swallows all exceptions and returns empty map**
- **File:** `infra/dao/impl/GetCompartimentRunsDaoImpl.java:116-119`
- **Root cause:** Java catch reclassifies a DB/cursor failure as the benign "0 rows" business outcome (`NoneRunCompartiment` critique). .NET has no catch — failures propagate.
- **Fix:** Remove the catch (or rethrow as RuntimeException after logging) so infra failures fail the run, preserving the DB-error vs no-rows distinction.

**M21. DATE_TIME / DATE in-params truncated** — duplicates of **H15**.

**M22. INT/DECIMAL params bound as raw strings instead of typed numeric values**
- **File:** `mapper/InParamSqlMapper.java:31-32`
- **Root cause:** .NET binds native int/decimal via invariant culture; Java relies on Oracle implicit string→number (fails under non-default NLS or grouped/space values).
- **Fix:** Parse INT→Long, DECIMAL→BigDecimal with `Locale.ROOT`/'.' (strip spaces), mirroring `ConversionInvariante`; on failure fall back to the .NET MinValue sentinel or raw string.

**M23. `parseIndexLignes` throws `NumberFormatException` on non-numeric INDEX_LIGNES token**
- **File:** `mapper/TaskExceptionMapper.java:40-43`
- **Root cause:** Direct `Integer::parseInt`; .NET `ToIntArray`/`ToInt` is tolerant (bad token → MinValue, keeps array length).
- **Fix:** Per token: trim + strip internal spaces, parse; on failure → `Integer.MIN_VALUE` (do not drop). Reconsider the `!isBlank()` filter so blank tokens still produce entries (preserves LINE-vs-TABLE classification).

**M24. Audit DURATION computed in seconds vs .NET TimeSpan.Milliseconds component**
*(merges the MEDIUM and LOW duplicate)*
- **File:** `infra/dao/impl/AuditDaoImpl.java:51-53, 62`
- **Root cause:** .NET stores the 0-999 ms component (itself a latent bug); Java stores whole seconds.
- **Fix:** Decide the semantic explicitly. Recommended: `Duration.between(start,end).toMillis()` (true total) with a comment noting the deviation; or `toMillisPart()` for strict parity. Do not keep `getSeconds()`. Fix the misleading comment.

**M25. Missing template-ID silently skipped instead of raising Bloquante; no dynamic-task gating**
- **File:** `business/LoadTemplatesBusiness.java:35-38`
- **Root cause:** .NET raises Bloquante `Exception_Run(MSG_Missing_ID_Gabarit_Template)` when a dynamic task exists but the ID is unset, and skips loading entirely when no dynamic task exists.
- **Fix:** Gate on "any `TaskDynamique` present". If present + ID unset → BLOQUANTE RunError (interrupt the run). If no dynamic task → return without loading.

**M26. `generateFileNames` lowercases the format extension; .NET uses it verbatim**
- **File:** `domain/DocumentDomain.java:275-279`
- **Root cause:** Java `this.format.toLowerCase()` → `DF_<id>.qxp`; .NET (and all five Java load-path DAOs and `getNewGabaritNameExt`) use the format verbatim → `DF_<id>.QXP`. Diverges on case-sensitive stores; internally inconsistent.
- **Fix:** Remove `.toLowerCase()` at line 277.

---

## LOW

**L1. Missing process strategy swallowed silently** (`service/task/impl/TaskProcessServiceImpl.java:32-37`) — latent (all 7 task types covered). Throw `IllegalStateException` so Pass-1 records a CRITIQUE RunError. Optionally add a boot-time assertion.

**L2. Redundant `RunTask` creation before re-processing** (`service/impl/CheckServiceImpl.java:182`) — dead code; delete line 182.

**L3. Double gabarit XML refresh when overflow re-processing ran and DOCUMENT storage enabled** (`CheckServiceImpl.java:67-70`) — redundant QXPS round-trip. Guard line 69 to skip when `checkOverflow` already refreshed at 188.

**L4. Early return on zero overflow boxes skips the `Todo=false` sweep** (`CheckServiceImpl.java:136-138`) — latent (nothing reads `Todo` after Check). Move the sweep out of the `!tasksToReprocess.isEmpty()` guard and run it unconditionally inside the Control_Overflow branch.

**L5. Modify file timestamp `HHmmssSSS` vs .NET `HHmmssff`** (`QxpsCallerBusiness.java:43`) — cosmetic; optionally `ofPattern("HHmmssSS")`.

**L6. Response text/binary classification uses `startsWith` vs .NET exact equality** (`QxpsHttpClient.java:124,163-167`) — strip parameters, compare bare media type for equality (keep empty→text).

**L7. HTTP protocol version not forced to 1.0** (`QxpsHttpClient.java:51-56`) — reactor-netty can't force 1.0; confirm QXPS accepts 1.1 and document the deviation (optionally `keepAlive(false)` + explicit Content-Length).

**L8. Null `textValue` renders literal `"null"` in ParamsValue query** (`infra/interop/qxps/message/ParamsValueMessage.java:40`) — coalesce: `nv.getTextValue() != null ? nv.getTextValue() : ""`.

**L9. Missing run-error when a bloc has no layout/spread** (`domain/modifier/QxpsModifier.java:180-185`) — add `RunError(RunError.UNSPECIFIED, "Empty_Layout_Or_Spread_For_Bloc: ...")` before returning null. **Do NOT change run status** (.NET records Unspecified, non-status-affecting).

**L10. QXPSM userName/userPassword never set → serialized as nil** (`QxpsmSoapClient.java:86-96`) — `context.setUserName(""); context.setUserPassword("");`.

**L11. `getProject` doesn't set mode-degrade on DOM-fetch failure** (`business/GetDocumentProjectBusiness.java:31-39`) — flip degrade at the caller `LoadTaskDocumentsBusiness.loadQxpSource`: if `getProject` returns `QxpProject.EMPTY`, `doc.setModeDegrade(true)`. (No caching/short-circuit change needed.)

**L12. QXPSM `connectionTimeout`/`retryBackoffInterval`/`namespace` configured but never applied** (`QxpsmProperties.java:18-22`) — remove the dead keys (recommended) or wire them (connection timeout on the Axis stub; implement an actual retry-with-backoff loop).

**L13. SystemTask missing destinationBlocName only logs** (`service/task/impl/SystemTaskProcessStrategy.java:29-31`) — add `RunError(RunError.UNSPECIFIED, "...MissingBlocNameInTask " + task.getDebugInfo())`.

**L14. Date/DateTime patterns hardcoded instead of run-configurable** (`DataTypeHelper.java:17-18`) — add `Run_DatePattern`/`Run_DateTimePattern` config keys (defaults unchanged) and build formatters from them.

**L15. Due-date emitted empty when `dateEcheance` is null** (`domain/helper/DocumentIdentityHelper.java:50-51`) — emit `LocalDate.of(1,1,1).atStartOfDay()` ("01/01/0001 00:00:00") to match .NET MinValue, or document the deviation.

**L16. Default previous report type loses out-of-range DB code; rejects negative explicit values** (`LoadTaskDocumentsBusiness.java:164-181`) — carry the raw `id_type_rapport` int; change `parsed > 0` to `parsed != 0`.

**L17. Returned `DocumentDomain.idLangue` left null** (`GetDocumentDaoImpl.java:86-96`, `GetLastQxpCertifieDaoImpl.java:74-84`) — call `setIdLangue` (thread the param, or default to 1). Harmless today.

**L18. `newBlocName()` omits .NET's `[...]` brackets** (`domain/helper/TElementHelper.java:249-252`) — wrap in brackets only if golden-file parity needed; else document.

**L19. `updatePosition(TGroup)` returns ZERO for unparseable position vs .NET decimal.MinValue** (`TElementHelper.java:406-421`) — Java's ZERO is saner; do not regress. Optionally fail-fast on non-numeric position.

**L20. `BlocPage.getNbBox()` REMOVE path swallows exceptions and returns 1** (`domain/bloc/BlocPage.java:44-58`) — remove the try/catch (the chain is null-safe and returns 0 for missing pages); add explicit null-guards that surface the precondition instead of masking as 1.

**L21. Pastboard/page-0 boxes excluded from counts (`currentPage>0` vs .NET IsSet)** (`QxpXml.java:472-499`) — use an `UNSET=Integer.MIN_VALUE` sentinel from the parse helper and guard with `!= UNSET` (includes page 0); only page-0 tables affect NbBox.

**L22. Page parsing rejects decimal/spaced values .NET accepts** (`QxpXml.java:316-317,666-675`) — add a `ConversionInvariante.ToInt`-equivalent helper (strip spaces, normalize comma, `BigDecimal` truncate); use at all page-parse sites. Optional parity hardening.

**L23. `getBlocInfo` reads only direct POSITION children; .NET reads all descendants** (`QxpXml.java:375-399`) — iterate descendant elements (`.//*`) instead of `getChildNodes()`.

**L24. `evaluateNodeListAsStrings` drops blank/whitespace names** (`QxpXml.java:610`) — drop the `!value.isBlank()` check; keep null-only guard.

**L25. Null element name produces a null map key instead of aborting** (`domain/project/QxpProject.java:135/162/192`) — add a null-name guard (`continue` + debug log) in processBoxes/Tables/Groups; optionally record a RunError when `logError`.

**L26. Audit END_STATUS casing differs (UPPER_SNAKE vs PascalCase)** (`AuditDaoImpl.java:63`) — map `RunStatus`→`ToGenerate/Generated/Error/Running` via a `getNetStatusLabel()` accessor.

**L27. `GetDocumentByIdDaoImpl` hardcodes format "QXP"** (`:73`) — read `rs.getString("format")`, uppercase, fall back to "QXP" only when null/blank. Latent.

**L28. Unknown-task-type warning logs coerced enum (SYSTEM) instead of raw code** (`mapper/TaskMapper.java:60`) — thread `idTypeTache` into the log. Diagnostic-only.

**L29. Empty store list skips the QXP_DATA_STORAGE cleanup DELETE** (`business/EndRunBusiness.java:134-160`) — remove the `!isEmpty()` clauses and bind a single `{null}` array so the proc's defensive DELETE runs (parity with eos.framework empty-collection-as-{null}).

**L30. Audit message content differs from .NET buildAuditMessage** (`EndRunBusiness.java:104-111`) — reproduce `Nb Tasks/Nb Errors` + per-error format if forensic parity matters; else document.

**L31. NPE if `dateEcheance` null when inserting a generated document** (`InsertDocumentDaoImpl.java:61`) — `dateEcheance != null ? java.sql.Date.valueOf(dateEcheance) : null`. (p_date_document already declared `Types.DATE`.)

**L32. `changeDocument` doesn't recompute `fileFullPath`** (`domain/DocumentDomain.java:222-227`) — refresh the absolute path (pass a precomputed `newFileFullPath`), or set it to null to avoid a stale read. Latent.

**L33. Mode_Degrade size check missing the QXP-type guard** (`domain/Run.java:159`) — add `"QXP".equalsIgnoreCase(format)` (encapsulate as `DocumentDomain.evaluateModeDegrade(limit)` mirroring .NET, also covers the null-data guard of M2).

**L34. Misleading RunError severity comment** (`business/ProcessSqlBusiness.java:36`) — correct to `1=Unspecified, 2=Critique, 3=Bloquante`. Optionally reference `RunError.CRITIQUE` directly.

---

## Suggested Fix Batching

**Batch 1 — Gabarit pool key + mode-degrade core (CRITICAL, unblocks all rendering)**
C1, C2, plus H1/H3 (load-chain degrade guard + full-XML load), M2/M33 (null-data + QXP-type guards), M1 (template degrade). Single coordinated change to `Run.prepareGabarit` and `ProcessRunServiceImpl.load`.

**Batch 2 — gabarit_template load + Dynamique (CRITICAL/HIGH)**
C5 (add `Run.gabaritTemplate` field, wire `LoadTemplatesBusiness`, fix `TaskDynamique.prepare`), H16 (Absolute_Repeat [Flags]), M14 (storeData bitwise), M25 (template-ID Bloquante + dynamic gating).

**Batch 3 — Compartiment & anchor (CRITICAL)**
C3 (`TaskAnchor.getBlocInfo` real lookup — depends on Batch 1's full-XML load), C4 (addRunBlocs use final QXP).

**Batch 4 — StoreDataType [Flags] + DAO associative-array binding (CRITICAL/HIGH)**
StoreDataType combined-value fix (C combined: CheckServiceImpl + EndRunBusiness + RunPropertiesMapper, plus M14), C6/C7 (`setPlsqlIndexTable` for Insert_Data and Insert_Run_Errors).

**Batch 5 — DataTypeHelper number/date formatting (HIGH/MEDIUM, isolated)**
H6, H7, H8, M5/M6/M7, L14. One file, well-contained.

**Batch 6 — InParam typed binding (HIGH/MEDIUM)**
H15/M21 (DATE/DATE_TIME timestamp/string), M22 (INT/DECIMAL typed), M23 (parseIndexLignes tolerance).

**Batch 7 — Error observability (HIGH/MEDIUM/LOW)**
H10 (TGroup throw + QxpProject RunError), M8/M9 (ProcessSql), M10 (PDF), M11 (compartiment mode), M20 (Get_Compartiment_Runs propagate), L1, L9, L13, L25.

**Batch 8 — Pool isolation + QXPSM/SOAP (HIGH/MEDIUM/LOW)**
H5 (modify R_<id>/ prefix), H11 (timeout 1h), M4 (maxRetries), L5, L6, L7, L8, L10, L12.

**Batch 9 — Document-task geometry + type guards (HIGH)**
H9 (pagination prepare step), H12 (degrade only QXP), H13 (PDF default position).

**Batch 10 — DID lenient parsing (HIGH/MEDIUM)**
H4, M16 (DocumentIdentityService leniency + isDefined), L15.

**Batch 11 — DAO robustness + persistence (MEDIUM/LOW)**
M19 (withoutProcedureColumnMetaDataAccess), M24/L26 (audit duration + status), M26 (file extension case), L11, L17, L27, L29, L30, L31, L32.

**Batch 12 — XML/xpath counting + low-risk hardening (MEDIUM/LOW)**
M17 (table cells), M18 (page sentinel), L20, L21, L22, L23, L24.

**Batch 13 — Cleanup/cosmetic (LOW)**
L2, L3, L4, L18, L19, L28, L34.
