/* ---------------------------------------------------------------------------
   QOFF-02A - Pre-reservation validation for an old-UI-created status-1 run
   Export: run_<ID>/00_pre_reservation_validation.csv

   Use only for an ID returned by QOFF-01C, with the batch, old .NET engine and
   Java engine already stopped. PRE_RESERVATION_RESULT must be PASS before the
   separate guarded reservation script is executed. This query changes nothing.
   --------------------------------------------------------------------------- */
WITH run_context AS (
    SELECT
        run_record.id_run,
        run_record.id_suivi,
        run_record.id_statut_generation,
        status.libelle AS run_status_label,
        suivi.id_statut_generation AS suivi_status,
        suivi.id_run_suivant,
        suivi.id_type_rapport,
        report_type.libelle AS report_type_label,
        suivi.id_fnd_code,
        suivi.id_unit_code,
        suivi.id_langue,
        suivi.id_gabarit,
        run_record.gabarit_source,
        run_record.mode_compart,
        run_record.date_planification,
        run_record.date_debut_generation,
        run_record.date_fin_generation,
        run_record.id_doc_qxp,
        run_record.id_doc_pdf,
        run_record.id_doc_doc,
        gabarit.is_actif AS gabarit_is_active,
        CASE WHEN gabarit.contenu IS NULL THEN 0
             ELSE DBMS_LOB.GETLENGTH(gabarit.contenu)
        END AS configured_gabarit_bytes,
        (SELECT COUNT(*)
           FROM qxp_asso_fond_gabarit association_row
          WHERE association_row.id_type_rapport = suivi.id_type_rapport
            AND association_row.id_fnd_code = suivi.id_fnd_code
            AND association_row.id_langue = suivi.id_langue
            AND association_row.id_gabarit = suivi.id_gabarit
        ) AS run_property_match_count
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    JOIN qxp_gabarit gabarit
      ON gabarit.id_gabarit = suivi.id_gabarit
    LEFT JOIN qxp_ref_statut_generation status
      ON status.id_statut_generation = run_record.id_statut_generation
    LEFT JOIN qxp_ref_type_rapport report_type
      ON report_type.id_type_rapport = suivi.id_type_rapport
    WHERE run_record.id_run = &RUN_ID
), task_profile AS (
    SELECT
        run_task.id_run,
        COUNT(DISTINCT task.id_tache) AS selected_active_task_count,
        COUNT(DISTINCT CASE WHEN task.id_type_tache BETWEEN 1 AND 5
                            THEN task.id_tache END) AS selected_change_task_count,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 1
                            THEN task.id_tache END) AS selected_sql_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 2
                            THEN task.id_tache END) AS selected_document_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 3
                            THEN task.id_tache END) AS selected_qxp_block_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 4
                            THEN task.id_tache END) AS selected_dynamic_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 5
                            THEN task.id_tache END) AS selected_compartment_tasks
    FROM qxp_asso_run_taches run_task
    JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
     AND task.is_actif = 1
    JOIN run_context context
      ON context.id_run = run_task.id_run
    JOIN qxp_asso_gabarit_taches gabarit_task
      ON gabarit_task.id_gabarit = context.id_gabarit
     AND gabarit_task.id_tache = task.id_tache
    GROUP BY run_task.id_run
)
SELECT
    context.id_run,
    context.id_suivi,
    context.id_statut_generation,
    context.run_status_label,
    context.suivi_status,
    context.id_type_rapport,
    context.report_type_label,
    context.id_fnd_code,
    context.id_unit_code,
    context.id_langue,
    context.id_gabarit,
    context.gabarit_source,
    context.mode_compart,
    CASE WHEN context.id_run_suivant = context.id_run THEN 1 ELSE 0 END
        AS is_current_suivi_run,
    CASE WHEN context.date_planification IS NULL
               OR context.date_planification < SYSDATE
         THEN 1 ELSE 0 END AS batch_time_eligible,
    TO_CHAR(context.date_planification, 'YYYY-MM-DD HH24:MI:SS') AS planned_time,
    context.run_property_match_count,
    context.gabarit_is_active,
    context.configured_gabarit_bytes,
    NVL(tasks.selected_active_task_count, 0) AS selected_active_task_count,
    NVL(tasks.selected_change_task_count, 0) AS selected_change_task_count,
    NVL(tasks.selected_sql_tasks, 0) AS selected_sql_tasks,
    NVL(tasks.selected_document_tasks, 0) AS selected_document_tasks,
    NVL(tasks.selected_qxp_block_tasks, 0) AS selected_qxp_block_tasks,
    NVL(tasks.selected_dynamic_tasks, 0) AS selected_dynamic_tasks,
    NVL(tasks.selected_compartment_tasks, 0) AS selected_compartment_tasks,
    CASE
        WHEN NVL(tasks.selected_compartment_tasks, 0) > 0 THEN 'COMPARTMENT'
        WHEN NVL(tasks.selected_dynamic_tasks, 0) > 0 THEN 'DYNAMIC'
        ELSE 'SIMPLE'
    END AS scenario_class,
    CASE
        WHEN NVL(context.id_statut_generation, -1) <> 1
          THEN 'STOP: run status is not UI-created (1)'
        WHEN NVL(context.suivi_status, -1) <> 1
          THEN 'STOP: QXP_SUIVI status is not UI-created (1)'
        WHEN NVL(context.id_run_suivant, -1) <> context.id_run
          THEN 'STOP: run is not ID_RUN_SUIVANT'
        WHEN NVL(context.gabarit_source, -1) NOT IN (1, 2, 3, 4)
          THEN 'STOP: gabarit source is not 1, 2, 3 or 4'
        WHEN context.date_planification IS NOT NULL
         AND context.date_planification >= SYSDATE THEN 'STOP: run is not batch-time eligible'
        WHEN context.run_property_match_count <> 1
          THEN 'STOP: run-property association count is not 1'
        WHEN context.gabarit_is_active <> 1
          THEN 'STOP: configured gabarit is inactive'
        WHEN context.gabarit_source = 1 AND context.configured_gabarit_bytes <= 0
          THEN 'STOP: source-1 gabarit content is unavailable'
        WHEN NVL(tasks.selected_change_task_count, 0) <= 0
          THEN 'STOP: no selected active change-capable task'
        WHEN context.date_debut_generation IS NOT NULL
          OR context.date_fin_generation IS NOT NULL
          THEN 'STOP: run already has generation timestamps'
        WHEN context.id_doc_qxp IS NOT NULL
          OR context.id_doc_pdf IS NOT NULL
          OR context.id_doc_doc IS NOT NULL
          THEN 'STOP: run already has generated document links'
        ELSE 'PASS'
    END AS pre_reservation_result
FROM run_context context
LEFT JOIN task_profile tasks
  ON tasks.id_run = context.id_run;

