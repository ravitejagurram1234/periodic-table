# EOS Quark — logging hygiene + run 339403 analysis (copy-paste ready)

**Repo:** `14-07 engine service repo/quark-engine`.

## Milestone first
Run **339403** (Dynamique, gabarit G_168 / template GT_6) completed **`GENERATED` end-to-end**:
properties ✓, 3 in-params ✓, **24 tasks + 349 templates loaded ✓**, GT_6 uploaded and its **project parsed
via `getXPressDOM` (the #2 template fix ran) ✓**, SOAP ✓, **PDF rendered ✓**, **`End_Run` executed
successfully (fresh run — no re-run hazard) ✓**, audit ✓. So the success-finalize (#4) + audit fix are
validated on a real run.

---

## Part 1 — Logging mistakes & corrections (the ask)

**The problem:** on a task-SQL failure the code logged `exception.getMessage()` **and** the throwable, and
Spring/the driver embed the **entire SQL query** in that message → the log gets flooded with the whole
statement (twice). You want the **SQL id (task id) + the in-params used**, not the query text.

**Sites found & fixed:**

| File | Was | Now |
|---|---|---|
| `DynamicQueryPortImpl:49` | `log.error("… failed: {}", e.getMessage(), e)` → full SQL + stack | in-params `name=value(TYPE)` + the concise `ORA-…` line only; full stack at DEBUG |
| `DynamiqueTaskProcessStrategy` (catch) | `log.error("… [{}]: {}", id, ex.getMessage(), ex)` → SQL in cause stack | `log.error("Dynamic task [{}] SQL failed: {}", id, ex.getMessage())` + stack at DEBUG |
| `ProcessTasksServiceImpl:51/90/107` | `log.error("Error … task {}: {}", id, ex.getMessage(), ex)` → SQL/huge stack for SQL tasks | same message, **throwable moved to DEBUG** (applies to every task type) |
| `ProcessSqlBusiness` (catch) | `throw new RuntimeException("Error executing SQL for task " + debugInfo, ex)` — no root error | rethrows with the concise `ORA-…` cause so the upstream ERROR line is informative, still no SQL |
| `application.yaml` | leftover `logging.level.org.apache.axis.transport.http: DEBUG` → dumps the full SOAP request/response XML every step | **removed** |

Result — a failed dynamic task now logs **one readable line**, e.g.:
```
ERROR ... DynamiqueTaskProcessStrategy : Dynamic task [229] SQL failed: SQL execution failed —
  in-params [P_DATE=12/01/2023 00:00:00(DATE_TIME), P_STRUCT=..(TEXT), P_GAB=168(INT)] -> ORA-01830: ...
```
The full SQL + stack is still available by turning that logger to DEBUG.

### `DynamicQueryPortImpl.java`  *(paste whole file)*
Path: `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/DynamicQueryPortImpl.java`
```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.domain.port.DynamicQueryPort;
import com.socgen.sgs.api.quark.engine.infra.dao.TaskSqlDao;
import com.socgen.sgs.api.quark.engine.mapper.InParamSqlMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.NestedExceptionUtils;
import org.springframework.stereotype.Repository;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Infrastructure implementation of DynamicQueryPort.
 * Reuses existing TaskSqlDao for SQL execution and InParamSqlMapper for parameter conversion.
 *
 * Cross-reference: .NET Proxy_Generic.GetReader() used in Process_Dynamique.Get_Report()
 */
@Repository
@RequiredArgsConstructor
@Slf4j
public class DynamicQueryPortImpl implements DynamicQueryPort {

    private final TaskSqlDao taskSqlDao;
    private final InParamSqlMapper inParamSqlMapper;

    @Override
    public List<Map<String, Object>> executeQuery(String sql, Map<String, InParam> parameters) {
        if (sql == null || sql.isBlank()) {
            log.warn("Empty SQL provided to DynamicQueryPort, returning empty result");
            return Collections.emptyList();
        }

        log.debug("DynamicQueryPort executing SQL with {} parameters",
                parameters != null ? parameters.size() : 0);

        try {
            Map<String, Object> jdbcParams = inParamSqlMapper.toParameterMap(
                    parameters != null ? parameters : Collections.emptyMap());

            List<Map<String, Object>> results = taskSqlDao.executeSql(sql, jdbcParams);

            log.debug("DynamicQueryPort returned {} rows", results.size());
            return results;

        } catch (Exception e) {
            // Do NOT surface the SQL text: the driver/Spring embed the whole query in the exception
            // message, which floods the logs. Carry the in-params + the concise Oracle error instead;
            // the full stack (with the SQL) is available only at DEBUG.
            log.debug("Dynamic SQL failure detail", e);
            throw new RuntimeException(
                    "SQL execution failed — in-params [" + describeParams(parameters) + "] -> " + rootMessage(e), e);
        }
    }

    /** "name=value(TYPE)" per in-param, so a bad bind is visible without dumping the SQL text. */
    private static String describeParams(Map<String, InParam> parameters) {
        if (parameters == null || parameters.isEmpty()) {
            return "";
        }
        return parameters.values().stream()
                .map(p -> p.getName() + "=" + p.getStringValue() + "(" + p.getType() + ")")
                .collect(Collectors.joining(", "));
    }

    /** Innermost cause message (the ORA-xxxxx line), stripped of the SQL text. */
    private static String rootMessage(Throwable e) {
        Throwable root = NestedExceptionUtils.getMostSpecificCause(e);
        String msg = root.getMessage();
        return msg != null ? msg.strip() : root.getClass().getSimpleName();
    }
}
```

### `DynamiqueTaskProcessStrategy.java`  *(snippet — Stage 1 catch)*
```java
        } catch (Exception ex) {

            log.error("Dynamic task [{}] SQL failed: {}", task.getId(), ex.getMessage());

            log.debug("Dynamic task [{}] SQL failure detail", task.getId(), ex);

            return;

        }
```

### `ProcessTasksServiceImpl.java`  *(3 snippets)*
```java
                // prepare (was: ..., ex.getMessage(), ex)
                log.error("Error preparing task {}: {}", task.getId(), ex.getMessage());
                log.debug("Task {} preparation failure detail", task.getId(), ex);
```
```java
                // process
                log.error("Error processing task {}: {}", task.getId(), ex.getMessage());
                log.debug("Task {} processing failure detail", task.getId(), ex);
```
```java
                // post-process
                log.error("Error post-processing task {}: {}", task.getId(), ex.getMessage());
                log.debug("Task {} post-processing failure detail", task.getId(), ex);
```

### `ProcessSqlBusiness.java`  *(snippet — add import + enrich rethrow)*
```java
import org.springframework.core.NestedExceptionUtils;   // add with the other imports
```
```java
        } catch (Exception ex) {
            // Carry the concise Oracle error (not the full SQL, which the driver embeds in the message)
            // so the upstream task-error log stays readable.
            throw new RuntimeException("SQL task " + task.getDebugInfo() + " failed: "
                    + NestedExceptionUtils.getMostSpecificCause(ex).getMessage(), ex);
        }
```

### `application.yaml`  *(remove the leftover SOAP wire-dump)*
Delete this block (it dumps the full SOAP request/response XML on every step):
```yaml
logging:
  level:
    # TEMP-DEBUG-RT: dump the raw SOAP request + response/fault to confirm multi-ref. REMOVE after diagnosis.
    org.apache.axis.transport.http: DEBUG
```

---

## Part 2 — The one real functional error: `ORA-01830` on task 229

Buried under the SQL spam, task **229**'s Dynamique SQL failed with **`ORA-01830: date format picture ends
before converting entire input string`**, so it produced **no blocs** ("has no blocs after processing") →
that dynamic table is **empty** in the output (the run still finalized `GENERATED` with 1 recorded error).

This is the **date/NLS class** (the query has the hardcoded `rf.FND_END_VALIDITY = '31/12/2199'` literal and
several `to_date(?)` binds). Two possible causes — the improved logging above will tell us which on the next
run:
1. **NLS not applied in the running build.** This repo already has
   `spring.datasource.hikari.connection-init-sql: ALTER SESSION SET NLS_DATE_FORMAT='DD/MM/YYYY'` and the
   `oracle.sql.DATE` bind. **Confirm both are present in the build you actually run** (your Windows repo).
   If the build is behind, apply `EOS_Quark_DynamicSQL_Date_NLS_Fix_14-07.md`.
2. **A date in-param typed `DATE_TIME`/`TEXT`** (not `DATE`) → bound as a raw string *with time*
   (`to_date('12/01/2023 00:00:00')`) which `ORA-01830`s even under `DD/MM/YYYY`. The new log line prints
   each param's `TYPE`, so a `(DATE_TIME)`/`(TEXT)` date param would be the smoking gun.

**Next step:** rebuild with these logging changes and re-run 339403 — the single ERROR line will show the
exact in-param (name, value, type) that broke `to_date`, and we fix precisely from there.

---

## Part 3 — Harmless noise (no action needed)
- `Zipkin … Connection refused :9411` — no local trace collector.
- `driver … not found, trying direct instantiation` — Hikari cosmetic; the Oracle connection succeeded.
- `Attachment support is disabled (javax.activation/javax.mail)` — fine (`responseAsURL=false` → inline base64).
- `Standard Commons Logging discovery … remove commons-logging.jar` — startup notice only.

## Files changed
- `infra/dao/impl/DynamicQueryPortImpl.java`, `service/task/impl/DynamiqueTaskProcessStrategy.java`,
  `service/impl/ProcessTasksServiceImpl.java`, `business/ProcessSqlBusiness.java`,
  `src/main/resources/application.yaml` (removed TEMP axis DEBUG).
