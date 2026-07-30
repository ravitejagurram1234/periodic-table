# EOS Quark — Dynamic-SQL Date / NLS Fix for the 14-07 repo (copy-paste ready)

**Repo:** `14-07 engine service repo/quark-engine` (current repo of record).
**Why this doc:** the earlier date-fix (`EOS_Quark_DynamicSQL_Date_Fix.md`, ORA-01843 / ORA-01830) was
**never applied to this 14-07 repo** — verified today:
- `application.yaml` has **no** `NLS_DATE_FORMAT` / `hikari` / `connection-init-sql`.
- `InParamSqlMapper` still binds DATE as `java.sql.Timestamp` (not `oracle.sql.DATE`).
- The two dead SOAP stubs still exist.

> ⚠️ **IMPORTANT — one merged file.** `InParamSqlMapper.java` is *also* touched by the sentinel→NULL batch
> (`EOS_Quark_RunAnalysis_Fixes_488654_505244.md`). The whole-file in **§1 below is the single MERGED
> version** that contains BOTH changes: (a) DATE → `oracle.sql.DATE` (this date fix) **and** (b) unset
> INT/DECIMAL/DATE sentinel → typed SQL NULL (the sentinel batch). **Paste §1 as the definitive
> `InParamSqlMapper` — it supersedes the version in the June date-fix doc AND the one in the sentinel
> batch.** Do not paste either of those older whole-files over it.

All four items below are already applied in the 14-07 working copy; the whole files here match it exactly.

---

## Root cause recap (two independent date problems — both required)

1. **Session `NLS_DATE_FORMAT` is wrong.** The gabarit (task) SQL has hardcoded day-first date literals vs
   DATE columns (e.g. `rf.fnd_end_validity='31/12/2199'`). Oracle evaluates `to_date('31/12/2199',
   <session NLS_DATE_FORMAT>)`, which only parses under `DD/MM/YYYY`. .NET prod ran a day-first session;
   the Java thin driver derives the format from the JVM locale → **ORA-01843 / ORA-01830**. `DD/MM/YYYY` is
   dictated by the literals themselves.
2. **DATE in-params were bound as the wrong Oracle type.** .NET binds the parsed `System.DateTime`, which
   ODP.NET sends as an **Oracle DATE**, so `to_date(?)` round-trips. Java bound a `java.sql.Timestamp` →
   driver sends an Oracle **TIMESTAMP** → `to_date(TIMESTAMP)` fails (time/fraction the DATE format can't
   consume). Fix: bind a true Oracle **DATE** (`oracle.sql.DATE`), time-preserving.

Neither alone suffices: only binding a real DATE + a day-first session makes both the bare-date literals and
the bound params parse through the same `to_date`.

---

## §1 — `InParamSqlMapper.java`  *(REQUIRED — merged, paste whole file)*
Path: `src/main/java/com/socgen/sgs/api/quark/engine/mapper/InParamSqlMapper.java`

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

## §2 — `application.yaml`: pin the session date format  *(REQUIRED)*
Path: `src/main/resources/application.yaml`

**Additive** — add the `hikari:` block under your existing `spring.datasource:` (same indentation, right
after the `password:` line). Nothing else in the datasource block changes, so **your password line stays
untouched**:

```yaml
    hikari:
      # Pin the Oracle session date format on every pooled connection. The gabarit (task) SQL contains
      # hardcoded day-first date literals compared against DATE columns (e.g. '31/12/2199'), parsed with
      # the session NLS_DATE_FORMAT. The .NET production app ran with a day-first session; the Java thin
      # driver otherwise derives the format from the JVM locale, so those literals (and to_date(?)) fail
      # with ORA-01843 / ORA-01830. DD/MM/YYYY is dictated by the literals in the SQL itself.
      connection-init-sql: ALTER SESSION SET NLS_DATE_FORMAT='DD/MM/YYYY'
```

Resulting block (for reference — password shown masked; keep your real value):

```yaml
  datasource:
    driver-class-name: oracle.jdbc.driver.OracleDriver
    url: jdbc:oracle:thin:@osfreygp3dwpp.ocp.cloud.socgen:1522:YGP3DWPP
    username: qxp
    password: ********            # keep your existing value
    hikari:
      connection-init-sql: ALTER SESSION SET NLS_DATE_FORMAT='DD/MM/YYYY'
```

> Belt-and-suspenders (optional, once): on a Java-app connection vs the .NET app's connection, compare
> `SELECT parameter, value FROM nls_session_parameters WHERE parameter LIKE 'NLS_DATE%'`. If .NET shows
> something other than `DD/MM/YYYY`, set ours to match that exact value.

---

## §3 — `InParamSqlMapperTest.java`  *(paste whole file)*
Path: `src/test/java/com/socgen/sgs/api/quark/engine/mapper/InParamSqlMapperTest.java`

```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.SqlParameterValue;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNull;

@DisplayName("InParamSqlMapper typed-binding Tests")
class InParamSqlMapperTest {

    private final InParamSqlMapper mapper = new InParamSqlMapper();

    private Object map(DataTypeEnum type, String value) {
        Map<String, InParam> in = new LinkedHashMap<>();
        in.put("p", new InParam("p", type, value));
        return mapper.toParameterMap(in).get("p");
    }

    /** Assert the mapped value is a typed SQL NULL of the expected java.sql.Types code. */
    private void assertTypedNull(int expectedSqlType, Object actual) {
        SqlParameterValue v = assertInstanceOf(SqlParameterValue.class, actual);
        assertEquals(expectedSqlType, v.getSqlType());
        assertNull(v.getValue());
    }

    @Test
    @DisplayName("#51 INT binds a typed Integer (truncating toward zero); unset/unparseable → typed SQL NULL")
    void intTyped() {
        assertEquals(123, map(DataTypeEnum.INT, "123"));
        assertEquals(12, map(DataTypeEnum.INT, "12.9"));      // (int)decimal truncates
        assertTypedNull(Types.NUMERIC, map(DataTypeEnum.INT, ""));
        assertTypedNull(Types.NUMERIC, map(DataTypeEnum.INT, "abc"));
    }

    @Test
    @DisplayName("#51 DECIMAL binds a typed BigDecimal; unset/unparseable → typed SQL NULL")
    void decimalTyped() {
        assertEquals(new BigDecimal("12.50"), map(DataTypeEnum.DECIMAL, "12.50"));
        assertTypedNull(Types.NUMERIC, map(DataTypeEnum.DECIMAL, ""));
        assertTypedNull(Types.NUMERIC, map(DataTypeEnum.DECIMAL, "n/a"));
    }

    @Test
    @DisplayName("#50 DATE binds a time-preserving Oracle DATE; unparseable → typed SQL NULL")
    void dateTimePreserving() throws java.sql.SQLException {
        // A valid date is bound as oracle.sql.DATE; assert via timestampValue() to keep the time check.
        Object parsed = map(DataTypeEnum.DATE, "12/29/2023 14:30:00");
        assertEquals(Timestamp.valueOf(LocalDateTime.of(2023, 12, 29, 14, 30, 0)),
                ((oracle.sql.DATE) parsed).timestampValue());
        assertTypedNull(Types.DATE, map(DataTypeEnum.DATE, ""));
    }

    @Test
    @DisplayName("#21 DATE_TIME (and TEXT) bind the RAW STRING (matches .NET switch default)")
    void dateTimeAndTextRawString() {
        assertEquals("12/29/2023 14:30:00", map(DataTypeEnum.DATE_TIME, "12/29/2023 14:30:00"));
        assertEquals("hello", map(DataTypeEnum.TEXT, "hello"));
    }
}
```

---

## §4 — Delete two dead SOAP stubs  *(cleanup)*
Empty stubs still naming the old `qxpsmsdk.wsdl` / `QManagerSDKSvc`; nothing references them (the real
client is `infra/interop/qxpsm/QxpsmSoapClient`). Delete:
- `src/main/java/com/socgen/sgs/api/quark/engine/integration/soap/client/EngineSoapClient.java`
- `src/main/java/com/socgen/sgs/api/quark/engine/integration/soap/config/SoapConfig.java`

(Leave `integration/soap/generated/` — that's the Axis-generated QXPS model.)

---

## Apply order
1. Paste §1 (whole `InParamSqlMapper.java`), add §2 (yaml), paste §3 (whole test); delete §4 files.
2. `mvn clean install` → expect `BUILD SUCCESS`.
3. Re-run **488654**: the per-task `ORA-01843 / ORA-01830` (and the `ORA-01722` from the sentinel batch)
   should be gone; dynamic tasks produce blocs; the rendered PDF has real content.

## Notes
- **Host alignment (was §5 in the June doc): already resolved here.** All three Quark URLs in this repo's
  `application.yaml` point at DEV `srvcldvapd001` (`qxps.server.url`, `qxpsm.soap.endpoint`,
  `qxp.thirdparty.url`). Nothing to change.
- Unrelated cleanup still present (not touched here): the TEMP `logging.level.org.apache.axis.transport.http:
  DEBUG` block near the bottom of `application.yaml` can be removed once SOAP wire-diagnosis is no longer
  needed.

## Files changed
- `src/main/java/.../mapper/InParamSqlMapper.java` (§1, merged)
- `src/main/resources/application.yaml` (§2)
- `src/test/java/.../mapper/InParamSqlMapperTest.java` (§3)
- deleted: `integration/soap/client/EngineSoapClient.java`, `integration/soap/config/SoapConfig.java` (§4)
```
