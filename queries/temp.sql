/* ---------------------------------------------------------------------------
   QOFF-01D - First Wave 10E SQL-only diagnostic candidates
   Export: planning/05_simple_sql_diagnostic_candidates.csv

   Read-only candidate selector. It returns untouched status-5 runs whose
   selected work consists only of active, configured, non-empty type-1 SQL
   tasks. It excludes DOC EOS/PDF, previous-QXP, dynamic, compartment and
   unknown tasks. The exact same selected tasks must have produced a non-zero
   update in the clean successful previous run.

   A returned row is not execution approval. Return the bounded rows for
   review, then set RUN_ID and require QOFF-02B=PASS immediately before GET/POST.
   Current business data can still produce zero updates; QOFF-17 proves the
   actual Java run after execution.
   --------------------------------------------------------------------------- */
WITH task_profile AS (
    SELECT
        run_task.id_run,
        COUNT(DISTINCT run_task.id_tache) AS selected_task_count,
        COUNT(DISTINCT CASE
            WHEN task.is_actif = 1
             AND gabarit_task.id_tache IS NOT NULL
             AND task.id_type_tache = 1
             AND task.sql IS NOT NULL
             AND DBMS_LOB.GETLENGTH(task.sql) > 0
            THEN task.id_tache
        END) AS valid_sql_task_count,
        COUNT(DISTINCT CASE
            WHEN task.id_tache IS NULL
              OR NVL(task.is_actif, 0) <> 1
              OR gabarit_task.id_tache IS NULL
              OR NVL(task.id_type_tache, -1) <> 1
              OR task.sql IS NULL
              OR DBMS_LOB.GETLENGTH(task.sql) = 0
            THEN run_task.id_tache
        END) AS invalid_or_non_sql_task_count
    FROM qxp_asso_run_taches run_task
    JOIN qxp_run run_record
      ON run_record.id_run = run_task.id_run
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    LEFT JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
    LEFT JOIN qxp_asso_gabarit_taches gabarit_task
      ON gabarit_task.id_gabarit = suivi.id_gabarit
     AND gabarit_task.id_tache = task.id_tache
    GROUP BY run_task.id_run
)
SELECT
    run_record.id_run AS swagger_run_id,
    run_record.id_suivi,
    suivi.id_type_rapport,
    report_type.libelle AS report_type_label,
    suivi.id_gabarit,
    run_record.gabarit_source,
    task_profile.selected_task_count,
    task_profile.valid_sql_task_count,
    suivi.id_run_precedent AS baseline_run_id,
    TO_CHAR(
        run_record.date_creation_run,
        'YYYY-MM-DD HH24:MI:SS'
    ) AS run_creation_time,
    TO_CHAR(
        previous_run.date_fin_generation,
        'YYYY-MM-DD HH24:MI:SS'
    ) AS baseline_completion_time,
    'CANDIDATE ONLY - RUN QOFF-02B BEFORE GET/POST'
        AS required_next_check
FROM qxp_run run_record
JOIN qxp_suivi suivi
  ON suivi.id_suivi = run_record.id_suivi
 AND suivi.id_run_suivant = run_record.id_run
 AND suivi.id_statut_generation = 1
JOIN qxp_gabarit gabarit
  ON gabarit.id_gabarit = suivi.id_gabarit
 AND gabarit.is_actif = 1
JOIN task_profile
  ON task_profile.id_run = run_record.id_run
JOIN qxp_run previous_run
  ON previous_run.id_run = suivi.id_run_precedent
LEFT JOIN qxp_ref_type_rapport report_type
  ON report_type.id_type_rapport = suivi.id_type_rapport
WHERE run_record.id_statut_generation = 5
  AND run_record.gabarit_source IN (1, 2, 3, 4)
  AND (
        run_record.date_planification IS NULL
        OR run_record.date_planification < SYSDATE
      )
  AND run_record.date_debut_generation IS NULL
  AND run_record.date_fin_generation IS NULL
  AND run_record.id_doc_qxp IS NULL
  AND run_record.id_doc_pdf IS NULL
  AND run_record.id_doc_doc IS NULL
  AND NVL(DBMS_LOB.GETLENGTH(run_record.log_trace), 0) = 0
  AND NOT EXISTS (
        SELECT 1
        FROM qxp_run_error current_error
        WHERE current_error.id_run = run_record.id_run
      )
  AND (
        run_record.gabarit_source <> 1
        OR (
            gabarit.contenu IS NOT NULL
            AND DBMS_LOB.GETLENGTH(gabarit.contenu) > 0
        )
      )
  AND (
        SELECT COUNT(*)
        FROM qxp_asso_fond_gabarit property_mapping
        WHERE property_mapping.id_type_rapport = suivi.id_type_rapport
          AND property_mapping.id_fnd_code = suivi.id_fnd_code
          AND property_mapping.id_langue = suivi.id_langue
          AND property_mapping.id_gabarit = suivi.id_gabarit
      ) = 1
  AND task_profile.selected_task_count > 0
  AND task_profile.valid_sql_task_count > 0
  AND task_profile.invalid_or_non_sql_task_count = 0
  AND previous_run.id_statut_generation = 2
  AND previous_run.id_doc_qxp IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM qxp_run_error baseline_error
        WHERE baseline_error.id_run = previous_run.id_run
      )
  AND REGEXP_LIKE(
        previous_run.log_trace,
        ', update=[1-9][[:digit:]]*,'
      )
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
ORDER BY
    CASE WHEN run_record.gabarit_source = 1 THEN 0 ELSE 1 END,
    run_record.date_creation_run DESC,
    run_record.id_run DESC
FETCH FIRST 20 ROWS ONLY;

