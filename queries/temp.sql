/* ---------------------------------------------------------------------------
   QOFF-01F - Reconcile a recent old-UI creation attempt
   Export: planning/07_recent_ui_creation_attempts.csv

   Use after the old UI displays CreationRunKO. This read-only query deliberately
   avoids normal candidate filters so it can show any QXP_RUN inserted or
   refreshed during the last 48 hours, including a row that committed before a
   later immediate-mode Batch WCF failure.

   SQL text, task values, traces, errors and document payloads are not selected.
   Do not execute or reserve any returned ID until it is reviewed.
   --------------------------------------------------------------------------- */
SELECT
    run_record.id_run,
    run_record.id_suivi,
    CASE WHEN suivi.id_run_suivant = run_record.id_run THEN 1 ELSE 0 END
        AS is_current_suivi_run,
    run_record.id_statut_generation AS run_status,
    suivi.id_statut_generation AS suivi_status,
    suivi.id_type_rapport,
    report_type.libelle AS report_type_label,
    suivi.id_fnd_code,
    suivi.id_unit_code,
    suivi.id_langue,
    suivi.id_gabarit,
    run_record.gabarit_source,
    run_record.mode_compart,
    COUNT(DISTINCT run_task.id_tache) AS selected_task_count,
    COUNT(DISTINCT CASE
        WHEN task.is_actif = 1 AND task.id_type_tache = 1
        THEN task.id_tache END) AS active_sql_tasks,
    COUNT(DISTINCT CASE
        WHEN task.is_actif = 1 AND task.id_type_tache = 2
        THEN task.id_tache END) AS active_document_tasks,
    COUNT(DISTINCT CASE
        WHEN task.is_actif = 1 AND task.id_type_tache = 3
        THEN task.id_tache END) AS active_previous_qxp_tasks,
    COUNT(DISTINCT CASE
        WHEN task.is_actif = 1 AND task.id_type_tache = 4
        THEN task.id_tache END) AS active_dynamic_tasks,
    COUNT(DISTINCT CASE
        WHEN task.is_actif = 1 AND task.id_type_tache = 5
        THEN task.id_tache END) AS active_compartment_tasks,
    TO_CHAR(
        run_record.date_creation_run,
        'YYYY-MM-DD HH24:MI:SS'
    ) AS creation_time,
    TO_CHAR(
        run_record.date_planification,
        'YYYY-MM-DD HH24:MI:SS'
    ) AS planned_time,
    CASE
        WHEN suivi.id_run_suivant = run_record.id_run
         AND run_record.id_statut_generation = 1
         AND suivi.id_statut_generation = 1
        THEN 'POSSIBLE_COMMITTED_UI_ATTEMPT'
        ELSE 'REVIEW_ONLY_NOT_A_STATUS1_CURRENT_RUN'
    END AS reconciliation_result
FROM qxp_run run_record
JOIN qxp_suivi suivi
  ON suivi.id_suivi = run_record.id_suivi
LEFT JOIN qxp_ref_type_rapport report_type
  ON report_type.id_type_rapport = suivi.id_type_rapport
LEFT JOIN qxp_asso_run_taches run_task
  ON run_task.id_run = run_record.id_run
LEFT JOIN qxp_tache task
  ON task.id_tache = run_task.id_tache
WHERE run_record.date_creation_run >= SYSDATE - 2
GROUP BY
    run_record.id_run,
    run_record.id_suivi,
    suivi.id_run_suivant,
    run_record.id_statut_generation,
    suivi.id_statut_generation,
    suivi.id_type_rapport,
    report_type.libelle,
    suivi.id_fnd_code,
    suivi.id_unit_code,
    suivi.id_langue,
    suivi.id_gabarit,
    run_record.gabarit_source,
    run_record.mode_compart,
    run_record.date_creation_run,
    run_record.date_planification
ORDER BY run_record.date_creation_run DESC, run_record.id_run DESC
FETCH FIRST 50 ROWS ONLY;
