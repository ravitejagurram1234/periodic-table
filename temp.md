# EOS Quark — New Repo Verification & Remaining Changes (27-06)

**Repo verified:** `/Users/tejaswigurram/Documents/eos quark/java repo 27-06/quark-engine`
**Date:** 2026-06-27
**Method:** every documented change checked against the actual file (matched on real code — method bodies, sentinels, guards, renamed symbols — not just comments).

---

## 0. TL;DR

| Area | Status |
|---|---|
| Batches 10, 11, 12, 13 | ✅ **fully implemented** (31/31 changes) |
| QXPSM SOAP migration (WSDL, stub, client, pom, yaml) | ✅ **in place** |
| BLOB insert fix (`InsertDocumentDaoImpl`) | ✅ **already applied** |
| `DBreakRule` lenient parse | ❌ **MISSING — must apply** (crashes run 488654) |
| 3 date null-guards (defensive) | ❌ **MISSING — recommended** |
| Cleanup (DEBUG logging, old wsdl, pom comment) | ⚠️ **optional** |

**Only one functional fix is still required: `DBreakRule` (§3.1).** The rest is defensive or cosmetic.

---

## 1. Batch verification (10 → 13) — ALL PRESENT

> **Independently re-verified by direct grep on the new repo (2026-06-27).** Final tally:
> **Batch 10 = 4/4, Batch 11 = 9/9, Batch 12 = 6/6, Batch 13 = 6/6 → 25/25 documented
> changes IMPLEMENTED.** Two checks that look like anomalies but are correct:
> `netLabel` is **absent** from `RunStatus.java` (rename to `auditStatusLabel` done, #87 ✅);
> `setRunTask(new RunTask(...))` exists **only in an explanatory comment** in
> `CheckServiceImpl.java:186` (the actual redundant call + `RunTask` import are removed, #59 ✅).

### Batch 10 — DocumentIdentityService (DID lenient parsing) — 4/4 ✅
| change (finding) | status |
|---|---|
| null/blank XML & absent element → `""` (#16) | ✅ |
| null/blank identity → empty `DocumentIdentity` (#23) | ✅ |
| `<6` parts → empty identity (#41) | ✅ |
| `parseDateTime` empty/unparseable → `DATE_MIN` (`0001-01-01`), lenient `M/d/uuuu H:mm:ss` (#42) | ✅ |

### Batch 11 (redo) — 9/9 ✅
`RunStatus` (#83/#87), `AuditDaoImpl` (#53/#82/#87), `InsertDocumentDaoImpl` (#47/#90/#89), `EndRunDaoImpl` (#91), `DocumentDomain` (#92/#57), `QxpsCallerBusiness` (#92/#57), `GetDocumentDaoImpl` (#73), `GetDocumentByIdDaoImpl` (#84), `DocumentDomainTest` (#57) — all present. `netLabel` fully gone; intentionally-kept class-header `.NET` cross-refs still present per policy.

### Batch 12 — QxpXml.java — 6/6 ✅
`getPageNum`→MIN_VALUE (#46), lenient `parseIntSafe` (#78), `!= MIN_VALUE` guards (#77), `getOwnerElement()` cell counting (#45), `.//*` descendants (#79), keep blank names (#80) — all present.

### Batch 13 — 6/6 ✅
`CheckServiceImpl` redundant `setRunTask` removed (#59), `DocumentIdentityHelper` null due-date→`0001-01-01` (#71), `TElementHelper.newBlocName` `[…]` wrap (#74) + `parseDecimal` sentinel (#75), `BlocPage.getNbBox` no swallow try/catch (#76), `ProcessSqlBusiness` comment (#94) — all present.

> Deferred items (#86, #88, #60, #61, #70, #72, #10) remain intentionally not implemented, per the batch docs + register. No action.

---

## 2. QXPSM SOAP migration — PRESENT ✅

| item | status |
|---|---|
| `pom.xml` `<wsdlFile>` = `RequestService.wsdl` | ✅ (stale comment at pom.xml:290 still says "qxpsmsdk.wsdl" — cosmetic) |
| `RequestService.wsdl` trimmed: 1 binding (`RequestServiceSoap11Binding`), 1 port (`RequestServiceHttpSoap11Endpoint`), ns `com.quark.qxpsm`, **0** `<wsdl:fault>` | ✅ |
| Regenerated stub (`RequestServiceLocator`/`RequestServicePortType`/`RequestServiceSoap11BindingStub`); no old `QManagerSDKSvc*`; `QxpsmProbe` deleted | ✅ |
| `QxpsmSoapClient` new locator/port + `setTimeout`, no multi-ref | ✅ |
| Endpoints all on **DEV `srvcldvapd001`**: `qxps.server.url`=`:8080`, `qxpsm.soap.endpoint`=`:8090/qxpsm/services/RequestService`, `qxp.thirdparty.url`=`:8080/saveas/pdf/` | ✅ consistent |

---

## 3. REMAINING CHANGES TO APPLY

### 3.1 `DBreakRule.java` — REQUIRED (crashes run 488654) ❌→✅
Path: `src/main/java/com/socgen/sgs/api/quark/engine/domain/dynamic/report/DBreakRule.java`
Currently still uses strict `Integer.parseInt` (lines 52, 53, 61, 64) → `NumberFormatException` on tokens like `"5L1"`. .NET `Conversion.ToInt` is lenient (→ `int.MinValue`). **Replace the whole file with:**

```java
package com.socgen.sgs.api.quark.engine.domain.dynamic.report;

import lombok.Getter;

import java.util.ArrayList;
import java.util.List;

/** A single break rule defining which row-levels trigger a page/column break and which levels to bring along. */
@Getter
public class DBreakRule {

    public static final DBreakRule DEFAULT = new DBreakRule(Integer.MIN_VALUE);

    private final List<Integer> levels = new ArrayList<>();
    private final List<Integer> bringLevels = new ArrayList<>();

    public DBreakRule(int... levels) {
        for (int level : levels) {
            this.levels.add(level);
        }
    }

    public DBreakRule(String rule) {
        analyseRule(rule);
    }

    public DBreakRule(int level, List<Integer> bringLevels) {
        this.levels.add(level);
        this.bringLevels.addAll(bringLevels);
    }

    /**
     * Parses a rule string in the format "X:Y" where X = levels triggering break, Y = levels to bring.
     * X and Y can be comma-separated values, ranges (e.g. 1-3), or LZ notation (bring Z lines).
     */
    private void analyseRule(String rule) {
        String[] ruleInfos = rule.split(":");
        if (ruleInfos.length == 2) {
            levels.addAll(parseRuleValues(ruleInfos[0]));
            bringLevels.addAll(parseRuleValues(ruleInfos[1]));
        }
    }

    private List<Integer> parseRuleValues(String input) {
        List<Integer> values = new ArrayList<>();
        String[] parts = input.split(",");

        for (String part : parts) {
            String[] rangeParts = part.split("-");

            if (rangeParts.length == 2 && !part.startsWith("L")) {
                int start = toInt(rangeParts[0].trim());
                int end = toInt(rangeParts[1].trim());
                for (int i = start; i <= end; i++) {
                    values.add(i);
                }
            } else {
                String level = rangeParts[0].trim();
                if (level.startsWith("L")) {
                    // LZ notation: negative value means "bring Z lines above regardless of row_level"
                    int nbLigne = toInt(level.substring(1));
                    values.add(-nbLigne);
                } else {
                    values.add(toInt(level));
                }
            }
        }
        return values;
    }

    /**
     * Lenient string-to-int conversion. A non-numeric or malformed break-rule token
     * (e.g. "5L1") yields Integer.MIN_VALUE (the wildcard level) instead of throwing,
     * so a bad rule degrades gracefully rather than failing the whole run. Spaces are
     * stripped and decimals are truncated toward zero.
     */
    private static int toInt(String value) {
        if (value == null) {
            return Integer.MIN_VALUE;
        }
        String v = value.replace(" ", "").trim();
        if (v.isEmpty()) {
            return Integer.MIN_VALUE;
        }
        try {
            return new java.math.BigDecimal(v).intValue();
        } catch (NumberFormatException e) {
            return Integer.MIN_VALUE;
        }
    }
}
```

### 3.2 Date null-guards — RECOMMENDED (defensive; matches `AuditDaoImpl` convention) ❌→✅

**(a)** `infra/dao/impl/GetCompartimentRunsDaoImpl.java` (~line 93):
```java
// FROM
                .addValue("p_date_echeance", java.sql.Date.valueOf(dateEcheance))
// TO
                .addValue("p_date_echeance",
                        dateEcheance != null ? java.sql.Date.valueOf(dateEcheance) : null,
                        java.sql.Types.DATE)
```

**(b)** `infra/dao/impl/EndRunDaoImpl.java` — BOTH occurrences (~line 57 and ~line 86):
```java
// FROM
        params.put("p_date_fin", Timestamp.valueOf(dateFin));
// TO
        params.put("p_date_fin", dateFin != null ? Timestamp.valueOf(dateFin) : null);
```

**(c)** `infra/dao/impl/InsertDataStorageDaoImpl.java` (~line 45):
```java
// FROM
                ops.setTimestamp(3, Timestamp.valueOf(dateGeneration));
// TO
                ops.setTimestamp(3, dateGeneration != null ? Timestamp.valueOf(dateGeneration) : null);
```

### 3.3 Cleanup — OPTIONAL ⚠️
- **Remove the temp Axis DEBUG block** in `src/main/resources/application.yaml` (~lines 70-73):
  ```yaml
  logging:
    level:
      org.apache.axis.transport.http: DEBUG   # delete this block (diagnosis done)
  ```
  (Keep it only if you still want SOAP wire dumps during the next runs.)
- **Delete** the now-unused `src/main/resources/wsdl/qxpsmsdk.wsdl` (the build uses `RequestService.wsdl`). Keep `RequestService.full.wsdl` as the vendor backup.
- **Fix the stale comment** at `pom.xml:290` ("qxpsmsdk.wsdl" → "RequestService.wsdl"). Cosmetic.

---

## 4. Known-good but UNTESTED live paths (watch, no change)
- `InsertDataStorageDaoImpl` (`setPlsqlIndexTable`) and `EndRunDaoImpl.insertRunErrors` (array binds) — correct Oracle idiom mirroring .NET ODP.NET, but not yet exercised by a run. A run that stores SQL/DOCUMENT data or records multiple errors is the real test.
- Final PDF render returned `#10122 blank pages` on run 509636 — that run has 0 content tasks; not a code defect (our `/pdf` is byte-identical to .NET). Validate rendering on a content-ful run (e.g. 488654, 24 tasks) after applying §3.1.

---

## 5. Apply order
1. **§3.1 `DBreakRule`** (required) + **§3.2** null-guards (recommended) + **§3.3** cleanup (optional).
2. `mvn clean install` → expect `BUILD SUCCESS`.
3. Run **488654** (Dynamique, 24 tasks) — should now pass task mapping, render a real PDF, and insert the document (BLOB fix already in).
4. Watch the data-storage / multi-error array-bind paths if that run exercises them.
```
