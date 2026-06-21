# EOS Quark Engine — Batch 4 Changes
**Theme: PL/SQL associative-array binding (the deterministic runtime-throw cluster)**

_Generated directly from the working-copy files. Whole-file copy-paste._

## Findings fixed in this batch
| # | Sev | Issue | .NET reference |
|---|---|---|---|
| 4 | CRITICAL | `Insert_Run_Errors` `p_messages`/`p_categories` bound as `OracleTypes.ARRAY` against PL/SQL `INDEX BY` associative arrays → ORA-00902/PLS-00306 at runtime, so the **entire error-persistence path threw**, masking the original failure | Proxy_Error.cs:127-129; ora.txt:9447-9451; QXP_PK_COMMON.sql:11-12 |
| 20 | CRITICAL* | `Insert_Data` `p_names`/`p_values`/`p_descriptifs`/`p_infos` — same associative-array binding failure → **all store_data persistence threw** | ora.txt:3080-3090; QXP_PK_COMMON.sql:11 |

_*#20 was filed HIGH; it is the same root-cause runtime throw as #4 (C6/C7 pair) and breaks all data-storage persistence, so it is fixed alongside it._

## Root cause
`QXP_PK_COMMON.VarCharArray` / `NumberArray` are declared `TABLE OF ... INDEX BY BINARY_INTEGER` — **PL/SQL package associative arrays**, not schema-level SQL collection types. `SimpleJdbcCall` + `OracleTypes.ARRAY` (with `createOracleArray`) can only bind a real `CREATE TYPE ... AS TABLE` SQL collection, so binding an associative array this way fails at execution. .NET binds these via ODP.NET's associative-array support (`Proxy_Error.cs:127-129`).

## The fix
For the two affected procedures, drop `SimpleJdbcCall` and bind through the Oracle index-table API `OraclePreparedStatement.setPlsqlIndexTable(...)`, which is the JDBC equivalent of ODP.NET's `PLSQLAssociativeArray`:
```java
new JdbcTemplate(dataSource).execute((ConnectionCallback<Void>) con -> {
    try (CallableStatement cs = con.prepareCall("{ call QXP_PK_RUN.Insert_Run_Errors(?, ?, ?) }")) {
        OraclePreparedStatement ops = cs.unwrap(OraclePreparedStatement.class);
        ops.setInt(1, idRun);
        // setPlsqlIndexTable(paramIndex, data, maxLen, curLen, elemSqlType, elemMaxLen)
        ops.setPlsqlIndexTable(2, messages, messages.length, messages.length, OracleTypes.VARCHAR, 4000);
        ops.setPlsqlIndexTable(3, categories, categories.length, categories.length, OracleTypes.NUMBER, 0);
        ops.execute();
    }
    return null;
});
```
- Positional binds verified against `ora.txt`: `Insert_Run_Errors(p_id_run, p_messages, p_categories)` (3 params); `Insert_Data(p_id_suivi, p_id_run, p_date_generation, p_store_type, p_names, p_values, p_descriptifs, p_infos, p_historisation_differentielle)` (9 params).
- `unwrap(OraclePreparedStatement.class)` handles the connection-pool statement wrapper (e.g. HikariCP).
- VARCHAR element max length = 4000 (matches `VARCHAR2(4000)`); NUMBER uses elemMaxLen 0.
- The existing length-0/null early-return guards are preserved.

## Parity extra: empty-message sentinel (#4)
`EndRunBusiness.insertErrors` now replaces a blank/null message with the **"aucun"** sentinel before binding, matching .NET `Proxy_Error.cs:115-118` (`MessageVide = "aucun"`). Previously a null message would have been persisted as SQL NULL.

## ⚠️ Needs live-DB validation
`setPlsqlIndexTable` cannot be exercised without a real Oracle connection (no DB in this environment). The signature, positional order, and element types are verified against `ora.txt` + `QXP_PK_COMMON.sql`, but please confirm against the live DB during the debug pass — this is the one change in the batch that touches driver-specific binding. (The `int[]` → NUMBER index-table bind in particular should be smoke-tested.)

---

## `infra/dao/impl/EndRunDaoImpl.java` — CHANGED
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

---

## `infra/dao/impl/InsertDataStorageDaoImpl.java` — CHANGED
```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.infra.dao.InsertDataStorageDao;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import oracle.jdbc.OraclePreparedStatement;
import oracle.jdbc.OracleTypes;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.CallableStatement;
import java.sql.Timestamp;
import java.time.LocalDateTime;

/**
 * Oracle implementation: QXP_PK_DATA_STORAGE.Insert_Data
 */
@Repository
@RequiredArgsConstructor
@Slf4j
public class InsertDataStorageDaoImpl implements InsertDataStorageDao {

    private final DataSource dataSource;

    @Override
    public void insertData(int idSuivi, int idRun, LocalDateTime dateGeneration,
                           int storeType, String[] names, String[] values,
                           String[] descriptifs, String[] infos,
                           boolean historisationDifferentielle) {
        if (names == null || names.length == 0) return;

        // p_names/p_values/p_descriptifs/p_infos are PL/SQL associative arrays
        // (QXP_PK_COMMON.VarCharArray = "TABLE OF VARCHAR2(4000) INDEX BY BINARY_INTEGER"). These
        // cannot be bound via SimpleJdbcCall + OracleTypes.ARRAY (raised ORA-00902/PLS-00306 at
        // runtime, so storeData persistence always threw). Bind them with the Oracle index-table API
        // setPlsqlIndexTable, mirroring .NET ODP.NET (Proxy_Store/Insert_Data). Finding #20 (C6).
        new JdbcTemplate(dataSource).execute((ConnectionCallback<Void>) con -> {
            try (CallableStatement cs = con.prepareCall(
                    "{ call QXP_PK_DATA_STORAGE.Insert_Data(?, ?, ?, ?, ?, ?, ?, ?, ?) }")) {
                OraclePreparedStatement ops = cs.unwrap(OraclePreparedStatement.class);
                ops.setInt(1, idSuivi);
                ops.setInt(2, idRun);
                ops.setTimestamp(3, Timestamp.valueOf(dateGeneration));
                ops.setInt(4, storeType);
                // setPlsqlIndexTable(paramIndex, data, maxLen, curLen, elemSqlType, elemMaxLen)
                ops.setPlsqlIndexTable(5, names, names.length, names.length, OracleTypes.VARCHAR, 4000);
                ops.setPlsqlIndexTable(6, values, values.length, values.length, OracleTypes.VARCHAR, 4000);
                ops.setPlsqlIndexTable(7, descriptifs, descriptifs.length, descriptifs.length,
                        OracleTypes.VARCHAR, 4000);
                ops.setPlsqlIndexTable(8, infos, infos.length, infos.length, OracleTypes.VARCHAR, 4000);
                ops.setInt(9, historisationDifferentielle ? 1 : 0);
                ops.execute();
            }
            return null;
        });
        log.info("Inserted {} data storage entries (type={}) for run [{}]",
                names.length, storeType, idRun);
    }
}
```

---

## `business/EndRunBusiness.java` — CHANGED
```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DataNameValue;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunResult;
import com.socgen.sgs.api.quark.engine.domain.RunStatus;
import com.socgen.sgs.api.quark.engine.domain.StoreDataType;
import com.socgen.sgs.api.quark.engine.infra.dao.AuditDao;
import com.socgen.sgs.api.quark.engine.infra.dao.EndRunDao;
import com.socgen.sgs.api.quark.engine.infra.dao.InsertDataStorageDao;
import com.socgen.sgs.api.quark.engine.infra.dao.InsertDocumentDao;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Orchestrates run finalization within a single transaction.
 * Inserts generated documents, updates run status, stores errors and data.
 *
 * Cross-reference: .NET Proxy_Run.End_Run()
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class EndRunBusiness {

    private static final int ID_SOUS_CATEGORIE_QXP = 6;
    private static final int ID_SOUS_CATEGORIE_PDF = 7;
    private static final int ID_SOUS_CATEGORIE_DOC = 8;

    private final EndRunDao endRunDao;
    private final InsertDocumentDao insertDocumentDao;
    private final InsertDataStorageDao insertDataStorageDao;
    private final AuditDao auditDao;

    /**
     * Finalize a run — insert documents, errors, data, and update status.
     * All operations within a single transaction.
     *
     * @param run the run to finalize
     */
    @Transactional
    public void execute(Run run) {
        log.info("Finalizing run [{}] with status [{}]", run.getId(), run.getStatus());

        run.setEndDate(LocalDateTime.now());
        int statusCode = run.getStatus().getCode();

        // Accumulated run trace persisted to the p_log_trace CLOB. Cross-reference: .NET Run.Trace_Context.All_Logs.
        String traceLog = run.getTraceLog();

        if (run.getStatus() == RunStatus.ERROR) {
            // Error case: just update status
            endRunDao.updateStatusRun(
                    run.getId(), statusCode, statusCode,
                    run.getEndDate(), traceLog);

        } else {
            // Success case: insert documents then end run
            int idQxp = insertGeneratedDocument(run, run.getResult().getFinalQxp(), ID_SOUS_CATEGORIE_QXP);
            int idPdf = insertGeneratedDocument(run, run.getResult().getFinalPdf(), ID_SOUS_CATEGORIE_PDF);
            int idDoc = Integer.MIN_VALUE; // Word not generated (skipped in .NET too)

            endRunDao.endRun(
                    run.getId(), statusCode,
                    run.getRunProperties().getIdSuivi(), statusCode,
                    run.getEndDate(), traceLog,
                    idPdf, idQxp, idDoc);
        }

        // Always insert errors
        insertErrors(run);

        // Always insert the audit row (matches .NET End_Run order: status/end -> errors -> audit -> data).
        auditDao.insertAuditRun(run, buildAuditMessage(run));

        // Store data only if not in error
        if (run.getStatus() != RunStatus.ERROR) {
            insertDataStorage(run);
        }

        log.info("Run [{}] finalized successfully", run.getId());
    }

    private int insertGeneratedDocument(Run run, DocumentDomain document, int idSousCategorie) {
        if (document == null || document.getData() == null) {
            return Integer.MIN_VALUE;
        }
        return insertDocumentDao.insertDocument(
                document, idSousCategorie,
                run.getRunProperties().getIdFndCode(),
                run.getRunProperties().getIdUnitCode(),
                run.getRunProperties().getDateEcheance(),
                run.getId());
    }

    /** Short audit message: status + error summary (the DAO truncates to the column size). */
    private String buildAuditMessage(Run run) {
        List<RunError> errors = run.getErrors();
        if (errors.isEmpty()) {
            return "Run " + run.getId() + " " + run.getStatus();
        }
        return "Run " + run.getId() + " " + run.getStatus()
                + " - " + errors.size() + " error(s): " + errors.get(0).getMessage();
    }

    private void insertErrors(Run run) {
        List<RunError> errors = run.getErrors();
        if (errors.isEmpty()) return;

        String[] messages = new String[errors.size()];
        int[] categories = new int[errors.size()];

        for (int i = 0; i < errors.size(); i++) {
            // Parity: .NET Proxy_Error replaces a blank message with the "aucun" sentinel
            // (Proxy_Error.cs:115-118, MessageVide = "aucun") before binding.
            String message = errors.get(i).getMessage();
            messages[i] = (message == null || message.isBlank()) ? "aucun" : message;
            categories[i] = errors.get(i).getCategory();
        }

        endRunDao.insertRunErrors(run.getId(), messages, categories);
    }

    /**
     * Insert data storage entries for SQL and DOCUMENT types.
     * SQL data uses simple historisation (0), DOCUMENT uses differential (1).
     *
     * Cross-reference: .NET Proxy_Store.Insert_Data_Storage
     */
    private void insertDataStorage(Run run) {
        // Bitwise tests on the raw store-type code so a combined value (0x03) persists BOTH SQL and
        // DOCUMENT storage. (.NET Run_Base.cs:677/699.) Finding #1.
        int storeCode = run.getRunProperties().getStoreDataTypeCode();

        // SQL data storage (historisation_differentielle = false)
        if (StoreDataType.hasFlag(storeCode, StoreDataType.SQL) && !run.getSqlDataNamesValues().isEmpty()) {
            String[][] arrays = toArrays(run.getSqlDataNamesValues());
            insertDataStorageDao.insertData(
                    run.getRunProperties().getIdSuivi(),
                    run.getId(),
                    run.getEndDate(),
                    StoreDataType.SQL.getCode(),
                    arrays[0], arrays[1], arrays[2], arrays[3],
                    false);
        }

        // Document data storage (historisation_differentielle = true)
        if (StoreDataType.hasFlag(storeCode, StoreDataType.DOCUMENT) && !run.getDocDataNamesValues().isEmpty()) {
            String[][] arrays = toArrays(run.getDocDataNamesValues());
            insertDataStorageDao.insertData(
                    run.getRunProperties().getIdSuivi(),
                    run.getId(),
                    run.getEndDate(),
                    StoreDataType.DOCUMENT.getCode(),
                    arrays[0], arrays[1], arrays[2], arrays[3],
                    true);
        }
    }

    /**
     * Convert DataNameValue list to parallel arrays.
     * Cross-reference: .NET DataNamesValues.ToArrays()
     *
     * @return [0]=names, [1]=values, [2]=descriptifs, [3]=infos
     */
    private String[][] toArrays(List<DataNameValue> dataList) {
        int maxNameSize = 30;
        int maxValueSize = 500;
        int maxDescriptifSize = 250;
        int maxInfoSize = 4000;

        String[] names = new String[dataList.size()];
        String[] values = new String[dataList.size()];
        String[] descriptifs = new String[dataList.size()];
        String[] infos = new String[dataList.size()];

        for (int i = 0; i < dataList.size(); i++) {
            DataNameValue dnv = dataList.get(i);
            names[i] = truncate(dnv.getName(), maxNameSize);
            values[i] = truncate(dnv.getValue(), maxValueSize);
            descriptifs[i] = truncate(dnv.getDescriptif(), maxDescriptifSize);
            infos[i] = truncate(dnv.getInfo(), maxInfoSize);
        }

        return new String[][]{names, values, descriptifs, infos};
    }

    private String truncate(String value, int maxLength) {
        if (value == null) return "";
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}
```

---

## Apply checklist
- [ ] Replace `infra/dao/impl/EndRunDaoImpl.java`
- [ ] Replace `infra/dao/impl/InsertDataStorageDaoImpl.java`
- [ ] Replace `business/EndRunBusiness.java`
- [ ] `mvn compile`
- [ ] `mvn test`
- [ ] **Live-DB**: run a generation that produces (a) ≥1 run error and (b) store_data SQL+DOCUMENT, and confirm `QXP_RUN_ERROR` + `QXP_DATA_STORAGE` rows are written without ORA-00902/PLS-00306.
