/* ---------------------------------------------------------------------------
   QOFF-01L - InsertSuiviTraduction contract and relevant source lines
   Export: planning/13_insert_suivi_traduction_contract.csv

   Run before ORA-QXP-SUIVI-COMPAT-01 to capture the deployed baseline and
   rerun after it to verify both email and numeric-user overloads. Returns the
   function arguments plus only its declaration and lines involving email,
   user identity, creator identity or InsertRun. It does not return the
   complete function or package. Read-only, bounded, and requires no
   substitution values.
   --------------------------------------------------------------------------- */
WITH source_lines AS (
    SELECT
        package_source.type AS source_type,
        package_source.line AS source_line,
        package_source.text AS source_text,
        LENGTH(package_source.text) - LENGTH(LTRIM(package_source.text))
            AS indentation
    FROM all_source package_source
    WHERE package_source.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
      AND package_source.name = 'QXP_PK_SUIVI'
      AND package_source.type IN ('PACKAGE', 'PACKAGE BODY')
), routine_starts AS (
    SELECT
        source_line.source_type,
        source_line.source_line AS start_line,
        source_line.indentation
    FROM source_lines source_line
    WHERE REGEXP_LIKE(
              source_line.source_text,
              '^[[:space:]]*FUNCTION[[:space:]]+INSERTSUIVITRADUCTION([[:space:]]|[(]|$)',
              'i'
          )
), routine_ranges AS (
    SELECT
        routine_start.source_type,
        routine_start.start_line,
        NVL(
            (
                SELECT MIN(next_routine.source_line) - 1
                FROM source_lines next_routine
                WHERE next_routine.source_type = routine_start.source_type
                  AND next_routine.source_line > routine_start.start_line
                  AND next_routine.indentation = routine_start.indentation
                  AND REGEXP_LIKE(
                          next_routine.source_text,
                          '^[[:space:]]*(FUNCTION|PROCEDURE)[[:space:]]+',
                          'i'
                      )
            ),
            (
                SELECT MAX(last_source_line.source_line)
                FROM source_lines last_source_line
                WHERE last_source_line.source_type = routine_start.source_type
            )
        ) AS end_line
    FROM routine_starts routine_start
), evidence AS (
    SELECT
        1 AS sort_order,
        'ARGUMENT' AS record_type,
        'PACKAGE' AS source_type,
        CAST(NULL AS NUMBER) AS source_line,
        package_argument.position,
        package_argument.argument_name,
        package_argument.data_type,
        package_argument.in_out,
        package_argument.defaulted,
        'SUBPROGRAM_ID=' || TO_CHAR(package_argument.subprogram_id)
            AS detail
    FROM all_arguments package_argument
    WHERE package_argument.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
      AND package_argument.package_name = 'QXP_PK_SUIVI'
      AND package_argument.object_name = 'INSERTSUIVITRADUCTION'
      AND package_argument.data_level = 0

    UNION ALL

    SELECT
        2,
        'SOURCE',
        source_line.source_type,
        source_line.source_line,
        CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(20)),
        CAST(NULL AS VARCHAR2(10)),
        RTRIM(source_line.source_text, CHR(13) || CHR(10))
    FROM source_lines source_line
    JOIN routine_ranges routine_range
      ON routine_range.source_type = source_line.source_type
     AND source_line.source_line BETWEEN routine_range.start_line
                                     AND routine_range.end_line
    WHERE source_line.source_line <= routine_range.start_line + 20
       OR REGEXP_LIKE(
              source_line.source_text,
              'P_EMAIL|P_IDUTILISATEUR|ID_CREATEUR|QXP_UTILISATEUR|INSERTRUN',
              'i'
          )
)
SELECT
    evidence.record_type,
    evidence.source_type,
    evidence.source_line,
    evidence.position,
    evidence.argument_name,
    evidence.data_type,
    evidence.in_out,
    evidence.defaulted,
    evidence.detail
FROM evidence
ORDER BY
    evidence.sort_order,
    CASE evidence.source_type WHEN 'PACKAGE' THEN 1 ELSE 2 END,
    NVL(evidence.source_line, evidence.position)
FETCH FIRST 100 ROWS ONLY;


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


/* ---------------------------------------------------------------------------
   QOFF-01H - Runtime QXP_PK_SUIVI.InsertRun contract and resolution
   Export: planning/09_runtime_insertrun_contract.csv

   Use after QOFF-01G reports PLS-00306 for InsertRun. This read-only query
   identifies the connected database/service/current schema, any visible
   QXP_PK_SUIVI synonym and every accessible deployed InsertRun argument.

   Compare the result with the old UI call, which supplies six named inputs:
   p_idSuivi, p_datePlanification, p_gabarit_source, p_idCreateur,
   p_integrerN1 and p_modeCompart. Do not alter the package or UI yet.
   --------------------------------------------------------------------------- */
SELECT
    evidence.record_type,
    evidence.owner_or_schema,
    evidence.object_or_service,
    evidence.overload,
    evidence.position,
    evidence.argument_name,
    evidence.data_type,
    evidence.in_out,
    evidence.defaulted,
    evidence.detail
FROM (
    SELECT
        1 AS sort_order,
        0 AS sort_sequence,
        'SESSION' AS record_type,
        SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS owner_or_schema,
        SYS_CONTEXT('USERENV', 'DB_NAME') || '/' ||
            SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS object_or_service,
        CAST(NULL AS VARCHAR2(40)) AS overload,
        CAST(NULL AS NUMBER) AS position,
        CAST(NULL AS VARCHAR2(128)) AS argument_name,
        CAST(NULL AS VARCHAR2(128)) AS data_type,
        CAST(NULL AS VARCHAR2(20)) AS in_out,
        CAST(NULL AS VARCHAR2(10)) AS defaulted,
        'SESSION_USER=' || SYS_CONTEXT('USERENV', 'SESSION_USER') AS detail
    FROM dual

    UNION ALL

    SELECT
        2,
        0,
        'SYNONYM',
        syn.owner,
        syn.synonym_name,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        syn.table_owner || '.' || syn.table_name ||
            CASE WHEN syn.db_link IS NULL
                 THEN '' ELSE '@' || syn.db_link END
    FROM all_synonyms syn
    WHERE UPPER(syn.synonym_name) = 'QXP_PK_SUIVI'
      AND syn.owner IN (
            SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'),
            SYS_CONTEXT('USERENV', 'SESSION_USER'),
            'PUBLIC'
          )

    UNION ALL

    SELECT
        3,
        arg.sequence,
        'ARGUMENT',
        arg.owner,
        arg.package_name || '.' || arg.object_name,
        arg.overload,
        arg.position,
        arg.argument_name,
        arg.data_type,
        arg.in_out,
        arg.defaulted,
        'SUBPROGRAM_ID=' || TO_CHAR(arg.subprogram_id) ||
            '; DATA_LENGTH=' || NVL(TO_CHAR(arg.data_length), 'NULL')
    FROM all_arguments arg
    WHERE UPPER(arg.package_name) = 'QXP_PK_SUIVI'
      AND UPPER(arg.object_name) = 'INSERTRUN'
      AND arg.data_level = 0
) evidence
ORDER BY evidence.sort_order,
         evidence.owner_or_schema,
         NVL(evidence.overload, '-'),
         evidence.sort_sequence;


/* ---------------------------------------------------------------------------
   QOFF-01I - Deployed QXP_PK_SUIVI.InsertRun source fragment
   Export: planning/10_deployed_insertrun_source_fragment.csv

   Read-only. Returns only the InsertRun routine from the deployed package
   specification and package body, with original Oracle source line numbers.
   It stops at the next top-level routine with matching indentation and also
   applies a hard cap of 220 lines per fragment. It never returns the complete
   package unless the package itself contains only this routine.

   Use this before writing the additive legacy overload. Do not compile or
   change either package object until the returned fragments are reviewed.
   No substitution values are required.
   --------------------------------------------------------------------------- */
WITH source_lines AS (
    SELECT
        package_source.type AS source_type,
        package_source.line AS source_line,
        package_source.text AS source_text,
        LENGTH(package_source.text) - LENGTH(LTRIM(package_source.text))
            AS indentation
    FROM all_source package_source
    WHERE package_source.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
      AND package_source.name = 'QXP_PK_SUIVI'
      AND package_source.type IN ('PACKAGE', 'PACKAGE BODY')
), routine_starts AS (
    SELECT
        source_line.source_type,
        source_line.source_line AS start_line,
        source_line.indentation
    FROM source_lines source_line
    WHERE REGEXP_LIKE(
              source_line.source_text,
              '^[[:space:]]*FUNCTION[[:space:]]+INSERTRUN([[:space:]]|[(]|$)',
              'i'
          )
), routine_ranges AS (
    SELECT
        routine_start.source_type,
        routine_start.start_line,
        NVL(
            (
                SELECT MIN(next_routine.source_line) - 1
                FROM source_lines next_routine
                WHERE next_routine.source_type = routine_start.source_type
                  AND next_routine.source_line > routine_start.start_line
                  AND next_routine.indentation = routine_start.indentation
                  AND REGEXP_LIKE(
                          next_routine.source_text,
                          '^[[:space:]]*(FUNCTION|PROCEDURE)[[:space:]]+',
                          'i'
                      )
            ),
            (
                SELECT MAX(last_source_line.source_line)
                FROM source_lines last_source_line
                WHERE last_source_line.source_type = routine_start.source_type
            )
        ) AS detected_end_line
    FROM routine_starts routine_start
)
SELECT
    source_line.source_type,
    source_line.source_line,
    RTRIM(source_line.source_text, CHR(13) || CHR(10)) AS source_text,
    CASE
        WHEN routine_range.detected_end_line
             > routine_range.start_line + 220
         AND source_line.source_line = routine_range.start_line + 220
        THEN 'STOP: FRAGMENT CAPPED; EXPORT DEPLOYED OBJECT TO A FILE'
        ELSE NULL
    END AS fragment_warning
FROM source_lines source_line
JOIN routine_ranges routine_range
  ON routine_range.source_type = source_line.source_type
 AND source_line.source_line BETWEEN routine_range.start_line
                                 AND LEAST(
                                         routine_range.detected_end_line,
                                         routine_range.start_line + 220
                                     )
ORDER BY
    CASE source_line.source_type WHEN 'PACKAGE' THEN 1 ELSE 2 END,
    source_line.source_line;


/* ---------------------------------------------------------------------------
   QOFF-01J - QXP_PK_SUIVI post-compile status and bounded errors
   Export: planning/11_qxp_pk_suivi_compile_status.csv

   Run immediately after applying ORA-QXP-SUIVI-COMPAT-01. PASS means exactly
   two OBJECT rows (PACKAGE and PACKAGE BODY), both VALID, and no ERROR rows.
   The query is read-only and returns at most the first 20 compiler errors.
   --------------------------------------------------------------------------- */
SELECT
    compile_evidence.record_type,
    compile_evidence.object_type,
    compile_evidence.object_status,
    compile_evidence.source_line,
    compile_evidence.source_position,
    compile_evidence.detail
FROM (
    SELECT
        1 AS sort_order,
        'OBJECT' AS record_type,
        package_object.object_type,
        package_object.status AS object_status,
        CAST(NULL AS NUMBER) AS source_line,
        CAST(NULL AS NUMBER) AS source_position,
        'LAST_DDL=' || TO_CHAR(
            package_object.last_ddl_time,
            'YYYY-MM-DD HH24:MI:SS'
        ) AS detail
    FROM user_objects package_object
    WHERE package_object.object_name = 'QXP_PK_SUIVI'
      AND package_object.object_type IN ('PACKAGE', 'PACKAGE BODY')

    UNION ALL

    SELECT
        2,
        'ERROR',
        compile_error.type,
        'INVALID',
        compile_error.line,
        compile_error.position,
        SUBSTR(
            REPLACE(REPLACE(compile_error.text, CHR(13), ' '), CHR(10), ' '),
            1,
            500
        )
    FROM user_errors compile_error
    WHERE compile_error.name = 'QXP_PK_SUIVI'
      AND compile_error.type IN ('PACKAGE', 'PACKAGE BODY')
) compile_evidence
ORDER BY
    compile_evidence.sort_order,
    compile_evidence.object_type,
    compile_evidence.source_line
FETCH FIRST 22 ROWS ONLY;

