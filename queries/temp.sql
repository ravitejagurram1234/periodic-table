
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

