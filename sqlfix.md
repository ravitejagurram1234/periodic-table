# EOS Quark — Dynamic-SQL Date Failure (ORA-01843 / ORA-01830) — Root Cause & Fix

**Run that exposed it:** 488654 (Dynamique, 24 tasks). The pipeline now completes end-to-end
(SOAP modify → QXP saved → PDF render → End_Run → `GENERATED`), **but every dynamic task SQL failed**
with `ORA-01843: not a valid month` / `ORA-01830: date format picture ends before converting entire
input string`, so each task logged "has no blocs after processing" and the PDF came out empty
(36 boxes in overflow). The HTTP run still reported success because the per-task failures are recorded
as run errors (166 inserted) rather than failing the run — see §4.

---

## 1. Root cause (two independent date problems, both required to fix)

The failing statements are the **gabarit (task) SQL** stored in the DB and shared verbatim by .NET and
Java. Both faces are about Oracle dates.

### 1a. Session NLS_DATE_FORMAT is wrong for this SQL
The SQL contains **hardcoded day-first date literals** compared against DATE columns, e.g.
`rf.fnd_end_validity='31/12/2199'`, `qsm.date_campagne in '31/12/2199'`, `rf.FND_END_VALIDITY = '31/12/2199'`.
Oracle implicitly evaluates `to_date('31/12/2199', <session NLS_DATE_FORMAT>)`. That string **only parses
under `NLS_DATE_FORMAT='DD/MM/YYYY'`** (month 31 / "12 not a month" otherwise).

- **.NET production** ran with a day-first (European) Oracle session → literals parse → OK.
- **Java** sets **no NLS** (verified: nothing in the codebase). The Oracle thin driver derives
  `NLS_DATE_FORMAT` from the JVM locale (commonly `DD-MON-RR`/US-ish) → `'31/12/2199'` →
  **ORA-01843 / ORA-01830**.

`DD/MM/YYYY` is **dictated by the literals in the SQL itself** — it is not a guess.

### 1b. Date in-params are bound as the wrong Oracle type
Confirmed against .NET source:
`InParam.cs` → `Data_Type_Helper.InputToTypedValue` → `ConversionInvariante.ToDateTime` parses a **Date(4)**
param string (US `MM/dd/yyyy`, InvariantCulture) into a `System.DateTime`; `InParams.cs` binds that value;
ODP.NET sends a `System.DateTime` as an **Oracle DATE**. So `to_date(?)` in the SQL receives a DATE and
round-trips cleanly.

Java's `InParamSqlMapper` bound the Date(4) param as a **`java.sql.Timestamp`** → the driver sends an
Oracle **TIMESTAMP** → `to_date(TIMESTAMP)` forces a TIMESTAMP→string→date conversion whose time/fractional
component the DATE format can't consume → **ORA-01830 / ORA-01843**.

**Why both fixes are needed (neither alone suffices):** there is no single `NLS_DATE_FORMAT` that makes
both a bare-date literal (`'31/12/2199'`, no time) **and** a timestamp-with-time bind parse through the same
`to_date`. Binding the param as a true Oracle **DATE** makes `to_date(DATE)` round-trip under
`NLS_DATE_FORMAT='DD/MM/YYYY'`, and that same format parses the literals. Both satisfied.

---

## 2. Changes (apply all)

### 2.1 `InParamSqlMapper.java` — bind DATE as Oracle DATE (not Timestamp)  *(REQUIRED)*
Path: `src/main/java/com/socgen/sgs/api/quark/engine/mapper/InParamSqlMapper.java`
Whole file:

```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.sql.Timestamp;
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
 *   <li>INT      → {@link Integer} (Int32 truncation; {@code int.MinValue} sentinel when unset/unparseable)</li>
 *   <li>DECIMAL  → {@link BigDecimal} ({@code decimal.MinValue} sentinel when unset/unparseable)</li>
 *   <li>DATE     → an Oracle {@code DATE} ({@link oracle.sql.DATE}, time-preserving; {@code DateTime.MinValue}
 *       sentinel). .NET binds the parsed {@code System.DateTime} which ODP.NET sends as an Oracle DATE, so
 *       the gabarit SQL's {@code to_date(?)} round-trips cleanly under any session NLS_DATE_FORMAT. Binding a
 *       {@code java.sql.Timestamp} instead would send an Oracle TIMESTAMP, and {@code to_date(TIMESTAMP)} fails
 *       (ORA-01830 / ORA-01843) because the timestamp's implicit string carries time the DATE format can't
 *       consume. Finding #50 / date-binding fix.</li>
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
            case INT:
                return toInt(value);
            case DECIMAL:
                return toDecimal(value);
            case DATE:
                return toOracleDate(value);
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
     * Binds a DATE param as an Oracle {@code DATE} (time-preserving), matching ODP.NET which sends the
     * parsed {@code System.DateTime} as an Oracle DATE. This makes {@code to_date(?)} in the gabarit SQL
     * round-trip cleanly regardless of the session NLS_DATE_FORMAT (unlike a {@code java.sql.Timestamp},
     * which the driver sends as TIMESTAMP and {@code to_date(TIMESTAMP)} cannot parse → ORA-01830/01843).
     */
    private oracle.sql.DATE toOracleDate(String value) {
        return new oracle.sql.DATE(toSqlTimestamp(value));
    }

    /**
     * Parses a DATE param string to a time-preserving {@link Timestamp}. Parity: .NET
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

### 2.2 `application.yaml` — pin the session date format  *(REQUIRED)*
Path: `src/main/resources/application.yaml`. Under `spring.datasource`, add the `hikari` block:

```yaml
  datasource:
    driver-class-name: oracle.jdbc.driver.OracleDriver
    url: jdbc:oracle:thin:@osfreygp3dwpp.ocp.cloud.socgen:1522:YGP3DWPP
    username: qxp
    password: ******** - commented since it's a secret
    hikari:
      # Pin the Oracle session date format on every pooled connection. The gabarit (task) SQL contains
      # hardcoded day-first date literals compared against DATE columns (e.g. '31/12/2199'), which Oracle
      # parses with the session NLS_DATE_FORMAT. The .NET production app ran with a day-first session; the
      # Java thin driver otherwise derives the format from the JVM locale, so those literals (and to_date(?))
      # fail with ORA-01843 / ORA-01830. DD/MM/YYYY is dictated by the literals in the SQL itself.
      connection-init-sql: ALTER SESSION SET NLS_DATE_FORMAT='DD/MM/YYYY'
```

> Belt-and-suspenders verification (optional, run once): on a Java-app connection vs the .NET app's
> connection, compare `SELECT parameter, value FROM nls_session_parameters WHERE parameter LIKE 'NLS_DATE%'`.
> If .NET shows anything other than `DD/MM/YYYY`, set ours to match that exact value instead.

### 2.3 `InParamSqlMapperTest.java` — update DATE assertions to Oracle DATE
Path: `src/test/java/com/socgen/sgs/api/quark/engine/mapper/InParamSqlMapperTest.java`
Replace the `dateTimePreserving` test:

```java
    @Test
    @DisplayName("#50 DATE binds a time-preserving Oracle DATE; DateTime.MinValue sentinel on unparseable")
    void dateTimePreserving() throws java.sql.SQLException {
        // Bound as oracle.sql.DATE (Oracle DATE) so the gabarit SQL's to_date(?) round-trips; assert via
        // its timestampValue() to keep the time component check.
        Object parsed = map(DataTypeEnum.DATE, "12/29/2023 14:30:00");
        assertEquals(Timestamp.valueOf(LocalDateTime.of(2023, 12, 29, 14, 30, 0)),
                ((oracle.sql.DATE) parsed).timestampValue());
        assertEquals(DATETIME_MIN, ((oracle.sql.DATE) map(DataTypeEnum.DATE, "")).timestampValue());
    }
```

### 2.4 Delete two dead SOAP stubs  *(cleanup — you asked)*
Both are empty stubs still naming the **old** `qxpsmsdk.wsdl` / `QManagerSDKSvc` that no longer exists; the
real client is `infra/interop/qxpsm/QxpsmSoapClient`. Nothing references them. Delete:
- `src/main/java/com/socgen/sgs/api/quark/engine/integration/soap/client/EngineSoapClient.java`
- `src/main/java/com/socgen/sgs/api/quark/engine/integration/soap/config/SoapConfig.java`

(The `integration/soap/generated/` package is the Axis-generated QXPS model — leave it alone.)

---

## 3. Apply order
1. Apply §2.1, §2.2, §2.3; delete §2.4 files.
2. `mvn clean install` → expect `BUILD SUCCESS`.
3. Re-run **488654**. Expect the per-task `ORA-01843 / ORA-01830` errors to disappear, tasks to produce
   blocs, and the rendered PDF to contain real content.

---

## 4. Separate item — "endpoint reports success though the run failed" (verify, do not guess)
The run finalized `GENERATED` while inserting 166 errors and producing no blocs. Recording per-task SQL
failures as run errors and still finalizing **may be .NET-faithful** (that is how .NET surfaces partial
failures — via the run error table, not a hard fail). Before changing the status/HTTP semantics I want to
confirm against the .NET `End_Run` / run-status logic. The date fix above removes the failures for this run,
so the question is moot here; it is tracked as a follow-up, not changed blindly.

## 5. Side note — host inconsistency in this repo's application.yaml
`qxps.server.url` = DEV `srvcldvapd001` (matches the run logs), but `qxp.thirdparty.url` and
`qxpsm.soap.endpoint` point at `srvcldqxpu001` (UAT). Not related to the date errors, but worth aligning all
three to the same environment before a real campaign.
