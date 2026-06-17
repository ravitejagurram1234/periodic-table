# EOS Quark — Batch 6B Changes (copy-paste) — task #16 Box_Complexity + getNbMaxBoxes

**Task #16 = box-exclusion limitation** (was disabled: `getNbMaxBoxes()` returned `Integer.MAX_VALUE`). Now ported from .NET and made configurable.

**What changed (5 files):**
- **`DocumentDomain`** — `getRatioSizeBox(avg)` and `getBoxComplexity(avg)` ported from .NET `Document.Ratio_Size_Box` / `Box_Complexity`: ratio = (QXP & data & XML & nbBox>100) ? data.length/nbBox : average; complexity = ratio / average.
- **`RunTaskStep.getNbMaxBoxes()`** — real formula: `Nb_Box_Max / clamp(boxComplexity, 0.8, 1.3)` (truncated), cached per step. Matches .NET `Run_Task_Step.NbMaxBoxes`. The existing `evaluateLimitation()` already uses this, so box-exclusion / fail-soft now actually engages on very large documents.
- **`Run`** — new `nbBoxMax` (17500) and `averageBoxSize` (3400) fields (defaults = .NET).
- **`application.yaml` + `ProcessRunServiceImpl`** — `engine.nb-box-max` and `engine.average-box-size` are now **configurable** (per your preference), injected onto the run; .NET defaults as fallback.

## How to apply
Each section is one file — replace its entire contents with the block. Paths relative to the `quark-engine` module root. Then `mvn -DskipTests compile` and `mvn test`.

## Checklist (5 files)
- [ ] `src/main/resources/application.yaml` — CHANGED
- [ ] `src/main/java/com/socgen/sgs/api/quark/engine/domain/Run.java` — CHANGED
- [ ] `src/main/java/com/socgen/sgs/api/quark/engine/domain/DocumentDomain.java` — CHANGED
- [ ] `src/main/java/com/socgen/sgs/api/quark/engine/domain/RunTaskStep.java` — CHANGED
- [ ] `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java` — CHANGED

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
  # Box-exclusion limitation (.NET EngineCoreSetting). NbMaxBoxes = nb-box-max / clamp(boxComplexity,0.8,1.3).
  nb-box-max: 17500
  average-box-size: 3400

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

## 3. `src/main/java/com/socgen/sgs/api/quark/engine/domain/DocumentDomain.java`  — **CHANGED**

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
     * @return the QxpXml instance, or QxpXml.EMPTY if not available
     */
    public QxpXml getQxpXml() {
        if (this.qxpXml == null) {
            return QxpXml.EMPTY;
        }
        return this.qxpXml;
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
     * @return the QxpProject instance, or QxpProject.EMPTY if not available
     */
    public QxpProject getQxpProject() {
        if (this.qxpProject == null) {
            return QxpProject.EMPTY;
        }
        return this.qxpProject;
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
     * @return the list of PDF file paths
     */
    public List<String> getPdfFiles() {
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
    public void changeDocument(String newFileName, String newFilePoolPath, byte[] newData) {
        this.fileName = newFileName;
        this.filePoolPath = newFilePoolPath;
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
                && getQxpXml().getProjectInfo().getNbBox() > 100) {
            return data.length / getQxpXml().getProjectInfo().getNbBox();
        }
        return averageBoxSize;
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
            this.fileName = String.format(FILE_NAME_PREFIX_PATTERN, this.prefix, this.id, this.format.toLowerCase());
        }
    }
}

```

## 4. `src/main/java/com/socgen/sgs/api/quark/engine/domain/RunTaskStep.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocPage;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.NameValueParam;
import lombok.Getter;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Defines one execution step for modifying a QuarkXPress document.
 * Tasks are grouped into steps based on type:
 * - UPDATE step: text value changes (via SOAP/ParamsValue)
 * - PAGINATION step: page create/remove operations (via HTTP/Modify)
 * - MODIFY steps: structural changes split at N blocs per step (via HTTP/Modify)
 *
 * Cross-reference: QXP.Engine.Core.Run_Task_Step
 */
@Getter
@Setter
@Slf4j
public class RunTaskStep {

    private static final int PAGE_PAIRE = 0;
    private static final int PAGE_IMPAIRE = 1;
    private static final int OFFSET_PAGE = 1;

    private int index = 0;
    private boolean directCall = true;
    private boolean pagination = false;

    private final List<BlocBase> blocsUpdate = new ArrayList<>();
    private final List<BlocBase> blocsModify = new ArrayList<>();
    private final List<NameValueParam> nameValues = new ArrayList<>();

    /** Tasks whose evaluateInfo() should be called before this step executes. */
    private final List<TaskBase> evaluateInfoTasks = new ArrayList<>();

    /** Optional preparation step (for double-page pagination edge cases). */
    private RunTaskStep prepareStep = null;

    private int nbBoxAdded = 0;
    private int nbBoxUpdate = 0;
    private int nbBoxExcluded = 0;
    private int nbBoxDoc = 0;

    private final Run run;

    public RunTaskStep(Run run) {
        this.run = run;
    }

    // ========================================================================
    // Prepare — called by Step 5 before execution
    // Cross-reference: Run_Task_Step.Prepare()
    // ========================================================================

    /**
     * Prepare this step for execution:
     * 1. Call evaluateInfo() on all associated tasks (re-evaluates page/layout from latest gabarit)
     * 2. Evaluate modifier and name-values
     * 3. Evaluate box count limitations
     *
     * @param ignoreStep if true, force-exclude all blocs in this step
     */
    public void prepare(boolean ignoreStep) {
        // Re-evaluate task info (page numbers, layout names) from latest gabarit version
        for (TaskBase task : evaluateInfoTasks) {
            task.evaluateInfo();
        }

        evaluateModifierAndValues();
        evaluateLimitation(ignoreStep);
    }

    /**
     * Evaluate pages for modify blocs and build name-value pairs for update blocs.
     *
     * Cross-reference: Run_Task_Step.Evaluate_Modifier_And_Values()
     */
    private void evaluateModifierAndValues() {
        // Evaluate pages for modify blocs
        for (BlocBase bloc : blocsModify) {
            bloc.evaluatePage();
        }

        // Handle pagination step page renumbering
        if (!blocsModify.isEmpty() && this.pagination) {
            updateBlocPagination(blocsModify);
        }

        // Build name-value pairs from update blocs
        for (BlocBase bloc : blocsUpdate) {
            if (bloc instanceof BlocBox) {
                BlocBox blocBox = (BlocBox) bloc;
                NameValueParam nv = new NameValueParam();
                nv.setParamName(bloc.getName());
                nv.setTextValue(blocBox.getValue());
                nameValues.add(nv);
            }
        }
        nbBoxUpdate += nameValues.size();
    }

    /**
     * Evaluate box count limitations to prevent exceeding QuarkXPress capacity.
     *
     * Cross-reference: Run_Task_Step.Evaluate_Limitation()
     */
    private void evaluateLimitation(boolean ignoreStep) {
        if (run.getGabarit() != null && run.getGabarit().getQxpXml() != null) {
            nbBoxDoc = run.getGabarit().getQxpXml().getProjectInfo().getNbBox();
        }

        // Evaluate modify blocs
        for (BlocBase bloc : blocsModify) {
            int nbBoxBloc = bloc.getNbBox();

            // Pagination steps don't check limitations (they may remove pages)
            if (!this.pagination && (nbBoxDoc > getNbMaxBoxes() || ignoreStep)) {
                bloc.setExclude(true);
                nbBoxExcluded += nbBoxBloc;
            } else {
                if (bloc.getAction() == BlocActionEnum.CREATE) {
                    nbBoxAdded += nbBoxBloc;
                    nbBoxDoc += nbBoxBloc;
                } else {
                    nbBoxUpdate += nbBoxBloc;
                }
            }
        }

        // If too many boxes, clear update blocs
        if (nbBoxDoc > getNbMaxBoxes()) {
            blocsUpdate.clear();
        }
    }

    /**
     * Get the maximum number of boxes this document can contain.
     * Based on document complexity ratio.
     *
     * Cross-reference: Run_Task_Step.NbMaxBoxes property
     */
    /** Clamp bounds for the box-complexity coefficient. Cross-reference: .NET Run_Task_Step.NbMaxBoxes. */
    private static final BigDecimal COMPLEXITY_MIN = new BigDecimal("0.8");
    private static final BigDecimal COMPLEXITY_MAX = new BigDecimal("1.3");

    /** Cached max-boxes for this step (re-evaluated per step, like .NET _nbMaxBoxes). */
    private Integer cachedNbMaxBoxes;

    /**
     * Maximum number of boxes a modified document may contain, evaluated from the gabarit's
     * box-complexity: {@code Nb_Box_Max / clamp(boxComplexity, 0.8, 1.3)}.
     * Cross-reference: .NET Run_Task_Step.NbMaxBoxes.
     */
    public int getNbMaxBoxes() {
        if (cachedNbMaxBoxes == null) {
            BigDecimal complexity = run.getGabarit().getBoxComplexity(run.getAverageBoxSize());
            BigDecimal divisor;
            if (complexity.compareTo(COMPLEXITY_MIN) < 0) {
                divisor = COMPLEXITY_MIN;
            } else if (complexity.compareTo(COMPLEXITY_MAX) > 0) {
                divisor = COMPLEXITY_MAX;
            } else {
                divisor = complexity;
            }
            cachedNbMaxBoxes = new BigDecimal(run.getNbBoxMax())
                    .divide(divisor, 0, RoundingMode.DOWN)
                    .intValue();
        }
        return cachedNbMaxBoxes;
    }

    /** Whether this step is fully excluded (no boxes added or updated). */
    public boolean isFullExclude() {
        return nbBoxAdded == 0 && nbBoxUpdate == 0;
    }

    /** Whether at least one box was excluded due to limitations. */
    public boolean isPartialExclude() {
        return nbBoxExcluded > 0;
    }

    // ========================================================================
    // Pagination — page renumbering for multi-task page operations
    // Cross-reference: Run_Task_Step.Update_Bloc_Pagination()
    // ========================================================================

    /**
     * Update page numbers across tasks when multiple tasks create/remove pages.
     * Handles both single-page and double-page (vis-à-vis) layouts.
     *
     * Cross-reference: Run_Task_Step.Update_Bloc_Pagination() lines 185-460
     */
    private void updateBlocPagination(List<BlocBase> blocs) {
        // Step 1: Group blocs by task
        Map<TaskBase, List<BlocBase>> taskBlocs = new LinkedHashMap<>();
        List<TaskBase> tasks = new ArrayList<>();

        for (BlocBase bloc : blocs) {
            taskBlocs.computeIfAbsent(bloc.getTask(), k -> new ArrayList<>()).add(bloc);
        }
        tasks.addAll(taskBlocs.keySet());

        // Sort tasks by starting page number
        tasks.sort((t1, t2) -> Integer.compare(
                t1.getProperties().getPageNum(),
                t2.getProperties().getPageNum()));

        boolean lagSpread = false;
        RunTaskStep localPrepareStep = new RunTaskStep(run);

        // Step 2: Analyse each task's page operations and update other tasks
        for (TaskBase task : tasks) {
            int nbPageCreer = 0;
            int nbPageSupprimer = 0;
            int minPageId = Integer.MAX_VALUE;
            int minCreationPageId = Integer.MAX_VALUE;
            int minCreationPageIdOriginale = Integer.MAX_VALUE;
            int maxCreationPageId = Integer.MIN_VALUE;
            BlocPage maxCreationPage = null;

            // Count page creates and removes for this task
            for (BlocBase bloc : taskBlocs.get(task)) {
                if (bloc instanceof BlocPage) {
                    switch (bloc.getAction()) {
                        case CREATE:
                            nbPageCreer++;
                            if (bloc.getPageId() > maxCreationPageId) {
                                maxCreationPageId = bloc.getPageId();
                                maxCreationPage = (BlocPage) bloc;
                            }
                            minCreationPageId = Math.min(minCreationPageId, bloc.getPageId());
                            minCreationPageIdOriginale = Math.min(
                                    minCreationPageIdOriginale, bloc.getPageIdOriginale());
                            break;
                        case REMOVE:
                            nbPageSupprimer++;
                            break;
                        default:
                            break;
                    }
                    minPageId = Math.min(minPageId, bloc.getPageId());
                }
            }

            // If pages were created, update other tasks' page numbers
            if (nbPageCreer > 0) {

                // Handle double-page (vis-à-vis) layout
                if (run.getRunProperties().getNbPageBySpread() == RunProperties.PAGINATION_DOUBLE) {
                    int checkPremiereCreation = lagSpread ? PAGE_PAIRE : PAGE_IMPAIRE;

                    // First creation page is on wrong side — needs reordering
                    if ((minCreationPageId % 2) == checkPremiereCreation) {
                        if (minCreationPageId > 1 && nbPageSupprimer > 0) {
                            int posPremiereSupp = maxCreationPageId + 1;
                            for (BlocBase bloc : taskBlocs.get(task)) {
                                if (bloc.getPageId() == posPremiereSupp) {
                                    bloc.setPageId(minCreationPageId);
                                } else if (bloc.getPageId() < posPremiereSupp
                                        && bloc.getPageId() >= minCreationPageId) {
                                    bloc.setPageId(bloc.getPageId() + OFFSET_PAGE);
                                }
                            }
                            maxCreationPageId += OFFSET_PAGE;
                        } else if (minCreationPageId == 1 && maxCreationPageId == 1) {
                            lagSpread = true;
                            for (BlocBase bloc : taskBlocs.get(task)) {
                                if (bloc.getPageId() > 1) {
                                    bloc.setLagSpread(true);
                                }
                            }
                        }
                    }

                    // Last creation page is even — needs dummy page for spread alignment
                    if (maxCreationPage != null
                            && (maxCreationPageId % 2) != checkPremiereCreation) {
                        maxCreationPage.setCreateNextDummyPage(true);
                        for (BlocBase bloc : taskBlocs.get(task)) {
                            if (bloc.getPageId() > maxCreationPageId) {
                                bloc.setPageId(bloc.getPageId() + OFFSET_PAGE);
                            }
                        }
                        nbPageCreer++;
                    }
                }

                // Update all other tasks' page numbers
                for (TaskBase taskSub : taskBlocs.keySet()) {
                    if (taskSub != task) {
                        for (BlocBase bloc : taskBlocs.get(taskSub)) {
                            if (bloc.getPageId() >= minPageId && bloc.getPageId() > 1) {
                                bloc.setPageId(bloc.getPageId() + nbPageCreer);
                            }
                            if (bloc.getPageId() > 1) {
                                bloc.setLagSpread(lagSpread);
                            }
                        }
                    }
                }
            }
        }

        // Store prepare step if needed
        if (localPrepareStep != this.prepareStep) {
            // prepareStep is set during complex double-page handling (simplified here)
        }
    }

    /**
     * Register a task for evaluateInfo callback during prepare().
     */
    public void addEvaluateInfoTask(TaskBase task) {
        if (!evaluateInfoTasks.contains(task)) {
            evaluateInfoTasks.add(task);
        }
    }

    /**
     * Remove a task from the evaluateInfo list (used when rebuilding steps).
     */
    public void removeEvaluateInfoTask(TaskBase task) {
        evaluateInfoTasks.remove(task);
    }
}
```

## 5. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java`  — **CHANGED**

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
    public void runProcessor(RunIdDto runIdDto) {
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

