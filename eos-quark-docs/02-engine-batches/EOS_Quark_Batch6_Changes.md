# EOS Quark Engine — Batch 6 Changes
**Theme: InParam typed binding + tolerant INDEX_LIGNES parsing**

_Generated directly from the working-copy files. Whole-file copy-paste (plus one test snippet)._

## Findings fixed in this batch
| # | Sev | Issue | .NET reference |
|---|---|---|---|
| 21 | HIGH | DATE_TIME(5) bound as a date-truncated `java.sql.Date` | Data_Type_Helper.cs:158-165 — DateTime(5) hits `default: return value` (raw string) |
| 50 | MEDIUM | DATE(4) lost its time component (`java.sql.Date`) | Data_Type_Helper.cs:162 `Date → ToDateTime` (time-preserving); ConversionInvariante.cs:306 |
| 49 | MEDIUM | DATE_TIME truncated (companion of #21) | same as #21 |
| 51 | MEDIUM | INT/DECIMAL bound as raw strings instead of typed numerics | Data_Type_Helper.cs:158-161 `Int→ToInt`, `Decimal→ToDecimal`; InParams.cs:69 binds typed value |
| 52 | MEDIUM | `parseIndexLignes` threw `NumberFormatException` on a non-numeric token, aborting exception loading | Proxy_Task.cs:186-198 `ToIntArray(Split('|'))`; Conversion.ToInt → int.MinValue, never throws |

## The binding rule (now matches .NET `InputToTypedValue` exactly)
`Data_Type_Helper.InputToTypedValue` switches on the type and binds a TYPED value (InParam.cs:54 → InParams.cs:69 binds `inParam.Value`):
| Type | .NET | Java bind |
|---|---|---|
| INT (2) | `ToInt` → Int32 | `Integer` (truncates toward zero; `int.MinValue` sentinel if unset/unparseable) |
| DECIMAL (3) | `ToDecimal` → Decimal | `BigDecimal` (`decimal.MinValue` sentinel if unset/unparseable) |
| DATE (4) | `ToDateTime` → DateTime | `java.sql.Timestamp` (time-preserving; `DateTime.MinValue` sentinel) |
| **DATE_TIME (5)** | **no case → `default: return value`** | **raw `String`** |
| TEXT / CURRENCY / POURCENTAGE / … | `default: return value` | raw `String` |

**The surprising one — DATE_TIME(5) → raw string — is genuine .NET parity**, verified three independent ways (#21, #49, #50): the `Data_Type_Helper` switch has **no** `case Data_Type.DateTime`, so it falls through to `default`. The SQL procs receive the literal string for DATE_TIME params (as they always have under .NET). This is a binding-type detail (not a visible-output bug like the percentage case), so it is implemented as-is rather than queried — but flagged here for your awareness.

## INDEX_LIGNES (#52)
`parseIndexLignes` now splits keeping empty tokens and converts each WITHOUT throwing (blank/unparseable → `int.MinValue`), mirroring .NET `ToIntArray(Split('|'))` + `Conversion.ToInt`. The leading `isBlank()` guard is preserved because .NET only parses when `Validation.IsSet(string)` is true (a whitespace-only string stays `int[0]` → TABLE) — confirmed against `Proxy_Task.cs:186-198`. All 13 existing `TaskExceptionMapperTest` cases (including `"   "` → TABLE) remain valid.

## Sentinels (faithful to .NET, documented)
- INT unset/unparseable → `Integer.MIN_VALUE` (= .NET `int.MinValue`).
- DECIMAL unset/unparseable → `-79228162514264337593543950335` (= .NET `decimal.MinValue`).
- DATE unset/unparseable → `0001-01-01 00:00:00` (= .NET `DateTime.MinValue`). .NET returns this sentinel rather than throwing, so the new code does NOT throw on a malformed date (the old code threw `IllegalArgumentException`).

## Minor flagged deviation
`new BigDecimal(token)` does not parse thousands-grouped tokens (e.g. `"1,234"`) that .NET `Decimal.TryParse(NumberStyles.Any)` would. This affects only grouped numeric strings — not expected for line indices or normal INT/DECIMAL param values — and yields the sentinel instead. Flagged for completeness; can be revisited if such data exists.

---

## `mapper/InParamSqlMapper.java`
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
 *   <li>DATE     → {@link Timestamp} (time-preserving DateTime; {@code DateTime.MinValue} sentinel)</li>
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
                return toSqlTimestamp(value);
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

## `mapper/TaskExceptionMapper.java`
```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.task.TaskException;
import com.socgen.sgs.api.quark.engine.enums.TaskExceptionTypeEnum;
import org.springframework.stereotype.Component;

import java.util.Map;

@Component
public class TaskExceptionMapper {

    public int getIdTache(Map<String, Object> row) {
        Object val = row.get("ID_TACHE");
        return val instanceof Number ? ((Number) val).intValue() : 0;
    }

    public String getNomBloc(Map<String, Object> row) {
        Object val = row.get("NOM_BLOC");
        return val != null ? val.toString() : "";
    }

    public TaskException mapToTaskException(Map<String, Object> row) {
        String nomBloc = getNomBloc(row);
        String nomTableau = getString(row, "NOM_TABLEAU");
        String strIndexLignes = getString(row, "INDEX_LIGNES");

        int[] indexLignes = parseIndexLignes(strIndexLignes);
        TaskExceptionTypeEnum type = (indexLignes.length > 0)
                ? TaskExceptionTypeEnum.LINE
                : TaskExceptionTypeEnum.TABLE;

        return new TaskException(nomTableau, nomBloc, indexLignes, type);
    }

    private int[] parseIndexLignes(String value) {
        if (value == null || value.isBlank()) {
            return new int[0];
        }
        // Split keeping empty tokens and convert each WITHOUT throwing. Parity: .NET
        // Proxy_Task.cs:188 ToIntArray(value.Split('|')) keeps every token and Conversion.ToInt
        // returns int.MinValue for a blank/unparseable token (Decimal.TryParse(.., NumberStyles.Any)),
        // so a non-numeric token never aborts exception loading. Finding #52.
        String[] tokens = value.split("\\|", -1);
        int[] result = new int[tokens.length];
        for (int i = 0; i < tokens.length; i++) {
            result[i] = toInt(tokens[i]);
        }
        return result;
    }

    /** .NET Conversion.ToInt: parse value (spaces stripped); int.MinValue sentinel on blank/unparseable. */
    private int toInt(String token) {
        String v = token.replace(" ", "");
        if (v.isEmpty()) {
            return Integer.MIN_VALUE;
        }
        try {
            return new java.math.BigDecimal(v).intValue(); // truncates toward zero, like (int)decimal in .NET
        } catch (NumberFormatException e) {
            return Integer.MIN_VALUE;
        }
    }

    private String getString(Map<String, Object> row, String key) {
        Object val = row.get(key);
        return val != null ? val.toString() : null;
    }
}
```

---

## `src/test/.../mapper/InParamSqlMapperTest.java (NEW)`
```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

@DisplayName("InParamSqlMapper typed-binding Tests")
class InParamSqlMapperTest {

    private static final BigDecimal DECIMAL_MIN = new BigDecimal("-79228162514264337593543950335");
    private static final Timestamp DATETIME_MIN = Timestamp.valueOf(LocalDateTime.of(1, 1, 1, 0, 0, 0));

    private final InParamSqlMapper mapper = new InParamSqlMapper();

    private Object map(DataTypeEnum type, String value) {
        Map<String, InParam> in = new LinkedHashMap<>();
        in.put("p", new InParam("p", type, value));
        return mapper.toParameterMap(in).get("p");
    }

    @Test
    @DisplayName("#51 INT binds a typed Integer (truncating toward zero), sentinel on empty/unparseable")
    void intTyped() {
        assertEquals(123, map(DataTypeEnum.INT, "123"));
        assertEquals(12, map(DataTypeEnum.INT, "12.9"));      // (int)decimal truncates
        assertEquals(Integer.MIN_VALUE, map(DataTypeEnum.INT, ""));
        assertEquals(Integer.MIN_VALUE, map(DataTypeEnum.INT, "abc"));
    }

    @Test
    @DisplayName("#51 DECIMAL binds a typed BigDecimal, decimal.MinValue sentinel on empty/unparseable")
    void decimalTyped() {
        assertEquals(new BigDecimal("12.50"), map(DataTypeEnum.DECIMAL, "12.50"));
        assertEquals(DECIMAL_MIN, map(DataTypeEnum.DECIMAL, ""));
        assertEquals(DECIMAL_MIN, map(DataTypeEnum.DECIMAL, "n/a"));
    }

    @Test
    @DisplayName("#50 DATE binds a time-preserving Timestamp; DateTime.MinValue sentinel on unparseable")
    void dateTimePreserving() {
        assertEquals(Timestamp.valueOf(LocalDateTime.of(2023, 12, 29, 14, 30, 0)),
                map(DataTypeEnum.DATE, "12/29/2023 14:30:00"));
        assertEquals(DATETIME_MIN, map(DataTypeEnum.DATE, ""));
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

## `TaskExceptionMapperTest.java` — add one test (snippet)
Insert before the `buildRow(...)` helper:
```java
    @Test
    @DisplayName("#52 Non-numeric / blank tokens become int.MinValue instead of throwing")
    void shouldNotThrowOnNonNumericIndexToken() {
        Map<String, Object> row = buildRow("BLOC_J", "TABLE_K", "1|abc|3");
        TaskException result = mapper.mapToTaskException(row);

        assertArrayEquals(new int[]{1, Integer.MIN_VALUE, 3}, result.getIndexLignes());
        assertEquals(TaskExceptionTypeEnum.LINE, result.getType());
    }
```

---

## Apply checklist
- [ ] Replace `mapper/InParamSqlMapper.java`
- [ ] Replace `mapper/TaskExceptionMapper.java`
- [ ] Add `src/test/.../mapper/InParamSqlMapperTest.java`
- [ ] Add the one test to `TaskExceptionMapperTest.java`
- [ ] `mvn test -Dtest=InParamSqlMapperTest,TaskExceptionMapperTest`
