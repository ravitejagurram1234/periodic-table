# EOS Quark Engine — Validation Findings Report

**Scope:** static correctness validation of the Java engine (`new java repo/new/quark-engine`) against the .NET source (`QXP.Engine.Core` / `QXP.Interop`) and the authoritative Oracle package bodies (`ora.txt`). No live/smoke/debug testing — pure code correctness, transcription drift, and parity.

**Method:** five parallel validators (Oracle DAOs, pipeline lifecycle, task strategies, QXPS/QXPSM interop, wiring/arch), then **every CRITICAL/HIGH finding re-verified by hand** against the actual files. Two reported items were rejected as false positives after verification (see §4).

**Bottom line:** the port's *structure* is largely faithful and the DAO layer is an exact match — BUT there is one large functional gap discovered during the QXP_Previous port: **the task document-content loading subsystem is entirely unimplemented (F14)**, which silently disables every Document task (PDF/image/RTF/DOC/XTG/QXP-data insertion) *and* QXP_Previous. Beyond that: **(F1) Batch 8 was not applied** (arch test fails), **(F2/F14) DOC_QXP is unported**, and **(F3) error-severity codes are inverted**. Everything else is medium/low or a live-validation item.

> **Why the first sweep didn't flag F14:** each validator checked its own slice. The Document strategy *logic* is a correct port (agent confirmed MATCH) — but nothing ever populates `task.document`, so the correct logic never runs. The gap lives in the seam *between* "task prepare" and "strategy", which surfaced only when wiring QXP_Previous end-to-end.

---

## 0. 🔴🔴 F14 — Task document-content loading subsystem is NOT implemented (highest impact)

- **Evidence:** `task.setDocument(...)` has **zero call sites** in the entire repo (verified in both your repo and my working copy). The `toLoad` flag is set in `TaskDocument.prepare()`/`TaskQxpPrevious.prepare()` but **nothing ever reads it**. There is no document-loader service/business. So `task.getDocument()` is always null → every document strategy hits its `… has no document loaded, skipping` branch and **silently produces nothing**.
- **What's affected:** the whole **Document** task type — `FILE_PDF`, `FILE_IMG`, `FILE_DOC`, `FILE_RTF`, `FILE_XTG`, `FILE_QXP_DATA` — i.e. inserting external images/charts/logos, certified PDFs, RTF/DOC fragments, and previous-QXP data into templates. Plus **QXP_Previous** (F2). These are core to factsheet/KIID/report generation.
- **.NET reference (`Task_Document.Prepare()`):** when `(ToLoad || Todo) && Id_Sous_Categorie set`:
  1. `__doc = QXPS_File_Manager.Get_Document(Id_Sous_Categorie, ID_Fnd_Code, ID_Unit_Code, Societe, ID_Langue, Date_Echeance)` (6-arg, Oracle `QXP_PK_RUN.Get_Document` @ `ora.txt:8894`);
  2. `this.Document = __doc`;
  3. **PDF** → split into per-page PDFs (`PDF_Tools.Split_PDF`), set `doc.PDFFiles`, `Addfile` each page to the pool;
  4. **else (QXP_Data/DOC/RTF/XTG/IMG)** → `Addfile(doc.FilePoolPath, doc.Data)` (upload to pool);
  5. null → `Errors.Add(Document_Null, …)`.
- **What porting it requires (a small subsystem):**
  - a new `Get_Document` DAO (6 args) + business bridge (different from the existing `Get_Document_ByID`);
  - a **document-loading pipeline step** (the "delegated to business/service layer" the code comments promise) that iterates tasks during Prepare and loads+uploads to the pool **via the Quark API** (Kube constraint — `addFile`, not local files);
  - **PDF page-splitting** — .NET used `QXPIO.PDF_Tools`; Java has no built-in equivalent → needs a library (e.g. Apache PDFBox). **This is a "not identical in Java" item requiring your approval** (new dependency + behavior to match: same page count/order/content as .NET's splitter).
- **Severity:** CRITICAL — without it, document-insertion features don't work, regardless of how correct the strategies are.

---

## 1. Verified findings (action required)

### 🔴 F1 — Batch 8 (Rule-2 business-bridge refactor) is missing from this repo — arch test fails
- **Evidence:** `service/impl/QxpsCallerServiceImpl.java:8-13` and `service/impl/CheckServiceImpl.java:12-14` import `infra.interop.qxps.*` directly. There is **no** `business/QxpsCallerBusiness.java` or `business/GetGabaritXmlBusiness.java` in the repo.
- **Why it matters:** `CleanArchitectureLayersTest.services_should_not_depend_on_infra` (test line 23-27) fails → `mvn test` red. This is the pre-Batch-8 state.
- **Cause:** Batch 8 was delivered but not applied when this repo was assembled. (Batch 9/#17 *was* applied — confirmed.)
- **Fix:** Apply the Batch 8 deliverable (`EOS_Quark_Batch8_Changes.md`): create `QxpsCallerBusiness` + `GetGabaritXmlBusiness` in `business/`, make `QxpsCallerServiceImpl`/`CheckServiceImpl` thin delegators with no `infra` imports. Files are ready — no new design needed.

### 🔴 F2 — DOC_QXP task type (`TaskQxpPrevious` / .NET `Process_QXP_Previous`) is unported — silently does nothing
- **Evidence:** `mapper/TaskMapper.java:46-49` creates a `TaskQxpPrevious` for task-type `DOC_QXP`. But `service/task/impl/TaskProcessServiceImpl.java` registers only 6 strategies; `strategyMap.get(TaskQxpPrevious.class)` returns null → falls to `else { log.warn("No process strategy registered…") }` and **processes nothing**. There is no `QxpPreviousTaskProcessStrategy`.
- **.NET:** `Business/Task/Process_QXP_Previous.cs` has real logic (AddBlocs over `|`-split source/dest names, `.N{level}` hierarchy walking via `GetListBoxNameEndWith`, NullString substitution, TBox/TTable style copy).
- **Why it matters:** any template that uses a DOC_QXP (previous-QXP incorporation) task produces wrong output (that task is skipped) with only a log warning — no run error.
- **Action:** (Decided: port the full strategy.) NOTE — porting the strategy is **necessary but not sufficient**: it depends on **F14** (the previous-QXP document must be loaded + uploaded to the pool in `prepare()` via `Get_Last_Qxp_Certifie` before the strategy can read it). Oracle `Get_Last_Qxp_Certifie` (`ora.txt:8987`) takes **2 params** — `p_id_suivi`, `p_id_type_rapport` (langue is derived inside the SQL), not the 3 the .NET wrapper signature implies. So F2 = new `Get_Last_Qxp_Certifie` DAO + business + prepare-time load (part of the F14 subsystem) + the `QxpPreviousTaskProcessStrategy` (AddBlocs: `|`-split explicit mode and `.N{level}` hierarchy mode, ¤/U+00A4 position separator, NullString substitution, TBox/TTable style-copy via `TElementHelper`).

### 🟠 F3 — Error-severity codes are inverted vs .NET `Error_Type` (persisted to DB)
- **Evidence:**
  - `.NET Error_Type` = `Unspecified=1, Critique=2, Bloquante=3` (no "Warning").
  - `domain/RunError.java:13` documents `1=Bloquante, 2=Critique, 3=Warning` — **wrong** (1 and 3 swapped, "Warning" doesn't exist).
  - `service/impl/ProcessRunServiceImpl.java:99` (fatal top-level catch): `new RunError(1, …)` → writes **Unspecified(1)** where .NET writes **Bloquante(3)** (`Run_Base.Launch` generic catch → `Errors.Add(Error_Type.Bloquante, …)`).
- **Why it matters:** these codes are persisted via `QXP_PK_RUN.Insert_Run_Errors`; a fatal error is recorded as "unspecified" instead of "blocking". (Note: `CRITIQUE=2` is used correctly elsewhere, so only the 1↔3 cases are wrong today.)
- **Fix:** Correct the `RunError` doc/constants to `Unspecified=1, Critique=2, Bloquante=3`; change the top-level catch to `new RunError(3, …)`. Recommend introducing named constants (`RunError.BLOQUANTE/CRITIQUE/UNSPECIFIED`) and using them everywhere.

### 🟠 F4 — SaveAs absolute path: encoding + slash normalization (top live-validation risk, plus a real bug)
- **Evidence (encoding):** `infra/interop/qxps/.../QxpsRequestBuilder` builds the final URI with `…build().encode()`, which percent-encodes `\`→`%5C` and space→`%20` in `path=D:\Documents\R_<id>\`. .NET (`QXPS_Request_Message`) assigns to `UriBuilder.Path/Query` and sends the path **literally** (no `%5C`).
- **Evidence (slashes):** `domain/RunProperties.java:90` `getPoolPathAbsolute` = `String.format("%s/R_%d/%s", base, runId, file)` → with a Windows base this yields **mixed** slashes `D:\Documents/R_<id>/file`. .NET normalizes the absolute pool path to **all-backslash** (`QXPS_File_Manager.GetPoolPathAbsolute` / `SetPoolPath`).
- **Why it matters:** the QXPS host is Windows; the SaveAs `path=` value differs from .NET both in slashes and in encoding. This is the single most likely cause of a SaveAs failure against the real server.
- **Fix:** (a) normalize the pool path to backslashes (`.replace("/","\\")`) to mirror .NET; (b) do not blanket-`encode()` the SaveAs path — build the URI treating it as pre-encoded (`fromUriString(...).build(true)`) or encode only what .NET's `UriBuilder` would. **Validate against live QXPS** that the literal backslash path is accepted (this is the §2a item in the live-test guide).

### 🟡 F5 — "Task generates no bloc" error uses wrong severity
- `service/impl/ProcessTasksServiceImpl.java:116` adds `RunError(CRITIQUE=2, "…ne genere aucun bloc")`. .NET (`Run_Base.Process` pass 3, `Errors.Add(TaskSansBloc, …)`) defaults to **Unspecified(1)**.
- **Fix:** use severity `1` for this error.

### 🟡 F6 — Missing `RunInSafeMode` error when run is in degraded mode
- `ProcessRunServiceImpl` finally block (lines ~101-119) never records a degraded-mode error. .NET `Run_Base.Launch` finally: `if (Mode_Degrade) Errors.Add(Error_Type.Critique, RunInSafeMode)` before `End()`.
- **Fix:** in the finally, before `endRunBusiness.execute`, if `run.getRunProperties().isModeDegrade()` add `new RunError(2, <RunInSafeMode msg>)`.

### 🟡 F7 — Render error handling swallows QXP (and JPG) failures
- `service/impl/QxpsCallerServiceImpl` render wraps the **QXP** (and JPG) fetch in try/catch that only logs, so the run still ends `GENERATED`. .NET `QXPS_Caller.Render` guards **only PDF** (and there only swallows `QXPS_Exception`; re-throws other `Exception`). JPG (233-239) and QXP (265-269) are **unguarded** → failures propagate → run = ERROR.
- **Fix:** guard only the PDF block (swallow `QXPS_Exception`, rethrow others); let JPG/QXP failures propagate so the pipeline sets ERROR. (JPG is default-disabled, so its part is low impact — but QXP matters.)

### 🟡 F8 — New-gabarit filename extension forced lowercase
- `QxpsCallerServiceImpl.java:281,285` use `gabarit.getFormat().toLowerCase()`. .NET `QXPS_Caller.GetNewGabaritNameExt` uses `Format` **verbatim** (e.g. `.QXP`).
- **Why it matters:** the saved pool object name differs in case from .NET; the subsequent `literal` re-fetch uses the lowercased name. Internally consistent in Java, but diverges from .NET-produced names.
- **Fix:** drop `.toLowerCase()`, keep only the null fallback.

### 🟡 F9 — QXPSM `QRequestContext` omits several fields set by .NET (verify against .NET config)
- `infra/interop/qxpsm/QxpsmSoapClient.java:86-90` sets only `documentName`, `request`, `maxRetries`, `requestTimeout`. .NET `QXPSM_Call.InitContext` also sets `responseAsURL`, `useCache`, `bypassFileInfo`, `userName`, `userPassword`, and when no timeout is configured forces `requestTimeout=3600000` **and** the Axis stub `Timeout=Infinite`.
- **Action:** confirm the .NET `QXPS_Call_Info` defaults. If any of these are non-default (esp. `useCache`/`bypassFileInfo`/credentials), populate them and set the stub timeout to match. **UNVERIFIED** pending the .NET config values.

### 🟡 F10 — Document QXP_Data STYLE: error-stream divergence (decision needed, not a functional defect)
- **.NET quirk (verified, `Process_Document.cs:127-163`):** in the `Conserver_Style` path, a **TBox** is added to `Blocs_Modify` **inline**, then the shared block re-checks `ContainsKey` (now true) and **always** raises `BlocDupliquerDansTache` (Unspecified severity). A **TTable** is not added inline, so it only errors on a genuine duplicate. This is effectively a .NET bug that logs a spurious error per TBox style-copy.
- **Java:** does not replicate the spurious TBox error (only `log.warn`); for a genuine TTable duplicate it also only `log.warn`s instead of raising a RunError.
- **Impact:** the generated document is **identical**; only the persisted error stream differs.
- **Decision:** (a) replicate the .NET quirk for byte-exact error parity, or (b) keep Java's cleaner behavior but add a real `RunError` on a *genuine* duplicate (recommended). Either way, flag per your "notify before deviating" rule.

### 🔵 F11 — Modifier inclusion gated on serialized layouts vs `.Modifier.Empty` (low)
- `QxpsmSoapClient.java:70` decides to attach `ModifierRequest` by inspecting the serialized `Project.getLayouts().length`. .NET gates on `!step.Modifier.Empty` (source object). Edge case: a layout shell with no real changes could send an empty Modifier (or vice-versa). Low risk.
- **Fix:** gate on the source modifier's emptiness before serializing.

### 🔵 F12 — DAO date params bound as TIMESTAMP where Oracle declares DATE (benign)
- `AuditDaoImpl`, `EndRunDaoImpl`, `RunStartUpdateDaoImpl`, `InsertDocumentDaoImpl` declare some date params `Types.TIMESTAMP` vs Oracle `DATE`. Oracle accepts the Timestamp bind transparently — **no correctness impact**. Align to `Types.DATE` only if strict typing is desired.

### 🔵 F13 — Dead placeholder beans (low)
- `integration/soap/client/EngineSoapClient.java` (empty `@Component`) and `integration/soap/config/SoapConfig.java` (empty `@Configuration`, no `@Bean`s). Harmless; remove or keep as scaffolding.

---

## 2. Confirmed CLEAN (no action)

- **Oracle DAO layer (all 18 DAOs)** vs `ora.txt`: package, routine name, FUNCTION-vs-PROCEDURE kind, every parameter name/direction/type/order, function-return/cursor handling, and row-mapper columns all **MATCH**. The riskiest-to-transcribe layer is exact.
- **Pipeline lifecycle:** step order (Start→Load→Prepare→Process→Steps→Check→Render→End), RUNNING-before-Start, mode-degrade skip set, 3-pass loop, render flags, RunResult build, End_Run transaction/order/retry, sous-categorie doc IDs — all MATCH.
- **Task strategies (5 of 6):** System, SQL, Dynamique, DID, Compartiment all faithful (incl. the #17 Compartiment incorporation: Run/Run_Previous, EmptyRunChildQXP/Project, page/anchor handling, Rename_Bloc).
- **QXPS/QXPSM interop:** combined-URL composition logic, message **priority ordering**, per-step message order (Params→Modify→SaveAs→QXP, one call), final-render flow, SOAP `processRequest` chain, `getXPressDOM`, multipart body, and the **entire Project→Modify XML serializer** — all MATCH. **All pool ops go through the Quark API (no local `java.io.File`)** — Kube constraint honored.
- **Wiring/dispatch:** bean graph resolves, the `@Lazy` correctly breaks the Compartiment↔ProcessRun cycle, 6 strategies map to 6 distinct task classes, Rule-1 clean.
- **#17 Compartiment fix** (`getChildRuns().clear()/addAll()`): correctly applied at lines 212-213.

---

## 3. Approved deviations (not defects — already cleared with you)

- **Document source/dest count-mismatch:** Java iterates `min(src,dest)` + adds a RunError; .NET indexes blindly (throws `IndexOutOfRangeException`). This is the Batch 7C improvement you approved.
- **Java native-serialization deep-clone** (`TElementHelper`): your approved §5-D parity decision. (Also: it does **not** break the arch test — see §4.)
- **Config deviations:** size-limit 200 MB (vs .NET 68 MB), step-limit 5000 — your choices, configurable in `application.yaml`.

---

## 4. Rejected false positives (verified NOT issues)

- **"Rule-3 violation: `java.io` in `TElementHelper`, `java.io`/`javax.xml` in `QxpXml`."** The actual `CleanArchitectureLayersTest` Rule-3 forbids only an **enumerated** list (jackson, apibank, swagger, servlet, spring web/http, `java.sql`, jpa, spring data/transaction/scheduling/security/validation). It does **not** include `java.io` or `javax.xml`. These classes **pass** the test. No action.
- **"`setChildRuns` call is commented-out dead code."** The working `getChildRuns().clear()/addAll()` fix is present right below it (lines 212-213). The commented line is a harmless leftover. No action.

---

## 5. Recommended fix order

1. **F1** — apply Batch 8 (makes the arch test green; files already exist).
2. **F2** — decide on DOC_QXP/QXP_Previous (port it, or hard-fail instead of silent skip).
3. **F3** — fix error-severity codes (correctness, persisted).
4. **F4** — pool-path slashes + encoding (do the slash fix now; encoding needs live QXPS validation).
5. **F5–F9** — severity/safe-mode/render-error/extension/SOAP-context fixes.
6. **F10** — decide error-stream parity for QXP_Data STYLE.
7. **F11–F13** — low priority / cleanup.

I can prepare a single "Batch 10" change set (`.md` + `apply.sh`) covering F1–F9 + F11 once you tell me how you want F2 (port vs hard-fail) and F10 (replicate vs improve) handled.
