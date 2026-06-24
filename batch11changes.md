# EOS Quark — Batch 11 (REDO) Changes

**Apply on top of Batch 10.** This **supersedes** the original Batch 11 delivery.

## What's different in this redo (2026-06-25)

1. **No `netLabel`.** `RunStatus.netLabel` / `getNetLabel()` → **`auditStatusLabel` / `getAuditStatusLabel()`**.
   The string **values are unchanged** (`ToGenerate` / `Generated` / `Error` / `Running`) — those are exactly
   what the `QXP_AUDIT_RUN.END_STATUS` column must contain, so `GROUP BY` / `WHERE` and historical rows stay
   consistent. Only the identifier name + comment changed.
2. **.NET-free code policy.** Identifiers and **Batch-11-introduced comments** carry no .NET references; the
   .NET source mapping lives **only in this `.md`** (table below). Per your instruction, **inherited comments
   from Batches 1–10 are left unchanged** ("no need to change existing comments now").

### Comment-scrub scope (your choice: "only Batch 11's own")
De-.NET'd only the comments tied to Batch 11 findings (#57, #73, #84, #92, #53/#82, #83/#87).
**Left in place** (inherited / not Batch 11's): the many B1–B10 comments inside `DocumentDomain` and
`QxpsCallerBusiness`, the Finding-#4 comment in `EndRunDaoImpl`, and **three class-header**
`Cross-reference: .NET …` lines (`AuditDaoImpl`, `GetDocumentDaoImpl`, `GetDocumentByIdDaoImpl`) — these
predate Batch 11's line-level fixes. **Say the word and I'll strip those class headers too.**

## Findings in this batch

| Finding | File | What changed | .NET source (reference only — not in code) |
|---|---|---|---|
| #47/#90 | `InsertDocumentDaoImpl` | `withoutProcedureColumnMetaDataAccess()` on the call (function param order is explicit) | `Proxy_Document.Insert_Document` (ODP.NET named params) |
| #91 | `EndRunDaoImpl` | `withoutProcedureColumnMetaDataAccess()` on `End_Run` + `Update_Status_Run` | `Proxy_Run.End_Run` / `Update_Status_Run` |
| #89 | `InsertDocumentDaoImpl` | null-safe `p_date_document` | `Proxy_Document.Insert_Document` |
| #57 | `DocumentDomain.generateFileNames`, `QxpsCallerBusiness.getNewGabaritNameExt` | use `format` **verbatim** (no `toLowerCase`) so the pool name matches | `Document.cs:115` / `QXPS_Caller.GetNewGabaritNameExt` |
| #92 | `DocumentDomain.changeDocument` (+`newFileFullPath` param), caller `QxpsCallerBusiness.updateGabaritAfterStep` passes `getPoolPathAbsolute` | keep absolute host path consistent, domain stays I/O-free | `Document.Change_Document` / `QXPS_File_Manager.GetPoolPathAbsolute` |
| #73 | `GetDocumentDaoImpl` | set `idLangue` from the input langue (cursor has no langue column) | `QXPS_File_Manager.Get_Document(…)` |
| #84 | `GetDocumentByIdDaoImpl` | read `format` from the cursor verbatim, fallback `QXP` | `QXPS_File_Manager.Get_Document(id)` |
| #53/#82 | `AuditDaoImpl` | `p_duration` = sub-second millisecond **component** (0–999), not total elapsed | `Audit.Duration = ((TimeSpan)).Milliseconds` (quirk, replicated) |
| #83/#87 | `RunStatus` (+`AuditDaoImpl` bind) | `auditStatusLabel` drives `p_end_status` (PascalCase status word) | `Proxy_Audit.InsertAuditRun` → `EndStatus.ToString()` |
| test | `DocumentDomainTest` | expect `G_100.QXP` (verbatim ext, #57) | — |

> **Deferred from this batch:** **#86** (store cleanup: delete-on-empty) and **#88** (audit message exact
> format) — details at the end. Not implemented; both need live-DB / golden-file validation.

---

## Files (full content — whole-file copy-paste)

### 1. `domain/RunStatus.java`
```java
package com.socgen.sgs.api.quark.engine.domain;

import lombok.Getter;

/**
 * Enumeration representing the status of a Run
 * Maps to QXP_RUN.ID_STATUT_GENERATION in the database
 */
@Getter
public enum RunStatus {

    TO_GENERATE(1, "ToGenerate"),
    GENERATED(2, "Generated"),
    ERROR(3, "Error"),
    RUNNING(4, "Running");

    private final int statusCode;

    /**
     * Stable status label persisted verbatim to QXP_AUDIT_RUN.END_STATUS.
     * Kept separate from the Java constant name on purpose, so the audit text stays
     * consistent with existing audit history and with status-based reporting
     * (GROUP BY / WHERE on END_STATUS). Do not derive from name() — the spelling is a contract.
     */
    private final String auditStatusLabel;

    RunStatus(int statusCode, String auditStatusLabel) {
        this.statusCode = statusCode;
        this.auditStatusLabel = auditStatusLabel;
    }

    /**
     * Get RunStatus from status code
     */
    public static RunStatus fromCode(int code) {
        for (RunStatus status : values()) {
            if (status.statusCode == code) {
                return status;
            }
        }
        throw new IllegalArgumentException("Invalid status code: " + code);
    }

    public int getCode() {
        return statusCode;
    }

}
```

### 2. `infra/dao/impl/AuditDaoImpl.java`
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
        // p_duration stores only the SUB-SECOND millisecond COMPONENT (0-999), NOT total elapsed time —
        // this matches the existing QXP_AUDIT_RUN.DURATION contract.
        // ⚠️ Quirk: the stored DURATION is only the 0-999 ms part, not the total duration.
        int durationMs = 0;
        if (run.getStartDate() != null && run.getEndDate() != null) {
            durationMs = Duration.between(run.getStartDate(), run.getEndDate()).toMillisPart();
        }

        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_run", run.getId())
                .addValue("p_id_suivi", run.getRunProperties() != null ? run.getRunProperties().getIdSuivi() : null)
                .addValue("p_run_type", run.getRunProperties() != null ? run.getRunProperties().getRunType() : null)
                .addValue("p_start_date", run.getStartDate() != null ? Timestamp.valueOf(run.getStartDate()) : null)
                .addValue("p_end_date", run.getEndDate() != null ? Timestamp.valueOf(run.getEndDate()) : null)
                .addValue("p_duration", durationMs)
                // Bind the stable PascalCase status label (Generated/Error/...) that END_STATUS expects,
                // not the Java enum name() (TO_GENERATE/...). The spelling is a persistence contract.
                .addValue("p_end_status", run.getStatus() != null ? run.getStatus().getAuditStatusLabel() : null)
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

### 3. `infra/dao/impl/InsertDocumentDaoImpl.java`
```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.infra.dao.InsertDocumentDao;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.SqlOutParameter;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.Types;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.Map;

/**
 * Oracle implementation: QXP_PK_RUN.Insert_Document
 */
@Repository
@RequiredArgsConstructor
@Slf4j
public class InsertDocumentDaoImpl implements InsertDocumentDao {

    private final DataSource dataSource;

    @Override
    public int insertDocument(DocumentDomain document, int idSousCategorie,
                              String idFndCode, String idUnitCode,
                              LocalDate dateEcheance, int idRun) {
        if (document == null || document.getData() == null) {
            return Integer.MIN_VALUE;
        }

        SimpleJdbcCall jdbcCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_RUN")
                .withFunctionName("Insert_Document")
                // Bind solely from the explicit declareParameters list (no JDBC metadata lookup),
                // matching AuditDao and the rest of the DAO layer — deterministic RETURN/param
                // resolution across drivers. Declared order matches the proc in ora.txt. Findings #47/#90.
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlOutParameter("RETURN", Types.NUMERIC),
                        new SqlParameter("p_code_port", Types.VARCHAR),
                        new SqlParameter("p_id_unit_code", Types.VARCHAR),
                        new SqlParameter("p_id_sous_categorie", Types.NUMERIC),
                        new SqlParameter("p_format", Types.VARCHAR),
                        new SqlParameter("p_id_langue", Types.NUMERIC),
                        new SqlParameter("p_date_document", Types.DATE),
                        new SqlParameter("p_nom_document", Types.VARCHAR),
                        new SqlParameter("p_id_utilisateur", Types.NUMERIC),
                        new SqlParameter("p_contenu", Types.BLOB),
                        new SqlParameter("p_taille_document", Types.NUMERIC),
                        new SqlParameter("p_is_actif", Types.NUMERIC),
                        new SqlParameter("p_id_run", Types.NUMERIC)
                );

        Map<String, Object> params = new HashMap<>();
        params.put("p_code_port", idFndCode);
        params.put("p_id_unit_code", idUnitCode);
        params.put("p_id_sous_categorie", idSousCategorie);
        params.put("p_format", document.getFormat());
        params.put("p_id_langue", document.getIdLangue() != null ? document.getIdLangue() : 1);
        // Null-safe (p_date_document is Types.DATE); mirrors GetDocumentDaoImpl's guard. Finding #89.
        params.put("p_date_document", dateEcheance != null ? java.sql.Date.valueOf(dateEcheance) : null);
        params.put("p_nom_document", document.getFileName());
        params.put("p_id_utilisateur", 0);
        params.put("p_contenu", document.getData());
        params.put("p_taille_document", document.getData().length);
        params.put("p_is_actif", 1);
        params.put("p_id_run", idRun);

        Map<String, Object> result = jdbcCall.execute(params);
        Number idDoc = (Number) result.get("RETURN");

        log.debug("Inserted document [{}] with id [{}] for run [{}]",
                document.getFileName(), idDoc, idRun);

        return idDoc != null ? idDoc.intValue() : Integer.MIN_VALUE;
    }
}
```

### 4. `infra/dao/impl/EndRunDaoImpl.java`
```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.infra.dao.EndRunDao;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import oracle.jdbc.OraclePreparedStatement;
import oracle.jdbc.OracleTypes;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.CallableStatement;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

/**
 * Oracle implementation for run finalization.
 */
@Repository
@RequiredArgsConstructor
@Slf4j
public class EndRunDaoImpl implements EndRunDao {

    private final DataSource dataSource;

    @Override
    public void endRun(int idRun, int runStatus, int idSuivi, int suiviStatus,
                       LocalDateTime dateFin, String logTrace,
                       int idDocPdf, int idDocQxp, int idDocDoc) {
        SimpleJdbcCall jdbcCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_RUN")
                .withProcedureName("End_Run")
                .withoutProcedureColumnMetaDataAccess() // deterministic binding from declareParameters. #91
                .declareParameters(
                        new SqlParameter("p_id_run", Types.NUMERIC),
                        new SqlParameter("p_run_status", Types.NUMERIC),
                        new SqlParameter("p_id_suivi", Types.NUMERIC),
                        new SqlParameter("p_suivi_status", Types.NUMERIC),
                        new SqlParameter("p_date_fin", Types.TIMESTAMP),
                        new SqlParameter("p_log_trace", Types.CLOB),
                        new SqlParameter("p_id_doc_pdf", Types.NUMERIC),
                        new SqlParameter("p_id_doc_qxp", Types.NUMERIC),
                        new SqlParameter("p_id_doc_doc", Types.NUMERIC)
                );

        Map<String, Object> params = new HashMap<>();
        params.put("p_id_run", idRun);
        params.put("p_run_status", runStatus);
        params.put("p_id_suivi", idSuivi);
        params.put("p_suivi_status", suiviStatus);
        params.put("p_date_fin", Timestamp.valueOf(dateFin));
        params.put("p_log_trace", logTrace);
        params.put("p_id_doc_pdf", idDocPdf);
        params.put("p_id_doc_qxp", idDocQxp);
        params.put("p_id_doc_doc", idDocDoc);

        jdbcCall.execute(params);
        log.info("End_Run executed for run [{}]", idRun);
    }

    @Override
    public void updateStatusRun(int idRun, int runStatus, int suiviStatus,
                                LocalDateTime dateFin, String logTrace) {
        SimpleJdbcCall jdbcCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_RUN")
                .withProcedureName("Update_Status_Run")
                .withoutProcedureColumnMetaDataAccess() // deterministic binding from declareParameters. #91
                .declareParameters(
                        new SqlParameter("p_id_run", Types.NUMERIC),
                        new SqlParameter("p_run_status", Types.NUMERIC),
                        new SqlParameter("p_suivi_status", Types.NUMERIC),
                        new SqlParameter("p_date_fin", Types.TIMESTAMP),
                        new SqlParameter("p_log_trace", Types.CLOB)
                );

        Map<String, Object> params = new HashMap<>();
        params.put("p_id_run", idRun);
        params.put("p_run_status", runStatus);
        params.put("p_suivi_status", suiviStatus);
        params.put("p_date_fin", Timestamp.valueOf(dateFin));
        params.put("p_log_trace", logTrace);

        jdbcCall.execute(params);
        log.info("Update_Status_Run executed for run [{}] with status [{}]", idRun, runStatus);
    }

    @Override
    public void insertRunErrors(int idRun, String[] messages, int[] categories) {
        if (messages == null || messages.length == 0) return;

        // p_messages / p_categories are PL/SQL associative arrays (QXP_PK_COMMON.VarCharArray /
        // NumberArray = "TABLE OF ... INDEX BY BINARY_INTEGER"). These CANNOT be bound as a SQL
        // collection via SimpleJdbcCall + OracleTypes.ARRAY (the previous code raised ORA-00902 /
        // PLS-00306 at runtime, so EVERY error-persistence call threw, masking the original failure).
        // They must be bound with the Oracle index-table API setPlsqlIndexTable, mirroring how .NET
        // ODP.NET binds the same VarCharArray/NumberArray params (Proxy_Error.cs:127-129). Finding #4.
        new JdbcTemplate(dataSource).execute((ConnectionCallback<Void>) con -> {
            try (CallableStatement cs = con.prepareCall("{ call QXP_PK_RUN.Insert_Run_Errors(?, ?, ?) }")) {
                OraclePreparedStatement ops = cs.unwrap(OraclePreparedStatement.class);
                ops.setInt(1, idRun);
                // setPlsqlIndexTable(paramIndex, data, maxLen, curLen, elemSqlType, elemMaxLen)
                ops.setPlsqlIndexTable(2, messages, messages.length, messages.length,
                        OracleTypes.VARCHAR, 4000);
                ops.setPlsqlIndexTable(3, categories, categories.length, categories.length,
                        OracleTypes.NUMBER, 0);
                ops.execute();
            }
            return null;
        });
        log.info("Inserted {} errors for run [{}]", messages.length, idRun);
    }
}
```

### 5. `domain/DocumentDomain.java`
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
                && getQxpXml().getProjectInfo().getNbBox() > 100) {
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

### 6. `business/QxpsCallerBusiness.java`
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
```

### 7. `infra/dao/impl/GetDocumentDaoImpl.java`
```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.infra.dao.GetDocumentDao;
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
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * Calls Oracle function QXP_PK_RUN.Get_Document (6-arg → cursor) to load a reference document.
 * Cross-reference: .NET QXPS_File_Manager.Get_Document(idSousCategorie, idFndCode, idUnitCode,
 * societe, idLangue, dateEcheance) used by Task_Document.Prepare.
 *
 * <p>ora.txt signature: p_id_sous_categorie NUMBER, p_id_fnd_code VARCHAR2, p_id_unit_code VARCHAR2,
 * p_societe VARCHAR2, p_id_langue NUMBER, p_date_echeance DATE → cursor(id_document, nom, contenu, format).
 */
@Repository
@Slf4j
public class GetDocumentDaoImpl implements GetDocumentDao {

    private static final String RESULT_KEY = "result_cursor";
    private final SimpleJdbcCall getDocumentCall;

    @Autowired
    public GetDocumentDaoImpl(DataSource dataSource) {
        this.getDocumentCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_RUN")
                .withFunctionName("Get_Document")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlOutParameter(RESULT_KEY, OracleTypes.CURSOR,
                                (rs, rowNum) -> mapFromResultSet(rs)),
                        new SqlParameter("p_id_sous_categorie", Types.NUMERIC),
                        new SqlParameter("p_id_fnd_code", Types.VARCHAR),
                        new SqlParameter("p_id_unit_code", Types.VARCHAR),
                        new SqlParameter("p_societe", Types.VARCHAR),
                        new SqlParameter("p_id_langue", Types.NUMERIC),
                        new SqlParameter("p_date_echeance", Types.DATE)
                );
    }

    @Override
    public DocumentDomain getDocument(int idSousCategorie, String idFndCode, String idUnitCode,
                                      String societe, int idLangue, LocalDate dateEcheance) {
        log.info("Fetching reference document: sousCategorie={}, fndCode={}, unitCode={}, societe={}, langue={}, echeance={}",
                idSousCategorie, idFndCode, idUnitCode, societe, idLangue, dateEcheance);

        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_sous_categorie", idSousCategorie)
                .addValue("p_id_fnd_code", idFndCode)
                .addValue("p_id_unit_code", idUnitCode)
                .addValue("p_societe", societe)
                .addValue("p_id_langue", idLangue)
                .addValue("p_date_echeance", dateEcheance != null ? java.sql.Date.valueOf(dateEcheance) : null);

        try {
            Map<String, Object> result = getDocumentCall.execute(params);

            @SuppressWarnings("unchecked")
            List<DocumentDomain> rows = (List<DocumentDomain>) result.get(RESULT_KEY);

            if (rows == null || rows.isEmpty()) {
                log.warn("No reference document found for sousCategorie={}", idSousCategorie);
                return null;
            }
            DocumentDomain doc = rows.get(0);
            // The Get_Document cursor has no langue column, so set ID_Langue from the input langue
            // used to query. Finding #73.
            doc.setIdLangue(idLangue);
            return doc;
        } catch (Exception e) {
            log.error("Error fetching reference document for sousCategorie={}", idSousCategorie, e);
            throw new RuntimeException("Failed to fetch reference document for sousCategorie: " + idSousCategorie, e);
        }
    }

    private DocumentDomain mapFromResultSet(ResultSet rs) throws SQLException {
        DocumentDomain doc = new DocumentDomain();
        doc.setId(rs.getInt("id_document"));
        doc.setName(rs.getString("nom"));
        doc.setFormat(rs.getString("format"));
        doc.setPrefix(DocumentDomain.FILE_DOCUMENT_PREFIX);
        doc.setData(rs.getBytes("contenu"));
        // fileName = D_<id>.<format> (paths are completed by the loader using the run pool + base path).
        doc.setFileName(String.format("%s_%d.%s", doc.getPrefix(), doc.getId(), doc.getFormat()));
        return doc;
    }
}
```

### 8. `infra/dao/impl/GetDocumentByIdDaoImpl.java`
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
        // Read the cursor's format column VERBATIM (Get_Document_ByID returns it), falling back to "QXP"
        // only when null/blank; the file name is built from the unmodified format value. Finding #84.
        String fmt = rs.getString("format");
        doc.setFormat(fmt != null && !fmt.isBlank() ? fmt : "QXP");
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

### 9. (test) `domain/DocumentDomainTest.java`
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
}

```

---

## Deferred considerations (flagged, NOT implemented in this batch)

### #86 — Store-data cleanup (delete-on-empty)
- **Behaviour in source:** when a run's store-data set is **empty**, the legacy engine **DELETEs** the
  existing store rows for the suivi (clears stale history) rather than leaving them.
- **Java today:** `EndRunBusiness.insertDataStorage` only **inserts** when the data set is non-empty; the
  empty-set DELETE path is not implemented.
- **Why deferred:** binding an **empty** associative array to the delete proc via `setPlsqlIndexTable` is
  driver-sensitive and must be validated against a **live Oracle DB** before shipping.
- **Lands in:** `EndRunBusiness.insertDataStorage` + a new `InsertDataStorageDao` delete path.

### #88 — Audit message exact format
- **Behaviour in source:** `p_message` for the audit row follows a specific composed layout
  (status + error summary in a fixed shape).
- **Java today:** `EndRunBusiness.buildAuditMessage` produces a short status + error-summary string that may
  not match the legacy layout byte-for-byte.
- **Why deferred:** needs a **golden-file** capture of real audit messages to lock the exact format.
- **Lands in:** `EndRunBusiness.buildAuditMessage`.

> Both are tracked in the consolidated **Deferred Considerations Register**.

---

## Apply checklist

- [ ] `domain/RunStatus.java` — `netLabel`→`auditStatusLabel`
- [ ] `infra/dao/impl/AuditDaoImpl.java` — `getAuditStatusLabel()` bind + duration/status comments
- [ ] `infra/dao/impl/InsertDocumentDaoImpl.java`
- [ ] `infra/dao/impl/EndRunDaoImpl.java`
- [ ] `domain/DocumentDomain.java`
- [ ] `business/QxpsCallerBusiness.java`
- [ ] `infra/dao/impl/GetDocumentDaoImpl.java`
- [ ] `infra/dao/impl/GetDocumentByIdDaoImpl.java`
- [ ] (test) `domain/DocumentDomainTest.java`
- [ ] `mvn test` — RunStatus / Audit / DocumentDomain green
