/*
===============================================================================
EOS Quark Engine - first simple diagnostic run selection
===============================================================================

Purpose
  Find an untouched status-5 run for the first Wave 10E diagnostic execution.

Strict candidate requirements
  - current QXP_RUN status is 5;
  - current QXP_SUIVI status is 1 and ID_RUN_SUIVANT points to the run;
  - no generation timestamps, generated-document links, persisted run errors,
    or persisted execution trace exist;
  - exactly one run-property association exists;
  - the configured gabarit is active and source 1 content is present when used;
  - every selected task is active and belongs to the run gabarit;
  - at least one selected type-1 SQL/value task has non-empty SQL;
  - no selected type-2 document, type-3 previous-QXP, type-4 dynamic, or
    type-5 compartment task exists;
  - no selected unknown task type exists, so the candidate is genuinely
    SQL/value-only;
  - the successful previous run used the exact same selected task IDs;
  - the previous run has no persisted run errors and its trace proves at least
    one non-zero update;
  - SQL text, bind values, parameter values, and document payloads are never
    selected.

Safety
  - All statements in this file are read-only SELECT statements.
  - A QOFF-01D result is only a candidate. QOFF-02B and QOFF-02C must both pass
    immediately before the Swagger POST.
  - A same-task baseline with a non-zero update is the strongest available
    pre-run evidence, but current Oracle data can still make this run update
    zero blocks. Only the post-run QOFF-17 result proves the actual run.
  - Do not execute a fallback/config-only candidate without reviewing it first.
===============================================================================
*/

SET VERIFY ON

DEFINE CANDIDATE_LOOKBACK_DAYS = 7300
DEFINE CANDIDATES_PER_REPORT_TYPE = 10
DEFINE RUN_ID = 0


/* ---------------------------------------------------------------------------
   QOFF-01D - Strict status-5 simple SQL-only diagnostic candidates
   Export: planning/05_simple_sql_diagnostic_candidates.csv

   An empty result is a valid outcome. Do not weaken this query or update an
   old run. Use the guarded old-UI flow when no suitable status-5 row exists.
   --------------------------------------------------------------------------- */
WITH selected_task_profile AS (
    SELECT
        run_record.id_run,
        COUNT(DISTINCT run_task.id_tache) AS selected_task_row_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
            THEN task.id_tache END) AS selected_active_configured_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache = 1
            THEN task.id_tache END) AS selected_sql_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache = 1
             AND task.sql IS NOT NULL
             AND DBMS_LOB.GETLENGTH(task.sql) > 0
            THEN task.id_tache END) AS selected_nonempty_sql_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache = 2
            THEN task.id_tache END) AS selected_document_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache = 3
            THEN task.id_tache END) AS selected_previous_qxp_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache = 4
            THEN task.id_tache END) AS selected_dynamic_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache = 5
            THEN task.id_tache END) AS selected_compartment_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND (task.id_type_tache IS NULL
                  OR task.id_type_tache NOT BETWEEN 1 AND 5)
            THEN task.id_tache END) AS selected_other_task_count,
        SUM(CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache = 1
             AND task.sql IS NOT NULL
            THEN DBMS_LOB.GETLENGTH(task.sql)
            ELSE 0 END) AS selected_total_sql_chars
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    JOIN qxp_asso_run_taches run_task
      ON run_task.id_run = run_record.id_run
    LEFT JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
    LEFT JOIN qxp_asso_gabarit_taches gabarit_task
      ON gabarit_task.id_gabarit = suivi.id_gabarit
     AND gabarit_task.id_tache = task.id_tache
    GROUP BY run_record.id_run
), candidate AS (
    SELECT
        run_record.id_run,
        run_record.id_suivi,
        suivi.id_type_rapport,
        report_type.libelle AS report_type_label,
        suivi.id_fnd_code,
        suivi.id_unit_code,
        suivi.id_langue,
        language.nom_langue,
        suivi.date_echeance,
        suivi.id_gabarit,
        run_record.gabarit_source,
        run_record.mode_compart,
        gabarit.pagination_double,
        NVL(gabarit.store_data_type, 0) AS store_data_type,
        task_profile.selected_task_row_count,
        task_profile.selected_active_configured_task_count,
        task_profile.selected_sql_task_count,
        task_profile.selected_nonempty_sql_task_count,
        task_profile.selected_document_task_count,
        task_profile.selected_previous_qxp_task_count,
        task_profile.selected_dynamic_task_count,
        task_profile.selected_compartment_task_count,
        task_profile.selected_other_task_count,
        task_profile.selected_total_sql_chars,
        suivi.id_run_precedent AS baseline_run_id,
        previous_run.id_doc_qxp AS baseline_qxp_document_id,
        previous_run.id_doc_pdf AS baseline_pdf_document_id,
        previous_run.id_doc_doc AS baseline_doc_document_id,
        TO_CHAR(previous_run.date_fin_generation, 'YYYY-MM-DD HH24:MI:SS')
            AS baseline_end_time,
        run_record.date_creation_run,
        run_record.date_planification,
        CASE
            WHEN previous_run.id_statut_generation = 2
             AND previous_run.id_doc_qxp IS NOT NULL
             AND NOT EXISTS (
                    SELECT current_task.id_tache
                    FROM qxp_asso_run_taches current_task
                    WHERE current_task.id_run = run_record.id_run
                    MINUS
                    SELECT baseline_task.id_tache
                    FROM qxp_asso_run_taches baseline_task
                    WHERE baseline_task.id_run = previous_run.id_run
                 )
             AND NOT EXISTS (
                    SELECT baseline_task.id_tache
                    FROM qxp_asso_run_taches baseline_task
                    WHERE baseline_task.id_run = previous_run.id_run
                    MINUS
                    SELECT current_task.id_tache
                    FROM qxp_asso_run_taches current_task
                    WHERE current_task.id_run = run_record.id_run
                 )
             AND NOT EXISTS (
                    SELECT 1
                    FROM qxp_run_error baseline_error
                    WHERE baseline_error.id_run = previous_run.id_run
                 )
             AND REGEXP_LIKE(
                    previous_run.log_trace,
                    ', update=[1-9][[:digit:]]*,'
                 )
            THEN 1 ELSE 0
        END AS baseline_same_tasks_nonzero_update
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
     AND suivi.id_run_suivant = run_record.id_run
     AND suivi.id_statut_generation = 1
    JOIN qxp_gabarit gabarit
      ON gabarit.id_gabarit = suivi.id_gabarit
     AND gabarit.is_actif = 1
    JOIN selected_task_profile task_profile
      ON task_profile.id_run = run_record.id_run
    LEFT JOIN qxp_run previous_run
      ON previous_run.id_run = suivi.id_run_precedent
    LEFT JOIN qxp_ref_type_rapport report_type
      ON report_type.id_type_rapport = suivi.id_type_rapport
    LEFT JOIN qxp_ref_langue_document language
      ON language.id_langue_document = suivi.id_langue
    WHERE run_record.id_statut_generation = 5
      AND run_record.gabarit_source IN (1, 2, 3, 4)
      AND (run_record.date_planification IS NULL
           OR run_record.date_planification < SYSDATE)
      AND run_record.date_debut_generation IS NULL
      AND run_record.date_fin_generation IS NULL
      AND run_record.id_doc_qxp IS NULL
      AND run_record.id_doc_pdf IS NULL
      AND run_record.id_doc_doc IS NULL
      AND (run_record.log_trace IS NULL
           OR DBMS_LOB.GETLENGTH(run_record.log_trace) = 0)
      AND NOT EXISTS (
            SELECT 1
            FROM qxp_run_error current_error
            WHERE current_error.id_run = run_record.id_run
          )
      AND run_record.date_creation_run >= SYSDATE - &CANDIDATE_LOOKBACK_DAYS
      AND (run_record.gabarit_source <> 1
           OR (gabarit.contenu IS NOT NULL
               AND DBMS_LOB.GETLENGTH(gabarit.contenu) > 0))
      AND (SELECT COUNT(*)
           FROM qxp_asso_fond_gabarit association_row
           WHERE association_row.id_type_rapport = suivi.id_type_rapport
             AND association_row.id_fnd_code = suivi.id_fnd_code
             AND association_row.id_langue = suivi.id_langue
             AND association_row.id_gabarit = suivi.id_gabarit) = 1
      AND task_profile.selected_task_row_count
            = task_profile.selected_active_configured_task_count
      AND task_profile.selected_sql_task_count > 0
      AND task_profile.selected_nonempty_sql_task_count
            = task_profile.selected_sql_task_count
      AND task_profile.selected_document_task_count = 0
      AND task_profile.selected_previous_qxp_task_count = 0
      AND task_profile.selected_dynamic_task_count = 0
      AND task_profile.selected_compartment_task_count = 0
      AND task_profile.selected_other_task_count = 0
), ranked AS (
    SELECT
        candidate.*,
        ROW_NUMBER() OVER (
            PARTITION BY candidate.id_type_rapport
            ORDER BY
                CASE WHEN candidate.gabarit_source = 1 THEN 0 ELSE 1 END,
                candidate.selected_other_task_count,
                candidate.date_creation_run DESC,
                candidate.id_run DESC
        ) AS candidate_rank
    FROM candidate
    WHERE candidate.baseline_same_tasks_nonzero_update = 1
)
SELECT
    'SIMPLE_SQL_DIAGNOSTIC' AS scenario_class,
    candidate_rank,
    id_run AS swagger_run_id,
    id_suivi,
    id_type_rapport,
    report_type_label,
    id_fnd_code,
    id_unit_code,
    id_langue,
    nom_langue,
    TO_CHAR(date_echeance, 'YYYY-MM-DD HH24:MI:SS') AS due_date,
    id_gabarit,
    gabarit_source,
    mode_compart,
    pagination_double,
    store_data_type,
    selected_task_row_count,
    selected_active_configured_task_count,
    selected_sql_task_count,
    selected_nonempty_sql_task_count,
    selected_other_task_count,
    selected_total_sql_chars,
    baseline_run_id,
    baseline_qxp_document_id,
    baseline_pdf_document_id,
    baseline_doc_document_id,
    baseline_end_time,
    'EXPECTED: same selected tasks previously produced a non-zero update; QOFF-17 must prove this run'
        AS expected_update_proof,
    TO_CHAR(date_creation_run, 'YYYY-MM-DD HH24:MI:SS') AS creation_time,
    TO_CHAR(date_planification, 'YYYY-MM-DD HH24:MI:SS') AS planned_time,
    'RUN QOFF-02B AND QOFF-02C IMMEDIATELY BEFORE POST' AS next_action
FROM ranked
WHERE candidate_rank <= &CANDIDATES_PER_REPORT_TYPE
ORDER BY id_type_rapport, candidate_rank;


/* ---------------------------------------------------------------------------
   QOFF-02C - Revalidate the selected simple SQL-only diagnostic run
   Export: run_<ID>/00B_simple_sql_diagnostic_validation.csv

   Set RUN_ID first. DIAGNOSTIC_CANDIDATE_RESULT must be PASS. QOFF-02B must
   independently return BASIC_ADMISSION_RESULT=PASS.
   --------------------------------------------------------------------------- */
WITH selected_task_profile AS (
    SELECT
        run_record.id_run,
        COUNT(DISTINCT run_task.id_tache) AS selected_task_row_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
            THEN task.id_tache END) AS selected_active_configured_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache = 1
            THEN task.id_tache END) AS selected_sql_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache = 1
             AND task.sql IS NOT NULL
             AND DBMS_LOB.GETLENGTH(task.sql) > 0
            THEN task.id_tache END) AS selected_nonempty_sql_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache BETWEEN 2 AND 5
            THEN task.id_tache END) AS selected_excluded_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND (task.id_type_tache IS NULL
                  OR task.id_type_tache NOT BETWEEN 1 AND 5)
            THEN task.id_tache END) AS selected_other_task_count
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    LEFT JOIN qxp_asso_run_taches run_task
      ON run_task.id_run = run_record.id_run
    LEFT JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
    LEFT JOIN qxp_asso_gabarit_taches gabarit_task
      ON gabarit_task.id_gabarit = suivi.id_gabarit
     AND gabarit_task.id_tache = task.id_tache
    WHERE run_record.id_run = &RUN_ID
    GROUP BY run_record.id_run
), run_context AS (
    SELECT
        run_record.id_run,
        run_record.id_suivi,
        run_record.id_statut_generation,
        suivi.id_statut_generation AS suivi_status,
        suivi.id_run_suivant,
        suivi.id_type_rapport,
        suivi.id_gabarit,
        run_record.gabarit_source,
        gabarit.is_actif AS gabarit_is_active,
        CASE WHEN gabarit.contenu IS NULL THEN 0
             ELSE DBMS_LOB.GETLENGTH(gabarit.contenu)
        END AS configured_gabarit_bytes,
        run_record.date_planification,
        run_record.date_debut_generation,
        run_record.date_fin_generation,
        run_record.id_doc_qxp,
        run_record.id_doc_pdf,
        run_record.id_doc_doc,
        CASE WHEN run_record.log_trace IS NULL THEN 0
             ELSE DBMS_LOB.GETLENGTH(run_record.log_trace)
        END AS current_trace_chars,
        (SELECT COUNT(*)
         FROM qxp_run_error current_error
         WHERE current_error.id_run = run_record.id_run) AS current_error_count,
        suivi.id_run_precedent AS baseline_run_id,
        previous_run.id_statut_generation AS baseline_status,
        previous_run.id_doc_qxp AS baseline_qxp_document_id,
        task_profile.selected_task_row_count,
        task_profile.selected_active_configured_task_count,
        task_profile.selected_sql_task_count,
        task_profile.selected_nonempty_sql_task_count,
        task_profile.selected_excluded_task_count,
        task_profile.selected_other_task_count,
        (SELECT COUNT(*)
         FROM qxp_asso_fond_gabarit association_row
         WHERE association_row.id_type_rapport = suivi.id_type_rapport
           AND association_row.id_fnd_code = suivi.id_fnd_code
           AND association_row.id_langue = suivi.id_langue
           AND association_row.id_gabarit = suivi.id_gabarit)
            AS run_property_match_count,
        CASE
            WHEN previous_run.id_statut_generation = 2
             AND previous_run.id_doc_qxp IS NOT NULL
             AND NOT EXISTS (
                    SELECT current_task.id_tache
                    FROM qxp_asso_run_taches current_task
                    WHERE current_task.id_run = run_record.id_run
                    MINUS
                    SELECT baseline_task.id_tache
                    FROM qxp_asso_run_taches baseline_task
                    WHERE baseline_task.id_run = previous_run.id_run
                 )
             AND NOT EXISTS (
                    SELECT baseline_task.id_tache
                    FROM qxp_asso_run_taches baseline_task
                    WHERE baseline_task.id_run = previous_run.id_run
                    MINUS
                    SELECT current_task.id_tache
                    FROM qxp_asso_run_taches current_task
                    WHERE current_task.id_run = run_record.id_run
                 )
             AND NOT EXISTS (
                    SELECT 1
                    FROM qxp_run_error baseline_error
                    WHERE baseline_error.id_run = previous_run.id_run
                 )
             AND REGEXP_LIKE(
                    previous_run.log_trace,
                    ', update=[1-9][[:digit:]]*,'
                 )
            THEN 1 ELSE 0
        END AS baseline_same_tasks_nonzero_update
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    JOIN qxp_gabarit gabarit
      ON gabarit.id_gabarit = suivi.id_gabarit
    JOIN selected_task_profile task_profile
      ON task_profile.id_run = run_record.id_run
    LEFT JOIN qxp_run previous_run
      ON previous_run.id_run = suivi.id_run_precedent
    WHERE run_record.id_run = &RUN_ID
)
SELECT
    context.id_run,
    context.id_suivi,
    context.id_type_rapport,
    context.id_gabarit,
    context.gabarit_source,
    context.selected_task_row_count,
    context.selected_active_configured_task_count,
    context.selected_sql_task_count,
    context.selected_nonempty_sql_task_count,
    context.selected_excluded_task_count,
    context.selected_other_task_count,
    context.current_trace_chars,
    context.current_error_count,
    context.baseline_run_id,
    context.baseline_status,
    context.baseline_qxp_document_id,
    context.baseline_same_tasks_nonzero_update,
    CASE
        WHEN NVL(context.id_statut_generation, -1) <> 5
          THEN 'STOP: QXP_RUN status is not 5'
        WHEN NVL(context.suivi_status, -1) <> 1
          THEN 'STOP: QXP_SUIVI status is not 1'
        WHEN NVL(context.id_run_suivant, -1) <> context.id_run
          THEN 'STOP: run is not ID_RUN_SUIVANT'
        WHEN NVL(context.gabarit_source, -1) NOT IN (1, 2, 3, 4)
          THEN 'STOP: invalid gabarit source'
        WHEN NVL(context.gabarit_is_active, 0) <> 1
          THEN 'STOP: gabarit is inactive'
        WHEN context.gabarit_source = 1
         AND context.configured_gabarit_bytes <= 0
          THEN 'STOP: source-1 gabarit content is empty'
        WHEN context.run_property_match_count <> 1
          THEN 'STOP: run-property association count is not 1'
        WHEN context.date_planification IS NOT NULL
         AND context.date_planification >= SYSDATE
          THEN 'STOP: run is not yet eligible by planning time'
        WHEN context.date_debut_generation IS NOT NULL
          OR context.date_fin_generation IS NOT NULL
          THEN 'STOP: run already has generation timestamps'
        WHEN context.id_doc_qxp IS NOT NULL
          OR context.id_doc_pdf IS NOT NULL
          OR context.id_doc_doc IS NOT NULL
          THEN 'STOP: run already has generated-document links'
        WHEN context.current_trace_chars <> 0
          THEN 'STOP: run already has a persisted execution trace'
        WHEN context.current_error_count <> 0
          THEN 'STOP: run already has persisted run errors'
        WHEN context.selected_task_row_count
             <> context.selected_active_configured_task_count
          THEN 'STOP: selected task is inactive or not configured for gabarit'
        WHEN context.selected_sql_task_count <= 0
          THEN 'STOP: no selected SQL/value task'
        WHEN context.selected_nonempty_sql_task_count
             <> context.selected_sql_task_count
          THEN 'STOP: selected SQL task has empty SQL'
        WHEN context.selected_excluded_task_count <> 0
          THEN 'STOP: document/previous-QXP/dynamic/compartment task is selected'
        WHEN context.selected_other_task_count <> 0
          THEN 'STOP: unknown task type is selected'
        WHEN context.baseline_same_tasks_nonzero_update <> 1
          THEN 'STOP: no clean same-task successful baseline with non-zero update'
        ELSE 'PASS'
    END AS diagnostic_candidate_result,
    'QOFF-02B BASIC_ADMISSION_RESULT must independently be PASS'
        AS mandatory_next_check
FROM run_context context;


/* ---------------------------------------------------------------------------
   QOFF-02D - Selected task metadata for the chosen diagnostic run
   Export: run_<ID>/00C_selected_diagnostic_tasks.csv

   SQL text is intentionally excluded. SQL_LENGTH proves configuration only.
   --------------------------------------------------------------------------- */
SELECT
    run_task.id_run,
    task.id_tache,
    task.id_type_tache,
    task_type.libelle AS task_type_label,
    task.is_actif,
    CASE WHEN gabarit_task.id_tache IS NULL THEN 0 ELSE 1 END
        AS configured_for_run_gabarit,
    CASE WHEN task.sql IS NULL THEN NULL
         ELSE DBMS_LOB.GETLENGTH(task.sql)
    END AS sql_length,
    task.output_data_type,
    task.nb_decimal,
    task.decimal_significative,
    task.afficher_zero,
    task.store_data,
    task.conserver_style,
    LENGTH(task.bloc_source) AS bloc_source_length,
    LENGTH(task.bloc_destination) AS bloc_destination_length
FROM qxp_run run_record
JOIN qxp_suivi suivi
  ON suivi.id_suivi = run_record.id_suivi
JOIN qxp_asso_run_taches run_task
  ON run_task.id_run = run_record.id_run
JOIN qxp_tache task
  ON task.id_tache = run_task.id_tache
LEFT JOIN qxp_asso_gabarit_taches gabarit_task
  ON gabarit_task.id_gabarit = suivi.id_gabarit
 AND gabarit_task.id_tache = task.id_tache
LEFT JOIN qxp_ref_type_tache task_type
  ON task_type.id_type_tache = task.id_type_tache
WHERE run_record.id_run = &RUN_ID
ORDER BY task.id_tache;


PROMPT Required before Swagger POST:
PROMPT 1. QOFF-02C DIAGNOSTIC_CANDIDATE_RESULT = PASS.
PROMPT 2. Main evidence query QOFF-02B BASIC_ADMISSION_RESULT = PASS.
PROMPT 3. Run QOFF-03, QOFF-04, QOFF-05, QOFF-05A, QOFF-07 and QOFF-07B.
PROMPT 4. Rabbit remains disabled.
PROMPT 5. Call properties GET once, then process POST once.
