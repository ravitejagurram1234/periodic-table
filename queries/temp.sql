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
