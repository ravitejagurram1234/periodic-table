
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

