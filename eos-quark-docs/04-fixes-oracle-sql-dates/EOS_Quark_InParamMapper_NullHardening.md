# EOS Quark — `InParamMapper` NULL-hardening (`input_data_type` NUMBER(2,0)) — copy-paste ready

**Repo:** `14-07 engine service repo/quark-engine`.
**Trigger:** `QXP_PK_RUN.Get_In_Params` returns `INPUT_DATA_TYPE` as `NUMBER(2,0)` (integer −99..99).
`ResultSet.getInt()` reads that losslessly and every `DataTypeEnum` code (0–7, 99) fits — so the type read
was already correct. The gap was **null-handling**: `getInt()` silently returns `0` for SQL NULL and
`getString()` returns Java `null`, whereas the legacy engine coerces both to defaults.

## .NET behavior (verified — the target to match)
The legacy loader reads through a null-tolerant data reader, never throwing:

| Column | Legacy read | NULL → |
|---|---|---|
| `input_data_type` | `(int) reader["input_data_type"]` → `QXP_Value_Helper.ToInt32` | **`int.MinValue`** → `(Data_Type)int.MinValue` (undefined enum) → `InputToTypedValue` `default` → **raw-string bind** |
| `nom_parametre`    | `reader["nom_parametre"]` → `QXP_Value_Helper.ToString` | **`""`** (empty string) |
| `valeur`           | `reader["valeur"]` → `QXP_Value_Helper.ToString` | **`""`** (empty string) |

.NET file refs: `Proxy_Param.cs:104-110` (loop), `OracleValue.cs:372`→`QXP_Value_Helper.ToInt32:169-179`
(`IsNull → Int32.MinValue`), `Validation.cs:42` (`IsNull` = null or DBNull), `InParam.cs:41`
(`(Data_Type)type` unchecked cast), `Data_Type_Helper.cs:154-165` (`default: return value`),
`QXP_Value_Helper.ToString:82` (`IsNull → String.Empty`).

## Java gap (before) vs. fix (after)
| Column NULL | Before (Java) | After (Java, matches .NET) |
|---|---|---|
| `input_data_type` | `getInt`→`0`→`UNSPECIFIED` (same *outcome*, but implicit) | `wasNull()`→`Integer.MIN_VALUE`→`UNSPECIFIED` (explicit) |
| `nom_parametre`   | `null` (used as a map key!) | `""` |
| `valeur`          | `null` (a TEXT param would bind NULL; .NET binds `""`) | `""` |

Outcome for a NULL type is unchanged (raw-string bind, since `UNSPECIFIED` is not INT/DECIMAL/DATE); the
real corrections are the empty-string normalization of name/value. Unknown non-null codes (e.g. `8`) already
resolve to `UNSPECIFIED` via `DataTypeEnum.fromCode`, so out-of-enum values in `NUMBER(2,0)` are safe too.

---

## `InParamMapper.java`  *(paste whole file)*
Path: `src/main/java/com/socgen/sgs/api/quark/engine/mapper/InParamMapper.java`

```java
package com.socgen.sgs.api.quark.engine.mapper;
import com.socgen.sgs.api.quark.engine.domain.InParam;
import org.springframework.stereotype.Component;
import java.sql.ResultSet;
import java.sql.SQLException;
@Component
public class InParamMapper {
    public InParam mapFromResultSet(ResultSet rs) throws SQLException {
        // Null-tolerant read matching the legacy engine's data reader: a NULL type code resolves to an
        // unset sentinel (→ DataTypeEnum.UNSPECIFIED → the param binds as its raw string), and a NULL
        // name or value normalizes to an empty string rather than a Java null.
        int typeCode = rs.getInt("input_data_type");
        if (rs.wasNull()) {
            typeCode = Integer.MIN_VALUE;
        }
        return new InParam(
                emptyIfNull(rs.getString("nom_parametre")),
                typeCode,
                emptyIfNull(rs.getString("valeur"))
        );
    }

    private static String emptyIfNull(String value) {
        return value != null ? value : "";
    }
}
```

## `InParamMapperTest.java`  *(paste whole file)*
Path: `src/test/java/com/socgen/sgs/api/quark/engine/mapper/InParamMapperTest.java`

```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.sql.ResultSet;
import java.sql.SQLException;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("InParamMapper Tests")
class InParamMapperTest {

    private InParamMapper mapper;

    @Mock
    private ResultSet resultSet;

    @BeforeEach
    void setUp() {
        mapper = new InParamMapper();
    }

    @Test
    @DisplayName("Should map ResultSet to InParam")
    void shouldMapResultSetToInParam() throws SQLException {
        when(resultSet.getString("nom_parametre")).thenReturn("testParam");
        when(resultSet.getInt("input_data_type")).thenReturn(1);
        when(resultSet.getString("valeur")).thenReturn("testValue");

        InParam result = mapper.mapFromResultSet(resultSet);

        assertNotNull(result);
        assertEquals("testParam", result.getName());
        assertEquals(DataTypeEnum.TEXT, result.getType());
        assertEquals("testValue", result.getStringValue());
    }

    @Test
    @DisplayName("Should map integer type correctly")
    void shouldMapIntegerTypeCorrectly() throws SQLException {
        when(resultSet.getString("nom_parametre")).thenReturn("intParam");
        when(resultSet.getInt("input_data_type")).thenReturn(2);
        when(resultSet.getString("valeur")).thenReturn("100");

        InParam result = mapper.mapFromResultSet(resultSet);

        assertEquals(DataTypeEnum.INT, result.getType());
        assertEquals("100", result.getStringValue());
    }

    @Test
    @DisplayName("Null name/value → empty string; NULL type code → UNSPECIFIED (raw-string bind)")
    void shouldHandleNullValues() throws SQLException {
        when(resultSet.getString("nom_parametre")).thenReturn(null);
        when(resultSet.getInt("input_data_type")).thenReturn(0);
        when(resultSet.wasNull()).thenReturn(true);   // input_data_type was SQL NULL
        when(resultSet.getString("valeur")).thenReturn(null);

        InParam result = mapper.mapFromResultSet(resultSet);

        assertEquals("", result.getName());
        assertEquals(DataTypeEnum.UNSPECIFIED, result.getType());
        assertEquals("", result.getStringValue());
    }

    @Test
    @DisplayName("Unknown (non-null) type code → UNSPECIFIED; fits NUMBER(2,0) range")
    void shouldMapUnknownTypeCodeToUnspecified() throws SQLException {
        when(resultSet.getString("nom_parametre")).thenReturn("p");
        when(resultSet.getInt("input_data_type")).thenReturn(8); // no such DataTypeEnum
        when(resultSet.getString("valeur")).thenReturn("x");

        InParam result = mapper.mapFromResultSet(resultSet);

        assertEquals(DataTypeEnum.UNSPECIFIED, result.getType());
        assertEquals("x", result.getStringValue());
    }
}
```

## Notes
- Both files are already applied in the 14-07 working copy; the listings above match it exactly.
- `NUMBER(2,0)` needs no special accessor — `getInt` is exactly right; this change is purely about NULL
  robustness and empty-string parity.
- The two existing non-null tests don't stub `wasNull()`; Mockito returns `false` by default, so they pass
  unchanged.
