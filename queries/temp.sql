
/* ---------------------------------------------------------------------------
   QOFF-01K - Deployed QXP_PK_SUIVI.InsertRun internal call sites
   Export: planning/12_deployed_insertrun_call_sites.csv

   Run before ORA-INSERTRUN-COMPAT-01. Returns only package-body source lines
   that invoke InsertRun, excluding the function declaration. This verifies
   whether InsertSuiviTraduction still uses the legacy seven-position call.
   Read-only, bounded, and requires no substitution values.
   --------------------------------------------------------------------------- */
SELECT
    package_source.line AS source_line,
    RTRIM(package_source.text, CHR(13) || CHR(10)) AS source_text
FROM all_source package_source
WHERE package_source.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
  AND package_source.name = 'QXP_PK_SUIVI'
  AND package_source.type = 'PACKAGE BODY'
  AND REGEXP_LIKE(
          package_source.text,
          'INSERTRUN[[:space:]]*[(]',
          'i'
      )
  AND NOT REGEXP_LIKE(
              package_source.text,
              '^[[:space:]]*FUNCTION[[:space:]]+INSERTRUN',
              'i'
          )
ORDER BY package_source.line
FETCH FIRST 50 ROWS ONLY;

