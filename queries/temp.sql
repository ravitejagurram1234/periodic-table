/* ---------------------------------------------------------------------------
   QOFF-01E - Reusable historical SQL-only baselines for old-UI creation
   Export: planning/06_reusable_sql_only_baselines.csv

   Use only when QOFF-01D returns no rows. This read-only selector finds a
   successful SQL-only previous run whose suivi is unlocked and currently has
   no ID_RUN_SUIVANT, so the normal old UI may create a fresh run for it.

   A returned BASELINE_RUN_ID is never a Swagger execution ID. Return these
   bounded rows for review before operating the UI. Do not start or reserve a
   run as part of this query.
   --------------------------------------------------------------------------- */
WITH baseline_task_profile AS (
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
    baseline_run.id_run AS baseline_run_id,
    suivi.id_suivi,
    suivi.id_type_rapport,
    report_type.libelle AS report_type_label,
    suivi.id_fnd_code,
    suivi.id_unit_code,
    suivi.id_langue,
    TO_CHAR(suivi.date_echeance, 'YYYY-MM-DD HH24:MI:SS') AS due_date,
    suivi.id_gabarit,
    baseline_run.gabarit_source,
    task_profile.selected_task_count,
    task_profile.valid_sql_task_count,
    TO_CHAR(
        baseline_run.date_fin_generation,
        'YYYY-MM-DD HH24:MI:SS'
    ) AS baseline_completion_time,
    'BASELINE ONLY - DO NOT POST THIS ID' AS required_action
FROM qxp_suivi suivi
JOIN qxp_run baseline_run
  ON baseline_run.id_run = suivi.id_run_precedent
 AND baseline_run.id_statut_generation = 2
JOIN baseline_task_profile task_profile
  ON task_profile.id_run = baseline_run.id_run
JOIN qxp_gabarit gabarit
  ON gabarit.id_gabarit = suivi.id_gabarit
 AND gabarit.is_actif = 1
JOIN qxp_document qxp_document
  ON qxp_document.id_document = baseline_run.id_doc_qxp
LEFT JOIN qxp_ref_type_rapport report_type
  ON report_type.id_type_rapport = suivi.id_type_rapport
WHERE suivi.id_run_suivant IS NULL
  AND NVL(suivi.is_locked, 0) = 0
  AND baseline_run.id_doc_qxp IS NOT NULL
  AND qxp_document.contenu IS NOT NULL
  AND DBMS_LOB.GETLENGTH(qxp_document.contenu) > 0
  AND baseline_run.date_fin_generation IS NOT NULL
  AND baseline_run.gabarit_source IN (1, 2, 3, 4)
  AND (
        baseline_run.gabarit_source <> 1
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
  AND NOT EXISTS (
        SELECT 1
        FROM qxp_run_error baseline_error
        WHERE baseline_error.id_run = baseline_run.id_run
      )
  AND REGEXP_LIKE(
        baseline_run.log_trace,
        ', update=[1-9][[:digit:]]*,'
      )
ORDER BY
    CASE WHEN baseline_run.gabarit_source = 1 THEN 0 ELSE 1 END,
    baseline_run.date_fin_generation DESC,
    baseline_run.id_run DESC
FETCH FIRST 20 ROWS ONLY;

