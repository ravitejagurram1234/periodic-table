# EOS Quark — Audit NULL-`id_suivi` fix + corrected test-run query (copy-paste ready)

**Repo:** `14-07 engine service repo/quark-engine`.

## Brief: issues & fixes

| # | Issue (from runs 493497 / 470017) | Kind | Fix |
|---|---|---|---|
| **A** | **Run finalize rolls back on an early failure.** When a run fails *before* its properties load, `run.getRunProperties()` is null, so `AuditDaoImpl` bound `p_id_suivi = NULL` into `QXP_AUDIT_RUN.ID_SUIVI` (a `NOT NULL` column) → `ORA-01400`. Because `EndRunBusiness.execute` is one `@Transactional` unit, the audit failure **rolled back the status update + error insert**, the retry repeated it, and errors were double-inserted. | 🔴 code | Bind `id_suivi = 0` (not NULL) when properties are absent — the audit then inserts and the finalize commits. |
| **B** | **493497** points at gabarit `161`, which exists but is **`is_actif = 0`**. `Get_Run_Properties` (no `is_actif` filter) loads, but `Get_Gabarit` (`WHERE is_actif = 1`) finds nothing → run fails at load. | 🟠 data / query | Query fix: require the run's gabarit be `is_actif = 1`. |
| **C** | **470017** has **no `Get_Run_Properties` row** — its own `r.id_suivi → suivi → gabarit/langue/asso` chain is incomplete in DEV. The earlier query only checked the *task* linkage (`s.id_run_suivant`), not the *load* linkage (`r.id_suivi = s.id_suivi`). | 🟠 data / query | Query fix: anchor on the `Get_Run_Properties` join chain so only loadable runs are returned. |

**Why fix A the way we did (verified against .NET):** .NET's `End_Run` is *also* a single transaction whose audit failure rolls back + re-throws — so making the audit "best-effort" would **diverge** from .NET. The real difference is that .NET constructs `Run` with `new Run_Properties()` whose `int _id_Suivi` defaults to **0**, so an early-failed run audits with `p_id_suivi = 0` (a non-null value) and commits cleanly. Binding `0` in Java is exact parity — the audit *succeeds* instead of failing, so nothing rolls back. (.NET refs: `Proxy_Run.cs:284-351` single tx; `Proxy_Audit.cs:96-97` binds `Run.Properties.ID_Suivi`; `Run_Base.cs:80-86` default `Run_Properties`; `Run_Properties.cs:23` `int _id_Suivi` default 0.)

> Note: fix A only changes behavior for runs that fail *before* properties load; a normal run already has a real `id_suivi`, so its audit was always fine (493497 audited OK). After the fix, an unloadable run (like 470017) still ends `ERROR` — but cleanly, with the status/error rows committed and one audit row (`id_suivi = 0`), no rollback, no retry, no duplicate errors.

---

## Fix A — `AuditDaoImpl.java` *(paste whole file)*
Path: `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/AuditDaoImpl.java`

```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.infra.dao.AuditDao;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.Duration;

/**
 * Calls QXP_PK_AUDIT.InsertAuditRun (PROCEDURE, 8 IN params).
 * Cross-reference: .NET Proxy_Audit.InsertAuditRun.
 */
@Repository
@Slf4j
public class AuditDaoImpl implements AuditDao {

    /** p_message is VARCHAR2 — keep within Oracle's standard VARCHAR2 limit. */
    private static final int MAX_MESSAGE_SIZE = 4000;

    private final SimpleJdbcCall insertAuditRunCall;

    @Autowired
    public AuditDaoImpl(DataSource dataSource) {
        this.insertAuditRunCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_AUDIT")
                .withProcedureName("InsertAuditRun")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlParameter("p_id_run", Types.NUMERIC),
                        new SqlParameter("p_id_suivi", Types.NUMERIC),
                        new SqlParameter("p_run_type", Types.VARCHAR),
                        new SqlParameter("p_start_date", Types.TIMESTAMP),
                        new SqlParameter("p_end_date", Types.TIMESTAMP),
                        new SqlParameter("p_duration", Types.NUMERIC),
                        new SqlParameter("p_end_status", Types.VARCHAR),
                        new SqlParameter("p_message", Types.VARCHAR)
                );
    }

    @Override
    public void insertAuditRun(Run run, String message) {
        // p_duration stores only the SUB-SECOND millisecond COMPONENT (0-999), NOT total elapsed time —
        // this matches the existing QXP_AUDIT_RUN.DURATION contract.
        // ⚠️ Quirk: the stored DURATION is only the 0-999 ms part, not the total duration.
        int durationMs = 0;
        if (run.getStartDate() != null && run.getEndDate() != null) {
            durationMs = Duration.between(run.getStartDate(), run.getEndDate()).toMillisPart();
        }

        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_run", run.getId())
                // ID_SUIVI is NOT NULL. When a run fails before its properties are loaded there is no
                // suivi id, so bind the neutral 0 (the field's default) rather than SQL NULL — otherwise
                // the audit insert violates the constraint and rolls back the whole finalize.
                .addValue("p_id_suivi", run.getRunProperties() != null ? run.getRunProperties().getIdSuivi() : 0)
                .addValue("p_run_type", run.getRunProperties() != null ? run.getRunProperties().getRunType() : null)
                .addValue("p_start_date", run.getStartDate() != null ? Timestamp.valueOf(run.getStartDate()) : null)
                .addValue("p_end_date", run.getEndDate() != null ? Timestamp.valueOf(run.getEndDate()) : null)
                .addValue("p_duration", durationMs)
                // Bind the stable PascalCase status label (Generated/Error/...) that END_STATUS expects,
                // not the Java enum name() (TO_GENERATE/...). The spelling is a persistence contract.
                .addValue("p_end_status", run.getStatus() != null ? run.getStatus().getAuditStatusLabel() : null)
                .addValue("p_message", truncate(message, MAX_MESSAGE_SIZE));

        try {
            insertAuditRunCall.execute(params);
            log.info("Audit row inserted for run [{}]", run.getId());
        } catch (Exception e) {
            log.error("Failed to insert audit row for run [{}]: {}", run.getId(), e.getMessage(), e);
            throw new RuntimeException("Failed to insert audit row for run: " + run.getId(), e);
        }
    }

    private static String truncate(String value, int maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}
```

*(One line changed: `p_id_suivi` fallback `null` → `0`, plus an explanatory comment. `mvn clean install` still compiles; no test references this binding — needs the live re-run below to confirm on the wire.)*

---

## Corrected test-run query (fixes B & C)
Returns only runs that will actually **load** (`Get_Run_Properties` chain + active gabarit) **and** have TODO content tasks:

```sql
SELECT r.id_run,
       s.id_suivi,
       s.id_gabarit,
       g.nom                              AS gabarit_nom,
       s.id_type_rapport,                 -- 2 = Plaquette, 5 = DICI, ...
       r.id_statut_generation,            -- 1=ToGenerate 2=Generated 3=Error 4=Running
       COUNT(DISTINCT gt.id_tache)                                        AS nb_taches,
       COUNT(DISTINCT rt.id_tache)                                        AS nb_todo,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=1 THEN t.id_tache END)    AS nb_sql,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=0 THEN t.id_tache END)    AS nb_system,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=2 THEN t.id_tache END)    AS nb_document,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=4 THEN t.id_tache END)    AS nb_dynamique,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=5 THEN t.id_tache END)    AS nb_compartiment
FROM       qxp_run                 r
-- run must LOAD: mirror Get_Run_Properties + the is_actif that Get_Gabarit requires
JOIN       qxp_suivi               s   ON s.id_suivi = r.id_suivi
JOIN       qxp_gabarit             g   ON g.id_gabarit = s.id_gabarit
                                      AND g.is_actif   = 1              -- fixes 493497 (inactive gabarit)
                                      AND g.contenu IS NOT NULL         -- needed for pool upload / render
JOIN       qxp_ref_langue_document rld ON rld.id_langue_document = s.id_langue
JOIN       qxp_asso_fond_gabarit   afg ON afg.id_fnd_code     = s.id_fnd_code
                                      AND afg.id_gabarit      = s.id_gabarit
                                      AND afg.id_type_rapport = s.id_type_rapport
                                      AND afg.id_langue       = s.id_langue
-- run must have TODO tasks on that same gabarit
JOIN       qxp_asso_gabarit_taches gt  ON gt.id_gabarit = s.id_gabarit
JOIN       qxp_tache               t   ON t.id_tache = gt.id_tache AND t.is_actif = 1
LEFT JOIN  qxp_asso_run_taches     rt  ON rt.id_run = r.id_run AND rt.id_tache = gt.id_tache
GROUP BY r.id_run, s.id_suivi, s.id_gabarit, g.nom, s.id_type_rapport, r.id_statut_generation
HAVING   COUNT(DISTINCT rt.id_tache) > 0
ORDER BY nb_sql DESC, nb_dynamique DESC, nb_taches DESC;
```
- If `HAVING COUNT(rt) > 0` returns nothing (TODO rows may be populated at run time), relax to `COUNT(DISTINCT gt.id_tache) > 0`.
- **Pre-flight a candidate** before running it: `SELECT id_gabarit, nom, is_actif, CASE WHEN contenu IS NULL THEN 'NULL' ELSE 'present' END FROM qxp_gabarit WHERE id_gabarit = <run's id_gabarit>;`
- **Or just re-run 488654** — proven active gabarit + 24 content tasks; the lowest-risk way to exercise fixes #1/#2/#4.

---

## Apply & test
1. Paste `AuditDaoImpl.java` (already applied in the 14-07 working copy).
2. `mvn clean install` → `BUILD SUCCESS`.
3. Run a candidate from the corrected query (or 488654). Expect: content-ful runs finalize `GENERATED`; and any run that still can't load ends `ERROR` **cleanly** — one status update, one error, one audit row (`id_suivi = 0`), no `ORA-01400`, no rollback/retry.

## File changed
- `src/main/java/.../infra/dao/impl/AuditDaoImpl.java` (fix A — `p_id_suivi` fallback `null` → `0`).
