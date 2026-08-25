# EOS Quark Engine — office live-run evidence capture guide

Status: operational guide for the REST-only connected test phase. It does not approve production deployment and
does not authorize a code or database change.

Companion SQL: [EOS_Quark_Office_Live_Run_Evidence_Queries.sql](./EOS_Quark_Office_Live_Run_Evidence_Queries.sql)

## 1. What we are proving now

We have completed the disconnected source-parity implementation waves through Wave 10D approval. The next stage is
connected evidence: prove that the Java service can load real Oracle data, execute each reachable engine branch,
call QXPS/QXPSM, persist the same functional result and generate correct documents.

This office campaign proves four things for each selected run:

1. the run received the exact expected database inputs;
2. Java followed the expected task, step, render and error-continuation flow;
3. Oracle contains the expected final status, errors, audit, trace, storage and document links;
4. the generated QXP/PDF/DOC artifacts are available for comparison with an accepted .NET result.

A Java `GENERATED` status by itself is not parity proof. Final replacement approval still needs paired .NET/Java
comparison, controlled error/fault scenarios and the remaining operational controls in
`EOS_Quark_Paired_Run_Acceptance_Matrix.md`.

## 2. Non-negotiable safety rules

- Keep Rabbit consumption disabled throughout this campaign:
  `engine.input.rabbit.enabled=false`. Do not temporarily override it.
- Use the REST endpoint only. Process one run at a time.
- Create every Java test run through the normal backend/batch business flow. Never insert a run or manually alter
  its status, dates, links or task associations.
- A historical successful run is only a scenario/baseline selector. Never submit a historical run ID to
  `processRun`.
- Submit a fresh run ID to `processRun` exactly once. If the HTTP client times out, do not submit it again; inspect
  application logs and `QOFF-03`/`QOFF-16` first.
- Do not start .NET and Java sequentially on the same run. Use an accepted historical .NET capture plus an
  equivalent fresh Java run, or isolated equivalent database states.
- Do not run tests in parallel. Do not restart the engine while a run is still active.
- Do not enable SQL/JPA value logging, raw Axis SOAP logging, HTTP wire dumps or full QXPS URI logging. Never place
  SQL, XML, modifiers, document text, BLOBs, tokens or passwords in ordinary logs.
- Parameters, `LOG_TRACE`, errors and storage rows can contain business data. Keep them in the approved evidence
  location; do not email or paste them into an unrestricted channel.
- Do not purge or acknowledge Rabbit messages as part of this work. Record the queue depth and obtain a separate
  approved cleanup decision before Rabbit is enabled later.

Why the queue warning matters: the batch may reserve a run and publish its ID while this engine listener is disabled.
Those messages can remain ready in the queue. Enabling Rabbit later without first classifying stale messages could
reprocess runs and recreate the repeated-run behavior already observed.

## 3. Evidence folder to create

Use one folder per office session and one subfolder per run. Do not place secrets in the manifest.

```text
engine-live-evidence/
  session_YYYYMMDD/
    00_build.txt
    01_runtime_and_commit.txt
    02_effective_config_redacted.txt
    03_reference_codes.csv
    04_sql_client_nls.csv
    05_startup_console.log
    06_engine_ecs.json
    07_rabbit_queue_before.png
    08_rabbit_queue_after.png
    planning/
      01_historical_candidate_profiles.csv
    run_<RUN_ID>_<SCENARIO>/
      00_manifest.md
      00_new_run_candidates.csv
      01_pre_run_overview.csv
      02_parameters.csv
      03_tasks.csv
      04_task_exceptions.csv
      05_template_metadata.csv
      05b_effective_gabarit_source.csv
      06_selected_task_documents.csv
      07_pre_compartment_children.csv
      08_fetch_run_properties_http.txt
      08_process_run_http.txt
      08_run_console.log
      09_persisted_trace_chunks.csv
      10_post_run_overview.csv
      11_errors.csv
      12_audit.csv
      13_documents.csv
      14_storage_summary.csv
      14_storage_rows.csv
      15_post_compartment_children.csv
      16_completion_check.csv
      artifacts/
        generated.pdf
        generated.qxp
        generated.doc
        SHA256.txt
      comparison_notes.md
```

Files whose query returns zero rows must still be saved with their headers. Zero rows are evidence, especially for
task exceptions, selected documents, compartments, errors and storage.

## 4. One-time office-session preparation

### 4.1 Apply and build the exact candidate

1. Apply the approved Wave 10D packet after the already approved Wave 10A–10C content.
2. Run `mvn clean install` using the same Maven settings and JDK 21 used by the project.
3. Save the complete build output as `00_build.txt`.
4. Record the Git commit/branch, Java version, Maven version and artifact version in
   `01_runtime_and_commit.txt`. If there are uncommitted files, record their names without copying secrets.
5. Do not continue if any test fails. Warnings may be recorded for later triage, but a test failure invalidates the
   candidate.

### 4.2 Record configuration without secrets

In `02_effective_config_redacted.txt`, record only the following effective values:

- active Spring profile;
- Oracle host/service name (no username/password);
- QXPS host and configured timeouts/buffer limit (no query values);
- QXPSM host and configured timeouts;
- `engine.input.rabbit.enabled=false`;
- Rabbit virtual host and queue name, but no credentials;
- REST port/TLS mode;
- trace maximum/event maximum;
- gabarit size limit (`209715200`, 200 MiB for the current approved Java behavior);
- `engine.step-limit`, `engine.nb-box-max` and `engine.average-box-size`;
- formatting date, datetime, decimal and grouping settings.

Do not copy the entire environment, JVM command line or YAML if it contains credentials.

### 4.3 Start with durable log capture

The current `logback-spring.xml` writes readable console logs and an ECS JSON file. Set `LOG_FILE` in the IntelliJ
run configuration to an approved evidence path such as:

```text
C:\engine-live-evidence\session_YYYYMMDD\06_engine_ecs.json
```

Also enable IntelliJ's **Save console output to file** option if available and select
`05_startup_console.log`. Keep logging at `INFO`. Do not uncomment the raw Axis SOAP debug block.

Start the application once and preserve the entire startup section. Confirm:

- Spring starts successfully with the expected profile and Java 21;
- Oracle connectivity succeeds;
- QXPS and QXPSM configuration resolves without printing secrets;
- no `RabbitListener` container starts and no `Received Rabbit run` line appears;
- the application is using Oracle, not the local H2 fallback;
- no French or garbled application-log message appears. Record any such line as a finding rather than editing it
  during the session.

Run `QOFF-00` and `QOFF-10` once and export the reference codes and SQL-client NLS results. `QOFF-10` describes the
SQL Developer session; the Java connection-pool NLS values are proved by successful typed date/number task runs and
the configured Hikari initialization statement.

### 4.4 Record the Rabbit backlog without consuming it

Take a Rabbit management screenshot before creating the first run and after finishing the session. The screenshot
must show the virtual host, queue name, ready count, unacknowledged count and timestamp. Do not include credentials.
The expected queue is `quark-batch-run-dev` in virtual host `vap-quark-host`.

If the Java log ever contains `Received Rabbit run` during this REST-only phase, stop the campaign immediately and
save the logs. The listener is not disabled as intended.

## 5. Choose business scenarios before creating runs

Run `QOFF-01` and export the latest 200 successful historical profiles. Use it to identify business combinations
that already exercised SQL, document, QXP-block, dynamic and compartment tasks. These IDs are accepted .NET/history
evidence candidates—not Java execution IDs.

Prefer the smallest set of new runs that covers the largest number of branches. Do not select only Annual Report
runs; the campaign must cover all reachable report and document families.

### Minimum connected run campaign

| Live case | Required fresh-run characteristic | How to confirm before POST |
|---|---|---|
| L01 — broad normal run | Multiple task types and normal DID processing | `QOFF-05`; compare with historical run `517912` if the same business configuration can be recreated |
| L02 — SQL formatting | SQL task with date/port binds, decimal formatting, zero/null marker and exceptions | `QOFF-04` to `QOFF-06`; task 53/run 509199 is a known historical shape |
| L03 — three-parameter SQL/storage | Port/date/gabarit or port/date/unit and `STORE_DATA=1` | `QOFF-04`, `QOFF-05`; known historical shapes include tasks 133 and 206 |
| L04 — DOC EOS QXP value | Type-2 task, selected format QXP, `CONSERVER_STYLE=0` | `QOFF-05`, `QOFF-08` |
| L05 — DOC EOS QXP style | Type-2 task, selected format QXP, `CONSERVER_STYLE=1` | `QOFF-05`, `QOFF-08` |
| L06 — DOC EOS PDF/image | Type-2 PDF and image inputs; include rotated/cropped or multipage input if reachable | `QOFF-05`, `QOFF-08` |
| L07 — Bloc QXP/previous | Type-3 task, preferably explicit and hierarchy/level variants | `QOFF-05` |
| L08 — dynamic normal | Type-4 task with returned data | `QOFF-05`; console/trace must show fetched rows and created processing steps |
| L09 — dynamic complex | Type-4 task with page/column break rules, double pagination or overflow control | `QOFF-03`, `QOFF-05`; require `PAGINATION_DOUBLE=1` and/or `CONTROL_OVERFLOW=1` where available |
| L10 — compartment generate | Type-5 task with `MODE_COMPART=1` | `QOFF-03`, `QOFF-05`, `QOFF-09` |
| L11 — compartment incorporate | Type-5 task with `MODE_COMPART=2` | `QOFF-03`, `QOFF-05`, `QOFF-09` |
| L12 — compartment both | Type-5 task with `MODE_COMPART=3` | `QOFF-03`, `QOFF-05`, `QOFF-09` |
| L13 — document storage | Gabarit `STORE_DATA_TYPE` contains bit 2 | `QOFF-03`, then verify `QOFF-14A/B` after execution |
| L14 — accepted nonblocking errors | A normal business run known to record Critique/Unspecified task errors but continue | Historical trace/errors plus fresh equivalent; verify later tasks still execute |

Across these live cases, cover when reachable:

- report types 1 Annual, 2 Plaquette, 3 Prospectus, 4 compartment report and 5 DICI;
- a fund-level run and a unit/part-level run;
- French and at least one other language;
- gabarit sources 1 through 4;
- output QXP and PDF, plus DOC where `GENERATE_TO_WORD` is configured;
- SQL, DOC EOS, Bloc QXP, dynamic and compartment task types;
- normal pagination and double/facing-page pagination;
- SQL storage and document storage.

Task type 9/QPP previously had no current rows. Do not invent a production test run for it. If it remains absent,
its behavior stays in focused test/static evidence unless real configuration is later supplied.

Not all rows above require a different run: one run may satisfy several cases. Record every satisfied case in its
manifest. Conversely, do not claim a branch merely because its task type exists; the pre-run query must prove the
branch-specific flag/format.

## 6. Create and identify one fresh run

1. In the normal backend/UI, choose the historical scenario's equivalent fund/unit, report type, due date, language
   and gabarit. Create/generate the run using the usual business workflow.
2. Allow the normal batch handoff to reserve/publish it as it did for the .NET engine. The Java Rabbit listener
   remains disabled, so the engine does not consume it.
3. Edit `CREATED_AFTER` and `FUND_CODE` in the companion SQL file and run `QOFF-02`.
4. Match the row against the UI values. Do not select an ID based only on “latest”.
5. Set `RUN_ID` in the SQL file to the confirmed fresh ID.

Run `QOFF-03` immediately. Confirm and record:

- the fund, unit, report type, language, due date and gabarit match the requested generation;
- `ID_SUIVI` is correct and `ID_RUN_SUIVANT` points to this fresh run where the normal flow requires it;
- start/end dates and generated document IDs are still absent before execution;
- the status is the exact state supplied by the normal batch handoff.

Do not manually convert status 1 to status 5 or otherwise “repair” the run. If the observed status/link differs from
the accepted batch-to-.NET handoff, save `QOFF-02`/`QOFF-03` and stop that case. It is admission-flow evidence that
must be resolved, not hidden.

Create `00_manifest.md` with:

```markdown
# Run evidence manifest

- Live case IDs:
- Fresh Java run ID:
- Suivi ID:
- Historical .NET/baseline run ID:
- Fund/unit:
- Report type:
- Due date:
- Language:
- Gabarit ID/source:
- Expected task branches:
- Created at:
- GET sent at:
- POST sent at:
- HTTP completed at:
- Operator:
- Build/commit reference:
- Notes (no secrets):
```

## 7. Mandatory pre-run exports

Before calling the endpoint, execute and export these blocks:

| Query | Evidence | Mandatory check |
|---|---|---|
| `QOFF-03` | run/suivi/gabarit overview | exact business identity, admission status and links |
| `QOFF-04` | all parameters | names, types, values and count match the run; keep 3- and 4-parameter shapes when present |
| `QOFF-05` | task inventory/config | every expected task exists; SQL text is not exported |
| `QOFF-06` | SQL exception rules | duplicates and whole-table/indexed rules are preserved |
| `QOFF-07` | gabarit/template metadata | configured size, pagination, storage and dynamic-template flags |
| `QOFF-07B` | effective starting gabarit | exact template/upload/previous/certified source ID and byte size selected by source modes 1–4 |
| `QOFF-08` | selected DOC EOS documents | expected format; `MATCHED_DOCUMENT_COUNT` should normally be 1 per type-2 task |
| `QOFF-09` | compartment children | exact child order/run/status for type-5 runs; otherwise zero rows |

Stop before POST and report the evidence if:

- any expected input parameter is missing or has an unexpected type/shape;
- the run has no expected tasks;
- a type-2 task has `MATCHED_DOCUMENT_COUNT=0` or greater than 1, unless that edge is the deliberately selected test;
- a compartment case has the wrong mode, child order, missing child, or wrong selected previous/next child;
- a generated document ID or generation end date is already present on what should be a fresh run;
- the run identity or handoff status/link is not the expected normal-flow result.

## 8. REST execution and live log capture

The current route is intentionally left as already implemented for this phase:

```text
GET  /api/v1/EngineService/fetchRunProperties/{runId}
POST /api/v1/EngineService/processRun/{runId}
```

Use Swagger, Postman or the approved authenticated internal client. Never save an access token in the evidence
folder.

### 8.1 Fetch properties first

Call `fetchRunProperties` once. Export the full HTTP status, response headers and JSON body to
`08_fetch_run_properties_http.txt`. Compare its non-binary fields to `QOFF-03` and `QOFF-04`.

Expected success is HTTP 200. A 500, missing property or mapping difference is a failed case; do not continue to
`processRun` until it is understood.

### 8.2 Process exactly once

Record the send timestamp in the manifest, then POST `processRun/{runId}` once. Save the HTTP status, headers and
body as `08_process_run_http.txt`.

- HTTP 200 with terminal `GENERATED` means the service reports successful completion.
- HTTP 500 with a body containing terminal `ERROR` means processing completed and persisted a run error; capture
  all evidence and classify the cause.
- HTTP 500 with an empty body means the adapter did not receive a usable terminal result; capture all logs and DB
  state.
- An HTTP timeout is unknown, not permission to retry. Check logs and `QOFF-03`/`QOFF-16`.

Copy the complete console interval from the controller line `Processing run with runId: <ID>` through
`Run completed for runId: <ID> with status: ...` into `08_run_console.log`. If the final line is absent, copy from
the first line through the last available line plus the subsequent five minutes of application output.

### 8.3 What a useful Java log should show

Depending on the selected branches, the console plus persisted trace should make these events reconstructable:

- controller acceptance and run ID;
- `Start_Run`, run-property loading and suivi context;
- gabarit source/size and normal or degraded mode;
- parameter/task/task-exception counts;
- each task ID/type with prepare, process and post-process outcome;
- SQL/dynamic fetched row counts without SQL text or values;
- document ID/format/page count without BLOB content;
- task-scoped errors and proof that later tasks continued;
- step order and add/update/excluded counts;
- double/facing-page prepare substeps when applicable;
- overflow detection and reprocessing when applicable;
- child-run selection/generation/incorporation and child IDs for compartment cases;
- render requests and QXP/PDF/JPEG byte counts;
- inserted document IDs and byte counts;
- End attempt, final status, error count, audit/storage outcome;
- MDC fields `runId`, `suiviId`, `taskId`, `stepIndex`, `childRunId` where applicable.

The persisted trace is essential because it contains per-task phase and per-step evidence that is intentionally not
duplicated at INFO level. It is bounded to 3 MiB. `QOFF-15` exports it completely in order; `QOFF-16` detects the
`TRACE_TRUNCATED` marker.

## 9. Mandatory post-run collection

Wait for the HTTP response or terminal log line, then run/export:

1. `QOFF-03` as `10_post_run_overview.csv`;
2. `QOFF-11` as `11_errors.csv`;
3. `QOFF-12` as `12_audit.csv`;
4. `QOFF-13` as `13_documents.csv`;
5. `QOFF-14A` and `QOFF-14B` as storage summary/rows;
6. `QOFF-15` as the complete chunked persisted trace;
7. `QOFF-09` again as `15_post_compartment_children.csv`;
8. `QOFF-16` as `16_completion_check.csv`.

Mandatory validation:

- final DB status agrees with the REST body and final Java log;
- start/end timestamps exist and are ordered;
- the audit row and end status exist as expected;
- every error row is retained, including duplicates; task-level errors did not stop unrelated later tasks where
  .NET continues;
- expected document roles are linked, have non-null BLOB length and match logged byte counts;
- storage rows exist only when the relevant task/gabarit storage flag requires them;
- compartment child statuses/documents agree with the trace;
- `TRACE_TRUNCATED=0`; if it is 1, preserve the run but mark its trace evidence incomplete;
- no SQL, raw XML/modifier, DID text, BLOB, token, password or full query-bearing URL appears in ordinary Java logs;
- all application-generated log text is English and readable.

Do not treat a run with an expected nonblocking error as failed solely because `QXP_RUN_ERROR` is non-empty. Compare
the error type/message/multiplicity and confirm the accepted continuation path and final status.

## 10. Generated document evidence

Download every generated QXP, PDF and DOC through the normal approved application mechanism. Do not export BLOBs
with an ad hoc query. Preserve the exact files without opening/resaving them.

On Windows PowerShell, calculate hashes:

```powershell
Get-ChildItem .\artifacts -File |
    Where-Object Name -ne 'SHA256.txt' |
    Get-FileHash -Algorithm SHA256 |
    Format-Table Algorithm, Hash, Path -AutoSize |
    Out-File .\artifacts\SHA256.txt
```

Record in `comparison_notes.md`:

- PDF page count, page dimensions, rotation and any visible clipping/overflow;
- whether every expected table/page/section appears in business order;
- QXP opens successfully and preserves expected layouts/pages/boxes;
- DOC opens successfully when generated;
- any font substitution, missing image, shifted block, blank page, repeated page or corrupted character;
- corresponding accepted .NET artifact/run ID.

Hashes establish artifact identity within the evidence bundle. A different Java/.NET PDF hash is not automatically a
failure because producer metadata can differ; page structure and controlled visual comparison are still required.

## 11. Accepted .NET baseline capture

Where an accepted historical .NET run represents the same business configuration, create a separate
`baseline_dotnet_<RUN_ID>` folder and run the same read-only QOFF exports with that historical ID. Download its
existing generated artifacts and record hashes. Do not call any processing endpoint for the historical ID.

Input equivalence must cover more than fund/date/report type. Compare:

- suivi/gabarit/language/unit/source/mode;
- parameter names, types and values;
- task IDs and non-payload configuration;
- task exceptions;
- gabarit/template/document metadata and binary sizes/hashes where approved;
- compartment child selection;
- relevant reference data version or database refresh/snapshot date.

If these inputs are not equivalent, the historical result is useful diagnostic evidence but not a strict paired
parity case.

## 12. Failure and timeout decision table

| Observation | Action |
|---|---|
| No controller log and no DB start date | Verify URL/authentication; do not resend until the HTTP attempt is conclusively closed |
| Controller log exists, start date exists, no final line yet | Treat as active; wait and monitor without a second POST |
| Client timed out but logs continue | Let the first execution finish; collect the eventual terminal state |
| Java process exited | Preserve all console/ECS output and DB state; do not restart against the same run |
| Run ends `ERROR` | Collect the complete bundle; classify whether Java, DB, QXPS, QXPSM, data or configuration caused it |
| Task error followed by later task activity | Preserve it; this may be correct .NET fail-soft behavior |
| `End_Run` first attempt fails | Capture both attempts and final persisted state; never repair it manually |
| `TRACE_TRUNCATED=1` | Mark trace evidence incomplete and retain all ECS/console logs |
| Any Rabbit receive line appears | Stop the REST campaign; the listener was unexpectedly enabled |
| Queue depth grows | Expected if batch publishes while engine consumption is disabled; record it and do not enable/purge without approval |

## 13. Are the current logs sufficient?

They are sufficient to begin the first connected campaign only when all four sources are captured together:

1. console/ECS application logs;
2. persisted `QXP_RUN.LOG_TRACE`;
3. pre/post Oracle exports;
4. generated binaries and comparison notes.

The current implementation already provides run/task/step IDs, task row counts, safe task errors, step counts,
overflow activity, child-run context, render byte counts, document insertion and End/final status. It also avoids
printing whole task SQL.

Two observability gaps should be assessed after the first connected run and will likely need a separately approved
production change before final sign-off:

1. **QXPS successful-call completion:** one safe line per call with operation/method, path category, HTTP status,
   duration and response byte count. It must not include query values, full URI, response body, XML or document
   content.
2. **QXPSM successful-call completion:** operation (`process` or `getXPressDOM`), duration and safe result size/count
   such as output bytes or layout count. It must not include the SOAP body, modifier XML, paths containing sensitive
   values or document text.

After the first run, also check whether INFO plus persisted trace clearly exposes one safe run-load summary containing
gabarit source/size, parameter count/names-and-types, task-type counts and selected document counts. If that evidence
is already unambiguous across the captured files, no duplicate INFO log is needed. If it is not, propose a small
observability packet for approval. Do not edit logging during the live session.

## 14. What to bring back for analysis

For each run, bring the complete folder listed in section 3. At minimum, a run cannot be analyzed conclusively
without:

- manifest and exact fresh run ID;
- pre-run overview, parameters, tasks and relevant document/compartment selection;
- GET and POST HTTP captures;
- complete run console interval;
- complete persisted trace chunks;
- post-run overview, errors, audit, document metadata and storage exports;
- generated artifacts and SHA-256 file;
- accepted .NET baseline ID/artifacts/logs where available;
- a short note describing what was expected and what was visually observed.

If time at the office is limited, prioritize in this order:

1. one broad normal run (L01);
2. one SQL formatting/storage run (L02/L03);
3. one DOC EOS run (L04–L06);
4. one dynamic complex/overflow run (L08/L09);
5. one compartment run (prefer mode 3, then cover modes 1 and 2 separately);
6. remaining report types, languages, source modes and document formats.

Do not rush several incomplete runs. One complete evidence bundle is more valuable than many run IDs without pre-run
inputs, persisted trace or generated artifacts.
