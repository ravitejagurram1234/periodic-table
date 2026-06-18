# EOS Quark — Batch 9 Changes

**Task #17 — Compartiment incorporation subsystem** (Run_Previous reuse + child final-QXP → project parsing + EmptyRunChildQXP / EmptyRunChildProject errors).

Cross-reference: .NET `Process_Compartiment` (Execute_Runs / Render_Runs / Add_Run_Blocs), `Run_Previous.Render`, `Document.QXPProject`, `QXPS_File_Manager.Get_Document` / `Get_Project`.

## Summary

| # | File | Change |
|---|------|--------|
| 1 | `com/socgen/sgs/api/quark/engine/infra/interop/qxpsm/QxpsmSoapClient.java` | CHANGED — added getProject(getXPressDOM) |
| 2 | `com/socgen/sgs/api/quark/engine/service/ProcessRunService.java` | CHANGED — runProcessor returns Run |
| 3 | `com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java` | CHANGED — return run |
| 4 | `com/socgen/sgs/api/quark/engine/infra/dao/GetDocumentByIdDao.java` | NEW — QXP_PK_RUN.Get_Document_ByID port |
| 5 | `com/socgen/sgs/api/quark/engine/infra/dao/impl/GetDocumentByIdDaoImpl.java` | NEW — Get_Document_ByID SimpleJdbcCall |
| 6 | `com/socgen/sgs/api/quark/engine/business/GetDocumentByIdBusiness.java` | NEW — dao bridge |
| 7 | `com/socgen/sgs/api/quark/engine/business/GetDocumentProjectBusiness.java` | NEW — getXPressDOM bridge |
| 8 | `com/socgen/sgs/api/quark/engine/service/task/impl/CompartimentTaskProcessStrategy.java` | CHANGED — Run_Previous + child project parsing |

> **Live-Quark dependency:** `QxpsmSoapClient.getProject` issues a real `getXPressDOM` SOAP call to QuarkXPress Server Manager. It can only be validated end-to-end against a running QXPSM (see the test guide). All other logic is unit-testable offline.

## How to apply

Either copy each file below into place, or run the self-applying script from the `quark-engine` module root:

```bash
bash batch9_apply.sh
```

---

## 1. `com/socgen/sgs/api/quark/engine/infra/interop/qxpsm/QxpsmSoapClient.java`

_CHANGED — added getProject(getXPressDOM)_

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

            // Build QRequestContext
            QRequestContext context = new QRequestContext();
            context.setDocumentName(documentName);
            context.setRequest(currentHead);
            context.setMaxRetries(qxpsmProperties.getMaxRetries());
            context.setRequestTimeout(qxpsmProperties.getTimeout());

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

## 2. `com/socgen/sgs/api/quark/engine/service/ProcessRunService.java`

_CHANGED — runProcessor returns Run_

```java
package com.socgen.sgs.api.quark.engine.service;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
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

    RunProperties getRunProperties(RunIdDto runIdDto);
}


```

---

## 3. `com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java`

_CHANGED — return run_

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

## 4. `com/socgen/sgs/api/quark/engine/infra/dao/GetDocumentByIdDao.java`

_NEW — QXP_PK_RUN.Get_Document_ByID port_

```java
package com.socgen.sgs.api.quark.engine.infra.dao;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;

/**
 * DAO for loading a generated document by its id. Cross-reference: .NET QXPS_File_Manager.Get_Document
 * (which calls QXP_PK_RUN.Get_Document_ByID). Used by the Run_Previous compartiment path.
 */
public interface GetDocumentByIdDao {

    /**
     * Load a document (QXP) by its id.
     *
     * @param idDocument the document id (e.g. RunProperties.idLastQxp)
     * @return the document, or null if not found
     */
    DocumentDomain getDocumentById(int idDocument);
}
```

---

## 5. `com/socgen/sgs/api/quark/engine/infra/dao/impl/GetDocumentByIdDaoImpl.java`

_NEW — Get_Document_ByID SimpleJdbcCall_

```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.infra.dao.GetDocumentByIdDao;
import lombok.extern.slf4j.Slf4j;
import oracle.jdbc.OracleTypes;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.SqlOutParameter;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.List;
import java.util.Map;

/**
 * Calls QXP_PK_RUN.Get_Document_ByID (FUNCTION → cursor) to load a document by id.
 * Cross-reference: .NET QXPS_File_Manager.Get_Document(id) (used by Run_Previous).
 */
@Repository
@Slf4j
public class GetDocumentByIdDaoImpl implements GetDocumentByIdDao {

    private static final String RESULT_KEY = "result_cursor";
    private final SimpleJdbcCall getDocumentByIdCall;

    @Autowired
    public GetDocumentByIdDaoImpl(DataSource dataSource) {
        this.getDocumentByIdCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_RUN")
                .withFunctionName("Get_Document_ByID")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlOutParameter(RESULT_KEY, OracleTypes.CURSOR,
                                (rs, rowNum) -> mapFromResultSet(rs)),
                        new SqlParameter("p_id_document", Types.NUMERIC)
                );
    }

    @Override
    public DocumentDomain getDocumentById(int idDocument) {
        log.info("Fetching document by id: {}", idDocument);

        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_document", idDocument);

        try {
            Map<String, Object> result = getDocumentByIdCall.execute(params);

            @SuppressWarnings("unchecked")
            List<DocumentDomain> rows = (List<DocumentDomain>) result.get(RESULT_KEY);

            if (rows == null || rows.isEmpty()) {
                log.warn("No document found for id: {}", idDocument);
                return null;
            }
            return rows.get(0);
        } catch (Exception e) {
            log.error("Error fetching document by id: {}", idDocument, e);
            throw new RuntimeException("Failed to fetch document by id: " + idDocument, e);
        }
    }

    private DocumentDomain mapFromResultSet(ResultSet rs) throws SQLException {
        DocumentDomain doc = new DocumentDomain();
        doc.setId(rs.getInt("id_document"));
        doc.setName(rs.getString("nom"));
        doc.setFormat("QXP");
        doc.setPrefix(DocumentDomain.FILE_DOCUMENT_PREFIX);
        doc.setData(rs.getBytes("contenu"));
        doc.setIdLangue(rs.getInt("id_langue"));
        String fileName = String.format("%s_%d.%s", doc.getPrefix(), doc.getId(), doc.getFormat());
        doc.setFileName(fileName);
        // Pool name used to upload (addFile) and to read back (getXPressDOM/getProject) — keep consistent.
        doc.setFilePoolPath(fileName);
        return doc;
    }
}
```

---

## 6. `com/socgen/sgs/api/quark/engine/business/GetDocumentByIdBusiness.java`

_NEW — dao bridge_

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.infra.dao.GetDocumentByIdDao;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/** Bridge for loading a generated document by id (service → business → dao). */
@Component
@RequiredArgsConstructor
public class GetDocumentByIdBusiness {

    private final GetDocumentByIdDao getDocumentByIdDao;

    public DocumentDomain getDocumentById(int idDocument) {
        return getDocumentByIdDao.getDocumentById(idDocument);
    }
}
```

---

## 7. `com/socgen/sgs/api/quark/engine/business/GetDocumentProjectBusiness.java`

_NEW — getXPressDOM bridge_

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.infra.interop.qxpsm.QxpsmSoapClient;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
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
@Slf4j
public class GetDocumentProjectBusiness {

    private final QxpsmSoapClient qxpsmSoapClient;

    /**
     * Fetch the QXP project (DOM) of a pooled document. Returns {@link QxpProject#EMPTY} when the
     * document has no project or the call fails (so the caller can report an empty-child error).
     *
     * @param documentName the pool path / document name
     * @return the parsed QxpProject, or QxpProject.EMPTY
     */
    public QxpProject getProject(String documentName) {
        try {
            Project project = qxpsmSoapClient.getProject(documentName);
            return project != null ? new QxpProject(project) : QxpProject.EMPTY;
        } catch (Exception e) {
            log.error("Failed to get project for document [{}]: {}", documentName, e.getMessage(), e);
            return QxpProject.EMPTY;
        }
    }
}
```

---

## 8. `com/socgen/sgs/api/quark/engine/service/task/impl/CompartimentTaskProcessStrategy.java`

_CHANGED — Run_Previous + child project parsing_

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.business.GetCompartimentRunsBusiness;
import com.socgen.sgs.api.quark.engine.business.GetDocumentByIdBusiness;
import com.socgen.sgs.api.quark.engine.business.GetDocumentProjectBusiness;
import com.socgen.sgs.api.quark.engine.business.GetRunPropertiesBusiness;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
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
    private final GetDocumentProjectBusiness getDocumentProjectBusiness;
    private final FilePoolPort filePool;

    /**
     * Constructor with @Lazy on ProcessRunService to break circular dependency.
     * Circular: ProcessRunService → ProcessTasksService → strategies → this → ProcessRunService
     */
    public CompartimentTaskProcessStrategy(
            GetCompartimentRunsBusiness getCompartimentRunsBusiness,
            @Lazy ProcessRunService processRunService,
            GetRunPropertiesBusiness getRunPropertiesBusiness,
            GetDocumentByIdBusiness getDocumentByIdBusiness,
            GetDocumentProjectBusiness getDocumentProjectBusiness,
            FilePoolPort filePool) {
        this.getCompartimentRunsBusiness = getCompartimentRunsBusiness;
        this.processRunService = processRunService;
        this.getRunPropertiesBusiness = getRunPropertiesBusiness;
        this.getDocumentByIdBusiness = getDocumentByIdBusiness;
        this.getDocumentProjectBusiness = getDocumentProjectBusiness;
        this.filePool = filePool;
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
            log.error("Unknown compartiment mode for task [{}]", task.getId());
            return;
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
                RunProperties childProps = new RunProperties();
                childProps.setIdFndCode(compartimentCode);
                childProps.setRunId(runId);
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
                    executed = processRunService.runProcessor(new RunIdDto(childRun.getId()));
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
        task.setChildRuns(executedChildren);
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

        // Put the previous document into the pool so getXPressDOM can read it back.
        filePool.addFile(doc.getFilePoolPath(), doc.getData());
        prev.setGabarit(doc);
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
        if (childRun.getResult() == null || childRun.getResult().getFinalQxp() == null
                || childRun.getGabarit() == null || childRun.getGabarit().getFilePoolPath() == null) {
            task.getRun().getErrors().add(new RunError(2,
                    "EmptyRunChildQXP: pas de QXP final pour le run enfant " + childRun.getId()));
            log.warn("Child run [{}] has no final QXP, skipping", childRun.getId());
            return lastPage;
        }

        // Fetch the child's generated QXP structure (DOM) via QXPSM getXPressDOM.
        // Cross-reference: .NET child_Run.Result.Final_QXP.QXPProject.
        QxpProject qxpProject = getDocumentProjectBusiness.getProject(childRun.getGabarit().getFilePoolPath());

        // EmptyRunChildProject: the child QXP has no parseable project.
        if (qxpProject == null || qxpProject == QxpProject.EMPTY
                || qxpProject.getProject() == null
                || qxpProject.getProject().getLayouts() == null) {
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

---

