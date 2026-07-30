# EOS Quark Engine — Batch 1 Changes
**Theme: Gabarit pool-key + Mode_Degrade + full-XML load (the `Run.prepareGabarit` cluster)**

_Generated directly from the working-copy files (no hand transcription). Whole-file copy-paste; CRLF/LF differs between the two repos so apply by replacing the whole file._

## Why this batch is first
This cluster breaks **every** render on a normal run, so nothing else can be validated live until it is fixed. All changes were ground-truth-verified against the actual .NET source in Phase 0.

## Findings fixed in this batch
| # | Sev | Issue | .NET reference |
|---|---|---|---|
| 0 | CRITICAL | Degrade mode returned before the pool upload → degraded render had no document | Run.cs:92 (Addfile unconditional); Run_Base.cs:110-124 (Launch_Load + Launch_Render always run) |
| 5 | CRITICAL | Gabarit uploaded under `getFileName()` but referenced everywhere by `getFilePoolPath()` | Run.cs:92 `Addfile(Gabarit.FilePoolPath, …)`; Run_Base.cs:954 `DocumentName = Gabarit.FilePoolPath` |
| 7 | CRITICAL | Mode-degrade early-return preceded `addFile` | Run.cs:92,94,97; Document.cs:200 (only DID parse is degrade-gated) |
| 8 | CRITICAL | Upload keyed to pool ROOT (`getFileName()`) not `R_<id>/` scoped path | Run.cs:92; Document.cs:118 `GetPoolPath(_fileName)` |
| 24 | HIGH | (companion of #7) — fix adjusted to use `getFilePoolPath()` for the upload key | Run.cs:92; Document.cs:200,228-233 |
| 25 | HIGH | Full gabarit XML never loaded before Process (stayed `QxpXml.EMPTY` until Check) | Run.cs:99 (first XML access in PrepareGabarit); Document.cs:421-444 (lazy-load + cache, no box filter) |
| 26 | HIGH | DID XML fetch used `getFileName()` (root) instead of `getFilePoolPath()` | Run.cs:92; Document.cs:205,430 |
| 9 | HIGH | `load()` ran InParams/Tasks/Templates even in degrade mode | Run_Base.cs:305-317 `if (!this.Mode_Degrade){ LoadInParams; LoadTasks; LoadTemplates; }` |

## What changed, in one paragraph
`Run.prepareGabarit` now (1) uploads the gabarit to the QXPS pool **unconditionally and before** the Mode_Degrade check, (2) keys that upload — and the DID fetch — on `getFilePoolPath()` (the `R_<runId>/…` name every consumer and .NET use), (3) on the non-degraded path, **loads the full gabarit XML** into the domain object so page/box/anchor info is available during Prepare/Process, and (4) in degrade mode skips only the DID parse + XML load. `ProcessRunServiceImpl.load()` now **skips** in-params/tasks/templates loading in degrade mode (matching .NET `Run_Base.Load`), and passes the new `GetGabaritXmlBusiness` dependency into `prepareGabarit`.

## Signature change (callers updated)
`Run.prepareGabarit(GetGabaritBusiness, FilePoolPort, DocumentIdentityPort)` → `Run.prepareGabarit(GetGabaritBusiness, GetGabaritXmlBusiness, FilePoolPort, DocumentIdentityPort)`. Callers updated: `ProcessRunServiceImpl.load()` and `RunTest`. Arch note: `Run` (domain) importing `business.GetGabaritXmlBusiness` is allowed — Rule 1 forbids only domain→service/infra; `business` is the sanctioned bridge (same pattern already used for `GetGabaritBusiness`).

## Not changed on purpose (scoped out of Batch 1)
- DID is still fetched via the box-scoped `fetchXmlForBox(...,"DID")` rather than read from the full XML. .NET reads DID from the full XML (`Document.cs:205`); converting to that is findings **#16/#23** and belongs to the later DID batch. Batch 1 only fixes the pool key on that call.
- Post-step XML refresh / purge behaviour (`updateGabaritAfterStep`, `CheckServiceImpl.refreshGabaritXml`) is unchanged.

---

## `domain/Run.java` — CHANGED
```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness;
import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Domain entity representing a Run
 */
@Getter
@Setter
@AllArgsConstructor
@Slf4j
public class Run {
    private Integer id;
    private String name;
    private RunStatus status;
    private LocalDateTime startDate;
    private RunProperties runProperties;
    private DocumentDomain gabarit;

    /** Keyed by parameter name, preserves insertion order. */
    private Map<String, InParam> inParams = new LinkedHashMap<>();

    /** Keyed by task ID, preserves insertion order. */
    private Map<Integer, TaskBase> tasks = new LinkedHashMap<>();

    /** Keyed by template name, preserves insertion order. */
    private Map<String, Template> templates = new LinkedHashMap<>();

    /** Aggregates tasks with blocs after Verify phase for Step 5. */
    private RunTask runTask;

    /** SQL data collected during Check step. Cross-reference: .NET Run_Base._sqlDataNamesValues */
    private final java.util.List<DataNameValue> sqlDataNamesValues = new java.util.ArrayList<>();

    /** Document data collected during Check step. Cross-reference: .NET Run_Base._docDataNamesValues */
    private final java.util.List<DataNameValue> docDataNamesValues = new java.util.ArrayList<>();

    /** Rendered output documents. Cross-reference: .NET Run_Base._result */
    private RunResult result = new RunResult();

    /** Errors collected during run execution. Cross-reference: .NET Run_Base._errors */
    private final java.util.List<RunError> errors = new java.util.ArrayList<>();

    /** End timestamp. Cross-reference: .NET Run_Base._finGeneration */
    private LocalDateTime endDate;

    private long sizeLimitBeforeFailSoft;

    /** Max boxes a modified document may contain (.NET EngineCoreSetting Nb_Box_Max). Configurable. */
    private int nbBoxMax = 17500;

    /** Average byte-size of a box, used for box-complexity (.NET EngineCoreSetting Average_Box_Size). Configurable. */
    private int averageBoxSize = 3400;

    /**
     * Accumulated run trace, persisted to the End_Run p_log_trace CLOB.
     * Cross-reference: .NET Run.Trace_Context.All_Logs.
     */
    private final java.util.List<String> traceLogs = new java.util.ArrayList<>();

    private static final java.time.format.DateTimeFormatter TRACE_TS =
            java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS");

    /** Append a timestamped trace message (kept in-memory for the End_Run trace CLOB). */
    public void trace(String message) {
        traceLogs.add(LocalDateTime.now().format(TRACE_TS) + "  " + message);
    }

    /** Full accumulated trace text for the End_Run p_log_trace CLOB. */
    public String getTraceLog() {
        return String.join(System.lineSeparator(), traceLogs);
    }

    /**
     * Constructor that accepts size limit parameter.
     * Used by ProcessRunServiceImpl to inject the configured size limit from application.yaml
     */
    public Run(long sizeLimitBeforeFailSoft) {
        this.sizeLimitBeforeFailSoft = sizeLimitBeforeFailSoft;
        this.runTask = new RunTask(this);
    }

    /**
     * No-arg constructor for backward compatibility.
     * Defaults to 10MB if no explicit size limit is provided.
     */
    public Run() {
        this.sizeLimitBeforeFailSoft = 209715200; // fallback = 200MB; configurable via engine.gabarit.size-limit-before-fail-soft
        this.runTask = new RunTask(this);
    }

    /**
     * Prepares the gabarit for this run based on gabarit source.
     * Calls the appropriate method on GetGabaritBusiness based on the gabarit source,
     * and stores the fetched document directly in this.gabarit.
     * After loading, adds the file to the QXPS document pool and retrieves the document identity (DID),
     * then sets the identity on the gabarit domain object.
     *
     * - GABARIT               → Get_Gabarit(idGabarit)
     * - DOCUMENT_COURANT      → Get_Gabarit_Document(idSuivi)
     * - DOCUMENT_PRECEDENT_CERTIFIE → Get_Gabarit_Document_Certifie(idSuivi)
     * - DOCUMENT_SUIVI        → Get_Gabarit_Document(idSuiviGabaritSource)
     *
     * @param getGabaritBusiness    the business component injected by the caller
     * @param getGabaritXmlBusiness business bridge for fetching the full gabarit XML (.NET Document.XML lazy-load)
     * @param filePoolPort          port for uploading the file to the QXPS document pool
     * @param documentIdentityPort  port for fetching XML and parsing document identity
     */
    public void prepareGabarit(GetGabaritBusiness getGabaritBusiness,
                                GetGabaritXmlBusiness getGabaritXmlBusiness,
                                FilePoolPort filePoolPort,
                                DocumentIdentityPort documentIdentityPort) {
        if (this.runProperties == null) {
            throw new IllegalStateException(
                    "Run properties must be set before preparing gabarit for runId: " + this.id);
        }

        switch (this.runProperties.getGabaritSource()) {
            case GABARIT:
                this.gabarit = getGabaritBusiness.getAndPrepareGabarit(
                        this.runProperties,
                        this.runProperties.getIdGabarit());
                break;
            case DOCUMENT_COURANT:
                this.gabarit = getGabaritBusiness.getAndPrepareGabaritDocumentCourant(
                        this.runProperties,
                        this.runProperties.getIdSuivi());
                break;
            case DOCUMENT_PRECEDENT_CERTIFIE:
                this.gabarit = getGabaritBusiness.getAndPrepareGabaritDocumentCertifie(
                        this.runProperties,
                        this.runProperties.getIdSuivi());
                break;
            case DOCUMENT_SUIVI:
                this.gabarit = getGabaritBusiness.getAndPrepareGabaritDocumentSuivi(
                        this.runProperties,
                        this.runProperties.getIdSuiviGabaritSource());
                break;
            default:
                throw new IllegalArgumentException(
                        "Unsupported gabarit source: " + this.runProperties.getGabaritSource());
        }

        if (this.gabarit == null) {
            return;
        }

        // Step 1: Upload the gabarit to the QXPS document pool — UNCONDITIONALLY, before the
        // Mode_Degrade check. Parity: .NET Run.cs:92 calls QXPS_File_Manager.Addfile(FilePoolPath, Data)
        // before any degrade branch; a degraded run still renders the PDF and fetches the literal QXP
        // from the pool, so the document MUST be present. The upload key is getFilePoolPath()
        // (the R_<runId>/-scoped name), matching .NET (Gabarit.FilePoolPath) and every downstream
        // consumer — QxpsCallerBusiness.executeStep/render and CheckServiceImpl all address the
        // gabarit by getFilePoolPath(). (Findings #0, #5, #7, #8, #24, #26.)
        filePoolPort.addFile(this.gabarit.getFilePoolPath(), this.gabarit.getData());

        // Step 2: Mode_Degrade — if the template exceeds the size limit, skip ONLY the DID parse and
        // the full-XML load (steps 3-4). Parity: .NET Document.cs:200 gates only the DID parse inside
        // Evaluate_Document_Identity, and the Document.XML getter returns QXP_XML.Empty in degrade mode.
        // The pool upload above has already run, so the degraded render has its document. (Findings #0, #7, #24.)
        if (this.gabarit.getData().length > sizeLimitBeforeFailSoft) {
            log.warn("Gabarit size {} bytes exceeds limit {} bytes, setting Mode_Degrade for runId: {}",
                    this.gabarit.getData().length, sizeLimitBeforeFailSoft, this.id);
            this.runProperties.setModeDegrade(true);
            return; // degrade: skip DID parse + full-XML load only — gabarit is already in the pool
        }

        // Step 3: Load the FULL gabarit XML into the domain object so page/layout/box info is
        // available during Prepare and Process (before Check). Parity: .NET first materialises
        // this.Gabarit.XML right after Addfile (Run.cs:99) and caches it (Document.cs:421-444);
        // without this the gabarit XML stays QxpXml.EMPTY until Check, breaking anchor/page/box
        // evaluation in Dynamique and Compartiment-incorporate tasks. (Finding #25.)
        String fullXml = getGabaritXmlBusiness.fetchXml(this.gabarit.getFilePoolPath());
        if (fullXml != null && !fullXml.isEmpty()) {
            this.gabarit.initXmlFromContent(fullXml);
        }

        // Step 4: Fetch XML for the DID box and parse document identity. Parity: .NET
        // Evaluate_Document_Identity (Document.cs:205). Keyed on getFilePoolPath() so the DID fetch
        // hits the same pooled document that was uploaded and that the modify/render path operates on.
        String xmlContent = documentIdentityPort.fetchXmlForBox(this.gabarit.getFilePoolPath(), "DID");
        String didValue = documentIdentityPort.getElementValueByIdName(xmlContent, "DID");
        DocumentIdentity identity = documentIdentityPort.parseDocumentIdentity(didValue);

        // Step 5: Set the document identity on the gabarit domain object
        this.gabarit.setDocumentIdentity(identity);
    }
}
```

---

## `service/impl/ProcessRunServiceImpl.java` — CHANGED
```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.business.*;
import com.socgen.sgs.api.quark.engine.domain.*;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult;
import com.socgen.sgs.api.quark.engine.dto.RunIdDto;
import com.socgen.sgs.api.quark.engine.service.*;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;

@Service
@Slf4j
@RequiredArgsConstructor
public class ProcessRunServiceImpl implements ProcessRunService {

    private final RunStartUpdateBusiness   runStartUpdateBusiness;
    private final GetRunPropertiesBusiness getRunPropertiesBusiness;
    private final GetGabaritBusiness       getGabaritBusiness;
    private final GetGabaritXmlBusiness    getGabaritXmlBusiness;
    private final GetInParamsBusiness      getInParamsBusiness;
    private final LoadTasksService         loadTasksService;
    private final FilePoolPort             filePoolPort;
    private final DocumentIdentityPort     documentIdentityPort;
    private final ProcessTasksService      processTasksService;
    private final QxpsCallerService        qxpsCallerService;
    private final CheckService             checkService;
    private final LoadTemplatesBusiness    loadTemplatesBusiness;
    private final LoadTaskDocumentsBusiness loadTaskDocumentsBusiness;
    private final EndRunBusiness           endRunBusiness;

    @Value("${engine.gabarit.size-limit-before-fail-soft:209715200}")
    private long sizeLimitBeforeFailSoft;

    @Value("${engine.nb-box-max:17500}")
    private int nbBoxMax;

    @Value("${engine.average-box-size:3400}")
    private int averageBoxSize;

    @Override
    public Run runProcessor(RunIdDto runIdDto) {
        log.info("Processing run with runId: {}", runIdDto.getRunId());
        Run run = new Run(sizeLimitBeforeFailSoft);
        run.setNbBoxMax(nbBoxMax);
        run.setAverageBoxSize(averageBoxSize);
        run.setId(runIdDto.getRunId());
        run.setStatus(RunStatus.TO_GENERATE);
        run.setStartDate(LocalDateTime.now());

        try {
            // Step 1: Start — status must be RUNNING before it is persisted by Start_Run.
            // Cross-reference: .NET Run_Base.Launch() sets _status = Running BEFORE Launch_Start().
            run.setStatus(RunStatus.RUNNING);
            runStartUpdateBusiness.execute(run);
            run.trace("Run " + run.getId() + " started");
            log.info("Run started successfully with runId: {}", runIdDto.getRunId());

            // Step 2: Load
            load(run);
            run.trace("Run loaded (modeDegrade=" + run.getRunProperties().isModeDegrade() + ")");

            if (!run.getRunProperties().isModeDegrade()) {
                // Step 3: Prepare — call prepare() on every task before processing.
                // Cross-reference: .NET Run_Base.Launch_Prepare() / Prepare().
                processTasksService.prepareTasks(run);

                // Step 3b: Load each task's reference/previous document and upload it to the pool
                // (PDFs split per page). In .NET this happens inside Task_Document.Prepare /
                // Task_QXP_Previous.Prepare; here it is a business step so the domain stays I/O-free.
                loadTaskDocumentsBusiness.loadDocuments(run);
                run.trace("Task documents loaded");

                // Step 4: Process tasks (3-pass loop)
                processTasksService.processTasks(run);
                run.trace("Tasks prepared and processed");

                // Step 5: Execute modification steps against QXPS
                qxpsCallerService.process(run);
                run.trace("Modification steps executed");

                // Step 6: Check — overflow detection + data collection
                checkService.check(run);
                run.trace("Check completed");
            }

            // Step 7: Render final outputs
            QxpsCallerResult renderResult = qxpsCallerService.render(
                    run, true, false, true, "true", "300");

            // Build RunResult from render data
            buildRunResult(run, renderResult);
            run.trace("Render completed");

            run.setStatus(RunStatus.GENERATED);

        } catch (Exception ex) {
            log.error("Run [{}] failed: {}", runIdDto.getRunId(), ex.getMessage(), ex);
            run.setStatus(RunStatus.ERROR);
            // An unexpected top-level failure is Bloquante (3), matching .NET Run_Base.Launch
            // generic catch → Errors.Add(Error_Type.Bloquante, ...). (NOT 1/Unspecified.)
            run.getErrors().add(new RunError(RunError.BLOQUANTE, ex.getMessage()));
            run.trace("ERROR: " + ex.getMessage());
        } finally {
            run.trace("Run ending with status " + run.getStatus());
            // A degraded run always records a Critique error before End.
            // Cross-reference: .NET Run_Base.Launch finally → if (Mode_Degrade) Errors.Add(Critique, RunInSafeMode).
            if (run.getRunProperties() != null && run.getRunProperties().isModeDegrade()) {
                run.getErrors().add(new RunError(RunError.CRITIQUE,
                        "Run execute en mode degrade (mode sans echec) : RunInSafeMode"));
            }
            // Step 8: End — finalize run (always executes)
            try {
                endRunBusiness.execute(run);
            } catch (Exception ex) {
                log.error("End_Run failed for run [{}]: {}", runIdDto.getRunId(), ex.getMessage(), ex);
                // Retry with error status
                run.setStatus(RunStatus.ERROR);
                try {
                    endRunBusiness.execute(run);
                } catch (Exception ex2) {
                    log.error("End_Run retry failed for run [{}]: {}",
                            runIdDto.getRunId(), ex2.getMessage(), ex2);
                }
            }
            log.info("Run completed for runId: {} with status: {}",
                    runIdDto.getRunId(), run.getStatus());
        }
        return run;
    }

    /**
     * Build RunResult from render output.
     * Cross-reference: .NET Run_Base.Render() — wraps binary data in Document objects
     */
    private void buildRunResult(Run run, QxpsCallerResult renderResult) {
        String docNamePrefix = String.format("DF_%d", run.getId());

        if (renderResult.getJpgData() != null) {
            run.getResult().setFinalJpg(new DocumentDomain(
                    run.getId(), docNamePrefix, "JPEG",
                    DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, renderResult.getJpgData()));
        }
        if (renderResult.getPdfData() != null) {
            run.getResult().setFinalPdf(new DocumentDomain(
                    run.getId(), docNamePrefix, "PDF",
                    DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, renderResult.getPdfData()));
        }
        if (renderResult.getQxpData() != null) {
            run.getResult().setFinalQxp(new DocumentDomain(
                    run.getId(), docNamePrefix, "QXP",
                    DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, renderResult.getQxpData()));
        }
    }

    public void load(Run run) {
        log.info("Loading run with runId: {}", run.getId());

        // Step 1: Fetch and set run properties
        RunProperties runProperties = getRunProperties(new RunIdDto(run.getId()));
        runProperties.setRunId(run.getId());
        run.setRunProperties(runProperties);

        // Step 2: Delegate gabarit preparation entirely to run domain.
        // prepareGabarit uploads the gabarit to the pool (unconditionally), sets Mode_Degrade if the
        // template is oversized, and — when not degraded — loads the full gabarit XML + the DID.
        run.prepareGabarit(getGabaritBusiness, getGabaritXmlBusiness, filePoolPort, documentIdentityPort);

        // Steps 3-5: In degrade mode .NET does NOT load in-params/tasks/templates.
        // Parity: .NET Run_Base.Load:305-317 — "si nous sommes en mode dégradé nous ne préparons
        // pas les taches et leurs paramètres" — guards LoadInParams / LoadTasks / LoadTemplates with
        // if (!this.Mode_Degrade). Skipping them avoids wasted DB work and the spurious ERROR that
        // would otherwise break the degraded-render success path. (Finding #9.)
        if (!run.getRunProperties().isModeDegrade()) {
            // Step 3: Inject and execute GetInParamsBusiness
            getInParamsBusiness.execute(run);

            // Step 4: Load tasks
            loadTasksService.loadTasks(run);

            // Step 5: Load templates for dynamic tasks
            loadTemplatesBusiness.execute(run);
        }
        log.info("Run loading completed for runId: {}", run.getId());
    }

    @Override
    public RunProperties getRunProperties(RunIdDto runIdDto) {
        log.info("Retrieving properties for runId: {}", runIdDto.getRunId());
        RunProperties runProperties = getRunPropertiesBusiness.execute(runIdDto);
        log.info("Successfully retrieved properties for runId: {}", runIdDto.getRunId());
        return runProperties;
    }

    @Override
    public List<Integer> fetchActiveRunIds() {
        return Collections.emptyList();
    }
}
```

---

## `src/test/.../domain/RunTest.java` — CHANGED (test signature)
```java
package com.socgen.sgs.api.quark.engine.domain;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.BeforeEach;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Run Tests")
class RunTest {

    private Run run;

    @BeforeEach
    void setUp() {
        run = new Run();
    }

    @Test
    @DisplayName("Should create Run with no arguments")
    void shouldCreateRunWithNoArguments() {
        assertNull(run.getId());
        assertNull(run.getName());
        assertNull(run.getStatus());
        assertNull(run.getStartDate());
        assertNull(run.getRunProperties());
        assertNull(run.getGabarit());
        assertNotNull(run.getInParams());
        assertNotNull(run.getTasks());
    }

    @Test
    @DisplayName("Should create Run with all arguments")
    void shouldCreateRunWithAllArguments() {
        RunStatus status = RunStatus.TO_GENERATE;
        LocalDateTime startDate = LocalDateTime.now();
        RunProperties props = new RunProperties();
        DocumentDomain gabarit = new DocumentDomain();
        Map<String, InParam> inParams = new LinkedHashMap<>();
        Map<Integer, TaskBase> tasks = new LinkedHashMap<>();
        Map<String, Template> templates = new LinkedHashMap<>();

        Run fullRun = new Run();
        fullRun.setId(1);
        fullRun.setName("TestRun");
        fullRun.setStatus(status);
        fullRun.setStartDate(startDate);
        fullRun.setRunProperties(props);
        fullRun.setGabarit(gabarit);
        fullRun.setInParams(inParams);
        fullRun.setTasks(tasks);
        fullRun.setTemplates(templates);

        assertEquals(1, fullRun.getId());
        assertEquals("TestRun", fullRun.getName());
        assertEquals(status, fullRun.getStatus());
        assertEquals(startDate, fullRun.getStartDate());
        assertEquals(props, fullRun.getRunProperties());
        assertEquals(gabarit, fullRun.getGabarit());
    }

    @Test
    @DisplayName("Should set and get id")
    void shouldSetAndGetId() {
        run.setId(42);
        assertEquals(42, run.getId());
    }

    @Test
    @DisplayName("Should set and get name")
    void shouldSetAndGetName() {
        run.setName("MyRun");
        assertEquals("MyRun", run.getName());
    }

    @Test
    @DisplayName("Should set and get status")
    void shouldSetAndGetStatus() {
        run.setStatus(RunStatus.RUNNING);
        assertEquals(RunStatus.RUNNING, run.getStatus());
    }

    @Test
    @DisplayName("Should set and get start date")
    void shouldSetAndGetStartDate() {
        LocalDateTime now = LocalDateTime.now();
        run.setStartDate(now);
        assertEquals(now, run.getStartDate());
    }

    @Test
    @DisplayName("Should set and get run properties")
    void shouldSetAndGetRunProperties() {
        RunProperties props = new RunProperties();
        run.setRunProperties(props);
        assertEquals(props, run.getRunProperties());
    }

    @Test
    @DisplayName("Should set and get gabarit")
    void shouldSetAndGetGabarit() {
        DocumentDomain gabarit = new DocumentDomain();
        run.setGabarit(gabarit);
        assertEquals(gabarit, run.getGabarit());
    }

    @Test
    @DisplayName("Should manage in params map")
    void shouldManageInParamsMap() {
        InParam param = new InParam("param1", 1, "value1");
        run.getInParams().put("param1", param);

        assertTrue(run.getInParams().containsKey("param1"));
        assertEquals(param, run.getInParams().get("param1"));
    }

    @Test
    @DisplayName("Should have ordered in params map")
    void shouldHaveOrderedInParamsMap() {
        run.getInParams().put("param1", new InParam("p1", 1, "v1"));
        run.getInParams().put("param2", new InParam("p2", 1, "v2"));
        run.getInParams().put("param3", new InParam("p3", 1, "v3"));

        Map<String, InParam> params = run.getInParams();
        assertEquals(3, params.size());
    }

    @Test
    @DisplayName("Should throw exception when preparing gabarit without run properties")
    void shouldThrowExceptionWhenPreparingGabaritWithoutRunProperties() {
        run.setId(100);
        run.setRunProperties(null);

        assertThrows(IllegalStateException.class, () -> run.prepareGabarit(null, null, null, null));
    }
}
```

---

## Apply checklist
- [ ] Replace `domain/Run.java` with the content above
- [ ] Replace `service/impl/ProcessRunServiceImpl.java` with the content above
- [ ] Update the one line in `RunTest.java` (`prepareGabarit(null, null, null, null)`)
- [ ] `mvn compile` (no other callers of `prepareGabarit` exist)
- [ ] `mvn test -Dtest=RunTest` (degrade/signature) and `CleanArchitectureLayersTest`
