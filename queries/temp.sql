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

