# EOS Quark Engine — Batch 5 Changes
**Theme: `DataTypeHelper` number / currency / percentage formatting**

_Generated directly from the working-copy files. Whole-file copy-paste._

## Findings fixed in this batch
| # | Sev | Issue | .NET reference |
|---|---|---|---|
| 12 | HIGH | INT output dropped thousands separators (`String.valueOf` instead of grouped) | Data_Type_Helper.cs:417-431 `GetStringInt` uses the "n" specifier (always groups) |
| 13 | HIGH | `decimalSignificative` had the wrong meaning — trailing zeros never suppressed (pattern always used '0' digits; flag only gated `setScale`) | Data_Type_Helper.cs:77-94 `GetDecimalPattern`: true→'0'*n (fixed), false→'#'*n (suppress) |
| 14 | HIGH | CURRENCY and POURCENTAGE were routed through plain decimal formatting → no currency symbol, no `%` | Data_Type_Helper.cs:33-34 CurrencyPattern/PercentPattern; QXP_Format_Helper.cs (correct percent path) |

## What changed
- **#12** `formatInteger` now formats via `DecimalFormat("#,##0", fr-FR)` → grouped output (e.g. `1 234 567`), matching .NET's `"n"` specifier.
- **#13** Decimal formatting now drives fraction digits off the flag: `setMaximumFractionDigits(nbDecimal)` always; `setMinimumFractionDigits(decimalSignificative ? nbDecimal : 0)`. So `decimalSignificative=true` shows fixed trailing zeros and `false` suppresses them — matching .NET's `'0'*n` vs `'#'*n` patterns. Rounding is set explicitly to **HALF_UP** (round-half-away-from-zero, matching .NET `Decimal.ToString`) instead of `DecimalFormat`'s default HALF_EVEN.
- **#14 CURRENCY** now appends `" " + currencySymbol` (fr-FR → `€`) after the formatted number — `1 234,56 €`. No ×100. Matches `Data_Type_Helper.GetStringCurrency`.
- **#14 POURCENTAGE** now appends a single `" %"` with **no ×100** — `15,00 %`. See the decision note below.
- Shared `formatDecimalCore` underlies DECIMAL / CURRENCY / POURCENTAGE so the grouping, fixed-vs-significative, rounding, and zero→nullString rules are identical across all three (a zero with `showZero=false` returns `nullString` with **no** suffix).

## ⚠️ POURCENTAGE — user-approved deviation from the engine's .NET formatter (documented decision)
A focused investigation (3 parallel source audits) established two facts:
1. **The data is stored SCALED** (`15` means 15%) — proven by `QXP_PK_KII_BODY.sql`: rates are produced as `(montant/actif)*100` and consumed as `taux*vb/100` (divide-by-100 to make a fraction only makes sense if the stored value is scaled). Corroborated by `InParamTest` and the verbatim pass-through in KIID/Fiscalité proxies.
2. **The .NET engine path (`Data_Type_Helper.GetStringPourcentage`, called from `Process_SQL.cs:105`) is buggy**: its pattern's `%` specifier multiplies by 100 AND it appends a second `" %"`, so a scaled `15` renders **`"1 500,00 % %"`** — wrong magnitude and a doubled sign. The .NET author flagged it `// TODO à voir si c'est correct`.

Because the data is scaled, the **correct** output is `"15,00 %"` (number + single `" %"`, no ×100) — which is also exactly what .NET's *other*, correct formatter `QXP_Format_Helper` produces. **You approved this deviation** from the buggy engine path. Strict bit-for-bit parity with `GetStringPourcentage` was explicitly declined (it would put visibly wrong figures on the factsheet).

## Flagged for later (not changed here)
- **Grouping character**: fr-FR grouping under JDK 17 (CLDR) may be the narrow no-break space `U+202F`, whereas .NET fr-FR historically uses `U+00A0`. This pre-existed (the decimal path already used `Locale.FRANCE`) and affects ALL grouped output; it is a separate parity item to verify against a .NET golden file, not part of #12/#13/#14. The new test builds expected values from the JVM's actual separator so it is robust either way.
- The `RunPropertiesTest:114` stale-assertion fix (mixed-slash → all-backslash) surfaced during the Batch 4 test run; ensure that one-liner is applied.

---

## `domain/helper/DataTypeHelper.java`
```java
package com.socgen.sgs.api.quark.engine.domain.helper;

import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

/** Converts raw DB values to formatted strings based on DataTypeEnum configuration. */
public final class DataTypeHelper {

    private static final DateTimeFormatter DATE_FMT = DateTimeFormatter.ofPattern("dd/MM/yyyy");
    private static final DateTimeFormatter DATETIME_FMT = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm:ss");

    /**
     * fr-FR symbols (NBSP thousands grouping, ',' decimal, "€" currency). The .NET engine renders
     * under the French thread culture, matching the existing decimal formatting in this class.
     */
    private static final DecimalFormatSymbols FR_SYMBOLS = new DecimalFormatSymbols(Locale.FRANCE);

    private DataTypeHelper() {
    }

    public static String outputToString(Object value, DataTypeEnum dataType, int nbDecimal,
                                        boolean showZero, String nullString, boolean decimalSignificative) {
        if (value == null) {
            return nullString;
        }

        String raw = value.toString().trim();
        if (raw.isEmpty()) {
            return nullString;
        }

        switch (dataType) {
            case INT:
                return formatInteger(raw, showZero, nullString);
            case DECIMAL:
                return formatDecimal(raw, nbDecimal, showZero, nullString, decimalSignificative);
            case CURRENCY:
                // .NET CurrencyPattern "#,##0.{0} {1}" → number + " " + currency symbol (fr-FR → "€").
                // No ×100. Cross-reference: Data_Type_Helper.GetStringCurrency. Finding #14.
                return formatWithSuffix(raw, nbDecimal, showZero, nullString, decimalSignificative,
                        " " + FR_SYMBOLS.getCurrencySymbol());
            case POURCENTAGE:
                // Data is stored SCALED (15 == 15%), confirmed from QXP_PK_KII SQL ((montant/actif)*100
                // to produce, taux*vb/100 to consume). So append a single " %" WITHOUT multiplying by 100,
                // matching .NET's correct formatter QXP_Format_Helper (plain number + literal " %").
                // This is a deliberate, user-approved deviation from the engine's
                // Data_Type_Helper.GetStringPourcentage, which is bugged (×100 via the "%" specifier PLUS
                // a second appended " %", flagged "// TODO à voir si c'est correct") and would render 15
                // as "1 500,00 % %". Finding #14.
                return formatWithSuffix(raw, nbDecimal, showZero, nullString, decimalSignificative, " %");
            case DATE:
                return formatDate(raw, nullString);
            case DATE_TIME:
                return formatDateTime(raw, nullString);
            default:
                return raw;
        }
    }

    private static String formatInteger(String raw, boolean showZero, String nullString) {
        try {
            long val = Long.parseLong(raw);
            if (val == 0 && !showZero) return nullString;
            // Grouped output (NBSP under fr-FR), matching .NET GetStringInt which uses the "n" format
            // specifier (always groups). Finding #12.
            return new DecimalFormat("#,##0", FR_SYMBOLS).format(val);
        } catch (NumberFormatException e) {
            return raw;
        }
    }

    private static String formatDecimal(String raw, int nbDecimal, boolean showZero,
                                        String nullString, boolean decimalSignificative) {
        try {
            String formatted = formatDecimalCore(raw, nbDecimal, showZero, decimalSignificative);
            return formatted == null ? nullString : formatted;
        } catch (NumberFormatException e) {
            return raw;
        }
    }

    /** DECIMAL formatting with a trailing suffix (currency symbol or " %"); suffix is omitted when the
     *  value is treated as null (zero with showZero=false) or unparseable. */
    private static String formatWithSuffix(String raw, int nbDecimal, boolean showZero,
                                           String nullString, boolean decimalSignificative, String suffix) {
        try {
            String formatted = formatDecimalCore(raw, nbDecimal, showZero, decimalSignificative);
            return formatted == null ? nullString : formatted + suffix;
        } catch (NumberFormatException e) {
            return raw;
        }
    }

    /**
     * Core decimal formatter shared by DECIMAL / CURRENCY / POURCENTAGE.
     * Returns the formatted number, or {@code null} to signal "use nullString" (zero with showZero=false).
     * Throws {@link NumberFormatException} on unparseable input so callers can fall back to the raw value.
     *
     * <p>decimalSignificative drives the fraction digits, matching .NET GetDecimalPattern:
     * true → fixed nbDecimal decimals with trailing zeros ('0' pattern); false → suppress trailing
     * zeros up to nbDecimal ('#' pattern). Finding #13. Rounding is HALF_UP (round half away from
     * zero), matching .NET Decimal.ToString, instead of DecimalFormat's default HALF_EVEN.
     */
    private static String formatDecimalCore(String raw, int nbDecimal, boolean showZero,
                                            boolean decimalSignificative) {
        BigDecimal val = new BigDecimal(raw);
        if (val.compareTo(BigDecimal.ZERO) == 0 && !showZero) {
            return null;
        }
        DecimalFormat df = new DecimalFormat("#,##0", FR_SYMBOLS);
        df.setMaximumFractionDigits(nbDecimal);
        df.setMinimumFractionDigits(decimalSignificative ? nbDecimal : 0);
        df.setRoundingMode(RoundingMode.HALF_UP);
        return df.format(val);
    }

    private static String formatDate(String raw, String nullString) {
        try {
            LocalDate date = LocalDate.parse(raw.substring(0, 10));
            return date.format(DATE_FMT);
        } catch (Exception e) {
            return raw.isEmpty() ? nullString : raw;
        }
    }

    private static String formatDateTime(String raw, String nullString) {
        try {
            LocalDateTime dt = LocalDateTime.parse(raw.substring(0, 19));
            return dt.format(DATETIME_FMT);
        } catch (Exception e) {
            return raw.isEmpty() ? nullString : raw;
        }
    }
}
```

---

## `src/test/.../domain/helper/DataTypeHelperTest.java (NEW)`
```java
package com.socgen.sgs.api.quark.engine.domain.helper;

import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.text.DecimalFormatSymbols;
import java.util.Locale;

import static org.junit.jupiter.api.Assertions.assertEquals;

@DisplayName("DataTypeHelper formatting Tests")
class DataTypeHelperTest {

    // Use the JVM's actual fr-FR symbols so assertions survive CLDR grouping-char changes
    // (the grouping separator may be NBSP U+00A0 or NNBSP U+202F depending on the JDK/CLDR).
    private static final DecimalFormatSymbols FR = new DecimalFormatSymbols(Locale.FRANCE);
    private static final char GRP = FR.getGroupingSeparator();
    private static final char DEC = FR.getDecimalSeparator();
    private static final String CUR = FR.getCurrencySymbol();

    @Test
    @DisplayName("#12 INT output is grouped (thousands separators)")
    void intIsGrouped() {
        assertEquals("1" + GRP + "234" + GRP + "567",
                DataTypeHelper.outputToString("1234567", DataTypeEnum.INT, 0, true, "-", false));
    }

    @Test
    @DisplayName("INT zero with showZero=false returns nullString")
    void intZeroNotShown() {
        assertEquals("N/A", DataTypeHelper.outputToString("0", DataTypeEnum.INT, 0, false, "N/A", false));
    }

    @Test
    @DisplayName("#13 decimalSignificative=true keeps fixed trailing zeros")
    void decimalSignificativeKeepsZeros() {
        assertEquals("12" + DEC + "50",
                DataTypeHelper.outputToString("12.5", DataTypeEnum.DECIMAL, 2, true, "-", true));
    }

    @Test
    @DisplayName("#13 decimalSignificative=false suppresses trailing zeros")
    void decimalNotSignificativeSuppressesZeros() {
        assertEquals("12" + DEC + "5",
                DataTypeHelper.outputToString("12.50", DataTypeEnum.DECIMAL, 2, true, "-", false));
        assertEquals("12",
                DataTypeHelper.outputToString("12", DataTypeEnum.DECIMAL, 2, true, "-", false));
    }

    @Test
    @DisplayName("Decimal rounding is HALF_UP (away from zero)")
    void decimalRoundsHalfUp() {
        assertEquals("2" + DEC + "35",
                DataTypeHelper.outputToString("2.345", DataTypeEnum.DECIMAL, 2, true, "-", true));
    }

    @Test
    @DisplayName("#14 CURRENCY appends the currency symbol, no ×100")
    void currencyAppendsSymbol() {
        assertEquals("1" + GRP + "234" + DEC + "50 " + CUR,
                DataTypeHelper.outputToString("1234.5", DataTypeEnum.CURRENCY, 2, true, "-", true));
    }

    @Test
    @DisplayName("#14 POURCENTAGE appends single ' %' and does NOT multiply by 100 (data is scaled)")
    void percentScaledSinglePercent() {
        // 15 means 15% — must render "15,00 %", NOT "1 500,00 % %"
        assertEquals("15" + DEC + "00 %",
                DataTypeHelper.outputToString("15", DataTypeEnum.POURCENTAGE, 2, true, "-", true));
        // significative=false suppresses the trailing zeros
        assertEquals("15 %",
                DataTypeHelper.outputToString("15", DataTypeEnum.POURCENTAGE, 2, true, "-", false));
    }

    @Test
    @DisplayName("CURRENCY/POURCENTAGE zero with showZero=false returns nullString (no suffix)")
    void zeroNotShownHasNoSuffix() {
        assertEquals("-", DataTypeHelper.outputToString("0", DataTypeEnum.CURRENCY, 2, false, "-", true));
        assertEquals("-", DataTypeHelper.outputToString("0", DataTypeEnum.POURCENTAGE, 2, false, "-", true));
    }
}
```

---

## Apply checklist
- [ ] Replace `domain/helper/DataTypeHelper.java`
- [ ] Add `src/test/.../domain/helper/DataTypeHelperTest.java`
- [ ] `mvn compile`
- [ ] `mvn test -Dtest=DataTypeHelperTest`
- [ ] (if not already) apply the `RunPropertiesTest:114` all-backslash fix from Batch 4
