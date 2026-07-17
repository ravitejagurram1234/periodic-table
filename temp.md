# EOS Quark — row-count logging + `?` positional-binding fix (copy-paste ready)

**Repo:** `14-07 engine service repo/quark-engine`.
**Builds on** `EOS_Quark_Logging_Fixes_and_Run339403.md` (the logging-hygiene changes). These are the
*additional* changes: (1) log how many rows each SQL fetches, and (2) bind `?`-style gabarit SQL correctly.

## Why
- **Row count** — you asked to see how many rows a run's SQL fetched, so a legitimate "0 rows" (no data)
  can be told apart from a broken execution.
- **`?` binding (real defect)** — gabarit SQL comes in two styles: `:name`/`:number` (bound by name) and
  `?` (positional). The engine ran everything through `NamedParameterJdbcTemplate`, which binds `:name`
  only — so `?`-style SQL (e.g. task 229) bound **nothing** and could never execute correctly. .NET binds
  `?` **by position** (verbatim SQL, params added in `Get_In_Params` order, i-th `?` ← i-th in-param). This
  fix routes `?`-SQL to positional binding and leaves `:name`-SQL on named binding.

> ⚠️ **Not yet proven end-to-end.** Task 229's SQL has ~20 `?` but the run loaded only **3** in-params.
> Positional binding needs one value per `?`, so this run would still warn/`ORA-01008` on the mismatch.
> That is most likely **incomplete DEV data** for the suivi (production would associate ~20 params). The new
> `WARN` line + `SELECT COUNT(*) FROM qxp_asso_suivi_parametres WHERE id_suivi=<idSuivi>` will confirm. This
> change fixes the binding *mechanism* + adds the diagnostics; it does not by itself guarantee the row fills.

---

## 1. `TaskSqlDaoImpl.java`  *(paste whole file — the `?` positional-binding fix)*
Path: `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/TaskSqlDaoImpl.java`

```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.infra.dao.TaskSqlDao;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.util.List;
import java.util.Map;

/**
 * Executes gabarit/task SQL, binding the run in-params into the statement.
 *
 * <p>Gabarit SQL comes in two placeholder styles across tasks:
 * <ul>
 *   <li><b>{@code ?} positional markers</b> — bound BY POSITION: the i-th {@code ?} takes the i-th
 *       in-param. The in-param map preserves the {@code Get_In_Params} cursor order, so its
 *       {@code values()} are already in placeholder order. A value reused across several {@code ?}
 *       appears as several consecutive in-param rows (same value, distinct names).</li>
 *   <li><b>{@code :name} / {@code :number} markers</b> — bound BY NAME.</li>
 * </ul>
 */
@Repository
@Slf4j
public class TaskSqlDaoImpl implements TaskSqlDao {

    private final NamedParameterJdbcTemplate namedJdbcTemplate;
    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public TaskSqlDaoImpl(DataSource dataSource) {
        this.namedJdbcTemplate = new NamedParameterJdbcTemplate(dataSource);
        this.jdbcTemplate = new JdbcTemplate(dataSource);
    }

    @Override
    public List<Map<String, Object>> executeSql(String sql, Map<String, Object> parameters) {
        int placeholders = countPositionalPlaceholders(sql);

        if (placeholders > 0) {
            // Positional binding: values in Get_In_Params order map left-to-right onto the ? markers.
            Object[] args = parameters.values().toArray();
            if (placeholders != args.length) {
                log.warn("SQL uses {} positional (?) placeholders but {} in-params were provided; "
                        + "positional binding requires an exact match", placeholders, args.length);
            }
            log.debug("Executing task SQL with {} positional (?) parameters", args.length);
            return jdbcTemplate.queryForList(sql, args);
        }

        log.debug("Executing task SQL with {} named parameters", parameters.size());
        return namedJdbcTemplate.queryForList(sql, parameters);
    }

    /** Count {@code ?} bind markers, ignoring string literals and comments so a literal/comment
     *  {@code ?} is not mistaken for a placeholder. Zero means the SQL uses named ({@code :x}) binds. */
    private static int countPositionalPlaceholders(String sql) {
        String stripped = sql
                .replaceAll("'(?:[^']|'')*'", "")   // single-quoted string literals
                .replaceAll("--[^\r\n]*", "")        // line comments
                .replaceAll("(?s)/\\*.*?\\*/", "");  // block comments
        return (int) stripped.chars().filter(c -> c == '?').count();
    }
}
```

---

## 2. Row-count logging  *(2 snippets — add one INFO line each)*

### `DynamiqueTaskProcessStrategy.java` — Stage 1 (`process(...)`)
Add the `log.info(...)` immediately after the `executeQuery(...)` call:
```java
            List<Map<String, Object>> rows = dynamicQueryPort.executeQuery(

                    task.getSql(), task.getRun().getInParams());

            log.info("Dynamic task [{}] (run [{}]) SQL fetched {} rows",

                    task.getId(), task.getRun().getId(), rows != null ? rows.size() : 0);

            if (rows != null && !rows.isEmpty()) {
```

### `ProcessSqlBusiness.java` — `execute(TaskSql)`
Add the `log.info(...)` immediately after the `executeSql(...)` call:
```java
            List<Map<String, Object>> rows = taskSqlDao.executeSql(task.getSql(), parameters);

            log.info("SQL task [{}] (run [{}]) fetched {} rows",
                    task.getId(), task.getRun().getId(), rows.size());

            if (rows.isEmpty()) {
                log.warn("No SQL data returned for task {}", task.getId());
            } else {
                addBlocs(task, rows);
            }
```

---

## Apply & verify
1. Paste §1 (whole `TaskSqlDaoImpl`), add the two §2 log lines. (All already applied in the 14-07 copy.)
2. `mvn clean install`.
3. Re-run a Dynamique run and read the new lines:
   - `Dynamic task [229] (run [339403]) SQL fetched N rows` → execution succeeded, N rows.
   - If you instead see `SQL uses X positional (?) placeholders but Y in-params were provided` → the
     suivi's parameter associations don't match the SQL's `?` count (run the `qxp_asso_suivi_parametres`
     count query above to confirm it's DEV data vs. a deeper mapping question).

## Files changed
- `infra/dao/impl/TaskSqlDaoImpl.java` (`?` positional binding + placeholder-count warning)
- `service/task/impl/DynamiqueTaskProcessStrategy.java` (row-count INFO)
- `business/ProcessSqlBusiness.java` (row-count INFO)
