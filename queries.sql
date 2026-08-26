/*
===============================================================================
EOS Quark Engine - office live-run evidence queries
===============================================================================

Purpose
  Read-only Oracle queries used with:
    EOS_Quark_Office_Live_Run_Evidence_Capture_Guide.md

Safety
  - This file contains SELECT statements only.
  - Never execute Start_Run, End_Run, Update_Status_Run, INSERT, UPDATE or DELETE
    manually for evidence collection.
  - Historical run IDs returned by candidate queries are examples/evidence
    selectors. Never submit them to the Java processRun endpoint.
  - Replace RUN_ID only with the fresh run created by the normal application
    workflow for this test.
  - LOG_TRACE, parameter values, errors and stored values may contain business
    data. Keep exports in the approved evidence location.

Usage
  1. Run QOFF-00, QOFF-01 and QOFF-01A to select a historical baseline.
  2. Recreate that business case through the normal UI/backend workflow.
  3. Set CREATED_AFTER and FUND_CODE, then use QOFF-02 to locate the fresh ID.
  4. Set RUN_ID to that fresh ID and require QOFF-02B to return PASS.
  5. Run/export each QOFF block separately so its result has the filename shown.
  6. Execute the PRE blocks before POST /processRun and the POST blocks
     afterwards as directed by the companion guide.

The statements use Oracle SQL Developer/SQLcl substitution variables.
===============================================================================
*/

SET VERIFY OFF

DEFINE RUN_ID = 0
DEFINE CREATED_AFTER = "25/08/2026 00:00:00"
DEFINE FUND_CODE = REPLACE_ME
DEFINE CANDIDATE_LOOKBACK_DAYS = 7300
DEFINE CANDIDATES_PER_GROUP = 10


/* ---------------------------------------------------------------------------
   QOFF-00 - Reference meanings (once per environment)
   Export: session/03_reference_codes.csv
   --------------------------------------------------------------------------- */
SELECT
    'RUN_STATUS' AS reference_type,
    TO_CHAR(status.id_statut_generation) AS reference_code,
    status.libelle AS label,
    status.traduction_code AS translation_code
FROM qxp_ref_statut_generation status
UNION ALL
SELECT
    'REPORT_TYPE',
    TO_CHAR(report_type.id_type_rapport),
    report_type.libelle,
    NULL
FROM qxp_ref_type_rapport report_type
UNION ALL
SELECT
    'TASK_TYPE',
    TO_CHAR(task_type.id_type_tache),
    task_type.libelle,
    NULL
FROM qxp_ref_type_tache task_type
UNION ALL
SELECT
    'LANGUAGE',
    TO_CHAR(language.id_langue_document),
    language.nom_langue,
    language.valeur_langue
FROM qxp_ref_langue_document language
UNION ALL
SELECT
    'ERROR_TYPE',
    TO_CHAR(error_type.id_type_error),
    error_type.code,
    NULL
FROM qxp_ref_type_error error_type
ORDER BY reference_type, reference_code;


/* ---------------------------------------------------------------------------
   QOFF-01 - Recent successful historical coverage candidates
   Export: planning/01_historical_candidate_profiles.csv

   Selection aid only. NEVER call processRun for an ID returned here.
   The flags show which functional branches appeared in each historical run.
   --------------------------------------------------------------------------- */
SELECT *
FROM (
    SELECT
        run_record.id_run,
        run_record.id_suivi,
        suivi.id_type_rapport,
        report_type.libelle AS report_type_label,
        suivi.id_fnd_code,
        suivi.id_unit_code,
        suivi.id_langue,
        language.nom_langue,
        suivi.id_gabarit,
        run_record.gabarit_source,
        run_record.mode_compart,
        gabarit.pagination_double,
        NVL(gabarit.store_data_type, 0) AS store_data_type,
        COUNT(DISTINCT run_task.id_tache) AS task_count,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 1 THEN task.id_tache END) AS sql_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 2 THEN task.id_tache END) AS document_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 3 THEN task.id_tache END) AS qxp_block_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 4 THEN task.id_tache END) AS dynamic_tasks,
        COUNT(DISTINCT CASE WHEN task.id_type_tache = 5 THEN task.id_tache END) AS compartment_tasks,
        COUNT(DISTINCT CASE
            WHEN task.id_type_tache = 4 AND task.control_overflow = 1
            THEN task.id_tache
        END) AS overflow_control_tasks,
        COUNT(DISTINCT CASE WHEN task.store_data = 1 THEN task.id_tache END) AS task_storage_tasks,
        TO_CHAR(run_record.date_creation_run, 'YYYY-MM-DD HH24:MI:SS') AS creation_time,
        TO_CHAR(run_record.date_debut_generation, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
        TO_CHAR(run_record.date_fin_generation, 'YYYY-MM-DD HH24:MI:SS') AS end_time,
        run_record.id_doc_qxp,
        run_record.id_doc_pdf,
        run_record.id_doc_doc
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    JOIN qxp_gabarit gabarit
      ON gabarit.id_gabarit = suivi.id_gabarit
    LEFT JOIN qxp_ref_type_rapport report_type
      ON report_type.id_type_rapport = suivi.id_type_rapport
    LEFT JOIN qxp_ref_langue_document language
      ON language.id_langue_document = suivi.id_langue
    LEFT JOIN qxp_asso_run_taches run_task
      ON run_task.id_run = run_record.id_run
    LEFT JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
    WHERE run_record.id_statut_generation = 2
    GROUP BY
        run_record.id_run,
        run_record.id_suivi,
        suivi.id_type_rapport,
        report_type.libelle,
        suivi.id_fnd_code,
        suivi.id_unit_code,
        suivi.id_langue,
        language.nom_langue,
        suivi.id_gabarit,
        run_record.gabarit_source,
        run_record.mode_compart,
        gabarit.pagination_double,
        NVL(gabarit.store_data_type, 0),
        run_record.date_creation_run,
        run_record.date_debut_generation,
        run_record.date_fin_generation,
        run_record.id_doc_qxp,
        run_record.id_doc_pdf,
        run_record.id_doc_doc
    ORDER BY NVL(
        run_record.date_fin_generation,
        NVL(run_record.date_debut_generation, run_record.date_creation_run)
    ) DESC NULLS LAST
)
FETCH FIRST 200 ROWS ONLY;


/* ---------------------------------------------------------------------------
   QOFF-01A - Ranked valid baselines by scenario, report type and compartment mode
   Export: planning/02_ranked_scenario_candidates.csv

   Selection aid only. NEVER call processRun for an ID returned here.

   SIMPLE      = selected active change tasks, but no dynamic/compartment task
   DYNAMIC     = at least one selected active type-4 task
   COMPARTMENT = at least one selected active type-5 task

   A candidate must have selected active tasks and a non-empty generated QXP.
   This proves historical reachability, not that a future fresh run has the same
   inputs. Recreate the business configuration and validate the fresh ID with
   QOFF-02, QOFF-02B and all mandatory pre-run queries.
   --------------------------------------------------------------------------- */
WITH run_profile AS (
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
        run_record.date_fin_generation,
        run_record.id_doc_qxp,
        run_record.id_doc_pdf,
        run_record.id_doc_doc,
        (SELECT DBMS_LOB.GETLENGTH(output_qxp.contenu)
           FROM qxp_document output_qxp
          WHERE output_qxp.id_document = run_record.id_doc_qxp
        ) AS output_qxp_bytes,
        (SELECT COUNT(*)
           FROM qxp_run_error error_row
          WHERE error_row.id_run = run_record.id_run
        ) AS historical_error_count
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    JOIN qxp_gabarit gabarit
      ON gabarit.id_gabarit = suivi.id_gabarit
    LEFT JOIN qxp_ref_type_rapport report_type
      ON report_type.id_type_rapport = suivi.id_type_rapport
    LEFT JOIN qxp_ref_langue_document language
      ON language.id_langue_document = suivi.id_langue
    JOIN qxp_asso_run_taches run_task
      ON run_task.id_run = run_record.id_run
    JOIN qxp_tache task
      ON task.id_tache = run_task.id_tache
     AND task.is_actif = 1
    WHERE run_record.id_statut_generation = 2
      AND run_record.id_doc_qxp IS NOT NULL
      AND run_record.date_fin_generation >= SYSDATE - &CANDIDATE_LOOKBACK_DAYS
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
        run_record.date_fin_generation,
        run_record.id_doc_qxp,
        run_record.id_doc_pdf,
        run_record.id_doc_doc
), classified AS (
    SELECT
        profile.*,
        CASE
            WHEN profile.compartment_tasks > 0 THEN 'COMPARTMENT'
            WHEN profile.dynamic_tasks > 0 THEN 'DYNAMIC'
            ELSE 'SIMPLE'
        END AS scenario_class
    FROM run_profile profile
    WHERE profile.selected_active_task_count > 0
      AND profile.selected_change_task_count > 0
      AND profile.output_qxp_bytes > 0
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
            ORDER BY classified.date_fin_generation DESC,
                     classified.id_run DESC
        ) AS candidate_rank
    FROM classified
)
SELECT
    scenario_class,
    candidate_rank,
    id_run,
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
    overflow_control_tasks,
    task_storage_tasks,
    historical_error_count,
    output_qxp_bytes,
    id_doc_qxp,
    id_doc_pdf,
    id_doc_doc,
    TO_CHAR(date_creation_run, 'YYYY-MM-DD HH24:MI:SS') AS creation_time,
    TO_CHAR(date_fin_generation, 'YYYY-MM-DD HH24:MI:SS') AS end_time
FROM ranked
WHERE candidate_rank <= &CANDIDATES_PER_GROUP
ORDER BY scenario_class, id_type_rapport,
         NVL(mode_compart, -1), candidate_rank;


/* ---------------------------------------------------------------------------
   QOFF-02 - Locate the fresh run just created by the normal UI/backend flow
   Export: run_<ID>/00_new_run_candidates.csv

   Set CREATED_AFTER and FUND_CODE before running. Confirm the chosen row in
   the UI and with QOFF-03; do not pick a row merely because it is newest.
   --------------------------------------------------------------------------- */
SELECT
    run_record.id_run,
    run_record.id_suivi,
    run_record.id_statut_generation,
    status.libelle AS run_status_label,
    TO_CHAR(run_record.date_creation_run, 'YYYY-MM-DD HH24:MI:SS') AS creation_time,
    suivi.id_fnd_code,
    suivi.id_unit_code,
    suivi.id_type_rapport,
    report_type.libelle AS report_type_label,
    suivi.id_langue,
    language.nom_langue,
    TO_CHAR(suivi.date_echeance, 'YYYY-MM-DD HH24:MI:SS') AS due_date,
    suivi.id_gabarit,
    suivi.id_run_precedent,
    suivi.id_run_suivant,
    run_record.gabarit_source,
    run_record.mode_compart
FROM qxp_run run_record
JOIN qxp_suivi suivi
  ON suivi.id_suivi = run_record.id_suivi
LEFT JOIN qxp_ref_statut_generation status
  ON status.id_statut_generation = run_record.id_statut_generation
LEFT JOIN qxp_ref_type_rapport report_type
  ON report_type.id_type_rapport = suivi.id_type_rapport
LEFT JOIN qxp_ref_langue_document language
  ON language.id_langue_document = suivi.id_langue
WHERE run_record.date_creation_run >= TO_DATE('&CREATED_AFTER', 'DD/MM/YYYY HH24:MI:SS')
  AND suivi.id_fnd_code = '&FUND_CODE'
ORDER BY run_record.date_creation_run DESC
FETCH FIRST 20 ROWS ONLY;


/* ---------------------------------------------------------------------------
   QOFF-02B - Fresh-run basic admission and selected-task validation
   Export: run_<ID>/00_fresh_run_validation.csv

   Run after QOFF-02 identifies the new ID and before any engine GET/POST.
   BASIC_ADMISSION_RESULT must be PASS. This query validates the normal batch
   handoff and proves that the run has active selected work. QOFF-07B, QOFF-08
   and QOFF-09 still validate source documents and branch-specific inputs.
   --------------------------------------------------------------------------- */
WITH fresh_profile AS (
    SELECT
        run_record.id_run,
        run_record.id_suivi,
        run_record.id_statut_generation,
        status.libelle AS run_status_label,
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
        WHEN profile.id_statut_generation <> 5 THEN 'STOP: status is not batch-reserved (5)'
        WHEN profile.is_current_suivi_run <> 1 THEN 'STOP: run is not ID_RUN_SUIVANT'
        WHEN profile.run_property_match_count <> 1 THEN 'STOP: run-property association count is not 1'
        WHEN profile.gabarit_is_active <> 1 OR profile.configured_gabarit_bytes <= 0
          THEN 'STOP: configured gabarit is unavailable'
        WHEN profile.selected_todo_task_count <= 0 THEN 'STOP: no selected active task'
        WHEN profile.date_debut_generation IS NOT NULL
          OR profile.date_fin_generation IS NOT NULL
          THEN 'STOP: run already has generation timestamps'
        WHEN profile.id_doc_qxp IS NOT NULL
          OR profile.id_doc_pdf IS NOT NULL
          OR profile.id_doc_doc IS NOT NULL
          THEN 'STOP: run already has generated document links'
        ELSE 'PASS'
    END AS basic_admission_result
FROM fresh_profile profile;


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


/* ---------------------------------------------------------------------------
   QOFF-11 - Persisted run errors after execution
   Export: run_<ID>/11_errors.csv

   Preserve duplicate rows. The table has no ordering column, so comparison is
   by (error type, message, multiplicity), not display order.
   --------------------------------------------------------------------------- */
SELECT
    run_error.id_run,
    run_error.id_type_error,
    error_type.code AS error_type_code,
    run_error.message,
    LENGTH(run_error.message) AS message_length
FROM qxp_run_error run_error
LEFT JOIN qxp_ref_type_error error_type
  ON error_type.id_type_error = run_error.id_type_error
WHERE run_error.id_run = &RUN_ID
ORDER BY run_error.id_type_error, run_error.message;


/* ---------------------------------------------------------------------------
   QOFF-12 - Run audit rows after execution
   Export: run_<ID>/12_audit.csv
   --------------------------------------------------------------------------- */
SELECT
    audit.id_audit_run,
    audit.id_run,
    audit.id_suivi,
    audit.run_type,
    TO_CHAR(audit.start_date, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
    TO_CHAR(audit.end_date, 'YYYY-MM-DD HH24:MI:SS') AS end_time,
    audit.duration,
    audit.end_status,
    audit.message
FROM qxp_audit_run audit
WHERE audit.id_run = &RUN_ID
ORDER BY audit.id_audit_run;


/* ---------------------------------------------------------------------------
   QOFF-13 - Generated output-document metadata after execution
   Export: run_<ID>/13_documents.csv

   Raw generated files must also be downloaded through the approved normal
   mechanism. This query intentionally does not select BLOB content.
   --------------------------------------------------------------------------- */
WITH run_documents AS (
    SELECT run_record.id_run, 'QXP' AS document_role, run_record.id_doc_qxp AS id_document
    FROM qxp_run run_record
    WHERE run_record.id_run = &RUN_ID
    UNION ALL
    SELECT run_record.id_run, 'PDF', run_record.id_doc_pdf
    FROM qxp_run run_record
    WHERE run_record.id_run = &RUN_ID
    UNION ALL
    SELECT run_record.id_run, 'DOC', run_record.id_doc_doc
    FROM qxp_run run_record
    WHERE run_record.id_run = &RUN_ID
)
SELECT
    selected.id_run,
    selected.document_role,
    selected.id_document,
    document_row.format,
    document_row.nom_complet_document,
    document_row.id_langue,
    document_row.id_sous_categorie,
    document_row.id_fnd_code,
    document_row.id_unit_code,
    TO_CHAR(document_row.date_echeance, 'YYYY-MM-DD HH24:MI:SS') AS document_due_date,
    TO_CHAR(document_row.date_creation_sys, 'YYYY-MM-DD HH24:MI:SS') AS document_creation_time,
    document_row.taille_document AS declared_document_size,
    CASE WHEN document_row.contenu IS NULL THEN NULL
         ELSE DBMS_LOB.GETLENGTH(document_row.contenu)
    END AS actual_document_bytes,
    document_row.is_actif
FROM run_documents selected
LEFT JOIN qxp_document document_row
  ON document_row.id_document = selected.id_document
ORDER BY selected.document_role;


/* ---------------------------------------------------------------------------
   QOFF-14A - Stored-data summary after execution
   Export: run_<ID>/14_storage_summary.csv
   --------------------------------------------------------------------------- */
SELECT
    stored_data.id_run,
    stored_data.id_suivi,
    stored_data.data_type,
    COUNT(*) AS stored_row_count,
    TO_CHAR(MIN(stored_data.date_generation), 'YYYY-MM-DD HH24:MI:SS') AS first_generation_time,
    TO_CHAR(MAX(stored_data.date_generation), 'YYYY-MM-DD HH24:MI:SS') AS last_generation_time,
    SUM(CASE WHEN stored_data.valeur_bloc IS NULL THEN 1 ELSE 0 END) AS null_values,
    SUM(CASE WHEN stored_data.description_bloc IS NULL THEN 1 ELSE 0 END) AS null_descriptions,
    SUM(CASE WHEN stored_data.info_bloc IS NULL THEN 1 ELSE 0 END) AS null_info
FROM qxp_data_storage stored_data
WHERE stored_data.id_run = &RUN_ID
GROUP BY stored_data.id_run, stored_data.id_suivi, stored_data.data_type
ORDER BY stored_data.data_type;


/* ---------------------------------------------------------------------------
   QOFF-14B - Complete stored-data rows after execution
   Export: run_<ID>/14_storage_rows.csv

   Zero rows are valid when storage is not configured for the selected run.
   --------------------------------------------------------------------------- */
SELECT
    stored_data.id_suivi,
    stored_data.id_run,
    TO_CHAR(stored_data.date_generation, 'YYYY-MM-DD HH24:MI:SS') AS generation_time,
    stored_data.data_type,
    stored_data.nom_bloc,
    stored_data.valeur_bloc,
    stored_data.description_bloc,
    stored_data.info_bloc
FROM qxp_data_storage stored_data
WHERE stored_data.id_run = &RUN_ID
ORDER BY stored_data.data_type, stored_data.nom_bloc,
         stored_data.valeur_bloc, stored_data.description_bloc,
         stored_data.info_bloc;


/* ---------------------------------------------------------------------------
   QOFF-15 - Complete persisted LOG_TRACE in ordered 1,000-character chunks
   Export: run_<ID>/09_persisted_trace_chunks.csv

   Reassemble CHUNK_TEXT strictly by CHUNK_NUMBER. MAX 10,000 chunks supports
   the current 3 MiB trace limit with room for future configuration changes.
   Search the export for TRACE_TRUNCATED; if present, record it as a finding.
   --------------------------------------------------------------------------- */
WITH chunk_numbers AS (
    SELECT LEVEL AS chunk_number
    FROM dual
    CONNECT BY LEVEL <= 10000
), selected_trace AS (
    SELECT run_record.id_run, run_record.log_trace
    FROM qxp_run run_record
    WHERE run_record.id_run = &RUN_ID
      AND run_record.log_trace IS NOT NULL
)
SELECT
    trace.id_run,
    chunks.chunk_number,
    DBMS_LOB.SUBSTR(
        trace.log_trace,
        1000,
        ((chunks.chunk_number - 1) * 1000) + 1
    ) AS chunk_text
FROM selected_trace trace
JOIN chunk_numbers chunks
  ON chunks.chunk_number <= CEIL(DBMS_LOB.GETLENGTH(trace.log_trace) / 1000)
ORDER BY chunks.chunk_number;


/* ---------------------------------------------------------------------------
   QOFF-16 - Compact completion check
   Export: run_<ID>/16_completion_check.csv
   --------------------------------------------------------------------------- */
SELECT
    run_record.id_run,
    run_record.id_statut_generation,
    status.libelle AS status_label,
    CASE WHEN run_record.date_debut_generation IS NULL THEN 0 ELSE 1 END AS has_start_time,
    CASE WHEN run_record.date_fin_generation IS NULL THEN 0 ELSE 1 END AS has_end_time,
    CASE WHEN run_record.log_trace IS NULL THEN 0 ELSE DBMS_LOB.GETLENGTH(run_record.log_trace) END AS trace_length,
    CASE WHEN DBMS_LOB.INSTR(run_record.log_trace, 'TRACE_TRUNCATED') > 0 THEN 1 ELSE 0 END AS trace_truncated,
    (SELECT COUNT(*) FROM qxp_run_error error_row
      WHERE error_row.id_run = run_record.id_run) AS error_count,
    (SELECT COUNT(*) FROM qxp_audit_run audit
      WHERE audit.id_run = run_record.id_run) AS audit_count,
    (SELECT COUNT(*) FROM qxp_data_storage stored_data
      WHERE stored_data.id_run = run_record.id_run) AS storage_row_count,
    run_record.id_doc_qxp,
    run_record.id_doc_pdf,
    run_record.id_doc_doc
FROM qxp_run run_record
LEFT JOIN qxp_ref_statut_generation status
  ON status.id_statut_generation = run_record.id_statut_generation
WHERE run_record.id_run = &RUN_ID;


/* ---------------------------------------------------------------------------
   QOFF-17 - Post-run persisted-trace milestone check
   Export: run_<ID>/17_trace_milestones.csv

   TRACE_EVIDENCE_RESULT=PASS proves that a non-degraded test reached task
   processing, at least one QXPS modification step, final QXP fetch and End.
   It does not replace the complete QOFF-15 export or visual artifact checks.
   --------------------------------------------------------------------------- */
SELECT
    run_record.id_run,
    CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'Run ' || TO_CHAR(run_record.id_run) || ' started'), 0) > 0
         THEN 1 ELSE 0 END AS has_run_started,
    CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'Run loaded (modeDegrade=false)'), 0) > 0
         THEN 1 ELSE 0 END AS has_non_degraded_load,
    CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'Tasks prepared and processed'), 0) > 0
         THEN 1 ELSE 0 END AS has_task_processing,
    CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'Step '), 0) > 0
         AND NVL(DBMS_LOB.INSTR(run_record.log_trace,
             ' executing, add='), 0) > 0
         THEN 1 ELSE 0 END AS has_qxps_step_execution,
    CASE WHEN REGEXP_LIKE(
             run_record.log_trace,
             ' executing, add=[1-9][[:digit:]]*,|, update=[1-9][[:digit:]]*,|, excluded=[1-9][[:digit:]]*,'
         )
         THEN 1 ELSE 0 END AS has_nonzero_step_change,
    CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'Modification steps executed'), 0) > 0
         THEN 1 ELSE 0 END AS has_modification_completion,
    CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'QXP literal fetch completed, bytes='), 0) > 0
         THEN 1 ELSE 0 END AS has_qxp_render_result,
    CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'End attempt=1'), 0) > 0
         THEN 1 ELSE 0 END AS has_end_attempt,
    CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'TRACE_TRUNCATED'), 0) > 0
         THEN 1 ELSE 0 END AS trace_truncated,
    CASE
        WHEN run_record.id_statut_generation = 2
         AND NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'Run loaded (modeDegrade=false)'), 0) > 0
         AND NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'Tasks prepared and processed'), 0) > 0
         AND NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'Step '), 0) > 0
         AND NVL(DBMS_LOB.INSTR(run_record.log_trace,
             ' executing, add='), 0) > 0
         AND REGEXP_LIKE(
             run_record.log_trace,
             ' executing, add=[1-9][[:digit:]]*,|, update=[1-9][[:digit:]]*,|, excluded=[1-9][[:digit:]]*,'
         )
         AND NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'Modification steps executed'), 0) > 0
         AND NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'QXP literal fetch completed, bytes='), 0) > 0
         AND NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'End attempt=1'), 0) > 0
         AND NVL(DBMS_LOB.INSTR(run_record.log_trace,
             'TRACE_TRUNCATED'), 0) = 0
        THEN 'PASS'
        ELSE 'REVIEW'
    END AS trace_evidence_result
FROM qxp_run run_record
WHERE run_record.id_run = &RUN_ID;
