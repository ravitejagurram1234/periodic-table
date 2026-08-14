# EOS Quark Engine — Fix Batch 1 Complete Java Copy Packet

This document contains the complete final content of every Java production class and test class changed in Fix Batch 1.
Each code block is generated directly from the corresponding repository file and can replace that file in full.

## Change inventory

1. `Run.prepareGabarit`: structural XML retrieval/parsing failure now caches empty XML, marks both document and
   run degraded, skips the separate DID request and leaves Render/End available. Size-triggered degradation also
   marks both objects. Successful parsing logs only run ID plus box/page counts.
2. `LoadTasksServiceImpl`: missing-task and duplicate-block exception rows now add the same Unspecified (1) run
   errors as .NET while continuing. Logs use task/run/block identifiers and aggregate counts; no task SQL is logged.
3. `LoadTemplatesBusiness`: an empty gabarit-template document result is deferred to per-task Prepare handling;
   duplicate or null template names fail Load like `.NET Dictionary.Add`. Template degradation marks document/run.
4. `GetGabaritTemplateDaoImpl`: an empty cursor returns `null`, and the pool filename is `GT_<id>.QXP`.
5. `TaskMapper`: a NULL `NB_DECIMAL` maps to `Integer.MIN_VALUE`, preserving the .NET unset sentinel.
6. `DataTypeHelper`: unset or out-of-range decimal precision uses the standard fixed two-digit default; configured
   precision 0–10 retains the existing significant/optional-zero behavior.
7. Focused tests cover retrieval failure, malformed XML, size degradation, nonblocking exception continuation,
   duplicate/null template names, missing template documents, per-task Prepare isolation, uppercase filenames and
   default decimal/currency/percentage formatting.

No REST endpoint, RabbitMQ configuration/listener, task SQL text, Oracle package, schema or size-threshold value is
changed by this packet.

## Production classes

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/Run.java`

SHA-256: `1f7908610d927ae787c1b7005ea164f76316b35353b71afc08f3b36997b75196`

```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness;
import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
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

    /**
     * The gabarit TEMPLATE document (distinct from the source {@link #gabarit}). Loaded only when the
     * run has dynamic tasks and an id_gabarit_template is set; dynamic tasks clone their blocs from
     * this document. Cross-reference: .NET Run_Base._gabarit_Template (Run.cs:152 Get_Gabarit_Template).
     */
    private DocumentDomain gabaritTemplate;

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
        // gabarit by getFilePoolPath().
        filePoolPort.addFile(this.gabarit.getFilePoolPath(), this.gabarit.getData());

        // Step 2: Mode_Degrade — if the template exceeds the size limit, skip ONLY the DID parse and
        // the full-XML load (steps 3-4). Parity: .NET Document.cs:200 gates only the DID parse inside
        // Evaluate_Document_Identity, and the Document.XML getter returns QXP_XML.Empty in degrade mode.
        // The pool upload above has already run, so the degraded render has its document. (Findings #0, #7, #24.)
        if (this.gabarit.evaluateModeDegrade(sizeLimitBeforeFailSoft)) {
            log.warn("Gabarit size {} bytes exceeds limit {} bytes, setting Mode_Degrade for runId: {}",
                    this.gabarit.getData().length, sizeLimitBeforeFailSoft, this.id);
            this.gabarit.setModeDegrade(true);
            this.runProperties.setModeDegrade(true);
            return;
        }

        // Step 3: Load the FULL gabarit XML into the domain object so page/layout/box info is
        // available during Prepare and Process (before Check). Parity: .NET first materialises
        // this.Gabarit.XML right after Addfile (Run.cs:99) and caches it (Document.cs:421-444);
        // without this the gabarit XML stays QxpXml.EMPTY until Check, breaking anchor/page/box
        // evaluation in Dynamique and Compartiment-incorporate tasks. (Finding #25.)
        String fullXml = getGabaritXmlBusiness.fetchXml(this.gabarit.getFilePoolPath());
        QxpXml parsedXml = QxpXml.createFromXml(fullXml);
        if (parsedXml == null) {
            // .NET Document.XML catches both QXPS retrieval and XML parsing failures, caches
            // QXP_XML.Empty, switches the document/run to Mode_Degrade, and keeps the run alive.
            // Do not make the separate Java DID request after this point: it would incorrectly turn
            // the fail-soft path into a top-level ERROR.
            this.gabarit.setQxpXml(QxpXml.EMPTY);
            this.gabarit.setModeDegrade(true);
            this.runProperties.setModeDegrade(true);
            log.warn("Unable to load structural XML; continuing run [{}] in Mode_Degrade", this.id);
            return;
        }
        this.gabarit.setQxpXml(parsedXml);
        log.info("Gabarit structure loaded for run [{}]: {} boxes across {} pages",
                this.id,
                parsedXml.getProjectInfo().getNbBox(),
                parsedXml.getProjectInfo().getNbPage());

        // Step 4: Fetch XML for the DID box and parse document identity. Parity: .NET
        // Evaluate_Document_Identity (Document.cs:205). Keyed on getFilePoolPath() so the DID fetch
        // hits the same pooled document that was uploaded and that the modify/render path operates on.
        String xmlContent = documentIdentityPort.fetchXmlForBox(this.gabarit.getFilePoolPath(), "DID");
        String didValue = documentIdentityPort.getElementValueByIdName(xmlContent, "DID");
        DocumentIdentity identity = documentIdentityPort.parseDocumentIdentity(didValue);

        // Step 5: Set the document identity on the gabarit domain object
        this.gabarit.setDocumentIdentity(identity);
        log.info("Gabarit identity evaluation completed for run [{}]", this.id);
    }
}
```

### `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/LoadTasksServiceImpl.java`

SHA-256: `013071daea207ba6c8f2ea9a5a845393e5c77eb401e60155892b89266e38dd1e`

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.business.GetTasksBusiness;
import com.socgen.sgs.api.quark.engine.business.GetTaskExceptionsBusiness;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDid;
import com.socgen.sgs.api.quark.engine.domain.task.TaskException;
import com.socgen.sgs.api.quark.engine.mapper.TaskExceptionMapper;
import com.socgen.sgs.api.quark.engine.mapper.TaskMapper;
import com.socgen.sgs.api.quark.engine.service.LoadTasksService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Service
@Slf4j
@RequiredArgsConstructor
public class LoadTasksServiceImpl implements LoadTasksService {

    private final GetTasksBusiness getTasksBusiness;
    private final GetTaskExceptionsBusiness getTaskExceptionsBusiness;
    private final TaskMapper taskMapper;
    private final TaskExceptionMapper taskExceptionMapper;

    @Override
    public void loadTasks(Run run) {
        log.info("Loading tasks for runId: {}", run.getId());

        List<Map<String, Object>> rows = getTasksBusiness.execute(run.getId());
        run.getTasks().clear();

        for (Map<String, Object> row : rows) {
            TaskBase task = taskMapper.mapToTask(row, run);
            if (task != null) {
                run.getTasks().put(task.getId(), task);
            }
        }

        log.info("Loaded {} tasks for runId: {}", run.getTasks().size(), run.getId());

        loadTaskExceptions(run);

        //adding did_Task
        TaskDid didTask = new TaskDid(TaskDid.DID_TASK_ID, run);
        run.getTasks().put(didTask.getId(), didTask);
        log.info("DID task added for runId: {}", run.getId());
    }

    private void loadTaskExceptions(Run run) {
        log.info("Loading task exceptions for runId: {}", run.getId());

        List<Map<String, Object>> rows = getTaskExceptionsBusiness.execute(run.getId());
        TaskBase cachedTask = null;
        int loadedCount = 0;
        int missingTaskCount = 0;
        int duplicateBlocCount = 0;

        for (Map<String, Object> row : rows) {
            int idTache = taskExceptionMapper.getIdTache(row);
            String nomBloc = taskExceptionMapper.getNomBloc(row);

            // Local cache: reuse last task if same id
            if (cachedTask == null || cachedTask.getId() != idTache) {
                if (run.getTasks().containsKey(idTache)) {
                    cachedTask = run.getTasks().get(idTache);
                } else {
                    cachedTask = null;
                    missingTaskCount++;
                    run.getErrors().add(new RunError(RunError.UNSPECIFIED, String.format(
                            "impossible de définir l'exception [%s] pour la tache %d "
                                    + "qui est introuvable dans le run %d",
                            nomBloc, idTache, run.getId())));
                    log.warn("Task {} not found in run {} for bloc exception '{}'", idTache, run.getId(), nomBloc);
                    continue;
                }
            }

            TaskException taskException = taskExceptionMapper.mapToTaskException(row);

            if (cachedTask.getExceptions().containsKey(nomBloc)) {
                duplicateBlocCount++;
                run.getErrors().add(new RunError(RunError.UNSPECIFIED, String.format(
                        "Le bloc %s est déjà défini dans la tache %s du run %d",
                        nomBloc, cachedTask.getDebugInfo(), run.getId())));
                log.warn("Duplicate bloc exception '{}' for taskId {} in run {}",
                        nomBloc, cachedTask.getId(), run.getId());
            } else {
                cachedTask.getExceptions().put(nomBloc, taskException);
                loadedCount++;
            }
        }

        log.info("Task exception loading completed for run [{}]: {} loaded, {} missing-task rows skipped, "
                        + "{} duplicate-block rows skipped",
                run.getId(), loadedCount, missingTaskCount, duplicateBlocCount);
    }
}
```

### `src/main/java/com/socgen/sgs/api/quark/engine/business/LoadTemplatesBusiness.java`

SHA-256: `87254c58c8d0d42f5684a9b68dc8d498cac5fbb5850ef6782065280517a2072e`

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;
import com.socgen.sgs.api.quark.engine.infra.dao.GetGabaritTemplateDao;
import com.socgen.sgs.api.quark.engine.mapper.TemplateMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/**
 * Business component for loading templates from the database into a Run.
 *
 * Cross-reference: .NET Proxy_Template.Load_Templates(Run)
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class LoadTemplatesBusiness {

    private final GetGabaritTemplateDao getGabaritTemplateDao;
    private final TemplateMapper templateMapper;

    /**
     * Load all templates for the run's gabarit template into run.getTemplates().
     *
     * @param run the run to populate with templates
     */
    public void execute(Run run) {
        // .NET Run.cs:132-165 only loads the template + templates when at least one dynamic task is
        // TODO (GetEnumerable<Task_Dynamique>(true)); otherwise it does nothing. Finding #56.
        boolean hasDynamicTodo = run.getTasks().values().stream()
                .anyMatch(t -> t instanceof TaskDynamique && t.isTodo());
        if (!hasDynamicTodo) {
            log.info("No TODO dynamic task for run [{}], skipping template loading", run.getId());
            return;
        }

        int idGabaritTemplate = run.getRunProperties().getIdGabaritTemplate();
        if (idGabaritTemplate == Integer.MIN_VALUE) {
            // .NET raises Exception_Run(MSG_Missing_ID_Gabarit_Template, Gabarit.ID) → Bloquante:
            // a dynamic run with no template id is a hard configuration error, not a silent skip.
            // Finding #56.
            Object gabId = run.getGabarit() != null ? run.getGabarit().getId() : run.getId();
            run.getErrors().add(new RunError(RunError.BLOQUANTE, String.format(
                    "Manque l'identifiant du gabarit template pour le gabarit %s", gabId)));
            log.error("Missing id_gabarit_template for run [{}] which has TODO dynamic tasks", run.getId());
            return;
        }

        log.info("Loading templates for idGabaritTemplate={} in run [{}]",
                idGabaritTemplate, run.getId());

        // Load the gabarit TEMPLATE document itself FIRST (parity: .NET Run.cs:152
        // this.Gabarit_Template = Get_Gabarit_Template(this); then :157 Load_Templates(this)).
        // Dynamic tasks clone their blocs from this document — without it TaskDynamique.prepare
        // would upload the wrong document. Finding #6/#22.
        DocumentDomain gabaritTemplate = getGabaritTemplateDao.getGabaritTemplate(idGabaritTemplate);
        run.setGabaritTemplate(gabaritTemplate);
        if (gabaritTemplate != null) {
            // The DAO builder sets fileName but not filePoolPath; populate it the same way the source
            // gabarit is set up (GetGabaritBusiness.preparePaths → getPoolPath), so the upload key and
            // every later pool lookup resolve to the same R_<runId>/<fileName> string.
            gabaritTemplate.setFilePoolPath(run.getRunProperties().getPoolPath(gabaritTemplate.getFileName()));

            // .NET Run_Base.Mode_Degrade degrades the run when either QXP document is oversized.
            if (gabaritTemplate.evaluateModeDegrade(run.getSizeLimitBeforeFailSoft())) {
                log.warn("Gabarit template {} bytes exceeds limit {} → setting Mode_Degrade for run [{}]",
                        gabaritTemplate.getData().length, run.getSizeLimitBeforeFailSoft(), run.getId());
                gabaritTemplate.setModeDegrade(true);
                run.getRunProperties().setModeDegrade(true);
            }
        } else {
            // .NET Get_Gabarit_Template returns null for an empty cursor and still loads the named
            // template definitions. Dynamic tasks then fail independently during Prepare (Critique),
            // instead of turning the whole Load phase into a Bloquante error.
            log.warn("No gabarit template document found for id {} in run {}; "
                            + "dynamic tasks will report their own Prepare errors",
                    idGabaritTemplate, run.getId());
        }

        List<Map<String, Object>> rows = getGabaritTemplateDao.getTemplates(idGabaritTemplate);

        run.getTemplates().clear();

        for (Map<String, Object> row : rows) {
            Template template = templateMapper.mapToTemplate(row);
            if (template != null) {
                if (template.getName() == null) {
                    // Dictionary.Add in .NET rejects a null key during Load as well.
                    log.error("Template with null name found for gabaritTemplateId {} in run {}",
                            idGabaritTemplate, run.getId());
                    throw new IllegalStateException(String.format(
                            "Template name is null for gabarit template %d", idGabaritTemplate));
                }
                if (run.getTemplates().containsKey(template.getName())) {
                    // .NET uses Dictionary.Add: a duplicate name throws during Load. The top-level
                    // run handler records that load failure as Bloquante and sets status ERROR.
                    log.error("Duplicate template name '{}' for gabaritTemplateId {} in run {}",
                            template.getName(), idGabaritTemplate, run.getId());
                    throw new IllegalStateException(String.format(
                            "Duplicate template name '%s' for gabarit template %d",
                            template.getName(), idGabaritTemplate));
                }
                run.getTemplates().put(template.getName(), template);
            }
        }

        log.info("Loaded {} templates for run [{}]", run.getTemplates().size(), run.getId());
    }
}
```

### `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/GetGabaritTemplateDaoImpl.java`

SHA-256: `32072ee2b1764d28caeec91d2c58b3788b891deaa4739d74c97079f9de0983ec`

```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.infra.dao.GetGabaritTemplateDao;
import lombok.extern.slf4j.Slf4j;
import oracle.jdbc.OracleTypes;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.ColumnMapRowMapper;
import org.springframework.jdbc.core.SqlOutParameter;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * Calls Oracle functions QXP_PK_TEMPLATE.Get_Gabarit_Template and Get_Templates.
 */
@Repository
@Slf4j
public class GetGabaritTemplateDaoImpl implements GetGabaritTemplateDao {

    private static final String RESULT_KEY = "result_cursor";
    private static final String PACKAGE     = "QXP_PK_TEMPLATE";

    private final SimpleJdbcCall getGabaritTemplateCall;
    private final SimpleJdbcCall getTemplatesCall;

    @Autowired
    public GetGabaritTemplateDaoImpl(DataSource dataSource) {
        this.getGabaritTemplateCall = new SimpleJdbcCall(dataSource)
                .withCatalogName(PACKAGE)
                .withFunctionName("Get_Gabarit_Template")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlOutParameter(RESULT_KEY, OracleTypes.CURSOR,
                                (rs, rowNum) -> mapGabaritTemplate(rs)),
                        new SqlParameter("p_id_gabarit_template", Types.NUMERIC)
                );

        this.getTemplatesCall = new SimpleJdbcCall(dataSource)
                .withCatalogName(PACKAGE)
                .withFunctionName("Get_Templates")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlOutParameter(RESULT_KEY, OracleTypes.CURSOR, new ColumnMapRowMapper()),
                        new SqlParameter("p_id_gabarit_template", Types.NUMERIC)
                );
    }

    private DocumentDomain mapGabaritTemplate(ResultSet rs) throws SQLException {
        int id = rs.getInt("id_gabarit_template");
        return DocumentDomain.builder()
                .id(id)
                .name(rs.getString("nom"))
                .data(rs.getBytes("contenu"))
                .format("QXP")
                .prefix(DocumentDomain.FILE_GABARIT_TEMPLATE_PREFIX)
                .gabarit(true)
                .fileName(String.format("%s_%d.%s",
                        DocumentDomain.FILE_GABARIT_TEMPLATE_PREFIX, id, "QXP"))
                .build();
    }

    @Override
    public DocumentDomain getGabaritTemplate(int idGabaritTemplate) {
        log.info("Fetching gabarit template for idGabaritTemplate: {}", idGabaritTemplate);

        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_gabarit_template", idGabaritTemplate);

        Map<String, Object> result = getGabaritTemplateCall.execute(params);

        @SuppressWarnings("unchecked")
        List<DocumentDomain> rows = (List<DocumentDomain>) result.get(RESULT_KEY);

        if (rows == null || rows.isEmpty()) {
            // .NET Proxy_Template.Get_Gabarit_Template returns null when its cursor is empty.
            log.warn("No gabarit template found for idGabaritTemplate: {}", idGabaritTemplate);
            return null;
        }

        log.info("Successfully retrieved gabarit template for idGabaritTemplate: {}", idGabaritTemplate);
        return rows.get(0);
    }

    @Override
    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> getTemplates(int idGabaritTemplate) {
        log.info("Fetching templates for idGabaritTemplate: {}", idGabaritTemplate);

        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_gabarit_template", idGabaritTemplate);

        Map<String, Object> result = getTemplatesCall.execute(params);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) result.get(RESULT_KEY);

        if (rows == null) {
            log.warn("No templates returned for idGabaritTemplate: {}", idGabaritTemplate);
            return Collections.emptyList();
        }

        log.info("Fetched {} template rows for idGabaritTemplate: {}", rows.size(), idGabaritTemplate);
        return rows;
    }
}
```

### `src/main/java/com/socgen/sgs/api/quark/engine/mapper/TaskMapper.java`

SHA-256: `c5c7e75f64e87afe0649fd67d72c195b8d61d53cde89862eb8bffed905cce04e`

```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBreakRules;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DMasterPage;
import com.socgen.sgs.api.quark.engine.domain.task.*;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import com.socgen.sgs.api.quark.engine.enums.TaskTypeEnum;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.util.Map;

@Component
@Slf4j
@RequiredArgsConstructor
public class TaskMapper {

    private final FilePoolPort filePoolPort;

    public TaskBase mapToTask(Map<String, Object> row, Run run) {
        int idTache = getInt(row, "ID_TACHE");
        int idTypeTache = getInt(row, "ID_TYPE_TACHE");
        TaskTypeEnum taskType = TaskTypeEnum.fromCode(idTypeTache); // it's a single time used variable, pass it directly

        TaskBase task = createTaskByType(taskType, idTache, run, row);
        if (task != null) {
            mapCommonFields(row, task);
        }
        return task;
    }

    private TaskBase createTaskByType(TaskTypeEnum taskType, int idTache, Run run, Map<String, Object> row) {
        switch (taskType) {
            case SQL:
                TaskSql taskSql = new TaskSql(idTache, run);
                mapTaskSql(row, taskSql);
                return taskSql;
            case DOC_EOS:
                TaskDocument taskDoc = new TaskDocument(idTache, run);
                mapTaskDocument(row, taskDoc);
                return taskDoc;
            case DOC_QXP:
                TaskQxpPrevious taskQxp = new TaskQxpPrevious(idTache, run);
                mapTaskQxpPrevious(row, taskQxp);
                return taskQxp;
            case SQL_DYNAMIQUE:
                TaskDynamique taskDyn = new TaskDynamique(idTache, run);
                taskDyn.setFilePoolService(filePoolPort);
                mapTaskDynamique(row, taskDyn);
                return taskDyn;
            case COMPARTIMENTS:
                TaskCompartiment taskComp = new TaskCompartiment(idTache, run);
                mapTaskCompartiment(row, taskComp);
                return taskComp;
            default:
                log.warn("Unknown task type code: {} for taskId: {}", taskType, idTache);
                return null;
        }
    }

    private void mapTaskSql(Map<String, Object> row, TaskSql task) {
        task.setSql(getString(row, "SQL"));
        task.setShowZero(getBoolean(row, "AFFICHER_ZERO"));
        // Oracle NULL maps to int.MinValue in the .NET OraDataReader conversion layer. This sentinel
        // selects the framework's default numeric pattern; mapping NULL to 0 changes output formatting.
        task.setNbDecimal(getIntOrDefault(row, "NB_DECIMAL", Integer.MIN_VALUE));
        task.setDecimalSignificative(getBoolean(row, "DECIMAL_SIGNIFICATIVE"));
        task.setStoreData(getBoolean(row, "STORE_DATA"));

        int idDataType = getInt(row, "OUTPUT_DATA_TYPE");
        try {
            task.setDataType(DataTypeEnum.fromCode(idDataType));
        } catch (Exception e) {
            log.error("Invalid data type {} for taskId {}", idDataType, task.getId());
        }
    }

    private void mapTaskDocument(Map<String, Object> row, TaskDocument task) {
        task.setFormatDocument(getString(row, "FORMAT"));
        task.setRotationImage(getBoolean(row, "ROTATION_IMAGE"));
        task.setIdSousCategorie(getInt(row, "ID_SOUS_CATEGORIE"));
        task.setOffsetValues(getString(row, "CROP_IMAGE_VALUES"));
        task.setConserverStyle(getBoolean(row, "CONSERVER_STYLE"));
        task.setSourceBlocName(getString(row, "BLOC_SOURCE"));
        task.setDestinationBlocName(getString(row, "BLOC_DESTINATION"));
        task.setPositionValues(getString(row, "POSITION_IMAGE"));
    }

    private void mapTaskQxpPrevious(Map<String, Object> row, TaskQxpPrevious task) {
        task.setConserverStyle(getBoolean(row, "CONSERVER_STYLE"));
        task.setPreviousTypeRapport(getString(row, "PREVIOUS_TYPE_RAPPORT"));
        task.setSourceBlocName(getString(row, "BLOC_SOURCE"));
        task.setDestinationBlocName(getString(row, "BLOC_DESTINATION"));
    }

    private void mapTaskDynamique(Map<String, Object> row, TaskDynamique task) {
        task.setSql(getString(row, "SQL"));
        task.setDestinationBlocName(getString(row, "BLOC_DESTINATION"));
        task.setControlOverflow(getBoolean(row, "CONTROL_OVERFLOW"));
        task.setNewPageTable(getBoolean(row, "NEW_PAGE_TABLE"));
        task.setNbColumn(getInt(row, "NB_COLUMN"));
        task.setStoreData(getBoolean(row, "STORE_DATA"));

        BigDecimal colSpace = getBigDecimal(row, "COLUMN_SPACE");
        if (colSpace != null) {
            task.setColumnSpace(colSpace);
        }

        String codeMasterPage = getString(row, "CODE_MASTER_PAGE");
        task.setMasterPage(isSet(codeMasterPage) ? new DMasterPage(codeMasterPage) : DMasterPage.DEFAULT);

        String pageBreakRules = getString(row, "PAGE_BREAK_RULES");
        task.setPageBreakRules(isSet(pageBreakRules) ? new DBreakRules(pageBreakRules) : DBreakRules.DEFAULT);

        String columnBreakRules = getString(row, "COLUMN_BREAK_RULES");
        task.setColumnBreakRules(isSet(columnBreakRules) ? new DBreakRules(columnBreakRules) : DBreakRules.DEFAULT);
    }

    private void mapTaskCompartiment(Map<String, Object> row, TaskCompartiment task) {
        task.setDestinationBlocName(getString(row, "BLOC_DESTINATION"));
        task.setIdGabaritFils(getInt(row, "ID_GABARIT_FILS"));

        String codeMasterPage = getString(row, "CODE_MASTER_PAGE");
        task.setMasterPage(isSet(codeMasterPage) ? new DMasterPage(codeMasterPage) : DMasterPage.DEFAULT);
    }

    private void mapCommonFields(Map<String, Object> row, TaskBase task) {
        String nullString = getString(row, "CHAMPS_VIDE");
        if (isSet(nullString)) {
            task.setNullString(nullString);
        }
        task.setTodo(getBoolean(row, "TODO"));
        task.setCommentaire(getString(row, "COMMENTAIRE"));
    }

    // --- Utility extraction methods ---

    private String getString(Map<String, Object> row, String key) {
        Object val = row.get(key);
        return val != null ? val.toString() : null;
    }

    private int getInt(Map<String, Object> row, String key) {
        return getIntOrDefault(row, key, 0);
    }

    private int getIntOrDefault(Map<String, Object> row, String key, int defaultValue) {
        Object val = row.get(key);
        if (val instanceof Number) {
            return ((Number) val).intValue();
        }
        return defaultValue;
    }

    private boolean getBoolean(Map<String, Object> row, String key) {
        Object val = row.get(key);
        if (val instanceof Number) {
            return ((Number) val).intValue() != 0;
        }
        if (val instanceof Boolean) {
            return (Boolean) val;
        }
        return false;
    }

    private BigDecimal getBigDecimal(Map<String, Object> row, String key) {
        Object val = row.get(key);
        if (val instanceof BigDecimal) {
            return (BigDecimal) val;
        }
        if (val instanceof Number) {
            return BigDecimal.valueOf(((Number) val).doubleValue());
        }
        return null;
    }

    private boolean isSet(String value) {
        return value != null && !value.isBlank();
    }
}
```

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/helper/DataTypeHelper.java`

SHA-256: `b8bc4958c79af74041f07e6d116f5ed4dd6f8eda577f6d222519f38116439b47`

```java
package com.socgen.sgs.api.quark.engine.domain.helper;

import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

/** Converts raw DB values to formatted strings based on DataTypeEnum configuration. */
public final class DataTypeHelper {

    private static final int DEFAULT_FRACTION_DIGITS = 2;

    private static final DateTimeFormatter DATE_FMT = DateTimeFormatter.ofPattern("dd/MM/yyyy");
    private static final DateTimeFormatter DATETIME_FMT = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm:ss");

    /**
     * fr-FR symbols (NBSP thousands grouping, ',' decimal, "€" currency). The .NET engine renders
     * under the French thread culture, matching the existing decimal formatting in this class.
     */
    private static final DecimalFormatSymbols FR_SYMBOLS = new DecimalFormatSymbols(Locale.FRANCE);

    private DataTypeHelper() {
    }

    public static String outputToString(Object value, DataTypeEnum dataType, int nbDecimal,
                                        boolean showZero, String nullString, boolean decimalSignificative) {
        if (value == null) {
            return nullString;
        }

        String raw = value.toString().trim();
        if (raw.isEmpty()) {
            return nullString;
        }

        switch (dataType) {
            case INT:
                return formatInteger(raw, showZero, nullString);
            case DECIMAL:
                return formatDecimal(raw, nbDecimal, showZero, nullString, decimalSignificative);
            case CURRENCY:
                // .NET CurrencyPattern "#,##0.{0} {1}" → number + " " + currency symbol (fr-FR → "€").
                // No ×100. Cross-reference: Data_Type_Helper.GetStringCurrency. Finding #14.
                return formatWithSuffix(raw, nbDecimal, showZero, nullString, decimalSignificative,
                        " " + FR_SYMBOLS.getCurrencySymbol());
            case POURCENTAGE:
                // Data is stored SCALED (15 == 15%), confirmed from QXP_PK_KII SQL ((montant/actif)*100
                // to produce, taux*vb/100 to consume). So append a single " %" WITHOUT multiplying by 100,
                // matching .NET's correct formatter QXP_Format_Helper (plain number + literal " %").
                // This is a deliberate, user-approved deviation from the engine's
                // Data_Type_Helper.GetStringPourcentage, which is bugged (×100 via the "%" specifier PLUS
                // a second appended " %", flagged "// TODO à voir si c'est correct") and would render 15
                // as "1 500,00 % %". Finding #14.
                return formatWithSuffix(raw, nbDecimal, showZero, nullString, decimalSignificative, " %");
            case DATE:
                return formatDate(raw, nullString);
            case DATE_TIME:
                return formatDateTime(raw, nullString);
            default:
                return raw;
        }
    }

    private static String formatInteger(String raw, boolean showZero, String nullString) {
        try {
            long val = Long.parseLong(raw);
            if (val == 0 && !showZero) return nullString;
            // Grouped output (NBSP under fr-FR), matching .NET GetStringInt which uses the "n" format
            // specifier (always groups). Finding #12.
            return new DecimalFormat("#,##0", FR_SYMBOLS).format(val);
        } catch (NumberFormatException e) {
            return raw;
        }
    }

    private static String formatDecimal(String raw, int nbDecimal, boolean showZero,
                                        String nullString, boolean decimalSignificative) {
        try {
            String formatted = formatDecimalCore(raw, nbDecimal, showZero, decimalSignificative);
            return formatted == null ? nullString : formatted;
        } catch (NumberFormatException e) {
            return raw;
        }
    }

    /** DECIMAL formatting with a trailing suffix (currency symbol or " %"); suffix is omitted when the
     *  value is treated as null (zero with showZero=false) or unparseable. */
    private static String formatWithSuffix(String raw, int nbDecimal, boolean showZero,
                                           String nullString, boolean decimalSignificative, String suffix) {
        try {
            String formatted = formatDecimalCore(raw, nbDecimal, showZero, decimalSignificative);
            return formatted == null ? nullString : formatted + suffix;
        } catch (NumberFormatException e) {
            return raw;
        }
    }

    /**
     * Core decimal formatter shared by DECIMAL / CURRENCY / POURCENTAGE.
     * Returns the formatted number, or {@code null} to signal "use nullString" (zero with showZero=false).
     * Throws {@link NumberFormatException} on unparseable input so callers can fall back to the raw value.
     *
     * <p>decimalSignificative drives the fraction digits, matching .NET GetDecimalPattern:
     * true → fixed nbDecimal decimals with trailing zeros ('0' pattern); false → suppress trailing
     * zeros up to nbDecimal ('#' pattern). Finding #13. Rounding is HALF_UP (round half away from
     * zero), matching .NET Decimal.ToString, instead of DecimalFormat's default HALF_EVEN.
     */
    private static String formatDecimalCore(String raw, int nbDecimal, boolean showZero,
                                            boolean decimalSignificative) {
        BigDecimal val = new BigDecimal(raw);
        if (val.compareTo(BigDecimal.ZERO) == 0 && !showZero) {
            return null;
        }
        boolean hasConfiguredPrecision = nbDecimal >= 0 && nbDecimal <= 10;
        int fractionDigits = hasConfiguredPrecision ? nbDecimal : DEFAULT_FRACTION_DIGITS;
        DecimalFormat df = new DecimalFormat("#,##0", FR_SYMBOLS);
        df.setMaximumFractionDigits(fractionDigits);
        // .NET falls back to standard "n"/"c"/"p" formats when NB_DECIMAL is unset or outside
        // 0..10. Those formats use the culture's fixed default precision (2 for fr-FR), regardless
        // of DECIMAL_SIGNIFICATIVE. Percentage retains this port's approved scaled-data behavior.
        df.setMinimumFractionDigits(hasConfiguredPrecision && !decimalSignificative ? 0 : fractionDigits);
        df.setRoundingMode(RoundingMode.HALF_UP);
        return df.format(val);
    }

    private static String formatDate(String raw, String nullString) {
        try {
            LocalDate date = LocalDate.parse(raw.substring(0, 10));
            return date.format(DATE_FMT);
        } catch (Exception e) {
            return raw.isEmpty() ? nullString : raw;
        }
    }

    private static String formatDateTime(String raw, String nullString) {
        try {
            LocalDateTime dt = LocalDateTime.parse(raw.substring(0, 19));
            return dt.format(DATETIME_FMT);
        } catch (Exception e) {
            return raw.isEmpty() ? nullString : raw;
        }
    }
}
```

## Test classes

### `src/test/java/com/socgen/sgs/api/quark/engine/domain/RunTest.java`

SHA-256: `159c3184e5f24b629636fd9f02529b2fc043e6c358fddc1d22ee248d7b1d951f`

```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.enums.GabaritSourceEnum;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.BeforeEach;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

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

    @Test
    @DisplayName("Structural XML retrieval failure switches to degraded mode and skips DID")
    void xmlRetrievalFailureUsesFailSoftMode() {
        GetGabaritBusiness getGabaritBusiness = mock(GetGabaritBusiness.class);
        GetGabaritXmlBusiness getGabaritXmlBusiness = mock(GetGabaritXmlBusiness.class);
        FilePoolPort filePoolPort = mock(FilePoolPort.class);
        DocumentIdentityPort documentIdentityPort = mock(DocumentIdentityPort.class);
        RunProperties properties = new RunProperties();
        properties.setGabaritSource(GabaritSourceEnum.GABARIT);
        properties.setIdGabarit(45);
        DocumentDomain document = DocumentDomain.builder()
                .id(45)
                .format("QXP")
                .data(new byte[]{1, 2, 3})
                .filePoolPath("R_100/G_45.QXP")
                .build();
        run.setId(100);
        run.setRunProperties(properties);
        when(getGabaritBusiness.getAndPrepareGabarit(properties, 45)).thenReturn(document);
        when(getGabaritXmlBusiness.fetchXml(document.getFilePoolPath())).thenReturn("");

        run.prepareGabarit(getGabaritBusiness, getGabaritXmlBusiness, filePoolPort, documentIdentityPort);

        assertTrue(properties.isModeDegrade());
        assertTrue(document.isModeDegrade());
        assertSame(QxpXml.EMPTY, document.getQxpXml());
        verify(filePoolPort).addFile(document.getFilePoolPath(), document.getData());
        verifyNoInteractions(documentIdentityPort);
    }

    @Test
    @DisplayName("Oversized gabarit marks both document and run as degraded")
    void oversizedGabaritMarksDocumentAndRunDegraded() {
        GetGabaritBusiness getGabaritBusiness = mock(GetGabaritBusiness.class);
        GetGabaritXmlBusiness getGabaritXmlBusiness = mock(GetGabaritXmlBusiness.class);
        FilePoolPort filePoolPort = mock(FilePoolPort.class);
        DocumentIdentityPort documentIdentityPort = mock(DocumentIdentityPort.class);
        Run sizeLimitedRun = new Run(2);
        sizeLimitedRun.setId(100);
        RunProperties properties = new RunProperties();
        properties.setGabaritSource(GabaritSourceEnum.GABARIT);
        properties.setIdGabarit(45);
        sizeLimitedRun.setRunProperties(properties);
        DocumentDomain document = DocumentDomain.builder()
                .id(45).format("QXP").data(new byte[]{1, 2, 3})
                .filePoolPath("R_100/G_45.QXP").build();
        when(getGabaritBusiness.getAndPrepareGabarit(properties, 45)).thenReturn(document);

        sizeLimitedRun.prepareGabarit(
                getGabaritBusiness, getGabaritXmlBusiness, filePoolPort, documentIdentityPort);

        assertTrue(document.isModeDegrade());
        assertTrue(properties.isModeDegrade());
        verifyNoInteractions(getGabaritXmlBusiness, documentIdentityPort);
    }

    @Test
    @DisplayName("Malformed structural XML also switches to degraded mode")
    void xmlParsingFailureUsesFailSoftMode() {
        GetGabaritBusiness getGabaritBusiness = mock(GetGabaritBusiness.class);
        GetGabaritXmlBusiness getGabaritXmlBusiness = mock(GetGabaritXmlBusiness.class);
        FilePoolPort filePoolPort = mock(FilePoolPort.class);
        DocumentIdentityPort documentIdentityPort = mock(DocumentIdentityPort.class);
        RunProperties properties = new RunProperties();
        properties.setGabaritSource(GabaritSourceEnum.GABARIT);
        properties.setIdGabarit(45);
        DocumentDomain document = DocumentDomain.builder()
                .id(45).format("QXP").data(new byte[]{1})
                .filePoolPath("R_100/G_45.QXP").build();
        run.setId(100);
        run.setRunProperties(properties);
        when(getGabaritBusiness.getAndPrepareGabarit(properties, 45)).thenReturn(document);
        when(getGabaritXmlBusiness.fetchXml(document.getFilePoolPath())).thenReturn("<PROJECT>");

        run.prepareGabarit(getGabaritBusiness, getGabaritXmlBusiness, filePoolPort, documentIdentityPort);

        assertTrue(properties.isModeDegrade());
        assertSame(QxpXml.EMPTY, document.getQxpXml());
        verifyNoInteractions(documentIdentityPort);
    }
}
```

### `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/LoadTasksServiceImplTest.java`

SHA-256: `bd06b41c533cf8814cc1e914d6605b4147bf542872c72f6f599d274c504205e7`

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.business.GetTaskExceptionsBusiness;
import com.socgen.sgs.api.quark.engine.business.GetTasksBusiness;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.task.TaskException;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.enums.TaskExceptionTypeEnum;
import com.socgen.sgs.api.quark.engine.mapper.TaskExceptionMapper;
import com.socgen.sgs.api.quark.engine.mapper.TaskMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("LoadTasksServiceImpl Tests")
class LoadTasksServiceImplTest {

    @InjectMocks
    private LoadTasksServiceImpl loadTasksService;

    @Mock
    private GetTasksBusiness getTasksBusiness;

    @Mock
    private GetTaskExceptionsBusiness getTaskExceptionsBusiness;

    @Mock
    private TaskMapper taskMapper;

    @Mock
    private TaskExceptionMapper taskExceptionMapper;

    private Run run;

    @BeforeEach
    void setUp() {
        run = new Run();
        run.setId(100);
    }

    // --- loadTasks: task loading ---

    @Test

    @DisplayName("Should load tasks and populate run.tasks map")
    void shouldLoadTasksAndPopulate() {
        Map<String, Object> row1 = Map.of("ID_TACHE", 10, "ID_TYPE_TACHE", 1);
        Map<String, Object> row2 = Map.of("ID_TACHE", 20, "ID_TYPE_TACHE", 2);
        when(getTasksBusiness.execute(100)).thenReturn(List.of(row1, row2));

        TaskSql task1 = new TaskSql(10, run);
        TaskSql task2 = new TaskSql(20, run);
        when(taskMapper.mapToTask(row1, run)).thenReturn(task1);
        when(taskMapper.mapToTask(row2, run)).thenReturn(task2);
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(Collections.emptyList());

        loadTasksService.loadTasks(run);

        assertEquals(3, run.getTasks().size());
        assertSame(task1, run.getTasks().get(10));
        assertSame(task2, run.getTasks().get(20));
        verify(getTasksBusiness, times(1)).execute(100);
    }

    @Test
    @DisplayName("Should skip null tasks returned by mapper")
    void shouldSkipNullTasks() {
        Map<String, Object> row1 = Map.of("ID_TACHE", 10, "ID_TYPE_TACHE", 0);
        when(getTasksBusiness.execute(100)).thenReturn(List.of(row1));
        when(taskMapper.mapToTask(row1, run)).thenReturn(null);
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(Collections.emptyList());

        loadTasksService.loadTasks(run);

        assertEquals(1, run.getTasks().size());
        assertTrue(run.getTasks().containsKey(0)); // DID task
    }

    @Test
    @DisplayName("Should handle empty task list from DAO")
    void shouldHandleEmptyTaskList() {
        when(getTasksBusiness.execute(100)).thenReturn(Collections.emptyList());
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(Collections.emptyList());

        loadTasksService.loadTasks(run);

        assertEquals(1, run.getTasks().size());
        assertTrue(run.getTasks().containsKey(0)); // only DID task
        verify(getTaskExceptionsBusiness, times(1)).execute(100);
    }

    // --- loadTasks: exception loading ---

    @Test
    @DisplayName("Should load task exceptions and add to task's exceptions map")
    void shouldLoadTaskExceptions() {
        TaskSql task = new TaskSql(10, run);

        Map<String, Object> taskRow = new HashMap<>();
        taskRow.put("ID_TACHE", 10);
        taskRow.put("ID_TYPE_TACHE", 1);

        Map<String, Object> excRow = new HashMap<>();
        excRow.put("ID_TACHE", 10);
        excRow.put("NOM_BLOC", "BLOC_A");
        excRow.put("NOM_TABLEAU", "TABLE_X");
        excRow.put("INDEX_LIGNES", "1|2");

        when(getTasksBusiness.execute(100)).thenReturn(List.of(taskRow));
        when(taskMapper.mapToTask(taskRow, run)).thenReturn(task);
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(List.of(excRow));
        when(taskExceptionMapper.getIdTache(excRow)).thenReturn(10);
        when(taskExceptionMapper.getNomBloc(excRow)).thenReturn("BLOC_A");
        TaskException taskException = new TaskException("TABLE_X", "BLOC_A", new int[]{1, 2}, TaskExceptionTypeEnum.LINE);
        when(taskExceptionMapper.mapToTaskException(excRow)).thenReturn(taskException);

        loadTasksService.loadTasks(run);

        assertEquals(1, task.getExceptions().size());
        assertSame(taskException, task.getExceptions().get("BLOC_A"));
    }

    @Test
    @DisplayName("Should skip exception when task not found in run")
    void shouldSkipExceptionWhenTaskNotFound() {
        when(getTasksBusiness.execute(100)).thenReturn(Collections.emptyList());

        Map<String, Object> excRow = new HashMap<>();
        excRow.put("ID_TACHE", 999);
        excRow.put("NOM_BLOC", "BLOC_MISSING");

        when(getTaskExceptionsBusiness.execute(100)).thenReturn(List.of(excRow));
        when(taskExceptionMapper.getIdTache(excRow)).thenReturn(999);
        when(taskExceptionMapper.getNomBloc(excRow)).thenReturn("BLOC_MISSING");

        loadTasksService.loadTasks(run);

        assertEquals(1, run.getTasks().size());
        assertTrue(run.getTasks().containsKey(0)); // only DID task, task 999 not found
        assertEquals(1, run.getErrors().size());
        assertEquals(RunError.UNSPECIFIED, run.getErrors().get(0).getCategory());
        assertTrue(run.getErrors().get(0).getMessage().contains("BLOC_MISSING"));
    }

    @Test
    @DisplayName("Missing-task exception records an error but does not block later exception rows")
    void missingTaskExceptionDoesNotBlockFollowingRows() {
        TaskSql task = new TaskSql(10, run);
        Map<String, Object> taskRow = new HashMap<>();
        Map<String, Object> missingRow = new HashMap<>();
        Map<String, Object> validRow = new HashMap<>();
        when(getTasksBusiness.execute(100)).thenReturn(List.of(taskRow));
        when(taskMapper.mapToTask(taskRow, run)).thenReturn(task);
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(List.of(missingRow, validRow));
        when(taskExceptionMapper.getIdTache(missingRow)).thenReturn(999);
        when(taskExceptionMapper.getNomBloc(missingRow)).thenReturn("MISSING");
        when(taskExceptionMapper.getIdTache(validRow)).thenReturn(10);
        when(taskExceptionMapper.getNomBloc(validRow)).thenReturn("VALID");
        TaskException validException = new TaskException(
                "TABLE", "VALID", new int[0], TaskExceptionTypeEnum.TABLE);
        when(taskExceptionMapper.mapToTaskException(validRow)).thenReturn(validException);

        loadTasksService.loadTasks(run);

        assertSame(validException, task.getExceptions().get("VALID"));
        assertTrue(run.getTasks().containsKey(0));
        assertEquals(1, run.getErrors().size());
        assertEquals(RunError.UNSPECIFIED, run.getErrors().get(0).getCategory());
    }

    @Test
    @DisplayName("Should warn on duplicate bloc exception and not overwrite")
    void shouldWarnOnDuplicateBlocException() {
        TaskSql task = new TaskSql(10, run);
        TaskException existingExc = new TaskException("TABLE_OLD", "BLOC_DUP", new int[0], TaskExceptionTypeEnum.TABLE);
        task.getExceptions().put("BLOC_DUP", existingExc);

        Map<String, Object> taskRow = new HashMap<>();
        taskRow.put("ID_TACHE", 10);
        taskRow.put("ID_TYPE_TACHE", 1);

        Map<String, Object> excRow = new HashMap<>();
        excRow.put("ID_TACHE", 10);
        excRow.put("NOM_BLOC", "BLOC_DUP");

        when(getTasksBusiness.execute(100)).thenReturn(List.of(taskRow));
        when(taskMapper.mapToTask(taskRow, run)).thenReturn(task);
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(List.of(excRow));
        when(taskExceptionMapper.getIdTache(excRow)).thenReturn(10);
        when(taskExceptionMapper.getNomBloc(excRow)).thenReturn("BLOC_DUP");

        loadTasksService.loadTasks(run);

        assertEquals(1, task.getExceptions().size());
        assertSame(existingExc, task.getExceptions().get("BLOC_DUP"));
        assertEquals(1, run.getErrors().size());
        assertEquals(RunError.UNSPECIFIED, run.getErrors().get(0).getCategory());
        assertTrue(run.getErrors().get(0).getMessage().contains("BLOC_DUP"));
    }

    @Test
    @DisplayName("Should reuse cached task for same task id in consecutive exception rows")
    void shouldReuseCachedTask() {
        TaskSql task = new TaskSql(10, run);

        Map<String, Object> taskRow = new HashMap<>();
        taskRow.put("ID_TACHE", 10);
        taskRow.put("ID_TYPE_TACHE", 1);

        Map<String, Object> excRow1 = new HashMap<>();
        excRow1.put("ID_TACHE", 10);
        excRow1.put("NOM_BLOC", "BLOC_1");
        Map<String, Object> excRow2 = new HashMap<>();
        excRow2.put("ID_TACHE", 10);
        excRow2.put("NOM_BLOC", "BLOC_2");

        when(getTasksBusiness.execute(100)).thenReturn(List.of(taskRow));
        when(taskMapper.mapToTask(taskRow, run)).thenReturn(task);
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(List.of(excRow1, excRow2));
        when(taskExceptionMapper.getIdTache(excRow1)).thenReturn(10);
        when(taskExceptionMapper.getNomBloc(excRow1)).thenReturn("BLOC_1");
        when(taskExceptionMapper.getIdTache(excRow2)).thenReturn(10);
        when(taskExceptionMapper.getNomBloc(excRow2)).thenReturn("BLOC_2");

        TaskException exc1 = new TaskException("T1", "BLOC_1", new int[]{1}, TaskExceptionTypeEnum.LINE);
        TaskException exc2 = new TaskException("T2", "BLOC_2", new int[0], TaskExceptionTypeEnum.TABLE);
        when(taskExceptionMapper.mapToTaskException(excRow1)).thenReturn(exc1);
        when(taskExceptionMapper.mapToTaskException(excRow2)).thenReturn(exc2);

        loadTasksService.loadTasks(run);

        assertEquals(2, task.getExceptions().size());
        assertSame(exc1, task.getExceptions().get("BLOC_1"));
        assertSame(exc2, task.getExceptions().get("BLOC_2"));
    }

    @Test
    @DisplayName("Should handle switching between different task ids in exceptions")
    void shouldHandleSwitchingBetweenTasks() {
        TaskSql task1 = new TaskSql(10, run);
        TaskSql task2 = new TaskSql(20, run);

        Map<String, Object> taskRow1 = new HashMap<>();
        taskRow1.put("ID_TACHE", 10);
        taskRow1.put("ID_TYPE_TACHE", 1);
        Map<String, Object> taskRow2 = new HashMap<>();
        taskRow2.put("ID_TACHE", 20);
        taskRow2.put("ID_TYPE_TACHE", 1);

        Map<String, Object> excRow1 = new HashMap<>();
        excRow1.put("ID_TACHE", 10);
        excRow1.put("NOM_BLOC", "BLOC_A");
        Map<String, Object> excRow2 = new HashMap<>();
        excRow2.put("ID_TACHE", 20);
        excRow2.put("NOM_BLOC", "BLOC_B");

        when(getTasksBusiness.execute(100)).thenReturn(List.of(taskRow1, taskRow2));
        when(taskMapper.mapToTask(taskRow1, run)).thenReturn(task1);
        when(taskMapper.mapToTask(taskRow2, run)).thenReturn(task2);
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(List.of(excRow1, excRow2));
        when(taskExceptionMapper.getIdTache(excRow1)).thenReturn(10);
        when(taskExceptionMapper.getNomBloc(excRow1)).thenReturn("BLOC_A");
        when(taskExceptionMapper.getIdTache(excRow2)).thenReturn(20);
        when(taskExceptionMapper.getNomBloc(excRow2)).thenReturn("BLOC_B");

        TaskException exc1 = new TaskException("T1", "BLOC_A", new int[]{1}, TaskExceptionTypeEnum.LINE);
        TaskException exc2 = new TaskException("T2", "BLOC_B", new int[0], TaskExceptionTypeEnum.TABLE);
        when(taskExceptionMapper.mapToTaskException(excRow1)).thenReturn(exc1);
        when(taskExceptionMapper.mapToTaskException(excRow2)).thenReturn(exc2);

        loadTasksService.loadTasks(run);

        assertEquals(1, task1.getExceptions().size());
        assertEquals(1, task2.getExceptions().size());
        assertSame(exc1, task1.getExceptions().get("BLOC_A"));
        assertSame(exc2, task2.getExceptions().get("BLOC_B"));
    }

    @Test
    @DisplayName("Should handle empty exception list from DAO")
    void shouldHandleEmptyExceptionList() {
        TaskSql task = new TaskSql(10, run);

        Map<String, Object> taskRow = new HashMap<>();
        taskRow.put("ID_TACHE", 10);
        taskRow.put("ID_TYPE_TACHE", 1);

        when(getTasksBusiness.execute(100)).thenReturn(List.of(taskRow));
        when(taskMapper.mapToTask(taskRow, run)).thenReturn(task);
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(Collections.emptyList());

        loadTasksService.loadTasks(run);

        assertTrue(task.getExceptions().isEmpty());
    }

    @Test
    @DisplayName("Should skip exception row after task-not-found and process next valid row")
    void shouldSkipMissingTaskAndContinue() {
        TaskSql task20 = new TaskSql(20, run);

        Map<String, Object> taskRow = new HashMap<>();
        taskRow.put("ID_TACHE", 20);
        taskRow.put("ID_TYPE_TACHE", 1);

        Map<String, Object> excRow1 = new HashMap<>();
        excRow1.put("ID_TACHE", 999);
        excRow1.put("NOM_BLOC", "BLOC_MISSING");
        Map<String, Object> excRow2 = new HashMap<>();
        excRow2.put("ID_TACHE", 20);
        excRow2.put("NOM_BLOC", "BLOC_OK");

        when(getTasksBusiness.execute(100)).thenReturn(List.of(taskRow));
        when(taskMapper.mapToTask(taskRow, run)).thenReturn(task20);
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(List.of(excRow1, excRow2));
        when(taskExceptionMapper.getIdTache(excRow1)).thenReturn(999);
        when(taskExceptionMapper.getNomBloc(excRow1)).thenReturn("BLOC_MISSING");
        when(taskExceptionMapper.getIdTache(excRow2)).thenReturn(20);
        when(taskExceptionMapper.getNomBloc(excRow2)).thenReturn("BLOC_OK");

        TaskException exc = new TaskException("T2", "BLOC_OK", new int[]{5}, TaskExceptionTypeEnum.LINE);
        when(taskExceptionMapper.mapToTaskException(excRow2)).thenReturn(exc);

        loadTasksService.loadTasks(run);

        assertEquals(1, task20.getExceptions().size());
        assertSame(exc, task20.getExceptions().get("BLOC_OK"));
    }
}
```

### `src/test/java/com/socgen/sgs/api/quark/engine/business/LoadTemplatesBusinessTest.java`

SHA-256: `e8821ea225d5b8ae0d10e8e8f2c937657cc5cedbbdc4299e0863321089031f6c`

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;
import com.socgen.sgs.api.quark.engine.infra.dao.GetGabaritTemplateDao;
import com.socgen.sgs.api.quark.engine.mapper.TemplateMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@DisplayName("LoadTemplatesBusiness parity tests")
class LoadTemplatesBusinessTest {

    private GetGabaritTemplateDao dao;
    private TemplateMapper mapper;
    private LoadTemplatesBusiness business;
    private Run run;

    @BeforeEach
    void setUp() {
        dao = mock(GetGabaritTemplateDao.class);
        mapper = mock(TemplateMapper.class);
        business = new LoadTemplatesBusiness(dao, mapper);
        run = new Run();
        run.setId(100);
        RunProperties properties = new RunProperties();
        properties.setRunId(100);
        properties.setIdGabaritTemplate(3);
        run.setRunProperties(properties);
        TaskDynamique dynamicTask = new TaskDynamique(40, run);
        dynamicTask.setTodo(true);
        run.getTasks().put(40, dynamicTask);
    }

    @Test
    @DisplayName("Missing template document does not abort Load and definitions are still loaded")
    void missingTemplateDocumentIsDeferredToTaskPrepare() {
        Map<String, Object> row = Map.of("NOM", "A");
        Template template = new Template();
        template.setName("A");
        when(dao.getGabaritTemplate(3)).thenReturn(null);
        when(dao.getTemplates(3)).thenReturn(List.of(row));
        when(mapper.mapToTemplate(row)).thenReturn(template);

        assertDoesNotThrow(() -> business.execute(run));

        assertNull(run.getGabaritTemplate());
        assertSame(template, run.getTemplates().get("A"));
    }

    @Test
    @DisplayName("Oversized gabarit template marks both document and run as degraded")
    void oversizedTemplateMarksDocumentAndRunDegraded() {
        run.setSizeLimitBeforeFailSoft(2);
        DocumentDomain document = DocumentDomain.builder()
                .id(3).format("QXP").data(new byte[]{1, 2, 3})
                .fileName("GT_3.QXP").build();
        when(dao.getGabaritTemplate(3)).thenReturn(document);
        when(dao.getTemplates(3)).thenReturn(List.of());

        business.execute(run);

        assertTrue(document.isModeDegrade());
        assertTrue(run.getRunProperties().isModeDegrade());
    }

    @Test
    @DisplayName("Duplicate template names fail Load like .NET Dictionary.Add")
    void duplicateTemplateNamesAreRejected() {
        Map<String, Object> row1 = Map.of("ID_TEMPLATE", 673);
        Map<String, Object> row2 = Map.of("ID_TEMPLATE", 1107);
        Template first = new Template();
        first.setName("SWAP_N1_RSA");
        Template second = new Template();
        second.setName("SWAP_N1_RSA");
        when(dao.getGabaritTemplate(3)).thenReturn(null);
        when(dao.getTemplates(3)).thenReturn(List.of(row1, row2));
        when(mapper.mapToTemplate(row1)).thenReturn(first);
        when(mapper.mapToTemplate(row2)).thenReturn(second);

        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> business.execute(run));

        assertTrue(error.getMessage().contains("SWAP_N1_RSA"));
        assertSame(first, run.getTemplates().get("SWAP_N1_RSA"));
    }

    @Test
    @DisplayName("Null template name fails Load like a null .NET Dictionary key")
    void nullTemplateNameIsRejected() {
        Map<String, Object> row = Map.of("ID_TEMPLATE", 1);
        Template template = new Template();
        template.setName(null);
        when(dao.getGabaritTemplate(3)).thenReturn(null);
        when(dao.getTemplates(3)).thenReturn(List.of(row));
        when(mapper.mapToTemplate(row)).thenReturn(template);

        assertThrows(IllegalStateException.class, () -> business.execute(run));
    }
}
```

### `src/test/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/GetGabaritTemplateDaoImplTest.java`

SHA-256: `3565b7121f489e9115c032fa451acd0d7a5acb087d858dc56829ae896422a3b7`

```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.test.util.ReflectionTestUtils;

import javax.sql.DataSource;
import java.sql.ResultSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("GetGabaritTemplateDaoImpl parity tests")
class GetGabaritTemplateDaoImplTest {

    @Mock private DataSource dataSource;
    @Mock private SimpleJdbcCall getGabaritTemplateCall;
    @Mock private ResultSet resultSet;
    private GetGabaritTemplateDaoImpl dao;

    @BeforeEach
    void setUp() {
        dao = new GetGabaritTemplateDaoImpl(dataSource);
        ReflectionTestUtils.setField(dao, "getGabaritTemplateCall", getGabaritTemplateCall);
    }

    @Test
    @DisplayName("Empty cursor returns null like .NET")
    void emptyCursorReturnsNull() {
        Map<String, Object> result = new HashMap<>();
        result.put("result_cursor", List.of());
        when(getGabaritTemplateCall.execute(any(SqlParameterSource.class))).thenReturn(result);

        assertNull(dao.getGabaritTemplate(3));
    }

    @Test
    @DisplayName("Gabarit template filename uses uppercase QXP extension")
    void filenameUsesUppercaseQxpExtension() throws Exception {
        when(resultSet.getInt("id_gabarit_template")).thenReturn(3);
        when(resultSet.getString("nom")).thenReturn("RSA");
        when(resultSet.getBytes("contenu")).thenReturn(new byte[]{1});

        DocumentDomain document = ReflectionTestUtils.invokeMethod(dao, "mapGabaritTemplate", resultSet);

        assertNotNull(document);
        assertEquals("GT_3.QXP", document.getFileName());
    }
}
```

### `src/test/java/com/socgen/sgs/api/quark/engine/mapper/TaskMapperTest.java`

SHA-256: `5a861b10588299a9c9de532d8c74027d3a3ba9edc726b4d3a35d9c1ac3c60375`

```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBreakRules;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DMasterPage;
import com.socgen.sgs.api.quark.engine.domain.task.*;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

@DisplayName("TaskMapper Tests")
class TaskMapperTest {

    private TaskMapper mapper;
    private Run run;

    @BeforeEach
    void setUp() {
        mapper = new TaskMapper(mock(com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort.class));
        run = new Run();
        run.setId(100);
    }

    // --- SQL task mapping ---

    @Test
    @DisplayName("Should map SQL task with all fields")
    void shouldMapSqlTask() {
        Map<String, Object> row = buildBaseRow(10, 1);
        row.put("SQL", "SELECT 1 FROM DUAL");
        row.put("AFFICHER_ZERO", 1);
        row.put("NB_DECIMAL", 2);
        row.put("DECIMAL_SIGNIFICATIVE", 1);
        row.put("STORE_DATA", 0);
        row.put("OUTPUT_DATA_TYPE", 1);

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertInstanceOf(TaskSql.class, result);
        TaskSql task = (TaskSql) result;
        assertEquals(10, task.getId());
        assertEquals("SELECT 1 FROM DUAL", task.getSql());
        assertTrue(task.isShowZero());
        assertEquals(2, task.getNbDecimal());
        assertTrue(task.isDecimalSignificative());
        assertFalse(task.isStoreData());
        assertEquals(DataTypeEnum.TEXT, task.getDataType());
    }

    @Test
    @DisplayName("Should preserve .NET unset sentinel when NB_DECIMAL is NULL")
    void shouldMapNullNbDecimalToUnsetSentinel() {
        Map<String, Object> row = buildBaseRow(12, 1);
        row.put("SQL", "SELECT 1 FROM DUAL");
        row.put("AFFICHER_ZERO", 1);
        row.put("NB_DECIMAL", null);
        row.put("DECIMAL_SIGNIFICATIVE", 0);
        row.put("STORE_DATA", 0);
        row.put("OUTPUT_DATA_TYPE", 3);

        TaskSql task = (TaskSql) mapper.mapToTask(row, run);

        assertEquals(Integer.MIN_VALUE, task.getNbDecimal());
    }

    @Test
    @DisplayName("Should map SQL task with unknown data type gracefully")
    void shouldHandleUnknownDataTypeInSqlTask() {
        Map<String, Object> row = buildBaseRow(11, 1);
        row.put("SQL", "");
        row.put("AFFICHER_ZERO", 0);
        row.put("NB_DECIMAL", 0);
        row.put("DECIMAL_SIGNIFICATIVE", 0);
        row.put("STORE_DATA", 0);
        row.put("OUTPUT_DATA_TYPE", 999);

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertInstanceOf(TaskSql.class, result);
        // fromCode(999) returns UNSPECIFIED — no exception thrown
        assertEquals(DataTypeEnum.UNSPECIFIED, ((TaskSql) result).getDataType());
    }

    // --- DOC_EOS task mapping ---

    @Test
    @DisplayName("Should map DOC_EOS task with all fields")
    void shouldMapDocEosTask() {
        Map<String, Object> row = buildBaseRow(20, 2);
        row.put("FORMAT", "PDF");
        row.put("ROTATION_IMAGE", 1);
        row.put("ID_SOUS_CATEGORIE", 5);
        row.put("CROP_IMAGE_VALUES", "10,20,30,40");
        row.put("CONSERVER_STYLE", 0);
        row.put("BLOC_SOURCE", "src_bloc");
        row.put("BLOC_DESTINATION", "dest_bloc");
        row.put("POSITION_IMAGE", "0,0,100,100");

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertInstanceOf(TaskDocument.class, result);
        TaskDocument task = (TaskDocument) result;
        assertEquals(20, task.getId());
        assertEquals("PDF", task.getFormatDocument());
        assertTrue(task.isRotationImage());
        assertEquals(5, task.getIdSousCategorie());
        assertEquals("10,20,30,40", task.getOffsetValues());
        assertFalse(task.isConserverStyle());
        assertEquals("src_bloc", task.getSourceBlocName());
        assertEquals("dest_bloc", task.getDestinationBlocName());
        assertEquals("0,0,100,100", task.getPositionValues());
    }

    // --- DOC_QXP task mapping ---

    @Test
    @DisplayName("Should map DOC_QXP task with all fields")
    void shouldMapDocQxpTask() {
        Map<String, Object> row = buildBaseRow(30, 3);
        row.put("CONSERVER_STYLE", 1);
        row.put("PREVIOUS_TYPE_RAPPORT", "PREV_TYPE");
        row.put("BLOC_SOURCE", "qxp_src");
        row.put("BLOC_DESTINATION", "qxp_dest");

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertInstanceOf(TaskQxpPrevious.class, result);
        TaskQxpPrevious task = (TaskQxpPrevious) result;
        assertEquals(30, task.getId());
        assertTrue(task.isConserverStyle());
        assertEquals("PREV_TYPE", task.getPreviousTypeRapport());
        assertEquals("qxp_src", task.getSourceBlocName());
        assertEquals("qxp_dest", task.getDestinationBlocName());
    }

    // --- SQL_DYNAMIQUE task mapping ---

    @Test
    @DisplayName("Should map SQL_DYNAMIQUE task with all fields including rules and master page")
    void shouldMapDynamiqueTaskWithRules() {
        Map<String, Object> row = buildBaseRow(40, 4);
        row.put("SQL", "SELECT * FROM TABLE");
        row.put("BLOC_DESTINATION", "dyn_dest");
        row.put("CONTROL_OVERFLOW", 1);
        row.put("NEW_PAGE_TABLE", 1);
        row.put("NB_COLUMN", 3);
        row.put("COLUMN_SPACE", new BigDecimal("2.5"));
        row.put("CODE_MASTER_PAGE", "5|6");
        row.put("PAGE_BREAK_RULES", "1:2|3:4");
        row.put("COLUMN_BREAK_RULES", "5:6");
        row.put("STORE_DATA", 1);

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertInstanceOf(TaskDynamique.class, result);
        TaskDynamique task = (TaskDynamique) result;
        assertEquals(40, task.getId());
        assertEquals("SELECT * FROM TABLE", task.getSql());
        assertEquals("dyn_dest", task.getDestinationBlocName());
        assertTrue(task.isControlOverflow());
        assertTrue(task.isNewPageTable());
        assertEquals(3, task.getNbColumn());
        assertEquals(new BigDecimal("2.5"), task.getColumnSpace());
        assertNotSame(DMasterPage.DEFAULT, task.getMasterPage());
        assertNotSame(DBreakRules.DEFAULT, task.getPageBreakRules());
        assertNotSame(DBreakRules.DEFAULT, task.getColumnBreakRules());
        assertTrue(task.isStoreData());
    }

    @Test
    @DisplayName("Should map SQL_DYNAMIQUE task with defaults when optional fields are null")
    void shouldMapDynamiqueTaskWithDefaults() {
        Map<String, Object> row = buildBaseRow(41, 4);
        row.put("SQL", "SELECT 1");
        row.put("BLOC_DESTINATION", "dest");
        row.put("CONTROL_OVERFLOW", 0);
        row.put("NEW_PAGE_TABLE", 0);
        row.put("NB_COLUMN", 1);
        row.put("STORE_DATA", 0);
        // CODE_MASTER_PAGE, PAGE_BREAK_RULES, COLUMN_BREAK_RULES, COLUMN_SPACE not set

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        TaskDynamique task = (TaskDynamique) result;
        assertSame(DMasterPage.DEFAULT, task.getMasterPage());
        assertSame(DBreakRules.DEFAULT, task.getPageBreakRules());
        assertSame(DBreakRules.DEFAULT, task.getColumnBreakRules());
    }

    @Test
    @DisplayName("Should map SQL_DYNAMIQUE task with Number column space (not BigDecimal)")
    void shouldMapDynamiqueTaskWithNumberColumnSpace() {
        Map<String, Object> row = buildBaseRow(42, 4);
        row.put("SQL", "SELECT 1");
        row.put("BLOC_DESTINATION", "dest");
        row.put("CONTROL_OVERFLOW", 0);
        row.put("NEW_PAGE_TABLE", 0);
        row.put("NB_COLUMN", 1);
        row.put("STORE_DATA", 0);
        row.put("COLUMN_SPACE", 3.0);

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        TaskDynamique task = (TaskDynamique) result;
        assertEquals(0, BigDecimal.valueOf(3.0).compareTo(task.getColumnSpace()));
    }

    // --- COMPARTIMENTS task mapping ---

    @Test
    @DisplayName("Should map COMPARTIMENTS task with master page")
    void shouldMapCompartimentTask() {
        Map<String, Object> row = buildBaseRow(50, 5);
        row.put("BLOC_DESTINATION", "comp_dest");
        row.put("ID_GABARIT_FILS", 77);
        row.put("CODE_MASTER_PAGE", "9");

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertInstanceOf(TaskCompartiment.class, result);
        TaskCompartiment task = (TaskCompartiment) result;
        assertEquals(50, task.getId());
        assertEquals("comp_dest", task.getDestinationBlocName());
        assertEquals(77, task.getIdGabaritFils());
        assertNotSame(DMasterPage.DEFAULT, task.getMasterPage());
    }

    @Test
    @DisplayName("Should map COMPARTIMENTS task with default master page when null")
    void shouldMapCompartimentTaskWithDefaultMasterPage() {
        Map<String, Object> row = buildBaseRow(51, 5);
        row.put("BLOC_DESTINATION", "comp_dest");
        row.put("ID_GABARIT_FILS", 88);

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        TaskCompartiment task = (TaskCompartiment) result;
        assertSame(DMasterPage.DEFAULT, task.getMasterPage());
    }

    // --- Unknown/SYSTEM task type ---

    @Test
    @DisplayName("Should return null for unknown task type (SYSTEM = 0)")
    void shouldReturnNullForUnknownTaskType() {
        Map<String, Object> row = buildBaseRow(99, 0);

        TaskBase result = mapper.mapToTask(row, run);

        assertNull(result);
    }

    @Test
    @DisplayName("Should return null for unmapped task type code")
    void shouldReturnNullForUnmappedCode() {
        Map<String, Object> row = buildBaseRow(99, 999);

        TaskBase result = mapper.mapToTask(row, run);

        assertNull(result);
    }

    // --- Common fields mapping ---

    @Test
    @DisplayName("Should map common fields (CHAMPS_VIDE, TODO, COMMENTAIRE)")
    void shouldMapCommonFields() {
        Map<String, Object> row = buildBaseRow(10, 1);
        row.put("SQL", "SELECT 1");
        row.put("AFFICHER_ZERO", 0);
        row.put("NB_DECIMAL", 0);
        row.put("DECIMAL_SIGNIFICATIVE", 0);
        row.put("STORE_DATA", 0);
        row.put("OUTPUT_DATA_TYPE", 0);
        row.put("CHAMPS_VIDE", "N/A");
        row.put("TODO", 1);
        row.put("COMMENTAIRE", "test comment");

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertEquals("N/A", result.getNullString());
        assertTrue(result.isTodo());
        assertEquals("test comment", result.getCommentaire());
    }

    @Test
    @DisplayName("Should keep default nullString when CHAMPS_VIDE is blank or null")
    void shouldKeepDefaultNullStringWhenBlank() {
        Map<String, Object> row = buildBaseRow(10, 1);
        row.put("SQL", "");
        row.put("AFFICHER_ZERO", 0);
        row.put("NB_DECIMAL", 0);
        row.put("DECIMAL_SIGNIFICATIVE", 0);
        row.put("STORE_DATA", 0);
        row.put("OUTPUT_DATA_TYPE", 0);
        row.put("CHAMPS_VIDE", "   ");
        row.put("TODO", 0);

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertEquals(" ", result.getNullString());
    }

    // --- Utility method edge cases ---

    @Test
    @DisplayName("Should handle Boolean type in getBoolean")
    void shouldHandleBooleanType() {
        Map<String, Object> row = buildBaseRow(10, 1);
        row.put("SQL", "");
        row.put("AFFICHER_ZERO", Boolean.TRUE);
        row.put("NB_DECIMAL", 0);
        row.put("DECIMAL_SIGNIFICATIVE", 0);
        row.put("STORE_DATA", 0);
        row.put("OUTPUT_DATA_TYPE", 0);
        row.put("TODO", 0);

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertTrue(((TaskSql) result).isShowZero());
    }

    @Test
    @DisplayName("Should return false for non-number non-boolean in getBoolean")
    void shouldReturnFalseForStringInBooleanField() {
        Map<String, Object> row = buildBaseRow(10, 1);
        row.put("SQL", "");
        row.put("AFFICHER_ZERO", "not_a_number");
        row.put("NB_DECIMAL", 0);
        row.put("DECIMAL_SIGNIFICATIVE", 0);
        row.put("STORE_DATA", 0);
        row.put("OUTPUT_DATA_TYPE", 0);
        row.put("TODO", 0);

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertFalse(((TaskSql) result).isShowZero());
    }

    @Test
    @DisplayName("Should return 0 for non-number in getInt")
    void shouldReturnZeroForNonNumberInGetInt() {
        Map<String, Object> row = new HashMap<>();
        row.put("ID_TACHE", "not_a_number");
        row.put("ID_TYPE_TACHE", 1);
        row.put("SQL", "");
        row.put("AFFICHER_ZERO", 0);
        row.put("NB_DECIMAL", 0);
        row.put("DECIMAL_SIGNIFICATIVE", 0);
        row.put("STORE_DATA", 0);
        row.put("OUTPUT_DATA_TYPE", 0);
        row.put("TODO", 0);

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertEquals(0, result.getId());
    }

    @Test
    @DisplayName("Should return null string for null value in getString")
    void shouldReturnNullForNullStringField() {
        Map<String, Object> row = buildBaseRow(10, 1);
        row.put("SQL", null);
        row.put("AFFICHER_ZERO", 0);
        row.put("NB_DECIMAL", 0);
        row.put("DECIMAL_SIGNIFICATIVE", 0);
        row.put("STORE_DATA", 0);
        row.put("OUTPUT_DATA_TYPE", 0);
        row.put("TODO", 0);

        TaskBase result = mapper.mapToTask(row, run);

        assertNotNull(result);
        assertNull(((TaskSql) result).getSql());
    }

    // --- Helper ---

    private Map<String, Object> buildBaseRow(int idTache, int idTypeTache) {
        Map<String, Object> row = new HashMap<>();
        row.put("ID_TACHE", idTache);
        row.put("ID_TYPE_TACHE", idTypeTache);
        row.put("CHAMPS_VIDE", null);
        row.put("TODO", 0);
        row.put("COMMENTAIRE", null);
        return row;
    }
}
```

### `src/test/java/com/socgen/sgs/api/quark/engine/domain/helper/DataTypeHelperTest.java`

SHA-256: `601c1b72a2e66288ab2a729bb53645f217f78e2999e3c32722055ceb5250f78e`

```java
package com.socgen.sgs.api.quark.engine.domain.helper;

import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.text.DecimalFormatSymbols;
import java.util.Locale;

import static org.junit.jupiter.api.Assertions.assertEquals;

@DisplayName("DataTypeHelper formatting Tests")
class DataTypeHelperTest {

    // Use the JVM's actual fr-FR symbols so assertions survive CLDR grouping-char changes
    // (the grouping separator may be NBSP U+00A0 or NNBSP U+202F depending on the JDK/CLDR).
    private static final DecimalFormatSymbols FR = new DecimalFormatSymbols(Locale.FRANCE);
    private static final char GRP = FR.getGroupingSeparator();
    private static final char DEC = FR.getDecimalSeparator();
    private static final String CUR = FR.getCurrencySymbol();

    @Test
    @DisplayName("#12 INT output is grouped (thousands separators)")
    void intIsGrouped() {
        assertEquals("1" + GRP + "234" + GRP + "567",
                DataTypeHelper.outputToString("1234567", DataTypeEnum.INT, 0, true, "-", false));
    }

    @Test
    @DisplayName("INT zero with showZero=false returns nullString")
    void intZeroNotShown() {
        assertEquals("N/A", DataTypeHelper.outputToString("0", DataTypeEnum.INT, 0, false, "N/A", false));
    }

    @Test
    @DisplayName("#13 decimalSignificative=true keeps fixed trailing zeros")
    void decimalSignificativeKeepsZeros() {
        assertEquals("12" + DEC + "50",
                DataTypeHelper.outputToString("12.5", DataTypeEnum.DECIMAL, 2, true, "-", true));
    }

    @Test
    @DisplayName("#13 decimalSignificative=false suppresses trailing zeros")
    void decimalNotSignificativeSuppressesZeros() {
        assertEquals("12" + DEC + "5",
                DataTypeHelper.outputToString("12.50", DataTypeEnum.DECIMAL, 2, true, "-", false));
        assertEquals("12",
                DataTypeHelper.outputToString("12", DataTypeEnum.DECIMAL, 2, true, "-", false));
    }

    @Test
    @DisplayName("Decimal rounding is HALF_UP (away from zero)")
    void decimalRoundsHalfUp() {
        assertEquals("2" + DEC + "35",
                DataTypeHelper.outputToString("2.345", DataTypeEnum.DECIMAL, 2, true, "-", true));
    }

    @Test
    @DisplayName("#14 CURRENCY appends the currency symbol, no ×100")
    void currencyAppendsSymbol() {
        assertEquals("1" + GRP + "234" + DEC + "50 " + CUR,
                DataTypeHelper.outputToString("1234.5", DataTypeEnum.CURRENCY, 2, true, "-", true));
    }

    @Test
    @DisplayName("#14 POURCENTAGE appends single ' %' and does NOT multiply by 100 (data is scaled)")
    void percentScaledSinglePercent() {
        // 15 means 15% — must render "15,00 %", NOT "1 500,00 % %"
        assertEquals("15" + DEC + "00 %",
                DataTypeHelper.outputToString("15", DataTypeEnum.POURCENTAGE, 2, true, "-", true));
        // significative=false suppresses the trailing zeros
        assertEquals("15 %",
                DataTypeHelper.outputToString("15", DataTypeEnum.POURCENTAGE, 2, true, "-", false));
    }

    @Test
    @DisplayName("CURRENCY/POURCENTAGE zero with showZero=false returns nullString (no suffix)")
    void zeroNotShownHasNoSuffix() {
        assertEquals("-", DataTypeHelper.outputToString("0", DataTypeEnum.CURRENCY, 2, false, "-", true));
        assertEquals("-", DataTypeHelper.outputToString("0", DataTypeEnum.POURCENTAGE, 2, false, "-", true));
    }

    @Test
    @DisplayName("NULL NB_DECIMAL sentinel uses fixed two-digit .NET default formats")
    void unsetNbDecimalUsesDefaultPrecision() {
        int unset = Integer.MIN_VALUE;
        assertEquals("1" + GRP + "234" + DEC + "50",
                DataTypeHelper.outputToString("1234.5", DataTypeEnum.DECIMAL, unset, true, "-", false));
        assertEquals("1" + GRP + "234" + DEC + "50 " + CUR,
                DataTypeHelper.outputToString("1234.5", DataTypeEnum.CURRENCY, unset, true, "-", false));
        assertEquals("15" + DEC + "00 %",
                DataTypeHelper.outputToString("15", DataTypeEnum.POURCENTAGE, unset, true, "-", false));
    }

    @Test
    @DisplayName("NB_DECIMAL outside .NET supported range also uses default precision")
    void invalidNbDecimalUsesDefaultPrecision() {
        assertEquals("12" + DEC + "35",
                DataTypeHelper.outputToString("12.345", DataTypeEnum.DECIMAL, 11, true, "-", true));
    }
}
```

### `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImplPrepareTest.java`

SHA-256: `452a5a9f7258edb2e5f5dca47083d4471434fcd9e61b7660e52b7686f5bd8bbc`

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.service.task.TaskPostProcessService;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

@DisplayName("ProcessTasksServiceImpl Prepare parity tests")
class ProcessTasksServiceImplPrepareTest {

    @Test
    @DisplayName("Missing gabarit template fails only its dynamic task and Prepare continues")
    void missingGabaritTemplateIsPerTaskCritiqueError() {
        ProcessTasksServiceImpl service = new ProcessTasksServiceImpl(
                mock(TaskProcessService.class), mock(TaskPostProcessService.class));
        Run run = new Run();
        run.setId(100);
        TaskDynamique dynamicTask = new TaskDynamique(40, run);
        dynamicTask.setTodo(true);
        dynamicTask.setFilePoolService(mock(FilePoolPort.class));
        TaskSql followingTask = new TaskSql(50, run);
        run.getTasks().put(40, dynamicTask);
        run.getTasks().put(50, followingTask);

        assertDoesNotThrow(() -> service.prepareTasks(run));

        assertTrue(dynamicTask.isInError());
        assertFalse(followingTask.isInError());
        assertEquals(1, run.getErrors().size());
        assertEquals(RunError.CRITIQUE, run.getErrors().get(0).getCategory());
        assertTrue(run.getErrors().get(0).getMessage().contains("40"));
    }
}
```

### `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImplTest.java`

SHA-256: `1c3fda560d3258d1448fb7de4ca5b1b4f68f3070b092e1132ff865eb8a9f047c`

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.GetInParamsBusiness;
import com.socgen.sgs.api.quark.engine.business.GetRunPropertiesBusiness;
import com.socgen.sgs.api.quark.engine.business.RunStartUpdateBusiness;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.RunStatus;
import com.socgen.sgs.api.quark.engine.dto.RunIdDto;
import com.socgen.sgs.api.quark.engine.enums.GabaritSourceEnum;
import com.socgen.sgs.api.quark.engine.service.LoadTasksService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("ProcessRunServiceImpl Tests")
class ProcessRunServiceImplTest {

    @InjectMocks
    private ProcessRunServiceImpl processRunService;

    @Mock
    private RunStartUpdateBusiness runStartUpdateBusiness;
    @Mock
    private GetRunPropertiesBusiness getRunPropertiesBusiness;
    @Mock
    private GetGabaritBusiness getGabaritBusiness;
    @Mock
    private GetInParamsBusiness getInParamsBusiness;
    @Mock
    private LoadTasksService loadTasksService;
    @Mock
    private com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort filePoolPort;
    @Mock
    private com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort documentIdentityPort;
    @Mock
    private com.socgen.sgs.api.quark.engine.service.ProcessTasksService processTasksService;
    // Dependencies added across later batches — required so the orchestrator pipeline does not NPE.
    @Mock
    private com.socgen.sgs.api.quark.engine.service.QxpsCallerService qxpsCallerService;
    @Mock
    private com.socgen.sgs.api.quark.engine.service.CheckService checkService;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.LoadTemplatesBusiness loadTemplatesBusiness;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.LoadTaskDocumentsBusiness loadTaskDocumentsBusiness;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.EndRunBusiness endRunBusiness;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness getGabaritXmlBusiness;

    private RunProperties runProperties;

    @BeforeEach
    void setUp() {
        ReflectionTestUtils.setField(processRunService, "sizeLimitBeforeFailSoft", 209715200L);
        ReflectionTestUtils.setField(processRunService, "nbBoxMax", 17500);
        ReflectionTestUtils.setField(processRunService, "averageBoxSize", 3400);
        runProperties = new RunProperties();
        runProperties.setGabaritSource(GabaritSourceEnum.GABARIT);
        runProperties.setIdGabarit(10);
        // render() returns a result object; stub it (lenient — only the full-pipeline tests reach it)
        // so buildRunResult does not NPE on a null render result.
        lenient().when(qxpsCallerService.render(any(), anyBoolean(), anyBoolean(), anyBoolean(), any(), any()))
                .thenReturn(new com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult());
    }

    // --- runProcessor ---

    @Test
    @DisplayName("Should initialise run with correct id, status and startDate then call load")
    void shouldInitialiseRunAndCallLoad() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        processRunService.runProcessor(new RunIdDto(42));

        ArgumentCaptor<Run> runCaptor = ArgumentCaptor.forClass(Run.class);
        verify(runStartUpdateBusiness).execute(runCaptor.capture());
        Run captured = runCaptor.getValue();

        assertEquals(42, captured.getId());
        // The captured Run is the same mutable instance the orchestrator drives to completion; with
        // all collaborators mocked the pipeline finishes successfully, so its final status is GENERATED.
        assertEquals(RunStatus.GENERATED, captured.getStatus());
        assertNotNull(captured.getStartDate());
    }

    @Test
    @DisplayName("Structural XML failure renders in degraded mode and finishes Generated")
    void xmlFailureCompletesThroughDegradedRenderPath() {
        DocumentDomain gabarit = DocumentDomain.builder()
                .id(10)
                .format("QXP")
                .data(new byte[]{1, 2, 3})
                .filePoolPath("R_42/G_10.QXP")
                .build();
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(gabarit);
        when(getGabaritXmlBusiness.fetchXml(gabarit.getFilePoolPath())).thenReturn("");

        Run result = processRunService.runProcessor(new RunIdDto(42));

        assertEquals(RunStatus.GENERATED, result.getStatus());
        assertTrue(result.getRunProperties().isModeDegrade());
        assertTrue(result.getErrors().stream().anyMatch(error -> error.getCategory() == RunError.CRITIQUE));
        verify(getInParamsBusiness, never()).execute(any());
        verify(loadTasksService, never()).loadTasks(any());
        verify(processTasksService, never()).prepareTasks(any());
        verify(qxpsCallerService).render(eq(result), eq(true), eq(false), eq(true), eq("true"), eq("300"));
        verify(endRunBusiness).execute(result);
    }

    @Test
    @DisplayName("Should call runStartUpdateBusiness before load")
    void shouldCallStartUpdateBeforeLoad() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        processRunService.runProcessor(new RunIdDto(1));

        verify(runStartUpdateBusiness, times(1)).execute(any(Run.class));
        verify(getRunPropertiesBusiness, times(1)).execute(any(RunIdDto.class));
        verify(loadTasksService, times(1)).loadTasks(any(Run.class));
    }

    // --- load ---

    @Test
    @DisplayName("Should set run properties and runId on the run")
    void shouldSetRunPropertiesAndRunId() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        Run run = new Run();
        run.setId(55);
        processRunService.load(run);

        assertEquals(55, run.getRunProperties().getRunId());
        assertSame(runProperties, run.getRunProperties());
    }

    @Test
    @DisplayName("Should call all four load steps in order")
    void shouldCallAllLoadStepsInOrder() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        Run run = new Run();
        run.setId(10);
        processRunService.load(run);

        var order = inOrder(getRunPropertiesBusiness, getGabaritBusiness, getInParamsBusiness, loadTasksService);
        order.verify(getRunPropertiesBusiness).execute(any(RunIdDto.class));
        order.verify(getGabaritBusiness).getAndPrepareGabarit(any(), any());
        order.verify(getInParamsBusiness).execute(run);
        order.verify(loadTasksService).loadTasks(run);
    }

    @Test
    @DisplayName("Should record ERROR (not propagate) when runStartUpdateBusiness throws")
    void shouldPropagateExceptionFromStartUpdate() {
        doThrow(new RuntimeException("start failed")).when(runStartUpdateBusiness).execute(any(Run.class));

        // runProcessor catches top-level failures, marks the run ERROR, and still runs End_Run in the
        // finally block (parity: .NET Run_Base.Launch try/catch/finally) — it does NOT propagate.
        Run result = processRunService.runProcessor(new RunIdDto(1));

        assertEquals(RunStatus.ERROR, result.getStatus());
        verify(getRunPropertiesBusiness, never()).execute(any());
        verify(endRunBusiness, atLeastOnce()).execute(any(Run.class));
    }

    @Test
    @DisplayName("Should propagate exception thrown during load")
    void shouldPropagateExceptionFromLoad() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class)))
                .thenThrow(new RuntimeException("properties failed"));

        Run run = new Run();
        run.setId(1);
        assertThrows(RuntimeException.class, () -> processRunService.load(run));
    }

    // --- getRunProperties ---

    @Test
    @DisplayName("Should return RunProperties from business layer")
    void shouldReturnRunPropertiesFromBusiness() {
        RunIdDto dto = new RunIdDto(99);
        when(getRunPropertiesBusiness.execute(dto)).thenReturn(runProperties);

        RunProperties result = processRunService.getRunProperties(dto);

        assertNotNull(result);
        assertSame(runProperties, result);
        verify(getRunPropertiesBusiness, times(1)).execute(dto);
    }

    // --- fetchActiveRunIds ---

    @Test
    @DisplayName("Should return empty list for fetchActiveRunIds")
    void shouldReturnEmptyListForFetchActiveRunIds() {
        List<Integer> result = processRunService.fetchActiveRunIds();

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }
}
```
