# EOS Quark Core Parity — Wave 2 Copy Packet

Date frozen: 2026-08-19

This packet contains the complete final content of every production and focused/regression test file changed for
approved Wave 2, plus a redacted configuration reference. Copy each Java fenced block to the repository-relative path shown above it. After copying,
normalize the copied file to LF line endings, calculate SHA-256, and compare it with the value printed here. An exact
checksum proves its normalized content matches the reviewed block; the `sha256-...` text is metadata and must not be
pasted into Java. Example: `tr -d '\\r' < path/to/File.java | shasum -a 256`.

Wave 2 scope is limited to root-tree execution context/file-pool isolation, lazy structural XML/project lifecycle,
working-document refresh, exact DOC EOS/QXP Previous target evaluation, controlled dynamic-anchor failure, root-tree
document caches and compartment child context/final-QXP snapshot behavior. The existing Java 200 MiB fail-soft limit
remains intentional and YAML-owned. REST, RabbitMQ, duplicate admission, capacity and replica topology are not changed.

Verification freeze: 485 production source files compiled; 385 tests passed; 0 failures; 0 errors.

The Java blocks below are authoritative whole-file replacements; create a path if it is absent. The YAML block is a
reference only: retain environment-specific connection values and apply only the documented `engine.gabarit` lines.


## 1. `src/main/java/com/socgen/sgs/api/quark/engine/business/DocumentStructureBusiness.java`

SHA-256: `sha256-ebcd976608dc5f18751c2c716448d3d506db6b3f47adbb67d8942f332be1aed5`

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/** Sole cache/fetch/fail-soft owner for QXP XML and typed project structures. */
@Component
@RequiredArgsConstructor
@Slf4j
public class DocumentStructureBusiness {

    private final FilePoolPort filePool;
    private final GetGabaritXmlBusiness getGabaritXmlBusiness;
    private final GetDocumentProjectBusiness getDocumentProjectBusiness;

    public QxpXml ensureXml(Run run, DocumentDomain document) {
        if (document.hasQxpXml()) {
            return document.getQxpXml();
        }

        try {
            filePool.addFile(run.requireExecutionContext(), document.getFilePoolPath(), document.getData());
            String content = getGabaritXmlBusiness.fetchXml(document.getFilePoolPath());
            QxpXml parsed = QxpXml.createFromXml(content);
            if (parsed == null) {
                throw new IllegalStateException("QXP XML response is empty or invalid");
            }
            document.setQxpXml(parsed);
            log.debug("QXP XML loaded for run [{}], documentId [{}]", run.getId(), document.getId());
        } catch (Exception failure) {
            document.setQxpXml(QxpXml.empty());
            markDegraded(run, document);
            log.warn("QXP XML unavailable; cached empty structure for run [{}], documentId [{}], failureType [{}]",
                    run.getId(), document.getId(), failure.getClass().getSimpleName());
        }
        return document.getQxpXml();
    }

    public QxpProject ensureProject(Run run, DocumentDomain document) {
        if (document.hasQxpProject()) {
            return document.getQxpProject();
        }

        try {
            filePool.addFile(run.requireExecutionContext(), document.getFilePoolPath(), document.getData());
            QxpProject project = getDocumentProjectBusiness.getProject(document.getFilePoolPath());
            if (project == null) {
                throw new IllegalStateException("QXP project response is empty");
            }
            document.setQxpProject(project);
            log.debug("QXP project loaded for run [{}], documentId [{}]", run.getId(), document.getId());
        } catch (Exception failure) {
            document.setQxpProject(QxpProject.empty());
            markDegraded(run, document);
            log.warn("QXP project unavailable; cached empty structure for run [{}], documentId [{}], failureType [{}]",
                    run.getId(), document.getId(), failure.getClass().getSimpleName());
        }
        return document.getQxpProject();
    }

    private static void markDegraded(Run run, DocumentDomain document) {
        document.setModeDegrade(true);
        if (document == run.getGabarit() || document == run.getGabaritTemplate()) {
            run.getRunProperties().setModeDegrade(true);
        }
    }
}
```


## 2. `src/main/java/com/socgen/sgs/api/quark/engine/domain/RunExecutionContext.java`

SHA-256: `sha256-165a574ddadd141422b014b75da09f8ca95f8f60ad296010a4f3d96b97661f76`

```java
package com.socgen.sgs.api.quark.engine.domain;

import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.function.Supplier;

/**
 * State owned by one root run and every compartment child executed below it.
 *
 * <p>The accepted .NET engine naturally obtained this lifetime by running one root tree in one
 * process. Java is long-lived, so the workspace, upload registry and document caches must be
 * explicit and must never live on singleton Spring services.
 */
public final class RunExecutionContext {

    private final int rootRunId;
    private final ConcurrentMap<String, CompletableFuture<Void>> poolFiles = new ConcurrentHashMap<>();
    private final ConcurrentMap<String, Optional<DocumentDomain>> referenceDocuments = new ConcurrentHashMap<>();
    private final ConcurrentMap<String, Optional<DocumentDomain>> previousDocuments = new ConcurrentHashMap<>();

    public RunExecutionContext(int rootRunId) {
        this.rootRunId = rootRunId;
    }

    public int getRootRunId() {
        return rootRunId;
    }

    public String getPoolPath(String fileName) {
        if (fileName == null) {
            return null;
        }
        return String.format("R_%d/%s", rootRunId, fileName);
    }

    public String getPoolPathAbsolute(String fileName, String documentPoolBasePath) {
        if (fileName == null || documentPoolBasePath == null) {
            return fileName;
        }
        String base = documentPoolBasePath.replaceAll("[/\\\\]+$", "");
        return (base + "/R_" + rootRunId + "/" + fileName).replace("/", "\\");
    }

    /** Execute one physical upload per path; followers wait for the leader to finish. */
    public void upload(String path, Runnable upload) {
        CompletableFuture<Void> leader = new CompletableFuture<>();
        CompletableFuture<Void> existing = poolFiles.putIfAbsent(path, leader);
        if (existing != null) {
            join(existing);
            return;
        }

        try {
            upload.run();
            leader.complete(null);
        } catch (RuntimeException | Error failure) {
            leader.completeExceptionally(failure);
            poolFiles.remove(path, leader);
            throw failure;
        }
    }

    /** Mark a file produced by SaveAs/ChangeDocument as present in this tree's workspace. */
    public void inform(String path) {
        poolFiles.compute(path, (ignored, current) -> {
            if (current != null) {
                current.complete(null);
                return current;
            }
            return CompletableFuture.completedFuture(null);
        });
    }

    public DocumentDomain getOrLoadReferenceDocument(String key, Supplier<DocumentDomain> loader) {
        return referenceDocuments.computeIfAbsent(key, ignored -> Optional.ofNullable(loader.get())).orElse(null);
    }

    public DocumentDomain getOrLoadPreviousDocument(String key, Supplier<DocumentDomain> loader) {
        return previousDocuments.computeIfAbsent(key, ignored -> Optional.ofNullable(loader.get())).orElse(null);
    }

    private static void join(CompletableFuture<Void> future) {
        try {
            future.join();
        } catch (CompletionException failure) {
            Throwable cause = failure.getCause();
            if (cause instanceof RuntimeException) {
                throw (RuntimeException) cause;
            }
            if (cause instanceof Error) {
                throw (Error) cause;
            }
            throw failure;
        }
    }
}
```


## 3. `src/main/java/com/socgen/sgs/api/quark/engine/domain/port/FilePoolPort.java`

SHA-256: `sha256-7b2d8215f7126467bf8628b2b9fcde776e6ea5578b7d986afdf39d28dca952a7`

```java
package com.socgen.sgs.api.quark.engine.domain.port;

import com.socgen.sgs.api.quark.engine.domain.RunExecutionContext;

/** Port for uploading files to the QuarkXPress Server document pool. */
public interface FilePoolPort {
    void addFile(RunExecutionContext context, String documentName, byte[] data);

    /**
     * Registers a pool file as already present without uploading it.
     * Cross-reference: .NET QXPS_File_Manager.Addfile_Inform(poolName).
     */
    void inform(RunExecutionContext context, String documentName);
}
```


## 4. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/pool/FilePoolService.java`

SHA-256: `sha256-1088275a2ad3b7c04af04c37fd5fbd037b798c35abb3a645273d541795f731cc`

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.pool;

import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.RunExecutionContext;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.helper.QxpsHelper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class FilePoolService implements FilePoolPort {

    private final QxpsHelper qxpsHelper;
    @Override
    public void addFile(RunExecutionContext context, String documentName, byte[] data) {
        context.upload(documentName, () -> qxpsHelper.addFile(documentName, data));
        log.info("File available in root workspace [{}]: {}",
                context.getRootRunId(), documentName);
    }

    /**
     * Registers a pool file as already known WITHOUT uploading it.
     * Used after a SaveAs/Change_Document so a later addFile() for the same name is skipped.
     *
     * Cross-reference: .NET QXPS_File_Manager.Addfile_Inform(poolName).
     */
    @Override
    public void inform(RunExecutionContext context, String documentName) {
        context.inform(documentName);
    }
}

```


## 5. `src/main/java/com/socgen/sgs/api/quark/engine/domain/Run.java`

SHA-256: `sha256-134753f22effeaf814d1e2d0987ac346abe10cddcc6cc9cab6522dec9235d90e`

```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;
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

    /** Root-tree workspace and caches; child runs inherit the same instance. */
    private RunExecutionContext executionContext;

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

    public String getDebugInfo() {
        int suivi = runProperties != null ? runProperties.getIdSuivi() : 0;
        return String.format("(R_%d/S_%d)", id, suivi);
    }

    public int currentQxpsExecutionNumber() {
        return qxpsExecutionCount;
    }

    /** Advance only after QXPS execution and the working-document switch both succeed. */
    public void advanceQxpsExecutionNumber() {
        qxpsExecutionCount++;
    }

    public String getPoolPath(String fileName) {
        return requireExecutionContext().getPoolPath(fileName);
    }

    public String getPoolPathAbsolute(String fileName, String documentPoolBasePath) {
        return requireExecutionContext().getPoolPathAbsolute(fileName, documentPoolBasePath);
    }

    public RunExecutionContext requireExecutionContext() {
        if (executionContext == null) {
            if (id == null) {
                throw new IllegalStateException("Run ID is required before creating its execution context");
            }
            executionContext = new RunExecutionContext(id);
        }
        return executionContext;
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
     * @param documentStructureBusiness cache-aware owner of lazy XML/project access
     * @param filePoolPort          port for uploading the file to the QXPS document pool
     * @param documentIdentityPort  port for fetching XML and parsing document identity
     */
    public void prepareGabarit(GetGabaritBusiness getGabaritBusiness,
                               DocumentStructureBusiness documentStructureBusiness,
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
        // GetGabaritBusiness still resolves the initial data object; the execution context is the
        // final authority for its root-tree paths, including child runs.
        this.gabarit.setFilePoolPath(getPoolPath(this.gabarit.getFileName()));
        filePoolPort.addFile(requireExecutionContext(), this.gabarit.getFilePoolPath(), this.gabarit.getData());

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
        // without this the gabarit XML stays unresolved until Check, breaking anchor/page/box
        // evaluation in Dynamique and Compartiment-incorporate tasks. (Finding #25.)
        QxpXml parsedXml = documentStructureBusiness.ensureXml(this, this.gabarit);
        if (this.runProperties.isModeDegrade()) {
            log.warn("Unable to load structural XML; continuing run [{}] in Mode_Degrade", this.id);
            return;
        }
        log.info("Gabarit structure loaded for run [{}]: {} boxes across {} pages",
                this.id,
                parsedXml.getProjectInfo().getNbBox(),
                parsedXml.getProjectInfo().getNbPage());

        // Step 4: Read DID from the already-cached full XML and parse document identity. Parity: .NET
        // Evaluate_Document_Identity (Document.cs:205); no second DID-only request is required.
        String didValue = parsedXml.getValue("DID");
        DocumentIdentity identity = documentIdentityPort.parseDocumentIdentity(didValue);

        // Step 5: Set the document identity on the gabarit domain object
        this.gabarit.setDocumentIdentity(identity);
        log.info("Gabarit identity evaluation completed for run [{}]", this.id);
    }
}
```


## 6. `src/main/java/com/socgen/sgs/api/quark/engine/service/ProcessRunService.java`

SHA-256: `sha256-10d76e906cb8c68e634490a06c420b5ef683ed444416c0ba16191b7ab76571dd`

```java
package com.socgen.sgs.api.quark.engine.service;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.RunExecutionContext;
import com.socgen.sgs.api.quark.engine.dto.RunIdDto;

import java.util.List;

public interface ProcessRunService {
    List<Integer> fetchActiveRunIds();

    /**
     * Process a run and return the executed {@link Run} (with its result), so a parent
     * compartiment run can read each child's generated output. Callers that don't need the
     * result (RabbitMQ listener, REST controller) may ignore the return value.
     */
    Run runProcessor(RunIdDto runIdDto);

    /** Execute an internal compartment child inside its parent's root workspace. */
    Run runChildProcessor(RunIdDto runIdDto, RunExecutionContext executionContext);

    RunProperties getRunProperties(RunIdDto runIdDto);
}
```


## 7. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java`

SHA-256: `sha256-3fb91ca5f954a5bbc0b6116591c809aabf8953bda78e6d911bb4a390b382513f`

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
    private final DocumentStructureBusiness documentStructureBusiness;
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
        return runProcessor(runIdDto, new RunExecutionContext(runIdDto.getRunId()));
    }

    @Override
    public Run runChildProcessor(RunIdDto runIdDto, RunExecutionContext executionContext) {
        return runProcessor(runIdDto, executionContext);
    }

    private Run runProcessor(RunIdDto runIdDto, RunExecutionContext executionContext) {
        log.info("Processing run with runId: {}", runIdDto.getRunId());
        Run run = new Run(sizeLimitBeforeFailSoft);
        run.setNbBoxMax(nbBoxMax);
        run.setAverageBoxSize(averageBoxSize);
        run.setId(runIdDto.getRunId());
        run.setExecutionContext(executionContext);
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
        // Retained for compatibility with remaining RunProperties callers during this wave; it is
        // the workspace ID, not the child's Oracle identity.
        runProperties.setRunId(run.requireExecutionContext().getRootRunId());
        run.setRunProperties(runProperties);

        // Step 2: Delegate gabarit preparation entirely to run domain.
        // prepareGabarit uploads the gabarit to the pool (unconditionally), sets Mode_Degrade if the
        // template is oversized, and — when not degraded — loads the full gabarit XML + the DID.
        run.prepareGabarit(getGabaritBusiness, documentStructureBusiness, filePoolPort, documentIdentityPort);

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


## 8. `src/main/java/com/socgen/sgs/api/quark/engine/domain/DocumentDomain.java`

SHA-256: `sha256-f657a11a9f48de59c39dac047a4007f068fb98d01ea26af2df4c6363ebcf7182`

```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.AccessLevel;

/**
 * Domain entity representing a Document.
 * Encapsulates document metadata and content.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DocumentDomain {

    // File prefix constants
    public static final String FILE_DOCUMENT_PREFIX = "D";
    public static final String FILE_GABARIT_PREFIX = "G";
    public static final String FILE_DOCUMENT_GABARIT_PREFIX = "DG";
    public static final String FILE_DOCUMENT_CERTIFIE_GABARIT_PREFIX = "DCG";
    public static final String FILE_DOCUMENT_FINAL_PREFIX = "DF";
    public static final String FILE_GABARIT_TEMPLATE_PREFIX = "GT";

    // File naming patterns
    private static final String FILE_NAME_PREFIX_PATTERN = "%s_%d.%s";

    // Document properties
    private Integer id;
    private byte[] data;
    private String name;
    private String format;
    private String prefix;
    private Integer idLangue;
    private String fileName;
    private String filePoolPath;
    private String fileFullPath;
    private boolean gabarit;
    @Builder.Default
    private boolean modeDegrade = false;
    private DocumentIdentity documentIdentity;

    // ========================================================================
    // XML and Project structure (lazy-loaded)
    // Cross-reference: .NET Document._xml, Document._project, Document._pdfs
    // ========================================================================

    /** Parsed XML structure of this QXP document (lazy-loaded). */
    @Getter(AccessLevel.NONE)
    @Setter(AccessLevel.NONE)
    private QxpXml qxpXml;

    /** Parsed project structure for element analysis (lazy-loaded). */
    @Getter(AccessLevel.NONE)
    @Setter(AccessLevel.NONE)
    private QxpProject qxpProject;

    /** List of PDF page file paths (for multi-page PDF documents). */
    @Builder.Default
    private List<String> pdfFiles = new ArrayList<>();

    /**
     * Constructor for creating a document with full details.
     *
     * @param id the document ID
     * @param name the document name
     * @param format the document format (e.g., QXP, PDF)
     * @param prefix the file prefix
     * @param data the document content
     */
    public DocumentDomain(Integer id, String name, String format, String prefix, byte[] data) {
        this.id = id;
        this.name = name;
        this.format = format;
        this.prefix = prefix;
        this.data = data;
        this.idLangue = 1;  // Default language ID
        this.gabarit = false;
        // @Builder.Default moves the field initializer out of the field declaration, so it is no
        // longer applied by hand-written constructors. Initialize explicitly here to keep the
        // "pdfFiles is never null" contract on this construction path. Finding #2.
        this.pdfFiles = new ArrayList<>();
        generateFileNames();
    }

    // ========================================================================
    // XML access (lazy-loaded from QXPS server)
    // Cross-reference: .NET Document.XML property
    // ========================================================================

    /**
     * Get the parsed XML structure of this document.
     * In the .NET code, this is lazy-loaded via QXPS_File_Manager.Get_XML(this).
     * In Java, the XML content must be set externally (via setQxpXml or initXmlFromContent).
     *
     * @return the cached QxpXml instance, or null when unresolved
     */
    public QxpXml getQxpXml() {
        return this.qxpXml;
    }

    public boolean hasQxpXml() {
        return this.qxpXml != null;
    }

    /**
     * Set the parsed XML structure.
     *
     * @param qxpXml the QxpXml instance
     */
    public void setQxpXml(QxpXml qxpXml) {
        this.qxpXml = qxpXml;
    }

    /**
     * Initialize QxpXml from a raw XML string.
     * Convenience method to create and set the QxpXml in one call.
     *
     * @param xmlContent the raw XML content from QXPS server
     */
    public void initXmlFromContent(String xmlContent) {
        this.qxpXml = QxpXml.createFromXml(xmlContent);
    }

    // ========================================================================
    // Project access (lazy-loaded from QXPS server)
    // Cross-reference: .NET Document.QXPProject property
    // ========================================================================

    /**
     * Get the parsed project structure for element analysis.
     * In the .NET code, this is lazy-loaded via QXPS_File_Manager.Get_Project(this).
     * In Java, the project must be set externally (via setQxpProject or initProjectFromSoap).
     *
     * @return the cached project, or null when unresolved
     */
    public QxpProject getQxpProject() {
        return this.qxpProject;
    }

    public boolean hasQxpProject() {
        return this.qxpProject != null;
    }

    /**
     * Set the parsed project structure.
     *
     * @param qxpProject the QxpProject instance
     */
    public void setQxpProject(QxpProject qxpProject) {
        this.qxpProject = qxpProject;
    }

    /**
     * Initialize QxpProject from a SOAP Project object.
     * Convenience method to create and set the QxpProject in one call.
     *
     * @param soapProject the SOAP-generated Project from QXPS server
     */
    public void initProjectFromSoap(Project soapProject) {
        this.qxpProject = new QxpProject(soapProject);
    }

    // ========================================================================
    // PDF files (for multi-page PDF documents)
    // Cross-reference: .NET Document.PDFFiles property
    // ========================================================================

    /**
     * Get the list of PDF page file paths.
     *
     * <p>Never returns {@code null}: if the backing list was explicitly set to {@code null}
     * (via {@code setPdfFiles(null)}, the all-args constructor, or {@code builder().pdfFiles(null)}),
     * an empty list is returned so callers can safely call {@code isEmpty()}/{@code size()}/{@code get()}.
     *
     * @return the list of PDF file paths (never {@code null})
     */
    public List<String> getPdfFiles() {
        if (this.pdfFiles == null) {
            this.pdfFiles = new ArrayList<>();
        }
        return this.pdfFiles;
    }

    /**
     * Set the list of PDF page file paths.
     *
     * @param pdfFiles the list of PDF file paths
     */
    public void setPdfFiles(List<String> pdfFiles) {
        this.pdfFiles = pdfFiles;
    }

    /**
     * Get the absolute pool path for a PDF page file.
     * Used by Process_Document PDF handling.
     *
     * Cross-reference: .NET Document.GetPDFFileAbsolutePath(file)
     *
     * @param pdfFileName the PDF file name
     * @param documentPoolBasePath the base path for document pool
     * @return the absolute path to the PDF file
     */
    public String getPdfFileAbsolutePath(String pdfFileName, String documentPoolBasePath) {
        if (pdfFileName == null || documentPoolBasePath == null) {
            return pdfFileName;
        }
        return documentPoolBasePath + "/" + pdfFileName;
    }

    /**
     * Swap this document to a newly-saved version: update name/pool path, replace the
     * binary content with the freshly-downloaded bytes, and purge the cached XML/Project.
     *
     * <p>In .NET, Document.Change_Document() downloads the bytes itself via
     * QXPS_Helper.GetFileData (a 'literal' HTTP call). To keep the domain free of I/O,
     * the caller (service layer) performs the download and passes the bytes here.
     *
     * Cross-reference: .NET Document.Change_Document(newDocumentName).
     *
     * @param newFileName      new file name (with extension), e.g. G_45_1.qxp
     * @param newFilePoolPath  pool-relative path of the new file
     * @param newData          freshly-downloaded binary content of the new file
     */
    public void changeDocument(String newFileName, String newFilePoolPath,
                               String newFileFullPath, byte[] newData) {
        this.fileName = newFileName;
        this.filePoolPath = newFilePoolPath;
        // Keep the absolute (Quark-host) path consistent with the new pool name. The caller passes the
        // precomputed absolute path so the domain stays I/O-free. Finding #92.
        this.fileFullPath = newFileFullPath;
        this.data = newData;
        purgeXmlAndProject();
    }

    /**
     * Purge cached XML and project data.
     * Called when the document content changes (e.g., after Change_Document).
     *
     * Cross-reference: .NET Document.Change_Document() — purges _xml and _project
     */
    public void purgeXmlAndProject() {
        this.qxpXml = null;
        this.qxpProject = null;
    }

    /**
     * Average byte-size of a single box in this QXP document: data length / box count when this is a
     * real QXP with &gt; 100 boxes, otherwise the configured average box size.
     *
     * Cross-reference: .NET Document.Ratio_Size_Box.
     *
     * @param averageBoxSize the configured average box size (engine.average-box-size)
     */
    public int getRatioSizeBox(int averageBoxSize) {
        if ("QXP".equalsIgnoreCase(format) && data != null && data.length > 0
                && qxpXml != null && qxpXml.getProjectInfo().getNbBox() > 100) {
            return data.length / getQxpXml().getProjectInfo().getNbBox();
        }
        return averageBoxSize;
    }

    /**
     * Whether this document is a Mode_Degrade candidate: a QXP document with non-empty data whose
     * size exceeds the limit. Mirrors .NET {@code Document.Evaluate_Mode_Degrade}
     * ({@code Type == QXP && IsSet(Data) && Data.Length > SizeLimitBeforeFailSoft}). The QXP-type and
     * null/empty-data guards avoid degrading non-QXP references and prevent an NPE on null data.
     * Findings #30 / #55 / #93.
     */
    public boolean evaluateModeDegrade(long sizeLimitBeforeFailSoft) {
        return "QXP".equalsIgnoreCase(format)
                && data != null && data.length > 0
                && data.length > sizeLimitBeforeFailSoft;
    }

    /**
     * Box-complexity coefficient (1.0 = normal boxes; higher = more complex). Used to bound how many
     * boxes a modified document may contain.
     *
     * Cross-reference: .NET Document.Box_Complexity = Ratio_Size_Box / Average_Box_Size.
     *
     * @param averageBoxSize the configured average box size (engine.average-box-size)
     */
    public BigDecimal getBoxComplexity(int averageBoxSize) {
        if (averageBoxSize <= 0) {
            return BigDecimal.ONE;
        }
        return new BigDecimal(getRatioSizeBox(averageBoxSize))
                .divide(new BigDecimal(averageBoxSize), 6, RoundingMode.HALF_UP);
    }

    /**
     * Generate file names from document properties.
     */
    private void generateFileNames() {
        if (this.id != null && this.prefix != null && this.format != null) {
            // Use the format VERBATIM (no toLowerCase) so the file name stays consistent with the DAO
            // name-builders and QxpsCallerBusiness.getNewGabaritNameExt. Finding #57.
            this.fileName = String.format(FILE_NAME_PREFIX_PATTERN, this.prefix, this.id, this.format);
        }
    }
}
```


## 9. `src/main/java/com/socgen/sgs/api/quark/engine/domain/xml/QxpXml.java`

SHA-256: `sha256-338ae6bfdf9c7de94bb506308605f32e721ad83b97672c74802905e33fb609bd`

```java
package com.socgen.sgs.api.quark.engine.domain.xml;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBlocInfo;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DProjectInfo;
import lombok.extern.slf4j.Slf4j;

import javax.xml.xpath.XPath;
import javax.xml.xpath.XPathConstants;
import javax.xml.xpath.XPathExpressionException;
import javax.xml.xpath.XPathFactory;
import java.io.StringReader;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

import org.w3c.dom.Document;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;

/**
 * Stores and analyses the XML structure of a QuarkXPress document.
 * Provides XPath-based queries for bloc values, names, pages, layouts, and structural info.
 *
 * <p>Usage:
 * <pre>
 *   QxpXml xml = QxpXml.createFromXml(xmlString);
 *   String value = xml.getValue("MY_BLOC_NAME");
 *   List&lt;String&gt; names = xml.getListBoxNameStartWith("PDF_");
 *   int pageNum = xml.getPageNum("MY_BLOC_NAME");
 * </pre>
 *
 * Cross-reference: QXP.Engine.Core.QXP_XML
 */
@Slf4j
public class QxpXml {

    // ========================================================================
    // XPath patterns — direct mapping from .NET QXP_XML constants
    // ========================================================================

    /** Retrieves the text value inside a named box: //ID[@NAME='X']/..//PARAGRAPH/RICHTEXT/text() */
    private static final String BLOC_VALUE_PATTERN =
            "//ID[@NAME='%s']/..//PARAGRAPH/RICHTEXT/text()";

    /** All CT_TEXT box/cell names: (//CELL | //BOX)[@BOXTYPE='CT_TEXT']/ID/@NAME */
    private static final String CT_TEXT_BOX_NAMES_PATTERN =
            "(//CELL | //BOX)[@BOXTYPE='CT_TEXT']/ID/@NAME";

    /** Relative path from a box ID to its RICHTEXT value */
    private static final String CT_BOX_VALUE_RELATIVE_BOX_ID =
            "../..//PARAGRAPH/RICHTEXT/text()";

    /** UID of a named bloc: //ID[@NAME='X']/@UID */
    private static final String UID_BLOC_PATTERN =
            "//ID[@NAME='%s']/@UID";

    /** Page ID of a named bloc (searches BOX, TABLE, and TABLE containing CELL): */
    private static final String PAGE_ID_BLOC_PATTERN =
            "(//BOX[ID[@NAME='%s']] | //TABLE[ID[@NAME='%s']] | //TABLE[ROW/CELL/ID[@NAME='%s']])/GEOMETRY/@PAGE";

    /** Position of a named bloc: /PROJECT/LAYOUT/SPREAD/BOX[ID[@NAME='X']]/GEOMETRY/POSITION */
    private static final String POSITION_BLOC_PATTERN =
            "/PROJECT/LAYOUT/SPREAD/BOX[ID[@NAME='%s']]/GEOMETRY/POSITION";

    /** Layout name containing a named bloc: /PROJECT/LAYOUT[//ID[@NAME='X']]/ID/@NAME */
    private static final String LAYOUT_NAME_BLOC_PATTERN =
            "/PROJECT/LAYOUT[//ID[@NAME='%s']]/ID/@NAME";

    /** Box names starting with a prefix: //ID[starts-with(@NAME,'X')]/@NAME */
    private static final String BOX_NAME_START_WITH_PATTERN =
            "//ID[starts-with(@NAME,'%s')]/@NAME";

    /** Box names containing a string: //ID[contains(@NAME,'X')]/@NAME */
    private static final String BOX_NAME_CONTAINS_PATTERN =
            "//ID[contains(@NAME,'%s')]/@NAME";

    /** Overflow box names: //OVERMATTER/../../../ID/@NAME */
    private static final String BOX_NAME_OVERFLOW_PATTERN =
            "//OVERMATTER/../../../ID/@NAME";

    /** Check if a specific box is in overflow: //OVERMATTER/../../../ID[@NAME='X'] */
    private static final String IS_BOX_OVERFLOW_PATTERN =
            "//OVERMATTER/../../../ID[@NAME='%s']";

    /** Number of rows in a named table: //TABLE[ID[@NAME='X']]//ROW */
    private static final String NB_LIGNES_IN_TABLE_PATTERN =
            "//TABLE[ID[@NAME='%s']]//ROW";

    /** Project root: /PROJECT */
    private static final String PROJECT_PATTERN = "/PROJECT";

    /** All spread IDs: //SPREAD/ID */
    private static final String SPREAD_ID_PATTERN = "//SPREAD/ID";

    /** All box geometries (direct in spread): //BOX/GEOMETRY */
    private static final String BOX_GEOMETRY_PATTERN = "//BOX/GEOMETRY";

    /** Table geometry page attributes: //TABLE/GEOMETRY/@PAGE */
    private static final String BOX_TABLE_GEOMETRY_PAGE_PATTERN = "//TABLE/GEOMETRY/@PAGE";

    /** Relative path from table geometry to cell IDs: ../../ROW/CELL/ID */
    private static final String BOX_TABLE_RELATIVE_TABLE_GEOMETRY_PAGE_PATTERN =
            "../../ROW/CELL/ID";

    /** Master process ID: /PROCESSID/MASTER/ID/text() */
    private static final String MASTER_PROCESS_ID_PATTERN = "/PROCESSID/MASTER/ID/text()";

    // Position element names
    private static final String LEFT_KEY = "LEFT";
    private static final String TOP_KEY = "TOP";
    private static final String RIGHT_KEY = "RIGHT";
    private static final String BOTTOM_KEY = "BOTTOM";

    /** BOM character that sometimes prefixes XML from QuarkXPress server */
    private static final char BOM_CHAR = 65279;

    /** Empty project XML structure */
    private static final String EMPTY_PROJECT_XML =
            "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?><PROJECT></PROJECT>";

    /**
     * Create a fresh empty XML model. XPath instances are mutable/not thread-safe and must never be
     * shared between root execution trees.
     */
    public static QxpXml empty() {
        return createFromXml(EMPTY_PROJECT_XML);
    }

    // ========================================================================
    // Instance fields
    // ========================================================================

    private final Document xmlDocument;
    private final XPath xpath;
    private DProjectInfo projectInfo;

    // ========================================================================
    // Constructor (private — use static factories)
    // ========================================================================

    private QxpXml(Document xmlDocument) {
        this.xmlDocument = xmlDocument;
        this.xpath = XPathFactory.newInstance().newXPath();
    }

    // ========================================================================
    // Static factories
    // ========================================================================

    /**
     * Create a QxpXml instance from a raw XML string.
     *
     * @param xml the XML content (from QXPS server XML command)
     * @return a QxpXml instance, or EMPTY if parsing fails
     */
    public static QxpXml createFromXml(String xml) {
        if (xml == null || xml.isBlank()) {
            log.warn("Cannot create QxpXml from null/blank XML");
            return null;
        }
        try {
            String fixedXml = fixXml(xml);
            DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
            // Security: disable external entities
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
            DocumentBuilder builder = factory.newDocumentBuilder();
            Document doc = builder.parse(new InputSource(new StringReader(fixedXml)));
            return new QxpXml(doc);
        } catch (Exception e) {
            log.error("Failed to parse QXP XML", e);
            return null;
        }
    }

    /**
     * Fix XML by removing BOM character if present.
     * The QuarkXPress server sometimes prepends a BOM character to XML responses.
     *
     * @param xml the raw XML string
     * @return the cleaned XML string
     */
    private static String fixXml(String xml) {
        if (xml.length() > 0 && xml.charAt(0) == BOM_CHAR) {
            return xml.substring(1);
        }
        return xml;
    }

    // ========================================================================
    // Bloc value queries
    // ========================================================================

    /**
     * Get the text value contained in a named bloc (box).
     *
     * @param blocName the box name
     * @return the value if found, otherwise empty string
     */
    public String getValue(String blocName) {
        String expression = String.format(BLOC_VALUE_PATTERN, blocName);
        return evaluateString(expression, "");
    }

    /**
     * Get the UID (unique identifier) of a named bloc.
     *
     * @param blocName the box name
     * @return the UID if found, otherwise empty string
     */
    public String getUID(String blocName) {
        String expression = String.format(UID_BLOC_PATTERN, blocName);
        return evaluateString(expression, "");
    }

    /**
     * Check if a named element exists in the document.
     *
     * @param name the element name
     * @return true if the element exists
     */
    public boolean existName(String name) {
        String uid = getUID(name);
        return uid != null && !uid.isBlank();
    }

    // ========================================================================
    // Box name queries
    // ========================================================================

    /**
     * Get the list of box names starting with the given prefix.
     *
     * @param name the prefix to search for
     * @return list of matching box names
     */
    public List<String> getListBoxNameStartWith(String name) {
        String expression = String.format(BOX_NAME_START_WITH_PATTERN, name);
        return evaluateNodeListAsStrings(expression);
    }

    /**
     * Get the list of box names ending with the given suffix.
     *
     * @param suffix the suffix to search for
     * @return list of matching box names
     */
    public List<String> getListBoxNameEndWith(String suffix) {
        // XPath 1.0 has no ends-with, so we use contains + Java filter
        String expression = String.format(BOX_NAME_CONTAINS_PATTERN, suffix);
        List<String> allMatches = evaluateNodeListAsStrings(expression);
        List<String> filtered = new ArrayList<>();
        for (String match : allMatches) {
            if (match.endsWith(suffix)) {
                filtered.add(match);
            }
        }
        return filtered;
    }

    /**
     * Get the list of box names containing the given string.
     *
     * @param name the string to search for
     * @return list of matching box names
     */
    public List<String> getListBoxNameContains(String name) {
        String expression = String.format(BOX_NAME_CONTAINS_PATTERN, name);
        return evaluateNodeListAsStrings(expression);
    }

    /**
     * Get the list of box names that are in overflow state.
     *
     * @return list of overflow box names
     */
    public List<String> getOverflowBoxes() {
        return evaluateNodeListAsStrings(BOX_NAME_OVERFLOW_PATTERN);
    }

    /**
     * Check if a named box is in overflow state.
     *
     * @param name the box name
     * @return true if the box is in overflow
     */
    public boolean checkBoxOverflow(String name) {
        String expression = String.format(IS_BOX_OVERFLOW_PATTERN, name);
        try {
            NodeList nodes = (NodeList) xpath.evaluate(expression, xmlDocument, XPathConstants.NODESET);
            return nodes.getLength() > 0;
        } catch (XPathExpressionException e) {
            log.warn("XPath error checking overflow for [{}]", name, e);
            return false;
        }
    }

    // ========================================================================
    // Page and layout queries
    // ========================================================================

    /**
     * Get the real page number for a named bloc.
     * Strips trailing '*' characters (left/right page indicators) before parsing.
     *
     * @param blocName the box name
     * @return the page number, or 0 if not found
     */
    public int getPageNum(String blocName) {
        // Returns Integer.MIN_VALUE (not 0) for a not-found / unparseable page, and parses leniently
        // (trailing '*' page markers, decimals, spaces). Delegates to the shared lenient parser.
        // Findings #46 / #78.
        return parseIntSafe(getPageID(blocName));
    }

    /**
     * Get the raw page ID for a named bloc.
     * May contain '*' suffixes indicating page position relative to spine.
     *
     * @param blocName the box name
     * @return the page ID string, or empty string if not found
     */
    public String getPageID(String blocName) {
        String expression = String.format(PAGE_ID_BLOC_PATTERN, blocName, blocName, blocName);
        return evaluateString(expression, "");
    }

    /**
     * Get the layout name containing a named bloc.
     *
     * @param blocName the box name
     * @return the layout name, or empty string if not found
     */
    public String getLayoutName(String blocName) {
        String expression = String.format(LAYOUT_NAME_BLOC_PATTERN, blocName);
        return evaluateString(expression, "");
    }

    // ========================================================================
    // Bloc info queries
    // ========================================================================

    /**
     * Get position and identification info for a named bloc.
     *
     * @param blocName the box name
     * @return a DBlocInfo with name, page, UID, and position coordinates
     */
    public DBlocInfo getBlocInfo(String blocName) {
        DBlocInfo info = new DBlocInfo();

        // 1 - Name
        info.setName(blocName);

        // 2 - Page number
        info.setPage(getPageNum(blocName));

        // 3 - UID
        info.setUid(getUID(blocName));

        // 4 - Position coordinates
        String expression = String.format(POSITION_BLOC_PATTERN, blocName);
        try {
            NodeList positionNodes = (NodeList) xpath.evaluate(expression, xmlDocument, XPathConstants.NODESET);
            if (positionNodes.getLength() > 0) {
                Node positionNode = positionNodes.item(0);
                // Read ALL descendant elements (not just direct children) so LEFT/TOP/RIGHT/BOTTOM
                // nested below POSITION are found, not only direct children. #79
                NodeList children = (NodeList) xpath.evaluate(".//*", positionNode, XPathConstants.NODESET);
                for (int i = 0; i < children.getLength(); i++) {
                    Node child = children.item(i);
                    String nodeName = child.getNodeName();
                    String nodeValue = child.getTextContent();
                    switch (nodeName) {
                        case LEFT_KEY:
                            info.setLeft(parseBigDecimal(nodeValue));
                            break;
                        case TOP_KEY:
                            info.setTop(parseBigDecimal(nodeValue));
                            break;
                        case RIGHT_KEY:
                            info.setRight(parseBigDecimal(nodeValue));
                            break;
                        case BOTTOM_KEY:
                            info.setBottom(parseBigDecimal(nodeValue));
                            break;
                        default:
                            break;
                    }
                }
            }
        } catch (XPathExpressionException e) {
            log.warn("XPath error getting bloc info for [{}]", blocName, e);
        }

        return info;
    }

    // ========================================================================
    // Table queries
    // ========================================================================

    /**
     * Get the number of rows in a named table.
     *
     * @param tableName the table name
     * @return the number of rows
     */
    public int getNbLignes(String tableName) {
        String expression = String.format(NB_LIGNES_IN_TABLE_PATTERN, tableName);
        try {
            NodeList nodes = (NodeList) xpath.evaluate(expression, xmlDocument, XPathConstants.NODESET);
            return nodes.getLength();
        } catch (XPathExpressionException e) {
            log.warn("XPath error counting rows for table [{}]", tableName, e);
            return 0;
        }
    }

    // ========================================================================
    // Project info
    // ========================================================================

    /**
     * Get structural information about the project (spreads, boxes per page, etc.).
     * Result is cached after first computation.
     *
     * @return the project info
     */
    public DProjectInfo getProjectInfo() {
        if (this.projectInfo != null) {
            return this.projectInfo;
        }
        this.projectInfo = buildProjectInfo();
        return this.projectInfo;
    }

    /**
     * Build project info by analyzing the XML structure.
     * Counts spreads, boxes per page (both direct boxes and boxes inside tables).
     */
    private DProjectInfo buildProjectInfo() {
        DProjectInfo info = new DProjectInfo();

        try {
            // 1 - Project name and XML version
            NodeList projectNodes = (NodeList) xpath.evaluate(PROJECT_PATTERN, xmlDocument, XPathConstants.NODESET);
            if (projectNodes.getLength() > 0) {
                Node projectNode = projectNodes.item(0);
                String projectName = getAttributeValue(projectNode, "PROJECTNAME");
                String xmlVersion = getAttributeValue(projectNode, "XMLVERSION");
                info.setName(projectName);
                info.setXmlVersion(xmlVersion);
            }

            // 2 - Count spreads
            NodeList spreadNodes = (NodeList) xpath.evaluate(SPREAD_ID_PATTERN, xmlDocument, XPathConstants.NODESET);
            info.setNbSpread(spreadNodes.getLength());

            // 3 - Count boxes directly in spreads
            NodeList boxGeometryNodes = (NodeList) xpath.evaluate(BOX_GEOMETRY_PATTERN, xmlDocument, XPathConstants.NODESET);
            int totalBoxes = 0;
            for (int i = 0; i < boxGeometryNodes.getLength(); i++) {
                Node geomNode = boxGeometryNodes.item(i);
                String pageStr = getAttributeValue(geomNode, "PAGE");
                int currentPage = parseIntSafe(pageStr);
                if (currentPage != Integer.MIN_VALUE) { // page 0 / pasteboard counts too; only MIN_VALUE means "no page". #77
                    info.getPageBoxes().merge(currentPage, 1, Integer::sum);
                }
                totalBoxes++;
            }

            // 4 - Count boxes inside tables
            NodeList tableGeomPages = (NodeList) xpath.evaluate(BOX_TABLE_GEOMETRY_PAGE_PATTERN, xmlDocument, XPathConstants.NODESET);
            for (int i = 0; i < tableGeomPages.getLength(); i++) {
                Node pageAttr = tableGeomPages.item(i);
                int currentPage = parseIntSafe(pageAttr.getNodeValue());
                if (currentPage != Integer.MIN_VALUE) { // page 0 / pasteboard counts too; only MIN_VALUE means "no page". #77
                    // Count cell IDs relative to this table. pageAttr is an ATTRIBUTE node, whose owning
                    // element is reached via getOwnerElement() — getParentNode() on an attribute is ALWAYS
                    // null, which is why table cells were never counted. Finding #45.
                    Node tableGeomNode = (pageAttr instanceof org.w3c.dom.Attr)
                            ? ((org.w3c.dom.Attr) pageAttr).getOwnerElement()   // GEOMETRY
                            : pageAttr.getParentNode();
                    if (tableGeomNode != null && tableGeomNode.getParentNode() != null) {
                        Node tableNode = tableGeomNode.getParentNode(); // TABLE
                        NodeList cellIds = findCellIds(tableNode);
                        for (int j = 0; j < cellIds.getLength(); j++) {
                            info.getPageBoxes().merge(currentPage, 1, Integer::sum);
                            totalBoxes++;
                        }
                    }
                }
            }

            info.setNbBox(totalBoxes);

        } catch (XPathExpressionException e) {
            log.error("XPath error building project info", e);
        }

        return info;
    }

    // ========================================================================
    // Process ID queries (used with getprocessid command XML)
    // ========================================================================

    /**
     * Get the master process ID from a getprocessid XML response.
     *
     * @return the master process ID, or empty string if not found
     */
    public String getMasterProcessID() {
        return evaluateString(MASTER_PROCESS_ID_PATTERN, "");
    }

    // ========================================================================
    // Name-value extraction (all CT_TEXT boxes)
    // ========================================================================

    /**
     * Get all box names and their text values from the document.
     * Only includes CT_TEXT boxes with defined names.
     *
     * @return list of name-value pairs as String arrays [name, value]
     */
    public List<String[]> getNamesValuesBoxes() {
        List<String[]> result = new ArrayList<>();
        try {
            NodeList nameNodes = (NodeList) xpath.evaluate(CT_TEXT_BOX_NAMES_PATTERN, xmlDocument, XPathConstants.NODESET);
            for (int i = 0; i < nameNodes.getLength(); i++) {
                Node nameNode = nameNodes.item(i);
                String name = nameNode.getNodeValue();
                if (name == null || name.isEmpty()) {
                    continue;
                }

                // Evaluate relative XPath from the NAME attribute node to get the value
                String value = "";
                try {
                    Node valueNode = (Node) xpath.evaluate(CT_BOX_VALUE_RELATIVE_BOX_ID, nameNode, XPathConstants.NODE);
                    if (valueNode != null) {
                        value = valueNode.getNodeValue();
                        if (value == null) {
                            value = "";
                        }
                    }
                } catch (XPathExpressionException e) {
                    // Value not found, use empty string
                }

                result.add(new String[]{name, value});
            }
        } catch (XPathExpressionException e) {
            log.warn("XPath error getting names/values", e);
        }
        return result;
    }

    // ========================================================================
    // Private helper methods
    // ========================================================================

    /**
     * Evaluate an XPath expression and return the first matching string.
     *
     * @param expression the XPath expression
     * @param defaultValue the default value if no match
     * @return the first match or defaultValue
     */
    private String evaluateString(String expression, String defaultValue) {
        try {
            NodeList nodes = (NodeList) xpath.evaluate(expression, xmlDocument, XPathConstants.NODESET);
            if (nodes.getLength() > 0) {
                Node node = nodes.item(0);
                String value = node.getNodeValue();
                if (value == null) {
                    value = node.getTextContent();
                }
                return value != null ? value : defaultValue;
            }
        } catch (XPathExpressionException e) {
            log.warn("XPath evaluation error for expression [{}]", expression, e);
        }
        return defaultValue;
    }

    /**
     * Evaluate an XPath expression and return all matching values as a string list.
     *
     * @param expression the XPath expression
     * @return list of matched string values
     */
    private List<String> evaluateNodeListAsStrings(String expression) {
        List<String> result = new ArrayList<>();
        try {
            NodeList nodes = (NodeList) xpath.evaluate(expression, xmlDocument, XPathConstants.NODESET);
            for (int i = 0; i < nodes.getLength(); i++) {
                Node node = nodes.item(i);
                String value = node.getNodeValue();
                if (value == null) {
                    value = node.getTextContent();
                }
                if (value != null) { // keep blank/whitespace names too — do not blank-filter. #80
                    result.add(value);
                }
            }
        } catch (XPathExpressionException e) {
            log.warn("XPath evaluation error for expression [{}]", expression, e);
        }
        return result;
    }

    /**
     * Find all CELL/ID nodes within a TABLE node.
     */
    private NodeList findCellIds(Node tableNode) {
        try {
            return (NodeList) xpath.evaluate(".//ROW/CELL/ID", tableNode, XPathConstants.NODESET);
        } catch (XPathExpressionException e) {
            log.warn("XPath error finding cell IDs in table", e);
            return new EmptyNodeList();
        }
    }

    /**
     * Get an attribute value from a node.
     */
    private String getAttributeValue(Node node, String attributeName) {
        if (node.getAttributes() != null) {
            Node attr = node.getAttributes().getNamedItem(attributeName);
            if (attr != null) {
                return attr.getNodeValue();
            }
        }
        return "";
    }

    /**
     * Parse a string to BigDecimal safely.
     * Handles comma-separated decimals (French locale) by replacing comma with dot.
     */
    private BigDecimal parseBigDecimal(String value) {
        if (value == null || value.isBlank()) {
            return BigDecimal.ZERO;
        }
        try {
            // QuarkXPress may use comma as decimal separator (French locale)
            String normalized = value.replace(',', '.');
            return new BigDecimal(normalized);
        } catch (NumberFormatException e) {
            log.warn("Cannot parse BigDecimal from [{}]", value);
            return BigDecimal.ZERO;
        }
    }

    /**
     * Parse a string to int safely.
     */
    private int parseIntSafe(String value) {
        // Lenient int parse: strip trailing '*' page markers and ALL spaces, normalize the decimal comma,
        // parse leniently (decimals/signs OK), and return Integer.MIN_VALUE (NOT 0) for null/blank/unparseable
        // — so a genuine page 0 is distinguishable from a parse failure.
        // Findings #46 / #77 / #78.
        if (value == null) {
            return Integer.MIN_VALUE;
        }
        String s = value.replaceAll("\\*+$", "").replace(" ", "").replace(',', '.');
        if (s.isEmpty()) {
            return Integer.MIN_VALUE;
        }
        try {
            return new java.math.BigDecimal(s).toBigInteger().intValue();
        } catch (NumberFormatException e) {
            log.warn("Cannot parse int from [{}]", value);
            return Integer.MIN_VALUE;
        }
    }

    // ========================================================================
    // Empty NodeList implementation (for null-safe returns)
    // ========================================================================

    /**
     * Empty NodeList implementation for null-safe fallback.
     */
    private static class EmptyNodeList implements NodeList {
        @Override
        public Node item(int index) {
            return null;
        }

        @Override
        public int getLength() {
            return 0;
        }
    }
}
```


## 10. `src/main/java/com/socgen/sgs/api/quark/engine/domain/project/QxpProject.java`

SHA-256: `sha256-31c929c80d210b25864da50fe4b3d55565f790d11d4a58f330ca786d15b77845`

```java
package com.socgen.sgs.api.quark.engine.domain.project;

import com.socgen.sgs.api.quark.engine.domain.element.ExceptionTElement;
import com.socgen.sgs.api.quark.engine.domain.element.TBox;
import com.socgen.sgs.api.quark.engine.domain.element.TElement;
import com.socgen.sgs.api.quark.engine.domain.element.TGroup;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.element.TTable;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Group;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Layout;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Spread;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Table;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Represents an advanced structure of a QuarkXPress project.
 * Analyses the SOAP Project object model to build a dictionary of named elements
 * (TBox, TTable, TGroup) that can be looked up by name.
 *
 * <p>The {@link #analyse(TaskBase, boolean)} method iterates through all
 * layouts → spreads → boxes/tables/groups and populates the elements dictionary.
 * This dictionary is then used by tasks (e.g., QXP_Data STYLE mode) to find
 * and clone source elements.
 *
 * <p>Usage:
 * <pre>
 *   QxpProject project = new QxpProject(soapProject);
 *   project.analyse(task, false);
 *   TElement element = project.getElements().get("MY_BOX_NAME");
 * </pre>
 *
 * Cross-reference: QXP.Engine.Core.QXP_Project
 */
@Getter
@Slf4j
public class QxpProject {

    /** The underlying SOAP project structure. */
    private final Project project;

    /** Named elements dictionary, populated by {@link #analyse(TaskBase, boolean)}. */
    private Map<String, TElement> elements;

    /** Whether the project has already been analysed. */
    private boolean analysed = false;

    /** Create a fresh empty project so analysis state cannot leak between runs. */
    public static QxpProject empty() {
        return new QxpProject(new Project());
    }

    /**
     * Create a QxpProject from a SOAP Project.
     *
     * @param project the SOAP-generated Project
     */
    public QxpProject(Project project) {
        this.project = project;
    }

    public boolean isEmpty() {
        return project == null || project.getLayouts() == null || project.getLayouts().length == 0;
    }

    /**
     * Analyse the project structure to build the elements dictionary.
     * Iterates through all layouts → spreads → boxes/tables/groups,
     * creating TBox/TTable/TGroup instances and adding them to the elements map.
     *
     * <p>This method is idempotent — calling it multiple times has no effect
     * after the first successful analysis.
     *
     * @param task     a reference to the calling task (for error logging to run)
     * @param logError if true, structural errors are logged to the run's error list;
     *                 if false, errors are silently ignored
     */
    public void analyse(TaskBase task, boolean logError) {
        // Don't re-analyse if already done
        if (analysed) {
            return;
        }

        elements = new LinkedHashMap<>();
        List<TGroup> pendingGroups = new ArrayList<>();

        if (project.getLayouts() == null) {
            analysed = true;
            return;
        }

        for (Layout layout : project.getLayouts()) {
            if (layout == null || layout.getSpreads() == null) {
                continue;
            }

            for (Spread spread : layout.getSpreads()) {
                if (spread == null) {
                    continue;
                }

                // Process boxes
                processBoxes(spread);

                // Process tables
                processTables(spread);

                // Process groups (collect first, evaluate after all elements are registered)
                processGroups(spread, pendingGroups);
            }
        }

        // Evaluate all groups after all boxes/tables are in the elements map.
        // Groups reference boxes by name via boxRefs, so boxes must be registered first.
        evaluatePendingGroups(pendingGroups, task, logError);

        analysed = true;
    }

    /**
     * Process all boxes in a spread.
     * Creates TBox instances and adds them to the elements dictionary.
     */
    private void processBoxes(Spread spread) {
        if (spread.getBoxes() == null) {
            return;
        }

        for (Box box : spread.getBoxes()) {
            if (box == null) {
                continue;
            }

            TBox tBox = new TBox(box);

            // Parity: .NET QXP_Project adds to a Dictionary which throws ArgumentNullException on a null
            // key, aborting Analyse. (Finding #81.)
            if (tBox.getName() == null) {
                throw new IllegalArgumentException("Element name is null");
            }

            // Some documents have duplicate box names (legacy QXP Server 7 bug)
            if (!elements.containsKey(tBox.getName())) {
                elements.put(tBox.getName(), tBox);
                tBox.evaluate(this);
            } else {
                log.debug("Duplicate box name [{}] — skipping", tBox.getName());
            }
        }
    }

    /**
     * Process all tables in a spread.
     * Creates TTable instances and adds them to the elements dictionary.
     */
    private void processTables(Spread spread) {
        if (spread.getTables() == null) {
            return;
        }

        for (Table table : spread.getTables()) {
            // QXP Server v9 bug: there's always a null table even when none exist
            if (table == null) {
                continue;
            }

            TTable tTable = new TTable(table);

            if (tTable.getName() == null) {
                throw new IllegalArgumentException("Element name is null"); // .NET ArgumentNullException (#81)
            }

            if (!elements.containsKey(tTable.getName())) {
                elements.put(tTable.getName(), tTable);
                tTable.evaluate(this);
            } else {
                log.debug("Duplicate table name [{}] — skipping", tTable.getName());
            }
        }
    }

    /**
     * Process all groups in a spread.
     * Creates TGroup instances, adds them to the elements dictionary,
     * and collects them for deferred evaluation.
     *
     * <p>Groups are evaluated after all boxes and tables are registered
     * because groups reference child elements via boxRefs.
     */
    private void processGroups(Spread spread, List<TGroup> pendingGroups) {
        if (spread.getGroups() == null) {
            return;
        }

        for (Group group : spread.getGroups()) {
            // QXP Server v9 bug: there's always a null group even when none exist
            if (group == null) {
                continue;
            }

            TGroup tGroup = new TGroup(group);

            if (tGroup.getName() == null) {
                throw new IllegalArgumentException("Element name is null"); // .NET ArgumentNullException (#81)
            }

            if (!elements.containsKey(tGroup.getName())) {
                elements.put(tGroup.getName(), tGroup);
                pendingGroups.add(tGroup);
            } else {
                log.debug("Duplicate group name [{}] — skipping", tGroup.getName());
            }
        }
    }

    /**
     * Evaluate all pending groups.
     * Called after all boxes/tables/groups are registered in the elements map.
     *
     * @param pendingGroups the groups to evaluate
     * @param task          the calling task (for error logging)
     * @param logError      whether to log structural errors to the run
     */
    private void evaluatePendingGroups(List<TGroup> pendingGroups, TaskBase task, boolean logError) {
        for (TGroup tGroup : pendingGroups) {
            try {
                tGroup.evaluate(this);
            } catch (ExceptionTElement e) {
                // Parity: .NET QXP_Project catches ONLY Exception_TElement and, when logError, records it
                // via task.Run.Errors.Add(tex.ToString()) — the string overload → Error_Type.Unspecified (1),
                // NOT Critique. Any non-TElement exception propagates and aborts analyse, as in .NET.
                // (Findings #18/#19/#44.)
                if (logError && task != null) {
                    log.error("Error evaluating TGroup [{}]: {}", tGroup.getName(), e.getMessage());
                    task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED, e.getMessage()));
                } else {
                    log.debug("Error evaluating TGroup [{}]: {}", tGroup.getName(), e.getMessage());
                }
            }
        }
    }
}
```


## 11. `src/main/java/com/socgen/sgs/api/quark/engine/business/GetGabaritXmlBusiness.java`

SHA-256: `sha256-f8b4a59c7b51086d92f67e91af74bb3b386f87315215fad73b6a407b827235fc`

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.infra.interop.qxps.client.QxpsHttpClient;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.FetchXmlMessage;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsResponseInfo;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;

/**
 * Business bridge for fetching a document's full XML (Modifier schema) from QuarkXPress Server.
 * Keeps the service → business → infra boundary (the Check service must not call infra directly).
 *
 * <p>Cross-reference: .NET QXPS_Helper.Get_Xml (document XML, no box filter).
 */
@Component
@RequiredArgsConstructor
public class GetGabaritXmlBusiness {

    private final QxpsHttpClient qxpsHttpClient;

    /**
     * Fetch the full document XML from the QXPS pool. The cache-aware structural boundary owns
     * failure handling and degraded-state transitions.
     *
     * @param documentName the pool path / document name
     * @return the document XML, or an empty string for an empty response
     */
    public String fetchXml(String documentName) {
        QxpsResponseInfo response = qxpsHttpClient.execute(documentName, new FetchXmlMessage());
        // XML is a text response; fall back to decoding bytes if the server returned binary.
        if (response.getTextResponse() != null) {
            return response.getTextResponse();
        }
        byte[] bytes = response.getBinaryResponse();
        return bytes != null ? new String(bytes, StandardCharsets.UTF_8) : "";
    }
}
```


## 12. `src/main/java/com/socgen/sgs/api/quark/engine/business/GetDocumentProjectBusiness.java`

SHA-256: `sha256-058e42279e867989042cf1b173533edb0b7109cf600969b5c492a337659d432e`

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.infra.interop.qxpsm.QxpsmSoapClient;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * Bridge for fetching a pooled document's QuarkXPress DOM (project) via QXPSM getXPressDOM
 * (service → business → infra). Used by compartiment incorporation to read a child run's
 * generated QXP structure.
 *
 * <p>Cross-reference: .NET Document.QXPProject (lazy QXPS_File_Manager.Get_Project).
 */
@Component
@RequiredArgsConstructor
public class GetDocumentProjectBusiness {

    private final QxpsmSoapClient qxpsmSoapClient;

    /**
     * Fetch the QXP project (DOM) of a pooled document. Failure is handled by the cache-aware
     * {@link DocumentStructureBusiness} boundary.
     *
     * @param documentName the pool path / document name
     * @return the parsed QxpProject, or null for an empty response
     */
    public QxpProject getProject(String documentName) {
        Project project = qxpsmSoapClient.getProject(documentName);
        return project != null ? new QxpProject(project) : null;
    }
}
```


## 13. `src/main/java/com/socgen/sgs/api/quark/engine/business/QxpsCallerBusiness.java`

SHA-256: `sha256-4f1db12b0db915ccc2a4a6f9cb66b69a948ffda0f22196d525ad4137844813d1`

```java
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
    private final DocumentStructureBusiness documentStructureBusiness;

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

            // Change_Document invalidates structural caches. The next top-level step lazily reads
            // the current working QXP before evaluating page/layout/box constraints.
            documentStructureBusiness.ensureXml(run, run.getGabarit());
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
        String saveAsPath = run.getPoolPathAbsolute("", poolBasePath);

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
            String modifyFileName = run.getPoolPath(
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
        String newPoolPath = run.getPoolPath(newGabaritName);
        // Absolute path on the Quark host, kept consistent with the new pool name. Finding #92.
        String newFullPath = run.getPoolPathAbsolute(
                newGabaritName, qxpsProperties.getPool().getDefaultPath());

        // Download the freshly-saved QXP binary via a 'literal' call (no re-render), exactly
        // like .NET Document.Change_Document() → QXPS_Helper.GetFileData(filePoolPath).
        byte[] newData = qxpsHttpClient.execute(newPoolPath, new LiteralMessage()).getBinaryResponse();

        // Swap the gabarit to the new version (name/pool path/abs path + binary, purges cached XML/Project).
        gabarit.changeDocument(newGabaritName, newPoolPath, newFullPath, newData);

        // Register the new pool file as known so it is not re-uploaded later.
        // Cross-reference: .NET QXPS_File_Manager.Addfile_Inform(newPoolName).
        filePool.inform(run.requireExecutionContext(), newPoolPath);

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
```


## 14. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/CheckServiceImpl.java`

SHA-256: `sha256-b71ed8f029d0e2deb99b842ac22c7e771df37e205a405d397935a3fabe49d58e`

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.DataNameValue;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.StoreDataType;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.service.CheckService;
import com.socgen.sgs.api.quark.engine.service.ProcessTasksService;
import com.socgen.sgs.api.quark.engine.service.QxpsCallerService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * Step 6: CHECK — Overflow detection, re-processing, and data collection.
 *
 * <p>Three phases:
 * <ol>
 *   <li>Overflow detection: find overflowing boxes, re-process affected dynamic tasks</li>
 *   <li>SQL data collection: collect DataNameValues from TaskDynamique and TaskSql</li>
 *   <li>Document data collection: collect box name/values from final document XML</li>
 * </ol>
 *
 * Cross-reference: .NET Run_Base.Check()
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class CheckServiceImpl implements CheckService {

    private static final String BOX_AUTO_NAME_PREFIX = "Box";
    private static final String BRACKET_OPEN = "[";
    private static final String BRACKET_CLOSE = "]";

    private final DocumentStructureBusiness documentStructureBusiness;
    private final ProcessTasksService processTasksService;
    private final QxpsCallerService qxpsCallerService;

    @Override
    public void check(Run run) {
        log.info("Starting Check step for run [{}]", run.getId());

        // Phase 1: Overflow detection and re-processing
        if (hasControlOverflow(run)) {
            documentStructureBusiness.ensureXml(run, run.getGabarit());
            checkOverflow(run);
        }

        // Phase 3 & 4: data collection — bitwise tests on the raw store-type code so a combined
        // value (0x03 = SQL|DOCUMENT) enables BOTH collections. (.NET Run_Base.cs:677/699 do two
        // independent (Store_Type & flag) == flag tests.) Finding #1.
        int storeCode = run.getRunProperties().getStoreDataTypeCode();

        // Phase 3: SQL data collection
        if (StoreDataType.hasFlag(storeCode, StoreDataType.SQL)) {
            collectSqlData(run);
        }

        // Phase 4: Document data collection
        if (StoreDataType.hasFlag(storeCode, StoreDataType.DOCUMENT)) {
            documentStructureBusiness.ensureXml(run, run.getGabarit());
            collectDocumentData(run);
        }

        log.info("Check step completed for run [{}]", run.getId());
    }

    // ========================================================================
    // Phase 2: Overflow detection
    // Cross-reference: .NET Run_Base.Check() — Control_Overflow section
    // ========================================================================

    /**
     * Check if any dynamic task in the run has overflow control enabled.
     */
    private boolean hasControlOverflow(Run run) {
        for (TaskBase task : run.getTasks().values()) {
            if (task instanceof TaskDynamique) {
                TaskDynamique dynTask = (TaskDynamique) task;
                if (dynTask.isTodo() && dynTask.isControlOverflow()) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Detect overflow boxes and re-process affected dynamic tasks.
     *
     * Cross-reference: .NET Run_Base.Check() overflow section
     */
    private void checkOverflow(Run run) {
        log.info("Run [{}] has overflow control enabled", run.getId());

        QxpXml xml = run.getGabarit().getQxpXml();
        List<String> overflowBoxes = xml.getOverflowBoxes();

        log.info("Document contains {} box(es) in overflow", overflowBoxes.size());

        List<TaskBase> tasksToReprocess = new ArrayList<>();

        // Check each dynamic task with control_overflow
        for (TaskBase task : run.getTasks().values()) {
            if (!(task instanceof TaskDynamique)) continue;

            TaskDynamique dynTask = (TaskDynamique) task;
            if (!dynTask.isTodo() || !dynTask.isControlOverflow()) continue;

            log.debug("Task [{}] has overflow control enabled", dynTask.getId());

            // Clear previous overflow boxes
            dynTask.getOverflowBoxes().clear();

            // Find which of this task's box names are in overflow
            for (String boxName : dynTask.getBoxNames()) {
                if (overflowBoxes.contains(boxName)) {
                    dynTask.getOverflowBoxes().add(boxName);
                }
            }

            if (!dynTask.getOverflowBoxes().isEmpty()) {
                tasksToReprocess.add(dynTask);
                log.info("Task [{}] has {} box(es) in overflow — will be re-processed",
                        dynTask.getId(), dynTask.getOverflowBoxes().size());
            } else {
                log.debug("No overflow for task [{}]", dynTask.getId());
            }
        }

        // Set all tasks to todo=false, EXCEPT tasks to reprocess and allwaysReprocess tasks
        for (TaskBase task : run.getTasks().values()) {
            if (!tasksToReprocess.contains(task) && !task.isAllwaysReprocess()) {
                task.setTodo(false);
            }
        }

        if (!tasksToReprocess.isEmpty()) {
            // Re-execute Process + Process_Steps
            log.info("Re-processing {} task(s) due to overflow", tasksToReprocess.size());

            // processTasks() creates and configures the RunTask itself (single source of truth, with the
            // step limit) — it is the sole creator during re-processing.
            // The previously redundant `run.setRunTask(new RunTask(run))` here was immediately overwritten. #59
            processTasksService.processTasks(run);
            qxpsCallerService.process(run);

        }
    }

    // ========================================================================
    // Phase 3: SQL data collection
    // Cross-reference: .NET Run_Base.Check() — Store_Data_Type.SQL section
    // ========================================================================

    private void collectSqlData(Run run) {
        log.debug("Collecting SQL data for run [{}]", run.getId());

        // From TaskDynamique
        for (TaskBase task : run.getTasks().values()) {
            if (task instanceof TaskDynamique) {
                TaskDynamique dynTask = (TaskDynamique) task;
                if (dynTask.isStoreData() && !dynTask.getDataNamesValues().isEmpty()) {
                    run.getSqlDataNamesValues().addAll(dynTask.getDataNamesValues());
                }
            }
        }

        // From TaskSql
        for (TaskBase task : run.getTasks().values()) {
            if (task instanceof TaskSql) {
                TaskSql sqlTask = (TaskSql) task;
                if (sqlTask.isStoreData() && !sqlTask.getDataNamesValues().isEmpty()) {
                    run.getSqlDataNamesValues().addAll(sqlTask.getDataNamesValues());
                }
            }
        }

        log.info("Collected {} SQL data entries for run [{}]",
                run.getSqlDataNamesValues().size(), run.getId());
    }

    // ========================================================================
    // Phase 4: Document data collection
    // Cross-reference: .NET Run_Base.Check() — Store_Data_Type.DOCUMENT section
    // ========================================================================

    private void collectDocumentData(Run run) {
        log.debug("Collecting document data for run [{}]", run.getId());

        QxpXml xml = run.getGabarit().getQxpXml();
        List<String[]> namesValues = xml.getNamesValuesBoxes();

        for (String[] nameValue : namesValues) {
            String name = nameValue[0];

            // Exclude auto-generated box names:
            // 1. Names starting with "Box" (QuarkXPress auto-naming)
            // 2. Names enclosed in brackets [name] (clone auto-naming)
            if (name.startsWith(BOX_AUTO_NAME_PREFIX)) {
                continue;
            }
            if (name.startsWith(BRACKET_OPEN) && name.endsWith(BRACKET_CLOSE)) {
                continue;
            }

            String value = nameValue.length > 1 ? nameValue[1] : "";
            run.getDocDataNamesValues().add(new DataNameValue(name, value));
        }

        log.info("Collected {} document data entries for run [{}]",
                run.getDocDataNamesValues().size(), run.getId());
    }
}
```


## 15. `src/main/java/com/socgen/sgs/api/quark/engine/domain/task/TaskDocument.java`

SHA-256: `sha256-00237d7697fd67d94adce532ac0d23dc3960a2f2d4f838b0de08ea98ef563c44`

```java
package com.socgen.sgs.api.quark.engine.domain.task;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.enums.DocumentFormatEnum;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import lombok.Getter;
import lombok.Setter;

/** Represents a task that inserts a document or document fragment. */
@Getter
@Setter
public class TaskDocument extends TaskBase {

    private String formatDocument;
    private boolean rotationImage = false;
    private int idSousCategorie;
    private boolean conserverStyle = false;
    private String offsetValues;
    private TaskImageOffset imageOffset;
    private DocumentDomain document;
    private String positionValues;
    private TaskImagePosition imagePosition;

    public TaskDocument(int id, Run run) {
        super(id, run);
    }

    @Override
    public void prepare() {
        DocumentFormatEnum format = DocumentFormatEnum.fromFormat(this.formatDocument);
        if (format == null) {
            this.setSubTaskType(SubTaskTypeEnum.UNKNOWN);
            return;
        }

        switch (format) {
            case PDF:
                this.setSubTaskType(SubTaskTypeEnum.FILE_PDF);
                this.setToLoad(true);
                break;
            case JPG:
            case JPEG:
            case EPS:
            case TIF:
            case TIFF:
            case GIF:
                this.setSubTaskType(SubTaskTypeEnum.FILE_IMG);
                this.setToLoad(true);
                break;
            case RTF:
                this.setSubTaskType(SubTaskTypeEnum.FILE_RTF);
                break;
            case DOC:
                this.setSubTaskType(SubTaskTypeEnum.FILE_DOC);
                break;
            case XTG:
                this.setSubTaskType(SubTaskTypeEnum.FILE_XTG);
                break;
            case QXP:
                this.setSubTaskType(SubTaskTypeEnum.FILE_QXP_DATA);
                break;
            default:
                this.setSubTaskType(SubTaskTypeEnum.UNKNOWN);
                break;
        }

        // Document loading is delegated to the business/service layer
    }

    public String resolveTargetBlocName() {
        switch (this.getSubTaskType()) {
            case FILE_PDF:
                return (this.getDestinationBlocName() == null ? "" : this.getDestinationBlocName()) + "_1";
            case FILE_QXP_DATA:
                String dest = this.getDestinationBlocName() != null ? this.getDestinationBlocName() : "";
                return dest.split("\\|", -1)[0];
            default:
                return this.getDestinationBlocName() != null ? this.getDestinationBlocName() : "";
        }
    }

    @Override
    public void evaluateInfo() {
        String target = resolveTargetBlocName();
        if (!target.isEmpty()) {
            this.getProperties().setPageNum(this.getRun().getGabarit().getQxpXml().getPageNum(target));
            this.getProperties().setLayoutName(this.getRun().getGabarit().getQxpXml().getLayoutName(target));
            if (this.getProperties().getPageNum() == Integer.MIN_VALUE) {
                this.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                        String.format("Le bloc %s est introuvable dans le document %s",
                                target, this.getRun().getGabarit().getFilePoolPath())));
            }
        } else {
            this.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                    String.format("Manque le bloc de destination %s dans la tache %s",
                            target, this.getDebugInfo())));
        }
    }

    @Override
    public boolean isModeDegrade() {
        return this.document != null && this.document.isModeDegrade();
    }
}

```


## 16. `src/main/java/com/socgen/sgs/api/quark/engine/domain/task/TaskQxpPrevious.java`

SHA-256: `sha256-97008707e100cedbf34a9c813c51e321e6ed15ba6127b781eaac19409f2f1bac`

```java
package com.socgen.sgs.api.quark.engine.domain.task;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import lombok.Getter;
import lombok.Setter;

/** Represents a task that retrieves data from a previously certified QXP document. */
@Getter
@Setter
public class TaskQxpPrevious extends TaskBase {

    private boolean conserverStyle = false;
    private String previousTypeRapport;
    private DocumentDomain document;
    private String positionBlocName = "";

    public TaskQxpPrevious(int id, Run run) {
        super(id, run);
    }

    @Override
    public void prepare() {
        this.setSubTaskType(SubTaskTypeEnum.FILE_QXP_PREVIOUS);
    }

    /** Resolves the target destination bloc name for page/layout evaluation. */
    public String resolveTargetBlocName() {
        if (this.positionBlocName != null && !this.positionBlocName.isEmpty()) {
            return this.positionBlocName;
        }
        if (this.getDestinationBlocName() != null && !this.getDestinationBlocName().isEmpty()) {
            String[] destinations = this.getDestinationBlocName().split("\\|", -1);
            return destinations[0];
        }
        return null;
    }

    @Override
    public void evaluateInfo() {
        String target = resolveTargetBlocName();
        if (target != null) {
            this.getProperties().setPageNum(this.getRun().getGabarit().getQxpXml().getPageNum(target));
            this.getProperties().setLayoutName(this.getRun().getGabarit().getQxpXml().getLayoutName(target));
        }
    }

    @Override
    public boolean isModeDegrade() {
        return this.document != null && this.document.isModeDegrade();
    }
}

```


## 17. `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/DynamiqueTaskProcessStrategy.java`

SHA-256: `sha256-c0a4e4bb39a31301845fe086204362cc296f4247a7de82af5d3c14f5b9b0b76a`

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DCell;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DMasterPage;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DPoint;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DReport;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DRow;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DSection;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DTable;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DZone;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.PrepareReportParameters;

import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocPage;

import com.socgen.sgs.api.quark.engine.domain.element.TElement;

import com.socgen.sgs.api.quark.engine.domain.helper.DynamiqueGeometryHelper;

import com.socgen.sgs.api.quark.engine.domain.helper.DynamiquePageBreakHelper;

import com.socgen.sgs.api.quark.engine.domain.helper.MathHelper;

import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;

import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;

import com.socgen.sgs.api.quark.engine.domain.port.DynamicQueryPort;

import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.domain.exception.EngineException;
import com.socgen.sgs.api.quark.engine.domain.RunError;

import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;

import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;

import com.socgen.sgs.api.quark.engine.enums.AbsoluteRepeatType;

import com.socgen.sgs.api.quark.engine.service.task.TaskProcessStrategy;

import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;

import lombok.RequiredArgsConstructor;

import lombok.extern.slf4j.Slf4j;

import org.springframework.stereotype.Component;

import java.math.BigDecimal;

import java.util.ArrayList;

import java.util.Iterator;

import java.util.List;

import java.util.Map;

import java.util.stream.Collectors;

/**

 * Strategy for processing TaskDynamique (dynamic SQL-driven report generation).

 * Handles 4 stages:

 * <ol>

 *   <li>Get_Report: Execute SQL, build DReport structure from result rows</li>

 *   <li>Check_Report: Verify each DCell has a valid TElement from gabarit template</li>

 *   <li>Prepare_Report: Calculate geometry (position, page, column) for all elements</li>

 *   <li>Render_Boxes: Convert DReport elements into BlocBox/BlocPage for QXPS Modifier</li>

 * </ol>

 *

 * Cross-reference: QXP.Engine.Core.Business.Process_Dynamique

 */

@Component

@Slf4j

@RequiredArgsConstructor

public class DynamiqueTaskProcessStrategy implements TaskProcessStrategy<TaskDynamique> {

    // SQL column names matching .NET constants

    private static final String ID_SECTION_COL = "ID_SECTION";

    private static final String ID_TABLE_COL = "ID_TABLE";

    private static final String ID_GROUP_COL = "ID_GROUPE";

    private static final String ID_LIGNE_COL = "ID_LIGNE";

    private static final String NOM_BLOC_COL = "NOM_BLOC";

    private static final String VALEUR_BLOC_COL = "VALEUR_BLOC";

    private static final String TEMPLATE_COL = "TEMPLATE";

    private static final String ROW_LEVEL_COL = "ROW_LEVEL";

    private static final String DESCRIPTION_BLOC_COL = "DESCRIPTION_BLOC";

    private static final String INFO_BLOC_COL = "INFO_BLOC";

    // Naming patterns

    private static final String NEW_PAGE_PATTERN = "%s_P%d";

    private final DynamicQueryPort dynamicQueryPort;

    private final DocumentStructureBusiness documentStructureBusiness;

    @Override

    public Class<TaskDynamique> getTaskType() {

        return TaskDynamique.class;

    }

    @Override

    public void process(TaskDynamique task) {

        log.debug("DynamiqueTaskProcessStrategy processing task [{}]", task.getId());

        DReport report = null;

        PrepareReportParameters prp = new PrepareReportParameters(task);

        if (task.getRun().getGabarit() == null) {

            log.error("Gabarit template is null for dynamic task [{}]", task.getId());

            return;

        }

        // The specimen boxes referenced by every report cell live in the gabarit-template
        // document, not the source gabarit. Parse that document's structure once so the

        // template elements can be resolved during Check_Report.

        ensureTemplateProject(task);
        // ================================================================

        // Stage 1: Get_Report — Execute SQL and build DReport

        // ================================================================

        try {

            List<Map<String, Object>> rows = dynamicQueryPort.executeQuery(

                    task.getSql(), task.getRun().getInParams());

            log.info("Dynamic task [{}] (run [{}]) SQL fetched {} rows",
                    task.getId(), task.getRun().getId(), rows != null ? rows.size() : 0);

            if (rows != null && !rows.isEmpty()) {

                report = getReport(prp, rows);

            } else {

                log.info("No SQL data for dynamic task [{}]", task.getId());

            }

        } catch (Exception ex) {

            log.error("Dynamic task [{}] SQL failed: {}", task.getId(), ex.getMessage());
            log.debug("Dynamic task [{}] SQL failure detail", task.getId(), ex);

            return;

        }

        // ================================================================

        // Stage 2: Check_Report — Verify TElements exist

        // ================================================================

        if (report != null) {

            checkReport(prp, report);

        }

        // ================================================================

        // Stage 3: Prepare_Report — Calculate geometry

        // ================================================================

        if (report != null) {

            prepareReport(prp, report);

        }

        // ================================================================

        // Stage 4: Render_Boxes — Build blocs from report

        // ================================================================

        renderBoxes(prp, report);

    }

    // ========================================================================

    // Stage 1: Get_Report

    // Cross-reference: Process_Dynamique.Get_Report() lines 95-220

    // ========================================================================

    private DReport getReport(PrepareReportParameters prp, List<Map<String, Object>> rows) {

        DReport report = new DReport();

        TaskDynamique task = prp.getTask();

        report.setPageBreakRules(task.getPageBreakRules());

        report.setColumnBreakRules(task.getColumnBreakRules());

        // Check which optional columns exist

        boolean includeRowLevel = dynamicQueryPort.existColumn(ROW_LEVEL_COL, rows);

        boolean includeIdTable = dynamicQueryPort.existColumn(ID_TABLE_COL, rows);

        boolean includeIdSection = dynamicQueryPort.existColumn(ID_SECTION_COL, rows);

        boolean includeDescriptionBloc = dynamicQueryPort.existColumn(DESCRIPTION_BLOC_COL, rows);

        boolean includeInfoBloc = dynamicQueryPort.existColumn(INFO_BLOC_COL, rows);

        // Store data flag — bitwise SQL test so combined values (0x03 = SQL|DOCUMENT) and ALL (0xFF)
        // are both honoured. (.NET Run_Base.cs:677 (Store_Type & SQL) == SQL.) Finding #1.

        boolean storeData = task.isStoreData()
                && com.socgen.sgs.api.quark.engine.domain.StoreDataType.hasFlag(
                task.getRun().getRunProperties().getStoreDataTypeCode(),
                com.socgen.sgs.api.quark.engine.domain.StoreDataType.SQL);
        // Tracking state

        int lastIdSection = Integer.MIN_VALUE;

        int lastIdGroupe = Integer.MIN_VALUE;

        int lastIdTable = Integer.MIN_VALUE;

        int lastIdLigne = Integer.MIN_VALUE;

        DSection currentDSection = null;

        DCell currentDCell = null;

        DRow currentDRow = null;

        DTable currentDTable = null;

        Template currentTemplate = null;

        for (Map<String, Object> row : rows) {

            int idGroupe = getIntValue(row, ID_GROUP_COL);

            int idLigne = getIntValue(row, ID_LIGNE_COL);

            String newName = getStringValue(row, NOM_BLOC_COL);

            String data = getStringValue(row, VALEUR_BLOC_COL);

            String templateName = getStringValue(row, TEMPLATE_COL);

            int rowLevel = includeRowLevel ? getIntValue(row, ROW_LEVEL_COL) : Integer.MIN_VALUE;

            int idTable = includeIdTable ? getIntValue(row, ID_TABLE_COL) : Integer.MIN_VALUE;

            int idSection = includeIdSection ? getIntValue(row, ID_SECTION_COL) : Integer.MIN_VALUE;

            String descriptionBloc = includeDescriptionBloc ? getStringValue(row, DESCRIPTION_BLOC_COL) : "";

            String infoBloc = includeInfoBloc ? getStringValue(row, INFO_BLOC_COL) : "";

            // Change detection

            boolean newSection = (idSection != lastIdSection);

            boolean newGroup = (idGroupe != lastIdGroupe);

            boolean newLigne = (idLigne != lastIdLigne);

            boolean newTable = (idTable != lastIdTable);

            lastIdSection = idSection;

            lastIdGroupe = idGroupe;

            lastIdLigne = idLigne;

            lastIdTable = idTable;

            // New section

            if (currentDSection == null || newSection) {

                currentDSection = new DSection();

                report.getSections().add(currentDSection);

                newTable = true;

                newGroup = true;

                currentDTable = null;

            }

            // New group → resolve template

            if (newGroup) {

                if (task.getRun().getTemplates().containsKey(templateName)) {

                    currentTemplate = task.getRun().getTemplates().get(templateName);

                } else {

                    Template newTemplate = new Template();

                    newTemplate.setName(templateName);

                    newTemplate.setSrcName(templateName);

                    task.getRun().getTemplates().put(templateName, newTemplate);

                    currentTemplate = newTemplate;

                }

            }

            // New line or new group → create cell

            if (newLigne || newGroup) {

                currentDCell = new DCell(currentTemplate);

                if (currentTemplate.isAbsolute()) {

                    // Absolute: add directly to section cells

                    currentDSection.getCells().add(currentDCell);

                } else {

                    // Relative: add to table

                    if (currentDTable == null || newTable) {

                        currentDTable = new DTable();

                        currentDTable.setNewPage(task.isNewPageTable());

                        currentDSection.getTables().add(currentDTable);

                        newLigne = true;

                    }

                    if (newLigne) {

                        currentDRow = new DRow();

                        currentDTable.getRows().add(currentDRow);

                        if (rowLevel != Integer.MIN_VALUE) {

                            currentDRow.setLevel(rowLevel);

                        }

                    }

                    currentDRow.getCells().add(currentDCell);

                }

            }

            // Add value and name to current cell

            currentDCell.getValues().add(data);

            currentDCell.getNewNames().add(newName);

            // Store data if configured

            if (storeData) {

                task.getDataNamesValues().add(

                        new com.socgen.sgs.api.quark.engine.domain.DataNameValue(

                                newName, data, descriptionBloc, infoBloc));

            }

        }

        return report;

    }

    // ========================================================================

    // Stage 2: Check_Report

    // Cross-reference: Process_Dynamique.Check_Report() lines 225-295

    // ========================================================================

    private void checkReport(PrepareReportParameters prp, DReport report) {

        TaskDynamique task = prp.getTask();

        boolean activeOverflowTemplate = !task.getOverflowBoxes().isEmpty();

        QxpProject qxpProject = task.getRun().getGabaritTemplate().getQxpProject();

        qxpProject.analyse(task, true);

        List<DSection> sections2Remove = new ArrayList<>();

        for (DSection section : report.getSections()) {

            // Check absolute cells

            List<DCell> cells2Remove = new ArrayList<>();

            for (DCell cell : section.getCells()) {

                cell.setOverflow(activeOverflowTemplate && cell.containsOneNewName(task.getOverflowBoxes()));

                cell.setTElement(evaluateTElement(task, cell));

                if (cell.getTElement() == null) {

                    cells2Remove.add(cell);

                }

            }

            section.getCells().removeAll(cells2Remove);

            // Check relative cells in tables

            List<DTable> tables2Remove = new ArrayList<>();

            for (DTable table : section.getTables()) {

                List<DRow> rows2Remove = new ArrayList<>();

                for (DRow row : table.getRows()) {

                    cells2Remove = new ArrayList<>();

                    for (DCell cell : row.getCells()) {

                        cell.setOverflow(activeOverflowTemplate && cell.containsOneNewName(task.getOverflowBoxes()));

                        cell.setTElement(evaluateTElement(task, cell));

                        if (cell.getTElement() == null) {

                            cells2Remove.add(cell);

                        }

                    }

                    row.getCells().removeAll(cells2Remove);

                    if (row.getCells().isEmpty()) {

                        rows2Remove.add(row);

                    }

                }

                table.getRows().removeAll(rows2Remove);

                if (table.getRows().isEmpty()) {

                    tables2Remove.add(table);

                }

            }

            section.getTables().removeAll(tables2Remove);

            if (section.getTables().isEmpty() && section.getCells().isEmpty()) {

                sections2Remove.add(section);

            }

        }

        report.getSections().removeAll(sections2Remove);

    }


    /**

     * Build and cache the gabarit-template document's project once per run. The template document

     * is uploaded to the pool during the Prepare phase; its structure is fetched and parsed here so

     * the report cells can resolve their specimen boxes against it.

     */

    private void ensureTemplateProject(TaskDynamique task) {

        DocumentDomain template = task.getRun().getGabaritTemplate();

        if (template == null) {

            return;

        }

        documentStructureBusiness.ensureProject(task.getRun(), template);

    }

    /**

     * Evaluate the TElement for a cell from the gabarit template project.

     * Selects srcName or srcNameOverflow based on cell.overflow flag.

     *

     * Cross-reference: TElement_Helper.Evaluate_TElement()

     */

    private TElement evaluateTElement(TaskDynamique task, DCell cell) {

        String srcName;

        if (cell.isOverflow()) {

            srcName = cell.getTemplate().getSrcNameOverflow();

        } else {

            srcName = cell.getTemplate().getSrcName();

        }

        if (srcName == null || srcName.isBlank()) {

            return null;

        }

        QxpProject qxpProject = task.getRun().getGabaritTemplate().getQxpProject();

        Map<String, TElement> elements = qxpProject.getElements();

        if (elements != null && elements.containsKey(srcName)) {

            return elements.get(srcName);

        } else {

            log.warn("Template element [{}] not found for cell names [{}]",

                    srcName, String.join("/", cell.getNewNames()));

            return null;

        }

    }

    // ========================================================================

    // Stage 3: Prepare_Report

    // Cross-reference: Process_Dynamique.Prepare_Report() lines 300-530

    // ========================================================================

    private void prepareReport(PrepareReportParameters prp, DReport report) {

        TaskDynamique task = prp.getTask();

        // Evaluate available height between anchors

        if (task.getStartAnchor() != null && task.getEndAnchor() != null) {

            if (task.getStartAnchor().getBottom().compareTo(task.getEndAnchor().getTop()) < 0
                    && task.getStartAnchor().getLeft().compareTo(task.getStartAnchor().getRight()) < 0) {

                prp.setAvailableHeight(task.getEndAnchor().getTop().subtract(task.getStartAnchor().getBottom()));

                prp.setAvailableWidth(task.getEndAnchor().getLeft().subtract(task.getStartAnchor().getRight()));

            } else {

                throw new EngineException(RunError.BLOQUANTE, String.format(
                        "La position des ancres est incohérente l'ancre %s et plus basse que l'ancre %s",
                        task.getStartAnchor().getName(), task.getEndAnchor().getName()));

            }

        }

        for (DSection section : report.getSections()) {

            prepareReportSection(prp, report, section);

        }

        // If control overflow, memorize box names

        if (task.isControlOverflow()) {

            task.getBoxNames().clear();

            for (DSection section : report.getSections()) {

                for (DCell cell : section.getCells()) {

                    task.getBoxNames().addAll(cell.getNewNames());

                }

                for (DTable table : section.getTables()) {

                    for (DRow row : table.getRows()) {

                        for (DCell cell : row.getCells()) {

                            task.getBoxNames().addAll(cell.getNewNames());

                        }

                    }

                }

            }

        }

        report.getInfo().setNbPage(prp.getPage());

    }

    private void prepareReportSection(PrepareReportParameters prp, DReport report, DSection section) {

        TaskDynamique task = prp.getTask();

        int cellLogicalId = 0;

        boolean firstTable = true;

        BigDecimal tableHeight = BigDecimal.ZERO;

        BigDecimal tableWidth = BigDecimal.ZERO;

        BigDecimal maxWidth = BigDecimal.ZERO;

        DPoint cursor = new DPoint(task.getStartAnchor().getRight(), task.getStartAnchor().getBottom());

        DPoint cursorBreak = new DPoint(cursor);

        prp.reset();

        prp.setPage(prp.getPage() + 1);

        DMasterPage master = DMasterPage.DEFAULT;

        section.getInfo().setMasterPage(master);

        List<DRow> currentPageBreakRows = new ArrayList<>();

        List<DRow> currentColumnBreakRows = new ArrayList<>();

        // ---- Prepare absolute cells ----

        for (DCell cell : section.getCells()) {

            cell.getInfo().setPage(prp.getPage());

            cell.setLogicalId(++cellLogicalId);

            cell.getInfo().setZone(DynamiqueGeometryHelper.getZone(null, cell));

            int absRepeat = cell.getTemplate().getAbsoluteRepeat();

            if (AbsoluteRepeatType.hasOtherPage(absRepeat)) {

                prp.getRepeatedCells().add(cell);

                if (!AbsoluteRepeatType.hasFirstPage(absRepeat)
                        && absRepeat != 0) {

                    cell.downgradeGeneration();

                }

            }

            if (AbsoluteRepeatType.hasLastPage(absRepeat)) {

                prp.getLastCells().add(cell);

            }

        }

        // Remove absolute cells not on first page or default (raw 0 == .NET Absolute_Repeat_Type.Default)

        section.getCells().removeIf(cell ->

                !(AbsoluteRepeatType.hasFirstPage(cell.getTemplate().getAbsoluteRepeat())

                        || cell.getTemplate().getAbsoluteRepeat() == 0));
        // ---- Process relative cells in tables ----

        for (DTable table : section.getTables()) {

            if (!firstTable) {

                if (table.isNewPage()) {

                    prp.setPage(prp.getPage() + 1);

                    tableHeight = BigDecimal.ZERO;

                    prp.setColumn(1);

                    tableWidth = BigDecimal.ZERO;

                    maxWidth = BigDecimal.ZERO;

                    addAbsoluteCells(prp, section);

                    cursor.reset(task.getStartAnchor().getRight(), task.getStartAnchor().getBottom());

                }

            } else {

                firstTable = false;

                prp.setColumn(1);

                tableWidth = BigDecimal.ZERO;

                maxWidth = BigDecimal.ZERO;

            }

            int maxRows = table.getRows().size();

            for (int indexRow = 0; indexRow < maxRows; indexRow++) {

                DRow row = table.getRows().get(indexRow);

                // Handle break rows (page/column header repetition)

                if (row.isPageBreak() || row.isColumnBreak()) {

                    prp.getRows2Remove().add(row);

                    if (row.isPageBreak()) {

                        int existingIndex = findBreakRowByLevel(currentPageBreakRows, row.getLevel());

                        if (existingIndex >= 0) {

                            DRow oldRow = currentPageBreakRows.get(existingIndex);

                            transferRowCellsInfo(oldRow, row);

                            currentPageBreakRows = new ArrayList<>(currentPageBreakRows);

                            currentPageBreakRows.set(existingIndex, row);

                        } else {

                            prepareReportCells(prp, row, cursorBreak);

                            currentPageBreakRows = new ArrayList<>(currentPageBreakRows);

                            currentPageBreakRows.add(row);

                            cursorBreak.setLeft(task.getStartAnchor().getRight());

                            cursorBreak.setTop(cursorBreak.getTop().add(row.getInfo().getHeight()));

                        }

                    }

                    if (row.isColumnBreak()) {

                        int existingIndex = findBreakRowByLevel(currentColumnBreakRows, row.getLevel());

                        if (existingIndex >= 0) {

                            DRow oldRow = currentColumnBreakRows.get(existingIndex);

                            transferRowCellsInfo(oldRow, row);

                            currentColumnBreakRows = new ArrayList<>(currentColumnBreakRows);

                            currentColumnBreakRows.set(existingIndex, row);

                        } else {

                            prepareReportCells(prp, row, cursorBreak);

                            currentColumnBreakRows = new ArrayList<>(currentColumnBreakRows);

                            currentColumnBreakRows.add(row);

                            cursorBreak.setLeft(task.getStartAnchor().getRight());

                            cursorBreak.setTop(cursorBreak.getTop().add(row.getInfo().getHeight()));

                        }

                    }

                    downgradeReportCells(row);

                    continue;

                }

                // Normal row processing

                row.setPageBreakRows(currentPageBreakRows);

                row.setColumnBreakRows(currentColumnBreakRows);

                prepareReportCells(prp, row, cursor);

                tableHeight = tableHeight.add(row.getInfo().getHeight());

                // Check if overflow

                if (tableHeight.compareTo(prp.getAvailableHeight()) > 0) {

                    if (prp.getColumn() < task.getNbColumn()) {

                        // New column

                        prp.setColumn(prp.getColumn() + 1);

                        tableWidth = tableWidth.add(maxWidth).add(task.getColumnSpace());

                        DynamiquePageBreakHelper.updateRows(report, table.getRows(), row, prp, false, tableWidth);

                        tableHeight = prp.getCurrentTableHeight();

                        maxWidth = prp.getCurrentTableWidth();

                        indexRow += prp.getNbRowsAdded();

                        maxRows += prp.getNbRowsAdded();

                    } else {

                        // New page

                        prp.setPage(prp.getPage() + 1);

                        prp.setColumn(1);

                        DynamiquePageBreakHelper.updateRows(report, table.getRows(), row, prp, true, BigDecimal.ZERO);

                        tableHeight = prp.getCurrentTableHeight();

                        tableWidth = BigDecimal.ZERO;

                        maxWidth = prp.getCurrentTableWidth();

                        indexRow += prp.getNbRowsAdded();

                        maxRows += prp.getNbRowsAdded();

                        addAbsoluteCells(prp, section);

                    }

                } else {

                    maxWidth = maxWidth.max(row.getInfo().getWidth());

                }

                cursor.setLeft(task.getStartAnchor().getRight().add(tableWidth));

                cursor.setTop(task.getStartAnchor().getBottom().add(tableHeight));

            }

            // Remove break rows from table

            table.getRows().removeAll(prp.getRows2Remove());

        }

        // Add last absolute cells

        addLastAbsoluteCells(prp, section);

    }

    private void prepareReportCells(PrepareReportParameters prp, DRow row, DPoint cursor) {

        BigDecimal rowHeight = BigDecimal.ZERO;

        BigDecimal rowWidth = BigDecimal.ZERO;

        boolean heightPercent = row.getInfo().getHeight().compareTo(BigDecimal.ZERO) != 0;

        for (DCell cell : row.getCells()) {

            cell.getInfo().setPage(prp.getPage());

            BigDecimal cellHeight;

            if (heightPercent) {

                cellHeight = MathHelper.getValPercent(row.getInfo().getHeight(), cell.getTemplate().getHeightPercent());

            } else {

                cellHeight = DynamiqueGeometryHelper.getCellHeightWithTop(cell);

            }

            rowHeight = rowHeight.max(cellHeight);

            rowWidth = rowWidth.add(DynamiqueGeometryHelper.getCellWidthWithLeft(cell));

            cell.getInfo().setZone(DynamiqueGeometryHelper.getZoneAndUpdateCursor(cursor, cell));

        }

        row.getInfo().setHeight(rowHeight);

        row.getInfo().setWidth(rowWidth);

        row.getInfo().setPage(prp.getPage());

        row.getInfo().setColumn(prp.getColumn());

    }

    private void downgradeReportCells(DRow row) {

        for (DCell cell : row.getCells()) {

            cell.downgradeGeneration();

        }

    }

    private void transferRowCellsInfo(DRow oldRow, DRow newRow) {

        newRow.setInfo(oldRow.getInfo());

        for (int i = 0; i < oldRow.getCells().size() && i < newRow.getCells().size(); i++) {

            newRow.getCells().get(i).setInfo(oldRow.getCells().get(i).getInfo());

        }

    }

    private void addAbsoluteCells(PrepareReportParameters prp, DSection section) {

        for (DCell srcCell : prp.getRepeatedCells()) {

            DCell newCell = srcCell.cloneCell();

            newCell.getInfo().setPage(prp.getPage());

            section.getCells().add(newCell);

        }

    }

    private void addLastAbsoluteCells(PrepareReportParameters prp, DSection section) {

        List<DCell> cellsInLastPage = section.getCells().stream()

                .filter(c -> c.getInfo().getPage() == prp.getPage())

                .collect(Collectors.toList());

        for (DCell srcCell : prp.getLastCells()) {

            boolean alreadyExists = cellsInLastPage.stream()

                    .anyMatch(c -> c.equalsCell(srcCell));

            if (!alreadyExists) {

                DCell newCell = srcCell.cloneCell();

                newCell.getInfo().setPage(prp.getPage());

                section.getCells().add(newCell);

            }

        }

    }

    private int findBreakRowByLevel(List<DRow> breakRows, int level) {

        for (int i = 0; i < breakRows.size(); i++) {

            if (breakRows.get(i).getLevel() == level) {

                return i;

            }

        }

        return -1;

    }

    // ========================================================================

    // Stage 4: Render_Boxes

    // Cross-reference: Process_Dynamique.Render_Boxes() lines 535-610

    // ========================================================================

    private void renderBoxes(PrepareReportParameters prp, DReport report) {

        TaskDynamique task = prp.getTask();

        int nbNewPage;

        if (report == null) {

            nbNewPage = 1;

        } else {

            nbNewPage = report.getInfo().getNbPage();

        }

        // 1. Create new pages

        for (int i = 0; i < nbNewPage; i++) {

            BlocPage blocPage = new BlocPage(task,

                    String.format(NEW_PAGE_PATTERN, task.getDestinationBlocName(), i));

            blocPage.setAction(BlocActionEnum.CREATE);

            blocPage.setRelativePage(i);

            task.getBlocsModify().put(blocPage.getName(), blocPage);

        }

        // 2. Remove old pages

        int nbAnciennePage = task.getNbAnciennePage();

        for (int i = 0; i < nbAnciennePage; i++) {

            int relativeRemovePage = nbNewPage + i;

            BlocPage blocPage = new BlocPage(task,

                    String.format(NEW_PAGE_PATTERN, task.getDestinationBlocName(), relativeRemovePage));

            blocPage.setAction(BlocActionEnum.REMOVE);

            blocPage.setRelativePage(relativeRemovePage);

            task.getBlocsModify().put(blocPage.getName(), blocPage);

        }

        // 3. Move start anchor to first new page

        BlocBox blocStart = TElementHelper.getMoveAnchor(task, task.getStartAnchor(), 0);

        if (blocStart != null) {

            blocStart.setPagination(true);

            task.getBlocsModify().put(blocStart.getName(), blocStart);

        }

        // 4. Move end anchor to last new page

        BlocBox blocEnd = TElementHelper.getMoveAnchor(task, task.getEndAnchor(), nbNewPage - 1);

        if (blocEnd != null) {

            blocEnd.setPagination(true);

            task.getBlocsModify().put(blocEnd.getName(), blocEnd);

        }

        // 5. Create blocs from report cells

        if (report != null) {

            for (DSection section : report.getSections()) {

                // Absolute cells

                for (DCell cell : section.getCells()) {

                    addDCellBlocs(cell, task);

                }

                // Relative cells

                for (DTable table : section.getTables()) {

                    for (DRow row : table.getRows()) {

                        for (DCell cell : row.getCells()) {

                            addDCellBlocs(cell, task);

                        }

                    }

                }

            }

        }

    }

    /**

     * Convert a DCell into bloc(s) and add to the task.

     *

     * Cross-reference: Process_Dynamique.Add_DCell_Blocs()

     */

    private void addDCellBlocs(DCell dCell, TaskDynamique task) {

        try {

            BlocBase bloc = TElementHelper.getBloc(dCell, task);

            if (bloc != null) {

                if (task.getBlocsModify().containsKey(bloc.getName())) {

                    log.warn("Duplicate bloc name [{}] in task [{}]", bloc.getName(), task.getId());

                } else {

                    task.getBlocsModify().put(bloc.getName(), bloc);

                }

            } else {

                log.warn("Null bloc generated for cell in task [{}]", task.getId());

            }

        } catch (Exception ex) {

            log.error("Error adding DCell bloc in task [{}]: {}", task.getId(), ex.getMessage());

        }

    }

    // ========================================================================

    // Utility methods

    // ========================================================================

    private int getIntValue(Map<String, Object> row, String column) {

        Object val = row.get(column);

        if (val == null) return Integer.MIN_VALUE;

        if (val instanceof Number) return ((Number) val).intValue();

        try {

            return Integer.parseInt(val.toString().trim());

        } catch (NumberFormatException e) {

            return Integer.MIN_VALUE;

        }

    }

    private String getStringValue(Map<String, Object> row, String column) {

        Object val = row.get(column);

        return val != null ? val.toString() : "";

    }

}
```


## 18. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImpl.java`

SHA-256: `sha256-0ceb186a14416667169acbbbcf466c843606bd305656665af634100ddcf07317`

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunTask;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.exception.EngineException;
import com.socgen.sgs.api.quark.engine.service.ProcessTasksService;
import com.socgen.sgs.api.quark.engine.service.task.TaskPostProcessService;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Implements the Prepare phase and the 3-pass task processing loop.
 * Cross-reference: .NET Run_Base.Prepare() and Run_Base.Process().
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ProcessTasksServiceImpl implements ProcessTasksService {

    /** RunError categories, matching .NET Error_Type: 1=Unspecified, 2=Critique, 3=Bloquante. */
    private static final int CRITIQUE = RunError.CRITIQUE;

    private final TaskProcessService taskProcessService;
    private final TaskPostProcessService taskPostProcessService;

    /** Max blocs per modify step (.NET EngineCoreSetting Step_Limit). Configurable via application.yaml. */
    @Value("${engine.step-limit:5000}")
    private int stepLimit;

    /**
     * Prepare phase — call prepare() on EVERY task (not just todo), before processing.
     * Per-task failures are recorded as Critique errors and flag the task in error.
     * Cross-reference: .NET Run_Base.Prepare() (iterates _tasks.Values).
     */
    @Override
    public void prepareTasks(Run run) {
        log.info("Preparing tasks for runId: {}", run.getId());

        for (TaskBase task : run.getTasks().values()) {
            try {
                log.debug("Preparing task {}", task.getId());
                task.prepare();
            } catch (Exception ex) {
                task.setInError(true);
                run.getErrors().add(new RunError(CRITIQUE,
                        "Erreur lors de la preparation de la tache " + task.getId() + " : " + ex.getMessage()));
                log.error("Error preparing task {}: {}", task.getId(), ex.getMessage());
                log.debug("Task {} preparation failure detail", task.getId(), ex);
            }
        }

        log.info("Task preparation completed for runId: {}", run.getId());
    }

    @Override
    public void processTasks(Run run) {
        log.info("Processing tasks for runId: {}", run.getId());

        // Fresh step aggregator for this processing pass.
        // Cross-reference: .NET Run_Base.Process() — `_run_Task = new Run_Task(this)`.
        RunTask runTask = new RunTask(run);
        runTask.setSplitStepBoxNumber(stepLimit); // configurable step limit
        run.setRunTask(runTask);

        // Pass 1: Reset + Process each task
        for (TaskBase task : run.getTasks().values()) {
            if (!task.isTodo()) continue;
            if (task.isInError()) continue;
            try {
                // A task in degraded mode is NOT reset/processed; it is reported as a fail-soft error.
                // Cross-reference: .NET Process() — Errors.Add(Critique, TaskFailSoftMode) and skip.
                if (task.isModeDegrade()) {
                    run.getErrors().add(new RunError(CRITIQUE,
                            "Tache " + task.getId() + " en mode degrade (fail-soft) : non traitee"));
                    log.warn("Task {} is in degraded mode (fail-soft), not processed", task.getId());
                    continue;
                }
                log.debug("Processing task {}", task.getId());
                task.resetProcess();
                taskProcessService.process(task);
                log.debug("Task {} produced {} blocsUpdate, {} blocsModify",
                        task.getId(), task.getBlocsUpdate().size(), task.getBlocsModify().size());
            } catch (EngineException controlled) {
                task.setInError(true);
                EngineException wrapped = new EngineException(CRITIQUE,
                        "Erreur lors du processing de la tache " + task.getId()
                                + " de " + run.getDebugInfo(), controlled);
                run.getErrors().add(new RunError(wrapped.getCategory(), wrapped.getSafeMessageChain()));
                log.error("Controlled processing failure for task [{}], run [{}], category [{}]",
                        task.getId(), run.getId(), wrapped.getCategory());
                log.debug("Controlled task processing failure detail", wrapped);
            } catch (Exception ex) {
                task.setInError(true);
                run.getErrors().add(new RunError(CRITIQUE,
                        "Erreur lors du traitement de la tache " + task.getId() + " : " + ex.getMessage()));
                log.error("Error processing task {}: {}", task.getId(), ex.getMessage());
                log.debug("Task {} processing failure detail", task.getId(), ex);
            }
        }

        // Pass 2: Post-process each task (e.g. DID, which needs all other tasks done first)
        for (TaskBase task : run.getTasks().values()) {
            if (!task.isTodo()) continue;
            if (task.isInError() || task.isModeDegrade()) continue;
            try {
                log.debug("Post-processing task {}", task.getId());
                taskPostProcessService.postProcess(task);
                log.debug("Task {} post-process: {} blocsUpdate, {} blocsModify",
                        task.getId(), task.getBlocsUpdate().size(), task.getBlocsModify().size());
            } catch (Exception ex) {
                task.setInError(true);
                run.getErrors().add(new RunError(CRITIQUE,
                        "Erreur lors du post-traitement de la tache " + task.getId() + " : " + ex.getMessage()));
                log.error("Error post-processing task {}: {}", task.getId(), ex.getMessage());
                log.debug("Task {} post-processing failure detail", task.getId(), ex);
            }
        }

        // Pass 3: Verify — a task with no blocs is an error; otherwise register its blocs
        for (TaskBase task : run.getTasks().values()) {
            if (!task.isTodo()) continue;
            if (task.isInError() || task.isModeDegrade()) continue;
            if (task.getBlocsUpdate().isEmpty() && task.getBlocsModify().isEmpty()) {
                // .NET Run_Base.Process pass 3: Errors.Add(TaskSansBloc, ...) → Unspecified (1), not Critique.
                run.getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "La tache " + task.getId() + " ne genere aucun bloc"));
                log.warn("Task {} has no blocs after processing", task.getDebugInfo());
            } else {
                run.getRunTask().addTask(task);
                log.debug("Task {} added to RunTask with {} blocsUpdate, {} blocsModify",
                        task.getId(), task.getBlocsUpdate().size(), task.getBlocsModify().size());
            }
        }

        log.info("Task processing completed for runId: {}", run.getId());
    }
}
```


## 19. `src/main/java/com/socgen/sgs/api/quark/engine/business/LoadTaskDocumentsBusiness.java`

SHA-256: `sha256-d47d7f29f86511a3216e185a7de73af923b1fe5f2c07105ff55eeb6b8f02306e`

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDocument;
import com.socgen.sgs.api.quark.engine.domain.task.TaskQxpPrevious;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import com.socgen.sgs.api.quark.engine.infra.dao.GetDocumentDao;
import com.socgen.sgs.api.quark.engine.infra.dao.GetLastQxpCertifieDao;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.config.QxpsProperties;
import com.socgen.sgs.api.quark.engine.infra.pdf.PdfSplitter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * Loads each task's reference/previous document during the Prepare phase and uploads it to the
 * QuarkXPress pool (PDFs are split per page), so the task strategies can read/insert it.
 *
 * <p>This is the service → business → (dao + infra) bridge for what .NET does inside
 * {@code Task_Document.Prepare()} and {@code Task_QXP_Previous.Prepare()} (document loading is
 * intentionally kept out of the Java domain {@code prepare()} methods). All pool writes go through
 * the Quark API ({@link FilePoolPort#addFile}) — never local files — honouring the Kubernetes
 * remote-host constraint.
 *
 * <p>Cross-reference: .NET Task_Document.Prepare (Get_Document + Addfile + PDF split) and
 * Task_QXP_Previous.Prepare (Get_Last_Qxp_Certifie + Addfile).
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class LoadTaskDocumentsBusiness {

    private static final String PDF_PAGE_NAME_PATTERN = "%s_%d_p%d.pdf"; // prefix, id, page (1-based)
    private static final String PREVIOUS_TYPE_ANY = "any";
    private static final String PREVIOUS_TYPE_SAME = "same";

    private final GetDocumentDao getDocumentDao;
    private final GetLastQxpCertifieDao getLastQxpCertifieDao;
    private final FilePoolPort filePool;
    private final PdfSplitter pdfSplitter;
    private final QxpsProperties qxpsProperties;

    /** Load + pool-upload documents for every task that needs one. */
    public void loadDocuments(Run run) {
        String basePath = qxpsProperties.getPool().getDefaultPath();
        for (TaskBase task : run.getTasks().values()) {
            try {
                if (task instanceof TaskDocument) {
                    loadDocumentTask(run, (TaskDocument) task, basePath);
                } else if (task instanceof TaskQxpPrevious) {
                    loadQxpPreviousTask(run, (TaskQxpPrevious) task, basePath);
                }
            } catch (Exception e) {
                task.setInError(true);
                run.getErrors().add(new RunError(RunError.CRITIQUE,
                        "Erreur lors du chargement du document de la tache " + task.getId() + " : " + e.getMessage()));
                log.error("Error loading document for task {}: {}", task.getId(), e.getMessage(), e);
            }
        }
    }

    // ------------------------------------------------------------------
    // TaskDocument — Cross-reference: .NET Task_Document.Prepare
    // ------------------------------------------------------------------

    private void loadDocumentTask(Run run, TaskDocument task, String basePath) {
        // .NET: (ToLoad || Todo) && IsSet(Id_Sous_Categorie, false)  (i.e. sous-categorie != 0)
        if (!(task.isToLoad() || task.isTodo()) || task.getIdSousCategorie() == 0) {
            return;
        }

        RunProperties props = run.getRunProperties();
        String cacheKey = String.join("|",
                value(task.getIdSousCategorie()), value(props.getIdFndCode()),
                value(props.getIdUnitCode()), value(props.getSociete()), value(props.getIdLangue()));
        DocumentDomain doc = run.requireExecutionContext().getOrLoadReferenceDocument(cacheKey,
                () -> getDocumentDao.getDocument(
                        task.getIdSousCategorie(), props.getIdFndCode(), props.getIdUnitCode(),
                        props.getSociete(), props.getIdLangue(), props.getDateEcheance()));

        if (doc == null) {
            // .NET Errors.Add(Document_Null, ...) → Unspecified severity.
            run.getErrors().add(new RunError(RunError.UNSPECIFIED,
                    "Document_Null: aucun document pour la sous-categorie " + task.getIdSousCategorie()
                            + " (tache " + task.getId() + ")"));
            log.warn("No document found for task {} (sousCategorie {})", task.getId(), task.getIdSousCategorie());
            return;
        }

        completePaths(doc, run, basePath);
        task.setDocument(doc);
        if (doc.evaluateModeDegrade(run.getSizeLimitBeforeFailSoft())) {
            doc.setModeDegrade(true);
            log.warn("QXP task document [{}] exceeds the configured fail-soft limit for run [{}]",
                    doc.getId(), run.getId());
        }

        SubTaskTypeEnum subType = task.getSubTaskType();
        if (subType == SubTaskTypeEnum.FILE_PDF) {
            loadPdfPages(doc, run, basePath);
        } else if (subType == SubTaskTypeEnum.FILE_QXP_DATA) {
            // DOC EOS explicitly uploads during Prepare; XML/project remains lazy.
            filePool.addFile(run.requireExecutionContext(), doc.getFilePoolPath(), doc.getData());
        } else {
            // IMG / DOC / RTF / XTG — upload the file as-is.
            filePool.addFile(run.requireExecutionContext(), doc.getFilePoolPath(), doc.getData());
        }
    }

    /** PDF: split into pages, upload each page to the pool, expose the per-page absolute paths. */
    private void loadPdfPages(DocumentDomain doc, Run run, String basePath) {
        List<byte[]> pages = pdfSplitter.split(doc.getData());
        List<String> pdfFiles = new ArrayList<>();
        for (int i = 0; i < pages.size(); i++) {
            String pageName = String.format(PDF_PAGE_NAME_PATTERN, doc.getPrefix(), doc.getId(), i + 1);
            filePool.addFile(run.requireExecutionContext(), run.getPoolPath(pageName), pages.get(i));
            // The strategy uses these entries directly as the picture content value (absolute host path).
            pdfFiles.add(run.getPoolPathAbsolute(pageName, basePath));
        }
        doc.setPdfFiles(pdfFiles);
        log.info("Loaded {} PDF page(s) for document {}", pdfFiles.size(), doc.getId());
    }

    // ------------------------------------------------------------------
    // TaskQxpPrevious — Cross-reference: .NET Task_QXP_Previous.Prepare
    // ------------------------------------------------------------------

    private void loadQxpPreviousTask(Run run, TaskQxpPrevious task, String basePath) {
        // .NET: this.Todo && IsNull(this.Document)  (the null-check eases standalone debugging).
        if (!task.isTodo() || task.getDocument() != null) {
            return;
        }

        RunProperties props = run.getRunProperties();
        int previousTypeRapport = resolvePreviousTypeRapport(props, task.getPreviousTypeRapport());

        String cacheKey = "cert|" + props.getIdSuivi() + "|" + previousTypeRapport;
        DocumentDomain doc = run.requireExecutionContext().getOrLoadPreviousDocument(cacheKey,
                () -> getLastQxpCertifieDao.getLastQxpCertifie(props.getIdSuivi(), previousTypeRapport));
        if (doc == null) {
            // .NET Errors.Add(Document_LastQxp_Null, ...) then Todo = false.
            run.getErrors().add(new RunError(RunError.UNSPECIFIED,
                    "Document_LastQxp_Null: aucun QXP certifie precedent pour le suivi " + props.getIdSuivi()
                            + " (type rapport " + previousTypeRapport + ", tache " + task.getId() + ")"));
            log.warn("No previous certified QXP for task {} (suivi {}, typeRapport {})",
                    task.getId(), props.getIdSuivi(), previousTypeRapport);
            task.setTodo(false);
            return;
        }

        completePaths(doc, run, basePath);
        task.setDocument(doc);
        if (doc.evaluateModeDegrade(run.getSizeLimitBeforeFailSoft())) {
            doc.setModeDegrade(true);
            log.warn("Previous QXP document [{}] exceeds the configured fail-soft limit for run [{}]",
                    doc.getId(), run.getId());
        }
    }

    /**
     * Resolve the certified report type to search for.
     * .NET: default = current run's report type; "any" → 0; "same" → keep default; else parse int.
     */
    private int resolvePreviousTypeRapport(RunProperties props, String previousType) {
        int type = props.getTypeRapport() != null ? props.getTypeRapport().getCode() : 0;
        if (previousType != null && !previousType.isBlank()) {
            if (PREVIOUS_TYPE_ANY.equals(previousType)) {
                type = 0;
            } else if (!PREVIOUS_TYPE_SAME.equals(previousType)) {
                try {
                    int parsed = Integer.parseInt(previousType.trim());
                    if (parsed > 0) {
                        type = parsed;
                    }
                } catch (NumberFormatException e) {
                    log.warn("Invalid previousTypeRapport [{}], using default {}", previousType, type);
                }
            }
        }
        return type;
    }

    // ------------------------------------------------------------------
    // Shared helpers
    // ------------------------------------------------------------------

    /** Fill pool-relative path + absolute (Windows) host path from the run pool + base path. */
    private void completePaths(DocumentDomain doc, Run run, String basePath) {
        String fileName = doc.getFileName();
        doc.setFilePoolPath(run.getPoolPath(fileName));
        doc.setFileFullPath(run.getPoolPathAbsolute(fileName, basePath));
    }

    private static String value(Object value) {
        return value == null ? "" : value.toString();
    }
}
```


## 20. `src/main/java/com/socgen/sgs/api/quark/engine/business/LoadTemplatesBusiness.java`

SHA-256: `sha256-b8a3f9ac8cf26bb0e51d8f6a5c268b9e8bf23a52f13410f42925ccfd3c186613`

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
            gabaritTemplate.setFilePoolPath(run.getPoolPath(gabaritTemplate.getFileName()));

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


## 21. `src/main/java/com/socgen/sgs/api/quark/engine/domain/task/TaskDynamique.java`

SHA-256: `sha256-c01a587925cc5243ef33c902f89a808c7b58b054fc3c7fcd54c22c45f0fec787`

```java
package com.socgen.sgs.api.quark.engine.domain.task;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBreakRules;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

/** Represents a dynamic task that adds blocs/tables/pages to a QuarkXPress document. */
@Getter
@Setter
public class TaskDynamique extends TaskAnchor {

    private String sql;
    private DBreakRules pageBreakRules = DBreakRules.DEFAULT;
    private DBreakRules columnBreakRules = DBreakRules.DEFAULT;
    private boolean controlOverflow = false;
    private boolean storeData = false;
    private boolean newPageTable = false;
    private int nbColumn = 1;
    private BigDecimal columnSpace = BigDecimal.ZERO;

    private final List<String> boxNames = new ArrayList<>();
    private final List<String> overflowBoxes = new ArrayList<>();

    private FilePoolPort filePoolService;

    public TaskDynamique(int id, Run run) {
        super(id, run);
    }

    @Override
    public void prepare() {
        if (this.isTodo() && filePoolService != null) {
            // Upload the gabarit TEMPLATE (not the source gabarit) into the QXPS pool.
            // Parity: .NET Task_Dynamique.Prepare → Addfile(this.Run.Gabarit_Template.FilePoolPath,
            // this.Run.Gabarit_Template.Data). Finding #22.
            DocumentDomain gabaritTemplate = this.getRun().getGabaritTemplate();
            if (gabaritTemplate == null) {
                // .NET raises MSG_Gabarit_Template_NULL; fail loudly rather than NPE / silently
                // uploading the wrong document.
                throw new IllegalStateException(
                        "Gabarit_Template is null for dynamic task " + this.getId()
                                + " in run " + this.getRun().getId()
                                + " — id_gabarit_template must be set and loaded before prepare()");
            }
            filePoolService.addFile(this.getRun().requireExecutionContext(),
                    gabaritTemplate.getFilePoolPath(), gabaritTemplate.getData());
        }
    }


    public void setNbColumn(int value) {
        if (value > 0) {
            this.nbColumn = value;
        }
    }

    public void setColumnSpace(BigDecimal value) {
        if (value != null && value.compareTo(BigDecimal.ZERO) > 0) {
            this.columnSpace = value;
        }
    }
}
```


## 22. `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/DocumentTaskProcessStrategy.java`

SHA-256: `sha256-441e78102405e93f73be8d6b06b74bd62736e992bff4260282c91977587f5e41`

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocPage;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocTable;
import com.socgen.sgs.api.quark.engine.domain.element.TBox;
import com.socgen.sgs.api.quark.engine.domain.element.TElement;
import com.socgen.sgs.api.quark.engine.domain.element.TGroup;
import com.socgen.sgs.api.quark.engine.domain.element.TTable;
import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDocument;
import com.socgen.sgs.api.quark.engine.domain.task.TaskImageOffset;
import com.socgen.sgs.api.quark.engine.domain.task.TaskImagePosition;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.enums.StaticTElementNameEnum;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessStrategy;
import lombok.extern.slf4j.Slf4j;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/**
 * Strategy for processing TaskDocument (document/image insertion into blocs).
 * Handles document formats: IMG, PDF, DOC/RTF/XTG, QXP_Data.
 *
 * <p>Each format has distinct processing logic matching .NET Process_Document.cs exactly:
 * <ul>
 *   <li>IMG: Get TElement template, set image path, create BlocBox in blocsModify</li>
 *   <li>PDF: Multi-page with UPDATE/CREATE logic based on existing blocs in gabarit</li>
 *   <li>DOC/RTF/XTG: Get TElement template, set file path with "file:" prefix, create BlocBox</li>
 *   <li>QXP_Data (value mode): Extract value from source document XML, create BlocBox in blocsUpdate</li>
 *   <li>QXP_Data (style mode): Analyse source project, clone TElement, create bloc in blocsModify</li>
 * </ul>
 *
 * Cross-reference: QXP.Engine.Core.Business.Process_Document
 */
@Component
@Slf4j
@RequiredArgsConstructor
public class DocumentTaskProcessStrategy implements TaskProcessStrategy<TaskDocument> {

    private final DocumentStructureBusiness documentStructureBusiness;

    // Constants matching .NET Process_Document
    private static final String SOURCE_FILE_ABSOLU_PATTERN = "%s";
    private static final String SOURCE_FILE_DOC_POOL_PATTERN = "file:%s";
    private static final String PDF_BLOC_NAME_PATTERN = "%s_%d";    // 0=prefix, 1=bloc number
    private static final String PDF_PAGE_NAME_PATTERN = "P%d_%s";   // 0=page, 1=bloc name
    private static final String PICTURE_ROTATION_90 = "90";

    @Override
    public Class<TaskDocument> getTaskType() {
        return TaskDocument.class;
    }

    @Override
    public void process(TaskDocument task) {
        log.debug("DocumentTaskProcessStrategy processing task [{}] format={}",
                task.getId(), task.getFormatDocument());

        // Validate destination bloc name
        if (task.getDestinationBlocName() == null || task.getDestinationBlocName().isBlank()) {
            log.warn("Missing destinationBlocName for document task [{}], skipping", task.getId());
            return;
        }

        BlocBox blocBox = null;

        SubTaskTypeEnum subTaskType = task.getSubTaskType();
        if (subTaskType == null) {
            log.warn("Document task [{}] has null sub-task type, skipping", task.getId());
            return;
        }

        switch (subTaskType) {
            case FILE_IMG:
                blocBox = processImg(task);
                break;
            case FILE_PDF:
                processFilePdf(task);
                break;
            case FILE_DOC:
            case FILE_RTF:
            case FILE_XTG:
                blocBox = processDocumentFile(task);
                break;
            case FILE_QXP_DATA:
                processFileQxpData(task);
                break;
            default:
                log.warn("Unsupported sub-task type [{}] for document task [{}]",
                        subTaskType, task.getId());
                return;
        }

        // IMG and DOC/RTF/XTG return a single blocBox to add to blocsModify
        // PDF and QXP_Data handle their own bloc additions internally
        if (blocBox != null) {
            task.getBlocsModify().put(blocBox.getName(), blocBox);
        }
    }

    // ========================================================================
    // IMG format
    // Cross-reference: Process_Document.cs lines 43-48
    // ========================================================================

    /**
     * IMG format: Get TElement template, set image file path, handle rotation.
     * Uses Static_TElement_Name.IMG template.
     * Action is NOT explicitly set (uses default from BlocBase constructor = NONE).
     */
    private BlocBox processImg(TaskDocument task) {
        log.debug("DocumentTaskProcessStrategy IMG: task [{}]", task.getId());

        DocumentDomain doc = task.getDocument();
        if (doc == null) {
            log.warn("IMG task [{}] has no document loaded, skipping", task.getId());
            return null;
        }

        // Get a clone of the IMG TElement template
        TElement tElement = TElementHelper.getTElement(
                StaticTElementNameEnum.IMG, task.getDestinationBlocName());
        if (!(tElement instanceof TBox)) {
            log.warn("IMG task [{}] could not get TBox template", task.getId());
            return null;
        }

        TBox tBox = (TBox) tElement;

        // Set image file path as content value (absolute path)
        // .NET: __tBox.SrcBox.content.value = string.Format(SourceFileAbsoluPattern, task.Document.FileFullPath)
        if (tBox.getSrcBox().getContent() != null) {
            tBox.getSrcBox().getContent().setValue(
                    String.format(SOURCE_FILE_ABSOLU_PATTERN, doc.getFileFullPath()));
        }

        // Handle image rotation
        // .NET: if (task.Rotation_Image) __tBox.SrcBox.picture.angle = "90"
        if (task.isRotationImage() && tBox.getSrcBox().getPicture() != null) {
            tBox.getSrcBox().getPicture().setAngle(PICTURE_ROTATION_90);
        }

        // Create BlocBox from TBox (extracts srcBox and srcExtraBox)
        BlocBox blocBox = new BlocBox(task, task.getDestinationBlocName(),
                tBox.getSrcBox(), tBox.getSrcExtraBox());

        log.debug("IMG bloc [{}] created with path [{}]",
                task.getDestinationBlocName(), doc.getFileFullPath());

        return blocBox;
    }

    // ========================================================================
    // DOC/RTF/XTG format
    // Cross-reference: Process_Document.cs lines 52-58
    // ========================================================================

    /**
     * DOC/RTF/XTG format: Get TElement template, set file path with "file:" prefix.
     * Uses Static_TElement_Name.RTF_DOC_XTG template.
     * Action is NOT explicitly set (uses default = NONE).
     */
    private BlocBox processDocumentFile(TaskDocument task) {
        log.debug("DocumentTaskProcessStrategy DOC/RTF/XTG: task [{}] subType={}",
                task.getId(), task.getSubTaskType());

        DocumentDomain doc = task.getDocument();
        if (doc == null) {
            log.warn("Document file task [{}] has no document loaded, skipping", task.getId());
            return null;
        }

        // Get a clone of the RTF_DOC_XTG TElement template
        TElement tElement = TElementHelper.getTElement(
                StaticTElementNameEnum.RTF_DOC_XTG, task.getDestinationBlocName());
        if (!(tElement instanceof TBox)) {
            log.warn("DOC/RTF/XTG task [{}] could not get TBox template", task.getId());
            return null;
        }

        TBox tBox = (TBox) tElement;

        // Set file path with "file:" prefix as content value
        // .NET: __tBox.SrcBox.content.value = string.Format(SourceFileDocPoolPattern, task.Document.FileFullPath)
        if (tBox.getSrcBox().getContent() != null) {
            tBox.getSrcBox().getContent().setValue(
                    String.format(SOURCE_FILE_DOC_POOL_PATTERN, doc.getFileFullPath()));
        }

        // Create BlocBox from TBox
        BlocBox blocBox = new BlocBox(task, task.getDestinationBlocName(),
                tBox.getSrcBox(), tBox.getSrcExtraBox());

        log.debug("DOC/RTF/XTG bloc [{}] created with path [{}]",
                task.getDestinationBlocName(), doc.getFileFullPath());

        return blocBox;
    }

    // ========================================================================
    // PDF format
    // Cross-reference: Process_Document.cs Process_File_PDF() lines 165-250
    // ========================================================================

    /**
     * PDF format: Multi-page handling with UPDATE/CREATE logic.
     * Compares PDF page count with existing box count in gabarit to determine:
     * - More blocs than PDFs → remove excess pages
     * - Same count → update existing blocs
     * - More PDFs than blocs → create new blocs and pages
     */
    private void processFilePdf(TaskDocument task) {
        log.debug("DocumentTaskProcessStrategy PDF: task [{}]", task.getId());

        DocumentDomain doc = task.getDocument();
        if (doc == null || doc.getPdfFiles().isEmpty()) {
            log.warn("PDF task [{}] has no PDF files, skipping", task.getId());
            return;
        }

        // Get list of existing box names starting with destination prefix in gabarit
        // .NET: task.Run.Gabarit.XML.GetListBoxNameStartWith(task.DestinationBlocName)
        QxpXml gabaritXml = task.getRun().getGabarit().getQxpXml();
        List<String> existingBoxNames = gabaritXml.getListBoxNameStartWith(task.getDestinationBlocName());

        if (existingBoxNames.isEmpty()) {
            // Parity: .NET Process_Document records MissingDestinationBlocNameInTask (Errors.Add(string)
            // → Error_Type.Unspecified) before returning, instead of silently skipping. Finding #39.
            task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED, String.format(
                    "Manque le bloc de destination %s dans la tache %s",
                    task.getDestinationBlocName(), task.getId())));
            log.warn("PDF task [{}] no existing blocs found for prefix [{}], skipping",
                    task.getId(), task.getDestinationBlocName());
            return;
        }

        int pdfFileCount = doc.getPdfFiles().size();
        int existingBoxCount = existingBoxNames.size();

        // Initialize image offset helper
        // .NET: task.Image_Offset = new Task_Image_Offset(task.Offset_Values)
        TaskImageOffset imageOffset = task.getImageOffset();
        if (imageOffset == null && task.getOffsetValues() != null) {
            imageOffset = new TaskImageOffset(task.getOffsetValues());
            task.setImageOffset(imageOffset);
        }

        // Initialize image position helper
        // .NET: task.Image_Position = new Task_Image_Position(task.Position_Values)
        // build position helper UNCONDITIONALLY (ctor maps null/invalid → DEFAULT)
        TaskImagePosition imagePosition = task.getImagePosition();
        if (imagePosition == null) {
            imagePosition = new TaskImagePosition(task.getPositionValues());
            task.setImagePosition(imagePosition);
        }

        int maxPages = Math.max(pdfFileCount, existingBoxCount);

        for (int i = 0; i < maxPages; i++) {

            // CASE 1: More existing blocs than PDF pages → remove excess pages
            // .NET: if(__i < __lstBoxName.Count && __i >= task.Document.PDFFiles.Count)
            if (i < existingBoxCount && i >= pdfFileCount) {
                String blocName = String.format(PDF_BLOC_NAME_PATTERN,
                        task.getDestinationBlocName(), i + 1);
                BlocPage blocPage = new BlocPage(task, blocName);
                blocPage.setRelativePage(i);
                blocPage.setAction(BlocActionEnum.REMOVE);
                task.getBlocsModify().put(blocPage.getName(), blocPage);
            }
            // CASE 2: PDF page exists → create or update bloc
            else {
                String pdfFile = doc.getPdfFiles().get(i);
                String blocName = String.format("%s_%d", task.getDestinationBlocName(), i + 1);

                // Select template: PDF_1 for first page, PDF_N for subsequent
                StaticTElementNameEnum templateName;
                if (i == 0) {
                    templateName = StaticTElementNameEnum.PDF_1;
                } else {
                    templateName = StaticTElementNameEnum.PDF_N;
                }

                TElement tElement = TElementHelper.getTElement(templateName, blocName);
                if (!(tElement instanceof TBox)) {
                    log.warn("PDF task [{}] could not get TBox template for page [{}]",
                            task.getId(), i + 1);
                    continue;
                }

                TBox tBox = (TBox) tElement;

                // Set PDF file path as content value
                // .NET: __tBox.SrcBox.content.value = __doc.GetPDFFileAbsolutePath(__file)
                if (tBox.getSrcBox().getContent() != null) {
                    tBox.getSrcBox().getContent().setValue(pdfFile);
                }

                // Create BlocBox from TBox
                BlocBox blocBox = new BlocBox(task, blocName,
                        tBox.getSrcBox(), tBox.getSrcExtraBox());
                blocBox.setRelativePage(i);

                Box srcBox = blocBox.getSrcBox();
                Box extraBox = blocBox.getSrcExtraBox();

                // Set position for pages after the first
                // .NET: if (__i > 0) { set geometry position from Image_Position }
                if (i > 0 && srcBox != null
                        && srcBox.getGeometry() != null && srcBox.getGeometry().getPosition() != null) {
                    srcBox.getGeometry().getPosition().setLeft(imagePosition.getLeft());
                    srcBox.getGeometry().getPosition().setTop(imagePosition.getTop());
                    srcBox.getGeometry().getPosition().setRight(imagePosition.getRight());
                    srcBox.getGeometry().getPosition().setBottom(imagePosition.getBottom());
                }

                // Handle rotation and offset
                if (task.isRotationImage()) {
                    // Rotation: set angle on srcBox picture
                    if (tBox.getSrcBox() != null && tBox.getSrcBox().getPicture() != null) {
                        tBox.getSrcBox().getPicture().setAngle(PICTURE_ROTATION_90);
                    }
                    // Offset across on extraBox when rotated
                    if (extraBox != null && extraBox.getPicture() != null && imageOffset != null) {
                        extraBox.getPicture().setOffsetAcross(imageOffset.getOffset(i));
                    }
                } else {
                    // Offset down on extraBox when not rotated
                    if (extraBox != null && extraBox.getPicture() != null && imageOffset != null) {
                        extraBox.getPicture().setOffsetDown(imageOffset.getOffset(i));
                    }
                }

                // Determine action: UPDATE if box exists, CREATE if new
                // .NET: if(__i < __lstBoxName.Count) → UPDATE, else → CREATE (with new page)
                if (i < existingBoxCount) {
                    blocBox.setAction(BlocActionEnum.UPDATE);
                } else {
                    // Need to create a new page first
                    String pageName = String.format(PDF_PAGE_NAME_PATTERN, i, blocName);
                    BlocPage blocPage = new BlocPage(task, pageName);
                    blocPage.setAction(BlocActionEnum.CREATE);
                    blocPage.setRelativePage(i);
                    task.getBlocsModify().put(blocPage.getName(), blocPage);

                    // Then create the box
                    blocBox.setAction(BlocActionEnum.CREATE);
                }

                task.getBlocsModify().put(blocBox.getName(), blocBox);

                log.debug("PDF page [{}] bloc [{}] action={}", i + 1, blocName, blocBox.getAction());
            }
        }
    }

    // ========================================================================
    // QXP_Data format
    // Cross-reference: Process_Document.cs Process_File_QXP_Data() lines 86-162
    // ========================================================================

    /**
     * QXP_Data: Copy content from a previous QXP document.
     * Two modes based on conserverStyle flag:
     * - false (VALUE mode): Extract text value from source XML, store in blocsUpdate
     * - true (STYLE mode): Analyse source project, clone elements, store in blocsModify
     */
    private void processFileQxpData(TaskDocument task) {
        log.debug("DocumentTaskProcessStrategy QXP_DATA: task [{}] conserverStyle={}",
                task.getId(), task.isConserverStyle());

        // Both source and destination must be set
        if (task.getSourceBlocName() == null || task.getSourceBlocName().isBlank()
                || task.getDestinationBlocName() == null || task.getDestinationBlocName().isBlank()) {
            log.warn("QXP_DATA task [{}] requires both source and destination bloc names", task.getId());
            return;
        }

        DocumentDomain doc = task.getDocument();
        if (doc == null) {
            log.warn("QXP_DATA task [{}] has no document loaded, skipping", task.getId());
            return;
        }

        // If style mode, analyse the project structure first
        // .NET: if(task.Conserver_Style) { task.Document.QXPProject.Analyse(task, false); }
        if (task.isConserverStyle()) {
            documentStructureBusiness.ensureProject(task.getRun(), doc);
            doc.getQxpProject().analyse(task, false);
        } else {
            documentStructureBusiness.ensureXml(task.getRun(), doc);
        }

        // Split pipe-separated source and destination names
        String[] sourceNames = task.getSourceBlocName().split("\\|");
        String[] destNames = task.getDestinationBlocName().split("\\|");

        // .NET has an unresolved TODO here: it iterates the SOURCE length and indexes the
        // DESTINATION array, so a mismatch would throw IndexOutOfRange. We instead surface a clear
        // run error and process only the safe overlap (no crash, no silent drop). (2 = Critique)
        if (sourceNames.length != destNames.length) {
            task.getRun().getErrors().add(new RunError(2,
                    "QXP_Data: nombre de blocs source (" + sourceNames.length
                            + ") different de la destination (" + destNames.length
                            + ") pour la tache " + task.getId()));
            log.warn("QXP_Data source/destination count mismatch ({} vs {}) for task [{}]",
                    sourceNames.length, destNames.length, task.getId());
        }
        int count = Math.min(sourceNames.length, destNames.length);

        for (int i = 0; i < count; i++) {
            String sourceName = sourceNames[i].trim();
            String destName = destNames[i].trim();

            if (sourceName.isEmpty() || destName.isEmpty()) {
                continue;
            }

            if (task.isConserverStyle()) {
                processQxpDataStyle(task, doc, sourceName, destName);
            } else {
                processQxpDataValue(task, doc, sourceName, destName);
            }
        }
    }

    /**
     * QXP_Data VALUE mode: Extract text value from source document XML.
     * Creates BlocBox in blocsUpdate with action UPDATE.
     *
     * Cross-reference: Process_Document.cs lines 152-158
     */
    private void processQxpDataValue(TaskDocument task, DocumentDomain doc,
                                     String sourceName, String destName) {
        // Extract value from source document's XML structure
        // .NET: string __bloc_Value = __doc.XML.GetValue(__sourceName)
        String blocValue = doc.getQxpXml().getValue(sourceName);

        BlocBox blocBox = new BlocBox(task, destName, blocValue);
        blocBox.setAction(BlocActionEnum.UPDATE);

        task.getBlocsUpdate().put(blocBox.getName(), blocBox);

        log.debug("QXP_DATA VALUE prepared for task [{}], source [{}], destination [{}], valueLength [{}]",
                task.getId(), sourceName, destName, blocValue != null ? blocValue.length() : null);
    }

    /**
     * QXP_Data STYLE mode: Clone element structure from source project.
     * Looks up source element in QXPProject.Elements, creates appropriate bloc type.
     * Supports TBox, TTable, and TGroup (TGroup not yet treated in .NET either).
     *
     * Cross-reference: Process_Document.cs lines 118-149
     */
    private void processQxpDataStyle(TaskDocument task, DocumentDomain doc,
                                     String sourceName, String destName) {
        Map<String, TElement> elements = doc.getQxpProject().getElements();

        if (elements == null || !elements.containsKey(sourceName)) {
            log.warn("QXP_DATA STYLE task [{}] source element [{}] not found in project",
                    task.getId(), sourceName);
            return;
        }

        TElement tElement = elements.get(sourceName);

        // Case 1: Source is a TBox
        // .NET: Bloc_Box __blocBox = new Bloc_Box(task, __destinationName, __tBox);
        //       __blocBox.Action = Bloc_Action.UPDATE;
        if (tElement instanceof TBox) {
            TBox srcTBox = (TBox) tElement;

            // Create a new TBox with style+value transferred from source
            TBox destTBox = TElementHelper.getNewTBoxStyleValueFromTBox(srcTBox, destName);
            if (destTBox == null) {
                log.warn("QXP_DATA STYLE task [{}] could not transfer TBox style for [{}]",
                        task.getId(), sourceName);
                return;
            }

            BlocBox blocBox = new BlocBox(task, destName,
                    destTBox.getSrcBox(), destTBox.getSrcExtraBox());
            blocBox.setAction(BlocActionEnum.UPDATE);

            // Genuine duplicate → record an Unspecified error (matches .NET BlocDupliquerDansTache
            // severity), WITHOUT the .NET quirk of flagging every TBox style-copy. The .NET code
            // added the bloc inline then re-checked ContainsKey (always true) — we only flag a real
            // collision.
            if (task.getBlocsModify().containsKey(blocBox.getName())) {
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "BlocDupliquerDansTache: bloc [" + blocBox.getName()
                                + "] deja present dans la tache " + task.getId()));
                log.warn("QXP_DATA STYLE task [{}] duplicate bloc name [{}]",
                        task.getId(), blocBox.getName());
            } else {
                task.getBlocsModify().put(blocBox.getName(), blocBox);
            }

            log.debug("QXP_DATA STYLE TBox: bloc [{}] cloned from source [{}]",
                    destName, sourceName);
        }
        // Case 2: Source is a TTable
        // .NET: Bloc_Table __blocTable = new Bloc_Table(task, __destinationName, __tTable);
        //       __blocTable.Action = Bloc_Action.UPDATE;
        else if (tElement instanceof TTable) {
            TTable srcTTable = (TTable) tElement;

            TTable destTTable = TElementHelper.getNewTTableStyleValueFromTTable(srcTTable, destName);
            if (destTTable == null) {
                log.warn("QXP_DATA STYLE task [{}] could not transfer TTable style for [{}]",
                        task.getId(), sourceName);
                return;
            }

            BlocTable blocTable = new BlocTable(task, destName, destTTable.getSrcTable());
            blocTable.setAction(BlocActionEnum.UPDATE);

            if (task.getBlocsModify().containsKey(blocTable.getName())) {
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "BlocDupliquerDansTache: bloc [" + blocTable.getName()
                                + "] deja present dans la tache " + task.getId()));
                log.warn("QXP_DATA STYLE task [{}] duplicate bloc name [{}]",
                        task.getId(), blocTable.getName());
            } else {
                task.getBlocsModify().put(blocTable.getName(), blocTable);
            }

            log.debug("QXP_DATA STYLE TTable: bloc [{}] cloned from source [{}]",
                    destName, sourceName);
        }
        // Case 3: Source is a TGroup — not yet treated
        // .NET: "Pas traité pour le moment"
        else if (tElement instanceof TGroup) {
            log.debug("QXP_DATA STYLE TGroup: not yet treated for source [{}]", sourceName);
        }
    }
}
```


## 23. `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/QxpPreviousTaskProcessStrategy.java`

SHA-256: `sha256-7480a31c8ed0b4e29e51ad9d3b8cedd09a1c4c8df2f2626b33d00c27f0f4cefb`

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocTable;
import com.socgen.sgs.api.quark.engine.domain.element.TBox;
import com.socgen.sgs.api.quark.engine.domain.element.TElement;
import com.socgen.sgs.api.quark.engine.domain.element.TTable;
import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;
import com.socgen.sgs.api.quark.engine.domain.task.TaskQxpPrevious;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessStrategy;
import lombok.extern.slf4j.Slf4j;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.SortedMap;
import java.util.TreeMap;

/**
 * Strategy for TaskQxpPrevious (DOC_QXP) — copy blocs from a previously certified QXP into the
 * current template, either as values or with their styles.
 *
 * <p>Two modes:
 * <ul>
 *   <li><b>Explicit</b> — source/destination bloc names given, '|'-separated. The destination may
 *       carry a position hint after a '¤' (U+00A4) used to resolve a TTable's spread/layout.</li>
 *   <li><b>Hierarchy</b> — no names given: walk source blocs ending with {@code .N0}, {@code .N1}, …
 *       and write each to the next level ({@code .N{level+1}}).</li>
 * </ul>
 *
 * <p>The source document is loaded + pool-uploaded (and its XML/project fetched) beforehand by
 * {@code LoadTaskDocumentsBusiness}. Cross-reference: QXP.Engine.Core.Business.Process_QXP_Previous.
 */
@Component
@Slf4j
@RequiredArgsConstructor
public class QxpPreviousTaskProcessStrategy implements TaskProcessStrategy<TaskQxpPrevious> {

    private final DocumentStructureBusiness documentStructureBusiness;

    /** Suffix marking source blocs in hierarchy mode (e.g. ".N0", ".N1"). */
    private static final String BLOC_N_SUFFIX = ".N";
    /** Position separator inside the destination field (U+00A4 ¤), matching .NET Split('¤'). */
    private static final String POSITION_SEPARATOR = "¤";
    private static final int N_SUFFIX_LEN = 3; // ".N" + single-digit level

    @Override
    public Class<TaskQxpPrevious> getTaskType() {
        return TaskQxpPrevious.class;
    }

    @Override
    public void process(TaskQxpPrevious task) {
        DocumentDomain doc = task.getDocument();
        if (doc == null) {
            // The document load failed/was empty — the loader already recorded the error.
            log.warn("QXP_Previous task [{}] has no source document, skipping", task.getId());
            return;
        }

        if (isSet(task.getSourceBlocName()) && isSet(task.getDestinationBlocName())) {
            // Explicit mode — '|'-separated source/destination names.
            String[] listSource = task.getSourceBlocName().split("\\|", -1);

            // The destination may encode "names¤positionName" (used to locate a TTable's spread/layout).
            String[] positionParts = task.getDestinationBlocName().split(POSITION_SEPARATOR, -1);
            String[] listDest;
            if (positionParts.length == 2) {
                listDest = positionParts[0].split("\\|", -1);
                task.setPositionBlocName(positionParts[1]);
            } else {
                listDest = task.getDestinationBlocName().split("\\|", -1);
            }

            if (listSource.length != listDest.length) {
                // .NET Errors.Add(Invalid_List_Count, ...) → Unspecified.
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "Invalid_List_Count: " + listSource.length + " source(s) vs " + listDest.length
                                + " destination(s) pour la tache " + task.getId()));
            }

            if (task.isConserverStyle()) {
                documentStructureBusiness.ensureProject(task.getRun(), doc);
                doc.getQxpProject().analyse(task, false);
            } else {
                documentStructureBusiness.ensureXml(task.getRun(), doc);
            }

            addBlocsExplicit(task, doc, listSource, listDest);
        } else {
            // Hierarchy mode — collect source blocs by level (.N0, .N1, …) until a level is empty.
            documentStructureBusiness.ensureXml(task.getRun(), doc);
            SortedMap<Integer, List<String>> byLevels = new TreeMap<>();
            int level = 0;
            while (true) {
                List<String> names = doc.getQxpXml().getListBoxNameEndWith(BLOC_N_SUFFIX + level);
                if (names != null && !names.isEmpty()) {
                    byLevels.put(level, names);
                    level++;
                } else {
                    break;
                }
            }
            if (!byLevels.isEmpty()) {
                addBlocsByLevels(task, doc, byLevels);
            }
        }
    }

    // ------------------------------------------------------------------
    // Explicit mode — Cross-reference: Process_QXP_Previous.AddBlocs(task, source[], dest[])
    // ------------------------------------------------------------------

    private void addBlocsExplicit(TaskQxpPrevious task, DocumentDomain doc,
                                  String[] listSource, String[] listDest) {
        // .NET iterates source.Length and indexes dest[i] (would throw on a shorter dest). We iterate
        // the safe overlap after recording Invalid_List_Count above — consistent with the approved
        // Document-task count-mismatch handling.
        int count = Math.min(listSource.length, listDest.length);
        for (int i = 0; i < count; i++) {
            String source = listSource[i];
            String dest = listDest[i];

            if (task.getBlocsUpdate().containsKey(dest) || task.getBlocsModify().containsKey(dest)) {
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "ErrorDuplicateBlocInTask: bloc [" + dest + "] deja present dans la tache " + task.getId()));
                continue;
            }

            if (task.isConserverStyle()) {
                Map<String, TElement> elements = doc.getQxpProject().getElements();
                if (elements != null && elements.containsKey(source)) {
                    TElement element = elements.get(source);
                    if (element instanceof TBox) {
                        addStyleBox(task, (TBox) element, dest);
                    } else if (element instanceof TTable) {
                        addStyleTable(task, (TTable) element, dest);
                    } else {
                        task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                                "Invalid_TElement_Type: [" + source + "] (tache " + task.getId() + ")"));
                    }
                } else {
                    task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                            "Missing_TElement: [" + source + "] (tache " + task.getId() + ")"));
                }
            } else {
                // Value only.
                BlocBox bloc = new BlocBox(task, dest, doc.getQxpXml().getValue(source));
                bloc.setAction(BlocActionEnum.UPDATE);
                task.getBlocsUpdate().put(dest, bloc);
            }
        }
    }

    // ------------------------------------------------------------------
    // Hierarchy mode — Cross-reference: Process_QXP_Previous.AddBlocs(task, byLevels)
    // ------------------------------------------------------------------

    private void addBlocsByLevels(TaskQxpPrevious task, DocumentDomain doc,
                                  SortedMap<Integer, List<String>> byLevels) {
        for (Map.Entry<Integer, List<String>> entry : byLevels.entrySet()) {
            int level = entry.getKey();
            for (String source : entry.getValue()) {
                if (source == null || source.length() < N_SUFFIX_LEN) {
                    continue;
                }
                // dest = <source without its ".Nx" suffix> + ".N" + (level+1)
                String dest = source.substring(0, source.length() - N_SUFFIX_LEN)
                        + BLOC_N_SUFFIX + (level + 1);
                try {
                    if (task.getBlocsUpdate().containsKey(dest)) {
                        task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                                "ErrorDuplicateBlocInTask: bloc [" + dest + "] deja present dans la tache " + task.getId()));
                    } else {
                        String value = doc.getQxpXml().getValue(source);
                        // Quark rejects empty strings at save time → substitute the task NullString.
                        if (value == null || value.isBlank()) {
                            value = task.getNullString();
                        }
                        BlocBox bloc = new BlocBox(task, dest, value);
                        bloc.setAction(BlocActionEnum.UPDATE);
                        task.getBlocsUpdate().put(dest, bloc);
                    }
                } catch (Exception e) {
                    task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                            "ErrorAddingBlocInTask: source [" + source + "] dest [" + dest + "] (tache "
                                    + task.getId() + ")"));
                    log.warn("Error adding bloc {}->{} for task {}: {}", source, dest, task.getId(), e.getMessage());
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Style copy helpers — Cross-reference: Process_QXP_Previous.AddBloc(TBox/TTable)
    // ------------------------------------------------------------------

    private void addStyleBox(TaskQxpPrevious task, TBox tBox, String newName) {
        TBox destTBox = TElementHelper.getNewTBoxStyleValueFromTBox(tBox, newName);
        if (destTBox == null) {
            task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                    "ErrorAddingBlocInTask: impossible de copier le style TBox vers [" + newName + "]"));
            return;
        }
        BlocBox bloc = new BlocBox(task, newName, destTBox.getSrcBox(), destTBox.getSrcExtraBox());
        bloc.setAction(BlocActionEnum.UPDATE);
        task.getBlocsModify().put(newName, bloc);
    }

    private void addStyleTable(TaskQxpPrevious task, TTable tTable, String newName) {
        TTable destTTable = TElementHelper.getNewTTableStyleValueFromTTable(tTable, newName);
        if (destTTable == null) {
            task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                    "ErrorAddingBlocInTask: impossible de copier le style TTable vers [" + newName + "]"));
            return;
        }
        BlocTable bloc = new BlocTable(task, newName, destTTable.getSrcTable());
        bloc.setAction(BlocActionEnum.UPDATE);
        task.getBlocsModify().put(newName, bloc);
    }

    private boolean isSet(String value) {
        return value != null && !value.isBlank();
    }
}
```


## 24. `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/CompartimentTaskProcessStrategy.java`

SHA-256: `sha256-16fdc59405012af715674141c077e4309380f60f66567e7aa49ec5ca5a4851bd`

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.business.GetCompartimentRunsBusiness;
import com.socgen.sgs.api.quark.engine.business.GetDocumentByIdBusiness;
import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;
import com.socgen.sgs.api.quark.engine.business.GetRunPropertiesBusiness;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.TaskCompartimentMode;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocPage;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBlocInfo;
import com.socgen.sgs.api.quark.engine.domain.element.TBox;
import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;
import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.domain.task.TaskCompartiment;
import com.socgen.sgs.api.quark.engine.dto.RunIdDto;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Layout;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Spread;
import com.socgen.sgs.api.quark.engine.service.ProcessRunService;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessStrategy;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.SortedMap;
import java.util.TreeMap;

/**
 * Strategy for processing TaskCompartiment (sub-document generation and merging).
 *
 * <p>Three phases:
 * <ol>
 *   <li>Prepare_Runs: Load child run IDs from database, create Run objects</li>
 *   <li>Execute_Runs: Launch each child run through the full pipeline</li>
 *   <li>Render_Runs: Extract blocs from child QXP projects, rename, create pages</li>
 * </ol>
 *
 * Cross-reference: QXP.Engine.Core.Business.Process_Compartiment
 */
@Component
@Slf4j
public class CompartimentTaskProcessStrategy implements TaskProcessStrategy<TaskCompartiment> {

    /** Report type for compartiment child runs. */
    private static final int TYPE_RAPPORT_COMPARTIMENT = 4;

    /** Maximum length for old box names before adding suffix. */
    private static final int MAX_OLD_NAME_SIZE = 24;

    private static final String SUFFIXE_PATTERN = "_%s";
    private static final String NEW_PAGE_PATTERN = "T%d_P%d";
    private static final String DEF_BOX_NAME_PATTERN = "Box%s";
    private static final String OUT_OF_PAGE_CHAR = "*";
    private static final String QXPSDK_FALSE = "false";

    private final GetCompartimentRunsBusiness getCompartimentRunsBusiness;
    private final ProcessRunService processRunService;
    private final GetRunPropertiesBusiness getRunPropertiesBusiness;
    private final GetDocumentByIdBusiness getDocumentByIdBusiness;
    private final DocumentStructureBusiness documentStructureBusiness;

    /**
     * Constructor with @Lazy on ProcessRunService to break circular dependency.
     * Circular: ProcessRunService → ProcessTasksService → strategies → this → ProcessRunService
     */
    public CompartimentTaskProcessStrategy(
            GetCompartimentRunsBusiness getCompartimentRunsBusiness,
            @Lazy ProcessRunService processRunService,
            GetRunPropertiesBusiness getRunPropertiesBusiness,
            GetDocumentByIdBusiness getDocumentByIdBusiness,
            DocumentStructureBusiness documentStructureBusiness) {
        this.getCompartimentRunsBusiness = getCompartimentRunsBusiness;
        this.processRunService = processRunService;
        this.getRunPropertiesBusiness = getRunPropertiesBusiness;
        this.getDocumentByIdBusiness = getDocumentByIdBusiness;
        this.documentStructureBusiness = documentStructureBusiness;
    }

    @Override
    public Class<TaskCompartiment> getTaskType() {
        return TaskCompartiment.class;
    }

    @Override
    public void process(TaskCompartiment task) {
        log.debug("CompartimentTaskProcessStrategy processing task [{}]", task.getId());

        RunProperties props = task.getRun().getRunProperties();

        if (props.getCompartimentMode() == TaskCompartimentMode.UNKNOWN) {
            // Parity: .NET Process_Compartiment raises Exception_Task(MSG_Load_Task_Compartiment) — the
            // ProcessTasksServiceImpl wrapper converts this to a CRITIQUE run error + setInError(true),
            // rather than silently returning. Finding #43.
            throw new IllegalStateException(String.format(
                    "Erreur sur la tache %s - manque le mode de la tache compartiment sur le run",
                    task.getId()));
        }

        // Phase 1: Prepare child runs
        if (task.isEvaluateRuns()) {
            prepareRuns(task);
        }

        // Phase 2: Execute child runs
        executeRuns(task);

        // Phase 3: Render — extract blocs from child run results
        renderRuns(task);

        // Free memory
        task.getChildRuns().clear();
    }

    // ========================================================================
    // Phase 1: Prepare_Runs
    // Cross-reference: Process_Compartiment.Prepare_Runs() lines 71-112
    // ========================================================================

    private void prepareRuns(TaskCompartiment task) {
        RunProperties props = task.getRun().getRunProperties();

        boolean toGenerate = (props.getCompartimentMode() == TaskCompartimentMode.GENERATE
                || props.getCompartimentMode() == TaskCompartimentMode.GENERATE_AND_INCORPORATE);

        LinkedHashMap<String, Integer> compartimentRuns = getCompartimentRunsBusiness.execute(
                props.getIdGabarit(),
                props.getIdFndCode(),
                task.getIdGabaritFils(),
                TYPE_RAPPORT_COMPARTIMENT,
                props.getIdLangue(),
                props.getDateEcheance(),
                toGenerate);

        if (compartimentRuns.isEmpty()) {
            // .NET: NoneRunCompartiment (2 = Critique)
            task.getRun().getErrors().add(new RunError(2,
                    "Aucun run compartiment trouve pour la tache " + task.getId()
                            + " (run " + task.getRun().getId() + ")"));
            log.warn("No compartment runs found for task [{}] in run [{}]",
                    task.getId(), task.getRun().getId());
            return;
        }

        for (Map.Entry<String, Integer> entry : compartimentRuns.entrySet()) {
            String compartimentCode = entry.getKey();
            int runId = entry.getValue();

            if (runId > 0) {
                Run childRun = new Run();
                childRun.setId(runId);
                childRun.setExecutionContext(task.getRun().requireExecutionContext());
                RunProperties childProps = new RunProperties();
                childProps.setIdFndCode(compartimentCode);
                childProps.setRunId(task.getRun().requireExecutionContext().getRootRunId());
                childRun.setRunProperties(childProps);
                task.getChildRuns().add(childRun);
            } else {
                // .NET: EmptyRunCompartiment (2 = Critique)
                task.getRun().getErrors().add(new RunError(2,
                        "Compartiment [" + compartimentCode + "] sans run pour la tache "
                                + task.getId() + " (run " + task.getRun().getId() + ")"));
                log.warn("No run found for compartment [{}] in task [{}], run [{}]",
                        compartimentCode, task.getId(), task.getRun().getId());
            }
        }
    }

    // ========================================================================
    // Phase 2: Execute_Runs
    // Cross-reference: Process_Compartiment.Execute_Runs() lines 118-132
    // ========================================================================

    private void executeRuns(TaskCompartiment task) {
        RunProperties props = task.getRun().getRunProperties();
        // When the parent mode includes GENERATE, each child is regenerated (Run); otherwise the
        // child's previously-generated document is reused (Run_Previous).
        // Cross-reference: .NET Process_Compartiment.Prepare_Runs (to_Generate ? Run : Run_Previous).
        boolean toGenerate = (props.getCompartimentMode() == TaskCompartimentMode.GENERATE
                || props.getCompartimentMode() == TaskCompartimentMode.GENERATE_AND_INCORPORATE);

        // runProcessor now returns the executed Run; we keep those (with their results) for render.
        List<Run> executedChildren = new ArrayList<>();
        for (Run childRun : task.getChildRuns()) {
            try {
                Run executed;
                if (toGenerate) {
                    log.info("Generating child run [{}] for compartiment task [{}]",
                            childRun.getId(), task.getId());
                    executed = processRunService.runChildProcessor(
                            new RunIdDto(childRun.getId()), task.getRun().requireExecutionContext());
                } else {
                    log.info("Reusing previous document for child run [{}] (compartiment task [{}])",
                            childRun.getId(), task.getId());
                    executed = loadPreviousChild(task, childRun);
                }
                executedChildren.add(executed != null ? executed : childRun);
            } catch (Exception e) {
                log.error("Error executing child run [{}] for task [{}]: {}",
                        childRun.getId(), task.getId(), e.getMessage(), e);
                executedChildren.add(childRun); // keep the stub; render will report it empty
            }
        }
        //task.setChildRuns(executedChildren);
        task.getChildRuns().clear();
        task.getChildRuns().addAll(executedChildren);
    }

    /**
     * Run_Previous: load a child's previously-generated QXP (by RunProperties.idLastQxp) instead of
     * regenerating it, and put it back in the pool so it can be read for incorporation.
     * Cross-reference: .NET Run_Previous.Render() — Get_Document(ID_Last_QXP) + Addfile.
     */
    private Run loadPreviousChild(TaskCompartiment task, Run childStub) {
        RunProperties childProps = getRunPropertiesBusiness.execute(new RunIdDto(childStub.getId()));
        Run prev = new Run();
        prev.setId(childStub.getId());
        prev.setExecutionContext(task.getRun().requireExecutionContext());
        prev.setRunProperties(childProps);

        int idLastQxp = childProps.getIdLastQxp();
        if (idLastQxp <= 0) {
            task.getRun().getErrors().add(new RunError(2,
                    "EmptyRunChildQXP: aucun QXP precedent (idLastQxp) pour le run enfant " + childStub.getId()));
            log.warn("No previous QXP (idLastQxp) for child run [{}]", childStub.getId());
            return prev; // no result → render reports it empty
        }

        DocumentDomain doc = getDocumentByIdBusiness.getDocumentById(idLastQxp);
        if (doc == null || doc.getData() == null) {
            task.getRun().getErrors().add(new RunError(2,
                    "EmptyRunChildQXP: document " + idLastQxp + " introuvable pour le run enfant " + childStub.getId()));
            return prev;
        }

        prev.getResult().setFinalQxp(doc);
        return prev;
    }

    // ========================================================================
    // Phase 3: Render_Runs
    // Cross-reference: Process_Compartiment.Render_Runs() lines 138-195
    // ========================================================================

    private void renderRuns(TaskCompartiment task) {
        int lastPage = 0;

        RunProperties props = task.getRun().getRunProperties();
        boolean incorporate = (props.getCompartimentMode() == TaskCompartimentMode.INCORPORATE
                || props.getCompartimentMode() == TaskCompartimentMode.GENERATE_AND_INCORPORATE);

        if (!incorporate) {
            // Nothing to incorporate — mark task as not todo
            task.setTodo(false);
            return;
        }

        // Extract blocs from each child run
        for (Run childRun : task.getChildRuns()) {
            lastPage = addRunBlocs(task, childRun, lastPage);
        }

        // 1. If no blocs generated, create one empty page
        if (task.getBlocsModify().isEmpty()) {
            BlocPage blocPage = new BlocPage(task,
                    String.format(NEW_PAGE_PATTERN, task.getId(), 0));
            blocPage.setAction(BlocActionEnum.CREATE);
            blocPage.setRelativePage(0);
            task.getBlocsModify().put(blocPage.getName(), blocPage);
            lastPage++;
        }

        // 2. Get anchor info
        DBlocInfo startInfo = task.getStartAnchor();
        DBlocInfo endInfo = task.getEndAnchor();

        // 3. Remove old pages between anchors (inclusive: <= not <)
        // .NET: for (int __i = 0; __i <= __nb_Ancien_Page; __i++)
        int nbAnciennePage = endInfo.getPage() - startInfo.getPage();
        for (int i = 0; i <= nbAnciennePage; i++) {
            int relativeRemovePage = lastPage + i;
            BlocPage blocPage = new BlocPage(task,
                    String.format(NEW_PAGE_PATTERN, task.getId(), relativeRemovePage));
            blocPage.setAction(BlocActionEnum.REMOVE);
            blocPage.setRelativePage(relativeRemovePage);
            task.getBlocsModify().put(blocPage.getName(), blocPage);
        }

        // 4. Move start anchor to first new page
        BlocBox blocStart = TElementHelper.getMoveAnchor(task, startInfo, 0);
        if (blocStart != null) {
            blocStart.setPagination(true);
            task.getBlocsModify().put(blocStart.getName(), blocStart);
        }

        // 5. Move end anchor to last new page
        BlocBox blocEnd = TElementHelper.getMoveAnchor(task, endInfo, lastPage - 1);
        if (blocEnd != null) {
            blocEnd.setPagination(true);
            task.getBlocsModify().put(blocEnd.getName(), blocEnd);
        }
    }

    // ========================================================================
    // Add_Run_Blocs + Add_Blocs
    // Cross-reference: Process_Compartiment.Add_Run_Blocs() lines 203-220
    //                  Process_Compartiment.Add_Blocs() lines 230-330
    // ========================================================================

    private int addRunBlocs(TaskCompartiment task, Run childRun, int lastPage) {
        // EmptyRunChildQXP: the child produced (or loaded) no final QXP.
        // Cross-reference: .NET Add_Run_Blocs — Result/Final_QXP null check.
        if (childRun.getResult() == null || childRun.getResult().getFinalQxp() == null) {
            task.getRun().getErrors().add(new RunError(2,
                    "EmptyRunChildQXP: pas de QXP final pour le run enfant " + childRun.getId()));
            log.warn("Child run [{}] has no final QXP, skipping", childRun.getId());
            return lastPage;
        }

        DocumentDomain finalQxp = childRun.getResult().getFinalQxp();
        if (finalQxp.getData() == null || finalQxp.getData().length == 0) {
            task.getRun().getErrors().add(new RunError(2,
                    "EmptyRunChildQXP: pas de contenu QXP final pour le run enfant " + childRun.getId()));
            return lastPage;
        }

        String format = finalQxp.getFormat() != null ? finalQxp.getFormat() : "QXP";
        DocumentDomain snapshot = new DocumentDomain(
                childRun.getId(), "DF_" + childRun.getId(), format,
                DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, finalQxp.getData());
        snapshot.setFilePoolPath(task.getRun().getPoolPath(snapshot.getFileName()));
        QxpProject qxpProject = documentStructureBusiness.ensureProject(task.getRun(), snapshot);

        // A structural fetch/parse failure is fail-soft in .NET: the document is degraded and
        // contributes no boxes, but no extra EmptyRunChildProject error is recorded.
        if (snapshot.isModeDegrade()) {
            log.warn("Child run [{}] QXP project is unavailable; continuing without child boxes",
                    childRun.getId());
            return lastPage;
        }

        // EmptyRunChildProject is reserved for an actually absent project reference.
        if (qxpProject == null) {
            task.getRun().getErrors().add(new RunError(2,
                    "EmptyRunChildProject: projet QXP vide pour le run enfant " + childRun.getId()));
            log.warn("Child run [{}] has empty QXP project, skipping", childRun.getId());
            return lastPage;
        }

        return addBlocs(task, qxpProject, childRun, lastPage);
    }

    private int addBlocs(TaskCompartiment task, QxpProject qxpProject,
                         Run childRun, int lastPage) {
        Project project = qxpProject.getProject();
        String standardSuffix = childRun.getRunProperties().getIdFndCode();

        // Group boxes by page (sorted by page number for correct ordering)
        SortedMap<Integer, List<BlocBox>> boxesByPage = new TreeMap<>();

        log.debug("Analysing child run [{}] project structure", childRun.getId());

        if (project.getLayouts() != null) {
            for (Layout layout : project.getLayouts()) {
                if (layout == null || layout.getSpreads() == null) {
                    continue;
                }
                for (Spread spread : layout.getSpreads()) {
                    if (spread == null || spread.getBoxes() == null) {
                        continue;
                    }
                    for (Box box : spread.getBoxes()) {
                        if (box == null || box.getGeometry() == null
                                || box.getGeometry().getPage() == null) {
                            continue;
                        }

                        String pageName = box.getGeometry().getPage();

                        // Skip boxes on pasteboard (page ends with *)
                        if (pageName.endsWith(OUT_OF_PAGE_CHAR)) {
                            continue;
                        }

                        int currentPageId;
                        try {
                            currentPageId = Integer.parseInt(pageName.trim());
                        } catch (NumberFormatException e) {
                            log.warn("Cannot parse page [{}] for box [{}]", pageName, box.getName());
                            continue;
                        }

                        // Rename box (must be BEFORE clearing UID)
                        box.setName(renameBloc(box, standardSuffix));

                        // Clear UID (must be AFTER rename)
                        box.setUID(null);

                        // Create BlocBox with CREATE action
                        BlocBox blocBox = new BlocBox(task, box.getName(), box, null);
                        blocBox.setAction(BlocActionEnum.CREATE);

                        boxesByPage.computeIfAbsent(currentPageId, k -> new ArrayList<>())
                                .add(blocBox);
                    }
                }
            }
        }

        // Process pages in order — only include pages with at least one visible box
        // .NET: suppressOutput == "false" means the box IS visible (not suppressed)
        for (Map.Entry<Integer, List<BlocBox>> entry : boxesByPage.entrySet()) {
            List<BlocBox> pageBoxes = entry.getValue();

            boolean hasVisibleBox = pageBoxes.stream()
                    .anyMatch(bloc -> {
                        Box srcBox = bloc.getSrcBox();
                        return srcBox != null
                                && srcBox.getGeometry() != null
                                && QXPSDK_FALSE.equals(srcBox.getGeometry().getSuppressOutput());
                    });

            if (hasVisibleBox) {
                // Create page
                BlocPage blocPage = new BlocPage(task,
                        String.format(NEW_PAGE_PATTERN, task.getId(), lastPage));
                blocPage.setAction(BlocActionEnum.CREATE);
                blocPage.setRelativePage(lastPage);
                task.getBlocsModify().put(blocPage.getName(), blocPage);

                // Add all boxes on this page
                for (BlocBox blocBox : pageBoxes) {
                    blocBox.setRelativePage(lastPage);
                    task.getBlocsModify().put(blocBox.getName(), blocBox);
                }

                lastPage++;
            }
        }

        log.debug("Extracted boxes from child run [{}], lastPage=[{}]", childRun.getId(), lastPage);
        return lastPage;
    }

    // ========================================================================
    // Rename_Bloc
    // Cross-reference: Process_Compartiment.Rename_Bloc() lines 340-365
    // ========================================================================

    private String renameBloc(Box box, String suffix) {
        String oldName = box.getName();
        String defName = String.format(DEF_BOX_NAME_PATTERN, box.getUID());
        String suffixStr = String.format(SUFFIXE_PATTERN, suffix);

        // Check if name is defined and not the default Quark pattern "BoxUID"
        if (oldName != null && !oldName.isBlank() && !oldName.equals(defName)) {
            // Truncate to max length
            String newName = oldName.length() > MAX_OLD_NAME_SIZE
                    ? oldName.substring(0, MAX_OLD_NAME_SIZE)
                    : oldName;

            // Only add suffix if not already present
            if (!newName.endsWith(suffixStr)) {
                newName = newName + suffixStr;
            }
            return newName;
        } else {
            return TElementHelper.newBlocName();
        }
    }
}
```


## 25. `src/main/java/com/socgen/sgs/api/quark/engine/domain/task/TaskAnchor.java`

SHA-256: `sha256-15629f989a34daba4c6cffeddd11413734893aa92da71b0a9e1c9e48a2bebdb9`

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
     * returns a cached fresh empty XML model rather than null, mirroring .NET's
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


## 26. `src/main/resources/application.yaml` — redacted reference, not a whole-file replacement

```yaml
---
spring:
  application.name: quark-engine-service
  # To avoid marshaling to JSON of null attribute
  jackson.default-property-inclusion: non-null
  jpa:
    hibernate.ddl-auto: ${HIBERNATE_DDL_AUTO:none}
    show-sql: ${JPA_SHOW_SQL:false}
  liquibase.enabled: false
  datasource:
    driver-class-name: oracle.jdbc.driver.OracleDriver
    url: <retain existing environment value>
    username: <retain existing environment value>
    password: <retain existing environment value>
    hikari:
      connection-init-sql: ALTER SESSION SET NLS_DATE_FORMAT='DD/MM/YYYY'
  rabbitmq:
    host: <retain existing environment value>
    port: 5671  # AMQP port (use 5671 for AMQPS with SSL enabled)
    ssl:
      enabled: true
    virtual-host: <retain existing environment value>
    username: <retain existing environment value>
    password: <retain existing environment value>
    connection-timeout: 30000  # 30 seconds connection timeout
    requested-heartbeat: 60    # 60 seconds heartbeat interval
    listener:
      simple:
        default-requeue-rejected: false

  xml : xml/

qxp:
  thirdparty:
    url: http://srvcldvapd001.dns43.socgen:8080/saveas/pdf/

quark-engine:
  rabitmq:
    run: quark-batch-run-dev

engine:
  gabarit:
    # QXP size above which processing enters Mode Degrade; modifications stop, final rendering continues.
    # Configurable. Set to 200 MB here (.NET EngineCoreSetting default was 68000000 / ~68 MB).
    size-limit-before-fail-soft: 209715200
  # Max blocs per modify step before a new step is created (.NET EngineCoreSetting Step_Limit).
  step-limit: 5000
  # Box-exclusion limitation (.NET EngineCoreSetting). NbMaxBoxes = nb-box-max / clamp(boxComplexity,0.8,1.3).
  nb-box-max: 17500
  average-box-size: 3400

qxps:
  server:
    url: "http://srvcldvapd001.dns43.socgen:8080"
    # 2 hours — generous budget for long QXPS render/fetch calls on large (100 MB+) documents.
    timeout: 7200000
    # Max bytes to buffer for a single QXPS response (full document XML / rendered PDF / literal QXP binary).
    # 500 MB. The /xml response can be several times the QXP binary size; raise per-env for very large gabarits.
    max-in-memory-size-bytes: 524288000
  pool:
    default-path: "D:\\Documents\\"
    current-path: ""

qxpsm:
  soap:
    endpoint: http://srvcldvapd001.dns43.socgen:8090/qxpsm/services/RequestService
    # 1 hour — mirrors .NET's effective request timeout for long modifier/render calls. Finding #11.
    timeout: 7200000
    # 0 = leave the SDK default (no forced retries), matching .NET. Finding #33.
    max-retries: 0
#
#logging:
#  level:
#    TEMP-DEBUG-RT: dump the raw SOAP request + response/fault to confirm multi-ref. REMOVE after diagnosis.
#    org.apache.axis.transport.http: DEBUG

management:
  endpoint:
    endpoints.web.exposure.include: ${ACTUATOR_ENDPOINTS:health}
  endpoints.web.exposure.include: ${ACTUATOR_ENDPOINTS:health}
  info.git.mode: full
  health.sgmonitoring.enabled: true
  # Config to have MicroMeter metrics centralized to Elasticsearch by APM agent
  # (https://www.elastic.co/guide/en/apm/agent/java/current/metrics.html#metrics-micrometer)
  # (https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.0-Migration-Guide#actuator-metrics-export-properties)
  simple.metrics.export:
    step: 30s
    mode: STEP

monitoring:
  enabled: false

scheduler:
  planned-runs:
    cron: "*/5 * * * * ?"  # Runs daily at midnight (00:00:00)

server:
  http2.enabled: ${HTTP2_ENABLED:true}
  port: ${WEB_PORT:8080}
  ssl:
    enabled: ${TLS_ENABLED:true}
    # Embedded Tomcat is not aware of JVM keystore so we must reference it
    key-alias: tomcat
    key-store-type: PKCS12
    key-store: ${javax.net.ssl.keyStore}
    key-store-password: ${javax.net.ssl.keyStorePassword}
  servlet:
    context-path: /

sg:
  api.code: quark-batch
  security:
    api:
      entry-point: "/api/**"
      paths:
        - pattern: /api/v1/**
          scopes: api.quark.v1
    sgconnect:
      enabled: true

  #    oauth2:
  #      scopes: api.quark.v1

  oauth2:
    enabled: true
    cache:
      enabled: true
    root-uri: https://sgconnect-hom.fr.world.socgen/sgconnect/oauth2
    userinfo: https://sgconnect-hom.fr.world.socgen/sgconnect/oauth2/userinfo


  monitoring:
    enabled: ${MONITORING_ENABLED:true}
    realm: ${SGMON_REALM}
    # Zipkin
    reporter:
      access-token-uri: ${SG_CONNECT_ROOT_URI}/access_token
      client-id: ${ZIPKIN_CLIENTID}
      client-secret: ${ZIPKIN_SECRET}

    # May be useful to avoid "The iss claim is not valid" when updating from sgsstack 9.1
    # token-analysis: opaque
  openapi:
    info:
      title: quark-backend API
      description: Manage quark data
      version: "${parsedVersion.majorVersion}\
               .${parsedVersion.minorVersion}\
               .${parsedVersion.incrementalVersion}"
      contact:
        name: API support
        email: GSC-ITEC-SGS-FSO-FVS-UTIL@socgen.com
        url: https://developer.sgmarkets.com/explore/api/quark-backend/
      license:
        name: Copyright SG Group 2017–2023 - All rights reserved
    sg-connect:
      # Flow to be used by web UIs and SwaggerUI
      # Autorization are managed through SG|IAM permissions
      # then only main SG|Connect scope is needed
      implicit:
        authorization-url: https://sgconnect-hom.fr.world.socgen/sgconnect/oauth2/authorize
        scopes:
          "[api.quark-batch-job.v1]": Authorization to use v1 of api.quark.v1 API
      # Define authorization code flow only if you include the necessary
      # endpoints involved (callback from SG Connect)

      #authorization-code:
      #  authorization-url: ${SG_CONNECT_ROOT_URI}/authorize
      #  token-url: ${SG_CONNECT_ROOT_URI}/access_token
      #  scopes:
      #    "[api.quark-batch-job.v1]": >-
      #      Authorization to use v1 of quark-batch-job API
      #    "[api.quark-batch-job.quark.create]": >-
      #      Authorization to create quark
      #    "[api.quark-batch-job.quark.read]": >-
      #      Authorization to read quark
      #    "[api.quark-batch-job.quark.update]": >-
      #      Authorization to update quark
      #    "[api.quark-batch-job.quark.delete]": >-
      #      Authorization to delete quark

      # Flow to be used by another program (batch, another API…), where the
      # user identity is not mandatory; permissions are managed with scopes
      client-credentials:
        token-url: ${SG_CONNECT_ROOT_URI}/access_token
        scopes:
          "[api.quark-batch-job.v1]": >-
            Authorization to use v1 of quark-backend API
  #          "[api.quark-batch-job.quark.create]": >-
  #            Authorization to create quark
  #          "[api.quark-batch-job.quark.read]": >-
  #            Authorization to read quark
  #          "[api.quark-batch-job.quark.update]": >-
  #            Authorization to update quark
  #          "[api.quark-batch-job.quark.delete]": >-
  #            Authorization to delete quark

  swagger-ui3:
    client-id: b57d602c-dfd9-4606-90ce-74527c324cca
#    b57d602c-dfd9-4606-90ce-74527c324cca
    enabled: true
    use-sg-theme: true
    custom-oidc-support-enabled: true

springdoc:
  # Show Actuator in the OpenAPI document in order to use Actuator endpoints
  # with the authenticated user. You should usually not do this in a deployed
  # environment but rather use an admin-server.
  # See https://codecentric.github.io/spring-boot-admin/current/
  show-actuator: true
  # Allow multiple major version using multiple groups
  group-configs:
    # https://springdoc.org/properties.html
    - group: all
      paths-to-match: /**
    - group: v1
      paths-to-match: /api/v1/**
  swagger-ui:
    groups-order: DESC
    # this should be the LATEST group (see group-configs above)
    urls-primary-name: v1
    #oauth.additional-query-string-params:
    #  # L2 is the default so you don't have to specify it
    #  acr_values: L2
    #  #nonce: swagger

queue:
  runqueue: quark-batch-run-dev
  # executequeue: quark-batch-run-dev

documentpool:
  basePath: D:\Documents

# Sample rate-limiter configuration, see https://sgithub.fr.world.socgen/sgm-api/apibank-java/tree/main/http-rate-limiter
rate-limiter:
  enabled: true
  time-precision: SYSTEM_MILLISECONDS
  global-policy: GLOBAL
  policies:
    - name: READ_SOME_OPERATION
      bandwidths:
        - maxCapacity: 3000
          window: 1h
    - name: WRITE_SOME_OPERATION
      bandwidths:
        - maxCapacity: 100
          window: 1m
    # health, swagger-ui, api-docs…
    - name: GLOBAL
      bandwidths:
        - maxCapacity: 10000
          window: 2h
```


## 27. `src/test/java/com/socgen/sgs/api/quark/engine/domain/RunExecutionContextTest.java`

SHA-256: `sha256-9665e40d587607953324b6f57245de8cbebe260690299a21761cc4f0abf4216c`

```java
package com.socgen.sgs.api.quark.engine.domain;

import org.junit.jupiter.api.Test;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;

class RunExecutionContextTest {

    @Test
    void rootRunOwnsRelativeAndAbsoluteWorkspacePaths() {
        RunExecutionContext context = new RunExecutionContext(42);

        assertEquals("R_42/G_10.QXP", context.getPoolPath("G_10.QXP"));
        assertEquals("D:\\Documents\\R_42\\G_10.QXP",
                context.getPoolPathAbsolute("G_10.QXP", "D:\\Documents\\"));
    }

    @Test
    void samePathUploadsOnlyOnceWithinOneRootTree() {
        RunExecutionContext context = new RunExecutionContext(42);
        AtomicInteger uploads = new AtomicInteger();

        context.upload("R_42/D_1.QXP", uploads::incrementAndGet);
        context.upload("R_42/D_1.QXP", uploads::incrementAndGet);

        assertEquals(1, uploads.get());
    }

    @Test
    void failedUploadCanBeRetried() {
        RunExecutionContext context = new RunExecutionContext(42);
        AtomicInteger attempts = new AtomicInteger();

        assertThrows(IllegalStateException.class, () -> context.upload("R_42/D_1.QXP", () -> {
            attempts.incrementAndGet();
            throw new IllegalStateException("first attempt failed");
        }));
        context.upload("R_42/D_1.QXP", attempts::incrementAndGet);

        assertEquals(2, attempts.get());
    }

    @Test
    void followerWaitsForLeaderAndDoesNotUploadAgain() throws Exception {
        RunExecutionContext context = new RunExecutionContext(42);
        CountDownLatch leaderStarted = new CountDownLatch(1);
        CountDownLatch allowLeaderToFinish = new CountDownLatch(1);
        AtomicInteger uploads = new AtomicInteger();
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            Future<?> leader = executor.submit(() -> context.upload("R_42/D_1.QXP", () -> {
                uploads.incrementAndGet();
                leaderStarted.countDown();
                try {
                    allowLeaderToFinish.await();
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    throw new IllegalStateException(interrupted);
                }
            }));
            leaderStarted.await();
            Future<?> follower = executor.submit(
                    () -> context.upload("R_42/D_1.QXP", uploads::incrementAndGet));

            assertFalse(follower.isDone());
            allowLeaderToFinish.countDown();
            leader.get();
            follower.get();
            assertEquals(1, uploads.get());
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void informedFileIsNotUploadedAgain() {
        RunExecutionContext context = new RunExecutionContext(42);
        AtomicInteger uploads = new AtomicInteger();

        context.inform("R_42/G_10_2.QXP");
        context.upload("R_42/G_10_2.QXP", uploads::incrementAndGet);

        assertEquals(0, uploads.get());
    }

    @Test
    void retryingSameDatabaseRunWithFreshRootContextUploadsAgain() {
        RunExecutionContext firstAttempt = new RunExecutionContext(42);
        RunExecutionContext retryAttempt = new RunExecutionContext(42);
        AtomicInteger uploads = new AtomicInteger();

        firstAttempt.upload("R_42/G_10.QXP", uploads::incrementAndGet);
        retryAttempt.upload("R_42/G_10.QXP", uploads::incrementAndGet);

        assertEquals(2, uploads.get());
    }

    @Test
    void documentCachesIncludeMissesAndAreIsolatedBetweenRoots() {
        RunExecutionContext first = new RunExecutionContext(42);
        RunExecutionContext second = new RunExecutionContext(43);
        AtomicInteger loads = new AtomicInteger();

        assertNull(first.getOrLoadReferenceDocument("1|2|3|4|5", () -> {
            loads.incrementAndGet();
            return null;
        }));
        assertNull(first.getOrLoadReferenceDocument("1|2|3|4|5", () -> {
            loads.incrementAndGet();
            return new DocumentDomain();
        }));
        assertNotNull(second.getOrLoadReferenceDocument("1|2|3|4|5", () -> {
            loads.incrementAndGet();
            return new DocumentDomain();
        }));

        assertEquals(2, loads.get());
    }
}
```


## 28. `src/test/java/com/socgen/sgs/api/quark/engine/business/DocumentStructureBusinessWave2Test.java`

SHA-256: `sha256-8fbb78714fc4aa70b4dec8c048fdc033e68f98818142195f909102ad64a9e301`

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunExecutionContext;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DocumentStructureBusinessWave2Test {

    private FilePoolPort filePool;
    private GetGabaritXmlBusiness xmlSource;
    private GetDocumentProjectBusiness projectSource;
    private DocumentStructureBusiness structures;
    private Run run;

    @BeforeEach
    void setUp() {
        filePool = mock(FilePoolPort.class);
        xmlSource = mock(GetGabaritXmlBusiness.class);
        projectSource = mock(GetDocumentProjectBusiness.class);
        structures = new DocumentStructureBusiness(filePool, xmlSource, projectSource);
        run = new Run();
        run.setId(42);
        run.setExecutionContext(new RunExecutionContext(42));
        run.setRunProperties(new RunProperties());
    }

    @Test
    void xmlIsFetchedOnceAndThenReturnedFromDocumentCache() {
        DocumentDomain document = document(10);
        when(xmlSource.fetchXml(document.getFilePoolPath())).thenReturn("<PROJECT/>");

        QxpXml first = structures.ensureXml(run, document);
        QxpXml second = structures.ensureXml(run, document);

        assertSame(first, second);
        verify(xmlSource).fetchXml(document.getFilePoolPath());
        verify(filePool).addFile(run.getExecutionContext(), document.getFilePoolPath(), document.getData());
    }

    @Test
    void gabaritXmlFailureCachesFreshEmptyAndDegradesRun() {
        DocumentDomain firstDocument = document(10);
        DocumentDomain secondDocument = document(11);
        run.setGabarit(firstDocument);
        when(xmlSource.fetchXml(anyString())).thenThrow(new IllegalStateException("QXPS unavailable"));

        QxpXml firstEmpty = structures.ensureXml(run, firstDocument);
        QxpXml secondEmpty = structures.ensureXml(run, secondDocument);

        assertTrue(firstDocument.isModeDegrade());
        assertTrue(run.getRunProperties().isModeDegrade());
        assertTrue(secondDocument.isModeDegrade());
        assertNotSame(firstEmpty, secondEmpty);
        verify(xmlSource, times(2)).fetchXml(anyString());
    }

    @Test
    void ordinaryDocumentFailureDoesNotDegradeWholeRun() {
        DocumentDomain document = document(20);
        when(projectSource.getProject(document.getFilePoolPath()))
                .thenThrow(new IllegalStateException("QXPS unavailable"));

        QxpProject empty = structures.ensureProject(run, document);

        assertTrue(empty.isEmpty());
        assertTrue(document.isModeDegrade());
        assertFalse(run.getRunProperties().isModeDegrade());
    }

    @Test
    void projectIsLazyAndCachedIndependentlyFromXml() {
        DocumentDomain document = document(30);
        QxpProject project = QxpProject.empty();
        when(projectSource.getProject(document.getFilePoolPath())).thenReturn(project);

        assertSame(project, structures.ensureProject(run, document));
        assertSame(project, structures.ensureProject(run, document));

        verify(projectSource).getProject(document.getFilePoolPath());
        verifyNoInteractions(xmlSource);
    }

    private static DocumentDomain document(int id) {
        return DocumentDomain.builder()
                .id(id)
                .data(new byte[]{1, 2, 3})
                .format("QXP")
                .filePoolPath("R_42/D_" + id + ".QXP")
                .build();
    }
}
```


## 29. `src/test/java/com/socgen/sgs/api/quark/engine/domain/task/TaskDocumentTargetWave2Test.java`

SHA-256: `sha256-5a2e8a43606abc74eb318e224a58a7c31f8a8264689d5be8d1b764a81299f34d`

```java
package com.socgen.sgs.api.quark.engine.domain.task;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class TaskDocumentTargetWave2Test {

    private Run run;

    @BeforeEach
    void setUp() {
        run = new Run();
        run.setId(42);
        DocumentDomain gabarit = DocumentDomain.builder()
                .id(10)
                .filePoolPath("R_42/G_10.QXP")
                .build();
        gabarit.setQxpXml(QxpXml.empty());
        run.setGabarit(gabarit);
    }

    @Test
    void pdfUsesFirstGeneratedPageSuffixEvenWhenDestinationIsNull() {
        TaskDocument task = new TaskDocument(7, run);
        task.setSubTaskType(SubTaskTypeEnum.FILE_PDF);

        assertEquals("_1", task.resolveTargetBlocName());
    }

    @Test
    void qxpDataUsesFirstPipeSeparatedDestinationWithoutTrimming() {
        TaskDocument task = new TaskDocument(7, run);
        task.setSubTaskType(SubTaskTypeEnum.FILE_QXP_DATA);
        task.setDestinationBlocName(" BOX_A |BOX_B");

        assertEquals(" BOX_A ", task.resolveTargetBlocName());
    }

    @Test
    void missingResolvedBlockAddsUnspecifiedErrorAndDoesNotThrow() {
        TaskDocument task = new TaskDocument(7, run);
        task.setSubTaskType(SubTaskTypeEnum.FILE_QXP_DATA);
        task.setDestinationBlocName("ABSENT");

        assertDoesNotThrow(task::evaluateInfo);
        assertEquals(1, run.getErrors().size());
        assertEquals(RunError.UNSPECIFIED, run.getErrors().get(0).getCategory());
        assertEquals("Le bloc ABSENT est introuvable dans le document R_42/G_10.QXP",
                run.getErrors().get(0).getMessage());
    }

    @Test
    void emptyTargetAddsUnspecifiedMissingDestinationError() {
        TaskDocument task = new TaskDocument(7, run);
        task.setSubTaskType(SubTaskTypeEnum.FILE_QXP_DATA);
        task.setCommentaire("document task");

        task.evaluateInfo();

        assertEquals(1, run.getErrors().size());
        assertEquals(RunError.UNSPECIFIED, run.getErrors().get(0).getCategory());
        assertTrue(run.getErrors().get(0).getMessage().contains("[7 - document task]"));
    }

    @Test
    void previousDocumentUsesPositionBeforeDestinationAndPreservesExistingInfoWhenAbsent() {
        TaskQxpPrevious task = new TaskQxpPrevious(8, run);
        task.setPositionBlocName("POSITION");
        task.setDestinationBlocName("DESTINATION|OTHER");
        assertEquals("POSITION", task.resolveTargetBlocName());

        task.setPositionBlocName("");
        assertEquals("DESTINATION", task.resolveTargetBlocName());

        task.setDestinationBlocName(null);
        task.getProperties().setPageNum(99);
        task.getProperties().setLayoutName("existing");
        task.evaluateInfo();
        assertEquals(99, task.getProperties().getPageNum());
        assertEquals("existing", task.getProperties().getLayoutName());
    }
}
```


## 30. `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImplWave2Test.java`

SHA-256: `sha256-40fad335e606b878883e69f6b8de2f7cecc1829c4623837963297f1e9123f391`

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.exception.EngineException;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.service.task.TaskPostProcessService;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class ProcessTasksServiceImplWave2Test {

    @Test
    void controlledAnchorFailureIsRecordedAndFollowingTaskStillRuns() {
        TaskProcessService processor = mock(TaskProcessService.class);
        TaskPostProcessService postProcessor = mock(TaskPostProcessService.class);
        ProcessTasksServiceImpl service = new ProcessTasksServiceImpl(processor, postProcessor);
        ReflectionTestUtils.setField(service, "stepLimit", 5000);
        Run run = new Run();
        run.setId(42);
        RunProperties properties = new RunProperties();
        properties.setIdSuivi(900);
        run.setRunProperties(properties);
        TaskBase failing = task(7, run);
        TaskBase following = task(8, run);
        run.getTasks().put(7, failing);
        run.getTasks().put(8, following);
        doThrow(new EngineException(RunError.BLOQUANTE,
                "La position des ancres est incohérente l'ancre HAUT et plus basse que l'ancre BAS"))
                .when(processor).process(failing);

        service.processTasks(run);

        assertTrue(failing.isInError());
        assertFalse(following.isInError());
        verify(processor).process(failing);
        verify(processor).process(following);
        RunError controlled = run.getErrors().stream()
                .filter(error -> error.getMessage().contains("position des ancres"))
                .findFirst()
                .orElseThrow();
        assertEquals(RunError.CRITIQUE, controlled.getCategory());
        assertTrue(controlled.getMessage().contains("Erreur lors du processing de la tache 7"));
        assertTrue(controlled.getMessage().contains("HAUT"));
        assertTrue(controlled.getMessage().contains("BAS"));
    }

    private static TaskBase task(int id, Run run) {
        TaskBase task = new TaskBase(id, run) {
            @Override
            public void prepare() {
                // Nothing required for this processing-boundary test.
            }
        };
        task.setTodo(true);
        return task;
    }
}
```


## 31. `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/CheckServiceImplWave2Test.java`

SHA-256: `sha256-ea24aea32b220510ae91717800c1b3d938c9759f45717df33a00b6f6029f5a12`

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.service.ProcessTasksService;
import com.socgen.sgs.api.quark.engine.service.QxpsCallerService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class CheckServiceImplWave2Test {

    private DocumentStructureBusiness structures;
    private ProcessTasksService tasksService;
    private QxpsCallerService qxps;
    private CheckServiceImpl check;
    private Run run;

    @BeforeEach
    void setUp() {
        structures = mock(DocumentStructureBusiness.class);
        tasksService = mock(ProcessTasksService.class);
        qxps = mock(QxpsCallerService.class);
        check = new CheckServiceImpl(structures, tasksService, qxps);
        run = new Run();
        run.setId(42);
        run.setRunProperties(new RunProperties());
        run.setGabarit(DocumentDomain.builder().id(10).filePoolPath("R_42/G_10.QXP").build());
    }

    @Test
    void checkWithoutOverflowOrDocumentStorageDoesNotResolveXml() {
        check.check(run);

        verifyNoInteractions(structures, tasksService, qxps);
    }

    @Test
    void zeroOverflowStillClearsStaleStateAndAppliesTodoTransition() {
        TaskDynamique dynamic = new TaskDynamique(7, run);
        dynamic.setTodo(true);
        dynamic.setControlOverflow(true);
        dynamic.getBoxNames().add("BOX_A");
        dynamic.getOverflowBoxes().add("STALE");
        TaskSql other = new TaskSql(8, run);
        other.setTodo(true);
        run.getTasks().put(7, dynamic);
        run.getTasks().put(8, other);
        QxpXml xml = QxpXml.empty();
        when(structures.ensureXml(run, run.getGabarit())).thenAnswer(invocation -> {
            run.getGabarit().setQxpXml(xml);
            return xml;
        });
        check.check(run);

        assertTrue(dynamic.getOverflowBoxes().isEmpty());
        assertFalse(dynamic.isTodo());
        assertFalse(other.isTodo());
        verify(structures).ensureXml(run, run.getGabarit());
        verifyNoInteractions(tasksService, qxps);
    }

    @Test
    void actualOverflowReprocessesOnlyOwningDynamicTask() {
        TaskDynamique owner = new TaskDynamique(7, run);
        owner.setTodo(true);
        owner.setControlOverflow(true);
        owner.getBoxNames().add("OVERFLOWING");
        TaskDynamique other = new TaskDynamique(8, run);
        other.setTodo(true);
        other.setControlOverflow(true);
        other.getBoxNames().add("SAFE");
        run.getTasks().put(7, owner);
        run.getTasks().put(8, other);
        QxpXml xml = mock(QxpXml.class);
        when(xml.getOverflowBoxes()).thenReturn(java.util.List.of("OVERFLOWING"));
        when(structures.ensureXml(run, run.getGabarit())).thenAnswer(invocation -> {
            run.getGabarit().setQxpXml(xml);
            return xml;
        });
        doAnswer(invocation -> {
            run.getGabarit().purgeXmlAndProject();
            return null;
        }).when(qxps).process(run);

        check.check(run);

        assertEquals(java.util.List.of("OVERFLOWING"), owner.getOverflowBoxes());
        assertTrue(owner.isTodo());
        assertFalse(other.isTodo());
        verify(tasksService).processTasks(run);
        verify(qxps).process(run);
        assertNull(run.getGabarit().getQxpXml(),
                "a real caller invalidates XML during reprocessing; Check must not force a final refresh");
    }
}
```


## 32. `src/test/java/com/socgen/sgs/api/quark/engine/business/LoadTaskDocumentsBusinessWave2Test.java`

SHA-256: `sha256-f4ed62cf3e6ad7abf4e554fae5f2a1cab50e2771ec19d1a25683221409e7c921`

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunExecutionContext;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDocument;
import com.socgen.sgs.api.quark.engine.domain.task.TaskQxpPrevious;
import com.socgen.sgs.api.quark.engine.infra.dao.GetDocumentDao;
import com.socgen.sgs.api.quark.engine.infra.dao.GetLastQxpCertifieDao;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.config.QxpsProperties;
import com.socgen.sgs.api.quark.engine.infra.pdf.PdfSplitter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class LoadTaskDocumentsBusinessWave2Test {

    private GetDocumentDao referenceDao;
    private GetLastQxpCertifieDao previousDao;
    private FilePoolPort filePool;
    private LoadTaskDocumentsBusiness loader;
    private Run run;

    @BeforeEach
    void setUp() {
        referenceDao = mock(GetDocumentDao.class);
        previousDao = mock(GetLastQxpCertifieDao.class);
        filePool = mock(FilePoolPort.class);
        QxpsProperties properties = new QxpsProperties();
        properties.getPool().setDefaultPath("D:\\Documents\\");
        loader = new LoadTaskDocumentsBusiness(
                referenceDao, previousDao, filePool, mock(PdfSplitter.class), properties);
        run = new Run();
        run.setId(42);
        run.setExecutionContext(new RunExecutionContext(42));
        RunProperties runProperties = new RunProperties();
        runProperties.setIdFndCode("FUND");
        runProperties.setIdUnitCode("UNIT");
        runProperties.setSociete("COMPANY");
        runProperties.setIdLangue(1);
        runProperties.setIdSuivi(900);
        run.setRunProperties(runProperties);
    }

    @Test
    void equalReferenceKeysShareOneLookupAndOneLazyDocumentObject() {
        DocumentDomain source = new DocumentDomain(100, "source", "QXP", "D", new byte[]{1});
        when(referenceDao.getDocument(eq(5), anyString(), anyString(), anyString(), eq(1), isNull()))
                .thenReturn(source);
        TaskDocument first = qxpDocumentTask(7);
        TaskDocument second = qxpDocumentTask(8);
        run.getTasks().put(7, first);
        run.getTasks().put(8, second);

        loader.loadDocuments(run);

        assertSame(source, first.getDocument());
        assertSame(source, second.getDocument());
        assertFalse(source.hasQxpXml());
        assertFalse(source.hasQxpProject());
        verify(referenceDao).getDocument(eq(5), eq("FUND"), eq("UNIT"), eq("COMPANY"), eq(1), isNull());
    }

    @Test
    void equalMissingReferenceKeysCacheTheMiss() {
        TaskDocument first = qxpDocumentTask(7);
        TaskDocument second = qxpDocumentTask(8);
        run.getTasks().put(7, first);
        run.getTasks().put(8, second);

        loader.loadDocuments(run);

        verify(referenceDao, times(1)).getDocument(anyInt(), any(), any(), any(), anyInt(), any());
        assertNull(first.getDocument());
        assertNull(second.getDocument());
        assertEquals(2, run.getErrors().size());
    }

    @Test
    void previousQxpIsCachedButNeitherUploadedNorStructurallyFetchedDuringPrepare() {
        DocumentDomain source = new DocumentDomain(101, "previous", "QXP", "D", new byte[]{1});
        when(previousDao.getLastQxpCertifie(900, 0)).thenReturn(source);
        TaskQxpPrevious first = previousTask(9);
        TaskQxpPrevious second = previousTask(10);
        run.getTasks().put(9, first);
        run.getTasks().put(10, second);

        loader.loadDocuments(run);

        assertSame(source, first.getDocument());
        assertSame(source, second.getDocument());
        assertFalse(source.hasQxpXml());
        assertFalse(source.hasQxpProject());
        verify(previousDao).getLastQxpCertifie(900, 0);
        verifyNoInteractions(filePool);
    }

    private TaskDocument qxpDocumentTask(int id) {
        TaskDocument task = new TaskDocument(id, run);
        task.setTodo(true);
        task.setIdSousCategorie(5);
        task.setFormatDocument("QXP");
        task.prepare();
        return task;
    }

    private TaskQxpPrevious previousTask(int id) {
        TaskQxpPrevious task = new TaskQxpPrevious(id, run);
        task.setTodo(true);
        task.setPreviousTypeRapport("any");
        task.prepare();
        return task;
    }
}
```


## 33. `src/test/java/com/socgen/sgs/api/quark/engine/business/QxpsCallerBusinessWave1Test.java`

SHA-256: `sha256-e3ab3e946be420b470997186dfbdc96f189ab8e84e552762cc980b8ff64fad65`

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.RunTask;
import com.socgen.sgs.api.quark.engine.domain.RunTaskStep;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
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
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
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
        business = new QxpsCallerBusiness(
                httpClient, soapClient, properties, filePool, mock(DocumentStructureBusiness.class));

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

    @Test
    void twoStepsReuseInitialXmlRefreshOnlyBetweenStepsAndDoNotRefreshAfterFinalStep() {
        GetGabaritXmlBusiness xmlSource = mock(GetGabaritXmlBusiness.class);
        DocumentStructureBusiness structures = new DocumentStructureBusiness(
                filePool, xmlSource, mock(GetDocumentProjectBusiness.class));
        QxpsProperties properties = new QxpsProperties();
        properties.getPool().setDefaultPath("D:\\Documents\\");
        QxpsCallerBusiness cacheAwareBusiness = new QxpsCallerBusiness(
                httpClient, soapClient, properties, filePool, structures);
        run.getGabarit().setData(new byte[]{1});
        run.getGabarit().setQxpXml(QxpXml.empty());
        RunTaskStep first = executableSoapStep();
        RunTaskStep second = executableSoapStep();
        RunTask runTask = mock(RunTask.class);
        when(runTask.getSteps()).thenReturn(List.of(first, second));
        when(runTask.getNbExcludeBoxes()).thenReturn(0);
        run.setRunTask(runTask);
        QxpsResponseInfo literal = new QxpsResponseInfo();
        literal.setBinaryResponse(new byte[]{9});
        when(httpClient.execute(anyString(), any(LiteralMessage.class))).thenReturn(literal);
        when(xmlSource.fetchXml("R_7/G_45_1.QXP")).thenReturn("<PROJECT/>");

        cacheAwareBusiness.process(run);

        verify(xmlSource).fetchXml("R_7/G_45_1.QXP");
        verifyNoMoreInteractions(xmlSource);
        assertNull(run.getGabarit().getQxpXml(),
                "the final changed document stays unresolved until a later structural consumer");
        assertEquals("R_7/G_45_2.QXP", run.getGabarit().getFilePoolPath());
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
```


## 34. `src/test/java/com/socgen/sgs/api/quark/engine/domain/RunTest.java`

SHA-256: `sha256-2f9efda299f350dae4e2d75efda98d03757acbdb000ec367f136ed71a4716529`

```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness;
import com.socgen.sgs.api.quark.engine.business.GetDocumentProjectBusiness;
import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
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

        DocumentStructureBusiness structures = new DocumentStructureBusiness(
                filePoolPort, getGabaritXmlBusiness, mock(GetDocumentProjectBusiness.class));

        run.prepareGabarit(getGabaritBusiness, structures, filePoolPort, documentIdentityPort);

        assertTrue(properties.isModeDegrade());
        assertTrue(document.isModeDegrade());
        assertNotNull(document.getQxpXml());
        verify(filePoolPort, atLeastOnce()).addFile(
                same(run.getExecutionContext()), eq(document.getFilePoolPath()), same(document.getData()));
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

        DocumentStructureBusiness structures = new DocumentStructureBusiness(
                filePoolPort, getGabaritXmlBusiness, mock(GetDocumentProjectBusiness.class));
        sizeLimitedRun.prepareGabarit(
                getGabaritBusiness, structures, filePoolPort, documentIdentityPort);

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

        DocumentStructureBusiness structures = new DocumentStructureBusiness(
                filePoolPort, getGabaritXmlBusiness, mock(GetDocumentProjectBusiness.class));
        run.prepareGabarit(getGabaritBusiness, structures, filePoolPort, documentIdentityPort);

        assertTrue(properties.isModeDegrade());
        assertNotNull(document.getQxpXml());
        verifyNoInteractions(documentIdentityPort);
    }
}
```


## 35. `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImplTest.java`

SHA-256: `sha256-9c7d92abf7c767770d9107af8ca4631025fdc636411b3990a028b0b38a49ac39`

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.GetDocumentProjectBusiness;
import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;
import com.socgen.sgs.api.quark.engine.business.GetInParamsBusiness;
import com.socgen.sgs.api.quark.engine.business.GetRunPropertiesBusiness;
import com.socgen.sgs.api.quark.engine.business.RunStartUpdateBusiness;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunExecutionContext;
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
    @Mock
    private GetDocumentProjectBusiness getDocumentProjectBusiness;

    private RunProperties runProperties;

    @BeforeEach
    void setUp() {
        ReflectionTestUtils.setField(processRunService, "documentStructureBusiness",
                new DocumentStructureBusiness(filePoolPort, getGabaritXmlBusiness, getDocumentProjectBusiness));
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
    @DisplayName("Child keeps its Oracle run id while inheriting the root execution workspace")
    void childRunInheritsRootExecutionContextWithoutChangingBusinessId() {
        RunExecutionContext rootContext = new RunExecutionContext(42);
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        Run child = processRunService.runChildProcessor(new RunIdDto(99), rootContext);

        assertEquals(99, child.getId());
        assertSame(rootContext, child.getExecutionContext());
        assertEquals("R_42/DF_99.QXP", child.getPoolPath("DF_99.QXP"));
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


## 36. `src/test/java/com/socgen/sgs/api/quark/engine/domain/DocumentDomainTest.java`

SHA-256: `sha256-dc7831187f536c2be42e442a9bdfd233d3bce14a39b0ace63fabe9bf12dafc42`

```java
package com.socgen.sgs.api.quark.engine.domain;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.BeforeEach;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("DocumentDomain Tests")
class DocumentDomainTest {

    private byte[] testData;

    @BeforeEach
    void setUp() {
        testData = "test content".getBytes();
    }

    @Test
    @DisplayName("Should create DocumentDomain with no arguments")
    void shouldCreateEmptyDocumentDomain() {
        DocumentDomain doc = new DocumentDomain();

        assertNull(doc.getId());
        assertNull(doc.getFileName());
        assertFalse(doc.isGabarit());
    }

    @Test
    @DisplayName("Should create DocumentDomain with all constructor parameters")
    void shouldCreateDocumentDomainWithAllParameters() {
        Integer id = 123;
        String name = "TestDoc";
        String format = "QXP";
        String prefix = "D";

        DocumentDomain doc = new DocumentDomain(id, name, format, prefix, testData);

        assertEquals(id, doc.getId());
        assertEquals(name, doc.getName());
        assertEquals(format, doc.getFormat());
        assertEquals(prefix, doc.getPrefix());
        assertEquals(testData, doc.getData());
        assertEquals(1, doc.getIdLangue());
        assertFalse(doc.isGabarit());
    }

    @Test
    @DisplayName("Should generate fileName correctly")
    void shouldGenerateFileNameCorrectly() {
        DocumentDomain doc = new DocumentDomain(432, "TestDoc", "pdf", "D", testData);

        assertEquals("D_432.pdf", doc.getFileName());
    }

    @Test
    @DisplayName("Should set and get properties")
    void shouldSetAndGetProperties() {
        DocumentDomain doc = new DocumentDomain();

        doc.setId(100);
        doc.setName("DocumentName");
        doc.setFormat("QXP");
        doc.setPrefix("G");
        doc.setIdLangue(2);
        doc.setGabarit(true);
        doc.setFilePoolPath("R_100/G_100.qxp");
        doc.setFileFullPath("D:/Documents/R_100/G_100.qxp");

        assertEquals(100, doc.getId());
        assertEquals("DocumentName", doc.getName());
        assertEquals("QXP", doc.getFormat());
        assertEquals("G", doc.getPrefix());
        assertEquals(2, doc.getIdLangue());
        assertTrue(doc.isGabarit());
        assertEquals("R_100/G_100.qxp", doc.getFilePoolPath());
        assertEquals("D:/Documents/R_100/G_100.qxp", doc.getFileFullPath());
    }

    @Test
    @DisplayName("Should verify all file prefix constants")
    void shouldVerifyFilePrefixConstants() {
        assertEquals("D", DocumentDomain.FILE_DOCUMENT_PREFIX);
        assertEquals("G", DocumentDomain.FILE_GABARIT_PREFIX);
        assertEquals("DG", DocumentDomain.FILE_DOCUMENT_GABARIT_PREFIX);
        assertEquals("DCG", DocumentDomain.FILE_DOCUMENT_CERTIFIE_GABARIT_PREFIX);
        assertEquals("DF", DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX);
        assertEquals("GT", DocumentDomain.FILE_GABARIT_TEMPLATE_PREFIX);
    }

    @Test
    @DisplayName("Should handle various formats")
    void shouldHandleVariousFormats() {
        assertNotNull(new DocumentDomain(1, "doc1", "PDF", "D", testData));
        assertNotNull(new DocumentDomain(2, "doc2", "QXP", "G", testData));
        assertNotNull(new DocumentDomain(3, "doc3", "JPG", "D", testData));
        assertNotNull(new DocumentDomain(4, "doc4", "DOC", "DG", testData));
    }

    @Test
    @DisplayName("Should handle null data")
    void shouldHandleNullData() {
        DocumentDomain doc = new DocumentDomain(100, "TestDoc", "QXP", "G", null);

        assertEquals(100, doc.getId());
        assertNull(doc.getData());
        // Extension is now the format VERBATIM (no lowercasing) — matches .NET. Finding #57.
        assertEquals("G_100.QXP", doc.getFileName());
    }

    @Test
    @DisplayName("Should have default language ID of 1")
    void shouldHaveDefaultLanguageId() {
        DocumentDomain doc = new DocumentDomain(100, "test", "QXP", "G", testData);

        assertEquals(1, doc.getIdLangue());
    }

    @Test
    @DisplayName("Should set gabarit flag correctly")
    void shouldSetGabaritFlagCorrectly() {
        DocumentDomain doc = new DocumentDomain(100, "test", "QXP", "G", testData);

        assertFalse(doc.isGabarit());

        doc.setGabarit(true);
        assertTrue(doc.isGabarit());
    }

    @Test
    @DisplayName("Fail-soft size limit is strict: only data above the configured limit degrades")
    void failSoftSizeLimitUsesStrictGreaterThanBoundary() {
        assertFalse(new DocumentDomain(1, "small", "QXP", "D", new byte[1])
                .evaluateModeDegrade(2));
        assertFalse(new DocumentDomain(2, "exact", "QXP", "D", new byte[2])
                .evaluateModeDegrade(2));
        assertTrue(new DocumentDomain(3, "large", "QXP", "D", new byte[3])
                .evaluateModeDegrade(2));
        assertFalse(new DocumentDomain(4, "not-qxp", "PDF", "D", new byte[3])
                .evaluateModeDegrade(2));
    }
}
```


## 37. `src/test/java/com/socgen/sgs/api/quark/engine/service/task/impl/CompartimentTaskProcessStrategyWave2Test.java`

SHA-256: `sha256-34c81e1c0baa03fc307c914864a1c8ea0a052f16ad0fafef620a0e0fdef282d1`

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;
import com.socgen.sgs.api.quark.engine.business.GetCompartimentRunsBusiness;
import com.socgen.sgs.api.quark.engine.business.GetDocumentByIdBusiness;
import com.socgen.sgs.api.quark.engine.business.GetRunPropertiesBusiness;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunResult;
import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.domain.task.TaskCompartiment;
import com.socgen.sgs.api.quark.engine.service.ProcessRunService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class CompartimentTaskProcessStrategyWave2Test {

    @Test
    void degradedChildProjectContributesNoBoxesWithoutAddingAnError() {
        DocumentStructureBusiness structures = mock(DocumentStructureBusiness.class);
        CompartimentTaskProcessStrategy strategy = new CompartimentTaskProcessStrategy(
                mock(GetCompartimentRunsBusiness.class),
                mock(ProcessRunService.class),
                mock(GetRunPropertiesBusiness.class),
                mock(GetDocumentByIdBusiness.class),
                structures);

        Run parent = new Run();
        parent.setId(42);
        TaskCompartiment task = new TaskCompartiment(5, parent);

        Run child = new Run();
        child.setId(99);
        RunResult result = new RunResult();
        result.setFinalQxp(new DocumentDomain(700, "child", "QXP",
                DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, new byte[]{1}));
        child.setResult(result);

        when(structures.ensureProject(eq(parent), any(DocumentDomain.class)))
                .thenAnswer(invocation -> {
                    DocumentDomain snapshot = invocation.getArgument(1);
                    snapshot.setModeDegrade(true);
                    return QxpProject.empty();
                });

        Integer lastPage = ReflectionTestUtils.invokeMethod(strategy, "addRunBlocs", task, child, 7);

        assertEquals(7, lastPage);
        assertTrue(parent.getErrors().isEmpty());
    }
}
```

<!-- PACKET-END -->
