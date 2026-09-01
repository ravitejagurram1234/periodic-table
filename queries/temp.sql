/* ---------------------------------------------------------------------------
   QOFF-01L - InsertSuiviTraduction contract and relevant source lines
   Export: planning/13_insert_suivi_traduction_contract.csv

   Run before ORA-INSERTRUN-COMPAT-01. Returns the deployed function arguments
   plus only its declaration and lines involving email, user identity,
   creator identity or InsertRun. It does not return the complete function or
   package. Read-only, bounded, and requires no substitution values.
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

