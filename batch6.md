# EOS Quark — Batch 6 Changes (copy-paste)

**Batch 6 = config alignment (now configurable) + small correctness fixes.**

**Configurable engine settings (your preference — tunable via `application.yaml`):**
- **`engine.gabarit.size-limit-before-fail-soft` = 209715200 (200 MB)** — Mode-Degrade threshold. *Deliberate deviation from .NET (68 MB) at your request.* Change the yaml value anytime.
- **`engine.step-limit` = 5000** — max blocs per modify step (.NET `Step_Limit`). Now read from yaml and applied to each `RunTask` (was a hardcoded 500).

**Small correctness fixes (verified vs .NET):**
- **QxpXml `BLOC_VALUE_PATTERN`** — removed an extra `/..` to match .NET `//ID[@NAME=…]/..//PARAGRAPH/RICHTEXT/text()` (was reading the wrong subtree → empty/wrong values).
- **`TaskBase.evaluateInfo()`** implemented (was empty): sets PageNum/LayoutName from the current gabarit XML — .NET `Evaluate_Info()`.
- **`TaskBase.getPageIdFromRelative()`** — conditional-bloc branch now resolves the page via `getPageNum(condName)` (both branches were identical) — .NET `Get_Page_ID_From_Relative()`.

**Verified — NO change (parity already correct):**
- `DocumentIdentityHelper` DID date format `MM/dd/yyyy HH:mm:ss` already matches .NET (invariant culture). Not a bug.

**DEFERRED — flagged (needs a missing .NET sub-feature):**
- Box-exclusion limitation (`RunTaskStep.getNbMaxBoxes`, `Average_Box_Size`, `Nb_Box_Max`): .NET computes `NbMaxBoxes = Nb_Box_Max / Box_Complexity`, and **`Document.Box_Complexity` is not yet ported to Java**. Not half-implemented; `getNbMaxBoxes()` still returns `Integer.MAX_VALUE` (limitation off). When implemented, `Nb_Box_Max` / `Average_Box_Size` will also be added as configurable yaml properties. Only affects fail-soft box-exclusion on very large documents.

## How to apply
Each section is one file — replace its entire contents with the block (create if missing). Paths are relative to the `quark-engine` module root. Then `mvn -DskipTests compile` and `mvn test`.

> Note: `ProcessTasksServiceImpl` is included again here — it changed since Batch 2 (added the configurable step-limit). Use THIS version.

## Checklist (7 files)
- [ ] `src/main/resources/application.yaml` — CHANGED
- [ ] `src/main/java/com/socgen/sgs/api/quark/engine/domain/Run.java` — CHANGED
- [ ] `src/main/java/com/socgen/sgs/api/quark/engine/domain/RunTask.java` — CHANGED
- [ ] `src/main/java/com/socgen/sgs/api/quark/engine/domain/xml/QxpXml.java` — CHANGED
- [ ] `src/main/java/com/socgen/sgs/api/quark/engine/domain/task/TaskBase.java` — CHANGED
- [ ] `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java` — CHANGED
- [ ] `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImpl.java` — CHANGED (also updated since Batch 2)

---

## 1. `src/main/resources/application.yaml`  — **CHANGED**

```yaml
---
spring:
  application.name: quark-engine-service
  # To avoid marshaling to JSON of null attribute
  jackson.default-property-inclusion: non-null
  jpa:
    hibernate.ddl-auto: ${HIBERNATE_DDL_AUTO:none}
    show-sql: ${JPA_SHOW_SQL:false}
  liquibase.enabled: true
  datasource:
    driver-class-name: oracle.jdbc.driver.OracleDriver
    url: jdbc:oracle:thin:@osfreygp3dwpp.ocp.cloud.socgen:1522:YGP3DWPP
    username: qxp
    password: ******** - commented since it's a secret
  rabbitmq:
    host: rabbitmq-vap-dev-965c0883.gslb2.trafficmanager.eu-fr-paris.cloud.socgen
    port: 5671  # AMQP port (use 5671 for AMQPS with SSL enabled)
    ssl:
      enabled: true
    virtual-host: vap-quark-host
    username: quark_dev
    password: quark_dev
    connection-timeout: 30000  # 30 seconds connection timeout
    requested-heartbeat: 60    # 60 seconds heartbeat interval
    listener:
      simple:
        default-requeue-rejected: false

  xml : xml/

qxp:
  thirdparty:
    url: http://srvcldqxpu001.dns43.socgen:8080/saveas/pdf/

quark-engine:
  rabitmq:
    run: quark-batch-run-dev

engine:
  gabarit:
    # Gabarit size above which the run goes into Mode Degrade (fail-soft) and skips modify/render.
    # Configurable. Set to 200 MB here (.NET EngineCoreSetting default was 68000000 / ~68 MB).
    size-limit-before-fail-soft: 209715200
  # Max blocs per modify step before a new step is created (.NET EngineCoreSetting Step_Limit).
  step-limit: 5000

qxps:
  server:
    url: "http://srvcldvapd001.dns43.socgen:8080"
    timeout: 3600000
  pool:
    default-path: "D:\\Documents\\"
    current-path: ""

qxpsm:
  soap:
    endpoint: http://srvcldqxpu001.dns43.socgen:8090/qxpsm/services/RequestService
    namespace: http://webservice.manager.quark.com
    connection-timeout: 10000
    timeout: 30000
    max-retries: 3
    retry-backoff-interval: 1000

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

## 2. `src/main/java/com/socgen/sgs/api/quark/engine/domain/Run.java`  — **CHANGED**

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

## 3. `src/main/java/com/socgen/sgs/api/quark/engine/domain/RunTask.java`  — **CHANGED**

```java
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

    /**
     * Set the split step box number (maximum blocs per modify step).
     *
     * @param splitStepBoxNumber max blocs per step
     */
    public void setSplitStepBoxNumber(int splitStepBoxNumber) {
        this.splitStepBoxNumber = splitStepBoxNumber;
    }
}
```

## 4. `src/main/java/com/socgen/sgs/api/quark/engine/domain/xml/QxpXml.java`  — **CHANGED**

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

    /** Singleton empty QxpXml instance (non-null but contains no data) */
    public static final QxpXml EMPTY = createFromXml(EMPTY_PROJECT_XML);

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
        String pageId = getPageID(blocName);
        if (pageId == null || pageId.isBlank()) {
            return 0;
        }
        try {
            // Remove trailing '*' characters (e.g., "10*" for left page, "24**" for right page)
            String cleaned = pageId.replaceAll("\\*+$", "");
            return Integer.parseInt(cleaned);
        } catch (NumberFormatException e) {
            log.warn("Cannot parse page number from pageID [{}] for bloc [{}]", pageId, blocName);
            return 0;
        }
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
                NodeList children = positionNode.getChildNodes();
                for (int i = 0; i < children.getLength(); i++) {
                    Node child = children.item(i);
                    if (child.getNodeType() != Node.ELEMENT_NODE) {
                        continue;
                    }
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
                if (currentPage > 0) {
                    info.getPageBoxes().merge(currentPage, 1, Integer::sum);
                }
                totalBoxes++;
            }

            // 4 - Count boxes inside tables
            NodeList tableGeomPages = (NodeList) xpath.evaluate(BOX_TABLE_GEOMETRY_PAGE_PATTERN, xmlDocument, XPathConstants.NODESET);
            for (int i = 0; i < tableGeomPages.getLength(); i++) {
                Node pageAttr = tableGeomPages.item(i);
                int currentPage = parseIntSafe(pageAttr.getNodeValue());
                if (currentPage > 0) {
                    // Count cell IDs relative to this table
                    Node tableGeomNode = pageAttr.getParentNode(); // GEOMETRY
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
                if (name == null || name.isBlank()) {
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
                if (value != null && !value.isBlank()) {
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
        if (value == null || value.isBlank()) {
            return 0;
        }
        try {
            String cleaned = value.replaceAll("\\*+$", "").trim();
            return Integer.parseInt(cleaned);
        } catch (NumberFormatException e) {
            return 0;
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

## 5. `src/main/java/com/socgen/sgs/api/quark/engine/domain/task/TaskBase.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.domain.task;
import com.socgen.sgs.api.quark.engine.domain.DataNameValue;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;
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
    private final Map<String, BlocBase> blocsUpdate = new LinkedHashMap<>();
    /** Blocs for structure/value modification (Modify command). Keyed by bloc name. */
    private final Map<String, BlocBase> blocsModify = new LinkedHashMap<>();
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
```

## 6. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java`  — **CHANGED**

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
            log.info("Run started successfully with runId: {}", runIdDto.getRunId());

            // Step 2: Load
            load(run);

            if (!run.getRunProperties().isModeDegrade()) {
                // Step 3: Prepare — call prepare() on every task before processing.
                // Cross-reference: .NET Run_Base.Launch_Prepare() / Prepare().
                processTasksService.prepareTasks(run);

                // Step 4: Process tasks (3-pass loop)
                processTasksService.processTasks(run);

                // Step 5: Execute modification steps against QXPS
                qxpsCallerService.process(run);

                // Step 6: Check — overflow detection + data collection
                checkService.check(run);
            }

            // Step 7: Render final outputs
            QxpsCallerResult renderResult = qxpsCallerService.render(
                    run, true, false, true, "true", "300");

            // Build RunResult from render data
            buildRunResult(run, renderResult);

            run.setStatus(RunStatus.GENERATED);

        } catch (Exception ex) {
            log.error("Run [{}] failed: {}", runIdDto.getRunId(), ex.getMessage(), ex);
            run.setStatus(RunStatus.ERROR);
            run.getErrors().add(new RunError(1, ex.getMessage()));
        } finally {
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

## 7. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImpl.java`  — **CHANGED (also updated since Batch 2)**

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

    /** RunError categories: 1=Bloquante, 2=Critique, 3=Warning. */
    private static final int CRITIQUE = 2;

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
                run.getErrors().add(new RunError(CRITIQUE,
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

