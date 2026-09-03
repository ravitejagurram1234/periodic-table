
/* ===========================================================================
   QOFF-18 - CONTIGUOUS POST-RUN PACKET FOR RUN 505258

   Copy and execute QOFF-18A through QOFF-18E together. Paste those compact
   results into chat. Execute QOFF-18F separately and save its complete output
   as the trace evidence file; do not paste the trace chunks unless QOFF-18A
   reports REVIEW, TRACE_TRUNCATED=1, or a later investigation requests them.

   Purpose:
     Reconcile the successful REST/log result with committed Oracle state.

   Expected for run 505258:
     status=2, ordered start/end, error_count=0, audit_count=1,
     storage_row_count=0, QXP=1051258/3811328 bytes,
     PDF=1051259/524313 bytes, DOC null, TRACE_TRUNCATED=0,
     HAS_NONZERO_STEP_CHANGE=1 and TRACE_EVIDENCE_RESULT=PASS.

   Stop:
     Do not select or process another run if any expected value differs.
     Preserve the output and diagnose the difference without resetting 505258.
   =========================================================================== */

DEFINE RUN_ID = 505258


/* QOFF-18A - Compact run, persistence and trace summary. PASTE THIS RESULT. */
WITH run_evidence AS (
    SELECT
        run_record.*,
        suivi.id_statut_generation AS suivi_status_code,
        status.libelle AS run_status_label,
        CASE WHEN run_record.log_trace IS NULL
             THEN 0 ELSE DBMS_LOB.GETLENGTH(run_record.log_trace)
        END AS trace_length,
        CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
                  'TRACE_TRUNCATED'), 0) > 0 THEN 1 ELSE 0
        END AS trace_truncated,
        CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
                  'Run ' || TO_CHAR(run_record.id_run) || ' started'), 0) > 0
             THEN 1 ELSE 0
        END AS has_run_started,
        CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
                  'Run loaded (modeDegrade=false)'), 0) > 0
             THEN 1 ELSE 0
        END AS has_non_degraded_load,
        CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
                  'Tasks prepared and processed'), 0) > 0
             THEN 1 ELSE 0
        END AS has_task_processing,
        CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace, 'Step '), 0) > 0
               AND NVL(DBMS_LOB.INSTR(run_record.log_trace,
                   ' executing, add='), 0) > 0
             THEN 1 ELSE 0
        END AS has_qxps_step_execution,
        CASE WHEN REGEXP_LIKE(
                  run_record.log_trace,
                  ' executing, add=[1-9][[:digit:]]*,|, update=[1-9][[:digit:]]*,|, excluded=[1-9][[:digit:]]*,'
             ) THEN 1 ELSE 0
        END AS has_nonzero_step_change,
        CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
                  'Modification steps executed'), 0) > 0
             THEN 1 ELSE 0
        END AS has_modification_completion,
        CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
                  'QXP literal fetch completed, bytes='), 0) > 0
             THEN 1 ELSE 0
        END AS has_qxp_render_result,
        CASE WHEN NVL(DBMS_LOB.INSTR(run_record.log_trace,
                  'End attempt=1'), 0) > 0
             THEN 1 ELSE 0
        END AS has_end_attempt
    FROM qxp_run run_record
    JOIN qxp_suivi suivi
      ON suivi.id_suivi = run_record.id_suivi
    LEFT JOIN qxp_ref_statut_generation status
      ON status.id_statut_generation = run_record.id_statut_generation
    WHERE run_record.id_run = &RUN_ID
)
SELECT
    evidence.id_run,
    evidence.id_suivi,
    evidence.id_statut_generation AS run_status_code,
    evidence.run_status_label,
    evidence.suivi_status_code,
    TO_CHAR(evidence.date_debut_generation,
            'YYYY-MM-DD HH24:MI:SS') AS start_time,
    TO_CHAR(evidence.date_fin_generation,
            'YYYY-MM-DD HH24:MI:SS') AS end_time,
    CASE WHEN evidence.date_debut_generation IS NULL THEN 0 ELSE 1
    END AS has_start_time,
    CASE WHEN evidence.date_fin_generation IS NULL THEN 0 ELSE 1
    END AS has_end_time,
    evidence.trace_length,
    evidence.trace_truncated,
    (SELECT COUNT(*)
       FROM qxp_run_error error_row
      WHERE error_row.id_run = evidence.id_run) AS error_count,
    (SELECT COUNT(*)
       FROM qxp_audit_run audit
      WHERE audit.id_run = evidence.id_run) AS audit_count,
    (SELECT COUNT(*)
       FROM qxp_data_storage stored_data
      WHERE stored_data.id_run = evidence.id_run) AS storage_row_count,
    evidence.id_doc_qxp,
    (SELECT DBMS_LOB.GETLENGTH(document_row.contenu)
       FROM qxp_document document_row
      WHERE document_row.id_document = evidence.id_doc_qxp) AS qxp_actual_bytes,
    evidence.id_doc_pdf,
    (SELECT DBMS_LOB.GETLENGTH(document_row.contenu)
       FROM qxp_document document_row
      WHERE document_row.id_document = evidence.id_doc_pdf) AS pdf_actual_bytes,
    evidence.id_doc_doc,
    evidence.has_run_started,
    evidence.has_non_degraded_load,
    evidence.has_task_processing,
    evidence.has_qxps_step_execution,
    evidence.has_nonzero_step_change,
    evidence.has_modification_completion,
    evidence.has_qxp_render_result,
    evidence.has_end_attempt,
    CASE
        WHEN evidence.id_statut_generation = 2
         AND evidence.date_debut_generation IS NOT NULL
         AND evidence.date_fin_generation IS NOT NULL
         AND evidence.date_fin_generation >= evidence.date_debut_generation
         AND evidence.trace_truncated = 0
         AND evidence.has_run_started = 1
         AND evidence.has_non_degraded_load = 1
         AND evidence.has_task_processing = 1
         AND evidence.has_qxps_step_execution = 1
         AND evidence.has_nonzero_step_change = 1
         AND evidence.has_modification_completion = 1
         AND evidence.has_qxp_render_result = 1
         AND evidence.has_end_attempt = 1
        THEN 'PASS'
        ELSE 'REVIEW'
    END AS trace_evidence_result
FROM run_evidence evidence;


/* QOFF-18B - Persisted errors. PASTE THE RESULT; zero rows are expected. */
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


/* QOFF-18C - Audit evidence. PASTE THIS RESULT; one row is expected. */
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


/* QOFF-18D - Generated document evidence. PASTE THESE THREE ROLE ROWS. */
WITH run_documents AS (
    SELECT run_record.id_run, 'QXP' AS document_role,
           run_record.id_doc_qxp AS id_document
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
    TO_CHAR(document_row.date_echeance,
            'YYYY-MM-DD HH24:MI:SS') AS document_due_date,
    TO_CHAR(document_row.date_creation_sys,
            'YYYY-MM-DD HH24:MI:SS') AS document_creation_time,
    document_row.taille_document AS declared_document_size,
    CASE WHEN document_row.contenu IS NULL THEN NULL
         ELSE DBMS_LOB.GETLENGTH(document_row.contenu)
    END AS actual_document_bytes,
    document_row.is_actif
FROM run_documents selected
LEFT JOIN qxp_document document_row
  ON document_row.id_document = selected.id_document
ORDER BY selected.document_role;


/* QOFF-18E - Unexpected branch counts. PASTE THESE TWO COUNT ROWS. */
SELECT
    'STORAGE_ROWS' AS evidence_type,
    COUNT(*) AS row_count
FROM qxp_data_storage stored_data
WHERE stored_data.id_run = &RUN_ID
UNION ALL
SELECT
    'SELECTED_ACTIVE_COMPARTMENT_TASKS',
    COUNT(*)
FROM qxp_asso_run_taches run_task
JOIN qxp_tache task
  ON task.id_tache = run_task.id_tache
 AND task.is_actif = 1
 AND task.id_type_tache = 5
WHERE run_task.id_run = &RUN_ID;


/* ---------------------------------------------------------------------------
   QOFF-18F - Full persisted trace. RUN SEPARATELY AND SAVE ALL ROWS.

   Save as: run_505258/09_persisted_trace_chunks.csv
   Do not paste these chunks into chat now. Share only if QOFF-18A is REVIEW,
   trace_truncated=1, or a specific later comparison needs exact trace text.
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


