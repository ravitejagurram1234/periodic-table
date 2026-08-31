/* ---------------------------------------------------------------------------
   QOFF-01B - Existing Swagger-ready reserved run IDs
   Export: planning/03_swagger_ready_run_candidates.csv

   IDs returned here MAY be used with Swagger only after QOFF-02B returns PASS
   and all branch-specific prechecks pass. These rows are already reserved by
   the batch (status 5), have not started, have no output links, are the current
   run for their suivi, and have selected active change-capable tasks.

   Rabbit consumption must remain disabled. A Rabbit message may already exist
   for each status-5 run, so record the queue backlog and classify these stale
   messages before Rabbit is enabled later.
   --------------------------------------------------------------------------- */
WITH reserved_profile AS (
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
        COUNT(DISTINCT task.id_tache) AS selected_active_task_count,
        COUNT(DISTINCT CASE WHEN task.id_type_tache BETWEEN 1 AND 5
                            THEN task.id_tache END) AS selected_change_task_count,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 1
                            THEN task.id_tache END) AS sql_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 2
                            THEN task.id_tache END) AS document_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 3
                            THEN task.id_tache END) AS qxp_block_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 4
                            THEN task.id_tache END) AS dynamic_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 5
                            THEN task.id_tache END) AS compartment_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 4
                                  AND task.control_overflow = 1
                            THEN task.id_tache END) AS overflow_control_tasks,
        COUNT(DISTINCT CASE WHEN task.store_data = 1
                            THEN task.id_tache END) AS task_storage_tasks,
        run_record.date_creation_run,
        run_record.date_planification,
        suivi.id_run_precedent AS suggested_baseline_run_id,
        previous_run.id_statut_generation AS baseline_status,
        previous_run.id_doc_qxp AS baseline_qxp_document_id,
        previous_run.id_doc_pdf AS baseline_pdf_document_id,
        previous_run.id_doc_doc AS baseline_doc_document_id
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
     AND suivi.id_run_suivant = run_record.id_run
    JOIN qxp_gabarit gabarit
      ON gabarit.id_gabarit = suivi.id_gabarit
     AND gabarit.is_actif = 1
    LEFT JOIN qxp_ref_type_rapport report_type
      ON report_type.id_type_rapport = suivi.id_type_rapport
    LEFT JOIN qxp_ref_langue_document language
      ON language.id_langue_document = suivi.id_langue
    JOIN qxp_asso_run_taches run_task
      ON run_task.id_run = run_record.id_run
    JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
     AND task.is_actif = 1
    JOIN qxp_asso_gabarit_taches gabarit_task
      ON gabarit_task.id_gabarit = suivi.id_gabarit
     AND gabarit_task.id_tache = task.id_tache
    LEFT JOIN qxp_run previous_run
      ON previous_run.id_run = suivi.id_run_precedent
    WHERE run_record.id_statut_generation = 5
      AND run_record.gabarit_source IN (1, 2, 3, 4)
      AND run_record.date_debut_generation IS NULL
      AND run_record.date_fin_generation IS NULL
      AND run_record.id_doc_qxp IS NULL
      AND run_record.id_doc_pdf IS NULL
      AND run_record.id_doc_doc IS NULL
    GROUP BY
        run_record.id_run,
        run_record.id_suivi,
        suivi.id_type_rapport,
        report_type.libelle,
        suivi.id_fnd_code,
        suivi.id_unit_code,
        suivi.id_langue,
        language.nom_langue,
        suivi.date_echeance,
        suivi.id_gabarit,
        run_record.gabarit_source,
        run_record.mode_compart,
        gabarit.pagination_double,
        NVL(gabarit.store_data_type, 0),
        run_record.date_creation_run,
        run_record.date_planification,
        suivi.id_run_precedent,
        previous_run.id_statut_generation,
        previous_run.id_doc_qxp,
        previous_run.id_doc_pdf,
        previous_run.id_doc_doc
), classified AS (
    SELECT
        profile.*,
        CASE
            WHEN profile.compartment_tasks > 0 THEN 'COMPARTMENT'
            WHEN profile.dynamic_tasks > 0 THEN 'DYNAMIC'
            ELSE 'SIMPLE'
        END AS scenario_class
    FROM reserved_profile profile
    WHERE profile.selected_active_task_count > 0
      AND profile.selected_change_task_count > 0
), ranked AS (
    SELECT
        classified.*,
        ROW_NUMBER() OVER (
            PARTITION BY
                classified.scenario_class,
                classified.id_type_rapport,
                CASE WHEN classified.scenario_class = 'COMPARTMENT'
                     THEN NVL(classified.mode_compart, -1)
                     ELSE -1
                END
            ORDER BY classified.date_creation_run DESC,
                     classified.id_run DESC
        ) AS candidate_rank
    FROM classified
)
SELECT
    scenario_class,
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
    selected_active_task_count,
    selected_change_task_count,
    sql_tasks,
    document_tasks,
    qxp_block_tasks,
    dynamic_tasks,
    compartment_tasks,
    sql_tasks AS selected_value_update_task_count,
    document_tasks + qxp_block_tasks + dynamic_tasks + compartment_tasks
        AS selected_structure_modify_task_count,
    CASE
        WHEN sql_tasks > 0
         AND document_tasks + qxp_block_tasks + dynamic_tasks + compartment_tasks > 0
        THEN 'UPDATE_AND_MODIFY_CONFIGURED'
        WHEN sql_tasks > 0 THEN 'UPDATE_CONFIGURED'
        WHEN document_tasks + qxp_block_tasks + dynamic_tasks + compartment_tasks > 0
        THEN 'MODIFY_CONFIGURED'
        ELSE 'NO_CHANGE_TASK_CONFIGURED'
    END AS configured_change_shape,
    overflow_control_tasks,
    task_storage_tasks,
    suggested_baseline_run_id,
    baseline_status,
    baseline_qxp_document_id,
    baseline_pdf_document_id,
    baseline_doc_document_id,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM qxp_run baseline_run
            WHERE baseline_run.id_run = ranked.suggested_baseline_run_id
              AND baseline_run.id_statut_generation = 2
              AND REGEXP_LIKE(
                    baseline_run.log_trace,
                    ' executing, add=[1-9][[:digit:]]*,|, update=[1-9][[:digit:]]*,|, excluded=[1-9][[:digit:]]*,'
                  )
        ) THEN 1 ELSE 0
    END AS baseline_has_nonzero_step_change,
    TO_CHAR(date_creation_run, 'YYYY-MM-DD HH24:MI:SS') AS creation_time,
    TO_CHAR(date_planification, 'YYYY-MM-DD HH24:MI:SS') AS planned_time
FROM ranked
WHERE candidate_rank <= &CANDIDATES_PER_GROUP
ORDER BY scenario_class, id_type_rapport,
         NVL(mode_compart, -1), candidate_rank;


