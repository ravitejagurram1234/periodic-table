/* ---------------------------------------------------------------------------
   QOFF-01N - Runtime InsertRunTaches and NumberArray contract
   Export: planning/15_insert_run_taches_contract.csv

   Use after QOFF-01G reports PLS-00306 for InsertRunTaches. This read-only,
   bounded query compares the deployed public arguments with the short package
   specification/body fragments and the QXP_PK_COMMON.NumberArray declaration.
   It does not return table payloads, task SQL, or complete package source.
   No substitution values are required.
   --------------------------------------------------------------------------- */
WITH suivi_source AS (
    SELECT
        package_source.type AS source_type,
        package_source.line AS source_line,
        package_source.text AS source_text
    FROM all_source package_source
    WHERE package_source.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
      AND package_source.name = 'QXP_PK_SUIVI'
      AND package_source.type IN ('PACKAGE', 'PACKAGE BODY')
), routine_starts AS (
    SELECT
        suivi_source.source_type,
        suivi_source.source_line AS start_line
    FROM suivi_source
    WHERE REGEXP_LIKE(
              suivi_source.source_text,
              '^[[:space:]]*PROCEDURE[[:space:]]+INSERTRUNTACHES([[:space:]]|[(]|$)',
              'i'
          )
), routine_ranges AS (
    SELECT
        routine_start.source_type,
        routine_start.start_line,
        NVL(
            (
                SELECT MIN(next_routine.source_line) - 1
                FROM suivi_source next_routine
                WHERE next_routine.source_type = routine_start.source_type
                  AND next_routine.source_line > routine_start.start_line
                  AND REGEXP_LIKE(
                          next_routine.source_text,
                          '^[[:space:]]*(FUNCTION|PROCEDURE)[[:space:]]+',
                          'i'
                      )
            ),
            (
                SELECT MAX(last_line.source_line)
                FROM suivi_source last_line
                WHERE last_line.source_type = routine_start.source_type
            )
        ) AS end_line
    FROM routine_starts routine_start
), evidence AS (
    SELECT
        1 AS sort_order,
        'SESSION' AS record_type,
        SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS object_name,
        CAST(NULL AS VARCHAR2(30)) AS source_type,
        CAST(NULL AS NUMBER) AS source_line,
        CAST(NULL AS VARCHAR2(40)) AS overload,
        CAST(NULL AS NUMBER) AS subprogram_id,
        CAST(NULL AS NUMBER) AS sequence,
        CAST(NULL AS NUMBER) AS position,
        CAST(NULL AS VARCHAR2(128)) AS argument_name,
        CAST(NULL AS VARCHAR2(128)) AS data_type,
        CAST(NULL AS VARCHAR2(20)) AS in_out,
        CAST(NULL AS VARCHAR2(10)) AS defaulted,
        CAST(NULL AS VARCHAR2(128)) AS type_owner,
        CAST(NULL AS VARCHAR2(128)) AS type_name,
        CAST(NULL AS VARCHAR2(128)) AS type_subname,
        'SESSION_USER=' || SYS_CONTEXT('USERENV', 'SESSION_USER') AS detail
    FROM dual

    UNION ALL

    SELECT
        2,
        'OBJECT',
        object_record.object_name,
        object_record.object_type,
        CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(20)),
        CAST(NULL AS VARCHAR2(10)),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)),
        'STATUS=' || object_record.status ||
            '; LAST_DDL=' || TO_CHAR(object_record.last_ddl_time, 'YYYY-MM-DD HH24:MI:SS')
    FROM all_objects object_record
    WHERE object_record.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
      AND object_record.object_name IN ('QXP_PK_SUIVI', 'QXP_PK_COMMON')
      AND object_record.object_type IN ('PACKAGE', 'PACKAGE BODY')

    UNION ALL

    SELECT
        3,
        'ARGUMENT',
        package_argument.package_name || '.' || package_argument.object_name,
        'PACKAGE',
        CAST(NULL AS NUMBER),
        package_argument.overload,
        package_argument.subprogram_id,
        package_argument.sequence,
        package_argument.position,
        package_argument.argument_name,
        package_argument.data_type,
        package_argument.in_out,
        package_argument.defaulted,
        package_argument.type_owner,
        package_argument.type_name,
        package_argument.type_subname,
        'DATA_LEVEL=' || TO_CHAR(package_argument.data_level) ||
            '; DATA_LENGTH=' || NVL(TO_CHAR(package_argument.data_length), 'NULL')
    FROM all_arguments package_argument
    WHERE package_argument.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
      AND package_argument.package_name = 'QXP_PK_SUIVI'
      AND package_argument.object_name = 'INSERTRUNTACHES'

    UNION ALL

    SELECT
        4,
        'SOURCE',
        'QXP_PK_SUIVI.INSERTRUNTACHES',
        suivi_source.source_type,
        suivi_source.source_line,
        CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(20)),
        CAST(NULL AS VARCHAR2(10)),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)),
        RTRIM(suivi_source.source_text, CHR(13) || CHR(10))
    FROM suivi_source
    JOIN routine_ranges routine_range
      ON routine_range.source_type = suivi_source.source_type
     AND suivi_source.source_line BETWEEN routine_range.start_line
                                      AND LEAST(
                                              routine_range.end_line,
                                              routine_range.start_line + 35
                                          )

    UNION ALL

    SELECT
        5,
        'TYPE_SOURCE',
        'QXP_PK_COMMON.NUMBERARRAY',
        package_source.type,
        package_source.line,
        CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(20)),
        CAST(NULL AS VARCHAR2(10)),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)),
        RTRIM(package_source.text, CHR(13) || CHR(10))
    FROM all_source package_source
    WHERE package_source.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
      AND package_source.name = 'QXP_PK_COMMON'
      AND package_source.type = 'PACKAGE'
      AND REGEXP_LIKE(
              package_source.text,
              'TYPE[[:space:]]+NUMBERARRAY[[:space:]]+IS',
              'i'
          )
)
SELECT
    evidence.record_type,
    evidence.object_name,
    evidence.source_type,
    evidence.source_line,
    evidence.overload,
    evidence.subprogram_id,
    evidence.sequence,
    evidence.position,
    evidence.argument_name,
    evidence.data_type,
    evidence.in_out,
    evidence.defaulted,
    evidence.type_owner,
    evidence.type_name,
    evidence.type_subname,
    evidence.detail
FROM evidence
ORDER BY
    evidence.sort_order,
    evidence.object_name,
    evidence.source_type,
    evidence.source_line,
    evidence.subprogram_id,
    evidence.sequence
FETCH FIRST 100 ROWS ONLY;

