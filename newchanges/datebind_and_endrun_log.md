# EOS Quark — production-verified date fix + document logging + tracing-spam silence (changes only)

**Repo:** `14-07 engine service repo/quark-engine`.
Only the diffs are shown so you can skip anything already applied. §1 is verified against .NET.

## Context (verified vs .NET)
Run 339403 / task 229 failed with `ORA-01858`; the same SQL run manually with the 3 in-params returned
**21 rows**, so the SQL is correct — it was a **Java date bind/parse bug**. Verified how .NET does it
(`ConversionInvariante.ToDateTime` + `OracleParameter.GetParameter(DateTime)`):

| Aspect | .NET | Java must do |
|---|---|---|
| Parse | `DateTime.TryParse(value, **InvariantCulture**, None)` — **month-first**, lenient, accepts **date-only AND date+time**, keeps time | month-first, optional time |
| Empty / bad input | → `DateTime.MinValue` (no throw) | → sentinel → SQL NULL |
| Bind | `OracleDbType.**Date**` (Oracle DATE, not Timestamp); `MinValue → DBNull` | `oracle.sql.DATE`; unset → SQL NULL |

The **bind** (`oracle.sql.DATE`) already matched. The **parse** was too strict (`"M/d/yyyy HH:mm:ss"` required
a time) — a **date-only** value silently became NULL where .NET parses it. §1 fixes the parse to match .NET.

---

## 1. `InParamSqlMapper.java` — the date fix *(4 small edits)*
Path: `src/main/java/com/socgen/sgs/api/quark/engine/mapper/InParamSqlMapper.java`

**1a. Imports** — add these three (next to the existing `java.time.*` imports):
```java
import java.time.format.DateTimeFormatterBuilder;
import java.time.temporal.ChronoField;
import java.util.Locale;
```

**1b. `INPUT_FORMAT`** — replace the strict formatter with a lenient, month-first, optional-time one:
```java
// BEFORE:
private static final DateTimeFormatter INPUT_FORMAT = DateTimeFormatter.ofPattern("M/d/yyyy HH:mm:ss");

// AFTER (mirrors .NET DateTime.TryParse(value, InvariantCulture, None)):
private static final DateTimeFormatter INPUT_FORMAT = new DateTimeFormatterBuilder()
        .parseCaseInsensitive()
        .appendPattern("M/d/uuuu")
        .optionalStart().appendLiteral(' ').appendPattern("H:m:s").optionalEnd()
        .parseDefaulting(ChronoField.HOUR_OF_DAY, 0)
        .parseDefaulting(ChronoField.MINUTE_OF_HOUR, 0)
        .parseDefaulting(ChronoField.SECOND_OF_MINUTE, 0)
        .toFormatter(Locale.ROOT);
```

**1c. `toSqlTimestamp(...)`** — replace with the lenient version (adds a date-only path + ISO fallbacks):
```java
    private Timestamp toSqlTimestamp(String value) {
        if (value == null || value.trim().isEmpty()) {
            return DATETIME_MIN_VALUE;
        }
        String v = value.trim();
        try {
            return Timestamp.valueOf(LocalDateTime.parse(v, INPUT_FORMAT)); // month-first, date-only or date+time
        } catch (Exception ignored) {
            try {
                return Timestamp.valueOf(LocalDateTime.parse(v));           // ISO yyyy-MM-ddTHH:mm:ss
            } catch (Exception ignored2) {
                try {
                    return Timestamp.valueOf(LocalDate.parse(v).atStartOfDay()); // ISO yyyy-MM-dd
                } catch (Exception ignored3) {
                    return DATETIME_MIN_VALUE;
                }
            }
        }
    }
```

**1d. DATE bind (the `to_date` blocker)** — in `toTypedValue(...)`, the `DATE` case must return
`new oracle.sql.DATE(ts)` (Oracle DATE), **not** the raw `Timestamp`. Confirm your build has the `oracle.sql.DATE` line:
```java
            case DATE: {
                Timestamp ts = toSqlTimestamp(value);
                return DATETIME_MIN_VALUE.equals(ts)
                        ? new SqlParameterValue(Types.DATE, null)
                        : new oracle.sql.DATE(ts);   // ← Oracle DATE (matches .NET OracleDbType.Date)
            }
```

*(Handled by 1a–1d, now covers: `"06/29/2018 00:00:00"`, date-only `"06/29/2018"`, single-digit `"6/9/2018 9:5:3"`,
ISO `"2018-06-29"`; empty/garbage → SQL NULL. Month-first, matching .NET Invariant.)*

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

---

## 3. `application-local.yaml` — silence "Failed to export spans" *(local only, additive)*
Path: `src/main/config/local/application-local.yaml` — add (nothing to replace):
```yaml
management:
  tracing:
    sampling:
      probability: 0.0   # no spans sampled -> nothing exported -> no localhost:9411 stack-trace spam
```

---

## Verify
`mvn clean install` (the added `InParamSqlMapperTest.dateParseMatchesDotNet` covers date-only / single-digit /
ISO / month-first / unparseable). Re-run 339403 → expect `Dynamic task [229] (run [339403]) SQL fetched
21 rows`, the `Stored … document …` lines, and no span stack-traces.

## One thing to confirm with real data
The parser handles the observed/realistic formats (4-digit year, `/` separator, 24-h time, with or without
time). .NET's `TryParse(Invariant)` is even looser (2-digit years, `AM/PM`, other separators). If any date
`valeur` in your DB uses those, send me a few samples (`SELECT valeur FROM qxp_asso_suivi_parametres WHERE …`
for date params across report types) and I'll widen the parser to match exactly.

## Files touched
- `mapper/InParamSqlMapper.java` (§1 — parse + `oracle.sql.DATE` bind) — **the fix**
- `mapper/InParamSqlMapperTest.java` (new date-parse cases)
- `business/EndRunBusiness.java` (§2 — doc-store logging)
- `src/main/config/local/application-local.yaml` (§3 — tracing off)
