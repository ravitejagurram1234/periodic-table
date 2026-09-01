/* ---------------------------------------------------------------------------
   QOFF-01M - Engine-related SGIAM Oracle dependency scan
   Export: planning/14_engine_sgiam_dependency_scan.csv

   Read-only audit for the Java engine, Rabbit/batch handoff, and the temporary
   old-.NET run-creation bridge. It checks only routines reachable by those
   flows, identity columns/foreign keys on tables written by them, and active
   task SQL executed by the engine. It does not scan unrelated UI,
   administration or authentication packages.

   SOURCE rows contain only matching source lines, never complete routines.
   TASK_SQL rows expose IDs and lengths, never full task SQL. At most 25 task
   rows and 200 total rows are returned. No substitution values are required.
   --------------------------------------------------------------------------- */
WITH engine_routines AS (
    SELECT 'QXP_PK_RUN' package_name, 'GET_RUN_PROPERTIES' routine_name FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'GET_GABARIT' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'GET_GABARIT_DOCUMENT' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'GET_GABARIT_DOCUMENT_CERTIFIE' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'GET_DOCUMENT' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'GET_DOCUMENT_BYID' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'GET_LAST_QXP_CERTIFIE' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'GET_TACHES' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'GET_RUN_TACHES_EXCEPTIONS' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'GET_IN_PARAMS' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'INSERT_DOCUMENT' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'START_RUN' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'UPDATE_STATUS_RUN' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'END_RUN' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'INSERT_RUN_ERRORS' FROM dual UNION ALL
    SELECT 'QXP_PK_RUN', 'GET_COMPARTIMENT_RUNS' FROM dual UNION ALL
    SELECT 'QXP_PK_AUDIT', 'INSERTAUDITRUN' FROM dual UNION ALL
    SELECT 'QXP_PK_DATA_STORAGE', 'INSERT_DATA' FROM dual UNION ALL
    SELECT 'QXP_PK_TEMPLATE', 'GET_GABARIT_TEMPLATE' FROM dual UNION ALL
    SELECT 'QXP_PK_TEMPLATE', 'GET_TEMPLATES' FROM dual UNION ALL
    SELECT 'QXP_PK_SUIVI', 'INSERTRUN' FROM dual UNION ALL
    SELECT 'QXP_PK_SUIVI', 'INSERTRUNTACHES' FROM dual UNION ALL
    SELECT 'QXP_PK_SUIVI', 'INSERTSUIVITRADUCTION' FROM dual UNION ALL
    SELECT 'QXP_PK_BATCH', 'GET_RUNS' FROM dual UNION ALL
    SELECT 'QXP_PK_BATCH', 'GET_RUNS_INITIALS' FROM dual UNION ALL
    SELECT 'QXP_PK_BATCH', 'RESET_RUNS_STATUS' FROM dual UNION ALL
    SELECT 'QXP_PK_BATCH', 'UPDATE_RUNS_STATUS' FROM dual UNION ALL
    SELECT 'QXP_PK_BATCH', 'CREATE_RUN_UPLOAD' FROM dual
), source_lines AS (
    SELECT
        package_source.name AS package_name,
        package_source.line AS source_line,
        package_source.text AS source_text,
        LENGTH(package_source.text) - LENGTH(LTRIM(package_source.text))
            AS indentation
    FROM all_source package_source
    WHERE package_source.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
      AND package_source.type = 'PACKAGE BODY'
      AND package_source.name IN (
            'QXP_PK_RUN',
            'QXP_PK_AUDIT',
            'QXP_PK_DATA_STORAGE',
            'QXP_PK_TEMPLATE',
            'QXP_PK_SUIVI',
            'QXP_PK_BATCH'
          )
), routine_starts AS (
    SELECT
        source_line.package_name,
        engine_routine.routine_name,
        source_line.source_line AS start_line,
        source_line.indentation
    FROM source_lines source_line
    JOIN engine_routines engine_routine
      ON engine_routine.package_name = source_line.package_name
     AND REGEXP_LIKE(
             source_line.source_text,
             '^[[:space:]]*(FUNCTION|PROCEDURE)[[:space:]]+' ||
                 engine_routine.routine_name || '([[:space:]]|[(]|$)',
             'i'
         )
), routine_ranges AS (
    SELECT
        routine_start.package_name,
        routine_start.routine_name,
        routine_start.start_line,
        NVL(
            (
                SELECT MIN(next_routine.source_line) - 1
                FROM source_lines next_routine
                WHERE next_routine.package_name = routine_start.package_name
                  AND next_routine.source_line > routine_start.start_line
                  AND next_routine.indentation = routine_start.indentation
                  AND REGEXP_LIKE(
                          next_routine.source_text,
                          '^[[:space:]]*(FUNCTION|PROCEDURE)[[:space:]]+',
                          'i'
                      )
            ),
            (
                SELECT MAX(last_line.source_line)
                FROM source_lines last_line
                WHERE last_line.package_name = routine_start.package_name
            )
        ) AS end_line
    FROM routine_starts routine_start
), source_matches AS (
    SELECT
        source_line.package_name,
        routine_range.routine_name,
        source_line.source_line,
        RTRIM(SUBSTR(source_line.source_text, 1, 500), CHR(13) || CHR(10))
            AS detail
    FROM source_lines source_line
    JOIN routine_ranges routine_range
      ON routine_range.package_name = source_line.package_name
     AND source_line.source_line BETWEEN routine_range.start_line
                                     AND routine_range.end_line
    WHERE REGEXP_LIKE(
              source_line.source_text,
              'QXP_UTILISATEUR|ID_UTILISATEUR|IDUTILISATEUR|' ||
                  'ID_CREATEUR|IDCREATEUR|P_EMAIL',
              'i'
          )
), identity_columns AS (
    SELECT
        table_column.table_name,
        table_column.column_name,
        table_column.data_type,
        table_column.data_length,
        table_column.nullable
    FROM all_tab_columns table_column
    WHERE table_column.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
      AND table_column.table_name IN (
            'QXP_RUN',
            'QXP_SUIVI',
            'QXP_DOCUMENT',
            'QXP_DOCUMENT_UPLOAD',
            'QXP_AUDIT_RUN',
            'QXP_DATA_STORAGE'
          )
      AND REGEXP_LIKE(
              table_column.column_name,
              'UTILISATEUR|CREATEUR|EMAIL|SGIAM',
              'i'
          )
), identity_foreign_keys AS (
    SELECT
        child_constraint.table_name,
        child_constraint.constraint_name,
        child_column.column_name AS child_column_name,
        parent_constraint.table_name AS parent_table_name,
        parent_column.column_name AS parent_column_name,
        child_constraint.status,
        child_constraint.delete_rule
    FROM all_constraints child_constraint
    JOIN all_cons_columns child_column
      ON child_column.owner = child_constraint.owner
     AND child_column.constraint_name = child_constraint.constraint_name
    JOIN all_constraints parent_constraint
      ON parent_constraint.owner = child_constraint.r_owner
     AND parent_constraint.constraint_name = child_constraint.r_constraint_name
    JOIN all_cons_columns parent_column
      ON parent_column.owner = parent_constraint.owner
     AND parent_column.constraint_name = parent_constraint.constraint_name
     AND parent_column.position = child_column.position
    WHERE child_constraint.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
      AND child_constraint.constraint_type = 'R'
      AND child_constraint.table_name IN (
            'QXP_RUN',
            'QXP_SUIVI',
            'QXP_DOCUMENT',
            'QXP_DOCUMENT_UPLOAD',
            'QXP_AUDIT_RUN',
            'QXP_DATA_STORAGE'
          )
      AND (
            REGEXP_LIKE(
                child_column.column_name,
                'UTILISATEUR|CREATEUR|EMAIL|SGIAM',
                'i'
            )
            OR parent_constraint.table_name = 'QXP_UTILISATEUR'
          )
), task_sql_matches AS (
    SELECT
        task.id_tache,
        task.id_type_tache,
        DBMS_LOB.GETLENGTH(task.sql) AS sql_chars,
        COUNT(*) OVER () AS total_matches,
        ROW_NUMBER() OVER (ORDER BY task.id_tache) AS match_number
    FROM qxp_tache task
    WHERE task.is_actif = 1
      AND task.sql IS NOT NULL
      AND REGEXP_LIKE(
              task.sql,
              'QXP_UTILISATEUR|ID_UTILISATEUR|ID_CREATEUR',
              'i'
          )
), evidence AS (
    SELECT
        1 AS sort_order,
        'OBJECT' AS record_type,
        'QXP_UTILISATEUR' AS object_name,
        CAST(NULL AS VARCHAR2(128)) AS member_name,
        CAST(NULL AS NUMBER) AS source_line,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM all_objects object_record
                WHERE object_record.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
                  AND object_record.object_name = 'QXP_UTILISATEUR'
                  AND object_record.object_type IN ('TABLE', 'VIEW')
            )
            THEN 'PRESENT IN CURRENT SCHEMA'
            WHEN EXISTS (
                SELECT 1
                FROM all_synonyms synonym_record
                WHERE synonym_record.synonym_name = 'QXP_UTILISATEUR'
                  AND synonym_record.owner IN (
                        SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'),
                        'PUBLIC'
                      )
            )
            THEN 'ACCESSIBLE THROUGH CURRENT/PUBLIC SYNONYM'
            ELSE 'ABSENT FROM CURRENT SCHEMA'
        END AS detail
    FROM dual

    UNION ALL

    SELECT
        2,
        'SOURCE',
        source_match.package_name,
        source_match.routine_name,
        source_match.source_line,
        source_match.detail
    FROM source_matches source_match

    UNION ALL

    SELECT
        3,
        'COLUMN',
        identity_column.table_name,
        identity_column.column_name,
        CAST(NULL AS NUMBER),
        'TYPE=' || identity_column.data_type ||
            '; LENGTH=' || TO_CHAR(identity_column.data_length) ||
            '; NULLABLE=' || identity_column.nullable
    FROM identity_columns identity_column

    UNION ALL

    SELECT
        4,
        'FOREIGN_KEY',
        identity_foreign_key.table_name,
        identity_foreign_key.constraint_name,
        CAST(NULL AS NUMBER),
        identity_foreign_key.child_column_name || ' -> ' ||
            identity_foreign_key.parent_table_name || '.' ||
            identity_foreign_key.parent_column_name ||
            '; STATUS=' || identity_foreign_key.status ||
            '; DELETE_RULE=' || identity_foreign_key.delete_rule
    FROM identity_foreign_keys identity_foreign_key

    UNION ALL

    SELECT
        5,
        'TASK_SQL',
        'QXP_TACHE',
        'ID_TACHE=' || TO_CHAR(task_sql_match.id_tache),
        CAST(NULL AS NUMBER),
        'ID_TYPE_TACHE=' || TO_CHAR(task_sql_match.id_type_tache) ||
            '; SQL_CHARS=' || TO_CHAR(task_sql_match.sql_chars) ||
            '; TOTAL_MATCHES=' || TO_CHAR(task_sql_match.total_matches)
    FROM task_sql_matches task_sql_match
    WHERE task_sql_match.match_number <= 25
)
SELECT
    evidence.record_type,
    evidence.object_name,
    evidence.member_name,
    evidence.source_line,
    evidence.detail
FROM evidence
ORDER BY
    evidence.sort_order,
    evidence.object_name,
    evidence.member_name,
    evidence.source_line
FETCH FIRST 200 ROWS ONLY;
