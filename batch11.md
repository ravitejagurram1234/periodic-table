# EOS Quark — Batch 11 Changes (F14 document-loading subsystem + F2 QXP_Previous)

Implements the two largest validation findings:

- **F14** — task document-content loading was unimplemented (`setDocument` had zero call sites), silently disabling ALL Document tasks (PDF/image/RTF/DOC/XTG/QXP-data) and QXP_Previous. This batch adds the loader that fetches each task's reference/previous document, uploads it to the QuarkXPress pool via the Quark API (PDFs split per page), and loads its XML/project for QXP-source tasks. Cross-reference: .NET `Task_Document.Prepare` + `Task_QXP_Previous.Prepare`.
- **F2** — the DOC_QXP task type (`TaskQxpPrevious`) had no strategy and was silently skipped. This batch adds `QxpPreviousTaskProcessStrategy`, a faithful port of .NET `Process_QXP_Previous` (explicit `|`-split mode with ¤/U+00A4 position hint, and `.N{level}` hierarchy mode; value-copy and style-copy via `TElementHelper`).

## Where it plugs in

A new **Step 3b** runs in the Prepare phase of `ProcessRunServiceImpl.runProcessor` (right after `prepareTasks`, before `processTasks`): `loadTaskDocumentsBusiness.loadDocuments(run)`. Document loading is kept in the `business` layer (not the domain `prepare()`) so the domain stays I/O-free; all pool writes use `FilePoolPort.addFile` (Kube remote-host constraint).

## Prerequisites

1. **Apache PDFBox dependency** — add to `pom.xml` (before `</dependencies>`):

```xml
    <!-- PDF page-splitting for Document (PDF) tasks — replaces .NET QXPIO.PDF_Tools.Split_PDF. -->
    <dependency>
      <groupId>org.apache.pdfbox</groupId>
      <artifactId>pdfbox</artifactId>
      <version>2.0.31</version>
    </dependency>
```

2. Batch 10 should be applied first (this batch builds on the Batch-8 business bridges and the F3 `RunError` constants).

## Notes / flagged deviations

- **PDF page file names** are internal/transient pool names chosen here (`<prefix>_<id>_p<n>.pdf`); the .NET splitter source (`QXPIO.PDF_Tools`) ships only as a compiled assembly so its exact page names can't be matched. The same name is used for both the pool upload and the content path, so QXPS resolves them correctly — **page count + order are what matter and are preserved**. Not a functional deviation.
- **Oracle `Get_Last_Qxp_Certifie` takes 2 params** (`p_id_suivi`, `p_id_type_rapport`); langue is derived inside the SQL (the .NET wrapper's 3rd langue arg is not an Oracle parameter).
- The count-mismatch handling in QXP_Previous iterates the safe overlap after recording `Invalid_List_Count` (consistent with the approved Document-task behavior), rather than throwing `IndexOutOfRange` like .NET.

## Summary

| # | File | Change |
|---|------|--------|
| 1 | `com/socgen/sgs/api/quark/engine/infra/dao/GetDocumentDao.java` | NEW — port for QXP_PK_RUN.Get_Document (6-arg) |
| 2 | `com/socgen/sgs/api/quark/engine/infra/dao/impl/GetDocumentDaoImpl.java` | NEW — Get_Document SimpleJdbcCall (reference doc load) |
| 3 | `com/socgen/sgs/api/quark/engine/infra/dao/GetLastQxpCertifieDao.java` | NEW — port for QXP_PK_RUN.Get_Last_Qxp_Certifie (2-arg) |
| 4 | `com/socgen/sgs/api/quark/engine/infra/dao/impl/GetLastQxpCertifieDaoImpl.java` | NEW — Get_Last_Qxp_Certifie SimpleJdbcCall (QXP_Previous source) |
| 5 | `com/socgen/sgs/api/quark/engine/infra/pdf/PdfSplitter.java` | NEW — PDF page-split via Apache PDFBox (replaces .NET PDF_Tools.Split_PDF) |
| 6 | `com/socgen/sgs/api/quark/engine/business/LoadTaskDocumentsBusiness.java` | NEW — F14 loader: load+pool-upload task documents (Prepare phase) |
| 7 | `com/socgen/sgs/api/quark/engine/service/task/impl/QxpPreviousTaskProcessStrategy.java` | NEW — F2 strategy (ports .NET Process_QXP_Previous) |
| 8 | `com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java` | CHANGED — inject loader + call loadDocuments() after prepareTasks |
| 9 | `pom.xml` | add Apache PDFBox 2.0.31 dependency (snippet above) |

After applying: `mvn -q -DskipTests compile`

---

## 1. `com/socgen/sgs/api/quark/engine/infra/dao/GetDocumentDao.java`

_NEW — port for QXP_PK_RUN.Get_Document (6-arg)_

```java
package com.socgen.sgs.api.quark.engine.infra.dao;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;

import java.time.LocalDate;

/**
 * DAO for loading a reference document (image/PDF/RTF/DOC/XTG/QXP) to be inserted into a template.
 * Cross-reference: .NET QXPS_File_Manager.Get_Document → Oracle QXP_PK_RUN.Get_Document (6-arg).
 */
public interface GetDocumentDao {

    /**
     * Load a reference document by sous-categorie + fund/part/company context for the run's
     * language and echeance date.
     *
     * @return the document (id/name/format/data, prefix "D"), or null if none found
     */
    DocumentDomain getDocument(int idSousCategorie, String idFndCode, String idUnitCode,
                               String societe, int idLangue, LocalDate dateEcheance);
}
```

---

## 2. `com/socgen/sgs/api/quark/engine/infra/dao/impl/GetDocumentDaoImpl.java`

_NEW — Get_Document SimpleJdbcCall (reference doc load)_

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
            return rows.get(0);
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

---

## 3. `com/socgen/sgs/api/quark/engine/infra/dao/GetLastQxpCertifieDao.java`

_NEW — port for QXP_PK_RUN.Get_Last_Qxp_Certifie (2-arg)_

```java
package com.socgen.sgs.api.quark.engine.infra.dao;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;

/**
 * DAO for loading the last certified QXP for a suivi + report type, used by QXP_Previous tasks.
 * Cross-reference: .NET QXPS_File_Manager.Get_Last_Qxp_Certifie → Oracle QXP_PK_RUN.Get_Last_Qxp_Certifie.
 *
 * <p>ora.txt signature: p_id_suivi NUMBER, p_id_type_rapport NUMBER (langue is derived inside the
 * SQL from the current suivi — there is NO langue parameter).
 */
public interface GetLastQxpCertifieDao {

    /**
     * Load the most recent certified QXP for the given suivi and report type
     * (idTypeRapport = 0 matches any report type).
     *
     * @return the document (id/name/format=QXP/data, prefix "D"), or null if none found
     */
    DocumentDomain getLastQxpCertifie(int idSuivi, int idTypeRapport);
}
```

---

## 4. `com/socgen/sgs/api/quark/engine/infra/dao/impl/GetLastQxpCertifieDaoImpl.java`

_NEW — Get_Last_Qxp_Certifie SimpleJdbcCall (QXP_Previous source)_

```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.infra.dao.GetLastQxpCertifieDao;
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
 * Calls Oracle function QXP_PK_RUN.Get_Last_Qxp_Certifie (2-arg → cursor) to load the last certified
 * QXP for a suivi + report type. Cross-reference: .NET QXPS_File_Manager.Get_Last_Qxp_Certifie used by
 * Task_QXP_Previous.Prepare.
 *
 * <p>ora.txt cursor columns: ID_DOCUMENT, CONTENU, NOM, FORMAT ('QXP').
 */
@Repository
@Slf4j
public class GetLastQxpCertifieDaoImpl implements GetLastQxpCertifieDao {

    private static final String RESULT_KEY = "result_cursor";
    private final SimpleJdbcCall getLastQxpCertifieCall;

    @Autowired
    public GetLastQxpCertifieDaoImpl(DataSource dataSource) {
        this.getLastQxpCertifieCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_RUN")
                .withFunctionName("Get_Last_Qxp_Certifie")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlOutParameter(RESULT_KEY, OracleTypes.CURSOR,
                                (rs, rowNum) -> mapFromResultSet(rs)),
                        new SqlParameter("p_id_suivi", Types.NUMERIC),
                        new SqlParameter("p_id_type_rapport", Types.NUMERIC)
                );
    }

    @Override
    public DocumentDomain getLastQxpCertifie(int idSuivi, int idTypeRapport) {
        log.info("Fetching last certified QXP for idSuivi={}, idTypeRapport={}", idSuivi, idTypeRapport);

        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_suivi", idSuivi)
                .addValue("p_id_type_rapport", idTypeRapport);

        try {
            Map<String, Object> result = getLastQxpCertifieCall.execute(params);

            @SuppressWarnings("unchecked")
            List<DocumentDomain> rows = (List<DocumentDomain>) result.get(RESULT_KEY);

            if (rows == null || rows.isEmpty()) {
                log.warn("No certified previous QXP found for idSuivi={}, idTypeRapport={}", idSuivi, idTypeRapport);
                return null;
            }
            return rows.get(0);
        } catch (Exception e) {
            log.error("Error fetching last certified QXP for idSuivi={}", idSuivi, e);
            throw new RuntimeException("Failed to fetch last certified QXP for idSuivi: " + idSuivi, e);
        }
    }

    private DocumentDomain mapFromResultSet(ResultSet rs) throws SQLException {
        DocumentDomain doc = new DocumentDomain();
        doc.setId(rs.getInt("id_document"));
        doc.setName(rs.getString("nom"));
        doc.setFormat(rs.getString("format"));
        doc.setPrefix(DocumentDomain.FILE_DOCUMENT_PREFIX);
        doc.setData(rs.getBytes("contenu"));
        // fileName = D_<id>.<format> (paths completed by the loader using the run pool + base path).
        doc.setFileName(String.format("%s_%d.%s", doc.getPrefix(), doc.getId(), doc.getFormat()));
        return doc;
    }
}
```

---

## 5. `com/socgen/sgs/api/quark/engine/infra/pdf/PdfSplitter.java`

_NEW — PDF page-split via Apache PDFBox (replaces .NET PDF_Tools.Split_PDF)_

```java
package com.socgen.sgs.api.quark.engine.infra.pdf;

import lombok.extern.slf4j.Slf4j;
import org.apache.pdfbox.multipdf.Splitter;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.springframework.stereotype.Component;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.List;

/**
 * Splits a multi-page PDF into one byte[] per page, using Apache PDFBox.
 *
 * <p>Replaces the .NET QXPIO.PDF_Tools.Split_PDF (whose source ships only as a compiled assembly).
 * Functional parity that matters: the number of output pages and their order. The per-page pool
 * file <em>names</em> are internal/transient (chosen by the loader), so they need not match .NET's.
 */
@Component
@Slf4j
public class PdfSplitter {

    /**
     * Split a PDF into per-page byte arrays (page order preserved).
     *
     * @param pdfData the source PDF bytes
     * @return one byte[] per page (empty list if input is null/empty)
     */
    public List<byte[]> split(byte[] pdfData) {
        List<byte[]> pages = new ArrayList<>();
        if (pdfData == null || pdfData.length == 0) {
            return pages;
        }
        try (PDDocument document = PDDocument.load(new ByteArrayInputStream(pdfData))) {
            Splitter splitter = new Splitter();
            List<PDDocument> split = splitter.split(document);
            for (PDDocument page : split) {
                try (page; ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
                    page.save(baos);
                    pages.add(baos.toByteArray());
                }
            }
            log.info("Split PDF into {} page(s)", pages.size());
            return pages;
        } catch (Exception e) {
            log.error("Failed to split PDF ({} bytes): {}", pdfData.length, e.getMessage(), e);
            throw new RuntimeException("Failed to split PDF", e);
        }
    }
}
```

---

## 6. `com/socgen/sgs/api/quark/engine/business/LoadTaskDocumentsBusiness.java`

_NEW — F14 loader: load+pool-upload task documents (Prepare phase)_

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
    private final GetGabaritXmlBusiness getGabaritXmlBusiness;
    private final GetDocumentProjectBusiness getDocumentProjectBusiness;
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
        DocumentDomain doc = getDocumentDao.getDocument(
                task.getIdSousCategorie(), props.getIdFndCode(), props.getIdUnitCode(),
                props.getSociete(), props.getIdLangue(), props.getDateEcheance());

        if (doc == null) {
            // .NET Errors.Add(Document_Null, ...) → Unspecified severity.
            run.getErrors().add(new RunError(RunError.UNSPECIFIED,
                    "Document_Null: aucun document pour la sous-categorie " + task.getIdSousCategorie()
                            + " (tache " + task.getId() + ")"));
            log.warn("No document found for task {} (sousCategorie {})", task.getId(), task.getIdSousCategorie());
            return;
        }

        completePaths(doc, props, basePath);
        markModeDegradeIfTooBig(doc, run);
        task.setDocument(doc);

        SubTaskTypeEnum subType = task.getSubTaskType();
        if (subType == SubTaskTypeEnum.FILE_PDF) {
            loadPdfPages(doc, props, basePath);
        } else if (subType == SubTaskTypeEnum.FILE_QXP_DATA) {
            // Upload the source QXP then load its XML (always) / project (only when keeping style).
            filePool.addFile(doc.getFilePoolPath(), doc.getData());
            loadQxpSource(doc, task.isConserverStyle());
        } else {
            // IMG / DOC / RTF / XTG — upload the file as-is.
            filePool.addFile(doc.getFilePoolPath(), doc.getData());
        }
    }

    /** PDF: split into pages, upload each page to the pool, expose the per-page absolute paths. */
    private void loadPdfPages(DocumentDomain doc, RunProperties props, String basePath) {
        List<byte[]> pages = pdfSplitter.split(doc.getData());
        List<String> pdfFiles = new ArrayList<>();
        for (int i = 0; i < pages.size(); i++) {
            String pageName = String.format(PDF_PAGE_NAME_PATTERN, doc.getPrefix(), doc.getId(), i + 1);
            filePool.addFile(props.getPoolPath(pageName), pages.get(i));
            // The strategy uses these entries directly as the picture content value (absolute host path).
            pdfFiles.add(props.getPoolPathAbsolute(pageName, basePath));
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

        DocumentDomain doc = getLastQxpCertifieDao.getLastQxpCertifie(props.getIdSuivi(), previousTypeRapport);
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

        completePaths(doc, props, basePath);
        markModeDegradeIfTooBig(doc, run);
        // Upload so getXPressDOM / fetchXml can read the source structure back.
        filePool.addFile(doc.getFilePoolPath(), doc.getData());
        loadQxpSource(doc, task.isConserverStyle());
        task.setDocument(doc);
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
    private void completePaths(DocumentDomain doc, RunProperties props, String basePath) {
        String fileName = doc.getFileName();
        doc.setFilePoolPath(props.getPoolPath(fileName));
        doc.setFileFullPath(props.getPoolPathAbsolute(fileName, basePath));
    }

    /** A reference doc exceeding the run size limit flags the (task) document as degraded. */
    private void markModeDegradeIfTooBig(DocumentDomain doc, Run run) {
        if (doc.getData() != null && doc.getData().length > run.getSizeLimitBeforeFailSoft()) {
            doc.setModeDegrade(true);
            log.warn("Document {} ({} bytes) exceeds size limit {} → mode degrade",
                    doc.getId(), doc.getData().length, run.getSizeLimitBeforeFailSoft());
        }
    }

    /** Load the XML (always) and, when keeping style, the project DOM of a pooled QXP source. */
    private void loadQxpSource(DocumentDomain doc, boolean conserverStyle) {
        doc.initXmlFromContent(getGabaritXmlBusiness.fetchXml(doc.getFilePoolPath()));
        if (conserverStyle) {
            doc.setQxpProject(getDocumentProjectBusiness.getProject(doc.getFilePoolPath()));
        }
    }
}
```

---

## 7. `com/socgen/sgs/api/quark/engine/service/task/impl/QxpPreviousTaskProcessStrategy.java`

_NEW — F2 strategy (ports .NET Process_QXP_Previous)_

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

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
public class QxpPreviousTaskProcessStrategy implements TaskProcessStrategy<TaskQxpPrevious> {

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
                doc.getQxpProject().analyse(task, false);
            }

            addBlocsExplicit(task, doc, listSource, listDest);
        } else {
            // Hierarchy mode — collect source blocs by level (.N0, .N1, …) until a level is empty.
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

---

## 8. `com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java`

_CHANGED — inject loader + call loadDocuments() after prepareTasks_

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

