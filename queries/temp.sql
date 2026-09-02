
/* ---------------------------------------------------------------------------
   QOFF-02B - Selected Swagger-run admission and task validation
   Export: run_<ID>/00_selected_run_validation.csv

   Run after choosing an ID from QOFF-01B, or after reserving a QOFF-01C ID,
   and before any engine GET/POST.
   BASIC_ADMISSION_RESULT must be PASS. This query validates the normal batch
   handoff and proves that the run has active selected work. QOFF-07B, QOFF-08
   and QOFF-09 still validate source documents and branch-specific inputs.
   --------------------------------------------------------------------------- */
WITH selected_profile AS (
    SELECT
        run_record.id_run,
        run_record.id_suivi,
        run_record.id_statut_generation,
        status.libelle AS run_status_label,
        suivi.id_statut_generation AS suivi_status,
        suivi.id_type_rapport,
        report_type.libelle AS report_type_label,
        suivi.id_fnd_code,
        suivi.id_unit_code,
        suivi.id_langue,
        suivi.id_gabarit,
        run_record.gabarit_source,
        run_record.mode_compart,
        CASE WHEN suivi.id_run_suivant = run_record.id_run THEN 1 ELSE 0 END
            AS is_current_suivi_run,
        (SELECT COUNT(*)
           FROM qxp_asso_fond_gabarit association_row
          WHERE association_row.id_type_rapport = suivi.id_type_rapport
            AND association_row.id_fnd_code = suivi.id_fnd_code
            AND association_row.id_langue = suivi.id_langue
            AND association_row.id_gabarit = suivi.id_gabarit
        ) AS run_property_match_count,
        gabarit.is_actif AS gabarit_is_active,
        MAX(CASE WHEN gabarit.contenu IS NULL THEN 0
                 ELSE DBMS_LOB.GETLENGTH(gabarit.contenu)
            END) AS configured_gabarit_bytes,
        COUNT(DISTINCT CASE WHEN task.is_actif = 1
                            THEN task.id_tache END) AS configured_active_task_count,
        COUNT(DISTINCT CASE WHEN task.is_actif = 1
                                  AND run_task.id_tache IS NOT NULL
                            THEN task.id_tache END) AS selected_todo_task_count,
        COUNT(DISTINCT CASE WHEN task.is_actif = 1
                                  AND run_task.id_tache IS NOT NULL
                                  AND task.id_type_tache BETWEEN 1 AND 5
                            THEN task.id_tache END) AS selected_change_task_count,
        COUNT(DISTINCT CASE WHEN task.is_actif = 1
                                  AND run_task.id_tache IS NOT NULL
                                  AND task.id_type_tache = 1
                            THEN task.id_tache END) AS selected_sql_tasks,
        COUNT(DISTINCT CASE WHEN task.is_actif = 1
                                  AND run_task.id_tache IS NOT NULL
                                  AND task.id_type_tache = 2
                            THEN task.id_tache END) AS selected_document_tasks,
        COUNT(DISTINCT CASE WHEN task.is_actif = 1
                                  AND run_task.id_tache IS NOT NULL
                                  AND task.id_type_tache = 3
                            THEN task.id_tache END) AS selected_qxp_block_tasks,
        COUNT(DISTINCT CASE WHEN task.is_actif = 1
                                  AND run_task.id_tache IS NOT NULL
                                  AND task.id_type_tache = 4
                            THEN task.id_tache END) AS selected_dynamic_tasks,
        COUNT(DISTINCT CASE WHEN task.is_actif = 1
                                  AND run_task.id_tache IS NOT NULL
                                  AND task.id_type_tache = 5
                            THEN task.id_tache END) AS selected_compartment_tasks,
        run_record.date_debut_generation,
        run_record.date_fin_generation,
        run_record.id_doc_qxp,
        run_record.id_doc_pdf,
        run_record.id_doc_doc
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    JOIN qxp_gabarit gabarit
      ON gabarit.id_gabarit = suivi.id_gabarit
    LEFT JOIN qxp_ref_statut_generation status
      ON status.id_statut_generation = run_record.id_statut_generation
    LEFT JOIN qxp_ref_type_rapport report_type
      ON report_type.id_type_rapport = suivi.id_type_rapport
    LEFT JOIN qxp_asso_gabarit_taches gabarit_task
      ON gabarit_task.id_gabarit = suivi.id_gabarit
    LEFT JOIN qxp_tache task
      ON task.id_tache = gabarit_task.id_tache
    LEFT JOIN qxp_asso_run_taches run_task
      ON run_task.id_run = run_record.id_run
     AND run_task.id_tache = task.id_tache
    WHERE run_record.id_run = &RUN_ID
    GROUP BY
        run_record.id_run,
        run_record.id_suivi,
        run_record.id_statut_generation,
        status.libelle,
        suivi.id_statut_generation,
        suivi.id_type_rapport,
        report_type.libelle,
        suivi.id_fnd_code,
        suivi.id_unit_code,
        suivi.id_langue,
        suivi.id_gabarit,
        suivi.id_run_suivant,
        gabarit.is_actif,
        run_record.gabarit_source,
        run_record.mode_compart,
        run_record.date_debut_generation,
        run_record.date_fin_generation,
        run_record.id_doc_qxp,
        run_record.id_doc_pdf,
        run_record.id_doc_doc
)
SELECT
    profile.*,
    CASE
        WHEN profile.selected_compartment_tasks > 0 THEN 'COMPARTMENT'
        WHEN profile.selected_dynamic_tasks > 0 THEN 'DYNAMIC'
        ELSE 'SIMPLE'
    END AS scenario_class,
    CASE
        WHEN NVL(profile.id_statut_generation, -1) <> 5
          THEN 'STOP: status is not batch-reserved (5)'
        WHEN NVL(profile.suivi_status, -1) <> 1
          THEN 'STOP: QXP_SUIVI status must remain 1 before processing'
        WHEN profile.is_current_suivi_run <> 1 THEN 'STOP: run is not ID_RUN_SUIVANT'
        WHEN NVL(profile.gabarit_source, -1) NOT IN (1, 2, 3, 4)
          THEN 'STOP: gabarit source is not 1, 2, 3 or 4'
        WHEN profile.run_property_match_count <> 1 THEN 'STOP: run-property association count is not 1'
        WHEN profile.gabarit_is_active <> 1
          THEN 'STOP: configured gabarit is inactive'
        WHEN profile.gabarit_source = 1 AND profile.configured_gabarit_bytes <= 0
          THEN 'STOP: source-1 gabarit content is unavailable'
        WHEN profile.selected_change_task_count <= 0
          THEN 'STOP: no selected active change-capable task'
        WHEN profile.date_debut_generation IS NOT NULL
          OR profile.date_fin_generation IS NOT NULL
          THEN 'STOP: run already has generation timestamps'
        WHEN profile.id_doc_qxp IS NOT NULL
          OR profile.id_doc_pdf IS NOT NULL
          OR profile.id_doc_doc IS NOT NULL
          THEN 'STOP: run already has generated document links'
        ELSE 'PASS'
    END AS basic_admission_result
FROM selected_profile profile;



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



/* ---------------------------------------------------------------------------
   QOFF-01C - Fresh old-UI runs eligible for controlled Swagger reservation
   Export: planning/04_ui_created_status1_candidates.csv

   Use only in non-production when QOFF-01B has no suitable status-5 row.
   These IDs are still status 1 and MUST NOT be posted to Java. Stop the batch,
   old .NET engine and Java engine before creating the UI run. After selection,
   require QOFF-02A=PASS, execute the separate guarded reservation script, and
   require QOFF-02B=PASS before starting Java and calling Swagger.

   CONFIGURED_CHANGE_SHAPE is configuration evidence, not proof that the
   current task SQL/source documents will produce a non-zero document change.
   Prefer BASELINE_HAS_NONZERO_STEP_CHANGE=1 and prove the current run with
   runtime counts plus QOFF-17 after execution. Output is limited to ten
   candidates per scenario/report-type grouping.
   --------------------------------------------------------------------------- */
WITH task_profile AS (
    SELECT
        run_task.id_run,
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
                            THEN task.id_tache END) AS task_storage_tasks
    FROM qxp_asso_run_taches run_task
    JOIN qxp_run run_record
      ON run_record.id_run = run_task.id_run
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
     AND task.is_actif = 1
    JOIN qxp_asso_gabarit_taches gabarit_task
      ON gabarit_task.id_gabarit = suivi.id_gabarit
     AND gabarit_task.id_tache = task.id_tache
    GROUP BY run_task.id_run
), candidate AS (
    SELECT
        run_record.id_run,
        run_record.id_suivi,
        run_record.id_statut_generation,
        suivi.id_statut_generation AS suivi_status,
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
        DBMS_LOB.GETLENGTH(gabarit.contenu) AS configured_gabarit_bytes,
        CASE WHEN dynamic_template.contenu IS NULL THEN NULL
             ELSE DBMS_LOB.GETLENGTH(dynamic_template.contenu)
        END AS dynamic_template_bytes,
        task_profile.selected_active_task_count,
        task_profile.selected_change_task_count,
        task_profile.sql_tasks,
        task_profile.document_tasks,
        task_profile.qxp_block_tasks,
        task_profile.dynamic_tasks,
        task_profile.compartment_tasks,
        task_profile.overflow_control_tasks,
        task_profile.task_storage_tasks,
        run_record.date_creation_run,
        run_record.date_planification,
        suivi.id_run_precedent AS suggested_baseline_run_id,
        previous_run.id_statut_generation AS baseline_status,
        previous_run.id_doc_qxp AS baseline_qxp_document_id,
        previous_run.id_doc_pdf AS baseline_pdf_document_id,
        previous_run.id_doc_doc AS baseline_doc_document_id,
        CASE
            WHEN previous_run.id_statut_generation = 2
             AND REGEXP_LIKE(
                    previous_run.log_trace,
                    ' executing, add=[1-9][[:digit:]]*,|, update=[1-9][[:digit:]]*,|, excluded=[1-9][[:digit:]]*,'
                 )
            THEN 1 ELSE 0
        END AS baseline_has_nonzero_step_change,
        CASE
            WHEN task_profile.compartment_tasks > 0 THEN 'COMPARTMENT'
            WHEN task_profile.dynamic_tasks > 0 THEN 'DYNAMIC'
            ELSE 'SIMPLE'
        END AS scenario_class,
        CASE
            WHEN task_profile.sql_tasks > 0
             AND task_profile.document_tasks + task_profile.qxp_block_tasks
                   + task_profile.dynamic_tasks + task_profile.compartment_tasks > 0
            THEN 'UPDATE_AND_MODIFY_CONFIGURED'
            WHEN task_profile.sql_tasks > 0 THEN 'UPDATE_CONFIGURED'
            WHEN task_profile.document_tasks + task_profile.qxp_block_tasks
                   + task_profile.dynamic_tasks + task_profile.compartment_tasks > 0
            THEN 'MODIFY_CONFIGURED'
            ELSE 'NO_CHANGE_TASK_CONFIGURED'
        END AS configured_change_shape
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
     AND suivi.id_run_suivant = run_record.id_run
    JOIN qxp_gabarit gabarit
      ON gabarit.id_gabarit = suivi.id_gabarit
     AND gabarit.is_actif = 1
    JOIN task_profile
      ON task_profile.id_run = run_record.id_run
     AND task_profile.selected_change_task_count > 0
    LEFT JOIN qxp_gabarit_template dynamic_template
      ON dynamic_template.id_gabarit_template = gabarit.id_gabarit_template
    LEFT JOIN qxp_ref_type_rapport report_type
      ON report_type.id_type_rapport = suivi.id_type_rapport
    LEFT JOIN qxp_ref_langue_document language
      ON language.id_langue_document = suivi.id_langue
    LEFT JOIN qxp_run previous_run
      ON previous_run.id_run = suivi.id_run_precedent
    WHERE run_record.id_statut_generation = 1
      AND suivi.id_statut_generation = 1
      AND run_record.gabarit_source IN (1, 2, 3, 4)
      AND (run_record.date_planification IS NULL
           OR run_record.date_planification < SYSDATE)
      AND run_record.date_debut_generation IS NULL
      AND run_record.date_fin_generation IS NULL
      AND run_record.id_doc_qxp IS NULL
      AND run_record.id_doc_pdf IS NULL
      AND run_record.id_doc_doc IS NULL
      AND (run_record.gabarit_source <> 1
           OR (gabarit.contenu IS NOT NULL
               AND DBMS_LOB.GETLENGTH(gabarit.contenu) > 0))
      AND 1 = (
          SELECT COUNT(*)
          FROM qxp_asso_fond_gabarit association_row
          WHERE association_row.id_type_rapport = suivi.id_type_rapport
            AND association_row.id_fnd_code = suivi.id_fnd_code
            AND association_row.id_langue = suivi.id_langue
            AND association_row.id_gabarit = suivi.id_gabarit
      )
), ranked AS (
    SELECT
        candidate.*,
        ROW_NUMBER() OVER (
            PARTITION BY
                candidate.scenario_class,
                candidate.id_type_rapport,
                CASE WHEN candidate.scenario_class = 'COMPARTMENT'
                     THEN NVL(candidate.mode_compart, -1)
                     ELSE -1
                END
            ORDER BY
                CASE WHEN candidate.configured_change_shape = 'UPDATE_AND_MODIFY_CONFIGURED'
                     THEN 0 ELSE 1 END,
                candidate.baseline_has_nonzero_step_change DESC,
                candidate.date_creation_run DESC,
                candidate.id_run DESC
        ) AS candidate_rank
    FROM candidate
)
SELECT
    scenario_class,
    candidate_rank,
    id_run AS ui_created_run_id,
    id_suivi,
    id_statut_generation AS run_status,
    suivi_status,
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
    configured_gabarit_bytes,
    dynamic_template_bytes,
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
    configured_change_shape,
    overflow_control_tasks,
    task_storage_tasks,
    suggested_baseline_run_id,
    baseline_status,
    baseline_qxp_document_id,
    baseline_pdf_document_id,
    baseline_doc_document_id,
    baseline_has_nonzero_step_change,
    TO_CHAR(date_creation_run, 'YYYY-MM-DD HH24:MI:SS') AS creation_time,
    TO_CHAR(date_planification, 'YYYY-MM-DD HH24:MI:SS') AS planned_time
FROM ranked
WHERE candidate_rank <= 10
ORDER BY scenario_class, id_type_rapport,
         NVL(mode_compart, -1), candidate_rank;


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




/* ---------------------------------------------------------------------------
   QOFF-03 - Exact run overview
   Export before: run_<ID>/01_pre_run_overview.csv
   Export after : run_<ID>/10_post_run_overview.csv
   --------------------------------------------------------------------------- */
SELECT
    run_record.id_run,
    run_record.id_suivi,
    run_record.id_statut_generation AS run_status_code,
    run_status.libelle AS run_status_label,
    suivi.id_statut_generation AS suivi_generation_status_code,
    suivi_status.libelle AS suivi_generation_status_label,
    TO_CHAR(run_record.date_planification, 'YYYY-MM-DD HH24:MI:SS') AS planned_time,
    TO_CHAR(run_record.date_creation_run, 'YYYY-MM-DD HH24:MI:SS') AS creation_time,
    TO_CHAR(run_record.date_debut_generation, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
    TO_CHAR(run_record.date_fin_generation, 'YYYY-MM-DD HH24:MI:SS') AS end_time,
    suivi.id_type_rapport,
    report_type.libelle AS report_type_label,
    suivi.id_fnd_code,
    suivi.id_unit_code,
    suivi.id_langue,
    language.nom_langue,
    language.valeur_langue,
    TO_CHAR(suivi.date_echeance, 'YYYY-MM-DD HH24:MI:SS') AS due_date,
    suivi.id_gabarit,
    gabarit.nom AS gabarit_name,
    gabarit.pagination_double,
    NVL(gabarit.store_data_type, 0) AS store_data_type,
    run_record.gabarit_source,
    run_record.id_suivi_gabarit_source,
    run_record.mode_compart,
    run_record.integrer_n1,
    suivi.id_run_precedent,
    suivi.id_run_suivant,
    run_record.id_qxp_upload,
    run_record.id_doc_qxp,
    run_record.id_doc_pdf,
    run_record.id_doc_doc,
    CASE WHEN run_record.log_trace IS NULL THEN 0
         ELSE DBMS_LOB.GETLENGTH(run_record.log_trace)
    END AS trace_length
FROM qxp_run run_record
JOIN qxp_suivi suivi
  ON suivi.id_suivi = run_record.id_suivi
JOIN qxp_gabarit gabarit
  ON gabarit.id_gabarit = suivi.id_gabarit
LEFT JOIN qxp_ref_statut_generation run_status
  ON run_status.id_statut_generation = run_record.id_statut_generation
LEFT JOIN qxp_ref_statut_generation suivi_status
  ON suivi_status.id_statut_generation = suivi.id_statut_generation
LEFT JOIN qxp_ref_type_rapport report_type
  ON report_type.id_type_rapport = suivi.id_type_rapport
LEFT JOIN qxp_ref_langue_document language
  ON language.id_langue_document = suivi.id_langue
WHERE run_record.id_run = &RUN_ID;




/* ---------------------------------------------------------------------------
   QOFF-04 - Input parameters, exactly as Get_In_Params supplies them
   Export: run_<ID>/02_parameters.csv
   --------------------------------------------------------------------------- */
SELECT
    run_record.id_run,
    run_record.id_suivi,
    parameter.id_parametre,
    parameter.nom_parametre,
    parameter.libelle,
    parameter.input_data_type,
    data_type.libelle AS input_type_label,
    suivi_parameter.valeur,
    LENGTH(suivi_parameter.valeur) AS value_length
FROM qxp_run run_record
JOIN qxp_asso_suivi_parametres suivi_parameter
  ON suivi_parameter.id_suivi = run_record.id_suivi
JOIN qxp_params_type_rapport parameter
  ON parameter.id_parametre = suivi_parameter.id_parametre
LEFT JOIN qxp_ref_data_type data_type
  ON data_type.id_data_type = parameter.input_data_type
WHERE run_record.id_run = &RUN_ID
ORDER BY parameter.id_parametre;






/* ---------------------------------------------------------------------------
   QOFF-05 - Tasks and complete non-payload configuration
   Export: run_<ID>/03_tasks.csv

   SQL text is intentionally not selected. SQL_LENGTH proves its presence.
   --------------------------------------------------------------------------- */
SELECT
    run_record.id_run,
    task.id_tache,
    task.id_type_tache,
    task_type.libelle AS task_type_label,
    gabarit_task.libelle_tache,
    CASE WHEN run_task.id_tache IS NULL THEN 0 ELSE 1 END AS todo,
    task.id_sous_categorie,
    CASE WHEN task.sql IS NULL THEN NULL ELSE DBMS_LOB.GETLENGTH(task.sql) END AS sql_length,
    task.output_data_type,
    task.nb_decimal,
    task.decimal_significative,
    task.afficher_zero,
    CASE WHEN task.champs_vide IS NULL THEN '<NULL>'
         ELSE '[' || task.champs_vide || ']'
    END AS champs_vide_exact,
    task.conserver_style,
    task.rotation_image,
    task.crop_image_values,
    task.position_image,
    task.previous_type_rapport,
    task.code_master_page,
    task.page_break_rules,
    task.column_break_rules,
    task.nb_column,
    task.column_space,
    task.new_page_table,
    task.id_gabarit_fils,
    task.control_overflow,
    task.store_data,
    CASE WHEN task.bloc_source IS NULL THEN '<NULL>'
         ELSE '[' || task.bloc_source || ']'
    END AS bloc_source_exact,
    LENGTH(task.bloc_source) AS bloc_source_length,
    CASE WHEN task.bloc_destination IS NULL THEN '<NULL>'
         ELSE '[' || task.bloc_destination || ']'
    END AS bloc_destination_exact,
    LENGTH(task.bloc_destination) AS bloc_destination_length,
    task.commentaire
FROM qxp_run run_record
JOIN qxp_suivi suivi
  ON suivi.id_suivi = run_record.id_suivi
 AND suivi.id_run_suivant = run_record.id_run
JOIN qxp_asso_fond_gabarit fond_gabarit
  ON fond_gabarit.id_type_rapport = suivi.id_type_rapport
 AND fond_gabarit.id_fnd_code = suivi.id_fnd_code
 AND fond_gabarit.id_langue = suivi.id_langue
 AND fond_gabarit.id_gabarit = suivi.id_gabarit
JOIN qxp_asso_gabarit_taches gabarit_task
  ON gabarit_task.id_gabarit = fond_gabarit.id_gabarit
JOIN qxp_tache task
  ON task.id_tache = gabarit_task.id_tache
 AND task.is_actif = 1
LEFT JOIN qxp_asso_run_taches run_task
  ON run_task.id_run = run_record.id_run
 AND run_task.id_tache = task.id_tache
LEFT JOIN qxp_ref_type_tache task_type
  ON task_type.id_type_tache = task.id_type_tache
WHERE run_record.id_run = &RUN_ID
ORDER BY task.id_tache;






/* ---------------------------------------------------------------------------
   QOFF-05A - Selected-task configured change readiness
   Export: run_<ID>/04_selected_task_change_readiness.csv

   This is a safe pre-run selector. It does not execute or print task SQL and
   cannot prove that current SQL/source data will produce blocks. Prefer a run
   with RUN_CHANGE_SHAPE=UPDATE_AND_MODIFY_CONFIGURED when broad coverage is
   needed. Runtime task counts and QOFF-17 are the final non-zero-change proof.
   --------------------------------------------------------------------------- */
SELECT
    run_record.id_run,
    task.id_tache,
    task.id_type_tache,
    task_type.libelle AS task_type_label,
    CASE task.id_type_tache
        WHEN 1 THEN 'VALUE_UPDATE'
        WHEN 2 THEN 'DOCUMENT_INSERT_OR_REPLACE'
        WHEN 3 THEN 'PREVIOUS_QXP_BLOCK_INSERT'
        WHEN 4 THEN 'DYNAMIC_BLOCK_GENERATION'
        WHEN 5 THEN 'COMPARTMENT_GENERATE_OR_INCORPORATE'
    END AS configured_operation,
    CASE WHEN task.id_type_tache = 1 THEN 1 ELSE 0 END
        AS configured_value_update_flag,
    CASE WHEN task.id_type_tache BETWEEN 2 AND 5 THEN 1 ELSE 0 END
        AS configured_structure_modify_flag,
    CASE
        WHEN SUM(CASE WHEN task.id_type_tache = 1 THEN 1 ELSE 0 END)
                 OVER (PARTITION BY run_record.id_run) > 0
         AND SUM(CASE WHEN task.id_type_tache BETWEEN 2 AND 5 THEN 1 ELSE 0 END)
                 OVER (PARTITION BY run_record.id_run) > 0
        THEN 'UPDATE_AND_MODIFY_CONFIGURED'
        WHEN SUM(CASE WHEN task.id_type_tache = 1 THEN 1 ELSE 0 END)
                 OVER (PARTITION BY run_record.id_run) > 0
        THEN 'UPDATE_CONFIGURED'
        ELSE 'MODIFY_CONFIGURED'
    END AS run_change_shape,
    CASE WHEN task.sql IS NULL THEN NULL
         ELSE DBMS_LOB.GETLENGTH(task.sql)
    END AS sql_length,
    CASE WHEN task.bloc_source IS NULL THEN '<NULL>'
         ELSE '[' || task.bloc_source || ']'
    END AS bloc_source_exact,
    LENGTH(task.bloc_source) AS bloc_source_length,
    CASE WHEN task.bloc_destination IS NULL THEN '<NULL>'
         ELSE '[' || task.bloc_destination || ']'
    END AS bloc_destination_exact,
    LENGTH(task.bloc_destination) AS bloc_destination_length,
    task.conserver_style,
    task.previous_type_rapport,
    task.control_overflow,
    task.id_gabarit_fils,
    run_record.mode_compart,
    CASE WHEN dynamic_template.contenu IS NULL THEN NULL
         ELSE DBMS_LOB.GETLENGTH(dynamic_template.contenu)
    END AS dynamic_template_bytes,
    CASE
        WHEN task.id_type_tache = 1
         AND task.sql IS NOT NULL
         AND DBMS_LOB.GETLENGTH(task.sql) > 0
        THEN 'CONFIGURED: prove fetched rows and updateCount at runtime'
        WHEN task.id_type_tache = 1
        THEN 'STOP: SQL task has no SQL content'
        WHEN task.id_type_tache = 2
        THEN 'CHECK QOFF-08: exactly one usable source document is required'
        WHEN task.id_type_tache = 3
        THEN 'CHECK QOFF-08B: a non-empty previous certified QXP is required'
        WHEN task.id_type_tache = 4
         AND task.sql IS NOT NULL
         AND DBMS_LOB.GETLENGTH(task.sql) > 0
         AND dynamic_template.contenu IS NOT NULL
         AND DBMS_LOB.GETLENGTH(dynamic_template.contenu) > 0
        THEN 'CONFIGURED: prove fetched rows and modifyCount at runtime'
        WHEN task.id_type_tache = 4
        THEN 'STOP: dynamic SQL or dynamic template is empty'
        WHEN task.id_type_tache = 5
         AND run_record.mode_compart IN (1, 2, 3)
        THEN 'CHECK QOFF-09: ordered child selection is required'
        WHEN task.id_type_tache = 5
        THEN 'STOP: compartment mode is not 1, 2 or 3'
        ELSE 'REVIEW'
    END AS configuration_readiness,
    CASE
        WHEN previous_run.id_statut_generation = 2
         AND REGEXP_LIKE(
                previous_run.log_trace,
                ' executing, add=[1-9][[:digit:]]*,|, update=[1-9][[:digit:]]*,|, excluded=[1-9][[:digit:]]*,'
             )
        THEN 1 ELSE 0
    END AS baseline_has_nonzero_step_change,
    'POST_ONLY: task counts plus QOFF-17' AS current_run_actual_change_proof
FROM qxp_run run_record
JOIN qxp_suivi suivi
  ON suivi.id_suivi = run_record.id_suivi
 AND suivi.id_run_suivant = run_record.id_run
JOIN qxp_asso_run_taches run_task
  ON run_task.id_run = run_record.id_run
JOIN qxp_tache task
  ON task.id_tache = run_task.id_tache
 AND task.is_actif = 1
 AND task.id_type_tache BETWEEN 1 AND 5
JOIN qxp_asso_gabarit_taches gabarit_task
  ON gabarit_task.id_gabarit = suivi.id_gabarit
 AND gabarit_task.id_tache = task.id_tache
JOIN qxp_gabarit gabarit
  ON gabarit.id_gabarit = suivi.id_gabarit
LEFT JOIN qxp_gabarit_template dynamic_template
  ON dynamic_template.id_gabarit_template = gabarit.id_gabarit_template
LEFT JOIN qxp_run previous_run
  ON previous_run.id_run = suivi.id_run_precedent
LEFT JOIN qxp_ref_type_tache task_type
  ON task_type.id_type_tache = task.id_type_tache
WHERE run_record.id_run = &RUN_ID
ORDER BY task.id_tache;





/* ---------------------------------------------------------------------------
   QOFF-06 - SQL task exception rules
   Export: run_<ID>/04_task_exceptions.csv
   Duplicate rows must be retained; do not de-duplicate the export.
   --------------------------------------------------------------------------- */
SELECT
    run_task.id_run,
    exception_row.id_tache,
    exception_row.nom_bloc,
    exception_row.nom_tableau,
    CASE WHEN exception_row.index_lignes IS NULL THEN '<WHOLE TABLE>'
         ELSE exception_row.index_lignes
    END AS removal_scope
FROM qxp_asso_run_taches run_task
JOIN qxp_tache task
  ON task.id_tache = run_task.id_tache
JOIN qxp_tache_exception exception_row
  ON exception_row.id_tache = run_task.id_tache
WHERE run_task.id_run = &RUN_ID
  AND task.id_type_tache = 1
  AND task.is_actif = 1
ORDER BY exception_row.id_tache, exception_row.nom_bloc,
         exception_row.nom_tableau, exception_row.index_lignes;





/* ---------------------------------------------------------------------------
   QOFF-07 - Gabarit and dynamic-template metadata
   Export: run_<ID>/05_template_metadata.csv
   No BLOB content is selected.
   --------------------------------------------------------------------------- */
SELECT
    run_record.id_run,
    suivi.id_gabarit,
    gabarit.nom AS gabarit_name,
    gabarit.id_type_rapport,
    gabarit.id_langue,
    gabarit.is_actif,
    gabarit.generate_to_word,
    gabarit.type,
    gabarit.id_sous_categorie,
    gabarit.pagination_double,
    NVL(gabarit.store_data_type, 0) AS store_data_type,
    gabarit.id_gabarit_template,
    gabarit.taille_document AS declared_gabarit_size,
    DBMS_LOB.GETLENGTH(gabarit.contenu) AS actual_gabarit_bytes,
    dynamic_template.nom AS dynamic_template_name,
    dynamic_template.commentaire AS dynamic_template_comment,
    CASE WHEN dynamic_template.contenu IS NULL THEN NULL
         ELSE DBMS_LOB.GETLENGTH(dynamic_template.contenu)
    END AS dynamic_template_bytes,
    run_record.gabarit_source,
    run_record.id_suivi_gabarit_source,
    run_record.id_qxp_upload
FROM qxp_run run_record
JOIN qxp_suivi suivi
  ON suivi.id_suivi = run_record.id_suivi
JOIN qxp_gabarit gabarit
  ON gabarit.id_gabarit = suivi.id_gabarit
LEFT JOIN qxp_gabarit_template dynamic_template
  ON dynamic_template.id_gabarit_template = gabarit.id_gabarit_template
WHERE run_record.id_run = &RUN_ID;





/* ---------------------------------------------------------------------------
   QOFF-07B - Effective starting-gabarit document selected for this run
   Export: run_<ID>/05b_effective_gabarit_source.csv

   Reconstructs Get_Gabarit / Get_Gabarit_Document /
   Get_Gabarit_Document_Certifie without selecting BLOB content.
   --------------------------------------------------------------------------- */
WITH run_context AS (
    SELECT
        run_record.id_run,
        run_record.gabarit_source,
        run_record.id_suivi_gabarit_source,
        suivi.id_suivi,
        suivi.id_gabarit,
        suivi.id_fnd_code,
        suivi.id_unit_code,
        suivi.id_type_rapport,
        suivi.id_langue,
        suivi.date_echeance,
        CASE
            WHEN run_record.gabarit_source = 4
            THEN run_record.id_suivi_gabarit_source
            ELSE suivi.id_suivi
        END AS document_source_suivi_id
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    WHERE run_record.id_run = &RUN_ID
), document_source AS (
    SELECT
        context.id_run,
        context.gabarit_source,
        source_suivi.id_suivi AS source_suivi_id,
        source_next_run.id_qxp_upload,
        upload.id_upload,
        upload.taille_document AS upload_declared_bytes,
        CASE WHEN upload.contenu IS NULL THEN NULL
             ELSE DBMS_LOB.GETLENGTH(upload.contenu)
        END AS upload_actual_bytes,
        previous_document.id_document AS previous_document_id,
        previous_document.nom_complet_document AS previous_document_name,
        previous_document.taille_document AS previous_declared_bytes,
        CASE WHEN previous_document.contenu IS NULL THEN NULL
             ELSE DBMS_LOB.GETLENGTH(previous_document.contenu)
        END AS previous_actual_bytes,
        source_suivi.id_langue AS source_language
    FROM run_context context
    JOIN qxp_suivi source_suivi
      ON source_suivi.id_suivi = context.document_source_suivi_id
    LEFT JOIN qxp_run source_next_run
      ON source_next_run.id_run = source_suivi.id_run_suivant
    LEFT JOIN qxp_document_upload upload
      ON upload.id_upload = source_next_run.id_qxp_upload
    LEFT JOIN qxp_run previous_run
      ON previous_run.id_run = source_suivi.id_run_precedent
    LEFT JOIN qxp_document previous_document
      ON previous_document.id_document = previous_run.id_doc_qxp
), certified_candidates AS (
    SELECT
        context.id_run,
        previous_suivi.id_suivi AS source_suivi_id,
        certified.id_document,
        certified.nom_complet_document,
        certified.taille_document AS declared_bytes,
        CASE WHEN certified.contenu IS NULL THEN NULL
             ELSE DBMS_LOB.GETLENGTH(certified.contenu)
        END AS actual_bytes,
        previous_suivi.id_langue AS source_language,
        ROW_NUMBER() OVER (
            ORDER BY previous_suivi.date_echeance DESC
        ) AS candidate_rank
    FROM run_context context
    JOIN qxp_suivi previous_suivi
      ON previous_suivi.id_fnd_code = context.id_fnd_code
     AND (
            (previous_suivi.id_unit_code IS NULL AND context.id_unit_code IS NULL)
         OR previous_suivi.id_unit_code = context.id_unit_code
     )
     AND previous_suivi.id_type_rapport = context.id_type_rapport
     AND previous_suivi.id_suivi <> context.id_suivi
     AND previous_suivi.date_echeance < context.date_echeance
    JOIN qxp_document_certifie certified
      ON certified.id_document = previous_suivi.id_qxp_certifie
    JOIN qxp_ref_langue_document previous_language
      ON previous_language.id_langue_document = previous_suivi.id_langue
    JOIN qxp_ref_langue_document current_language
      ON current_language.id_langue_document = context.id_langue
     AND SUBSTR(current_language.valeur_langue, 1, 2)
         = SUBSTR(previous_language.valeur_langue, 1, 2)
)
SELECT
    context.id_run,
    context.gabarit_source,
    'GABARIT' AS selected_source_kind,
    TO_CHAR(gabarit.id_gabarit) AS selected_source_id,
    gabarit.nom AS selected_source_name,
    gabarit.taille_document AS declared_bytes,
    DBMS_LOB.GETLENGTH(gabarit.contenu) AS actual_bytes,
    gabarit.id_langue AS source_language,
    context.id_suivi AS source_suivi_id
FROM run_context context
JOIN qxp_gabarit gabarit
  ON gabarit.id_gabarit = context.id_gabarit
 AND gabarit.is_actif = 1
WHERE context.gabarit_source = 1
UNION ALL
SELECT
    context.id_run,
    context.gabarit_source,
    CASE WHEN NVL(source.id_qxp_upload, 0) > 0
         THEN 'DOCUMENT_UPLOAD'
         ELSE 'PREVIOUS_QXP_DOCUMENT'
    END AS selected_source_kind,
    TO_CHAR(CASE WHEN NVL(source.id_qxp_upload, 0) > 0
                 THEN source.id_upload
                 ELSE source.previous_document_id
            END) AS selected_source_id,
    CASE WHEN NVL(source.id_qxp_upload, 0) > 0
         THEN 'DG_' || source.id_upload || '.qxp'
         ELSE source.previous_document_name
    END AS selected_source_name,
    CASE WHEN NVL(source.id_qxp_upload, 0) > 0
         THEN source.upload_declared_bytes
         ELSE source.previous_declared_bytes
    END AS declared_bytes,
    CASE WHEN NVL(source.id_qxp_upload, 0) > 0
         THEN source.upload_actual_bytes
         ELSE source.previous_actual_bytes
    END AS actual_bytes,
    source.source_language,
    source.source_suivi_id
FROM run_context context
JOIN document_source source
  ON source.id_run = context.id_run
WHERE context.gabarit_source IN (2, 4)
UNION ALL
SELECT
    context.id_run,
    context.gabarit_source,
    'PREVIOUS_CERTIFIED_QXP' AS selected_source_kind,
    TO_CHAR(certified.id_document) AS selected_source_id,
    certified.nom_complet_document || '.QXP' AS selected_source_name,
    certified.declared_bytes,
    certified.actual_bytes,
    certified.source_language,
    certified.source_suivi_id
FROM run_context context
LEFT JOIN certified_candidates certified
  ON certified.id_run = context.id_run
 AND certified.candidate_rank = 1
WHERE context.gabarit_source = 3;




/* ---------------------------------------------------------------------------
   QOFF-08 - DOC EOS documents selected by the Get_Taches rules
   Export: run_<ID>/06_selected_task_documents.csv

   MATCHED_DOCUMENT_COUNT=0 is a missing-document case. More than 1 exposes a
   duplicate task cursor row. This query does not retrieve document BLOBs.
   --------------------------------------------------------------------------- */
WITH document_task_context AS (
    SELECT DISTINCT
        run_record.id_run,
        run_record.id_statut_generation,
        suivi.id_suivi,
        suivi.id_fnd_code,
        suivi.id_unit_code,
        suivi.id_langue,
        suivi.date_echeance,
        fond_gabarit.societe,
        task.id_tache,
        task.id_sous_categorie,
        task.conserver_style,
        task.rotation_image,
        task.crop_image_values,
        task.position_image,
        task.bloc_source,
        task.bloc_destination,
        category.id_type_categorie
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
     AND suivi.id_run_suivant = run_record.id_run
    JOIN qxp_asso_fond_gabarit fond_gabarit
      ON fond_gabarit.id_type_rapport = suivi.id_type_rapport
     AND fond_gabarit.id_fnd_code = suivi.id_fnd_code
     AND fond_gabarit.id_langue = suivi.id_langue
     AND fond_gabarit.id_gabarit = suivi.id_gabarit
    JOIN qxp_asso_run_taches run_task
      ON run_task.id_run = run_record.id_run
    JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
     AND task.is_actif = 1
     AND task.id_type_tache = 2
    LEFT JOIN qxp_ref_sous_categorie subcategory
      ON subcategory.id_sous_categorie = task.id_sous_categorie
    LEFT JOIN qxp_ref_categorie category
      ON category.id_categorie = subcategory.id_categorie
    WHERE run_record.id_run = &RUN_ID
), selected_document_rows AS (
    SELECT
        task_context.*,
        document_row.id_document,
        document_row.format,
        document_row.date_echeance AS document_due_date,
        document_row.nom_complet_document,
        document_row.taille_document,
        CASE WHEN document_row.contenu IS NULL THEN NULL
             ELSE DBMS_LOB.GETLENGTH(document_row.contenu)
        END AS actual_document_bytes,
        COUNT(document_row.id_document) OVER (
            PARTITION BY task_context.id_run, task_context.id_tache
        ) AS matched_document_count
    FROM document_task_context task_context
    LEFT JOIN qxp_document document_row
      ON document_row.id_sous_categorie = task_context.id_sous_categorie
     AND document_row.is_actif = 1
     AND document_row.id_langue = task_context.id_langue
     AND (
            (task_context.id_type_categorie = 1
             AND document_row.id_fnd_code = task_context.id_fnd_code)
         OR (task_context.id_type_categorie = 2
             AND document_row.societe = task_context.societe)
         OR (task_context.id_type_categorie = 3
             AND document_row.id_fnd_code = task_context.id_fnd_code
             AND document_row.id_unit_code = task_context.id_unit_code)
     )
     AND (
            (task_context.id_sous_categorie IN (5, 10)
             AND document_row.date_echeance = (
                 SELECT MAX(candidate.date_echeance)
                 FROM qxp_document candidate
                 WHERE candidate.id_sous_categorie = task_context.id_sous_categorie
                   AND candidate.id_langue = task_context.id_langue
                   AND candidate.societe = task_context.societe
                   AND candidate.date_echeance <= task_context.date_echeance
             ))
         OR (task_context.id_sous_categorie NOT IN (5, 10)
             AND document_row.date_echeance = task_context.date_echeance)
     )
)
SELECT
    id_run,
    id_statut_generation,
    id_suivi,
    id_tache,
    id_sous_categorie,
    id_type_categorie,
    id_document,
    format,
    TO_CHAR(document_due_date, 'YYYY-MM-DD HH24:MI:SS') AS document_due_date,
    nom_complet_document,
    taille_document,
    actual_document_bytes,
    conserver_style,
    rotation_image,
    crop_image_values,
    position_image,
    CASE WHEN bloc_source IS NULL THEN '<NULL>'
         ELSE '[' || bloc_source || ']'
    END AS bloc_source_exact,
    LENGTH(bloc_source) AS bloc_source_length,
    CASE WHEN bloc_destination IS NULL THEN '<NULL>'
         ELSE '[' || bloc_destination || ']'
    END AS bloc_destination_exact,
    LENGTH(bloc_destination) AS bloc_destination_length,
    matched_document_count
FROM selected_document_rows
ORDER BY id_tache, id_document;



/* ---------------------------------------------------------------------------
   QOFF-08B - Previous certified QXP selected for type-3 tasks
   Export: run_<ID>/06b_previous_qxp_task_documents.csv

   Reconstructs QXP_PK_RUN.Get_Last_Qxp_Certifie without selecting BLOB data.
   "any" resolves to report type 0 (any type); "same", null, blank or zero
   resolves to the current report type. Non-integer/custom-formatted values are
   flagged for review because Java resolves them using effective formatting.
   --------------------------------------------------------------------------- */
WITH task_context AS (
    SELECT
        run_record.id_run,
        run_record.id_statut_generation,
        suivi.id_suivi,
        suivi.id_fnd_code,
        suivi.id_type_rapport AS current_report_type,
        suivi.id_langue,
        suivi.date_echeance,
        task.id_tache,
        task.previous_type_rapport,
        task.bloc_source,
        task.bloc_destination
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
     AND suivi.id_run_suivant = run_record.id_run
    JOIN qxp_asso_run_taches run_task
      ON run_task.id_run = run_record.id_run
    JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
     AND task.is_actif = 1
     AND task.id_type_tache = 3
    JOIN qxp_asso_gabarit_taches gabarit_task
      ON gabarit_task.id_gabarit = suivi.id_gabarit
     AND gabarit_task.id_tache = task.id_tache
    WHERE run_record.id_run = &RUN_ID
), resolved_context AS (
    SELECT
        task_context.*,
        CASE
            WHEN LOWER(TRIM(task_context.previous_type_rapport)) = 'any' THEN 0
            WHEN TRIM(task_context.previous_type_rapport) IS NULL
              OR LOWER(TRIM(task_context.previous_type_rapport)) = 'same'
            THEN task_context.current_report_type
            WHEN LENGTH(TRIM(task_context.previous_type_rapport)) <= 11
             AND REGEXP_LIKE(TRIM(task_context.previous_type_rapport), '^[+-]?[[:digit:]]+$')
            THEN CASE
                    WHEN TO_NUMBER(TRIM(task_context.previous_type_rapport)) = 0
                    THEN task_context.current_report_type
                    WHEN TO_NUMBER(TRIM(task_context.previous_type_rapport))
                             BETWEEN -2147483648 AND 2147483647
                    THEN TO_NUMBER(TRIM(task_context.previous_type_rapport))
                    ELSE NULL
                 END
            ELSE NULL
        END AS resolved_previous_report_type,
        CASE
            WHEN LOWER(TRIM(task_context.previous_type_rapport)) = 'any'
            THEN 'ANY_REPORT_TYPE'
            WHEN TRIM(task_context.previous_type_rapport) IS NULL
              OR LOWER(TRIM(task_context.previous_type_rapport)) = 'same'
            THEN 'CURRENT_REPORT_TYPE'
            WHEN LENGTH(TRIM(task_context.previous_type_rapport)) <= 11
             AND REGEXP_LIKE(TRIM(task_context.previous_type_rapport), '^[+-]?[[:digit:]]+$')
            THEN CASE
                    WHEN TO_NUMBER(TRIM(task_context.previous_type_rapport))
                             BETWEEN -2147483648 AND 2147483647
                    THEN 'EXPLICIT_OR_ZERO_INTEGER'
                    ELSE 'REVIEW_OUT_OF_INT32_RANGE'
                 END
            ELSE 'REVIEW_EFFECTIVE_JAVA_FORMATTING'
        END AS previous_type_resolution
    FROM task_context
), certified_candidates AS (
    SELECT
        context.id_run,
        context.id_tache,
        previous_suivi.id_suivi AS previous_suivi_id,
        previous_suivi.id_type_rapport AS previous_report_type,
        previous_suivi.date_echeance AS previous_due_date,
        certified.id_document,
        certified.nom_complet_document,
        certified.taille_document AS declared_bytes,
        CASE WHEN certified.contenu IS NULL THEN NULL
             ELSE DBMS_LOB.GETLENGTH(certified.contenu)
        END AS actual_bytes,
        COUNT(*) OVER (
            PARTITION BY context.id_run, context.id_tache
        ) AS matched_document_count,
        ROW_NUMBER() OVER (
            PARTITION BY context.id_run, context.id_tache
            ORDER BY previous_suivi.date_echeance DESC
        ) AS candidate_rank
    FROM resolved_context context
    JOIN qxp_suivi previous_suivi
      ON previous_suivi.id_fnd_code = context.id_fnd_code
     AND previous_suivi.id_suivi <> context.id_suivi
     AND previous_suivi.date_echeance < context.date_echeance
     AND (previous_suivi.id_type_rapport = context.resolved_previous_report_type
          OR context.resolved_previous_report_type = 0)
    JOIN qxp_document_certifie certified
      ON certified.id_document = previous_suivi.id_qxp_certifie
    JOIN qxp_ref_langue_document previous_language
      ON previous_language.id_langue_document = previous_suivi.id_langue
    JOIN qxp_ref_langue_document current_language
      ON current_language.id_langue_document = context.id_langue
     AND SUBSTR(current_language.valeur_langue, 1, 2)
         = SUBSTR(previous_language.valeur_langue, 1, 2)
)
SELECT
    context.id_run,
    context.id_statut_generation,
    context.id_suivi,
    context.id_tache,
    context.previous_type_rapport AS configured_previous_type,
    context.resolved_previous_report_type,
    context.previous_type_resolution,
    candidate.previous_suivi_id,
    candidate.previous_report_type,
    TO_CHAR(candidate.previous_due_date, 'YYYY-MM-DD HH24:MI:SS') AS previous_due_date,
    candidate.id_document,
    candidate.nom_complet_document,
    'QXP' AS format,
    candidate.declared_bytes,
    candidate.actual_bytes,
    NVL(candidate.matched_document_count, 0) AS matched_document_count,
    CASE WHEN context.bloc_source IS NULL THEN '<NULL>'
         ELSE '[' || context.bloc_source || ']'
    END AS bloc_source_exact,
    LENGTH(context.bloc_source) AS bloc_source_length,
    CASE WHEN context.bloc_destination IS NULL THEN '<NULL>'
         ELSE '[' || context.bloc_destination || ']'
    END AS bloc_destination_exact,
    LENGTH(context.bloc_destination) AS bloc_destination_length,
    CASE
        WHEN context.resolved_previous_report_type IS NULL
        THEN 'STOP: previous report type needs effective-format review'
        WHEN candidate.id_document IS NULL THEN 'STOP: no previous certified QXP selected'
        WHEN candidate.actual_bytes <= 0 THEN 'STOP: selected certified QXP is empty'
        ELSE 'PASS'
    END AS previous_qxp_readiness
FROM resolved_context context
LEFT JOIN certified_candidates candidate
  ON candidate.id_run = context.id_run
 AND candidate.id_tache = context.id_tache
 AND candidate.candidate_rank = 1
ORDER BY context.id_tache;



/* ---------------------------------------------------------------------------
   QOFF-09 - Compartment child-run selection for this parent run
   Export before: run_<ID>/07_pre_compartment_children.csv
   Export after : run_<ID>/15_post_compartment_children.csv
   Empty output is expected for a non-compartment run.
   --------------------------------------------------------------------------- */
WITH parent_context AS (
    SELECT DISTINCT
        parent_run.id_run AS parent_run_id,
        run_task.id_tache,
        parent_suivi.id_gabarit AS id_gabarit_tete,
        parent_suivi.id_fnd_code AS id_structure,
        task.id_gabarit_fils,
        parent_suivi.id_langue,
        parent_suivi.date_echeance,
        parent_run.mode_compart
    FROM qxp_asso_run_taches run_task
    JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
     AND task.is_actif = 1
     AND task.id_type_tache = 5
    JOIN qxp_run parent_run
      ON parent_run.id_run = run_task.id_run
     AND parent_run.id_run = &RUN_ID
    JOIN qxp_suivi parent_suivi
      ON parent_suivi.id_suivi = parent_run.id_suivi
), child_selection AS (
    SELECT
        parent.parent_run_id,
        parent.id_tache,
        parent.mode_compart,
        compartment_link.position AS child_position,
        compartment_link.id_fnd_code AS child_fnd_code,
        child_suivi.id_suivi AS child_suivi_id,
        CASE
            WHEN BITAND(NVL(parent.mode_compart, 0), 1) = 1
            THEN child_suivi.id_run_suivant
            ELSE child_suivi.id_run_precedent
        END AS selected_child_run_id
    FROM parent_context parent
    JOIN qxp_asso_struct_gabarit_comp compartment_link
      ON compartment_link.id_structure = parent.id_structure
     AND compartment_link.id_gabarit = parent.id_gabarit_tete
    LEFT JOIN qxp_suivi child_suivi
      ON child_suivi.id_fnd_code = compartment_link.id_fnd_code
     AND child_suivi.id_langue = parent.id_langue
     AND child_suivi.id_gabarit = parent.id_gabarit_fils
     AND child_suivi.date_echeance = parent.date_echeance
     AND child_suivi.id_type_rapport = 4
)
SELECT
    selection.parent_run_id,
    selection.id_tache,
    selection.mode_compart,
    selection.child_position,
    selection.child_fnd_code,
    selection.child_suivi_id,
    selection.selected_child_run_id,
    child_run.id_statut_generation AS child_run_status,
    child_status.libelle AS child_status_label,
    child_run.id_doc_qxp AS child_qxp_document_id,
    TO_CHAR(child_run.date_debut_generation, 'YYYY-MM-DD HH24:MI:SS') AS child_start_time,
    TO_CHAR(child_run.date_fin_generation, 'YYYY-MM-DD HH24:MI:SS') AS child_end_time
FROM child_selection selection
LEFT JOIN qxp_run child_run
  ON child_run.id_run = selection.selected_child_run_id
LEFT JOIN qxp_ref_statut_generation child_status
  ON child_status.id_statut_generation = child_run.id_statut_generation
ORDER BY selection.id_tache, selection.child_position,
         selection.child_fnd_code, selection.child_suivi_id;




/* ---------------------------------------------------------------------------
   QOFF-10 - Current SQL-client NLS values
   Export: session/04_sql_client_nls.csv

   This describes this SQL client session, not a Java pool connection. Java's
   configured NLS is separately proven by connected task execution.
   --------------------------------------------------------------------------- */
SELECT parameter, value
FROM nls_session_parameters
WHERE parameter IN (
    'NLS_DATE_FORMAT',
    'NLS_DATE_LANGUAGE',
    'NLS_NUMERIC_CHARACTERS',
    'NLS_TERRITORY'
)
ORDER BY parameter;

