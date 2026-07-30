# EOS Quark Engine — Batch 2 Changes
**Theme: gabarit_template load + Dynamique, and the `[Flags]` enum fixes (`StoreDataType`, `AbsoluteRepeatType`)**

_Generated directly from the working-copy files (no hand transcription). Whole-file copy-paste, except `DynamiqueTaskProcessStrategy.java` (1243 lines) which is given as two precise before→after snippets._

## Findings fixed in this batch
| # | Sev | Issue | .NET reference |
|---|---|---|---|
| 6 | CRITICAL | `Gabarit_Template` document was never loaded; dynamic tasks cloned from the wrong source | Run.cs:152 `Get_Gabarit_Template`; :157 `Load_Templates`; Document.cs:118 `GetPoolPath` |
| 22 | HIGH | `TaskDynamique.prepare` uploaded the run's *source* gabarit instead of the template | Task_Dynamique.cs:60 `Addfile(Run.Gabarit_Template.FilePoolPath, …)` |
| 1 | CRITICAL | Combined store type `0x03` (SQL\|DOCUMENT) collapsed to NONE → collected/persisted **nothing** | Store_Data_Type.cs:14 `[Flags]`; Run_Base.cs:677/699 two independent bit tests; Proxy_Run.cs:151-153 |
| 28 | HIGH | `AbsoluteRepeatType` modeled as fixed enum → combined values (3/5/6/7) threw on template load | Absolute_Repeat_Type.cs:10-32 `[Flags]`; Proxy_Template.cs:185-188; analysis lines 616/624/635/647 |

## Design decision (important)
Both `[Flags]` enums (`StoreDataType`, `AbsoluteRepeatType`) are now carried as the **raw `int`** value, not as the enum. A plain Java enum cannot represent a combined value such as `0x03`, so any `fromCode`/`fromValue` that maps an int to a single constant must either throw (AbsoluteRepeat) or silently collapse to `NONE` (StoreData) — both are the bugs we are fixing. .NET keeps these as `[Flags]` enums whose underlying value holds the raw bits (e.g. `ToEnum<Store_Data_Type>(3)`), so the faithful single-source-of-truth port is a raw int tested with `(code & flag) == flag`. The enums are kept as the **bit-constant holders** with new static helpers (`StoreDataType.hasFlag(int,flag)`, `AbsoluteRepeatType.hasFirstPage/hasOtherPage/hasLastPage(int)`).

## API changes (all callers updated)
- `RunProperties`: field `StoreDataType storeDataType` → `int storeDataTypeCode`. Getter/setter become `getStoreDataTypeCode()/setStoreDataTypeCode()`.
- `Template`: field `AbsoluteRepeatType absoluteRepeat` → `int absoluteRepeat` (0 = Default). Getter/setter become `int`.
- `AbsoluteRepeatType.fromValue(int)` (threw on combined values) **removed** — no remaining callers.
- New `Run.gabaritTemplate` field (+ Lombok getter/setter).
- Callers updated: `RunPropertiesMapper`, `CheckServiceImpl`, `EndRunBusiness`, `ProcessSqlBusiness`, `DynamiqueTaskProcessStrategy` (store + absolute-repeat), `TemplateMapper`, `LoadTemplatesBusiness`, `TaskDynamique`. Tests updated: `RunPropertiesTest`, `RunPropertiesMapperTest` (+ new combined-value assertions), new `AbsoluteRepeatTypeTest`.

## Scoped out of Batch 2 (deferred, by design)
- **M25** — .NET raises a *Bloquante* error when a run has dynamic tasks but no `id_gabarit_template`, and only loads templates when at least one dynamic task is TODO (`Run.cs:144` `if(__load_templates)`). Batch 2 loads the template document whenever `id_gabarit_template` is set; the dynamic-task gating + Bloquante-on-missing is its own later finding. `TaskDynamique.prepare` now throws a clear `IllegalStateException` if the template is missing, so there is no silent NPE in the meantime.
- **C6/C7** (PL/SQL associative-array DAO binding for store_data persistence) is Batch 4 — this batch only fixes which data is *selected* for storage, not the DAO bind.

---

## `service/task/impl/DynamiqueTaskProcessStrategy.java` — CHANGED (2 snippets; 1243-line file)

### Snippet 1 — store-data flag (around line 249)
**Before:**
```java
        // Store data flag

        boolean storeData = task.isStoreData()
                && (task.getRun().getRunProperties().getStoreDataType() == com.socgen.sgs.api.quark.engine.domain.StoreDataType.SQL

                || task.getRun().getRunProperties().getStoreDataType() == com.socgen.sgs.api.quark.engine.domain.StoreDataType.ALL);
```
**After:**
```java
        // Store data flag — bitwise SQL test so combined values (0x03 = SQL|DOCUMENT) and ALL (0xFF)
        // are both honoured. (.NET Run_Base.cs:677 (Store_Type & SQL) == SQL.) Finding #1.

        boolean storeData = task.isStoreData()
                && com.socgen.sgs.api.quark.engine.domain.StoreDataType.hasFlag(
                        task.getRun().getRunProperties().getStoreDataTypeCode(),
                        com.socgen.sgs.api.quark.engine.domain.StoreDataType.SQL);
```

### Snippet 2 — absolute-repeat classification (around line 700)
**Before:**
```java
            if (cell.getTemplate().getAbsoluteRepeat().hasOtherPage()) {

                prp.getRepeatedCells().add(cell);

                if (!cell.getTemplate().getAbsoluteRepeat().hasFirstPage()
                        && cell.getTemplate().getAbsoluteRepeat() != AbsoluteRepeatType.DEFAULT) {

                    cell.downgradeGeneration();

                }

            }

            if (cell.getTemplate().getAbsoluteRepeat().hasLastPage()) {

                prp.getLastCells().add(cell);

            }

        }

        // Remove absolute cells not on first page or default

        section.getCells().removeIf(cell ->

                !(cell.getTemplate().getAbsoluteRepeat().hasFirstPage()

                        || cell.getTemplate().getAbsoluteRepeat() == AbsoluteRepeatType.DEFAULT));
```
**After:**
```java
            int absRepeat = cell.getTemplate().getAbsoluteRepeat();

            if (AbsoluteRepeatType.hasOtherPage(absRepeat)) {

                prp.getRepeatedCells().add(cell);

                if (!AbsoluteRepeatType.hasFirstPage(absRepeat)
                        && absRepeat != 0) {

                    cell.downgradeGeneration();

                }

            }

            if (AbsoluteRepeatType.hasLastPage(absRepeat)) {

                prp.getLastCells().add(cell);

            }

        }

        // Remove absolute cells not on first page or default (raw 0 == .NET Absolute_Repeat_Type.Default)

        section.getCells().removeIf(cell ->

                !(AbsoluteRepeatType.hasFirstPage(cell.getTemplate().getAbsoluteRepeat())

                        || cell.getTemplate().getAbsoluteRepeat() == 0));
```
> The existing `import ...enums.AbsoluteRepeatType;` (line 47) stays — it is now used for the static helpers.

---

## `domain/StoreDataType.java`
```java
package com.socgen.sgs.api.quark.engine.domain;

import lombok.Getter;

/**
 * Defines the type of data storage for a run.
 * Uses bitwise flags matching .NET [Flags] Store_Data_Type enum.
 */
@Getter
public enum StoreDataType {
    NONE(0x00),
    SQL(0x01),
    DOCUMENT(0x02),
    ALL(0xFF);

    private final int code;

    StoreDataType(int code) {
        this.code = code;
    }

    /**
     * Check if this store type includes the given flag.
     * Mirrors .NET: (storeType & flag) == flag
     */
    public boolean hasFlag(StoreDataType flag) {
        return (this.code & flag.code) == flag.code;
    }

    /**
     * Bit test against a raw store-type code. This is the .NET-faithful check
     * ({@code (Store_Type & flag) == flag}, Run_Base.cs:677/699) and — unlike a single-value
     * enum — correctly handles combined values such as 0x03 (SQL|DOCUMENT). The raw int code
     * must be carried through (RunProperties.storeDataTypeCode) rather than collapsed to an enum,
     * because a plain Java enum cannot represent a combined flag value.
     *
     * @param code the raw store_data_type value from the DB
     * @param flag the flag to test for
     * @return true if all bits of {@code flag} are set in {@code code}
     */
    public static boolean hasFlag(int code, StoreDataType flag) {
        return (code & flag.code) == flag.code;
    }

    public static StoreDataType fromCode(int code) {
        for (StoreDataType type : values()) {
            if (type.code == code) {
                return type;
            }
        }
        return NONE;
    }
}
```

---

## `enums/AbsoluteRepeatType.java`
```java
package com.socgen.sgs.api.quark.engine.enums;

/**
 * Defines how an absolute bloc is repeated across pages.
 * Uses bit flags for combinable values (matching .NET [Flags] Absolute_Repeat_Type).
 *
 * Cross-reference: QXP.Engine.Core.Absolute_Repeat_Type
 */
public enum AbsoluteRepeatType {

    /** By default, the absolute bloc appears only on the first page. */
    DEFAULT(0x00),

    /** The absolute bloc appears on the first page. */
    FIRST_PAGE(0x01),

    /** The absolute bloc appears on other pages (but not the first). */
    OTHER_PAGE(0x02),

    /** The absolute bloc appears on the last page. */
    LAST_PAGE(0x04),

    /** The absolute bloc appears on all pages. */
    ALL(0xFF);

    private final int value;

    AbsoluteRepeatType(int value) {
        this.value = value;
    }

    public int getValue() {
        return value;
    }

    /**
     * Check if this repeat type includes FIRST_PAGE behavior.
     * Matches .NET: (type & Absolute_Repeat_Type.First_Page) == Absolute_Repeat_Type.First_Page
     */
    public boolean hasFirstPage() {
        return (this.value & FIRST_PAGE.value) == FIRST_PAGE.value;
    }

    /**
     * Check if this repeat type includes OTHER_PAGE behavior.
     * Matches .NET: (type & Absolute_Repeat_Type.Other_Page) == Absolute_Repeat_Type.Other_Page
     */
    public boolean hasOtherPage() {
        return (this.value & OTHER_PAGE.value) == OTHER_PAGE.value;
    }

    /**
     * Check if this repeat type includes LAST_PAGE behavior.
     * Matches .NET: (type & Absolute_Repeat_Type.Last_Page) == Absolute_Repeat_Type.Last_Page
     */
    public boolean hasLastPage() {
        return (this.value & LAST_PAGE.value) == LAST_PAGE.value;
    }

    /**
     * Bit test against a raw absolute-repeat code, the .NET-faithful check
     * ({@code (Absolute_Repeat & First_Page) == First_Page}). Unlike a single-value enum, this
     * correctly handles combined values (e.g. 0x03 = First_Page|Other_Page, 0x05, 0x06, 0xFF).
     * The raw int must be carried (Template.absoluteRepeat is an int) because a plain Java enum
     * cannot represent a combined flag value — that is why {@code fromValue} was removed.
     */
    public static boolean hasFirstPage(int code) {
        return (code & FIRST_PAGE.value) == FIRST_PAGE.value;
    }

    public static boolean hasOtherPage(int code) {
        return (code & OTHER_PAGE.value) == OTHER_PAGE.value;
    }

    public static boolean hasLastPage(int code) {
        return (code & LAST_PAGE.value) == LAST_PAGE.value;
    }
}
```

---

## `domain/dynamic/template/Template.java`
```java
package com.socgen.sgs.api.quark.engine.domain.dynamic.template;

import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;

/**
 * Represents a layout template that maps a named element (box or group of boxes)
 * from a QuarkXPress gabarit to a position and sizing definition in the final document.
 * Supports both relative and absolute positioning, with configurable page-break,
 * column-break and multi-page repetition behaviour for absolute blocs.
 */
@Getter
@Setter
public class Template {


    /** Shared default template instance. */
    public static final Template DEFAULT = new Template();

    /** Logical name of the template (defaults to "Default"). */
    private String name = "Default";

    /**
     * When {@code true} the template is positioned absolutely on the page;
     * when {@code false} (default) it flows relatively with the content.
     */
    private boolean absolute = false;

    /**
     * Defines how this absolute bloc is repeated across pages, as a raw [Flags] bit-field
     * (.NET Absolute_Repeat_Type: Default=0x00, First_Page=0x01, Other_Page=0x02, Last_Page=0x04,
     * All=0xFF). Stored as an int — not the enum — so combined values (e.g. 0x03) are preserved.
     * Test the bits via {@code AbsoluteRepeatType.hasFirstPage/hasOtherPage/hasLastPage(int)}.
     * Ignored when {@link #absolute} is {@code false}.
     */
    private int absoluteRepeat = 0;

    /**
     * When {@code true} this template is rendered only on page breaks.
     */
    private boolean pageBreak = false;

    /**
     * When {@code true} this template is rendered only on column breaks.
     */
    private boolean columnBreak = false;

    /**
     * Name of the element (box or group of boxes) associated with this template
     * in the gabarit template for the normal (non-overflow) case.
     */
    private String srcName = null;

    /**
     * Name of the element (box or group of boxes) associated with this template
     * in the gabarit template when the content overflows.
     * If not set, falls back to {@link #srcName}.
     */
    private String srcNameOverflow = null;

    /** Left position of the template in the final document. */
    private BigDecimal left = BigDecimal.ZERO;

    /** Top position of the template in the final document. */
    private BigDecimal top = BigDecimal.ZERO;

    /** Final width of the template. */
    private BigDecimal width = BigDecimal.ZERO;

    /** Final height of the template. */
    private BigDecimal height = BigDecimal.ZERO;

    /** Final height of the template expressed as a percentage (default 100 %). */
    private BigDecimal heightPercent = BigDecimal.valueOf(100);

    /** Creates a new Template instance with all default values. */
    public Template() {
    }

    /**
     * Returns the overflow source name. If it has not been explicitly set,
     * falls back to the standard {@link #srcName}.
     */
    public String getSrcNameOverflow() {
        if (srcNameOverflow == null || srcNameOverflow.isBlank()) {
            return srcName;
        }
        return srcNameOverflow;
    }
}
```

---

## `mapper/TemplateMapper.java`
```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.util.Map;

@Component
public class TemplateMapper {

    public Template mapToTemplate(Map<String, Object> row) {
        Template template = new Template();

        template.setName(getString(row, "NOM"));
        template.setSrcName(getString(row, "SRC_NOM"));
        template.setSrcNameOverflow(getString(row, "SRC_NOM_OVERFLOW"));
        template.setAbsolute(getBoolean(row, "ABSOLUTE"));
        template.setPageBreak(getBoolean(row, "PAGE_BREAK"));
        template.setColumnBreak(getBoolean(row, "COLUMN_BREAK"));

        BigDecimal left = getBigDecimal(row, "LEFT");
        if (left != null) template.setLeft(left);

        BigDecimal top = getBigDecimal(row, "TOP");
        if (top != null) template.setTop(top);

        BigDecimal width = getBigDecimal(row, "WIDTH");
        if (width != null) template.setWidth(width);

        BigDecimal height = getBigDecimal(row, "HEIGHT");
        if (height != null) template.setHeight(height);

        // Store the raw [Flags] value directly (parity: .NET Proxy_Template.cs:185-188 casts the int
        // to the [Flags] enum without validating bit combinations). Never throws on combined values.
        Integer absoluteRepeatVal = getInteger(row, "ABSOLUTE_REPEAT");
        if (absoluteRepeatVal != null) {
            template.setAbsoluteRepeat(absoluteRepeatVal);
        }

        return template;
    }

    private String getString(Map<String, Object> row, String key) {
        Object val = row.get(key);
        return val != null ? val.toString() : null;
    }

    private boolean getBoolean(Map<String, Object> row, String key) {
        Object val = row.get(key);
        if (val instanceof Number) return ((Number) val).intValue() != 0;
        if (val instanceof Boolean) return (Boolean) val;
        return false;
    }

    private BigDecimal getBigDecimal(Map<String, Object> row, String key) {
        Object val = row.get(key);
        if (val instanceof BigDecimal) return (BigDecimal) val;
        if (val instanceof Number) return BigDecimal.valueOf(((Number) val).doubleValue());
        return null;
    }

    private Integer getInteger(Map<String, Object> row, String key) {
        Object val = row.get(key);
        if (val instanceof Number) return ((Number) val).intValue();
        return null;
    }
}
```

---

## `domain/RunProperties.java`
```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.enums.GabaritSourceEnum;
import com.socgen.sgs.api.quark.engine.enums.TypeRapportEnum;
import lombok.Getter;
import lombok.Setter;
import lombok.NoArgsConstructor;
import java.time.LocalDate;

/**
 * Represents the properties of a Run object.
 * This class encapsulates all the configuration and metadata for a run.
 */
@Getter
@Setter
@NoArgsConstructor
public class RunProperties {
/*sup bro - by ananymous */
    // Constants for pagination
    public static final int PAGINATION_SIMPLE = 1;
    public static final int PAGINATION_DOUBLE = 2;

    // Run identification
    private TypeRapportEnum typeRapport = TypeRapportEnum.UNKNOWN;
    private String idFndCode;
    private String idUnitCode;
    private int idSuivi;

    // Company and language
    private LocalDate dateEcheance;
    private int idLangue;
    private String societe;
    private String codeLangue;

    // Template and document settings
    private GabaritSourceEnum gabaritSource = GabaritSourceEnum.DOCUMENT_COURANT;
    private int idSuiviGabaritSource = Integer.MIN_VALUE;
    private int idGabarit = Integer.MIN_VALUE;
    private int idGabaritTemplate = Integer.MIN_VALUE;

    // Run configuration
    private boolean integrerN1 = true;
    private TaskCompartimentMode compartimentMode = TaskCompartimentMode.UNKNOWN;
    private String runType;
    private boolean generateToWord = false;

    // Mode degrade flag (set when gabarit exceeds size limit)
    private boolean modeDegrade = false;

    // Generated files tracking
    private int idLastPdf = Integer.MIN_VALUE;
    private int idLastQxp = Integer.MIN_VALUE;
    private int idLastDoc = Integer.MIN_VALUE;

    // Pagination settings
    private int nbPageBySpread = PAGINATION_SIMPLE;

    // Storage type — raw [Flags] code from store_data_type (0x00 NONE, 0x01 SQL, 0x02 DOCUMENT,
    // 0x03 SQL|DOCUMENT, 0xFF ALL). Stored as an int (not the StoreDataType enum) so combined
    // values survive; test bits via StoreDataType.hasFlag(code, flag). Parity: .NET Run_Properties
    // .Store_Type holds the raw [Flags] value (Proxy_Run.cs:151-153). Finding #1.
    private int storeDataTypeCode = 0;

    // Run ID for path generation
    private Integer runId;

    /**
     * Get the pool path for a given file name.
     * Returns a relative path in the format: R_runId/fileName
     *
     * @param fileName the file name
     * @return the pool path
     */
    public String getPoolPath(String fileName) {
        if (this.runId == null || fileName == null) {
            return fileName;
        }
        return String.format("R_%d/%s", this.runId, fileName);
    }

    /**
     * Get the absolute pool path for a given file name.
     * Returns an absolute path in the format: documentPoolBasePath/R_runId/fileName
     *
     * @param fileName the file name
     * @param documentPoolBasePath the base path for document pool (e.g., D:\Documents)
     * @return the absolute pool path
     */
    public String getPoolPathAbsolute(String fileName, String documentPoolBasePath) {
        if (this.runId == null || fileName == null || documentPoolBasePath == null) {
            return fileName;
        }
        // The Quark host is Windows: the SaveAs absolute path must use all-backslash separators,
        // matching .NET QXPS_File_Manager.GetPoolPathAbsolute/SetPoolPath which do .Replace("/","\\").
        // Strip any trailing separator on the base, then normalize every separator to '\'.
        String base = documentPoolBasePath.replaceAll("[/\\\\]+$", "");
        String raw = base + "/R_" + this.runId + "/" + fileName;
        return raw.replace("/", "\\");
    }
}
```

---

## `mapper/RunPropertiesMapper.java`
```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.TaskCompartimentMode;
import com.socgen.sgs.api.quark.engine.enums.GabaritSourceEnum;
import com.socgen.sgs.api.quark.engine.enums.TypeRapportEnum;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * Mapper class for converting database ResultSet or column maps to {@link RunProperties}.
 * This mapper can be reused for DTO conversions and other transformations.
 */
@Component
@Slf4j
public class RunPropertiesMapper {

    /**
     * Maps a ResultSet row to a RunProperties domain object.
     * Used by returningResultSet RowMapper in SimpleJdbcCall.
     *
     * @param rs the ResultSet positioned at the current row
     * @return a populated RunProperties object
     * @throws SQLException if a database access error occurs
     */
    public RunProperties mapFromResultSet(ResultSet rs) throws SQLException {
        RunProperties props = new RunProperties();
        int intVal;

        intVal = rs.getInt("id_type_rapport");
        props.setTypeRapport(rs.wasNull() ? TypeRapportEnum.UNKNOWN : TypeRapportEnum.fromCode(intVal));

        props.setIdFndCode(rs.getString("id_fnd_code"));
        props.setIdUnitCode(rs.getString("id_unit_code"));

        java.sql.Date dateEcheance = rs.getDate("date_echeance");
        if (dateEcheance != null) {
            props.setDateEcheance(dateEcheance.toLocalDate());
        }

        props.setIdSuivi(rs.getInt("id_suivi"));
        props.setIdLangue(rs.getInt("id_langue"));
        props.setSociete(rs.getString("societe"));
        props.setCodeLangue(rs.getString("code_langue"));

        intVal = rs.getInt("gabarit_source");
        props.setGabaritSource(rs.wasNull() ? GabaritSourceEnum.UNKNOWN : GabaritSourceEnum.fromCode(intVal));

        intVal = rs.getInt("id_suivi_gabarit_source");
        props.setIdSuiviGabaritSource(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        props.setIntegrerN1(rs.getInt("integrer_n1") != 0);

        intVal = rs.getInt("mode_compart");
        props.setCompartimentMode(rs.wasNull() ? TaskCompartimentMode.UNKNOWN
                : TaskCompartimentMode.fromCode(intVal));

        props.setRunType(rs.getString("runtype"));
        props.setGenerateToWord(rs.getInt("generate_to_word") != 0);

        intVal = rs.getInt("id_gabarit");
        props.setIdGabarit(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        intVal = rs.getInt("id_gabarit_template");
        props.setIdGabaritTemplate(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        intVal = rs.getInt("id_doc_pdf");
        props.setIdLastPdf(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        intVal = rs.getInt("id_doc_qxp");
        props.setIdLastQxp(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        intVal = rs.getInt("id_doc_doc");
        props.setIdLastDoc(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        props.setNbPageBySpread(rs.getInt("pagination_double") != 0
                ? RunProperties.PAGINATION_DOUBLE
                : RunProperties.PAGINATION_SIMPLE);

        // Carry the raw [Flags] value so combined codes (e.g. 3 = SQL|DOCUMENT) survive — do NOT
        // collapse to an enum, which would silently drop combined values to NONE. Finding #1.
        intVal = rs.getInt("store_data_type");
        props.setStoreDataTypeCode(rs.wasNull() ? 0 : intVal);

        return props;
    }
}
```

---

## `service/impl/CheckServiceImpl.java`
```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.DataNameValue;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunTask;
import com.socgen.sgs.api.quark.engine.domain.StoreDataType;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.service.CheckService;
import com.socgen.sgs.api.quark.engine.service.ProcessTasksService;
import com.socgen.sgs.api.quark.engine.service.QxpsCallerService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * Step 6: CHECK — Overflow detection, re-processing, and data collection.
 *
 * <p>Three phases:
 * <ol>
 *   <li>Overflow detection: find overflowing boxes, re-process affected dynamic tasks</li>
 *   <li>SQL data collection: collect DataNameValues from TaskDynamique and TaskSql</li>
 *   <li>Document data collection: collect box name/values from final document XML</li>
 * </ol>
 *
 * Cross-reference: .NET Run_Base.Check()
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class CheckServiceImpl implements CheckService {

    private static final String BOX_AUTO_NAME_PREFIX = "Box";
    private static final String BRACKET_OPEN = "[";
    private static final String BRACKET_CLOSE = "]";

    private final GetGabaritXmlBusiness getGabaritXmlBusiness;
    private final ProcessTasksService processTasksService;
    private final QxpsCallerService qxpsCallerService;

    @Override
    public void check(Run run) {
        log.info("Starting Check step for run [{}]", run.getId());

        // Phase 1: Refresh gabarit XML from QXPS (it was purged after step execution)
        refreshGabaritXml(run);

        // Phase 2: Overflow detection and re-processing
        if (hasControlOverflow(run)) {
            checkOverflow(run);
        }

        // Phase 3 & 4: data collection — bitwise tests on the raw store-type code so a combined
        // value (0x03 = SQL|DOCUMENT) enables BOTH collections. (.NET Run_Base.cs:677/699 do two
        // independent (Store_Type & flag) == flag tests.) Finding #1.
        int storeCode = run.getRunProperties().getStoreDataTypeCode();

        // Phase 3: SQL data collection
        if (StoreDataType.hasFlag(storeCode, StoreDataType.SQL)) {
            collectSqlData(run);
        }

        // Phase 4: Document data collection
        if (StoreDataType.hasFlag(storeCode, StoreDataType.DOCUMENT)) {
            // Refresh XML again if overflow re-processing changed the document
            refreshGabaritXml(run);
            collectDocumentData(run);
        }

        log.info("Check step completed for run [{}]", run.getId());
    }

    // ========================================================================
    // Phase 1: Refresh gabarit XML
    // ========================================================================

    /**
     * Fetch the full document XML from QXPS and update the gabarit.
     * After step execution, the gabarit XML is purged (document content changed).
     * We need to fetch the latest XML for overflow detection and data collection.
     *
     * Cross-reference: .NET Document.XML property (lazy-loaded via QXPS_File_Manager.Get_XML)
     */
    private void refreshGabaritXml(Run run) {
        DocumentDomain gabarit = run.getGabarit();
        String documentName = gabarit.getFilePoolPath();

        log.debug("Refreshing gabarit XML from QXPS for document [{}]", documentName);

        // Fetch full document XML via the business bridge (the service must not call infra directly).
        String xmlContent = getGabaritXmlBusiness.fetchXml(documentName);
        if (xmlContent != null && !xmlContent.isEmpty()) {
            gabarit.initXmlFromContent(xmlContent);
            log.debug("Gabarit XML refreshed successfully for document [{}]", documentName);
        } else {
            log.warn("Gabarit XML refresh returned empty for document [{}]", documentName);
        }
    }

    // ========================================================================
    // Phase 2: Overflow detection
    // Cross-reference: .NET Run_Base.Check() — Control_Overflow section
    // ========================================================================

    /**
     * Check if any dynamic task in the run has overflow control enabled.
     */
    private boolean hasControlOverflow(Run run) {
        for (TaskBase task : run.getTasks().values()) {
            if (task instanceof TaskDynamique) {
                TaskDynamique dynTask = (TaskDynamique) task;
                if (dynTask.isTodo() && dynTask.isControlOverflow()) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Detect overflow boxes and re-process affected dynamic tasks.
     *
     * Cross-reference: .NET Run_Base.Check() overflow section
     */
    private void checkOverflow(Run run) {
        log.info("Run [{}] has overflow control enabled", run.getId());

        QxpXml xml = run.getGabarit().getQxpXml();
        List<String> overflowBoxes = xml.getOverflowBoxes();

        log.info("Document contains {} box(es) in overflow", overflowBoxes.size());

        if (overflowBoxes.isEmpty()) {
            return;
        }

        List<TaskBase> tasksToReprocess = new ArrayList<>();

        // Check each dynamic task with control_overflow
        for (TaskBase task : run.getTasks().values()) {
            if (!(task instanceof TaskDynamique)) continue;

            TaskDynamique dynTask = (TaskDynamique) task;
            if (!dynTask.isTodo() || !dynTask.isControlOverflow()) continue;

            log.debug("Task [{}] has overflow control enabled", dynTask.getId());

            // Clear previous overflow boxes
            dynTask.getOverflowBoxes().clear();

            // Find which of this task's box names are in overflow
            for (String boxName : dynTask.getBoxNames()) {
                if (overflowBoxes.contains(boxName)) {
                    dynTask.getOverflowBoxes().add(boxName);
                }
            }

            if (!dynTask.getOverflowBoxes().isEmpty()) {
                tasksToReprocess.add(dynTask);
                log.info("Task [{}] has {} box(es) in overflow — will be re-processed",
                        dynTask.getId(), dynTask.getOverflowBoxes().size());
            } else {
                log.debug("No overflow for task [{}]", dynTask.getId());
            }
        }

        // Set all tasks to todo=false, EXCEPT tasks to reprocess and allwaysReprocess tasks
        if (!tasksToReprocess.isEmpty()) {
            for (TaskBase task : run.getTasks().values()) {
                if (!tasksToReprocess.contains(task) && !task.isAllwaysReprocess()) {
                    task.setTodo(false);
                }
            }

            // Re-execute Process + Process_Steps
            log.info("Re-processing {} task(s) due to overflow", tasksToReprocess.size());

            // Re-create RunTask for re-processing
            run.setRunTask(new RunTask(run));

            processTasksService.processTasks(run);
            qxpsCallerService.process(run);

            // Refresh XML after re-processing
            refreshGabaritXml(run);
        }
    }

    // ========================================================================
    // Phase 3: SQL data collection
    // Cross-reference: .NET Run_Base.Check() — Store_Data_Type.SQL section
    // ========================================================================

    private void collectSqlData(Run run) {
        log.debug("Collecting SQL data for run [{}]", run.getId());

        // From TaskDynamique
        for (TaskBase task : run.getTasks().values()) {
            if (task instanceof TaskDynamique) {
                TaskDynamique dynTask = (TaskDynamique) task;
                if (dynTask.isStoreData() && !dynTask.getDataNamesValues().isEmpty()) {
                    run.getSqlDataNamesValues().addAll(dynTask.getDataNamesValues());
                }
            }
        }

        // From TaskSql
        for (TaskBase task : run.getTasks().values()) {
            if (task instanceof TaskSql) {
                TaskSql sqlTask = (TaskSql) task;
                if (sqlTask.isStoreData() && !sqlTask.getDataNamesValues().isEmpty()) {
                    run.getSqlDataNamesValues().addAll(sqlTask.getDataNamesValues());
                }
            }
        }

        log.info("Collected {} SQL data entries for run [{}]",
                run.getSqlDataNamesValues().size(), run.getId());
    }

    // ========================================================================
    // Phase 4: Document data collection
    // Cross-reference: .NET Run_Base.Check() — Store_Data_Type.DOCUMENT section
    // ========================================================================

    private void collectDocumentData(Run run) {
        log.debug("Collecting document data for run [{}]", run.getId());

        QxpXml xml = run.getGabarit().getQxpXml();
        List<String[]> namesValues = xml.getNamesValuesBoxes();

        for (String[] nameValue : namesValues) {
            String name = nameValue[0];

            // Exclude auto-generated box names:
            // 1. Names starting with "Box" (QuarkXPress auto-naming)
            // 2. Names enclosed in brackets [name] (clone auto-naming)
            if (name.startsWith(BOX_AUTO_NAME_PREFIX)) {
                continue;
            }
            if (name.startsWith(BRACKET_OPEN) && name.endsWith(BRACKET_CLOSE)) {
                continue;
            }

            String value = nameValue.length > 1 ? nameValue[1] : "";
            run.getDocDataNamesValues().add(new DataNameValue(name, value));
        }

        log.info("Collected {} document data entries for run [{}]",
                run.getDocDataNamesValues().size(), run.getId());
    }
}
```

---

## `business/EndRunBusiness.java`
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
            messages[i] = errors.get(i).getMessage();
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

## `business/ProcessSqlBusiness.java`
```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DataNameValue;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.StoreDataType;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocLigne;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocTable;
import com.socgen.sgs.api.quark.engine.domain.helper.DataTypeHelper;
import com.socgen.sgs.api.quark.engine.domain.task.TaskException;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.enums.TaskExceptionTypeEnum;
import com.socgen.sgs.api.quark.engine.infra.dao.TaskSqlDao;
import com.socgen.sgs.api.quark.engine.mapper.InParamSqlMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/** Processes a SQL task: executes SQL, creates blocs, checks exceptions. */
@Component
@RequiredArgsConstructor
@Slf4j
public class ProcessSqlBusiness {

    private static final String NAME_BLOC_COL = "NOM_BLOC";
    private static final String VALUE_BLOC_COL = "VALEUR_BLOC";
    private static final String DESCRIPTION_BLOC_COL = "DESCRIPTION_BLOC";
    private static final String INFO_BLOC_COL = "INFO_BLOC";
    private static final String N1_END_BLOC = "N1";

    /** RunError categories: 1=Bloquante, 2=Critique, 3=Warning. */
    private static final int CRITIQUE = 2;

    private final TaskSqlDao taskSqlDao;
    private final InParamSqlMapper inParamSqlMapper;

    public void execute(TaskSql task) {
        Map<String, Object> parameters = inParamSqlMapper.toParameterMap(task.getRun().getInParams());

        try {
            List<Map<String, Object>> rows = taskSqlDao.executeSql(task.getSql(), parameters);

            if (rows.isEmpty()) {
                log.warn("No SQL data returned for task {}", task.getId());
            } else {
                addBlocs(task, rows);
            }

            checkTaskExceptions(task);
        } catch (Exception ex) {
            throw new RuntimeException("Error executing SQL for task " + task.getDebugInfo(), ex);
        }
    }

    private void addBlocs(TaskSql task, List<Map<String, Object>> rows) {
        boolean integrerN1 = task.getRun().getRunProperties().isIntegrerN1();
        // Bitwise SQL test on the raw store-type code (the enum collapsed combined values like 0x03
        // to NONE, losing the SQL bit). (.NET Run_Base.cs:677.) Finding #1.
        boolean storeData = task.isStoreData()
                && StoreDataType.hasFlag(task.getRun().getRunProperties().getStoreDataTypeCode(), StoreDataType.SQL);

        for (Map<String, Object> row : rows) {
            String blocName = "";
            try {
                blocName = toString(row.get(NAME_BLOC_COL));
                if (!integrerN1 && blocName.endsWith(N1_END_BLOC)) {
                    continue;
                }

                String blocValue = DataTypeHelper.outputToString(
                        row.get(VALUE_BLOC_COL), task.getDataType(), task.getNbDecimal(),
                        task.isShowZero(), task.getNullString(), task.isDecimalSignificative());

                if (task.getBlocsUpdate().containsKey(blocName)) {
                    log.warn("Duplicate bloc '{}' in task {}", blocName, task.getDebugInfo());
                    continue;
                }

                BlocBox bloc = new BlocBox(task, blocName, blocValue);
                bloc.setAction(BlocActionEnum.UPDATE);
                task.getBlocsUpdate().put(blocName, bloc);

                if (storeData) {
                    String desc = row.containsKey(DESCRIPTION_BLOC_COL) ? toString(row.get(DESCRIPTION_BLOC_COL)) : "";
                    String info = row.containsKey(INFO_BLOC_COL) ? toString(row.get(INFO_BLOC_COL)) : "";
                    task.getDataNamesValues().add(new DataNameValue(blocName, blocValue, desc, info));
                }

            } catch (Exception e) {
                log.error("Error adding bloc '{}' in task {}", blocName, task.getDebugInfo(), e);
            }
        }
    }

    private void checkTaskExceptions(TaskSql task) {
        if (task.getExceptions().isEmpty()) return;

        QxpXml xml = task.getRun().getGabarit().getQxpXml();
        String lastDestination = "";

        for (TaskException exception : task.getExceptions().values()) {
            boolean processRemove;

            if (task.getBlocsUpdate().containsKey(exception.getName())) {
                BlocBox bloc = (BlocBox) task.getBlocsUpdate().get(exception.getName());
                processRemove = bloc.getValue() == null
                        || bloc.getValue().isBlank()
                        || bloc.getValue().equals(task.getNullString());
            } else {
                processRemove = true;
            }

            if (!processRemove) continue;

            // The conditional bloc to remove must exist in the document.
            // Cross-reference: .NET Process_SQL.Check_Task_Exception — Exist_Name guard.
            if (!xml.existName(exception.getName())) {
                task.getRun().getErrors().add(new RunError(CRITIQUE,
                        "Bloc conditionnel invalide [" + exception.getName() + "] (tache " + task.getId() + ")"));
                continue;
            }

            // The table being removed (or holding the rows) must exist.
            if (xml.existName(exception.getTableName())) {
                if (exception.getType() == TaskExceptionTypeEnum.LINE) {
                    // The table must hold at least the highest row index we want to remove.
                    int maxLigne = 0;
                    if (exception.getIndexLignes() != null) {
                        for (int ligne : exception.getIndexLignes()) {
                            maxLigne = Math.max(maxLigne, ligne);
                        }
                    }
                    if (xml.getNbLignes(exception.getTableName()) >= maxLigne) {
                        if (exception.getIndexLignes() != null) {
                            for (int idx : exception.getIndexLignes()) {
                                String ligneId = exception.getTableName() + "_" + idx;
                                if (!task.getBlocsModify().containsKey(ligneId)) {
                                    BlocLigne blocLigne = new BlocLigne(task, ligneId, exception.getTableName(), idx);
                                    blocLigne.setCondName(exception.getTableName());
                                    blocLigne.setAction(BlocActionEnum.REMOVE);
                                    task.getBlocsModify().put(ligneId, blocLigne);
                                    lastDestination = exception.getTableName();
                                }
                            }
                        }
                    } else {
                        task.getRun().getErrors().add(new RunError(CRITIQUE,
                                "Lignes manquantes dans la table [" + exception.getTableName()
                                        + "] pour le bloc [" + exception.getName() + "]"));
                    }
                } else {
                    if (!task.getBlocsModify().containsKey(exception.getTableName())) {
                        BlocTable blocTable = new BlocTable(task, exception.getTableName());
                        blocTable.setCondName(exception.getTableName());
                        blocTable.setAction(BlocActionEnum.REMOVE);
                        task.getBlocsModify().put(exception.getTableName(), blocTable);
                        lastDestination = exception.getTableName();
                    }
                }
            } else {
                task.getRun().getErrors().add(new RunError(CRITIQUE,
                        "Table inexistante [" + exception.getTableName() + "]"));
            }
        }

        if (!lastDestination.isEmpty()) {
            task.setDestinationBlocName(lastDestination);
        }
    }

    private static String toString(Object value) {
        return value != null ? value.toString() : "";
    }
}
```

---

## `business/LoadTemplatesBusiness.java`
```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;
import com.socgen.sgs.api.quark.engine.infra.dao.GetGabaritTemplateDao;
import com.socgen.sgs.api.quark.engine.mapper.TemplateMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/**
 * Business component for loading templates from the database into a Run.
 *
 * Cross-reference: .NET Proxy_Template.Load_Templates(Run)
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class LoadTemplatesBusiness {

    private final GetGabaritTemplateDao getGabaritTemplateDao;
    private final TemplateMapper templateMapper;

    /**
     * Load all templates for the run's gabarit template into run.getTemplates().
     *
     * @param run the run to populate with templates
     */
    public void execute(Run run) {
        int idGabaritTemplate = run.getRunProperties().getIdGabaritTemplate();

        if (idGabaritTemplate == Integer.MIN_VALUE) {
            log.info("No gabarit template ID set for run [{}], skipping template loading", run.getId());
            return;
        }

        log.info("Loading templates for idGabaritTemplate={} in run [{}]",
                idGabaritTemplate, run.getId());

        // Load the gabarit TEMPLATE document itself FIRST (parity: .NET Run.cs:152
        // this.Gabarit_Template = Get_Gabarit_Template(this); then :157 Load_Templates(this)).
        // Dynamic tasks clone their blocs from this document — without it TaskDynamique.prepare
        // would upload the wrong document. Finding #6/#22.
        DocumentDomain gabaritTemplate = getGabaritTemplateDao.getGabaritTemplate(idGabaritTemplate);
        // The DAO builder sets fileName but not filePoolPath; populate it the same way the source
        // gabarit is set up (GetGabaritBusiness.preparePaths → getPoolPath), so the upload key and
        // every later pool lookup resolve to the same R_<runId>/<fileName> string. .NET sets it in
        // the Document ctor via GetPoolPath (Document.cs:118).
        gabaritTemplate.setFilePoolPath(run.getRunProperties().getPoolPath(gabaritTemplate.getFileName()));
        run.setGabaritTemplate(gabaritTemplate);

        List<Map<String, Object>> rows = getGabaritTemplateDao.getTemplates(idGabaritTemplate);

        run.getTemplates().clear();

        for (Map<String, Object> row : rows) {
            Template template = templateMapper.mapToTemplate(row);
            if (template != null) {
                run.getTemplates().put(template.getName(), template);
            }
        }

        log.info("Loaded {} templates for run [{}]", run.getTemplates().size(), run.getId());
    }
}
```

---

## `domain/task/TaskDynamique.java`
```java
package com.socgen.sgs.api.quark.engine.domain.task;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBreakRules;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

/** Represents a dynamic task that adds blocs/tables/pages to a QuarkXPress document. */
@Getter
@Setter
public class TaskDynamique extends TaskAnchor {

    private String sql;
    private DBreakRules pageBreakRules = DBreakRules.DEFAULT;
    private DBreakRules columnBreakRules = DBreakRules.DEFAULT;
    private boolean controlOverflow = false;
    private boolean storeData = false;
    private boolean newPageTable = false;
    private int nbColumn = 1;
    private BigDecimal columnSpace = BigDecimal.ZERO;

    private final List<String> boxNames = new ArrayList<>();
    private final List<String> overflowBoxes = new ArrayList<>();

    private FilePoolPort filePoolService;

    public TaskDynamique(int id, Run run) {
        super(id, run);
    }

    @Override
    public void prepare() {
        if (this.isTodo() && filePoolService != null) {
            // Upload the gabarit TEMPLATE (not the source gabarit) into the QXPS pool.
            // Parity: .NET Task_Dynamique.Prepare → Addfile(this.Run.Gabarit_Template.FilePoolPath,
            // this.Run.Gabarit_Template.Data). Finding #22.
            DocumentDomain gabaritTemplate = this.getRun().getGabaritTemplate();
            if (gabaritTemplate == null) {
                // .NET raises MSG_Gabarit_Template_NULL; fail loudly rather than NPE / silently
                // uploading the wrong document.
                throw new IllegalStateException(
                        "Gabarit_Template is null for dynamic task " + this.getId()
                                + " in run " + this.getRun().getId()
                                + " — id_gabarit_template must be set and loaded before prepare()");
            }
            filePoolService.addFile(gabaritTemplate.getFilePoolPath(), gabaritTemplate.getData());
        }
    }


    public void setNbColumn(int value) {
        if (value > 0) {
            this.nbColumn = value;
        }
    }

    public void setColumnSpace(BigDecimal value) {
        if (value != null && value.compareTo(BigDecimal.ZERO) > 0) {
            this.columnSpace = value;
        }
    }
}
```

---

## `domain/Run.java`
```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness;
import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Domain entity representing a Run
 */
@Getter
@Setter
@AllArgsConstructor
@Slf4j
public class Run {
    private Integer id;
    private String name;
    private RunStatus status;
    private LocalDateTime startDate;
    private RunProperties runProperties;
    private DocumentDomain gabarit;

    /**
     * The gabarit TEMPLATE document (distinct from the source {@link #gabarit}). Loaded only when the
     * run has dynamic tasks and an id_gabarit_template is set; dynamic tasks clone their blocs from
     * this document. Cross-reference: .NET Run_Base._gabarit_Template (Run.cs:152 Get_Gabarit_Template).
     */
    private DocumentDomain gabaritTemplate;

    /** Keyed by parameter name, preserves insertion order. */
    private Map<String, InParam> inParams = new LinkedHashMap<>();

    /** Keyed by task ID, preserves insertion order. */
    private Map<Integer, TaskBase> tasks = new LinkedHashMap<>();

    /** Keyed by template name, preserves insertion order. */
    private Map<String, Template> templates = new LinkedHashMap<>();

    /** Aggregates tasks with blocs after Verify phase for Step 5. */
    private RunTask runTask;

    /** SQL data collected during Check step. Cross-reference: .NET Run_Base._sqlDataNamesValues */
    private final java.util.List<DataNameValue> sqlDataNamesValues = new java.util.ArrayList<>();

    /** Document data collected during Check step. Cross-reference: .NET Run_Base._docDataNamesValues */
    private final java.util.List<DataNameValue> docDataNamesValues = new java.util.ArrayList<>();

    /** Rendered output documents. Cross-reference: .NET Run_Base._result */
    private RunResult result = new RunResult();

    /** Errors collected during run execution. Cross-reference: .NET Run_Base._errors */
    private final java.util.List<RunError> errors = new java.util.ArrayList<>();

    /** End timestamp. Cross-reference: .NET Run_Base._finGeneration */
    private LocalDateTime endDate;

    private long sizeLimitBeforeFailSoft;

    /** Max boxes a modified document may contain (.NET EngineCoreSetting Nb_Box_Max). Configurable. */
    private int nbBoxMax = 17500;

    /** Average byte-size of a box, used for box-complexity (.NET EngineCoreSetting Average_Box_Size). Configurable. */
    private int averageBoxSize = 3400;

    /**
     * Accumulated run trace, persisted to the End_Run p_log_trace CLOB.
     * Cross-reference: .NET Run.Trace_Context.All_Logs.
     */
    private final java.util.List<String> traceLogs = new java.util.ArrayList<>();

    private static final java.time.format.DateTimeFormatter TRACE_TS =
            java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS");

    /** Append a timestamped trace message (kept in-memory for the End_Run trace CLOB). */
    public void trace(String message) {
        traceLogs.add(LocalDateTime.now().format(TRACE_TS) + "  " + message);
    }

    /** Full accumulated trace text for the End_Run p_log_trace CLOB. */
    public String getTraceLog() {
        return String.join(System.lineSeparator(), traceLogs);
    }

    /**
     * Constructor that accepts size limit parameter.
     * Used by ProcessRunServiceImpl to inject the configured size limit from application.yaml
     */
    public Run(long sizeLimitBeforeFailSoft) {
        this.sizeLimitBeforeFailSoft = sizeLimitBeforeFailSoft;
        this.runTask = new RunTask(this);
    }

    /**
     * No-arg constructor for backward compatibility.
     * Defaults to 10MB if no explicit size limit is provided.
     */
    public Run() {
        this.sizeLimitBeforeFailSoft = 209715200; // fallback = 200MB; configurable via engine.gabarit.size-limit-before-fail-soft
        this.runTask = new RunTask(this);
    }

    /**
     * Prepares the gabarit for this run based on gabarit source.
     * Calls the appropriate method on GetGabaritBusiness based on the gabarit source,
     * and stores the fetched document directly in this.gabarit.
     * After loading, adds the file to the QXPS document pool and retrieves the document identity (DID),
     * then sets the identity on the gabarit domain object.
     *
     * - GABARIT               → Get_Gabarit(idGabarit)
     * - DOCUMENT_COURANT      → Get_Gabarit_Document(idSuivi)
     * - DOCUMENT_PRECEDENT_CERTIFIE → Get_Gabarit_Document_Certifie(idSuivi)
     * - DOCUMENT_SUIVI        → Get_Gabarit_Document(idSuiviGabaritSource)
     *
     * @param getGabaritBusiness    the business component injected by the caller
     * @param getGabaritXmlBusiness business bridge for fetching the full gabarit XML (.NET Document.XML lazy-load)
     * @param filePoolPort          port for uploading the file to the QXPS document pool
     * @param documentIdentityPort  port for fetching XML and parsing document identity
     */
    public void prepareGabarit(GetGabaritBusiness getGabaritBusiness,
                                GetGabaritXmlBusiness getGabaritXmlBusiness,
                                FilePoolPort filePoolPort,
                                DocumentIdentityPort documentIdentityPort) {
        if (this.runProperties == null) {
            throw new IllegalStateException(
                    "Run properties must be set before preparing gabarit for runId: " + this.id);
        }

        switch (this.runProperties.getGabaritSource()) {
            case GABARIT:
                this.gabarit = getGabaritBusiness.getAndPrepareGabarit(
                        this.runProperties,
                        this.runProperties.getIdGabarit());
                break;
            case DOCUMENT_COURANT:
                this.gabarit = getGabaritBusiness.getAndPrepareGabaritDocumentCourant(
                        this.runProperties,
                        this.runProperties.getIdSuivi());
                break;
            case DOCUMENT_PRECEDENT_CERTIFIE:
                this.gabarit = getGabaritBusiness.getAndPrepareGabaritDocumentCertifie(
                        this.runProperties,
                        this.runProperties.getIdSuivi());
                break;
            case DOCUMENT_SUIVI:
                this.gabarit = getGabaritBusiness.getAndPrepareGabaritDocumentSuivi(
                        this.runProperties,
                        this.runProperties.getIdSuiviGabaritSource());
                break;
            default:
                throw new IllegalArgumentException(
                        "Unsupported gabarit source: " + this.runProperties.getGabaritSource());
        }

        if (this.gabarit == null) {
            return;
        }

        // Step 1: Upload the gabarit to the QXPS document pool — UNCONDITIONALLY, before the
        // Mode_Degrade check. Parity: .NET Run.cs:92 calls QXPS_File_Manager.Addfile(FilePoolPath, Data)
        // before any degrade branch; a degraded run still renders the PDF and fetches the literal QXP
        // from the pool, so the document MUST be present. The upload key is getFilePoolPath()
        // (the R_<runId>/-scoped name), matching .NET (Gabarit.FilePoolPath) and every downstream
        // consumer — QxpsCallerBusiness.executeStep/render and CheckServiceImpl all address the
        // gabarit by getFilePoolPath(). (Findings #0, #5, #7, #8, #24, #26.)
        filePoolPort.addFile(this.gabarit.getFilePoolPath(), this.gabarit.getData());

        // Step 2: Mode_Degrade — if the template exceeds the size limit, skip ONLY the DID parse and
        // the full-XML load (steps 3-4). Parity: .NET Document.cs:200 gates only the DID parse inside
        // Evaluate_Document_Identity, and the Document.XML getter returns QXP_XML.Empty in degrade mode.
        // The pool upload above has already run, so the degraded render has its document. (Findings #0, #7, #24.)
        if (this.gabarit.getData().length > sizeLimitBeforeFailSoft) {
            log.warn("Gabarit size {} bytes exceeds limit {} bytes, setting Mode_Degrade for runId: {}",
                    this.gabarit.getData().length, sizeLimitBeforeFailSoft, this.id);
            this.runProperties.setModeDegrade(true);
            return; // degrade: skip DID parse + full-XML load only — gabarit is already in the pool
        }

        // Step 3: Load the FULL gabarit XML into the domain object so page/layout/box info is
        // available during Prepare and Process (before Check). Parity: .NET first materialises
        // this.Gabarit.XML right after Addfile (Run.cs:99) and caches it (Document.cs:421-444);
        // without this the gabarit XML stays QxpXml.EMPTY until Check, breaking anchor/page/box
        // evaluation in Dynamique and Compartiment-incorporate tasks. (Finding #25.)
        String fullXml = getGabaritXmlBusiness.fetchXml(this.gabarit.getFilePoolPath());
        if (fullXml != null && !fullXml.isEmpty()) {
            this.gabarit.initXmlFromContent(fullXml);
        }

        // Step 4: Fetch XML for the DID box and parse document identity. Parity: .NET
        // Evaluate_Document_Identity (Document.cs:205). Keyed on getFilePoolPath() so the DID fetch
        // hits the same pooled document that was uploaded and that the modify/render path operates on.
        String xmlContent = documentIdentityPort.fetchXmlForBox(this.gabarit.getFilePoolPath(), "DID");
        String didValue = documentIdentityPort.getElementValueByIdName(xmlContent, "DID");
        DocumentIdentity identity = documentIdentityPort.parseDocumentIdentity(didValue);

        // Step 5: Set the document identity on the gabarit domain object
        this.gabarit.setDocumentIdentity(identity);
    }
}
```

---

## `src/test/.../enums/AbsoluteRepeatTypeTest.java (NEW)`
```java
package com.socgen.sgs.api.quark.engine.enums;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

@DisplayName("AbsoluteRepeatType [Flags] bit-test Tests")
class AbsoluteRepeatTypeTest {

    @Test
    @DisplayName("Combined values (0x03/0x05/0x06/0x07/0xFF) classify correctly and never throw")
    void shouldHandleCombinedFlagValues() {
        // 0x00 = Default
        assertFalse(AbsoluteRepeatType.hasFirstPage(0));
        assertFalse(AbsoluteRepeatType.hasOtherPage(0));
        assertFalse(AbsoluteRepeatType.hasLastPage(0));

        // 0x01 First, 0x02 Other, 0x04 Last
        assertTrue(AbsoluteRepeatType.hasFirstPage(0x01));
        assertTrue(AbsoluteRepeatType.hasOtherPage(0x02));
        assertTrue(AbsoluteRepeatType.hasLastPage(0x04));

        // 0x03 = First | Other
        assertTrue(AbsoluteRepeatType.hasFirstPage(0x03));
        assertTrue(AbsoluteRepeatType.hasOtherPage(0x03));
        assertFalse(AbsoluteRepeatType.hasLastPage(0x03));

        // 0x06 = Other | Last
        assertFalse(AbsoluteRepeatType.hasFirstPage(0x06));
        assertTrue(AbsoluteRepeatType.hasOtherPage(0x06));
        assertTrue(AbsoluteRepeatType.hasLastPage(0x06));

        // 0x07 = First | Other | Last ; 0xFF = All
        assertTrue(AbsoluteRepeatType.hasFirstPage(0x07));
        assertTrue(AbsoluteRepeatType.hasOtherPage(0x07));
        assertTrue(AbsoluteRepeatType.hasLastPage(0x07));
        assertTrue(AbsoluteRepeatType.hasFirstPage(0xFF));
        assertTrue(AbsoluteRepeatType.hasOtherPage(0xFF));
        assertTrue(AbsoluteRepeatType.hasLastPage(0xFF));
    }
}
```

---

## Test edits (snippets)

### `RunPropertiesTest.java`
Line ~31 (defaults test):
```java
        assertEquals(StoreDataType.NONE.getCode(), runProperties.getStoreDataTypeCode());
```
Replace the `shouldSetStoreDataType` test and add a combined-value test:
```java
    @Test
    @DisplayName("Should set store data type code")
    void shouldSetStoreDataType() {
        runProperties.setStoreDataTypeCode(StoreDataType.DOCUMENT.getCode());

        assertEquals(StoreDataType.DOCUMENT.getCode(), runProperties.getStoreDataTypeCode());
    }

    @Test
    @DisplayName("Combined store type 0x03 enables both SQL and DOCUMENT (no collapse to NONE)")
    void shouldHonourCombinedStoreType() {
        runProperties.setStoreDataTypeCode(0x03);

        assertTrue(StoreDataType.hasFlag(runProperties.getStoreDataTypeCode(), StoreDataType.SQL));
        assertTrue(StoreDataType.hasFlag(runProperties.getStoreDataTypeCode(), StoreDataType.DOCUMENT));
    }
```

### `RunPropertiesMapperTest.java`
Line ~159:
```java
        assertEquals(StoreDataType.DOCUMENT.getCode(), props.getStoreDataTypeCode());
```

---

## Apply checklist
- [ ] Replace `domain/StoreDataType.java`
- [ ] Replace `enums/AbsoluteRepeatType.java`
- [ ] Replace `domain/dynamic/template/Template.java`
- [ ] Replace `mapper/TemplateMapper.java`
- [ ] Replace `domain/RunProperties.java`
- [ ] Replace `mapper/RunPropertiesMapper.java`
- [ ] Replace `service/impl/CheckServiceImpl.java`
- [ ] Replace `business/EndRunBusiness.java`
- [ ] Replace `business/ProcessSqlBusiness.java`
- [ ] Replace `business/LoadTemplatesBusiness.java`
- [ ] Replace `domain/task/TaskDynamique.java`
- [ ] Replace `domain/Run.java`
- [ ] Replace `src/test/.../enums/AbsoluteRepeatTypeTest.java (NEW)`
- [ ] Apply the 2 snippets in `service/task/impl/DynamiqueTaskProcessStrategy.java`
- [ ] Apply the test edits in `RunPropertiesTest.java` and `RunPropertiesMapperTest.java`
- [ ] `mvn compile`
- [ ] `mvn test -Dtest=RunPropertiesTest,RunPropertiesMapperTest,AbsoluteRepeatTypeTest,StoreDataTypeTest,CleanArchitectureLayersTest`
