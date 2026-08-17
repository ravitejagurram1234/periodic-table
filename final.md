# EOS Quark Core Parity Wave 1 — Complete Copy Packet

Date: 18 August 2026

Scope: the user-approved Wave 1 only — Batch 2A, 3A1, 3A2, 3E1 and the safe 3E3 foundation.

This is a whole-file transfer artifact. Replace each listed destination file with the complete content in its
code block. Do not copy only a displayed method or diff fragment. No `application.yaml`, REST or RabbitMQ file is
changed by this wave.

Verification completed before packet generation:

- all 483 Java production source files compiled with Java 17 in an independent Maven dependency mirror;
- 81 focused tests passed; failures 0, errors 0, skipped 0;
- accepted invariant numeric/date behavior was cross-checked with executable .NET probes;
- repository-native Maven still requires the private parent POM/dependencies available in the connected environment.

After transfer, run the repository's normal clean build and the focused tests in the connected environment. A
checksum mismatch means the destination is not the reviewed Wave 1 file.

## Production files

### `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/LoadTasksServiceImpl.java`

SHA-256: `a11c8cc04456c234f1c2c3f7890ebc9bf9cc18c84b378365283209d33d494498`

````java
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
                addTaskOrThrow(run, task);
            }
        }

        log.info("Loaded {} tasks for runId: {}", run.getTasks().size(), run.getId());

        loadTaskExceptions(run);

        //adding did_Task
        TaskDid didTask = new TaskDid(TaskDid.DID_TASK_ID, run);
        addTaskOrThrow(run, didTask);
        log.info("DID task added for runId: {}", run.getId());
    }

    private void addTaskOrThrow(Run run, TaskBase task) {
        if (run.getTasks().containsKey(task.getId())) {
            throw new IllegalStateException(String.format(
                    "Duplicate task id %d for run %d", task.getId(), run.getId()));
        }

        run.getTasks().put(task.getId(), task);
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
````

### `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/DidTaskPostProcessStrategy.java`

SHA-256: `673d681d916cdde9966dbdaec0d844a0e8315f0e994b4dba2e40e84112344ef2`

````java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBlocInfo;
import com.socgen.sgs.api.quark.engine.domain.element.TBox;
import com.socgen.sgs.api.quark.engine.domain.helper.DocumentIdentityHelper;
import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDid;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.enums.StaticTElementNameEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.service.task.TaskPostProcessStrategy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * DID post-processing — chooses MOVE vs NAME_VALUE mode, builds the DID identity, and produces
 * the DID bloc by routing through the standard system bloc-creation path.
 *
 * <p>Cross-reference: .NET {@code Task_DID.PostProcess()} → {@code Business.Process_System.Process(this)}.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class DidTaskPostProcessStrategy implements TaskPostProcessStrategy<TaskDid> {

    private static final String DID_BLOC_NAME = "DID";
    /** Reused to actually create the bloc, exactly like .NET delegates to Process_System. */
    private final SystemTaskProcessStrategy systemTaskProcessStrategy;

    @Override
    public Class<TaskDid> getTaskType() {
        return TaskDid.class;
    }

    @Override
    public void postProcess(TaskDid task) {
        // 1. Choose update mode.
        // If any task produced a paginated modify bloc (page create/remove) it may shift the DID's
        // position, so the DID is repositioned + revalued via MOVE; otherwise just its value changes.
        // Cross-reference: .NET Task_DID.PostProcess() mode selection.
        boolean modifier = false;
        modeSelection:
        for (TaskBase other : task.getRun().getTasks().values()) {
            for (BlocBase bloc : other.getBlocsModify().values()) {
                if (bloc.isPagination()) {
                    modifier = true;
                    break modeSelection;
                }
            }
        }

        // 2. Build the new identity value.
        String didValue = DocumentIdentityHelper.getNewIdentity(task.getRun());

        if (modifier) {
            // MOVE mode — keep the DID box on the page where it currently is, with the new value.
            task.setAction(BlocActionEnum.MOVE);
            task.setPagination(true);

            DBlocInfo didInfo = task.getRun().getGabarit().getQxpXml().getBlocInfo(DID_BLOC_NAME);

            // A box with no UID does not exist (every Quark box, even unnamed, has a UID).
            if (didInfo == null || didInfo.getUid() == null || didInfo.getUid().isEmpty()) {
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "Le bloc DID est absent du document"));
                log.warn("Missing DID box for run [{}] in MOVE branch; DID update skipped",
                        task.getRun().getId());
                return;
            }

            // To move a box, QuarkXPress needs at least its position + UID (the page is set later in
            // the modifier). Cross-reference: .NET TElement_Helper.Get_TElement(MOVE_BLOC_VALUE, dest).
            TBox tBox = (TBox) TElementHelper.getTElement(
                    StaticTElementNameEnum.MOVE_BLOC_VALUE, task.getDestinationBlocName());
            Box box = tBox.getSrcBox();
            box.getGeometry().getPosition().setLeft(didInfo.getLeft().toString());
            box.getGeometry().getPosition().setTop(didInfo.getTop().toString());
            box.getGeometry().getPosition().setRight(didInfo.getRight().toString());
            box.getGeometry().getPosition().setBottom(didInfo.getBottom().toString());
            box.setUID(didInfo.getUid());
            box.getContent().setValue(didValue);

            // Drives SystemTaskProcessStrategy BOX mode → a MOVE bloc in blocsModify.
            task.setTBoxSrcBox(box);
            log.info("DID update mode: MOVE for run [{}]", task.getRun().getId());

        } else {
            // NAME_VALUE mode — update the DID value only.
            String didUid = task.getRun().getGabarit().getQxpXml().getUID(DID_BLOC_NAME);
            if (didUid == null || didUid.isEmpty()) {
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "Le bloc DID est absent du document"));
                log.warn("Missing DID box for run [{}] in NAME_VALUE branch; DID update skipped",
                        task.getRun().getId());
                return;
            }
            // tBoxSrcBox stays null → SystemTaskProcessStrategy VALUE mode → an UPDATE bloc in blocsUpdate.
            task.setValue(didValue);
            log.info("DID update mode: NAME_VALUE for run [{}]", task.getRun().getId());
        }

        // 3. Create the actual bloc as a standard system task.
        // Cross-reference: .NET Task_DID.PostProcess() → Business.Process_System.Process(this).
        systemTaskProcessStrategy.process(task);

        log.info("DID task post-process completed for run [{}]", task.getRun().getId());
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/Run.java`

SHA-256: `3f36ef8cb9dc65fa3e0ee5bff615b7e2bb27ead20ac776f1e75858aaf84103a0`

````java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness;
import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import lombok.AccessLevel;
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

    /**
     * Next QXPS working-document suffix for this run. The accepted caller retains this counter
     * across overflow reprocessing of the same run.
     */
    @Getter(AccessLevel.NONE)
    @Setter(AccessLevel.NONE)
    private int qxpsExecutionCount = 1;

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

    public int currentQxpsExecutionNumber() {
        return qxpsExecutionCount;
    }

    /** Advance only after QXPS execution and the working-document switch both succeed. */
    public void advanceQxpsExecutionNumber() {
        qxpsExecutionCount++;
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
````

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/RunTask.java`

SHA-256: `45a2c3b65b9e524f8b5e86a302a863741f380b41ae1042f0acba1ddf6bb5f7ad`

````java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Consolidates tasks into execution steps for the QuarkXPress server.
 * Provides getSteps() which builds the ordered list of RunTaskStep:
 * <ol>
 *   <li>Step[0]: UPDATE — all blocsUpdate (text values via SOAP, directCall=false)</li>
 *   <li>Step[1]: PAGINATION — blocs with pagination=true (page create/remove via HTTP)</li>
 *   <li>Step[2..N]: MODIFY — remaining blocsModify, split at splitStepBoxNumber per step</li>
 * </ol>
 *
 * Cross-reference: QXP.Engine.Core.Run_Task
 */
@Getter
@Slf4j
public class RunTask {

    /** Tasks that have modify blocs. Keyed by task ID, preserves order. */
    private final Map<Integer, TaskBase> tasksModifier = new LinkedHashMap<>();

    /** Tasks that have update blocs. Keyed by task ID, preserves order. */
    private final Map<Integer, TaskBase> tasksUpdate = new LinkedHashMap<>();

    /**
     * Maximum blocs per modify step. If exceeded, a new step is created.
     * Default 5000 (from .NET EngineCoreSetting.Def_Step_Limit).
     */
    private int splitStepBoxNumber = 5000;

    /** Temporary steps (intermediate modify steps created when splitting). */
    private List<RunTaskStep> stepsTemp = null;

    /** Final ordered list of steps. */
    private List<RunTaskStep> steps = null;

    private final Run run;

    public RunTask() {
        this.run = null;
    }

    public RunTask(Run run) {
        this.run = run;
    }

    /**
     * Add a task to the appropriate task lists based on its blocs.
     * Called during Pass 2 (Verify) of ProcessTasksServiceImpl.
     *
     * @param task the task that has been processed and verified
     */
    public void addTask(TaskBase task) {
        if (task.getBlocsModify().size() > 0) {
            tasksModifier.put(task.getId(), task);
        }
        if (task.getBlocsUpdate().size() > 0) {
            tasksUpdate.put(task.getId(), task);
        }
    }

    /**
     * Build the ordered list of execution steps from all collected tasks.
     * This is the main aggregation method called by Step 5.
     *
     * <p>Step ordering:
     * <ol>
     *   <li>UPDATE step — all blocsUpdate, directCall=false (SOAP)</li>
     *   <li>PAGINATION step — blocs with pagination=true</li>
     *   <li>Intermediate MODIFY steps (if split due to box count limit)</li>
     *   <li>Final MODIFY step — remaining blocsModify</li>
     * </ol>
     *
     * Cross-reference: QXP.Engine.Core.Run_Task.Get_Steps()
     *
     * @return the ordered list of RunTaskStep
     */
    public List<RunTaskStep> getSteps() {
        if (steps != null) {
            return steps;
        }

        int index = 0;
        int nbModify = 0;

        stepsTemp = new ArrayList<>();
        steps = new ArrayList<>();

        // ================================================================
        // Step 1: UPDATE step — all text value changes (SOAP/ParamsValue)
        // Direct_Call = false → goes through QuarkXPress Manager (SOAP)
        // ================================================================

        RunTaskStep updateStep = new RunTaskStep(run);
        updateStep.setDirectCall(false);

        if (!tasksUpdate.isEmpty()) {
            for (TaskBase task : tasksUpdate.values()) {
                updateStep.getBlocsUpdate().addAll(task.getBlocsUpdate().values());
            }
        }

        if (!updateStep.getBlocsUpdate().isEmpty()) {
            steps.add(updateStep);
        }

        // ================================================================
        // Step 2: PAGINATION step — blocs with pagination=true
        // Step 3+: MODIFY steps — remaining structural modifications
        // ================================================================

        RunTaskStep paginationStep = new RunTaskStep(run);
        RunTaskStep modifyStep = new RunTaskStep(run);

        for (TaskBase taskModify : tasksModifier.values()) {
            if (taskModify.getBlocsModify().isEmpty()) {
                continue;
            }

            boolean haveModifyPagination = false;
            boolean haveModify = false;

            for (BlocBase bloc : taskModify.getBlocsModify().values()) {
                if (bloc.isPagination()) {
                    // Pagination blocs → pagination step
                    haveModifyPagination = true;
                    paginationStep.getBlocsModify().add(bloc);
                } else {
                    // Regular modify blocs → modify step
                    nbModify += bloc.getNbBox();
                    haveModify = true;
                    modifyStep.getBlocsModify().add(bloc);
                }

                // Check if we need to split into a new modify step
                if (splitStepBoxNumber > 0 && nbModify > splitStepBoxNumber) {
                    // Remove old and add new evaluateInfo task reference
                    modifyStep.removeEvaluateInfoTask(taskModify);
                    modifyStep.addEvaluateInfoTask(taskModify);

                    // Save current modify step to temp list
                    stepsTemp.add(modifyStep);

                    // Create new modify step
                    modifyStep = new RunTaskStep(run);
                    haveModify = false;
                    nbModify = 0;
                }
            }

            // Register evaluateInfo callbacks
            if (haveModifyPagination) {
                paginationStep.addEvaluateInfoTask(taskModify);
                paginationStep.setPagination(true);
            }

            if (haveModify) {
                modifyStep.removeEvaluateInfoTask(taskModify);
                modifyStep.addEvaluateInfoTask(taskModify);
            }
        }

        // Add steps in correct order:
        // 1. Pagination step (page operations first)
        if (!paginationStep.getBlocsModify().isEmpty()) {
            steps.add(paginationStep);
        }

        // 2. Intermediate modify steps (from splitting)
        if (!stepsTemp.isEmpty()) {
            steps.addAll(stepsTemp);
        }

        // 3. Final modify step
        if (!modifyStep.getBlocsModify().isEmpty()) {
            steps.add(modifyStep);
        }

        // Number the steps
        for (RunTaskStep step : steps) {
            step.setIndex(index++);
        }

        return steps;
    }

    /**
     * Get total number of excluded boxes across all steps.
     *
     * Cross-reference: .NET Run_Task.NbExcludeBoxes
     */
    public int getNbExcludeBoxes() {
        int excludes = 0;
        if (steps != null) {
            for (RunTaskStep step : steps) {
                excludes += step.getNbBoxExcluded();
            }
        }
        return excludes;
    }

    /** Returns the maximum-box budget calculated for the final execution step. */
    public int getLastNbMaxDocBoxes() {
        if (steps == null || steps.isEmpty()) {
            return 0;
        }
        return steps.get(steps.size() - 1).getNbMaxBoxes();
    }

    /**
     * Set the split step box number (maximum blocs per modify step).
     *
     * @param splitStepBoxNumber max blocs per step
     */
    public void setSplitStepBoxNumber(int splitStepBoxNumber) {
        this.splitStepBoxNumber = splitStepBoxNumber;
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/business/QxpsCallerBusiness.java`

SHA-256: `932ebf5f3fd217b8fd0be65b890d050c3a08125437ca2ed8509b298262eddf5a`

````java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunTaskStep;
import com.socgen.sgs.api.quark.engine.domain.modifier.QxpsModifier;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.client.QxpsHttpClient;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.config.QxpsProperties;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.exception.QxpsException;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.helper.QxpsProjectSerializer;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.*;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsResponseInfo;
import com.socgen.sgs.api.quark.engine.infra.interop.qxpsm.QxpsmSoapClient;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.NameValueParam;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.QContentData;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * Business bridge that drives QuarkXPress Server / Manager for a run's modification steps and final
 * renders. This is the service → infra boundary: the {@code service} layer calls this {@code business}
 * class, which in turn calls the {@code infra.interop} clients (same shape as service → business → dao).
 *
 * <p>Cross-reference: QXP.Engine.Core.QXPS_Caller.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class QxpsCallerBusiness {

    private static final String MODIFY_NAME_PATTERN = "Modify_%s.xml";
    private static final String NEW_GABARIT_NAME_WITH_ID_PATTERN = "%s_%d_%d.%s";
    private static final String NEW_GABARIT_NAME_PATTERN = "%s_%d.%s";
    // .NET uses {0:HHmmssff} (2 fractional-second digits); Java 'SS' = 2 fraction digits. Finding #62.
    private static final DateTimeFormatter TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("HHmmssSS");

    private final QxpsHttpClient qxpsHttpClient;
    private final QxpsmSoapClient qxpsmSoapClient;
    private final QxpsProperties qxpsProperties;
    private final FilePoolPort filePool;

    // ========================================================================
    // Process — execute all steps
    // Cross-reference: QXPS_Caller.Process()
    // ========================================================================

    public void process(Run run) {
        if (run.getRunProperties().isModeDegrade()) {
            log.info("Mode degrade detected — no modifications executed for run [{}]", run.getId());
            return;
        }

        List<RunTaskStep> steps = run.getRunTask().getSteps();
        boolean stopProcess = false;

        log.info("Starting step execution for run [{}] with {} steps", run.getId(), steps.size());

        for (RunTaskStep step : steps) {
            log.info("Preparing step [{}] for run [{}]", step.getIndex(), run.getId());

            step.prepare(stopProcess);

            log.info("Executing step [{}]: add={} update={} excluded={}",
                    step.getIndex(), step.getNbBoxAdded(),
                    step.getNbBoxUpdate(), step.getNbBoxExcluded());

            if (step.isFullExclude()) {
                log.info("Step [{}] fully excluded — nothing to execute", step.getIndex());
            } else {
                if (step.getPrepareStep() != null) {
                    log.info("Executing prepare sub-step for step [{}]", step.getIndex());
                    executeStep(run, step.getPrepareStep());
                }
                executeStep(run, step);
            }

            stopProcess = stopProcess || step.isPartialExclude();
            log.info("Step [{}] completed for run [{}]", step.getIndex(), run.getId());
        }

        int nbExcluded = run.getRunTask().getNbExcludeBoxes();
        if (nbExcluded > 0) {
            int maximum = run.getRunTask().getLastNbMaxDocBoxes();
            String message = String.format(
                    "La taille du document (%d boxes) ne permettait pas d'effectuer toutes les modifications, %d Boxes ont été exclues",
                    maximum, nbExcluded);
            run.getErrors().add(new RunError(RunError.CRITIQUE, message));
            run.trace(message);
            log.warn("Run [{}]: {} boxes excluded; final step maximum={}",
                    run.getId(), nbExcluded, maximum);
        }

        log.info("All steps completed for run [{}]", run.getId());
    }

    // ========================================================================
    // Execute — single step
    // Cross-reference: QXPS_Caller.Execute(Run_Task_Step)
    // ========================================================================

    private void executeStep(Run run, RunTaskStep step) {
        DocumentDomain gabarit = run.getGabarit();
        String currentDocName = gabarit.getFilePoolPath();
        String newGabaritName = getNewGabaritNameExt(
                gabarit, run.currentQxpsExecutionNumber());
        String poolBasePath = qxpsProperties.getPool().getDefaultPath();
        String saveAsPath = run.getRunProperties().getPoolPathAbsolute("", poolBasePath);

        QxpsModifier modifier = new QxpsModifier();
        modifier.addRange(step.getBlocsModify());

        if (step.isDirectCall()) {
            executeDirectCall(run, step, modifier, currentDocName, saveAsPath, newGabaritName);
        } else {
            executeSoapCall(step, modifier, currentDocName, saveAsPath, newGabaritName);
        }

        updateGabaritAfterStep(run, newGabaritName, currentDocName);

        run.advanceQxpsExecutionNumber();
    }

    // ========================================================================
    // HTTP (directCall=true)
    // ========================================================================

    private void executeDirectCall(Run run, RunTaskStep step, QxpsModifier modifier,
                                   String documentName, String saveAsPath,
                                   String newGabaritName) {
        // All messages for this step are combined into ONE QuarkXPress Server URL and sent
        // as ONE HTTP call (sorted by priority by the request builder), exactly like .NET
        // QXPS_Caller.Execute(): ParamsValue + Modify + SaveAs + QXP rendered in a single call.
        // Cross-reference: QXPS_Caller.Execute(Run_Task_Step).
        List<QxpsMessage> messages = new ArrayList<>();

        // 1. ParamsValue (name/value updates) — query only, no path.
        if (!step.getNameValues().isEmpty()) {
            NameValueParam[] nvArray = step.getNameValues().toArray(new NameValueParam[0]);
            messages.add(new ParamsValueMessage(nvArray));
            log.debug("ParamsValue queued with {} entries", nvArray.length);
        }

        // 2. Modify — the modify XML is uploaded as a SEPARATE standalone POST first
        //    (matching .NET QXPS_File_Manager.Addfile), then referenced by the combined call.
        if (!modifier.isEmpty()) {
            Project project = modifier.getProject();
            byte[] modifyXml = QxpsProjectSerializer.toBytes(project);
            // Scope the modify file to the run's pool directory (R_<runId>/Modify_xxx.xml) for per-run
            // isolation, mirroring .NET GetPoolPath. Both the upload and the reference use the same
            // scoped name. Findings #27/#31.
            String modifyFileName = run.getRunProperties().getPoolPath(
                    String.format(MODIFY_NAME_PATTERN, LocalDateTime.now().format(TIMESTAMP_FORMAT)));

            // Standalone upload of the modify XML to the document pool.
            qxpsHttpClient.execute(modifyFileName, new AddFileMessage(modifyXml));

            // Reference to the uploaded modify file (added to the combined call).
            messages.add(new ModifyMessage(modifyFileName));
        }

        // 3. SaveAs — replace=true, saveToPool=false (matches .NET Execute(): the file is written
        //    to the absolute pool dir on the Quark host, but not registered in the server pool).
        messages.add(new SaveAsMessage(saveAsPath, newGabaritName, true, false));

        // 4. QXP render — forces QuarkXPress to render/save the document as QXP before SaveAs.
        messages.add(new QxpRenderMessage());

        // ONE combined call.
        qxpsHttpClient.executeCombined(documentName, messages);
    }

    // ========================================================================
    // SOAP (directCall=false)
    // ========================================================================

    private void executeSoapCall(RunTaskStep step, QxpsModifier modifier,
                                 String documentName, String saveAsPath,
                                 String newGabaritName) {
        Project project = modifier.isEmpty() ? null : modifier.getProject();

        QContentData result = qxpsmSoapClient.executeStep(
                documentName, step.getNameValues(), project,
                saveAsPath, newGabaritName);

        if (result != null && result.getStreamValue() != null) {
            log.debug("SOAP call returned {} bytes of QXP data",
                    result.getStreamValue().length);
        }
    }

    // ========================================================================
    // Render — final outputs
    // Cross-reference: QXPS_Caller.Render()
    // ========================================================================

    public QxpsCallerResult render(Run run, boolean renderPdf, boolean renderJpg,
                                   boolean renderQxp, String compression, String downsample) {
        String documentName = run.getGabarit().getFilePoolPath();
        QxpsCallerResult result = new QxpsCallerResult();

        log.info("Starting final renders for run [{}]", run.getId());

        if (renderJpg) {
            // .NET QXPS_Caller.Render: the JPG render is NOT guarded — a failure must propagate
            // so the run is marked ERROR (do not swallow).
            QxpsResponseInfo response = qxpsHttpClient.execute(
                    documentName, new JpegRenderMessage());
            result.setJpgData(response.getBinaryResponse());
            log.info("JPEG render completed for run [{}]", run.getId());
        }

        // ONLY a QXPS render error (e.g. empty document) is non-blocking for PDF — matches .NET
        // Render() which catches QXPS_Exception but rethrows any other Exception.
        if (renderPdf) {
            try {
                PdfRenderMessage pdfMessage = new PdfRenderMessage();
                // All three down-sample params take the down-sample value; all three compression
                // params take the compression value (matches .NET: ColorImageDownSample =
                // GrayscaleImageDownSample = MonochromeImagedownSample = Value_Compression;
                // ColorCompression = GrayscaleCompression = MonochromeCompression = Compression).
                pdfMessage.setColorImageDownSample(downsample);
                pdfMessage.setGrayscaleImageDownSample(downsample);
                pdfMessage.setMonochromeImageDownSample(downsample);
                pdfMessage.setColorCompression(compression);
                pdfMessage.setGrayscaleCompression(compression);
                pdfMessage.setMonochromeCompression(compression);
                QxpsResponseInfo response = qxpsHttpClient.execute(documentName, pdfMessage);
                result.setPdfData(response.getBinaryResponse());
                log.info("PDF render completed for run [{}]", run.getId());
            } catch (QxpsException e) {
                run.getErrors().add(new RunError(
                        RunError.CRITIQUE, "Rendu Impossible du document pdf"));
                log.warn("PDF render failed for run [{}]; exceptionType={}; continuing with QXP render",
                        run.getId(), e.getClass().getSimpleName());
            }
        }

        if (renderQxp) {
            // .NET QXPS_Caller.Render: the QXP fetch is NOT guarded — a failure must propagate
            // so the run is marked ERROR (do not swallow).
            // The latest QXP version is already saved in the pool — fetch it via a 'literal'
            // call (no re-render), exactly like .NET: QXPS_Helper.GetFileData(Gabarit.FilePoolPath).
            QxpsResponseInfo response = qxpsHttpClient.execute(
                    documentName, new LiteralMessage());
            result.setQxpData(response.getBinaryResponse());
            log.info("QXP fetched (literal) for run [{}]", run.getId());
        }

        log.info("All renders completed for run [{}]", run.getId());
        return result;
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    private void updateGabaritAfterStep(Run run, String newGabaritName, String previousDocName) {
        DocumentDomain gabarit = run.getGabarit();
        String newPoolPath = run.getRunProperties().getPoolPath(newGabaritName);
        // Absolute path on the Quark host, kept consistent with the new pool name. Finding #92.
        String newFullPath = run.getRunProperties().getPoolPathAbsolute(
                newGabaritName, qxpsProperties.getPool().getDefaultPath());

        // Download the freshly-saved QXP binary via a 'literal' call (no re-render), exactly
        // like .NET Document.Change_Document() → QXPS_Helper.GetFileData(filePoolPath).
        byte[] newData = qxpsHttpClient.execute(newPoolPath, new LiteralMessage()).getBinaryResponse();

        // Swap the gabarit to the new version (name/pool path/abs path + binary, purges cached XML/Project).
        gabarit.changeDocument(newGabaritName, newPoolPath, newFullPath, newData);

        // Register the new pool file as known so it is not re-uploaded later.
        // Cross-reference: .NET QXPS_File_Manager.Addfile_Inform(newPoolName).
        filePool.inform(newPoolPath);

        log.debug("Gabarit changed: [{}] → [{}] ({} bytes)",
                previousDocName, newPoolPath, newData != null ? newData.length : 0);
    }

    private String getNewGabaritNameExt(DocumentDomain gabarit, int executionCount) {
        // Use the Format verbatim (no case change) so the generated gabarit name matches the pool name
        // the server produces (lowercasing it would diverge). Finding #57.
        if (gabarit.getId() != null && gabarit.getId() > 0) {
            return String.format(NEW_GABARIT_NAME_WITH_ID_PATTERN,
                    gabarit.getPrefix(), gabarit.getId(), executionCount,
                    gabarit.getFormat() != null ? gabarit.getFormat() : "QXP");
        } else {
            return String.format(NEW_GABARIT_NAME_PATTERN,
                    gabarit.getName(), executionCount,
                    gabarit.getFormat() != null ? gabarit.getFormat() : "QXP");
        }
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/RunStartUpdateDaoImpl.java`

SHA-256: `360dc66e9654fdd29ce18e1e4c7097a862abdd79d6f662eba82f77b54b82ce5a`

````java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.infra.dao.RunStartUpdateDao;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.LocalDateTime;

/**
 * Implementation of RunStartUpdateDao that executes the Start_Run Oracle procedure
 */
@Repository
@Slf4j
public class RunStartUpdateDaoImpl implements RunStartUpdateDao {

    static final int START_DATE_SQL_TYPE = Types.TIMESTAMP;

    private final SimpleJdbcCall startRunCall;

    @Autowired
    public RunStartUpdateDaoImpl(DataSource dataSource) {
        // Start_Run is a PROCEDURE in QXP_PK_RUN catalog
        this.startRunCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_RUN")
                .withProcedureName("Start_Run")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlParameter("p_id_run", Types.NUMERIC),
                        new SqlParameter("p_run_status", Types.NUMERIC),
                        new SqlParameter("p_date_debut", START_DATE_SQL_TYPE)
                );
    }

    @Override
    public void startRun(Run run) {
        log.info("Starting run with ID: {}", run.getId());

        // Set start date to current time if not already set
        LocalDateTime startDate = run.getStartDate();
        if (startDate == null) {
            startDate = LocalDateTime.now();
            run.setStartDate(startDate);
        }

        // Prepare parameters for the procedure
        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_run", run.getId())
                .addValue("p_run_status", run.getStatus().getStatusCode())
                .addValue("p_date_debut", Timestamp.valueOf(startDate));

        try {
            // Execute the procedure
            startRunCall.execute(params);
            log.info("Successfully started run with ID: {}", run.getId());
        } catch (Exception e) {
            log.error("Error starting run with ID: {}", run.getId(), e);
            throw new RuntimeException("Failed to start run: " + run.getId(), e);
        }
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/helper/InvariantValueConverter.java`

SHA-256: `7cacfd6dd6465e2d4ee2bc787d10c2306ff90c685c8965b52c22afb2a204605e`

````java
package com.socgen.sgs.api.quark.engine.domain.helper;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeFormatterBuilder;
import java.time.format.DateTimeParseException;
import java.time.format.ResolverStyle;
import java.time.temporal.ChronoField;
import java.time.temporal.TemporalAccessor;
import java.util.List;
import java.util.Locale;

/**
 * Culture-invariant conversions used at the database boundary.
 *
 * <p>The numeric path models a 96-bit decimal coefficient with a scale from 0 to 28. Excess
 * fractional precision is rounded half-even. Integer conversion truncates toward zero and is
 * checked, so a parsed value outside the signed 32-bit range fails instead of wrapping.
 */
public final class InvariantValueConverter {

    public static final BigDecimal DECIMAL_UNSET =
            new BigDecimal("-79228162514264337593543950335");
    public static final LocalDateTime DATE_TIME_UNSET = LocalDateTime.of(1, 1, 1, 0, 0);

    private static final BigInteger MAX_DECIMAL_COEFFICIENT =
            new BigInteger("79228162514264337593543950335");
    private static final int MAX_DECIMAL_SCALE = 28;

    private static final List<DateTimeFormatter> DATE_TIME_FORMATTERS = List.of(
            dateTimeFormatter("M/d/uuuu", " ", false),
            dateTimeFormatter("M/d/uuuu", " ", true),
            dateTimeFormatter("uuuu-M-d", " ", false),
            dateTimeFormatter("uuuu-M-d", " ", true),
            dateTimeFormatter("uuuu-M-d", "T", false),
            englishDateTimeFormatter("MMMM d, uuuu", false),
            englishDateTimeFormatter("MMMM d, uuuu", true),
            englishDateTimeFormatter("MMM d, uuuu", false),
            englishDateTimeFormatter("MMM d, uuuu", true),
            englishDateTimeFormatter("d MMMM uuuu", false),
            englishDateTimeFormatter("d MMMM uuuu", true),
            englishDateTimeFormatter("d MMM uuuu", false),
            englishDateTimeFormatter("d MMM uuuu", true),
            englishDateTimeFormatter("MMM d uuuu", false),
            englishDateTimeFormatter("MMM d uuuu", true),
            reducedYearDateTimeFormatter(false),
            reducedYearDateTimeFormatter(true),
            dateTimeFormatter("M-d-uuuu", " ", false),
            dateTimeFormatter("M-d-uuuu", " ", true)
    );

    private static final List<DateTimeFormatter> DATE_FORMATTERS = List.of(
            strictDateFormatter("M/d/uuuu"),
            strictDateFormatter("uuuu-M-d"),
            strictEnglishDateFormatter("MMMM d, uuuu"),
            strictEnglishDateFormatter("MMM d, uuuu"),
            strictEnglishDateFormatter("d MMMM uuuu"),
            strictEnglishDateFormatter("d MMM uuuu"),
            strictEnglishDateFormatter("MMM d uuuu"),
            strictDateFormatter("uuuu/M/d"),
            strictDateFormatter("M-d-uuuu"),
            reducedYearDateFormatter()
    );

    private InvariantValueConverter() {
    }

    /** Returns the unset sentinel for empty, malformed, or non-representable input. */
    public static BigDecimal toDecimal(String value) {
        BigDecimal parsed = parseDecimal(value);
        return parsed != null ? parsed : DECIMAL_UNSET;
    }

    /**
     * Returns the unset sentinel for empty/malformed input and throws for a parsed Int32 overflow.
     */
    public static int toInt32(String value) {
        BigDecimal parsed = parseDecimal(value);
        if (parsed == null) {
            return Integer.MIN_VALUE;
        }
        return parsed.setScale(0, RoundingMode.DOWN).intValueExact();
    }

    /** Returns the unset sentinel for empty, malformed, or out-of-range input. */
    public static LocalDateTime toDateTime(String value) {
        if (value == null || value.isEmpty()) {
            return DATE_TIME_UNSET;
        }

        String candidate = value.strip();
        if (candidate.isEmpty()) {
            return DATE_TIME_UNSET;
        }

        LocalDateTime offsetDateTime = parseOffsetDateTime(candidate);
        if (offsetDateTime != null) {
            return offsetDateTime;
        }

        for (DateTimeFormatter formatter : DATE_TIME_FORMATTERS) {
            try {
                TemporalAccessor parsed = formatter.parse(candidate);
                LocalDate date = LocalDate.from(parsed);
                LocalTime time = LocalTime.from(parsed);
                return LocalDateTime.of(date, time);
            } catch (DateTimeParseException ignored) {
                // Try the next invariant form.
            }
        }

        for (DateTimeFormatter formatter : DATE_FORMATTERS) {
            try {
                return LocalDate.parse(candidate, formatter).atStartOfDay();
            } catch (DateTimeParseException ignored) {
                // Try the next invariant form.
            }
        }

        LocalDate today = LocalDate.now();
        for (DateTimeFormatter formatter : List.of(
                strictEnglishDateFormatter("MMMM d"),
                strictEnglishDateFormatter("MMM d"))) {
            try {
                TemporalAccessor parsed = formatter.parse(candidate);
                return LocalDate.of(
                        today.getYear(),
                        parsed.get(ChronoField.MONTH_OF_YEAR),
                        parsed.get(ChronoField.DAY_OF_MONTH)).atStartOfDay();
            } catch (DateTimeParseException ignored) {
                // Try the next invariant form.
            }
        }

        for (DateTimeFormatter formatter : List.of(
                strictEnglishDateFormatter("uuuu MMMM"),
                strictEnglishDateFormatter("uuuu MMM"))) {
            try {
                TemporalAccessor parsed = formatter.parse(candidate);
                return LocalDate.of(
                        parsed.get(ChronoField.YEAR),
                        parsed.get(ChronoField.MONTH_OF_YEAR),
                        1).atStartOfDay();
            } catch (DateTimeParseException ignored) {
                // Try the next invariant form.
            }
        }

        for (DateTimeFormatter formatter : List.of(
                timeOnlyFormatter(false),
                timeOnlyFormatter(true))) {
            try {
                return LocalDateTime.of(today, LocalTime.parse(candidate, formatter));
            } catch (DateTimeParseException ignored) {
                // Try the next invariant form.
            }
        }

        return DATE_TIME_UNSET;
    }

    private static LocalDateTime parseOffsetDateTime(String candidate) {
        String normalized = candidate.indexOf('T') >= 0
                ? candidate
                : candidate.replaceFirst(" ", "T");
        try {
            return OffsetDateTime.parse(normalized, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
                    .atZoneSameInstant(ZoneId.systemDefault())
                    .toLocalDateTime();
        } catch (DateTimeParseException ignored) {
            return null;
        }
    }

    private static BigDecimal parseDecimal(String value) {
        if (value == null || value.isEmpty()) {
            return null;
        }

        String candidate = value.replace(" ", "").strip();
        if (candidate.isEmpty()) {
            return null;
        }

        int currencyIndex = candidate.indexOf('¤');
        if (currencyIndex >= 0) {
            boolean validCurrencyPosition = currencyIndex == 0
                    || currencyIndex == candidate.length() - 1
                    || (currencyIndex == 1 && "+-(".indexOf(candidate.charAt(0)) >= 0)
                    || (currencyIndex == candidate.length() - 2
                        && "+-)".indexOf(candidate.charAt(candidate.length() - 1)) >= 0);
            if (!validCurrencyPosition || currencyIndex != candidate.lastIndexOf('¤')) {
                return null;
            }
            candidate = candidate.substring(0, currencyIndex)
                    + candidate.substring(currencyIndex + 1);
        }

        boolean negativeByParentheses = candidate.startsWith("(") && candidate.endsWith(")");
        if (negativeByParentheses) {
            candidate = candidate.substring(1, candidate.length() - 1);
        } else if (candidate.indexOf('(') >= 0 || candidate.indexOf(')') >= 0) {
            return null;
        }

        if (candidate.isEmpty()) {
            return null;
        }

        boolean negativeByTrailingSign = candidate.endsWith("-");
        boolean positiveByTrailingSign = candidate.endsWith("+");
        if (negativeByTrailingSign || positiveByTrailingSign) {
            candidate = candidate.substring(0, candidate.length() - 1);
        }

        boolean negativeByLeadingSign = candidate.startsWith("-");
        boolean positiveByLeadingSign = candidate.startsWith("+");
        if (negativeByLeadingSign || positiveByLeadingSign) {
            candidate = candidate.substring(1);
        }

        int signCount = (negativeByParentheses ? 1 : 0)
                + (negativeByTrailingSign || positiveByTrailingSign ? 1 : 0)
                + (negativeByLeadingSign || positiveByLeadingSign ? 1 : 0);
        if (signCount > 1 || candidate.isEmpty()) {
            return null;
        }

        int exponentIndex = Math.max(candidate.indexOf('e'), candidate.indexOf('E'));
        String mantissa = exponentIndex >= 0 ? candidate.substring(0, exponentIndex) : candidate;
        String exponent = exponentIndex >= 0 ? candidate.substring(exponentIndex) : "";
        if (exponentIndex >= 0
                && (exponent.length() < 2 || !exponent.matches("[eE][+-]?\\d+"))) {
            return null;
        }

        int decimalIndex = mantissa.indexOf('.');
        if (decimalIndex != mantissa.lastIndexOf('.')) {
            return null;
        }
        if (mantissa.startsWith(",")
                || (decimalIndex >= 0 && mantissa.substring(decimalIndex + 1).indexOf(',') >= 0)) {
            return null;
        }

        String normalizedMantissa = mantissa.replace(",", "");
        if (!normalizedMantissa.matches("(?:\\d+(?:\\.\\d*)?|\\.\\d+)")) {
            return null;
        }

        try {
            BigDecimal parsed = new BigDecimal(normalizedMantissa + exponent);
            if (negativeByParentheses || negativeByTrailingSign || negativeByLeadingSign) {
                parsed = parsed.negate();
            }
            return fitDecimal(parsed);
        } catch (NumberFormatException | ArithmeticException ignored) {
            return null;
        }
    }

    private static BigDecimal fitDecimal(BigDecimal value) {
        BigDecimal fitted = value;
        if (fitted.scale() < 0) {
            fitted = fitted.setScale(0);
        }
        if (fitted.scale() > MAX_DECIMAL_SCALE) {
            fitted = fitted.setScale(MAX_DECIMAL_SCALE, RoundingMode.HALF_EVEN);
        }

        while (fitted.unscaledValue().abs().compareTo(MAX_DECIMAL_COEFFICIENT) > 0
                && fitted.scale() > 0) {
            fitted = fitted.setScale(fitted.scale() - 1, RoundingMode.HALF_EVEN);
        }

        return fitted.unscaledValue().abs().compareTo(MAX_DECIMAL_COEFFICIENT) <= 0
                ? fitted
                : null;
    }

    private static DateTimeFormatter dateTimeFormatter(
            String datePattern, String separator, boolean twelveHour) {
        DateTimeFormatterBuilder builder = new DateTimeFormatterBuilder()
                .parseCaseInsensitive()
                .appendPattern(datePattern)
                .appendLiteral(separator);
        appendTime(builder, twelveHour);
        return builder.toFormatter(Locale.ENGLISH).withResolverStyle(ResolverStyle.STRICT);
    }

    private static DateTimeFormatter englishDateTimeFormatter(String datePattern, boolean twelveHour) {
        return dateTimeFormatter(datePattern, " ", twelveHour);
    }

    private static DateTimeFormatter reducedYearDateTimeFormatter(boolean twelveHour) {
        DateTimeFormatterBuilder builder = new DateTimeFormatterBuilder()
                .parseCaseInsensitive()
                .appendPattern("M/d/")
                .appendValueReduced(ChronoField.YEAR, 2, 2, 1930)
                .appendLiteral(' ');
        appendTime(builder, twelveHour);
        return builder.toFormatter(Locale.ENGLISH).withResolverStyle(ResolverStyle.STRICT);
    }

    private static void appendTime(DateTimeFormatterBuilder builder, boolean twelveHour) {
        builder.appendValue(twelveHour ? ChronoField.CLOCK_HOUR_OF_AMPM : ChronoField.HOUR_OF_DAY)
                .appendLiteral(':')
                .appendValue(ChronoField.MINUTE_OF_HOUR);
        builder.optionalStart()
                .appendLiteral(':')
                .appendValue(ChronoField.SECOND_OF_MINUTE)
                .optionalStart()
                .appendFraction(ChronoField.NANO_OF_SECOND, 0, 7, true)
                .optionalEnd()
                .optionalEnd();
        if (twelveHour) {
            builder.appendLiteral(' ').appendText(ChronoField.AMPM_OF_DAY);
        }
        builder.parseDefaulting(ChronoField.SECOND_OF_MINUTE, 0)
                .parseDefaulting(ChronoField.NANO_OF_SECOND, 0);
    }

    private static DateTimeFormatter strictDateFormatter(String pattern) {
        return new DateTimeFormatterBuilder()
                .parseCaseInsensitive()
                .appendPattern(pattern)
                .toFormatter(Locale.ENGLISH)
                .withResolverStyle(ResolverStyle.STRICT);
    }

    private static DateTimeFormatter strictEnglishDateFormatter(String pattern) {
        return strictDateFormatter(pattern);
    }

    private static DateTimeFormatter reducedYearDateFormatter() {
        return new DateTimeFormatterBuilder()
                .parseCaseInsensitive()
                .appendPattern("M/d/")
                .appendValueReduced(ChronoField.YEAR, 2, 2, 1930)
                .toFormatter(Locale.ENGLISH)
                .withResolverStyle(ResolverStyle.STRICT);
    }

    private static DateTimeFormatter timeOnlyFormatter(boolean twelveHour) {
        DateTimeFormatterBuilder builder = new DateTimeFormatterBuilder().parseCaseInsensitive();
        appendTime(builder, twelveHour);
        return builder.toFormatter(Locale.ENGLISH).withResolverStyle(ResolverStyle.STRICT);
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/InParam.java`

SHA-256: `378f762d094c108383eb9351c609d35392492e84b65d45da0141bac6cfd2cadb`

````java
package com.socgen.sgs.api.quark.engine.domain;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import com.socgen.sgs.api.quark.engine.domain.helper.InvariantValueConverter;
import lombok.Getter;

import java.time.LocalDateTime;

/**
 * Immutable domain value object representing a typed input parameter for a run.
 * Mirrors QXPDataOracle.OraParameter from the .NET implementation.
 * The raw string is retained for traceable domain behavior. Integer, decimal and date values are
 * converted once when the parameter is loaded; all other types retain the raw string.
 */
@Getter
public class InParam {

    private final String name;
    private final DataTypeEnum type;
    private final String stringValue;
    private final Object value;

    public InParam(String name, int type, String stringValue) {
        this(name, DataTypeEnum.fromCode(type), stringValue);
    }

    public InParam(String name, DataTypeEnum type, String stringValue) {
        this.name = name;
        this.type = type;
        this.stringValue = stringValue;
        this.value = toTypedValue(type, stringValue);
    }

    private static Object toTypedValue(DataTypeEnum type, String stringValue) {
        if (type == null) {
            return stringValue;
        }
        switch (type) {
            case INT:
                return InvariantValueConverter.toInt32(stringValue);
            case DECIMAL:
                return InvariantValueConverter.toDecimal(stringValue);
            case DATE:
                LocalDateTime dateTime = InvariantValueConverter.toDateTime(stringValue);
                return dateTime;
            default:
                return stringValue;
        }
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/mapper/InParamSqlMapper.java`

SHA-256: `282b8aa63d3a4b4a6a584660a55848c0a9c8918ca6f07e75f4b01bacc1c590d1`

````java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.domain.helper.InvariantValueConverter;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import org.springframework.jdbc.core.SqlParameterValue;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Maps run InParams to a flat parameter map for the dynamic-SQL named binds.
 *
 * <p>Binds the TYPED value for each param, mirroring .NET
 * {@code Data_Type_Helper.InputToTypedValue} + {@code ConversionInvariante} (InParam.cs:54 sets
 * {@code _value = InputToTypedValue(_string_value, _type)}, InParams.cs:69 binds {@code inParam.Value}):
 * <ul>
 *   <li>INT      → {@link Integer} (Int32 truncation); unset/unparseable → typed SQL NULL</li>
 *   <li>DECIMAL  → {@link BigDecimal}; unset/unparseable → typed SQL NULL</li>
 *   <li>DATE     → an Oracle {@code DATE} ({@link oracle.sql.DATE}, time-preserving) so the gabarit SQL's
 *       {@code to_date(?)} round-trips under any session date format; unset/unparseable → typed SQL NULL</li>
 *   <li>An unset value binds as SQL NULL (not the MIN_VALUE placeholder), matching how the legacy
 *       Oracle parameter layer converts an unset sentinel to a null bind.</li>
 *   <li>DATE_TIME and every other type → the RAW STRING — .NET's switch has no case for DateTime(5)
 *       (nor Text/Currency/Pourcentage), so it falls to {@code default: return value}.</li>
 * </ul>
 * Findings #21, #49, #50, #51.
 */
@Component
public class InParamSqlMapper {

    public Map<String, Object> toParameterMap(Map<String, InParam> inParams) {
        Map<String, Object> params = new LinkedHashMap<>();
        for (Map.Entry<String, InParam> entry : inParams.entrySet()) {
            params.put(entry.getKey(), toTypedValue(entry.getValue()));
        }
        return params;
    }

    private Object toTypedValue(InParam inParam) {
        Object value = inParam.getValue();
        DataTypeEnum type = inParam.getType();
        if (type == null) {
            return value;
        }
        switch (type) {
            case INT: {
                Integer i = (Integer) value;
                return i == Integer.MIN_VALUE ? new SqlParameterValue(Types.NUMERIC, null) : i;
            }
            case DECIMAL: {
                BigDecimal d = (BigDecimal) value;
                return InvariantValueConverter.DECIMAL_UNSET.compareTo(d) == 0
                        ? new SqlParameterValue(Types.NUMERIC, null)
                        : d;
            }
            case DATE: {
                LocalDateTime dateTime = (LocalDateTime) value;
                return InvariantValueConverter.DATE_TIME_UNSET.equals(dateTime)
                        ? new SqlParameterValue(Types.DATE, null)
                        : new oracle.sql.DATE(Timestamp.valueOf(dateTime));
            }
            default:
                // DATE_TIME (5), TEXT, CURRENCY, POURCENTAGE, UNSPECIFIED, CUSTOM → raw string
                // (.NET Data_Type_Helper.InputToTypedValue `default: return value`).
                return value;
        }
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/GetInParamsDaoImpl.java`

SHA-256: `216f499dbcc858c0eccf33713a0e38b32b62d0e3c8aac703e3148608ecb2d9e0`

````java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;
import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.infra.dao.GetInParamsDao;
import com.socgen.sgs.api.quark.engine.mapper.InParamMapper;
import lombok.extern.slf4j.Slf4j;
import oracle.jdbc.OracleTypes;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.SqlOutParameter;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;
import javax.sql.DataSource;
import java.sql.Types;
import java.util.List;
import java.util.Map;
/**
 * Calls Oracle function QXP_PK_RUN.Get_In_Params and populates run.inParams.
 */
@Repository
@Slf4j
public class GetInParamsDaoImpl implements GetInParamsDao {
    private static final String RESULT_KEY = "result_cursor";
    private final SimpleJdbcCall getInParamsCall;
    @Autowired
    public GetInParamsDaoImpl(DataSource dataSource, InParamMapper inParamMapper) {
        this.getInParamsCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_RUN")
                .withFunctionName("Get_In_Params")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlOutParameter(RESULT_KEY, OracleTypes.CURSOR,
                                (rs, rowNum) -> inParamMapper.mapFromResultSet(rs)),
                        new SqlParameter("p_id_suivi", Types.NUMERIC)
                );
    }
    @Override
    public void getInParams(Run run) {
        log.info("Fetching in-params for idSuivi: {}", run.getRunProperties().getIdSuivi());
        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_suivi", run.getRunProperties().getIdSuivi());
        try {
            Map<String, Object> result = getInParamsCall.execute(params);
            log.debug("Input-parameter call returned keys: {}", result.keySet());
            @SuppressWarnings("unchecked")
            List<InParam> rows = (List<InParam>) result.get(RESULT_KEY);
            run.getInParams().clear();
            if (rows != null) {
                for (InParam inParam : rows) {
                    if (run.getInParams().containsKey(inParam.getName())) {
                        throw new IllegalStateException(String.format(
                                "Duplicate input parameter name for suivi %d",
                                run.getRunProperties().getIdSuivi()));
                    }
                    run.getInParams().put(inParam.getName(), inParam);
                }
            }
            log.info("Loaded {} in-params for idSuivi: {}",
                    run.getInParams().size(), run.getRunProperties().getIdSuivi());
        } catch (Exception e) {
            log.error("Error fetching in-params for idSuivi: {}; exceptionType={}",
                    run.getRunProperties().getIdSuivi(), e.getClass().getSimpleName());
            throw new RuntimeException("Failed to fetch in-params for idSuivi: "
                    + run.getRunProperties().getIdSuivi(), e);
        }
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/collection/AddOnlyLinkedHashMap.java`

SHA-256: `f8a60d26c2c26f8a3e4ae3613dd4e1d215406ac8a50079fa45fc3456efd215a9`

````java
package com.socgen.sgs.api.quark.engine.domain.collection;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Insertion-ordered map whose direct insertion operation rejects null and duplicate keys.
 * Existing entries may still be removed or the map cleared between processing passes.
 */
public final class AddOnlyLinkedHashMap<K, V> extends LinkedHashMap<K, V> {

    @Override
    public V put(K key, V value) {
        if (key == null) {
            throw new IllegalArgumentException("Null key is not allowed");
        }
        if (containsKey(key)) {
            throw new IllegalStateException("Duplicate key is not allowed");
        }
        return super.put(key, value);
    }

    @Override
    public void putAll(Map<? extends K, ? extends V> values) {
        for (Map.Entry<? extends K, ? extends V> entry : values.entrySet()) {
            put(entry.getKey(), entry.getValue());
        }
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/task/TaskBase.java`

SHA-256: `5eea8ce0fe7e5a8588b7fc7404e0de1faf8d08027439af9df50cfeda4ac18709`

````java
package com.socgen.sgs.api.quark.engine.domain.task;
import com.socgen.sgs.api.quark.engine.domain.DataNameValue;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;
import com.socgen.sgs.api.quark.engine.domain.collection.AddOnlyLinkedHashMap;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DMasterPage;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import lombok.Getter;
import lombok.Setter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
/** Abstract base class for all task types in a run. */
@Getter
@Setter
public abstract class TaskBase {
    private static final String DEF_NULL_STRING    = " ";
    private static final String DEBUG_INFO_PATTERN = "[%d - %s]";
    private final int    id;
    private final Run    run;
    private String         commentaire;
    private boolean        todo;
    private boolean        toLoad;
    private boolean        allwaysReprocess       = false;
    private String         sourceBlocName;
    private String         destinationBlocName;
    private String         nullString             = DEF_NULL_STRING;
    private SubTaskTypeEnum subTaskType;
    private boolean        inError                = false;
    private DMasterPage    masterPage;
    /** Task properties for page/layout configuration. */
    private final TaskProperties properties = new TaskProperties();
    /** Blocs for value update (NameValue command). Keyed by bloc name. */
    private final Map<String, BlocBase> blocsUpdate = new AddOnlyLinkedHashMap<>();
    /** Blocs for structure/value modification (Modify command). Keyed by bloc name. */
    private final Map<String, BlocBase> blocsModify = new AddOnlyLinkedHashMap<>();
    /** Exception tasks keyed by bloc name. */
    private final Map<String, TaskException> exceptions = new LinkedHashMap<>();
    /** Data generated by this task. */
    private final List<DataNameValue> dataNamesValues = new ArrayList<>();
    protected TaskBase(int id, Run run) {
        this.id         = id;
        this.run        = run;
        this.masterPage = DMasterPage.DEFAULT;
    }
    /** Prepares the task. */
    public abstract void prepare();
    /**
     * Evaluates properties linked to the latest version of the gabarit.
     * Executed between each step before real execution.
     * Override in specific task types.
     */
    public void evaluateInfo() {
        // Re-evaluate the destination bloc's page/layout from the current gabarit XML.
        // Cross-reference: .NET Task_Base.Evaluate_Info().
        if (destinationBlocName != null && !destinationBlocName.isBlank()) {
            properties.setPageNum(getRun().getGabarit().getQxpXml().getPageNum(destinationBlocName));
            properties.setLayoutName(getRun().getGabarit().getQxpXml().getLayoutName(destinationBlocName));
        }
    }
    /**
     * Returns the page ID evaluated from the relative page offset.
     *
     * @param condName     conditional bloc name
     * @param relativePage relative page index
     * @return evaluated page ID
     */
    public int getPageIdFromRelative(String condName, int relativePage) {
        int spreadNum;
        // A conditional bloc, when set, drives the page evaluation; otherwise use the task's own page.
        // Cross-reference: .NET Task_Base.Get_Page_ID_From_Relative().
        if (condName != null && !condName.isBlank()) {
            spreadNum = getRun().getGabarit().getQxpXml().getPageNum(condName);
        } else {
            spreadNum = properties.getPageNum();
        }
        return spreadNum + relativePage;
    }
    /**
     * Returns the spread ID from a given page ID.
     *
     * @param pageId    the page ID
     * @param lagSpread whether spread 1 was deleted (double-page handling)
     * @return the evaluated spread ID
     */
    public int getSpreadIdFromPageId(int pageId, boolean lagSpread) {
        int nbPageBySpread = run.getRunProperties().getNbPageBySpread();
        if (nbPageBySpread == 1) {
            return pageId;
        }
        if (pageId == 1) {
            return 1;
        }
        double val = lagSpread
                ? (double) pageId / nbPageBySpread + 1
                : (double) (pageId + 1) / nbPageBySpread;
        return (int) Math.ceil(val);
    }
    /** Returns the debug info string in format [id - commentaire]. */
    public String getDebugInfo() {
        return String.format(DEBUG_INFO_PATTERN, this.id, this.commentaire);
    }
    /** Resets blocs and data generated during a previous processing step. */
    public void resetProcess() {
        blocsUpdate.clear();
        blocsModify.clear();
        dataNamesValues.clear();
    }
    /** Whether this task makes direct calls to QuarkXPress Server. Override if needed. */
    public boolean isDirectCall() {
        return false;
    }
    /** Whether this task is in degraded mode. Override in specific task types. */
    public boolean isModeDegrade() {
        return false;
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/modifier/ModifierSpread.java`

SHA-256: `77d427ba7bff2e82005aa5c565548085d457e46d5801f0ad774a5fb3429a7892`

````java
package com.socgen.sgs.api.quark.engine.domain.modifier;

import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.domain.collection.AddOnlyLinkedHashMap;
import com.socgen.sgs.api.quark.engine.enums.TaskActionTypeEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.DeleteCells;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Geometry;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Page;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Spread;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Table;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import lombok.Getter;
import lombok.Setter;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Represents a spread in a modifier project hierarchy.
 * Aggregates boxes, pages, tables, and groups, then converts them to SOAP SDK objects.
 *
 * Cross-reference: QXP.Engine.Core.Spread (Modifier namespace)
 */
@Getter
@Setter
public class ModifierSpread {

    private static final String BLOC_OPERATION_CREATE = "CREATE";
    private static final String BLOC_OPERATION_DELETE = "DELETE";

    private String uid;
    private final Map<String, ModifierBox> boxes = new AddOnlyLinkedHashMap<>();
    private final Map<String, ModifierBox> boxesExtra = new AddOnlyLinkedHashMap<>();
    private final Map<String, ModifierGroup> groups = new AddOnlyLinkedHashMap<>();
    private final Map<String, ModifierTable> tables = new LinkedHashMap<>();
    private final Map<String, ModifierPage> pages = new LinkedHashMap<>();
    private boolean create = false;

    public ModifierSpread() {
    }

    /**
     * Build SDK Box array from normal boxes.
     * Cross-reference: .NET Spread.GetSDKBoxes()
     */
    public Box[] getSdkBoxes() {
        List<Box> destBoxes = new ArrayList<>();

        // Normal boxes
        destBoxes.addAll(evaluateSdkBoxes(boxes, false));

        // Groups
        for (ModifierGroup grp : groups.values()) {
            if (grp.getSrcBoxes() != null) {
                for (Box newBox : grp.getSrcBoxes()) {
                    newBox.setOperation(BLOC_OPERATION_CREATE);
                    newBox.setUID("");
                    destBoxes.add(newBox);
                    if (newBox.getGeometry() == null) {
                        newBox.setGeometry(new Geometry());
                    }
                    newBox.getGeometry().setPage(String.valueOf(grp.getPageId()));
                }
            }
        }

        return destBoxes.toArray(new Box[0]);
    }

    /**
     * Build SDK Box array from extra boxes.
     * Cross-reference: .NET Spread.GetSDKBoxesExtra()
     */
    public Box[] getSdkBoxesExtra() {
        List<Box> destBoxes = new ArrayList<>(evaluateSdkBoxes(boxesExtra, true));
        return destBoxes.toArray(new Box[0]);
    }

    private List<Box> evaluateSdkBoxes(Map<String, ModifierBox> boxMap, boolean ignoreOperation) {
        List<Box> destBoxes = new ArrayList<>();
        for (ModifierBox bx : boxMap.values()) {
            Box box = bx.getSrcBox();
            switch (bx.getAction()) {
                case CREATE:
                    if (!ignoreOperation) {
                        box.setOperation(BLOC_OPERATION_CREATE);
                    }
                    box.setUID("");
                    if (box.getGeometry() == null) {
                        box.setGeometry(new Geometry());
                    }
                    box.getGeometry().setPage(String.valueOf(bx.getPageId()));
                    break;
                case MOVE:
                    if (box.getGeometry() != null) {
                        box.getGeometry().setPage(String.valueOf(bx.getPageId()));
                    }
                    break;
                default:
                    break;
            }
            destBoxes.add(box);
        }
        return destBoxes;
    }

    /**
     * Build SDK Table array.
     * Cross-reference: .NET Spread.GetSDKTables()
     */
    public Table[] getSdkTables() {
        List<Table> sdkTables = new ArrayList<>();

        for (ModifierTable tab : tables.values()) {
            if (tab.getAction() == BlocActionEnum.REMOVE) {
                Table table = new Table();
                table.setName(tab.getName());
                table.setOperation(BLOC_OPERATION_DELETE);
                sdkTables.add(table);
            } else if (tab.getTask() != null
                    && tab.getTask().getSubTaskType() == SubTaskTypeEnum.FILE_QXP_PREVIOUS
                    && tab.getSrcTable() != null) {
                Table table = tab.getSrcTable();
                table.setName(tab.getName());
                sdkTables.add(table);
            } else {
                Table table = new Table();
                table.setName(tab.getName());

                List<ModifierLigne> lignes = new ArrayList<>(tab.getLignes().values());
                lignes.sort(Comparator.comparingInt(ModifierLigne::getIndex).reversed());

                List<DeleteCells> deleteCellsList = new ArrayList<>();
                for (ModifierLigne ligne : lignes) {
                    DeleteCells dc = new DeleteCells();
                    dc.setType("ROW");
                    dc.setBaseIndex(String.valueOf(ligne.getIndex()));
                    dc.setDeleteCount("1");
                    deleteCellsList.add(dc);
                }
                if (!deleteCellsList.isEmpty()) {
                    table.setDeleteCells(deleteCellsList.toArray(new DeleteCells[0]));
                    sdkTables.add(table);
                }
            }
        }

        return sdkTables.toArray(new Table[0]);
    }

    /**
     * Build SDK Page array.
     * Cross-reference: .NET Spread.GetSDKPages()
     */
    public Page[] getSdkPages() {
        List<Page> sdkPages = new ArrayList<>();

        for (ModifierPage pg : pages.values()) {
            Page page = new Page();
            page.setUID(pg.getUid());

            // Page operation is driven first by the task's action, then (only when NONE) by the
            // bloc that created the page. Cross-reference: .NET Spread.GetSDKPages().
            TaskActionTypeEnum taskAction = (pg.getTask() != null && pg.getTask().getProperties() != null)
                    ? pg.getTask().getProperties().getTaskAction()
                    : TaskActionTypeEnum.NONE;

            String operation = null;
            switch (taskAction) {
                case NONE:
                    switch (pg.getAction()) {
                        case REMOVE:
                            operation = BLOC_OPERATION_DELETE;
                            break;
                        case CREATE:
                            operation = BLOC_OPERATION_CREATE;
                            break;
                        default:
                            break;
                    }
                    break;
                case REMOVE:
                    operation = BLOC_OPERATION_DELETE;
                    break;
                default: // UPDATE / CREATE → page creation
                    operation = BLOC_OPERATION_CREATE;
                    break;
            }

            page.setOperation(operation);

            if (BLOC_OPERATION_CREATE.equals(operation)) {
                if (pg.getTask() != null && pg.getTask().getMasterPage() != null) {
                    page.setMaster(pg.getTask().getMasterPage().getMasterPageId(0));
                }
                page.setPosition(pg.getPosition());

                if (pg.getIndexPosition() == 0) {
                    this.create = true;
                }
            }
            sdkPages.add(page);

            // Dummy page handling for double-page layouts
            if (pg.isCreateDummyNextPage()) {
                String nextPageId = String.valueOf(Integer.parseInt(pg.getUid()) + 1);

                Page dummyCreate = new Page();
                dummyCreate.setUID(nextPageId);
                dummyCreate.setOperation(BLOC_OPERATION_CREATE);
                sdkPages.add(dummyCreate);

                Page dummyDelete = new Page();
                dummyDelete.setUID(nextPageId);
                dummyDelete.setOperation(BLOC_OPERATION_DELETE);
                sdkPages.add(dummyDelete);
            }
        }

        return sdkPages.toArray(new Page[0]);
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/modifier/QxpsModifier.java`

SHA-256: `ab177cbfe6f272ec1562037ea7f0134442defbf75e343ad5978aea2c029d538e`

````java
package com.socgen.sgs.api.quark.engine.domain.modifier;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocGroup;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocLigne;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocPage;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocTable;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.List;

/**
 * Aggregates all bloc types into a project hierarchy for sending to QuarkXPress Server.
 * Converts BlocBox/BlocPage/BlocTable/BlocGroup/BlocLigne into the Modifier structure
 * (ModifierProjet → ModifierLayout → ModifierSpread → ModifierBox/Page/Table/Group).
 *
 * Cross-reference: QXP.Engine.Core.QXPS_Modifier
 */
@Getter
@Slf4j
public class QxpsModifier {

    private final ModifierProjet projet = new ModifierProjet();
    private boolean empty = true;
    private final List<BlocBase> blocs = new ArrayList<>();

    public QxpsModifier() {
    }

    /**
     * Add a list of blocs to the modifier.
     */
    public void addRange(Iterable<BlocBase> blocs) {
        for (BlocBase bloc : blocs) {
            add(bloc);
        }
    }

    /**
     * Add a single bloc to the modifier hierarchy.
     * Routes to the correct typed add method based on bloc class.
     *
     * Cross-reference: .NET QXPS_Modifier.Add(Bloc_Base)
     */
    public void add(BlocBase bloc) {
        if (bloc.isExclude()) {
            return;
        }
        blocs.add(bloc);

        if (bloc instanceof BlocBox) {
            addBlocBox((BlocBox) bloc);
        } else if (bloc instanceof BlocGroup) {
            addBlocGroup((BlocGroup) bloc);
        } else if (bloc instanceof BlocTable) {
            addBlocTable((BlocTable) bloc);
        } else if (bloc instanceof BlocLigne) {
            addBlocLigne((BlocLigne) bloc);
        } else if (bloc instanceof BlocPage) {
            addBlocPage((BlocPage) bloc);
        }
    }

    private void addBlocBox(BlocBox bloc) {
        ModifierSpread spread = addGetSpread(bloc);
        if (spread == null) return;

        ModifierBox box = new ModifierBox();
        box.setName(bloc.getName());
        box.setAction(bloc.getAction());
        box.setPageId(bloc.getPageId());
        box.setValue(bloc.getValue());
        box.setSrcBox(getBox(bloc, false));
        spread.getBoxes().put(box.getName(), box);

        if (bloc.getSrcExtraBox() != null) {
            ModifierBox extraBox = new ModifierBox();
            extraBox.setName(bloc.getName());
            extraBox.setAction(bloc.getAction());
            extraBox.setPageId(bloc.getPageId());
            extraBox.setValue(bloc.getValue());
            extraBox.setSrcBox(getBox(bloc, true));
            spread.getBoxesExtra().put(extraBox.getName(), extraBox);
        }
    }

    private void addBlocGroup(BlocGroup bloc) {
        ModifierSpread spread = addGetSpread(bloc);
        if (spread == null) return;

        ModifierGroup group = new ModifierGroup();
        group.setName(bloc.getName());
        group.setPageId(bloc.getPageId());
        group.setAction(bloc.getAction());
        group.setSrcBoxes(bloc.getSrcBoxes());
        spread.getGroups().put(group.getName(), group);
    }

    private void addBlocTable(BlocTable bloc) {
        ModifierSpread spread = addGetSpread(bloc);
        if (spread == null) return;

        if (!spread.getTables().containsKey(bloc.getName())) {
            ModifierTable table = new ModifierTable();
            table.setName(bloc.getName());
            table.setAction(bloc.getAction());
            table.setTask(bloc.getTask());
            table.setSrcTable(bloc.getSrcTable());
            spread.getTables().put(table.getName(), table);
        } else {
            ModifierTable existing = spread.getTables().get(bloc.getName());
            if (bloc.getAction() == BlocActionEnum.REMOVE) {
                existing.setAction(bloc.getAction());
                existing.getLignes().clear();
            }
        }
    }

    private void addBlocLigne(BlocLigne bloc) {
        ModifierTable table = addGetTable(bloc);
        if (table == null) return;

        ModifierLigne ligne = new ModifierLigne();
        ligne.setIndex(bloc.getIndex());

        if (!table.getLignes().containsKey(bloc.getIndex())
                && table.getAction() != BlocActionEnum.REMOVE) {
            table.getLignes().put(ligne.getIndex(), ligne);
        }
    }

    private void addBlocPage(BlocPage bloc) {
        ModifierSpread spread = addGetSpread(bloc);
        if (spread == null) return;

        ModifierPage page = new ModifierPage();
        page.setAction(bloc.getAction());
        page.setUid(String.valueOf(bloc.getPageId()));
        page.setPosition(bloc.getPosition());
        page.setIndexPosition(bloc.getIndexPosition());
        page.setName(bloc.getName());
        page.setTask(bloc.getTask());
        page.setCreateDummyNextPage(bloc.isCreateNextDummyPage());

        if (!spread.getPages().containsKey(page.getUid())) {
            spread.getPages().put(page.getUid(), page);
        }
    }

    // ========================================================================
    // Hierarchy navigation helpers
    // ========================================================================

    private ModifierLayout addGetLayout(BlocBase bloc) {
        String layoutName;
        if (bloc.getCondName() != null && !bloc.getCondName().isBlank()) {
            layoutName = bloc.getTask().getRun().getGabarit()
                    .getQxpXml().getLayoutName(bloc.getCondName());
        } else {
            layoutName = bloc.getTask().getProperties().getLayoutName();
        }

        if (layoutName == null || layoutName.isBlank()) {
            return null;
        }

        return projet.getLayouts().computeIfAbsent(layoutName, k -> {
            ModifierLayout layout = new ModifierLayout();
            layout.setName(layoutName);
            return layout;
        });
    }

    private ModifierSpread addGetSpread(BlocBase bloc) {
        ModifierLayout layout = addGetLayout(bloc);
        if (layout == null) {
            // Parity: .NET QXPS_Modifier records Empty_Layout_Or_Spread_For_Bloc (Errors.Add(string) →
            // Error_Type.Unspecified) as an audit-trail entry; it does NOT fail the run. Finding #65.
            bloc.getTask().getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                    "Layout ou Spread NULL pour le bloc " + bloc.getName()));
            log.warn("No layout found for bloc [{}]", bloc.getName());
            return null;
        }

        empty = false;
        String spreadUid = String.valueOf(bloc.getSpreadId());

        return layout.getSpreads().computeIfAbsent(spreadUid, k -> {
            ModifierSpread spread = new ModifierSpread();
            spread.setUid(spreadUid);
            return spread;
        });
    }

    private ModifierTable addGetTable(BlocBase bloc) {
        ModifierSpread spread = addGetSpread(bloc);
        if (spread == null) return null;

        return spread.getTables().computeIfAbsent(bloc.getParentName(), k -> {
            ModifierTable table = new ModifierTable();
            table.setName(bloc.getParentName());
            table.setAction(BlocActionEnum.NONE);
            table.setTask(bloc.getTask());
            return table;
        });
    }

    private Box getBox(BlocBox blocBox, boolean fromExtraSrc) {
        return fromExtraSrc ? blocBox.getSrcExtraBox() : blocBox.getSrcBox();
    }

    // ========================================================================
    // Output
    // ========================================================================

    /**
     * Get the SOAP Project structure.
     * Cross-reference: .NET QXPS_Modifier.GetProject()
     */
    public Project getProject() {
        return projet.getSdkProject();
    }
}
````

### `src/main/java/com/socgen/sgs/api/quark/engine/domain/exception/EngineException.java`

SHA-256: `cc159ff6cd7b962402d7a7a9d9b2158801c54eaa20a5ded213f8b3bdfd14f2b3`

````java
package com.socgen.sgs.api.quark.engine.domain.exception;

import com.socgen.sgs.api.quark.engine.domain.RunError;

/**
 * Controlled engine failure carrying an explicit persisted severity and a payload-safe message.
 *
 * <p>Only messages from this controlled exception type participate in the persisted chain. Raw
 * messages from JDBC, HTTP, XML, SQL or other untyped causes are deliberately excluded.
 */
public final class EngineException extends RuntimeException {

    private static final String CHAIN_PREFIX = "==> ";

    private final int category;

    public EngineException(int category, String safeMessage) {
        this(category, safeMessage, null);
    }

    public EngineException(int category, String safeMessage, Throwable cause) {
        super(requireSafeMessage(safeMessage), cause);
        if (category < RunError.UNSPECIFIED || category > RunError.BLOQUANTE) {
            throw new IllegalArgumentException("Unsupported engine error category");
        }
        this.category = category;
    }

    public int getCategory() {
        return category;
    }

    /** Returns controlled messages from outermost to innermost, one per line. */
    public String getSafeMessageChain() {
        StringBuilder chain = new StringBuilder(System.lineSeparator());
        EngineException current = this;
        while (current != null) {
            chain.append(CHAIN_PREFIX)
                    .append(current.getMessage())
                    .append(System.lineSeparator());
            current = current.getCause() instanceof EngineException
                    ? (EngineException) current.getCause()
                    : null;
        }
        return chain.toString();
    }

    private static String requireSafeMessage(String safeMessage) {
        if (safeMessage == null || safeMessage.isEmpty()) {
            throw new IllegalArgumentException("Safe engine error message is required");
        }
        return safeMessage;
    }
}
````

## Focused test files

### `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/LoadTasksServiceImplTest.java`

SHA-256: `4cac64385504a26b3c153255d4b4593e567c635f88f91e2a1f5ee8d07aac6f00`

````java
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

    @Test
    @DisplayName("Duplicate mapped task ID fails instead of replacing the first task")
    void duplicateMappedTaskIdFails() {
        Map<String, Object> row1 = new HashMap<>();
        Map<String, Object> row2 = new HashMap<>();
        row1.put("ROW", 1);
        row2.put("ROW", 2);
        TaskSql first = new TaskSql(10, run);
        TaskSql second = new TaskSql(10, run);
        when(getTasksBusiness.execute(100)).thenReturn(List.of(row1, row2));
        when(taskMapper.mapToTask(row1, run)).thenReturn(first);
        when(taskMapper.mapToTask(row2, run)).thenReturn(second);

        IllegalStateException failure = assertThrows(
                IllegalStateException.class, () -> loadTasksService.loadTasks(run));

        assertSame(first, run.getTasks().get(10));
        assertTrue(failure.getMessage().contains("task id 10"));
        assertTrue(failure.getMessage().contains("run 100"));
        verifyNoInteractions(getTaskExceptionsBusiness);
    }

    @Test
    @DisplayName("Database task ID zero collides with the synthetic DID task")
    void databaseTaskZeroFailsBeforeDidReplacement() {
        Map<String, Object> row = new HashMap<>();
        TaskSql databaseTask = new TaskSql(0, run);
        when(getTasksBusiness.execute(100)).thenReturn(List.of(row));
        when(taskMapper.mapToTask(row, run)).thenReturn(databaseTask);
        when(getTaskExceptionsBusiness.execute(100)).thenReturn(Collections.emptyList());

        assertThrows(IllegalStateException.class, () -> loadTasksService.loadTasks(run));
        assertSame(databaseTask, run.getTasks().get(0));
        verify(getTaskExceptionsBusiness).execute(100);
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
````

### `src/test/java/com/socgen/sgs/api/quark/engine/service/task/impl/DidTaskPostProcessStrategyTest.java`

SHA-256: `b6f366526d41629b2896407b7b038c29650faf930b6b241f2b04028920a4c212`

````java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDid;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class DidTaskPostProcessStrategyTest {

    private SystemTaskProcessStrategy systemTaskProcessStrategy;
    private DidTaskPostProcessStrategy strategy;
    private Run run;
    private TaskDid didTask;
    private QxpXml qxpXml;

    @BeforeEach
    void setUp() {
        systemTaskProcessStrategy = mock(SystemTaskProcessStrategy.class);
        strategy = new DidTaskPostProcessStrategy(systemTaskProcessStrategy);
        qxpXml = mock(QxpXml.class);

        run = new Run();
        run.setId(100);
        run.setRunProperties(new RunProperties());
        DocumentDomain document = new DocumentDomain();
        document.setQxpXml(qxpXml);
        run.setGabarit(document);
        didTask = new TaskDid(TaskDid.DID_TASK_ID, run);
        run.getTasks().put(didTask.getId(), didTask);
    }

    @Test
    void missingDidInValueBranchAddsExactUnspecifiedErrorAndReturns() {
        when(qxpXml.getUID("DID")).thenReturn("");

        strategy.postProcess(didTask);

        assertEquals(1, run.getErrors().size());
        assertEquals(RunError.UNSPECIFIED, run.getErrors().get(0).getCategory());
        assertEquals("Le bloc DID est absent du document", run.getErrors().get(0).getMessage());
        verify(systemTaskProcessStrategy, never()).process(didTask);
    }

    @Test
    void whitespaceUidIsConfiguredTextAndContinuesValueProcessing() {
        when(qxpXml.getUID("DID")).thenReturn(" ");

        strategy.postProcess(didTask);

        assertEquals(0, run.getErrors().size());
        verify(systemTaskProcessStrategy).process(didTask);
    }

    @Test
    void missingDidInMoveBranchAddsExactUnspecifiedErrorAndReturns() {
        TaskSql paginationTask = new TaskSql(10, run);
        BlocBox paginationBloc = new BlocBox(paginationTask, "PAGE", "value");
        paginationBloc.setPagination(true);
        paginationTask.getBlocsModify().put(paginationBloc.getName(), paginationBloc);
        run.getTasks().put(paginationTask.getId(), paginationTask);
        when(qxpXml.getBlocInfo("DID")).thenReturn(null);

        strategy.postProcess(didTask);

        assertEquals(1, run.getErrors().size());
        assertEquals(RunError.UNSPECIFIED, run.getErrors().get(0).getCategory());
        assertEquals("Le bloc DID est absent du document", run.getErrors().get(0).getMessage());
        verify(systemTaskProcessStrategy, never()).process(didTask);
    }
}
````

### `src/test/java/com/socgen/sgs/api/quark/engine/domain/RunTest.java`

SHA-256: `b5c225e903cfa4bb6c11583196976b6205edb2ef16deee0fe8328d538d12f83c`

````java
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
        assertEquals(1, run.currentQxpsExecutionNumber());
    }

    @Test
    @DisplayName("QXPS execution numbering is owned by each run and advances explicitly")
    void qxpsExecutionNumberIsRunScoped() {
        Run anotherRun = new Run();

        run.advanceQxpsExecutionNumber();
        run.advanceQxpsExecutionNumber();

        assertEquals(3, run.currentQxpsExecutionNumber());
        assertEquals(1, anotherRun.currentQxpsExecutionNumber());
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
````

### `src/test/java/com/socgen/sgs/api/quark/engine/business/QxpsCallerBusinessWave1Test.java`

SHA-256: `c08b814206842090bded4ca1046064a38a05c32501dde4016994959c139f1aa6`

````java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.RunTask;
import com.socgen.sgs.api.quark.engine.domain.RunTaskStep;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.client.QxpsHttpClient;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.config.QxpsProperties;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.exception.QxpsException;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.LiteralMessage;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.PdfRenderMessage;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsRequestInfo;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsResponseInfo;
import com.socgen.sgs.api.quark.engine.infra.interop.qxpsm.QxpsmSoapClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpMethod;

import java.net.URI;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class QxpsCallerBusinessWave1Test {

    private QxpsHttpClient httpClient;
    private QxpsmSoapClient soapClient;
    private FilePoolPort filePool;
    private QxpsCallerBusiness business;
    private Run run;

    @BeforeEach
    void setUp() {
        httpClient = mock(QxpsHttpClient.class);
        soapClient = mock(QxpsmSoapClient.class);
        filePool = mock(FilePoolPort.class);
        QxpsProperties properties = new QxpsProperties();
        properties.getPool().setDefaultPath("D:\\Documents\\");
        business = new QxpsCallerBusiness(httpClient, soapClient, properties, filePool);

        RunProperties runProperties = new RunProperties();
        runProperties.setRunId(7);
        run = new Run();
        run.setId(7);
        run.setRunProperties(runProperties);
        DocumentDomain gabarit = new DocumentDomain();
        gabarit.setId(45);
        gabarit.setPrefix("G");
        gabarit.setName("Gabarit");
        gabarit.setFormat("QXP");
        gabarit.setFilePoolPath("R_7/G_45.QXP");
        run.setGabarit(gabarit);
    }

    @Test
    void excludedBoxesAddTheExactCritiqueErrorWithoutStoppingProcessing() {
        RunTask runTask = mock(RunTask.class);
        when(runTask.getSteps()).thenReturn(List.of());
        when(runTask.getNbExcludeBoxes()).thenReturn(2);
        when(runTask.getLastNbMaxDocBoxes()).thenReturn(16900);
        run.setRunTask(runTask);

        business.process(run);

        assertEquals(1, run.getErrors().size());
        assertEquals(RunError.CRITIQUE, run.getErrors().get(0).getCategory());
        assertEquals(
                "La taille du document (16900 boxes) ne permettait pas d'effectuer toutes les modifications, 2 Boxes ont été exclues",
                run.getErrors().get(0).getMessage());
    }

    @Test
    void pdfQxpsFailureAddsCritiqueAndContinuesWithQxpFetch() {
        QxpsRequestInfo request = new QxpsRequestInfo(
                URI.create("https://example.invalid/render?secret=value"), HttpMethod.GET, null);
        when(httpClient.execute(anyString(), any(PdfRenderMessage.class)))
                .thenThrow(new QxpsException(request, "payload"));
        QxpsResponseInfo literal = new QxpsResponseInfo();
        literal.setBinaryResponse(new byte[]{4, 5});
        when(httpClient.execute(anyString(), any(LiteralMessage.class))).thenReturn(literal);

        assertEquals(2,
                business.render(run, true, false, true, "true", "300").getQxpData().length);

        assertEquals(1, run.getErrors().size());
        assertEquals(RunError.CRITIQUE, run.getErrors().get(0).getCategory());
        assertEquals("Rendu Impossible du document pdf", run.getErrors().get(0).getMessage());
        verify(httpClient).execute(anyString(), any(LiteralMessage.class));
    }

    @Test
    void untypedPdfFailureStillPropagates() {
        when(httpClient.execute(anyString(), any(PdfRenderMessage.class)))
                .thenThrow(new IllegalStateException("internal failure"));

        assertThrows(IllegalStateException.class,
                () -> business.render(run, true, false, true, "true", "300"));

        assertEquals(0, run.getErrors().size());
        verify(httpClient, never()).execute(anyString(), any(LiteralMessage.class));
    }

    @Test
    void repeatedProcessingContinuesRunOwnedExecutionNumbers() {
        RunTaskStep step = executableSoapStep();
        RunTask runTask = mock(RunTask.class);
        when(runTask.getSteps()).thenReturn(List.of(step));
        when(runTask.getNbExcludeBoxes()).thenReturn(0);
        run.setRunTask(runTask);
        QxpsResponseInfo literal = new QxpsResponseInfo();
        literal.setBinaryResponse(new byte[]{1});
        when(httpClient.execute(anyString(), any(LiteralMessage.class))).thenReturn(literal);

        business.process(run);
        business.process(run);

        ArgumentCaptor<String> names = ArgumentCaptor.forClass(String.class);
        verify(soapClient, times(2)).executeStep(
                anyString(), anyList(), isNull(), anyString(), names.capture());
        assertEquals(List.of("G_45_1.QXP", "G_45_2.QXP"), names.getAllValues());
        assertEquals(3, run.currentQxpsExecutionNumber());
    }

    @Test
    void differentRunsDoNotShareExecutionNumbers() {
        RunTaskStep firstStep = executableSoapStep();
        RunTask firstRunTask = mock(RunTask.class);
        when(firstRunTask.getSteps()).thenReturn(List.of(firstStep));
        run.setRunTask(firstRunTask);

        Run secondRun = new Run();
        secondRun.setId(8);
        RunProperties secondProperties = new RunProperties();
        secondProperties.setRunId(8);
        secondRun.setRunProperties(secondProperties);
        DocumentDomain secondGabarit = new DocumentDomain();
        secondGabarit.setId(46);
        secondGabarit.setPrefix("H");
        secondGabarit.setName("Second");
        secondGabarit.setFormat("QXP");
        secondGabarit.setFilePoolPath("R_8/H_46.QXP");
        secondRun.setGabarit(secondGabarit);
        RunTaskStep secondStep = executableSoapStep();
        RunTask secondRunTask = mock(RunTask.class);
        when(secondRunTask.getSteps()).thenReturn(List.of(secondStep));
        secondRun.setRunTask(secondRunTask);

        QxpsResponseInfo literal = new QxpsResponseInfo();
        literal.setBinaryResponse(new byte[]{1});
        when(httpClient.execute(anyString(), any(LiteralMessage.class))).thenReturn(literal);

        business.process(run);
        business.process(secondRun);

        ArgumentCaptor<String> names = ArgumentCaptor.forClass(String.class);
        verify(soapClient, times(2)).executeStep(
                anyString(), anyList(), isNull(), anyString(), names.capture());
        assertEquals(List.of("G_45_1.QXP", "H_46_1.QXP"), names.getAllValues());
    }

    @Test
    void failedExecutionDoesNotAdvanceTheRunCounter() {
        RunTaskStep step = executableSoapStep();
        RunTask runTask = mock(RunTask.class);
        when(runTask.getSteps()).thenReturn(List.of(step));
        run.setRunTask(runTask);
        when(soapClient.executeStep(anyString(), anyList(), isNull(), anyString(), anyString()))
                .thenThrow(new RuntimeException("failure"));

        assertThrows(RuntimeException.class, () -> business.process(run));

        assertEquals(1, run.currentQxpsExecutionNumber());
        verify(httpClient, never()).execute(anyString(), any(LiteralMessage.class));
    }

    private RunTaskStep executableSoapStep() {
        RunTaskStep step = mock(RunTaskStep.class);
        when(step.getBlocsModify()).thenReturn(List.of());
        when(step.getNameValues()).thenReturn(List.of());
        when(step.isDirectCall()).thenReturn(false);
        when(step.isFullExclude()).thenReturn(false);
        return step;
    }
}
````

### `src/test/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/RunStartUpdateDaoImplTest.java`

SHA-256: `3d875e8b659af923c415db356b958f07f9e4f025914e0d934f2eb28b9508fcb4`

````java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunStatus;
import com.socgen.sgs.api.quark.engine.infra.dao.RunStartUpdateDao;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.ArgumentCaptor;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.test.util.ReflectionTestUtils;

import javax.sql.DataSource;
import java.time.LocalDateTime;
import java.sql.Timestamp;
import java.sql.Types;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("RunStartUpdateDaoImpl Tests")
class RunStartUpdateDaoImplTest {

    @Mock
    private DataSource dataSource;

    @Mock
    private SimpleJdbcCall simpleJdbcCall;

    private RunStartUpdateDao dao;
    private Run run;

    @BeforeEach
    void setUp() {
        dao = new RunStartUpdateDaoImpl(dataSource);
        ReflectionTestUtils.setField(dao, "startRunCall", simpleJdbcCall);

        run = new Run();
        run.setId(77);
        run.setStatus(RunStatus.RUNNING);
        run.setStartDate(LocalDateTime.now());
    }

    @Test
    @DisplayName("Should execute startRun procedure successfully")
    void shouldExecuteStartRunProcedure() {
        when(simpleJdbcCall.execute(any(SqlParameterSource.class))).thenReturn(Map.of());

        assertDoesNotThrow(() -> dao.startRun(run));

        verify(simpleJdbcCall, times(1)).execute(any(SqlParameterSource.class));
    }

    @Test
    @DisplayName("Should bind the exact start timestamp without dropping the time")
    void shouldBindExactStartTimestamp() {
        LocalDateTime expected = LocalDateTime.of(2026, 8, 18, 14, 37, 42);
        run.setStartDate(expected);
        when(simpleJdbcCall.execute(any(SqlParameterSource.class))).thenReturn(Map.of());
        ArgumentCaptor<SqlParameterSource> params = ArgumentCaptor.forClass(SqlParameterSource.class);

        dao.startRun(run);

        verify(simpleJdbcCall).execute(params.capture());
        assertEquals(Timestamp.valueOf(expected), params.getValue().getValue("p_date_debut"));
        assertEquals(Types.TIMESTAMP, RunStartUpdateDaoImpl.START_DATE_SQL_TYPE);
    }

    @Test
    @DisplayName("Should use current time when run startDate is null")
    void shouldUseCurrentTimeWhenStartDateNull() {
        run.setStartDate(null);
        when(simpleJdbcCall.execute(any(SqlParameterSource.class))).thenReturn(Map.of());

        assertDoesNotThrow(() -> dao.startRun(run));

        assertNotNull(run.getStartDate());
        verify(simpleJdbcCall, times(1)).execute(any(SqlParameterSource.class));
    }

    @Test
    @DisplayName("Should throw RuntimeException when procedure call fails")
    void shouldThrowRuntimeExceptionOnFailure() {
        when(simpleJdbcCall.execute(any(SqlParameterSource.class)))
                .thenThrow(new RuntimeException("db error"));

        assertThrows(RuntimeException.class, () -> dao.startRun(run));
    }

    @Test
    @DisplayName("Should include correct status code in parameters")
    void shouldIncludeStatusCodeInParams() {
        run.setStatus(RunStatus.TO_GENERATE);
        when(simpleJdbcCall.execute(any(SqlParameterSource.class))).thenReturn(Map.of());

        dao.startRun(run);

        verify(simpleJdbcCall).execute(any(SqlParameterSource.class));
    }
}
````

### `src/test/java/com/socgen/sgs/api/quark/engine/domain/helper/InvariantValueConverterTest.java`

SHA-256: `6e9bcafcc67d19c4ab57c2205491d2189ea34d6af16fa141721cad9eb7c8b073`

````java
package com.socgen.sgs.api.quark.engine.domain.helper;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class InvariantValueConverterTest {

    @Test
    void parsesInvariantNumericFormsAndAppliesCheckedInt32Conversion() {
        assertEquals(1234, InvariantValueConverter.toInt32("1,234"));
        assertEquals(1234, InvariantValueConverter.toInt32("1 234"));
        assertEquals(-123, InvariantValueConverter.toInt32("(123)"));
        assertEquals(-123, InvariantValueConverter.toInt32("123-"));
        assertEquals(-123, InvariantValueConverter.toInt32("-¤123"));
        assertEquals(-123, InvariantValueConverter.toInt32("123¤-"));
        assertEquals(-123, InvariantValueConverter.toInt32("¤(123)"));
        assertEquals(12, InvariantValueConverter.toInt32("1,,2"));
        assertEquals(1000, InvariantValueConverter.toInt32("1e3"));
        assertEquals(12, InvariantValueConverter.toInt32("12.9"));
        assertEquals(Integer.MIN_VALUE, InvariantValueConverter.toInt32("not-a-number"));
        assertThrows(ArithmeticException.class,
                () -> InvariantValueConverter.toInt32("2147483648"));
    }

    @Test
    void modelsDecimalRangeScaleAndHalfEvenRounding() {
        assertEquals(new BigDecimal("79228162514264337593543950335"),
                InvariantValueConverter.toDecimal("79228162514264337593543950335"));
        assertEquals(InvariantValueConverter.DECIMAL_UNSET,
                InvariantValueConverter.toDecimal("79228162514264337593543950336"));
        assertEquals(new BigDecimal("0.1234567890123456789012345679"),
                InvariantValueConverter.toDecimal("0.123456789012345678901234567895"));
        assertEquals(new BigDecimal("12345678901234567890123456790"),
                InvariantValueConverter.toDecimal("12345678901234567890123456789.5"));
    }

    @Test
    void parsesProvenAndCommonInvariantDateForms() {
        assertEquals(LocalDateTime.of(2025, 12, 31, 0, 0),
                InvariantValueConverter.toDateTime("12/31/2025 00:00:00"));
        assertEquals(LocalDateTime.of(2025, 1, 2, 3, 4, 5),
                InvariantValueConverter.toDateTime("1/2/2025 3:4:5"));
        assertEquals(LocalDateTime.of(2025, 12, 31, 23, 30),
                InvariantValueConverter.toDateTime("12/31/2025 11:30 PM"));
        assertEquals(LocalDateTime.of(2025, 12, 31, 0, 0),
                InvariantValueConverter.toDateTime("December 31, 2025"));
        assertEquals(LocalDateTime.of(2025, 12, 31, 14, 30),
                InvariantValueConverter.toDateTime("2025-12-31T14:30:00"));
        assertEquals(LocalDateTime.of(2025, 12, 31, 0, 0),
                InvariantValueConverter.toDateTime("12/31/25"));
        assertEquals(LocalDateTime.of(2025, 12, 31, 0, 0),
                InvariantValueConverter.toDateTime("2025/12/31"));
        assertEquals(LocalDateTime.of(2025, 12, 31, 14, 30),
                InvariantValueConverter.toDateTime("31 Dec 2025 14:30"));
    }

    @Test
    void returnsDateSentinelForEmptyDayFirstAndInvalidDates() {
        assertEquals(InvariantValueConverter.DATE_TIME_UNSET,
                InvariantValueConverter.toDateTime(""));
        assertEquals(InvariantValueConverter.DATE_TIME_UNSET,
                InvariantValueConverter.toDateTime("31/12/2025"));
        assertEquals(InvariantValueConverter.DATE_TIME_UNSET,
                InvariantValueConverter.toDateTime("02/29/2025"));
    }
}
````

### `src/test/java/com/socgen/sgs/api/quark/engine/domain/InParamTest.java`

SHA-256: `474c0f01aff42c1f3d246f471f5edc233c2377c2c96e5dc6f27800d7e9b9532a`

````java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import com.socgen.sgs.api.quark.engine.domain.helper.InvariantValueConverter;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("InParam Tests")
class InParamTest {

    @Test
    @DisplayName("Should create InParam with int type code and string value")
    void shouldCreateInParamWithIntTypeCode() {
        InParam param = new InParam("paramName", 1, "testValue");

        assertEquals("paramName", param.getName());
        assertEquals(DataTypeEnum.TEXT, param.getType());
        assertEquals("testValue", param.getStringValue());
    }

    @Test
    @DisplayName("Should create InParam with DataTypeEnum and string value")
    void shouldCreateInParamWithDataTypeEnum() {
        InParam param = new InParam("paramName", DataTypeEnum.TEXT, "testValue");

        assertEquals("paramName", param.getName());
        assertEquals(DataTypeEnum.TEXT, param.getType());
        assertEquals("testValue", param.getStringValue());
    }

    @Test
    @DisplayName("Should store numeric string as-is for INT type")
    void shouldStoreNumericStringForIntType() {
        InParam param = new InParam("intParam", DataTypeEnum.INT, "42");

        assertEquals("intParam", param.getName());
        assertEquals(DataTypeEnum.INT, param.getType());
        assertEquals("42", param.getStringValue());
        assertEquals(42, param.getValue());
    }

    @Test
    @DisplayName("Should store decimal string as-is for DECIMAL type")
    void shouldStoreDecimalString() {
        InParam param = new InParam("decimalParam", DataTypeEnum.DECIMAL, "3.14");

        assertEquals("decimalParam", param.getName());
        assertEquals(DataTypeEnum.DECIMAL, param.getType());
        assertEquals("3.14", param.getStringValue());
        assertEquals(new java.math.BigDecimal("3.14"), param.getValue());
    }

    @Test
    @DisplayName("Should store currency string as-is for CURRENCY type")
    void shouldStoreCurrencyString() {
        InParam param = new InParam("currencyParam", DataTypeEnum.CURRENCY, "99.99");

        assertEquals("currencyParam", param.getName());
        assertEquals(DataTypeEnum.CURRENCY, param.getType());
        assertEquals("99.99", param.getStringValue());
        assertEquals("99.99", param.getValue());
    }

    @Test
    @DisplayName("Should store pourcentage string as-is for POURCENTAGE type")
    void shouldStorePourcentageString() {
        InParam param = new InParam("pourcentageParam", DataTypeEnum.POURCENTAGE, "25.5");

        assertEquals("pourcentageParam", param.getName());
        assertEquals(DataTypeEnum.POURCENTAGE, param.getType());
        assertEquals("25.5", param.getStringValue());
        assertEquals("25.5", param.getValue());
    }

    @Test
    @DisplayName("Should store non-numeric string for INT type without error")
    void shouldStoreNonNumericStringForIntType() {
        InParam param = new InParam("invalidIntParam", DataTypeEnum.INT, "notANumber");

        assertEquals("invalidIntParam", param.getName());
        assertEquals(DataTypeEnum.INT, param.getType());
        assertEquals("notANumber", param.getStringValue());
        assertEquals(Integer.MIN_VALUE, param.getValue());
    }

    @Test
    @DisplayName("Should handle null string value")
    void shouldHandleNullStringValue() {
        InParam param = new InParam("nullParam", DataTypeEnum.TEXT, null);

        assertEquals("nullParam", param.getName());
        assertEquals(DataTypeEnum.TEXT, param.getType());
        assertNull(param.getStringValue());
    }

    @Test
    @DisplayName("Should handle empty string value")
    void shouldHandleEmptyStringValue() {
        InParam param = new InParam("emptyParam", DataTypeEnum.TEXT, "");

        assertEquals("emptyParam", param.getName());
        assertEquals(DataTypeEnum.TEXT, param.getType());
        assertEquals("", param.getStringValue());
    }

    @Test
    @DisplayName("Should keep string value as-is for TEXT type")
    void shouldKeepStringValueAsIsForTextType() {
        InParam param = new InParam("textParam", DataTypeEnum.TEXT, "some text 123");

        assertEquals("textParam", param.getName());
        assertEquals(DataTypeEnum.TEXT, param.getType());
        assertEquals("some text 123", param.getStringValue());
    }

    @Test
    @DisplayName("Should retain DATE text and convert its typed value during loading")
    void shouldKeepDateStringAsIsForDateType() {
        InParam param = new InParam("dateParam", DataTypeEnum.DATE, "2024-01-15");

        assertEquals("dateParam", param.getName());
        assertEquals(DataTypeEnum.DATE, param.getType());
        assertEquals("2024-01-15", param.getStringValue());
        assertEquals(java.time.LocalDateTime.of(2024, 1, 15, 0, 0), param.getValue());
    }

    @Test
    @DisplayName("Should keep datetime string as-is for DATE_TIME type - Oracle handles conversion")
    void shouldKeepDateTimeStringAsIsForDateTimeType() {
        InParam param = new InParam("dtParam", DataTypeEnum.DATE_TIME, "2024-01-15T10:30:00");

        assertEquals("dtParam", param.getName());
        assertEquals(DataTypeEnum.DATE_TIME, param.getType());
        assertEquals("2024-01-15T10:30:00", param.getStringValue());
    }

    @Test
    @DisplayName("Should keep dd/MM/yyyy format as-is for DATE type")
    void shouldKeepSlashDateFormatAsIs() {
        InParam param = new InParam("dateParam", DataTypeEnum.DATE, "15/01/2024");

        assertEquals(DataTypeEnum.DATE, param.getType());
        assertEquals("15/01/2024", param.getStringValue());
    }

    @Test
    @DisplayName("Should keep any date string as-is even if unparseable")
    void shouldKeepUnparseableDateAsIs() {
        InParam param = new InParam("dateParam", DataTypeEnum.DATE, "not-a-date");

        assertEquals("not-a-date", param.getStringValue());
        assertEquals(InvariantValueConverter.DATE_TIME_UNSET, param.getValue());
    }

    @Test
    @DisplayName("Parsed integer overflow fails while the parameter row is loaded")
    void shouldFailOnParsedInt32Overflow() {
        assertThrows(ArithmeticException.class,
                () -> new InParam("intParam", DataTypeEnum.INT, "2147483648"));
    }

    @Test
    @DisplayName("Should be immutable")
    void shouldBeImmutable() {
        InParam param = new InParam("param", DataTypeEnum.TEXT, "value");

        assertEquals("param", param.getName());
        assertEquals("value", param.getStringValue());
    }
}
````

### `src/test/java/com/socgen/sgs/api/quark/engine/mapper/InParamSqlMapperTest.java`

SHA-256: `8bd8b435f57cec5d7095a55f5b28f34ac6e309d8b590400a7179f069e9a62d8b`

````java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.SqlParameterValue;

import oracle.sql.DATE;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

@DisplayName("InParamSqlMapper typed-binding Tests")
class InParamSqlMapperTest {

    private final InParamSqlMapper mapper = new InParamSqlMapper();

    private Object map(DataTypeEnum type, String value) {
        Map<String, InParam> in = new LinkedHashMap<>();
        in.put("p", new InParam("p", type, value));
        return mapper.toParameterMap(in).get("p");
    }

    /** Assert the mapped value is a typed SQL NULL of the expected java.sql.Types code. */
    private void assertTypedNull(int expectedSqlType, Object actual) {
        SqlParameterValue v = assertInstanceOf(SqlParameterValue.class, actual);
        assertEquals(expectedSqlType, v.getSqlType());
        assertNull(v.getValue());
    }

    @Test
    @DisplayName("#51 INT binds a typed Integer (truncating toward zero); unset/unparseable → typed SQL NULL")
    void intTyped() {
        assertEquals(123, map(DataTypeEnum.INT, "123"));
        assertEquals(12, map(DataTypeEnum.INT, "12.9"));      // (int)decimal truncates
        assertEquals(1234, map(DataTypeEnum.INT, "1,234"));
        assertEquals(-123, map(DataTypeEnum.INT, "(123)"));
        assertTypedNull(Types.NUMERIC, map(DataTypeEnum.INT, ""));
        assertTypedNull(Types.NUMERIC, map(DataTypeEnum.INT, "abc"));
        assertTypedNull(Types.NUMERIC, map(DataTypeEnum.INT, "-2147483648"));
        assertThrows(ArithmeticException.class,
                () -> map(DataTypeEnum.INT, "2147483648"));
    }

    @Test
    @DisplayName("#51 DECIMAL binds a typed BigDecimal; unset/unparseable → typed SQL NULL")
    void decimalTyped() {
        assertEquals(new BigDecimal("12.50"), map(DataTypeEnum.DECIMAL, "12.50"));
        assertEquals(new BigDecimal("1000"), map(DataTypeEnum.DECIMAL, "1e3"));
        assertTypedNull(Types.NUMERIC, map(DataTypeEnum.DECIMAL, ""));
        assertTypedNull(Types.NUMERIC, map(DataTypeEnum.DECIMAL, "n/a"));
        assertTypedNull(Types.NUMERIC,
                map(DataTypeEnum.DECIMAL, "-79228162514264337593543950335"));
        assertTypedNull(Types.NUMERIC,
                map(DataTypeEnum.DECIMAL, "79228162514264337593543950336"));
    }

    @Test
    @DisplayName("#50 DATE binds a time-preserving oracle.sql.DATE; unparseable → typed SQL NULL")
    void dateTimePreserving() throws Exception {
        Object result = map(DataTypeEnum.DATE, "12/29/2023 14:30:00");
        DATE oracleDate = assertInstanceOf(DATE.class, result);
        Timestamp expected = Timestamp.valueOf(LocalDateTime.of(2023, 12, 29, 14, 30, 0));
        assertEquals(expected, oracleDate.timestampValue());
        assertTypedNull(Types.DATE, map(DataTypeEnum.DATE, ""));
        assertTypedNull(Types.DATE, map(DataTypeEnum.DATE, "31/12/2025"));
    }

    @Test
    @DisplayName("#21 DATE_TIME (and TEXT) bind the RAW STRING (matches .NET switch default)")
    void dateTimeAndTextRawString() {
        assertEquals("12/29/2023 14:30:00", map(DataTypeEnum.DATE_TIME, "12/29/2023 14:30:00"));
        assertEquals("hello", map(DataTypeEnum.TEXT, "hello"));
    }

    @Test
    @DisplayName("All four report parameters are retained and typed independently")
    void mapsAllFourReportParametersTogether() throws Exception {
        Map<String, InParam> input = new LinkedHashMap<>();
        input.put("p_code_port", new InParam("p_code_port", DataTypeEnum.TEXT, "101005"));
        input.put("p_date_echeance",
                new InParam("p_date_echeance", DataTypeEnum.DATE, "12/30/2022 00:00:00"));
        input.put("p_id_gabarit", new InParam("p_id_gabarit", DataTypeEnum.INT, "329"));
        input.put("p_id_unit_code", new InParam("p_id_unit_code", DataTypeEnum.TEXT, "_A"));

        Map<String, Object> result = mapper.toParameterMap(input);

        assertEquals(java.util.List.of(
                        "p_code_port", "p_date_echeance", "p_id_gabarit", "p_id_unit_code"),
                new java.util.ArrayList<>(result.keySet()));
        assertEquals("101005", result.get("p_code_port"));
        DATE oracleDate = assertInstanceOf(DATE.class, result.get("p_date_echeance"));
        assertEquals(Timestamp.valueOf("2022-12-30 00:00:00"), oracleDate.timestampValue());
        assertEquals(329, result.get("p_id_gabarit"));
        assertEquals("_A", result.get("p_id_unit_code"));
    }
}
````

### `src/test/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/GetInParamsDaoImplTest.java`

SHA-256: `d0935689642b694f6b89b8fa0510814f9560d5cd5d1f2a40d68919e7120b7ed3`

````java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.infra.dao.GetInParamsDao;
import com.socgen.sgs.api.quark.engine.mapper.InParamMapper;
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
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("GetInParamsDaoImpl Tests")
class GetInParamsDaoImplTest {

    @Mock
    private DataSource dataSource;

    @Mock
    private InParamMapper inParamMapper;

    @Mock
    private SimpleJdbcCall simpleJdbcCall;

    private GetInParamsDao dao;
    private Run run;

    @BeforeEach
    void setUp() {
        dao = new GetInParamsDaoImpl(dataSource, inParamMapper);
        ReflectionTestUtils.setField(dao, "getInParamsCall", simpleJdbcCall);

        RunProperties props = new RunProperties();
        props.setIdSuivi(55);
        run = new Run();
        run.setId(1);
        run.setRunProperties(props);
    }

    @Test
    @DisplayName("Should populate run inParams from cursor results")
    void shouldPopulateInParams() {
        InParam param1 = new InParam("P1", 1, "val1");
        InParam param2 = new InParam("P2", 2, "100");

        Map<String, Object> result = new HashMap<>();
        result.put("result_cursor", List.of(param1, param2));
        when(simpleJdbcCall.execute(any(SqlParameterSource.class))).thenReturn(result);

        dao.getInParams(run);

        assertEquals(2, run.getInParams().size());
        assertSame(param1, run.getInParams().get("P1"));
        assertSame(param2, run.getInParams().get("P2"));
    }

    @Test
    @DisplayName("Should clear existing inParams before loading")
    void shouldClearExistingInParams() {
        run.getInParams().put("OLD", new InParam("OLD", 1, "old"));

        Map<String, Object> result = new HashMap<>();
        result.put("result_cursor", List.of(new InParam("NEW", 1, "new")));
        when(simpleJdbcCall.execute(any(SqlParameterSource.class))).thenReturn(result);

        dao.getInParams(run);

        assertFalse(run.getInParams().containsKey("OLD"));
        assertTrue(run.getInParams().containsKey("NEW"));
    }

    @Test
    @DisplayName("Should leave inParams empty when cursor returns null")
    void shouldLeaveEmptyWhenCursorNull() {
        Map<String, Object> result = new HashMap<>();
        result.put("result_cursor", null);
        when(simpleJdbcCall.execute(any(SqlParameterSource.class))).thenReturn(result);

        dao.getInParams(run);

        assertTrue(run.getInParams().isEmpty());
    }

    @Test
    @DisplayName("Should leave inParams empty when cursor returns empty list")
    void shouldLeaveEmptyWhenCursorEmpty() {
        Map<String, Object> result = new HashMap<>();
        result.put("result_cursor", List.of());
        when(simpleJdbcCall.execute(any(SqlParameterSource.class))).thenReturn(result);

        dao.getInParams(run);

        assertTrue(run.getInParams().isEmpty());
    }

    @Test
    @DisplayName("Duplicate parameter name fails without replacing the first cursor row")
    void duplicateParameterNameFails() {
        InParam before = new InParam("BEFORE", 1, "before");
        InParam first = new InParam("P", 1, "first");
        InParam second = new InParam("P", 1, "second");
        InParam after = new InParam("AFTER", 1, "after");
        Map<String, Object> result = new HashMap<>();
        result.put("result_cursor", List.of(before, first, second, after));
        when(simpleJdbcCall.execute(any(SqlParameterSource.class))).thenReturn(result);

        RuntimeException failure = assertThrows(RuntimeException.class, () -> dao.getInParams(run));

        assertSame(first, run.getInParams().get("P"));
        assertFalse(run.getInParams().containsKey("AFTER"));
        assertInstanceOf(IllegalStateException.class, failure.getCause());
    }

    @Test
    @DisplayName("Duplicate empty parameter name fails without replacing the first cursor row")
    void duplicateEmptyParameterNameFails() {
        InParam first = new InParam("", 1, "first");
        InParam second = new InParam("", 1, "second");
        Map<String, Object> result = new HashMap<>();
        result.put("result_cursor", List.of(first, second));
        when(simpleJdbcCall.execute(any(SqlParameterSource.class))).thenReturn(result);

        RuntimeException failure = assertThrows(RuntimeException.class, () -> dao.getInParams(run));

        assertSame(first, run.getInParams().get(""));
        assertInstanceOf(IllegalStateException.class, failure.getCause());
    }

    @Test
    @DisplayName("Should throw RuntimeException when DAO call fails")
    void shouldThrowRuntimeExceptionOnFailure() {
        when(simpleJdbcCall.execute(any(SqlParameterSource.class)))
                .thenThrow(new RuntimeException("db error"));

        assertThrows(RuntimeException.class, () -> dao.getInParams(run));
    }
}
````

### `src/test/java/com/socgen/sgs/api/quark/engine/domain/collection/AddOnlyLinkedHashMapTest.java`

SHA-256: `9f5b0cdefa3ce8e6fb06b31abe53f79250d5b7c4d34059ec1a3f73706da24249`

````java
package com.socgen.sgs.api.quark.engine.domain.collection;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.modifier.ModifierBox;
import com.socgen.sgs.api.quark.engine.domain.modifier.ModifierGroup;
import com.socgen.sgs.api.quark.engine.domain.modifier.ModifierSpread;
import com.socgen.sgs.api.quark.engine.domain.modifier.QxpsModifier;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class AddOnlyLinkedHashMapTest {

    @Test
    void acceptsUniqueEmptyAndWhitespaceKeysInInsertionOrder() {
        Map<String, Integer> values = new AddOnlyLinkedHashMap<>();
        values.put("", 1);
        values.put(" ", 2);
        values.put("A", 3);

        assertEquals(java.util.List.of("", " ", "A"),
                new java.util.ArrayList<>(values.keySet()));
    }

    @Test
    void rejectsNullAndDuplicateKeysWithoutReplacingTheFirstValue() {
        Map<String, Integer> values = new AddOnlyLinkedHashMap<>();
        values.put("A", 1);

        assertThrows(IllegalArgumentException.class, () -> values.put(null, 2));
        assertThrows(IllegalStateException.class, () -> values.put("A", 2));
        assertEquals(1, values.get("A"));
    }

    @Test
    void clearAllowsAKeyToBeAddedInANewProcessingPass() {
        Map<String, Integer> values = new AddOnlyLinkedHashMap<>();
        values.put("A", 1);
        values.clear();
        values.put("A", 2);

        assertEquals(2, values.get("A"));
    }

    @Test
    void taskAndModifierOwnedCollectionsUseAddOnlySemantics() {
        TaskSql task = new TaskSql(10, new Run());
        BlocBox first = new BlocBox(task, "B", "first");
        BlocBox second = new BlocBox(task, "B", "second");
        task.getBlocsUpdate().put("B", first);
        ModifierSpread spread = new ModifierSpread();
        spread.getBoxes().put("B", new ModifierBox());
        spread.getBoxesExtra().put("B", new ModifierBox());
        spread.getGroups().put("G", new ModifierGroup());

        assertThrows(IllegalStateException.class,
                () -> task.getBlocsUpdate().put("B", second));
        assertThrows(IllegalStateException.class,
                () -> spread.getBoxes().put("B", new ModifierBox()));
        assertThrows(IllegalStateException.class,
                () -> spread.getBoxesExtra().put("B", new ModifierBox()));
        assertThrows(IllegalStateException.class,
                () -> spread.getGroups().put("G", new ModifierGroup()));
        assertThrows(NullPointerException.class, () -> new QxpsModifier().add(null));
    }
}
````

### `src/test/java/com/socgen/sgs/api/quark/engine/domain/exception/EngineExceptionTest.java`

SHA-256: `73c04d6abe42b4f868acaf5ffce24a540994f38ad63003fd74643ca231800d05`

````java
package com.socgen.sgs.api.quark.engine.domain.exception;

import com.socgen.sgs.api.quark.engine.domain.RunError;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;

class EngineExceptionTest {

    @Test
    void preservesSeverityAndControlledOuterToInnerMessages() {
        EngineException inner = new EngineException(RunError.UNSPECIFIED, "safe inner");
        EngineException outer = new EngineException(RunError.CRITIQUE, "safe outer", inner);

        assertEquals(RunError.CRITIQUE, outer.getCategory());
        assertEquals(System.lineSeparator()
                        + "==> safe outer" + System.lineSeparator()
                        + "==> safe inner" + System.lineSeparator(),
                outer.getSafeMessageChain());
    }

    @Test
    void excludesRawMessageFromUntypedCause() {
        EngineException failure = new EngineException(
                RunError.BLOQUANTE,
                "safe database context",
                new RuntimeException("select secret_value from hidden_table"));

        assertFalse(failure.getSafeMessageChain().contains("secret_value"));
        assertEquals(System.lineSeparator()
                        + "==> safe database context" + System.lineSeparator(),
                failure.getSafeMessageChain());
    }

    @Test
    void rejectsUnsupportedSeverityAndMissingSafeMessage() {
        assertThrows(IllegalArgumentException.class,
                () -> new EngineException(0, "message"));
        assertThrows(IllegalArgumentException.class,
                () -> new EngineException(RunError.CRITIQUE, ""));
    }
}
````

