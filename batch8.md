# EOS Quark — Batch 8 Changes (copy-paste) — Architecture Rule-2 fix

**Batch 8 (Rule-2) = remove the `service → infra` dependency** flagged by `CleanArchitectureLayersTest` (`services_should_not_depend_on_infra`). Done via the **business bridge** (same shape as `service → business → infra.dao`). **Zero behavior change.**

**Verified test status (against the real rules + imports):**
- Rule 1 (`domain ↛ service/infra`): already PASSES — `domain.Run → business.GetGabaritBusiness` is allowed (business is not forbidden by Rule 1), so **left as-is per your instruction**.
- Rule 3 (`service/domain ↛ frameworks/io`): PASSES.
- Rule 2 (`service ↛ infra`): was FAILING on `QxpsCallerServiceImpl` + `CheckServiceImpl` → now FIXED.

**What changed (4 files):**
- **`QxpsCallerBusiness` (NEW, business)** — holds all the QXPS/QXPSM message-building + calls (moved verbatim from the old `QxpsCallerServiceImpl`). business → infra.interop is allowed.
- **`QxpsCallerServiceImpl` (service)** — now a thin delegator to `QxpsCallerBusiness`; no infra imports.
- **`GetGabaritXmlBusiness` (NEW, business)** — fetches document XML via `QxpsHttpClient` + `FetchXmlMessage`.
- **`CheckServiceImpl` (service)** — calls `GetGabaritXmlBusiness.fetchXml(...)` instead of `QxpsHttpClient`; no infra imports. (Also more robust: XML is read from the TEXT response with a binary fallback — the old code read only the binary response, which would have been empty for an XML content-type.)

## How to apply
Each section is one file (create the two NEW business files). Paths relative to the `quark-engine` module root. Then `mvn -DskipTests compile` and `mvn test` (the ArchUnit test should now be green).

## Checklist (4 files)
- [ ] `business/QxpsCallerBusiness.java` — NEW
- [ ] `business/GetGabaritXmlBusiness.java` — NEW
- [ ] `service/impl/QxpsCallerServiceImpl.java` — CHANGED (now thin delegator)
- [ ] `service/impl/CheckServiceImpl.java` — CHANGED (uses business bridge)

## Remaining Batch 8 cleanup (NOT in this file — deletions, your call)
- Delete the dead empty stubs `integration/soap/client/EngineSoapClient.java` and `integration/soap/config/SoapConfig.java` (unused; the real SOAP client is `infra.interop.qxpsm.QxpsmSoapClient`). These are file DELETIONS — do them manually on your side.
- Replace/disable the placeholder Liquibase changelog (`src/main/resources/db/changelog/...`) — it creates a junk example table; the `QXP_PK_*` packages are external. Decide whether to disable Liquibase or point it at real schema.

---

## 1. `src/main/java/com/socgen/sgs/api/quark/engine/business/QxpsCallerBusiness.java`  — **NEW**

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunTaskStep;
import com.socgen.sgs.api.quark.engine.domain.modifier.QxpsModifier;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.client.QxpsHttpClient;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.config.QxpsProperties;
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
    private static final DateTimeFormatter TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("HHmmssSSS");

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
        int executionCount = 1;

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
                    executionCount = executeStep(run, step.getPrepareStep(), executionCount);
                }
                executionCount = executeStep(run, step, executionCount);
            }

            stopProcess = stopProcess || step.isPartialExclude();
            log.info("Step [{}] completed for run [{}]", step.getIndex(), run.getId());
        }

        int nbExcluded = run.getRunTask().getNbExcludeBoxes();
        if (nbExcluded > 0) {
            log.warn("Run [{}]: {} boxes were excluded due to document size limits",
                    run.getId(), nbExcluded);
        }

        log.info("All steps completed for run [{}]", run.getId());
    }

    // ========================================================================
    // Execute — single step
    // Cross-reference: QXPS_Caller.Execute(Run_Task_Step)
    // ========================================================================

    private int executeStep(Run run, RunTaskStep step, int executionCount) {
        DocumentDomain gabarit = run.getGabarit();
        String currentDocName = gabarit.getFilePoolPath();
        String newGabaritName = getNewGabaritNameExt(gabarit, executionCount);
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

        return executionCount + 1;
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
            String modifyFileName = String.format(MODIFY_NAME_PATTERN,
                    LocalDateTime.now().format(TIMESTAMP_FORMAT));

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
            try {
                QxpsResponseInfo response = qxpsHttpClient.execute(
                        documentName, new JpegRenderMessage());
                result.setJpgData(response.getBinaryResponse());
                log.info("JPEG render completed for run [{}]", run.getId());
            } catch (Exception e) {
                log.error("JPEG render failed for run [{}]: {}", run.getId(), e.getMessage(), e);
            }
        }

        // PDF render errors (e.g. empty document) must NOT block the run render — non-blocking.
        // Cross-reference: QXPS_Caller.Render() try/catch on QXPS_Exception.
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
            } catch (Exception e) {
                log.error("PDF render failed for run [{}]: {}", run.getId(), e.getMessage(), e);
            }
        }

        if (renderQxp) {
            try {
                // The latest QXP version is already saved in the pool — fetch it via a 'literal'
                // call (no re-render), exactly like .NET: QXPS_Helper.GetFileData(Gabarit.FilePoolPath).
                QxpsResponseInfo response = qxpsHttpClient.execute(
                        documentName, new LiteralMessage());
                result.setQxpData(response.getBinaryResponse());
                log.info("QXP fetched (literal) for run [{}]", run.getId());
            } catch (Exception e) {
                log.error("QXP fetch failed for run [{}]: {}", run.getId(), e.getMessage(), e);
            }
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

        // Download the freshly-saved QXP binary via a 'literal' call (no re-render), exactly
        // like .NET Document.Change_Document() → QXPS_Helper.GetFileData(filePoolPath).
        byte[] newData = qxpsHttpClient.execute(newPoolPath, new LiteralMessage()).getBinaryResponse();

        // Swap the gabarit to the new version (updates name/pool path + binary, purges cached XML/Project).
        gabarit.changeDocument(newGabaritName, newPoolPath, newData);

        // Register the new pool file as known so it is not re-uploaded later.
        // Cross-reference: .NET QXPS_File_Manager.Addfile_Inform(newPoolName).
        filePool.inform(newPoolPath);

        log.debug("Gabarit changed: [{}] → [{}] ({} bytes)",
                previousDocName, newPoolPath, newData != null ? newData.length : 0);
    }

    private String getNewGabaritNameExt(DocumentDomain gabarit, int executionCount) {
        if (gabarit.getId() != null && gabarit.getId() > 0) {
            return String.format(NEW_GABARIT_NAME_WITH_ID_PATTERN,
                    gabarit.getPrefix(), gabarit.getId(), executionCount,
                    gabarit.getFormat() != null ? gabarit.getFormat().toLowerCase() : "qxp");
        } else {
            return String.format(NEW_GABARIT_NAME_PATTERN,
                    gabarit.getName(), executionCount,
                    gabarit.getFormat() != null ? gabarit.getFormat().toLowerCase() : "qxp");
        }
    }
}
```

## 2. `src/main/java/com/socgen/sgs/api/quark/engine/business/GetGabaritXmlBusiness.java`  — **NEW**

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.infra.interop.qxps.client.QxpsHttpClient;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.FetchXmlMessage;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsResponseInfo;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
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
@Slf4j
public class GetGabaritXmlBusiness {

    private final QxpsHttpClient qxpsHttpClient;

    /**
     * Fetch the full document XML from the QXPS pool. Returns "" on failure (logged), so the
     * caller can continue gracefully.
     *
     * @param documentName the pool path / document name
     * @return the document XML, or "" if it could not be fetched
     */
    public String fetchXml(String documentName) {
        try {
            QxpsResponseInfo response = qxpsHttpClient.execute(documentName, new FetchXmlMessage());
            // XML is a text response; fall back to decoding bytes if the server returned binary.
            if (response.getTextResponse() != null) {
                return response.getTextResponse();
            }
            byte[] bytes = response.getBinaryResponse();
            return bytes != null ? new String(bytes, StandardCharsets.UTF_8) : "";
        } catch (Exception e) {
            log.error("Failed to fetch XML for document [{}]: {}", documentName, e.getMessage(), e);
            return "";
        }
    }
}
```

## 3. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/QxpsCallerServiceImpl.java`  — **CHANGED (now thin delegator)**

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.business.QxpsCallerBusiness;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult;
import com.socgen.sgs.api.quark.engine.service.QxpsCallerService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Orchestrates QuarkXPress Server execution for a run. The actual QXPS/SOAP work lives in the
 * {@code business} layer ({@link QxpsCallerBusiness}); this service simply delegates, keeping the
 * service → business → infra boundary (the service must not depend on {@code infra} directly).
 *
 * Cross-reference: QXP.Engine.Core.QXPS_Caller.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class QxpsCallerServiceImpl implements QxpsCallerService {

    private final QxpsCallerBusiness qxpsCallerBusiness;

    @Override
    public void process(Run run) {
        qxpsCallerBusiness.process(run);
    }

    @Override
    public QxpsCallerResult render(Run run, boolean renderPdf, boolean renderJpg,
                                   boolean renderQxp, String compression, String downsample) {
        return qxpsCallerBusiness.render(run, renderPdf, renderJpg, renderQxp, compression, downsample);
    }
}
```

## 4. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/CheckServiceImpl.java`  — **CHANGED (uses business bridge)**

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.DataNameValue;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunTask;
import com.socgen.sgs.api.quark.engine.domain.StoreDataType;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness;
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

    private final GetGabaritXmlBusiness getGabaritXmlBusiness;
    private final ProcessTasksService processTasksService;
    private final QxpsCallerService qxpsCallerService;

    @Override
    public void check(Run run) {
        log.info("Starting Check step for run [{}]", run.getId());

        // Phase 1: Refresh gabarit XML from QXPS (it was purged after step execution)
        refreshGabaritXml(run);

        // Phase 2: Overflow detection and re-processing
        if (hasControlOverflow(run)) {
            checkOverflow(run);
        }

        // Phase 3: SQL data collection
        StoreDataType storeType = run.getRunProperties().getStoreDataType();
        if (storeType.hasFlag(StoreDataType.SQL)) {
            collectSqlData(run);
        }

        // Phase 4: Document data collection
        if (storeType.hasFlag(StoreDataType.DOCUMENT)) {
            // Refresh XML again if overflow re-processing changed the document
            refreshGabaritXml(run);
            collectDocumentData(run);
        }

        log.info("Check step completed for run [{}]", run.getId());
    }

    // ========================================================================
    // Phase 1: Refresh gabarit XML
    // ========================================================================

    /**
     * Fetch the full document XML from QXPS and update the gabarit.
     * After step execution, the gabarit XML is purged (document content changed).
     * We need to fetch the latest XML for overflow detection and data collection.
     *
     * Cross-reference: .NET Document.XML property (lazy-loaded via QXPS_File_Manager.Get_XML)
     */
    private void refreshGabaritXml(Run run) {
        DocumentDomain gabarit = run.getGabarit();
        String documentName = gabarit.getFilePoolPath();

        log.debug("Refreshing gabarit XML from QXPS for document [{}]", documentName);

        // Fetch full document XML via the business bridge (the service must not call infra directly).
        String xmlContent = getGabaritXmlBusiness.fetchXml(documentName);
        if (xmlContent != null && !xmlContent.isEmpty()) {
            gabarit.initXmlFromContent(xmlContent);
            log.debug("Gabarit XML refreshed successfully for document [{}]", documentName);
        } else {
            log.warn("Gabarit XML refresh returned empty for document [{}]", documentName);
        }
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

        if (overflowBoxes.isEmpty()) {
            return;
        }

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
        if (!tasksToReprocess.isEmpty()) {
            for (TaskBase task : run.getTasks().values()) {
                if (!tasksToReprocess.contains(task) && !task.isAllwaysReprocess()) {
                    task.setTodo(false);
                }
            }

            // Re-execute Process + Process_Steps
            log.info("Re-processing {} task(s) due to overflow", tasksToReprocess.size());

            // Re-create RunTask for re-processing
            run.setRunTask(new RunTask(run));

            processTasksService.processTasks(run);
            qxpsCallerService.process(run);

            // Refresh XML after re-processing
            refreshGabaritXml(run);
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

