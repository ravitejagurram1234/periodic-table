# EOS Quark — date-bind blocker + document-store logging + tracing-spam silence (changes only)

**Repo:** `14-07 engine service repo/quark-engine`.
Only the diffs are shown below, so you can skip any you already applied.

## Context (why)
Run 339403 / task 229 failed with `ORA-01858`. The same SQL run manually with the 3 in-params returned
**21 rows**, so the SQL is fine — it's a **Java bind-type bug on the date**: the SQL does
`to_date(:p_date_echeance)` and the date was bound as a `java.sql.Timestamp`. Oracle renders that timestamp
via `NLS_TIMESTAMP_FORMAT` (`"29-JUN-18 …"`) then parses with `DD/MM/YYYY` → chokes on `J` in `JUN` →
`ORA-01858`. Binding a real Oracle `DATE` makes `to_date(DATE)` round-trip and work.

---

## 1. `InParamSqlMapper.java` — bind DATE as Oracle `DATE` *(THE blocker)*
Path: `src/main/java/com/socgen/sgs/api/quark/engine/mapper/InParamSqlMapper.java`
In `toTypedValue(...)`, the **`DATE` case** must return `new oracle.sql.DATE(ts)` for a valid date — not the
raw `Timestamp`. The only essential change is `: ts` → `: new oracle.sql.DATE(ts)`.

**BEFORE** (your build likely has one of these — both bind a `Timestamp`):
```java
            case DATE:
                return toSqlTimestamp(value);
```
```java
            // or the sentinel-null variant:
            case DATE: {
                Timestamp ts = toSqlTimestamp(value);
                return DATETIME_MIN_VALUE.equals(ts) ? new SqlParameterValue(Types.DATE, null) : ts;
            }
```

**AFTER** (bind Oracle `DATE`):
```java
            case DATE: {
                // A valid date binds as an Oracle DATE (time-preserving) so the gabarit SQL's to_date(?)
                // round-trips regardless of the session date format; an unset value binds as SQL NULL.
                Timestamp ts = toSqlTimestamp(value);
                return DATETIME_MIN_VALUE.equals(ts)
                        ? new SqlParameterValue(Types.DATE, null)
                        : new oracle.sql.DATE(ts);
            }
```
No new import needed (`oracle.sql.DATE` is fully qualified). `Types` / `SqlParameterValue` are already
imported if you have the sentinel-null variant; if not, add
`import org.springframework.jdbc.core.SqlParameterValue;` and `import java.sql.Types;`.

---

## 2. `EndRunBusiness.java` — log where the generated document is stored
Path: `src/main/java/com/socgen/sgs/api/quark/engine/business/EndRunBusiness.java`

**BEFORE** (`insertGeneratedDocument`):
```java
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
```

**AFTER** (add the two log lines + the `documentKind` helper):
```java
    private int insertGeneratedDocument(Run run, DocumentDomain document, int idSousCategorie) {
        String kind = documentKind(idSousCategorie);
        if (document == null || document.getData() == null) {
            log.info("No {} generated for run [{}] — nothing stored in QXP_DOCUMENT", kind, run.getId());
            return Integer.MIN_VALUE;
        }
        int idDocument = insertDocumentDao.insertDocument(
                document, idSousCategorie,
                run.getRunProperties().getIdFndCode(),
                run.getRunProperties().getIdUnitCode(),
                run.getRunProperties().getDateEcheance(),
                run.getId());
        log.info("Stored {} document [id={}, {} bytes] in QXP_DOCUMENT for run [{}] (pool file: {})",
                kind, idDocument, document.getData().length, run.getId(), document.getFilePoolPath());
        return idDocument;
    }

    private static String documentKind(int idSousCategorie) {
        switch (idSousCategorie) {
            case ID_SOUS_CATEGORIE_QXP: return "QXP";
            case ID_SOUS_CATEGORIE_PDF: return "PDF";
            case ID_SOUS_CATEGORIE_DOC: return "Word";
            default: return "document(cat=" + idSousCategorie + ")";
        }
    }
```
Gives, at End_Run: `Stored PDF document [id=987654, 412300 bytes] in QXP_DOCUMENT for run [339403] (pool file: R_339403/G_168_1.QXP)`.

---

## 3. `application-local.yaml` — silence "Failed to export spans" *(local only, additive)*
Path: `src/main/config/local/application-local.yaml`
Add this block (nothing to replace):
```yaml
management:
  tracing:
    sampling:
      probability: 0.0   # no spans sampled -> nothing exported -> no localhost:9411 stack-trace spam
```
(Alternative that only mutes the log: `logging.level.io.opentelemetry.exporter.zipkin: "off"`.)

---

## Verify
`mvn clean install`, re-run 339403 → expect `Dynamic task [229] (run [339403]) SQL fetched 21 rows`,
`Stored QXP/PDF document …` at End_Run, and no more "Failed to export spans" traces.

## Files touched
- `mapper/InParamSqlMapper.java` (§1 — DATE → `oracle.sql.DATE`) — **the fix that unblocks the data**
- `business/EndRunBusiness.java` (§2 — doc-store logging)
- `src/main/config/local/application-local.yaml` (§3 — tracing off)
