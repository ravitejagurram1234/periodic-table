/* ---------------------------------------------------------------------------
   QOFF-01G - Bounded old-UI run-creation exception evidence
   Export: planning/08_ui_creation_error_evidence.csv

   Use when QOFF-01F has no matching committed run. QXP.Framework writes to
   QXP_LOG by default when UseLog4Net is not enabled. This query returns only
   recent run/task/WCF creation messages, a bounded ORA excerpt and a bounded
   first exception line. It does not return an entire stack trace.

   If this returns no rows, obtain the deployed WebSite UseLog4Net setting and
   the corresponding bounded log entries from operations. Never export an
   entire log file or credentials.
   --------------------------------------------------------------------------- */
SELECT
    TO_CHAR(log_entry.log_date, 'YYYY-MM-DD HH24:MI:SS') AS log_time,
    log_entry.log_type,
    log_entry.log_message,
    REGEXP_SUBSTR(
        REPLACE(REPLACE(log_entry.log_info, CHR(13), ' '), CHR(10), ' '),
        'ORA-[[:digit:]]{5}:.{0,500}'
    ) AS oracle_error_excerpt,
    SUBSTR(
        log_entry.log_info,
        1,
        LEAST(
            600,
            CASE
                WHEN INSTR(log_entry.log_info, CHR(10)) > 0
                THEN INSTR(log_entry.log_info, CHR(10)) - 1
                ELSE NVL(LENGTH(log_entry.log_info), 0)
            END
        )
    ) AS exception_head,
    NVL(LENGTH(log_entry.log_info), 0) AS full_exception_chars
FROM qxp_log log_entry
WHERE log_entry.log_date >= SYSDATE - 2
  AND (
        log_entry.log_message = 'CreationRunKO'
        OR LOWER(log_entry.log_message) LIKE '%run%'
        OR LOWER(log_entry.log_message) LIKE '%tache%'
        OR LOWER(log_entry.log_message) LIKE '%wcf%'
      )
ORDER BY log_entry.log_date DESC
FETCH FIRST 20 ROWS ONLY;

