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

