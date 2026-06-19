# EOS Quark — Batch 10 Changes (validation fixes)

Fixes from the validation report (`EOS_Quark_Engine_Validation_Findings.md`): **F1, F3, F4, F5, F6, F7, F8, F9, F10**. (F11 was already mitigated; F2 + F14 ship separately as Batch 11.)

> **Important — F1:** this batch RE-APPLIES Batch 8 (the Rule-2 business-bridge refactor) which was missing from the shared repo. It adds `business/QxpsCallerBusiness` + `business/GetGabaritXmlBusiness` and makes `QxpsCallerServiceImpl`/`CheckServiceImpl` thin delegators with no `infra` imports, so `CleanArchitectureLayersTest` (Rule 2) passes.

## Summary

| # | Finding | File | Change |
|---|---------|------|--------|
| 1 | F1(Batch8) | `com/socgen/sgs/api/quark/engine/business/QxpsCallerBusiness.java` | + F7 render-error propagation + F8 verbatim extension |
| 2 | F1(Batch8) | `com/socgen/sgs/api/quark/engine/business/GetGabaritXmlBusiness.java` | NEW — service→business→infra XML-fetch bridge |
| 3 | F1(Batch8) | `com/socgen/sgs/api/quark/engine/service/impl/QxpsCallerServiceImpl.java` | — thin delegator, no infra imports (Rule2) |
| 4 | F1(Batch8) | `com/socgen/sgs/api/quark/engine/service/impl/CheckServiceImpl.java` | — uses GetGabaritXmlBusiness, no infra imports (Rule2) |
| 5 | F3 | `com/socgen/sgs/api/quark/engine/domain/RunError.java` | — severity constants UNSPECIFIED=1/CRITIQUE=2/BLOQUANTE=3 (match .NET Error_Type) |
| 6 | F3 | `com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java` | fatal=BLOQUANTE(3) + F6 RunInSafeMode Critique in finally |
| 7 | F3 | `com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImpl.java` | comment + F5 no-bloc=UNSPECIFIED(1) |
| 8 | F4 | `com/socgen/sgs/api/quark/engine/domain/RunProperties.java` | — getPoolPathAbsolute backslash normalization (Windows SaveAs path) |
| 9 | F9 | `com/socgen/sgs/api/quark/engine/infra/interop/qxpsm/QxpsmSoapClient.java` | — QRequestContext fields + 1h timeout fallback |
| 10 | F10 | `com/socgen/sgs/api/quark/engine/service/task/impl/DocumentTaskProcessStrategy.java` | — RunError on genuine duplicate (TBox/TTable) |

## How to apply

```bash
bash batch10_apply.sh   # from the quark-engine module root
```
Then rebuild + run the arch test:
```bash
mvn -q -DskipTests compile && mvn -q -Dtest=CleanArchitectureLayersTest test
```

---

## 1. `com/socgen/sgs/api/quark/engine/business/QxpsCallerBusiness.java`

_F1(Batch8) + F7 render-error propagation + F8 verbatim extension_

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
                // QXPS-side render failure only (e.g. empty document) — swallow as .NET does.
                // Any other exception is NOT caught here and propagates → run marked ERROR.
                log.error("PDF render failed (QXPS) for run [{}]: {}", run.getId(), e.getMessage(), e);
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
        // Use the Format verbatim (no case change) — matches .NET QXPS_Caller.GetNewGabaritNameExt,
        // which uses gabarit.Format as-is. Lowercasing diverged from the .NET-produced pool name.
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

---

## 2. `com/socgen/sgs/api/quark/engine/business/GetGabaritXmlBusiness.java`

_F1(Batch8) NEW — service→business→infra XML-fetch bridge_

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

---

## 3. `com/socgen/sgs/api/quark/engine/service/impl/QxpsCallerServiceImpl.java`

_F1(Batch8) — thin delegator, no infra imports (Rule2)_

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

---

## 4. `com/socgen/sgs/api/quark/engine/service/impl/CheckServiceImpl.java`

_F1(Batch8) — uses GetGabaritXmlBusiness, no infra imports (Rule2)_

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

---

## 5. `com/socgen/sgs/api/quark/engine/domain/RunError.java`

_F3 — severity constants UNSPECIFIED=1/CRITIQUE=2/BLOQUANTE=3 (match .NET Error_Type)_

```java
package com.socgen.sgs.api.quark.engine.domain;

import lombok.Getter;

/**
 * Represents an error that occurred during run execution.
 *
 * Cross-reference: .NET Error (Type + Message)
 */
@Getter
public class RunError {

    /**
     * Error severity codes, matching .NET {@code Error_Type} EXACTLY (these are persisted to the DB
     * via {@code QXP_PK_RUN.Insert_Run_Errors}, so the numeric value is load-bearing):
     * <ul>
     *   <li>{@link #UNSPECIFIED} = 1 — Non spécifiée</li>
     *   <li>{@link #CRITIQUE} = 2 — Critique (interrupts the current task)</li>
     *   <li>{@link #BLOQUANTE} = 3 — Bloquante (interrupts the whole run)</li>
     * </ul>
     */
    public static final int UNSPECIFIED = 1;
    public static final int CRITIQUE = 2;
    public static final int BLOQUANTE = 3;

    /** Severity code — see {@link #UNSPECIFIED}/{@link #CRITIQUE}/{@link #BLOQUANTE}. */
    private final int category;
    private final String message;

    public RunError(int category, String message) {
        this.category = category;
        this.message = message != null && !message.isBlank() ? message : "aucun";
    }
}
```

---

## 6. `com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java`

_F3 fatal=BLOQUANTE(3) + F6 RunInSafeMode Critique in finally_

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

---

## 7. `com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImpl.java`

_F3 comment + F5 no-bloc=UNSPECIFIED(1)_

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunTask;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
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
                log.error("Error preparing task {}: {}", task.getId(), ex.getMessage(), ex);
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
            } catch (Exception ex) {
                task.setInError(true);
                run.getErrors().add(new RunError(CRITIQUE,
                        "Erreur lors du traitement de la tache " + task.getId() + " : " + ex.getMessage()));
                log.error("Error processing task {}: {}", task.getId(), ex.getMessage(), ex);
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
                log.error("Error post-processing task {}: {}", task.getId(), ex.getMessage(), ex);
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

---

## 8. `com/socgen/sgs/api/quark/engine/domain/RunProperties.java`

_F4 — getPoolPathAbsolute backslash normalization (Windows SaveAs path)_

```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.enums.GabaritSourceEnum;
import com.socgen.sgs.api.quark.engine.enums.TypeRapportEnum;
import lombok.Getter;
import lombok.Setter;
import lombok.NoArgsConstructor;
import java.time.LocalDate;

/**
 * Represents the properties of a Run object.
 * This class encapsulates all the configuration and metadata for a run.
 */
@Getter
@Setter
@NoArgsConstructor
public class RunProperties {
/*sup bro - by ananymous */
    // Constants for pagination
    public static final int PAGINATION_SIMPLE = 1;
    public static final int PAGINATION_DOUBLE = 2;

    // Run identification
    private TypeRapportEnum typeRapport = TypeRapportEnum.UNKNOWN;
    private String idFndCode;
    private String idUnitCode;
    private int idSuivi;

    // Company and language
    private LocalDate dateEcheance;
    private int idLangue;
    private String societe;
    private String codeLangue;

    // Template and document settings
    private GabaritSourceEnum gabaritSource = GabaritSourceEnum.DOCUMENT_COURANT;
    private int idSuiviGabaritSource = Integer.MIN_VALUE;
    private int idGabarit = Integer.MIN_VALUE;
    private int idGabaritTemplate = Integer.MIN_VALUE;

    // Run configuration
    private boolean integrerN1 = true;
    private TaskCompartimentMode compartimentMode = TaskCompartimentMode.UNKNOWN;
    private String runType;
    private boolean generateToWord = false;

    // Mode degrade flag (set when gabarit exceeds size limit)
    private boolean modeDegrade = false;

    // Generated files tracking
    private int idLastPdf = Integer.MIN_VALUE;
    private int idLastQxp = Integer.MIN_VALUE;
    private int idLastDoc = Integer.MIN_VALUE;

    // Pagination settings
    private int nbPageBySpread = PAGINATION_SIMPLE;

    // Storage type
    private StoreDataType storeDataType = StoreDataType.NONE;

    // Run ID for path generation
    private Integer runId;

    /**
     * Get the pool path for a given file name.
     * Returns a relative path in the format: R_runId/fileName
     *
     * @param fileName the file name
     * @return the pool path
     */
    public String getPoolPath(String fileName) {
        if (this.runId == null || fileName == null) {
            return fileName;
        }
        return String.format("R_%d/%s", this.runId, fileName);
    }

    /**
     * Get the absolute pool path for a given file name.
     * Returns an absolute path in the format: documentPoolBasePath/R_runId/fileName
     *
     * @param fileName the file name
     * @param documentPoolBasePath the base path for document pool (e.g., D:\Documents)
     * @return the absolute pool path
     */
    public String getPoolPathAbsolute(String fileName, String documentPoolBasePath) {
        if (this.runId == null || fileName == null || documentPoolBasePath == null) {
            return fileName;
        }
        // The Quark host is Windows: the SaveAs absolute path must use all-backslash separators,
        // matching .NET QXPS_File_Manager.GetPoolPathAbsolute/SetPoolPath which do .Replace("/","\\").
        // Strip any trailing separator on the base, then normalize every separator to '\'.
        String base = documentPoolBasePath.replaceAll("[/\\\\]+$", "");
        String raw = base + "/R_" + this.runId + "/" + fileName;
        return raw.replace("/", "\\");
    }
}






```

---

## 9. `com/socgen/sgs/api/quark/engine/infra/interop/qxpsm/QxpsmSoapClient.java`

_F9 — QRequestContext fields + 1h timeout fallback_

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxpsm;

import com.socgen.sgs.api.quark.engine.integration.soap.generated.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.net.URL;
import java.util.List;

/**
 * SOAP client for communicating with QuarkXPress Server Manager (QXPSM).
 * Uses the Axis 1.x generated stub to call processRequest.
 *
 * <p>Used for UPDATE steps (directCall=false) where text value changes
 * and structural modifications are sent via SOAP.
 *
 * <p>Request chain built inside QRequestContext:
 * RequestParameters → ModifierRequest → SaveAsRequest → QuarkXPressRenderRequest
 * (each linked via the inherited QRequest.request field)
 *
 * Cross-reference: .NET QXPSM_Call.SDKCall() / QXPS_Caller.Execute()
 */
@Component
@Slf4j
public class QxpsmSoapClient {

    private final QxpsmProperties qxpsmProperties;

    public QxpsmSoapClient(QxpsmProperties qxpsmProperties) {
        this.qxpsmProperties = qxpsmProperties;
    }

    /**
     * Execute a complete step via SOAP using the Axis-generated stub.
     * Builds the QRequest chain and calls processRequest on the QXPSM web service.
     *
     * @param documentName  the current document name in the pool
     * @param nameValues    name-value params to set (may be null or empty)
     * @param project       modification project (may be null if no structural changes)
     * @param saveAsPath    path for saving (e.g., pool absolute path)
     * @param saveAsName    new file name for the saved document
     * @return QContentData response containing streamValue (QXP binary) and/or textData
     */
    public QContentData executeStep(String documentName,
                                    List<NameValueParam> nameValues,
                                    Project project,
                                    String saveAsPath,
                                    String saveAsName) {
        log.info("QXPSM SOAP processRequest for document [{}]", documentName);

        try {
            // Get the Axis-generated stub
            QManagerSDKSvcServiceLocator locator = new QManagerSDKSvcServiceLocator();
            QManagerSDKSvc stub = locator.getqxpsmsdk(new URL(qxpsmProperties.getEndpoint()));

            // Build the request chain (last → first, then link)
            // 4. QXP Render (last in chain)
            QuarkXPressRenderRequest qxpRender = new QuarkXPressRenderRequest();

            // 3. SaveAs → chains to QXP Render
            SaveAsRequest saveAs = new SaveAsRequest();
            saveAs.setNewFilePath(saveAsPath);
            saveAs.setNewName(saveAsName);
            saveAs.setReplaceFile("true");
            saveAs.setSaveToPool("false");
            saveAs.setRequest(qxpRender);

            // 2. Modifier → chains to SaveAs (only if project has modifications)
            QRequest currentHead = saveAs;
            if (project != null && project.getLayouts() != null && project.getLayouts().length > 0) {
                ModifierRequest modifier = new ModifierRequest();
                modifier.setProject(project);
                modifier.setRequest(saveAs);
                currentHead = modifier;
            }

            // 1. RequestParameters → chains to Modifier or SaveAs (only if there are name-values)
            if (nameValues != null && !nameValues.isEmpty()) {
                RequestParameters params = new RequestParameters();
                params.setParams(nameValues.toArray(new NameValueParam[0]));
                params.setRequest(currentHead);
                currentHead = params;
            }

            // Build QRequestContext — set the same fields as .NET QXPSM_Call.InitContext.
            QRequestContext context = new QRequestContext();
            context.setDocumentName(documentName);
            context.setRequest(currentHead);
            // .NET QXPS_Call_Info defaults (set explicitly to document intent / match the wire).
            context.setResponseAsURL(false);
            context.setUseCache(false);
            context.setBypassFileInfo(false);
            context.setMaxRetries(qxpsmProperties.getMaxRetries());
            // .NET: if no timeout is configured, use 3600s (1h) instead of the SOAP default of 100s.
            int timeout = qxpsmProperties.getTimeout();
            context.setRequestTimeout(timeout > 0 ? timeout : 3600 * 1000);

            // Execute SOAP call
            log.debug("QXPSM calling processRequest with chain: {} → ... → QXPRender",
                    currentHead.getClass().getSimpleName());

            QContentData result = stub.processRequest(context);

            log.info("QXPSM processRequest completed for document [{}]", documentName);
            return result;

        } catch (Exception e) {
            log.error("QXPSM SOAP call failed for document [{}]: {}", documentName, e.getMessage(), e);
            throw new RuntimeException("QXPSM SOAP call failed for document: " + documentName, e);
        }
    }

    /**
     * Fetch the QuarkXPress DOM (Project) of a pooled document via getXPressDOM.
     * Used to read a child run's generated QXP structure for compartiment incorporation.
     *
     * <p>Cross-reference: .NET QXPS_File_Manager.Get_Project / Document.QXPProject.
     * NOTE: this is a live QuarkXPress Server Manager call — must be validated against a running server.
     *
     * @param documentName the pool path / document name of the saved QXP
     * @return the QuarkXPress DOM as a SOAP Project
     */
    public Project getProject(String documentName) {
        log.info("QXPSM getXPressDOM for document [{}]", documentName);
        try {
            QManagerSDKSvcServiceLocator locator = new QManagerSDKSvcServiceLocator();
            QManagerSDKSvc stub = locator.getqxpsmsdk(new URL(qxpsmProperties.getEndpoint()));
            return stub.getXPressDOM(documentName);
        } catch (Exception e) {
            log.error("QXPSM getXPressDOM failed for document [{}]: {}", documentName, e.getMessage(), e);
            throw new RuntimeException("QXPSM getXPressDOM failed for document: " + documentName, e);
        }
    }
}
```

---

## 10. `com/socgen/sgs/api/quark/engine/service/task/impl/DocumentTaskProcessStrategy.java`

_F10 — RunError on genuine duplicate (TBox/TTable)_

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

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
public class DocumentTaskProcessStrategy implements TaskProcessStrategy<TaskDocument> {

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
        TaskImagePosition imagePosition = task.getImagePosition();
        if (imagePosition == null && task.getPositionValues() != null) {
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
                if (i > 0 && imagePosition != null && srcBox != null
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
            doc.getQxpProject().analyse(task, false);
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

        log.debug("QXP_DATA VALUE: bloc [{}] = [{}] from source [{}]",
                destName, blocValue, sourceName);
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

---

