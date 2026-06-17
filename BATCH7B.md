# EOS Quark — Batch 7B Changes (copy-paste) — End_Run audit + trace log

**Task #14 = restore the End_Run audit insert + the trace-log CLOB** (dropped vs .NET).

**What changed (5 files):**
- **Audit insert** — new `AuditDao` + `AuditDaoImpl` calling `QXP_PK_AUDIT.InsertAuditRun` (verified signature: p_id_run, p_id_suivi, p_run_type, p_start_date, p_end_date, p_duration, p_end_status, p_message). `EndRunBusiness` now inserts the audit row inside the finalize transaction, in .NET order (status/end → errors → **audit** → data storage).
- **Trace-log CLOB** — `Run` now accumulates a timestamped trace (`run.trace(...)`, `run.getTraceLog()`) mirroring .NET `Run.Trace_Context.All_Logs`. `EndRunBusiness` passes it into `End_Run` / `Update_Status_Run` `p_log_trace` (was empty `""`). `ProcessRunServiceImpl` writes trace milestones (start, load, tasks, steps, check, render, error, end).

**Decisions taken (you can tune):**
- Trace detail = **(a) full milestone trace** at the pipeline level (your "what do you suggest" → I chose the run-scoped buffer; thread-safe across compartiment recursion / reactive calls). More granular per-task/per-step trace() calls can be added later.
- `p_run_type` = `RunProperties.runType` (already mapped in Java). NOTE: the mapper reads cursor column `"runtime"` — likely a typo for `"runtype"`; verify the Get_Run_Properties cursor column name (separate from this change).
- `p_duration` = whole **seconds** between start and end. `p_end_status` = run status enum name (e.g. GENERATED/ERROR). `p_message` = short status+error summary (truncated to 4000). Tell me if .NET expects different units/text.

## How to apply
Each section is one file (create the two NEW files). Paths relative to the `quark-engine` module root. Then `mvn -DskipTests compile` and `mvn test`.

## Checklist (5 files)
- [ ] `domain/Run.java` — CHANGED
- [ ] `infra/dao/AuditDao.java` — NEW
- [ ] `infra/dao/impl/AuditDaoImpl.java` — NEW
- [ ] `business/EndRunBusiness.java` — CHANGED
- [ ] `service/impl/ProcessRunServiceImpl.java` — CHANGED (also touched in Batches 2 & 6)

---

## 1. `src/main/java/com/socgen/sgs/api/quark/engine/domain/Run.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
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
     * @param getGabaritBusiness   the business component injected by the caller
     * @param filePoolPort         port for uploading the file to the QXPS document pool
     * @param documentIdentityPort port for fetching XML and parsing document identity
     */
    public void prepareGabarit(GetGabaritBusiness getGabaritBusiness,
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

        // Check Mode_Degrade: if template exceeds size limit, skip processing steps 3-6
        if (this.gabarit.getData().length > sizeLimitBeforeFailSoft) {
            log.warn("Gabarit size {} bytes exceeds limit {} bytes, setting Mode_Degrade for runId: {}",
                    this.gabarit.getData().length, sizeLimitBeforeFailSoft, this.id);
            this.runProperties.setModeDegrade(true);
            return; // Return early — skip file pool operations and DID parsing in degraded mode
        }

        // Step 1: Add gabarit file to the QXPS document pool
        filePoolPort.addFile(this.gabarit.getFileName(), this.gabarit.getData());

        // Step 2: Fetch XML for the DID box and parse document identity
        String xmlContent = documentIdentityPort.fetchXmlForBox(this.gabarit.getFileName(), "DID");
        String didValue = documentIdentityPort.getElementValueByIdName(xmlContent, "DID");
        DocumentIdentity identity = documentIdentityPort.parseDocumentIdentity(didValue);

        // Step 3: Set the document identity on the gabarit domain object
        this.gabarit.setDocumentIdentity(identity);
    }
}
```

## 2. `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/AuditDao.java`  — **NEW**

```java
package com.socgen.sgs.api.quark.engine.infra.dao;

import com.socgen.sgs.api.quark.engine.domain.Run;

/**
 * DAO for run audit. Cross-reference: .NET Proxy_Audit.InsertAuditRun.
 */
public interface AuditDao {

    /**
     * Insert one audit row for a finished run (QXP_PK_AUDIT.InsertAuditRun).
     *
     * @param run     the finished run (id, suivi, run type, start/end dates, status)
     * @param message a short audit message (truncated to fit the VARCHAR2 column)
     */
    void insertAuditRun(Run run, String message);
}
```

## 3. `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/AuditDaoImpl.java`  — **NEW**

```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.infra.dao.AuditDao;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.Duration;

/**
 * Calls QXP_PK_AUDIT.InsertAuditRun (PROCEDURE, 8 IN params).
 * Cross-reference: .NET Proxy_Audit.InsertAuditRun.
 */
@Repository
@Slf4j
public class AuditDaoImpl implements AuditDao {

    /** p_message is VARCHAR2 — keep within Oracle's standard VARCHAR2 limit. */
    private static final int MAX_MESSAGE_SIZE = 4000;

    private final SimpleJdbcCall insertAuditRunCall;

    @Autowired
    public AuditDaoImpl(DataSource dataSource) {
        this.insertAuditRunCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_AUDIT")
                .withProcedureName("InsertAuditRun")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlParameter("p_id_run", Types.NUMERIC),
                        new SqlParameter("p_id_suivi", Types.NUMERIC),
                        new SqlParameter("p_run_type", Types.VARCHAR),
                        new SqlParameter("p_start_date", Types.TIMESTAMP),
                        new SqlParameter("p_end_date", Types.TIMESTAMP),
                        new SqlParameter("p_duration", Types.NUMERIC),
                        new SqlParameter("p_end_status", Types.VARCHAR),
                        new SqlParameter("p_message", Types.VARCHAR)
                );
    }

    @Override
    public void insertAuditRun(Run run, String message) {
        // Duration in seconds between start and end (.NET audit.Duration).
        long durationSeconds = 0L;
        if (run.getStartDate() != null && run.getEndDate() != null) {
            durationSeconds = Duration.between(run.getStartDate(), run.getEndDate()).getSeconds();
        }

        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_run", run.getId())
                .addValue("p_id_suivi", run.getRunProperties() != null ? run.getRunProperties().getIdSuivi() : null)
                .addValue("p_run_type", run.getRunProperties() != null ? run.getRunProperties().getRunType() : null)
                .addValue("p_start_date", run.getStartDate() != null ? Timestamp.valueOf(run.getStartDate()) : null)
                .addValue("p_end_date", run.getEndDate() != null ? Timestamp.valueOf(run.getEndDate()) : null)
                .addValue("p_duration", durationSeconds)
                .addValue("p_end_status", run.getStatus() != null ? run.getStatus().name() : null)
                .addValue("p_message", truncate(message, MAX_MESSAGE_SIZE));

        try {
            insertAuditRunCall.execute(params);
            log.info("Audit row inserted for run [{}]", run.getId());
        } catch (Exception e) {
            log.error("Failed to insert audit row for run [{}]: {}", run.getId(), e.getMessage(), e);
            throw new RuntimeException("Failed to insert audit row for run: " + run.getId(), e);
        }
    }

    private static String truncate(String value, int maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}
```

## 4. `src/main/java/com/socgen/sgs/api/quark/engine/business/EndRunBusiness.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DataNameValue;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunResult;
import com.socgen.sgs.api.quark.engine.domain.RunStatus;
import com.socgen.sgs.api.quark.engine.domain.StoreDataType;
import com.socgen.sgs.api.quark.engine.infra.dao.AuditDao;
import com.socgen.sgs.api.quark.engine.infra.dao.EndRunDao;
import com.socgen.sgs.api.quark.engine.infra.dao.InsertDataStorageDao;
import com.socgen.sgs.api.quark.engine.infra.dao.InsertDocumentDao;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Orchestrates run finalization within a single transaction.
 * Inserts generated documents, updates run status, stores errors and data.
 *
 * Cross-reference: .NET Proxy_Run.End_Run()
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class EndRunBusiness {

    private static final int ID_SOUS_CATEGORIE_QXP = 6;
    private static final int ID_SOUS_CATEGORIE_PDF = 7;
    private static final int ID_SOUS_CATEGORIE_DOC = 8;

    private final EndRunDao endRunDao;
    private final InsertDocumentDao insertDocumentDao;
    private final InsertDataStorageDao insertDataStorageDao;
    private final AuditDao auditDao;

    /**
     * Finalize a run — insert documents, errors, data, and update status.
     * All operations within a single transaction.
     *
     * @param run the run to finalize
     */
    @Transactional
    public void execute(Run run) {
        log.info("Finalizing run [{}] with status [{}]", run.getId(), run.getStatus());

        run.setEndDate(LocalDateTime.now());
        int statusCode = run.getStatus().getCode();

        // Accumulated run trace persisted to the p_log_trace CLOB. Cross-reference: .NET Run.Trace_Context.All_Logs.
        String traceLog = run.getTraceLog();

        if (run.getStatus() == RunStatus.ERROR) {
            // Error case: just update status
            endRunDao.updateStatusRun(
                    run.getId(), statusCode, statusCode,
                    run.getEndDate(), traceLog);

        } else {
            // Success case: insert documents then end run
            int idQxp = insertGeneratedDocument(run, run.getResult().getFinalQxp(), ID_SOUS_CATEGORIE_QXP);
            int idPdf = insertGeneratedDocument(run, run.getResult().getFinalPdf(), ID_SOUS_CATEGORIE_PDF);
            int idDoc = Integer.MIN_VALUE; // Word not generated (skipped in .NET too)

            endRunDao.endRun(
                    run.getId(), statusCode,
                    run.getRunProperties().getIdSuivi(), statusCode,
                    run.getEndDate(), traceLog,
                    idPdf, idQxp, idDoc);
        }

        // Always insert errors
        insertErrors(run);

        // Always insert the audit row (matches .NET End_Run order: status/end -> errors -> audit -> data).
        auditDao.insertAuditRun(run, buildAuditMessage(run));

        // Store data only if not in error
        if (run.getStatus() != RunStatus.ERROR) {
            insertDataStorage(run);
        }

        log.info("Run [{}] finalized successfully", run.getId());
    }

    private int insertGeneratedDocument(Run run, DocumentDomain document, int idSousCategorie) {
        if (document == null || document.getData() == null) {
            return Integer.MIN_VALUE;
        }
        return insertDocumentDao.insertDocument(
                document, idSousCategorie,
                run.getRunProperties().getIdFndCode(),
                run.getRunProperties().getIdUnitCode(),
                run.getRunProperties().getDateEcheance(),
                run.getId());
    }

    /** Short audit message: status + error summary (the DAO truncates to the column size). */
    private String buildAuditMessage(Run run) {
        List<RunError> errors = run.getErrors();
        if (errors.isEmpty()) {
            return "Run " + run.getId() + " " + run.getStatus();
        }
        return "Run " + run.getId() + " " + run.getStatus()
                + " - " + errors.size() + " error(s): " + errors.get(0).getMessage();
    }

    private void insertErrors(Run run) {
        List<RunError> errors = run.getErrors();
        if (errors.isEmpty()) return;

        String[] messages = new String[errors.size()];
        int[] categories = new int[errors.size()];

        for (int i = 0; i < errors.size(); i++) {
            messages[i] = errors.get(i).getMessage();
            categories[i] = errors.get(i).getCategory();
        }

        endRunDao.insertRunErrors(run.getId(), messages, categories);
    }

    /**
     * Insert data storage entries for SQL and DOCUMENT types.
     * SQL data uses simple historisation (0), DOCUMENT uses differential (1).
     *
     * Cross-reference: .NET Proxy_Store.Insert_Data_Storage
     */
    private void insertDataStorage(Run run) {
        StoreDataType storeType = run.getRunProperties().getStoreDataType();

        // SQL data storage (historisation_differentielle = false)
        if (storeType.hasFlag(StoreDataType.SQL) && !run.getSqlDataNamesValues().isEmpty()) {
            String[][] arrays = toArrays(run.getSqlDataNamesValues());
            insertDataStorageDao.insertData(
                    run.getRunProperties().getIdSuivi(),
                    run.getId(),
                    run.getEndDate(),
                    StoreDataType.SQL.getCode(),
                    arrays[0], arrays[1], arrays[2], arrays[3],
                    false);
        }

        // Document data storage (historisation_differentielle = true)
        if (storeType.hasFlag(StoreDataType.DOCUMENT) && !run.getDocDataNamesValues().isEmpty()) {
            String[][] arrays = toArrays(run.getDocDataNamesValues());
            insertDataStorageDao.insertData(
                    run.getRunProperties().getIdSuivi(),
                    run.getId(),
                    run.getEndDate(),
                    StoreDataType.DOCUMENT.getCode(),
                    arrays[0], arrays[1], arrays[2], arrays[3],
                    true);
        }
    }

    /**
     * Convert DataNameValue list to parallel arrays.
     * Cross-reference: .NET DataNamesValues.ToArrays()
     *
     * @return [0]=names, [1]=values, [2]=descriptifs, [3]=infos
     */
    private String[][] toArrays(List<DataNameValue> dataList) {
        int maxNameSize = 30;
        int maxValueSize = 500;
        int maxDescriptifSize = 250;
        int maxInfoSize = 4000;

        String[] names = new String[dataList.size()];
        String[] values = new String[dataList.size()];
        String[] descriptifs = new String[dataList.size()];
        String[] infos = new String[dataList.size()];

        for (int i = 0; i < dataList.size(); i++) {
            DataNameValue dnv = dataList.get(i);
            names[i] = truncate(dnv.getName(), maxNameSize);
            values[i] = truncate(dnv.getValue(), maxValueSize);
            descriptifs[i] = truncate(dnv.getDescriptif(), maxDescriptifSize);
            infos[i] = truncate(dnv.getInfo(), maxInfoSize);
        }

        return new String[][]{names, values, descriptifs, infos};
    }

    private String truncate(String value, int maxLength) {
        if (value == null) return "";
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}
```

## 5. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java`  — **CHANGED (also touched in Batches 2 & 6)**

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
    private final GetInParamsBusiness      getInParamsBusiness;
    private final LoadTasksService         loadTasksService;
    private final FilePoolPort             filePoolPort;
    private final DocumentIdentityPort     documentIdentityPort;
    private final ProcessTasksService      processTasksService;
    private final QxpsCallerService        qxpsCallerService;
    private final CheckService             checkService;
    private final LoadTemplatesBusiness    loadTemplatesBusiness;
    private final EndRunBusiness           endRunBusiness;

    @Value("${engine.gabarit.size-limit-before-fail-soft:209715200}")
    private long sizeLimitBeforeFailSoft;

    @Override
    public void runProcessor(RunIdDto runIdDto) {
        log.info("Processing run with runId: {}", runIdDto.getRunId());
        Run run = new Run(sizeLimitBeforeFailSoft);
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
            run.getErrors().add(new RunError(1, ex.getMessage()));
            run.trace("ERROR: " + ex.getMessage());
        } finally {
            run.trace("Run ending with status " + run.getStatus());
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

        // Step 2: Delegate gabarit preparation entirely to run domain
        run.prepareGabarit(getGabaritBusiness, filePoolPort, documentIdentityPort);

        // Step 3: Inject and execute GetInParamsBusiness
        getInParamsBusiness.execute(run);

        // Step 4: Load tasks
        loadTasksService.loadTasks(run);

        //step 5: load templates for dynamic tasks
        loadTemplatesBusiness.execute(run);
        //pending implementation
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

