# EOS Quark — Run-Analysis Fix Batch (runs 488654 & 505244)

**Repo of record:** `14-07 engine service repo/quark-engine`
**Scope:** three code fixes (#1, #2, #4) + one flagged data/run item (#3), all traced to the
488654 (Dynamique, gabarit G_168 / template GT_6) and 505244 (Plaquette, `gabaritSource=DOCUMENT_COURANT`)
runs. This is a **new, standalone batch**, separate from the verified-list Batches 1–13 and from
`EOS_Quark_Consolidated_Changes.md`.

Working-style conventions honoured: whole-file listings for the small classes; targeted snippets for
the ~1200-line `DynamiqueTaskProcessStrategy` (as done for Batch 2); **no .NET identifiers/comments in
new code** — all .NET traceability lives in this document; inherited (earlier-batch) comments left as-is.

---

## Summary

| # | Symptom (run) | Root cause | Fix | Files |
|---|---|---|---|---|
| **1** | `ORA-01722 invalid number` on `srq_photo.id_structure = :7` (488654) | Java replicates .NET's `int.MinValue` **unset sentinel** but binds it as the literal number `-2147483648`; Oracle then applies `TO_NUMBER(id_structure)` against it → ORA-01722 on the first non-numeric column value | Bind an unset numeric/date sentinel as a **typed SQL NULL** (mirrors .NET's Oracle-parameter layer) | `mapper/InParamSqlMapper.java` (+ test) |
| **2** | thousands of `Template element [X] not found` → all dynamic tables emptied (488654) | TElements resolved against the **main gabarit** project (never even populated); specimen boxes live in the **gabarit-template** doc (`GT_6`), whose project was never parsed | Parse the gabarit-template document's project (via the existing QXPSM DOM bridge) and resolve TElements against **it** | `service/task/impl/DynamiqueTaskProcessStrategy.java` |
| **4** | `ORA-02291` FK violation in `QXP_PK_RUN.End_Run` on every successful finalize (505244) | Absent generated-document ids (`Integer.MIN_VALUE`) passed verbatim to the FK doc-id columns → no parent row | Bind an absent doc-id as **SQL NULL** (the FK columns are nullable) | `infra/dao/impl/EndRunDaoImpl.java` |
| **3** | PDF `Error #10122 … document contains only blank pages` (505244) | **Not a port defect** — the run has 0 content tasks (DID only) → empty document → Quark `/pdf` refuses. Our `/pdf` params are byte-identical to .NET. | **Flagged only** — re-run with a content-ful Plaquette (SQL/System tasks). Optional parity Q below. | — |

**#1 and #4 are the same class of defect:** the Java port copied .NET's `int.MinValue` *sentinel value*
but dropped the .NET step that converts that sentinel to **SQL NULL** before binding.

---

## Scope: this fix is universal, not id_structure- or document-type-specific

`id_structure` is merely one INT-declared bind parameter; the defect is in the **shared InParam→SQL
binding layer** (`InParamSqlMapper`), used by every run of every report type:
- Both SQL execution paths route through it — `ProcessSqlBusiness` (SQL tasks) and `DynamicQueryPortImpl`
  (Dynamique).
- InParams are loaded per-run via `Get_In_Params` for **all** document types (Plaquette / DICI / KIID /
  Annual / Dynamique / Compartiment).
- The mapper never inspects column type or document type — it binds exactly what .NET binds for the
  param's declared `DataTypeEnum`. So any run binding an INT/DECIMAL/DATE param whose value is the unset
  sentinel is covered. It surfaced in 488654 (Dynamique) but is not specific to it.

## Confirmations performed before patching (full .NET + ora.txt cross-check)

Read directly from the .NET source at `eos quark whole application code/qxp`
(`QXP.Engine.Core` / `QXP.Framework`) and the Oracle package bodies in `ora.txt`.

### Completeness of the sentinel→NULL rule — ALL typed cases verified (not just INT)
The Oracle-parameter layer (`OracleParameter.cs`) applies the same `Validation.IsSet(value) ?
value : DBNull.Value` gate for **every** type `Data_Type_Helper.InputToTypedValue` can emit:

| Produced CLR type | .NET overload | Gate | Sentinel → NULL |
|---|---|---|---|
| Int32   | `GetParameter(Int32)` `OracleParameter.cs:509-521` | `IsSet(int)` `Validation.cs:71`  | `int.MinValue` |
| Decimal | `GetParameter(decimal)` `OracleParameter.cs:523-535` | `IsSet(decimal)` `Validation.cs:122` | `decimal.MinValue` |
| DateTime| `GetParameter(DateTime)` `OracleParameter.cs:537-549` (`OracleDbType.Date`) | `IsSet(DateTime)` `Validation.cs:171` | `DateTime.MinValue` |
| String / other | generic fallback `new OracleParameter(name, value)` `OracleParameter.cs:118-121` | **none** | — (raw value bound verbatim) |

→ The Java mapper mirrors this exactly: INT/DECIMAL/DATE unset sentinel → typed SQL NULL (types
`NUMERIC`/`NUMERIC`/`DATE`); every other type → raw string (no gate), matching the .NET fallback. The
sentinels are identical (`Integer.MIN_VALUE`, `decimal.MinValue` = `-79228162514264337593543950335`,
`DateTime.MinValue` = 0001-01-01). DECIMAL uses `compareTo` to match .NET's scale-insensitive `!=`; the
DATE null uses `Types.DATE` to mirror `OracleDbType.Date`.

### ora.txt (package bodies) cross-check
- **`Get_In_Params`** (`ora.txt:9186`): the cursor selects `p.INPUT_DATA_TYPE` as a **stored column** of
  the parameter-definition table `qxp_params_type_rapport` — data-driven per parameter, never computed.
  So a param's type is a fixed DB attribute; only the *binding* is ours to fix. Cursor columns
  (`nom_parametre`, `input_data_type`, `valeur`) match what `InParamMapper` reads.
- **`End_Run`** (`ora.txt:9350`): `PROCEDURE End_Run(p_id_run, p_run_status, p_id_suivi, p_suivi_status,
  p_date_fin, p_log_trace, p_id_doc_pdf, p_id_doc_qxp, p_id_doc_doc)` — all `IN NUMBER`, **no DEFAULTs**,
  doc-ids are the last three in that order. This matches `EndRunDaoImpl.declareParameters` exactly, so the
  NULLs land on `QXP_RUN.ID_DOC_PDF/QXP/DOC` (`UPDATE` at `ora.txt:9407`). The FK that raised ORA-02291 is
  in table DDL (not in this package-body-only dump); the body itself nulls those columns in its cleanup
  block, confirming NULL is a valid value. `Insert_Document` is a FUNCTION returning a positive NUMBER id,
  consistent with `int.MinValue` = "absent".

### Original two confirmations

### (a) Why the id_structure InParam is INT — and how .NET actually binds it
- The InParam type is **DB-metadata-driven**: it is read from the `QXP_PK_RUN.Get_In_Params` cursor
  column `input_data_type` (`InParamMapper.mapFromResultSet` → `DataTypeEnum.fromCode`). It is **not**
  engine/context-set. So id_structure being INT (code 2) comes from the parameter-definition row.
- **.NET binds an INT InParam as a NUMBER, not a string.** `Data_Type_Helper.InputToTypedValue`
  (`Helper/Data_Type_Helper.cs:154-167`) → `case Data_Type.Int: return ConversionInvariante.ToInt(value)`
  (a boxed `Int32`); the value is bound via `InParams.cs:69` → `OraParameter(name, inParam.Value)`.
- **The real parity gap:** the Oracle-parameter layer converts the unset sentinel to `DBNull`:
  `OracleParameter.cs:509-521` — `GetParameter(string, Int32)` does
  `if (Validation.IsSet(value)) Value = value; else Value = DBNull.Value;`, and
  `Validation.cs:67-71` — `IsSet(int)` returns `false` for `int.MinValue`.
  Since `ToInt("_P0_…")` returns `int.MinValue`, .NET binds **SQL NULL**. Java produced the same
  sentinel but bound the literal `-2147483648` → `TO_NUMBER(id_structure) = -2147483648` → ORA-01722.
  *(The only place .NET binds `id_structure` as a string is the unrelated `Proxy_Run.Get_Compartiment_Runs`
  stored proc, where its C# parameter is declared `string`.)*
  → **The originally-queued "bind id_structure as String" fix was based on a wrong premise and is not
  used.** The correct, faithful fix is sentinel → typed SQL NULL.

### (b) Which project .NET's Evaluate_TElement sources template TElements from
- `TElement_Helper.cs:116-146` — `Evaluate_TElement(task, cell)` looks the box up in
  `task.Run.Gabarit_Template.QXPProject.Elements` (**line 121**), i.e. the **gabarit-TEMPLATE**
  `Document`, *not* `task.Run.Gabarit`. `Gabarit` and `Gabarit_Template` are separate `Document`
  fields on `Run_Base` (`Run_Base.cs:859` vs `:868`), loaded independently
  (`Run.cs:89` vs `Run.cs:152`).
- The template `Document.QXPProject` is lazily parsed from **its own** pool file via
  `Document.cs:385-414` → `QXPS_File_Manager.Get_Project` → `getXPressDOM(documentName)`
  (`QXPSM_Request_Dom.cs:42`). It is a distinct, separately-cached project.
  → Java must parse the gabarit-template document's project and resolve TElements against it. Confirmed.

### (c) (issue #4) What .NET passes to End_Run for an absent document
- `Proxy_Document.Insert_Document` returns `int.MinValue` when the document is null
  (`Proxy_Document.cs:242-245`). Those ids flow into `End_Run`'s `p_id_doc_pdf/qxp/doc`
  (`Proxy_Run.cs:274-276, 310-318`) and hit the **same** `GetParameter(Int32)` → `Validation.IsSet`
  gate, so **End_Run receives SQL NULL** for an absent id. Java bound the literal `MIN_VALUE` → ORA-02291.

---

## Fix #1 — `InParamSqlMapper`: unset sentinel → typed SQL NULL

**Path:** `src/main/java/com/socgen/sgs/api/quark/engine/mapper/InParamSqlMapper.java`
**.NET parity:** `OracleParameter.GetParameter(Int32/…)` + `Validation.IsSet` (unset → `DBNull.Value`).
**Covers both SQL paths:** the SQL-query task (`ProcessSqlBusiness`) and the Dynamique query
(`DynamicQueryPortImpl`) both bind through this mapper.

**Mechanism:** a typed SQL NULL is emitted as a `SqlParameterValue(java.sql.Types.…, null)` map value.
`NamedParameterJdbcTemplate` (via `StatementCreatorUtils.setParameterValue`) unwraps `SqlParameterValue`
and binds `setNull(idx, <declaredType>)` — the exact analogue of .NET's `DBNull` + `OracleDbType.Int32`.
This avoids Oracle "unable to determine type" issues that a bare Java `null` could raise.

**Whole file (post-change):**

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
 *   <li>DATE     → {@link Timestamp} (time-preserving DateTime); unset/unparseable → typed SQL NULL</li>
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
                Timestamp ts = toSqlTimestamp(value);
                return DATETIME_MIN_VALUE.equals(ts) ? new SqlParameterValue(Types.DATE, null) : ts;
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

> **Correctness is settled; one symptom-specific note.** The change is proven **byte-for-byte .NET
> parity** — it emits the identical typed NULL the .NET Oracle-parameter layer emits for an unset
> sentinel (verified for INT/DECIMAL/DATE above), so it is not a bet on Oracle's NULL-comparison
> behaviour: whatever the live DB does with .NET's bind, it does identically with ours. The only
> value-dependent point is whether it *clears the specific 488654 ORA-01722*: that holds when bind `:7`'s
> value is the unset sentinel (empty / non-numeric → NULL, as .NET does). If `:7` were instead a *real
> numeric* structure id, both engines bind that number and both apply `TO_NUMBER(id_structure)` — a
> data/gabarit issue affecting .NET equally, not a port defect. The 488654 log's in-param dump would
> confirm `:7`'s value/type, but it changes nothing about the fix's correctness.

---

## Fix #2 — `DynamiqueTaskProcessStrategy`: resolve TElements against the gabarit-template project

**Path:** `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/DynamiqueTaskProcessStrategy.java`
**.NET parity:** `TElement_Helper.Evaluate_TElement` → `task.Run.Gabarit_Template.QXPProject.Elements`.

**Why the strategy (not `LoadTemplatesBusiness`):** the template document is uploaded to the pool in
`TaskDynamique.prepare()` (Prepare phase). `getXPressDOM` needs the doc already pooled, so the project
is built lazily at the start of the Process phase — mirroring .NET's lazy `Document.QXPProject`. The
build uses the existing `GetDocumentProjectBusiness` bridge (already injected by
`CompartimentTaskProcessStrategy`; injecting a business into a strategy is an established pattern here,
e.g. `SqlTaskProcessStrategy` → `ProcessSqlBusiness`). The main-gabarit project was the *only* other use
of a gabarit project in the whole strategy and was never even populated, so both lookup sites move.

**Change 2.1 — imports** (after the `TElementHelper` import):

```java
import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;

import com.socgen.sgs.api.quark.engine.business.GetDocumentProjectBusiness;
```

**Change 2.2 — new injected field** (after `dynamicQueryPort`; Lombok `@RequiredArgsConstructor` wires it):

```java
    private final DynamicQueryPort dynamicQueryPort;

    private final GetDocumentProjectBusiness getDocumentProjectBusiness;
```

**Change 2.3 — build the template project once, at the top of `process(...)`** (right after the
existing gabarit null-check `}`):

```java
            return;

        }

        // The specimen boxes referenced by every report cell live in the gabarit-template
        // document, not the source gabarit. Parse that document's structure once so the

        // template elements can be resolved during Check_Report.

        ensureTemplateProject(task);

        // ================================================================

        // Stage 1: Get_Report — Execute SQL and build DReport
```

**Change 2.4 — new private method** (inserted between `checkReport(...)` and `evaluateTElement(...)`):

```java
    /**

     * Build and cache the gabarit-template document's project once per run. The template document

     * is uploaded to the pool during the Prepare phase; its structure is fetched and parsed here so

     * the report cells can resolve their specimen boxes against it.

     */

    private void ensureTemplateProject(TaskDynamique task) {

        DocumentDomain template = task.getRun().getGabaritTemplate();

        if (template == null) {

            return;

        }

        if (template.getQxpProject() == QxpProject.EMPTY) {

            template.setQxpProject(getDocumentProjectBusiness.getProject(template.getFilePoolPath()));

        }

    }
```

**Change 2.5 — `checkReport(...)` analyses the template project** (was `getGabarit()`):

```java
        boolean activeOverflowTemplate = !task.getOverflowBoxes().isEmpty();

        QxpProject qxpProject = task.getRun().getGabaritTemplate().getQxpProject();

        qxpProject.analyse(task, true);
```

**Change 2.6 — `evaluateTElement(...)` reads the template project** (was `getGabarit()`):

```java
        QxpProject qxpProject = task.getRun().getGabaritTemplate().getQxpProject();

        Map<String, TElement> elements = qxpProject.getElements();
```

*(No change to `LoadTemplatesBusiness` — it already loads the template document, sets its
`filePoolPath`, and re-evaluates Mode_Degrade against it.)*

---

## Fix #4 — `EndRunDaoImpl.endRun`: absent doc-id → SQL NULL

**Path:** `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/EndRunDaoImpl.java`
**.NET parity:** absent `Insert_Document` id (`int.MinValue`) → `DBNull` at the Oracle-parameter layer.
The `p_id_doc_*` parameters are already declared `Types.NUMERIC`, so `SimpleJdbcCall` binds a proper
typed NULL. Single choke point — covers `idDoc` (always absent: Word is never generated) and
`idPdf`/`idQxp` when their render failed.

**Changed binding block in `endRun(...)`:**

```java
        params.put("p_date_fin", dateFin != null ? Timestamp.valueOf(dateFin) : null);
        params.put("p_log_trace", logTrace);
        // The document-id columns carry a foreign key. When a document was not generated its id is
        // the MIN_VALUE "absent" placeholder; binding it verbatim has no parent row and raises
        // ORA-02291. Bind SQL NULL for an absent id (the columns are nullable). Declared NUMERIC.
        params.put("p_id_doc_pdf", nullIfAbsent(idDocPdf));
        params.put("p_id_doc_qxp", nullIfAbsent(idDocQxp));
        params.put("p_id_doc_doc", nullIfAbsent(idDocDoc));

        jdbcCall.execute(params);
        log.info("End_Run executed for run [{}]", idRun);
    }
```

**New private helper** (added after `updateStatusRun(...)`):

```java
    /** An absent generated-document id ({@link Integer#MIN_VALUE}) is bound as SQL NULL. */
    private static Integer nullIfAbsent(int idDocument) {
        return idDocument == Integer.MIN_VALUE ? null : idDocument;
    }
```

---

## Issue #3 — PDF blank-pages (505244): FLAGGED, no code change

`Error #10122 … document contains only blank pages` is a **data/run-selection** condition: run 505244
loaded **0 content tasks** (DID only), so the document is empty and QXPS `/pdf` refuses to render. Our
`/pdf` request (path + 6 downsample/compression params) is byte-identical to .NET `QXPS_Message_PDF`, so
this is not a port defect.

- **Action:** re-run with a **content-ful Plaquette** (a run that carries SQL/System tasks) to validate
  PDF render + document insert end-to-end.
- **Optional parity question (your call, not changed here):** in .NET a swallowed render failure is not
  recorded as a `RunError` / run-fail either; today Java logs `ERROR` and continues. If you want a blank
  PDF to mark the run failed, that's a deliberate deviation to decide separately.

---

## Test impact

- **`InParamSqlMapperTest`** — updated (four sentinel assertions changed from "returns MIN_VALUE
  placeholder" to "returns a typed SQL NULL"). Whole file below. Non-sentinel cases unchanged.
- **No other tests** construct `DynamiqueTaskProcessStrategy` or `EndRunDaoImpl` (both Spring-wired), so
  the new constructor arg / helper are safe. `ProcessRunServiceImplTest` mocks its collaborators — no
  change needed.

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
    @DisplayName("#50 DATE binds a time-preserving Timestamp; unparseable → typed SQL NULL")
    void dateTimePreserving() {
        assertEquals(Timestamp.valueOf(LocalDateTime.of(2023, 12, 29, 14, 30, 0)),
                map(DataTypeEnum.DATE, "12/29/2023 14:30:00"));
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

## Apply & verify

1. Apply the four edits above (all four are already applied in `14-07 engine service repo/quark-engine`).
2. `mvn clean install` (no Maven in this sandbox — please run locally). Expected: green; the updated
   `InParamSqlMapperTest` compiles against `spring-jdbc` (`SqlParameterValue`, already on the classpath).
3. Re-run **488654 (Dynamique)** → expect: no ORA-01722; dynamic tables populate (no mass
   "Template element not found").
4. Re-run a **content-ful Plaquette** → expect: PDF renders, document inserts, and `End_Run` finalizes
   with no ORA-02291.

## Files changed
- `src/main/java/.../mapper/InParamSqlMapper.java` (#1)
- `src/test/java/.../mapper/InParamSqlMapperTest.java` (#1, test)
- `src/main/java/.../service/task/impl/DynamiqueTaskProcessStrategy.java` (#2)
- `src/main/java/.../infra/dao/impl/EndRunDaoImpl.java` (#4)
