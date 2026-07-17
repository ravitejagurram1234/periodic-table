# EOS Quark — date-bind blocker + document-store logging + tracing-spam silence (copy-paste ready)

**Repo:** `14-07 engine service repo/quark-engine`.
Three changes bundled: (1) the `ORA-01858` blocker fix (bind DATE as an Oracle `DATE`), (2) log where the
generated document is stored, (3) silence the Zipkin "Failed to export spans" noise.

## Context (why)
Run 339403 / task 229 failed with `ORA-01858`. Running the same SQL manually with the 3 in-params returned
**21 rows**, proving the SQL + params are correct — so it's a **Java bind-type bug on the date**:
the SQL does `to_date(:p_date_echeance)`, and the param was bound as a `java.sql.Timestamp`. Oracle evaluates
`to_date(TIMESTAMP)` by rendering the timestamp via `NLS_TIMESTAMP_FORMAT` (default `DD-MON-RR …` →
`"29-JUN-18 …"`) then parsing with `NLS_DATE_FORMAT='DD/MM/YYYY'` → hits the letter `J` in `JUN` →
`ORA-01858`. Binding a real Oracle `DATE` makes `to_date(DATE)` round-trip through `NLS_DATE_FORMAT` and work.

---

## 1. `InParamSqlMapper.java` — bind DATE as Oracle `DATE` *(the blocker — paste whole file)*
Path: `src/main/java/com/socgen/sgs/api/quark/engine/mapper/InParamSqlMapper.java`
Key line is the DATE case: `new oracle.sql.DATE(ts)` (your build likely still returns the raw `ts` Timestamp).

```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import org.springframework.jdbc.core.SqlParameterValue;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Maps run InParams to a flat parameter map for the dynamic-SQL named binds.
 *
 * <p>Binds the TYPED value for each param, mirroring .NET
 * {@code Data_Type_Helper.InputToTypedValue} + {@code ConversionInvariante} (InParam.cs:54 sets
 * {@code _value = InputToTypedValue(_string_value, _type)}, InParams.cs:69 binds {@code inParam.Value}):
 * <ul>
 *   <li>INT      → {@link Integer} (Int32 truncation); unset/unparseable → typed SQL NULL</li>
 *   <li>DECIMAL  → {@link BigDecimal}; unset/unparseable → typed SQL NULL</li>
 *   <li>DATE     → an Oracle {@code DATE} ({@link oracle.sql.DATE}, time-preserving) so the gabarit SQL's
 *       {@code to_date(?)} round-trips under any session date format; unset/unparseable → typed SQL NULL</li>
 *   <li>An unset value binds as SQL NULL (not the MIN_VALUE placeholder), matching how the legacy
 *       Oracle parameter layer converts an unset sentinel to a null bind.</li>
 *   <li>DATE_TIME and every other type → the RAW STRING — .NET's switch has no case for DateTime(5)
 *       (nor Text/Currency/Pourcentage), so it falls to {@code default: return value}.</li>
 * </ul>
 * Findings #21, #49, #50, #51.
 */
@Component
public class InParamSqlMapper {

    /** Format the date value arrives in from Oracle Get_In_Params (M/d/yyyy HH:mm:ss). */
    private static final DateTimeFormatter INPUT_FORMAT = DateTimeFormatter.ofPattern("M/d/yyyy HH:mm:ss");

    /** .NET {@code decimal.MinValue} — the sentinel ConversionInvariante.ToDecimal returns when unset/unparseable. */
    private static final BigDecimal DECIMAL_MIN_VALUE = new BigDecimal("-79228162514264337593543950335");

    /** .NET {@code DateTime.MinValue} (0001-01-01 00:00:00) — the sentinel ToDateTime returns when unset/unparseable. */
    private static final Timestamp DATETIME_MIN_VALUE = Timestamp.valueOf(LocalDateTime.of(1, 1, 1, 0, 0, 0));

    public Map<String, Object> toParameterMap(Map<String, InParam> inParams) {
        Map<String, Object> params = new LinkedHashMap<>();
        for (Map.Entry<String, InParam> entry : inParams.entrySet()) {
            params.put(entry.getKey(), toTypedValue(entry.getValue()));
        }
        return params;
    }

    private Object toTypedValue(InParam inParam) {
        String value = inParam.getStringValue();
        DataTypeEnum type = inParam.getType();
        if (type == null) {
            return value;
        }
        switch (type) {
            case INT: {
                // An unset / unparseable numeric input is bound as a typed SQL NULL, not as the
                // MIN_VALUE placeholder number. Binding the placeholder would force a numeric
                // predicate over a textual column through TO_NUMBER against that number, which
                // raises ORA-01722 on the first non-numeric column value.
                Integer i = toInt(value);
                return i == Integer.MIN_VALUE ? new SqlParameterValue(Types.NUMERIC, null) : i;
            }
            case DECIMAL: {
                // compareTo (not equals) so an unset value is caught regardless of its scale.
                BigDecimal d = toDecimal(value);
                return DECIMAL_MIN_VALUE.compareTo(d) == 0 ? new SqlParameterValue(Types.NUMERIC, null) : d;
            }
            case DATE: {
                // A valid date binds as an Oracle DATE (time-preserving) so the gabarit SQL's to_date(?)
                // round-trips regardless of the session date format; an unset value binds as SQL NULL.
                Timestamp ts = toSqlTimestamp(value);
                return DATETIME_MIN_VALUE.equals(ts)
                        ? new SqlParameterValue(Types.DATE, null)
                        : new oracle.sql.DATE(ts);
            }
            default:
                // DATE_TIME (5), TEXT, CURRENCY, POURCENTAGE, UNSPECIFIED, CUSTOM → raw string
                // (.NET Data_Type_Helper.InputToTypedValue `default: return value`).
                return value;
        }
    }

    /** .NET ConversionInvariante.ToInt: Decimal.TryParse(value w/o spaces, NumberStyles.Any) cast to Int32; else int.MinValue. */
    private Integer toInt(String value) {
        BigDecimal d = parseNumber(value);
        return d == null ? Integer.MIN_VALUE : d.intValue(); // intValue() truncates toward zero, like (int)decimal
    }

    /** .NET ConversionInvariante.ToDecimal: Decimal.TryParse(value w/o spaces, NumberStyles.Any); else decimal.MinValue. */
    private BigDecimal toDecimal(String value) {
        BigDecimal d = parseNumber(value);
        return d == null ? DECIMAL_MIN_VALUE : d;
    }

    /** Returns the parsed number, or null to signal the caller to bind its sentinel. */
    private BigDecimal parseNumber(String value) {
        if (value == null) {
            return null;
        }
        String v = value.replace(" ", ""); // .NET ToInt/ToDecimal do value.Replace(" ", "")
        if (v.isEmpty()) {
            return null;
        }
        try {
            return new BigDecimal(v);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /**
     * Converts a DATE param string to a time-preserving {@link Timestamp}. Parity: .NET
     * ConversionInvariante.ToDateTime returns the parsed DateTime, or DateTime.MinValue when
     * unset/unparseable (it does NOT throw).
     */
    private Timestamp toSqlTimestamp(String value) {
        if (value == null || value.trim().isEmpty()) {
            return DATETIME_MIN_VALUE;
        }
        String v = value.trim();
        try {
            return Timestamp.valueOf(LocalDateTime.parse(v, INPUT_FORMAT));
        } catch (Exception e) {
            try {
                return Timestamp.valueOf(LocalDate.parse(v).atStartOfDay());
            } catch (Exception e2) {
                return DATETIME_MIN_VALUE;
            }
        }
    }
}
```

---

## 2. `EndRunBusiness.java` — log where the generated document is stored *(snippet)*
Path: `src/main/java/com/socgen/sgs/api/quark/engine/business/EndRunBusiness.java`
Replace the `insertGeneratedDocument(...)` method with this, and add the `documentKind(...)` helper next to it:

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

You'll then see, at End_Run, e.g.:
`Stored PDF document [id=987654, 412300 bytes] in QXP_DOCUMENT for run [339403] (pool file: R_339403/G_168_1.QXP)`

> Where things land: the QXP is SaveAs'd to `D:\Documents\R_<runId>\<name>_1.QXP` **on the Quark host**
> (`srvcldvapd001`); the final PDF + QXP bytes are inserted into the **`QXP_DOCUMENT`** table (the persistent
> repository). Both are on the server side, not your laptop.

---

## 3. `application-local.yaml` — silence the "Failed to export spans" spam *(local dev only)*
Path: `src/main/config/local/application-local.yaml`
The Zipkin/OpenTelemetry exporter tries to POST traces to a local collector (`localhost:9411`) that isn't
running, and dumps a huge reactor stack each time. It's harmless. Add:

```yaml
management:
  tracing:
    sampling:
      probability: 0.0   # no spans sampled -> nothing exported -> no localhost:9411 connection spam
```
(Alternative, to only mute the log instead of disabling tracing: `logging.level.io.opentelemetry.exporter.zipkin: "off"`.)

---

## Apply & verify
1. Fix §1 (`InParamSqlMapper` DATE → `oracle.sql.DATE`) — the blocker.
2. Apply §2 (`EndRunBusiness` doc logging). *(Already applied in the 14-07 copy.)*
3. Add §3 (local tracing off).
4. `mvn clean install`, re-run 339403. Expect:
   - `Dynamic task [229] (run [339403]) SQL fetched 21 rows`
   - `Stored QXP document [...]` and `Stored PDF document [...]` at End_Run
   - no more "Failed to export spans" stack traces.

## Files changed
- `mapper/InParamSqlMapper.java` (§1 — DATE → `oracle.sql.DATE`)
- `business/EndRunBusiness.java` (§2 — document-store logging)
- `src/main/config/local/application-local.yaml` (§3 — tracing sampling 0)
