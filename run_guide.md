# EOS Quark Engine — office live-run evidence capture guide

Status: operational guide for the REST-only connected parity campaign after the output-parity changes are built.
It does not approve production deployment and does not authorize a code or database change.

Companion SQL: [EOS_Quark_Office_Live_Run_Evidence_Queries.sql](./EOS_Quark_Office_Live_Run_Evidence_Queries.sql)

Remaining changes: [EOS_Quark_Remaining_Parity_Change_Suggestions.md](./EOS_Quark_Remaining_Parity_Change_Suggestions.md)

## 1. What we are proving now

We have completed the disconnected source-parity implementation waves through Wave 10D approval. The next stage is
connected evidence: prove that the Java service can load real Oracle data, execute each reachable engine branch,
call QXPS/QXPSM, persist the same functional result and generate correct documents.

This office campaign proves four things for each selected run:

1. the run received the exact expected database inputs;
2. Java followed the expected task, step, render and error-continuation flow;
3. Oracle contains the expected final status, errors, audit, trace, storage and document links;
4. the generated QXP/PDF/DOC artifacts are available for comparison with an accepted .NET result.

The functional campaign has three mandatory run archetypes:

1. **Simple:** selected active SQL/document/QXP-block tasks, with no selected dynamic or compartment task.
2. **Dynamic:** at least one selected active dynamic task that returns data and creates document changes.
3. **Compartment:** at least one selected active compartment task with valid child runs and the intended mode.

For every executed run, `QOFF-02B` must prove before execution that the fresh run is valid and has selected work.
After execution, `QOFF-17` must prove that at least one QXPS step had a non-zero add, update or exclude count. A run
that has tasks configured but produces no document change is useful diagnostic evidence, but it does not satisfy
this campaign's successful parity case.

A Java `GENERATED` status by itself is not parity proof. Final replacement approval still needs paired .NET/Java
comparison, controlled error/fault scenarios and the remaining operational controls in
`EOS_Quark_Paired_Run_Acceptance_Matrix.md`.

## 2. Non-negotiable safety rules

- Keep Rabbit consumption disabled throughout this campaign:
  `engine.input.rabbit.enabled=false`. Do not temporarily override it.
- Use the REST endpoint only. Process one run at a time.
- Do not start the three-run concurrency campaign until the sequential simple, dynamic and compartment cases pass.
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
      02_ranked_scenario_candidates.csv
    run_<RUN_ID>_<SCENARIO>/
      00_manifest.md
      00_new_run_candidates.csv
      00_baseline_candidate.csv
      00_fresh_run_validation.csv
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
      17_trace_milestones.csv
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

1. Start from the approved Wave 10D candidate and apply the subsequently approved output-parity changes from
   `EOS_Quark_Remaining_Parity_Change_Suggestions.md` before calling this a final parity campaign. At minimum, the
   PDF split, QXP XML conversion, QXPS transport and required safe completion logs must be in the tested build.
2. Run `mvn clean install` using the same Maven settings and JDK 21 used by the project.
3. Save the complete build output as `00_build.txt`.
4. Record the Git commit/branch, Java version, Maven version and artifact version in
   `01_runtime_and_commit.txt`. If there are uncommitted files, record their names without copying secrets.
5. Do not continue if any test fails. Warnings may be recorded for later triage, but a test failure invalidates the
   candidate.

A connected run executed before those changes is useful diagnostic evidence only. Label its manifest `PRE-FIX`; it
cannot approve final rendered-document parity.

### 4.2 Record configuration without secrets

In `02_effective_config_redacted.txt`, record only the following effective values:

- active Spring profile;
- Oracle host/service name (no username/password);
- QXPS host and configured timeouts/buffer limit (no query values);
- QXPSM host and configured timeouts;
- `engine.input.rabbit.enabled=false`;
- `engine.processing.max-concurrent-runs=3` after the concurrency change is implemented;
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

After the proposed safe transport observability change is implemented, successful calls must also produce one
summary line without payload data:

- QXPS: operation, method/path category, HTTP status, duration and response byte count;
- QXPSM: operation, duration and safe output size/count;
- never a full query-bearing URI, SQL, XML/modifier body, document text, BLOB, token or password.

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

Run `QOFF-01` for the broad historical inventory and `QOFF-01A` for ranked usable candidates. Export both files.
`QOFF-01A` returns successful historical runs grouped by scenario class, report type and compartment mode. It only
returns rows that currently have selected active change-capable tasks and a non-empty generated QXP.

Every ID returned by `QOFF-01` or `QOFF-01A` is a historical `.NET`/baseline selector. **Never POST one of these
historical IDs to Java.** Use its business fields to create an equivalent fresh run through the normal UI/backend
workflow. Section 6 explains how to locate and validate the new Java run ID.

### 5.1 Select the three mandatory archetypes

| Archetype | Required `QOFF-01A` values | Additional requirement before Java POST | Required proof after Java POST |
|---|---|---|---|
| Simple | `SCENARIO_CLASS=SIMPLE`, `SELECTED_ACTIVE_TASK_COUNT>0`, `SELECTED_CHANGE_TASK_COUNT>0` | `QOFF-02B=PASS`; `QOFF-05` has at least one `TODO=1` SQL, document or QXP-block task | `QOFF-17=PASS`; complete trace has non-zero task/step changes |
| Dynamic | `SCENARIO_CLASS=DYNAMIC`, `DYNAMIC_TASKS>0` | `QOFF-02B=PASS`; `QOFF-05` proves selected type 4; `QOFF-07` proves a non-empty dynamic template | Dynamic SQL fetched rows; generated blocks; `QOFF-17=PASS` |
| Compartment | `SCENARIO_CLASS=COMPARTMENT`, `COMPARTMENT_TASKS>0` | `QOFF-02B=PASS`; `QOFF-05` proves selected type 5; `QOFF-09` proves ordered child selection | Expected child generation/reuse/incorporation; parent `QOFF-17=PASS` |

For compartment coverage, select separate mode `1`, `2` and `3` baselines when each mode is present in current
data. Do not treat one mode as proof for another.

### 5.2 Cover all reachable report families

Use the `ID_TYPE_RAPPORT` and `REPORT_TYPE_LABEL` values returned by `QOFF-01A`; do not rely only on remembered code
meanings. The expected current families are:

| Report type | Family | Required campaign coverage |
|---|---|---|
| 1 | Annual report | At least one valid fresh case |
| 2 | Plaquette | At least one valid fresh case when current configuration exists |
| 3 | Prospectus | At least one valid fresh case when current configuration exists |
| 4 | Compartment report | Cover through valid parent/child compartment evidence; run directly only if the normal UI creates it as an executable root |
| 5 | DICI | At least one valid fresh case when current configuration exists |

If `QOFF-01A` returns no candidate for a report/archetype combination, save the zero-row evidence and record the
combination as not currently reachable. Do not invent rows, alter task associations, or force a report through an
unsupported path.

Prefer the smallest set of fresh runs that covers the largest number of branches, but do not select only Annual
Report runs. A single run may satisfy multiple live cases only when its pre-run exports prove every claimed branch.

### 5.3 Detailed connected run campaign

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

1. Choose one historical row from `QOFF-01A`. Save that exact row as `00_baseline_candidate.csv` in the future
   fresh-run folder.
2. Record its historical ID only as `Historical .NET/baseline run ID` in the manifest. Never send it to Java.
3. In the normal backend/UI, recreate the equivalent fund/unit, report type, due date, language, gabarit, source
   mode, compartment mode and requested task selection.
4. Create/generate the run using the usual business workflow.
5. Allow the normal batch handoff to reserve and publish it. The supplied `QXP_PK_BATCH.Get_Runs` flow changes an
   eligible run from status `1` to status `5`. The Java Rabbit listener remains disabled, so the message is not
   consumed by Java during this REST campaign.
6. Set `CREATED_AFTER` to a time immediately before step 4 and set `FUND_CODE` in the companion SQL file.
7. Run `QOFF-02` and save `00_new_run_candidates.csv`.
8. Match fund, unit, report type, language, due date, gabarit, source mode and creation time against the UI. Do not
   select a row merely because it is newest.
9. Set `RUN_ID` to the confirmed **fresh** ID.
10. Run `QOFF-02B` and save `00_fresh_run_validation.csv`.

`BASIC_ADMISSION_RESULT` must be `PASS`. It proves that:

- the normal batch has reserved the run with status `5`;
- the run is the current `ID_RUN_SUIVANT` for its suivi;
- exactly one fund/gabarit association can supply run properties;
- the configured gabarit exists;
- at least one active task is selected for this run;
- generation has not started and no generated document is already linked.

If `QOFF-02B` says `STOP`, do not repair the row manually and do not call either engine endpoint. Keep the export and
choose or create a valid run through the business flow.

Run `QOFF-03` immediately. Confirm and record:

- the fund, unit, report type, language, due date and gabarit match the requested generation;
- `ID_SUIVI` is correct and `ID_RUN_SUIVANT` points to this fresh run where the normal flow requires it;
- start/end dates and generated document IDs are still absent before execution;
- the status is the exact state supplied by the normal batch handoff.

For this REST campaign the expected state is the batch-reserved status `5`, as verified from the supplied Oracle
package. `Start_Run` later changes it to status `4` during execution.

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
| `QOFF-02B` | fresh-run admission | `BASIC_ADMISSION_RESULT=PASS` and selected TODO task count is greater than zero |
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
- `QOFF-02B` is not `PASS`;
- the run has no expected tasks or `QOFF-05` has no expected row with `TODO=1`;
- a simple case has no selected SQL/document/QXP-block task;
- a dynamic case has no selected type-4 task or no usable dynamic-template content;
- a compartment case has no selected type-5 task;
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

### 8.4 Expected evidence for a simple run

The pre-run files must show `SCENARIO_CLASS=SIMPLE`, at least one selected TODO task, and no selected dynamic or
compartment task. During execution, capture:

1. common run start/load milestones;
2. every selected task ID and type;
3. for SQL tasks, `SQL task [<TASK_ID>] (run [<RUN_ID>]) fetched <N> rows` with `N > 0` for the chosen success case;
4. for document tasks, selected document ID/format and PDF page count where applicable;
5. task trace lines with `updateCount` and `modifyCount`;
6. step lines with `add`, `update` and `excluded`, with at least one non-zero value across the run;
7. safe QXPS completion summaries corresponding to the step and final renders;
8. final QXP byte count, End attempt and terminal status.

If all selected tasks return no data or produce zero blocks, keep the evidence but select another run for the valid
simple parity case.

### 8.5 Expected evidence for a dynamic run

The pre-run files must show a selected type-4 task and a non-empty dynamic template. During execution, capture:

1. `Dynamic task [<TASK_ID>] (run [<RUN_ID>]) SQL fetched <N> rows`, with `N > 0`;
2. dynamic task prepare, process and post-process milestones;
3. task `updateCount`/`modifyCount`, with generated work greater than zero;
4. page-break, column-break, master-page and double-pagination behavior configured for that task;
5. overflow detection and reprocessing when `CONTROL_OVERFLOW=1`;
6. every QXPS step in order with non-zero add/update/exclude evidence;
7. safe QXPS/QXPSM completion summaries and output sizes;
8. final document evidence and `QOFF-17=PASS`.

A dynamic task returning zero rows does not satisfy the successful dynamic case. It may be retained as separate
empty-data behavior evidence.

### 8.6 Expected evidence for a compartment run

Before POST, `QOFF-09` must list the expected child funds/runs in exact position order. During execution, capture the
parent `runId` and child `childRunId` context on every child event.

| Mode | Expected behavior and logs |
|---|---|
| `1` - generate | `Generating child run [...]`; each selected child starts, processes, renders and persists; the parent does not incorporate child pages for this task |
| `2` - incorporate | `Reusing previous document for child run [...]`; previous child QXP is loaded; child pages/boxes are incorporated into parent steps |
| `3` - generate and incorporate | Child generation evidence followed by child QXP project extraction and incorporation into parent steps |

For every mode, confirm:

1. no expected child is missing;
2. child order matches `QOFF-09`;
3. generated children have terminal status and non-empty QXP results;
4. incorporated children contribute the expected pages/boxes;
5. child traces are merged into the parent trace without losing child IDs;
6. later parent tasks continue according to .NET behavior;
7. parent final render and persistence complete;
8. `QOFF-09` after execution matches observed child statuses/documents;
9. `QOFF-17=PASS`, including a non-zero child or parent modification step.

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
8. `QOFF-16` as `16_completion_check.csv`;
9. `QOFF-17` as `17_trace_milestones.csv`.

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
- `QOFF-17.TRACE_EVIDENCE_RESULT=PASS` for a valid non-degraded parity case;
- `QOFF-17.HAS_NONZERO_STEP_CHANGE=1`; a configured task with no actual add/update/exclude does not satisfy the
  successful scenario requirement;
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

For strict final rendered-document approval, use the same approved renderer for both `.NET` and Java outputs and
record:

1. page count, dimensions and rotation equality;
2. extracted text/content equality;
3. one raster image per page at the same DPI and color settings;
4. pixel-difference count per page;
5. visual classification of every non-zero difference.

No unexplained visible/content/layout difference is accepted. Binary hashes are still recorded, but binary equality
is not required when the only differences are non-rendered metadata, timestamps, compression or object numbering.

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

## 13. Required logging from now on

The existing logs are sufficient for an initial diagnostic run only when all four sources are captured together:

1. console/ECS application logs;
2. persisted `QXP_RUN.LOG_TRACE`;
3. pre/post Oracle exports;
4. generated binaries and comparison notes.

The implementation already provides run/task/step IDs, task row counts, safe task errors, step counts, overflow
activity, child-run context, render byte counts, document insertion and End/final status. It also avoids printing
whole task SQL.

Before final parity sign-off, implement and capture these safe completion logs:

1. **QXPS successful-call completion:** one safe line per call with operation/method, path category, HTTP status,
   duration and response byte count. It must not include query values, full URI, response body, XML or document
   content.
2. **QXPSM successful-call completion:** operation (`process` or `getXPressDOM`), duration and safe result size/count
   such as output bytes or layout count. It must not include the SOAP body, modifier XML, paths containing sensitive
   values or document text.
3. **Run admission:** source (`REST` or `RABBIT`), run ID, persisted status, claim accepted/rejected and redelivery
   flag. Do not log parameter values.
4. **Concurrency permit:** permit acquired/released, run ID and active root count. Do not emit a repeating waiting
   line while a run is queued.

INFO plus persisted trace must expose one safe run-load summary containing gabarit source/size, parameter count and
types, task-type counts, selected task count and selected document count. Names/values that can contain business data
remain in the protected Oracle exports, not ordinary logs.

For every QXPS modification or render request, the request-start evidence and completion evidence must pair by
`runId`, `taskId`/`stepIndex` where applicable, and operation category. A missing completion event means unknown
transport outcome and must be investigated before retrying the run.

## 14. What to bring back for analysis

For each run, bring the complete folder listed in section 3. At minimum, a run cannot be analyzed conclusively
without:

- manifest and exact fresh run ID;
- `QOFF-01A` baseline candidate row and `QOFF-02B=PASS` fresh-run validation;
- pre-run overview, parameters, tasks and relevant document/compartment selection;
- GET and POST HTTP captures;
- complete run console interval;
- complete persisted trace chunks;
- `QOFF-17` milestone result, including non-zero step-change proof;
- post-run overview, errors, audit, document metadata and storage exports;
- generated artifacts and SHA-256 file;
- accepted .NET baseline ID/artifacts/logs where available;
- a short note describing what was expected and what was visually observed.

If time at the office is limited, prioritize in this order:

1. one valid simple run with non-zero changes;
2. one valid dynamic run with returned rows and non-zero changes;
3. one valid compartment mode-3 run;
4. separate compartment mode-1 and mode-2 runs;
5. SQL formatting/storage and DOC EOS/PDF branches;
6. remaining report types, languages, source modes and document formats.

Do not rush several incomplete runs. One complete evidence bundle is more valuable than many run IDs without pre-run
inputs, persisted trace or generated artifacts.

## 15. Later Rabbit/concurrency evidence campaign

This is a separate production-readiness campaign. Do not perform it during the REST-only functional parity session.
Begin only after the atomic run claim, duplicate guard, configurable three-root limiter and safe admission logs are
implemented and the simple/dynamic/compartment sequential cases pass.

Required cases:

1. Publish four different valid fresh run IDs and prove only three roots are active at once.
2. Prove the fourth starts only after one active root releases its permit.
3. Publish the same run ID twice and prove only one atomic Oracle claim succeeds.
4. Redeliver a terminal run and prove no second execution or document insertion occurs.
5. Present a status-`4` run and prove Java does not rerun it automatically.
6. Run three representative near-200-MiB reports and capture heap, process RSS, GC pauses, duration and container
   restart/OOM evidence.

Expected safe logs:

- Rabbit receive with run ID and redelivery flag;
- Oracle claim accepted/rejected and persisted status;
- root permit acquired/released and active count, never above three;
- one distinct execution context/root workspace per active run;
- duplicate decision without SQL, document or parameter payload;
- terminal acknowledgement only after terminal state is persisted.

The deployment currently has one replica. If replicas are increased, this campaign must also prove the required
cluster-wide concurrency behavior; a per-replica setting of three is not a global cap of three.
