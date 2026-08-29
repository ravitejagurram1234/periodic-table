# EOS Quark Engine — office live-run evidence capture guide

Status: operational guide for the REST-only connected parity campaign after the output-parity changes are built.
It does not approve production deployment and does not authorize a code or database change.

Companion SQL: [EOS_Quark_Office_Live_Run_Evidence_Queries.sql](./EOS_Quark_Office_Live_Run_Evidence_Queries.sql)

Controlled non-production reservation:
[EOS_Quark_NonProd_Swagger_Run_Reservation.sql](./EOS_Quark_NonProd_Swagger_Run_Reservation.sql)

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

For every executed run, `QOFF-02B` must prove before execution that the selected status-`5` run is unused, valid and
has selected work. If no suitable status-`5` row exists, create the run through the old UI, require `QOFF-02A=PASS`
while it is still status `1`, reserve it with the guarded non-production script, and then require `QOFF-02B=PASS`.
After execution, `QOFF-17` must prove that at least one QXPS step had a non-zero add, update or exclude count. A run
that has tasks configured but produces no document change is useful diagnostic evidence, but it does not satisfy
this campaign's successful parity case.

A Java `GENERATED` status by itself is not parity proof. Final replacement approval still needs paired .NET/Java
comparison, controlled error/fault scenarios and the remaining operational controls in
`EOS_Quark_Paired_Run_Acceptance_Matrix.md`.

## 2. Non-negotiable safety rules

- Keep Rabbit consumption disabled throughout this campaign:
  `engine.input.rabbit.enabled=false`. Do not temporarily override it.
- Use the REST endpoint only for engine execution. The old UI may create the run but must not execute it. Process one
  run at a time.
- Do not start the three-run concurrency campaign until the sequential simple, dynamic and compartment cases pass.
- Prefer an existing batch-reserved status-`5` run from `QOFF-01B`.
- If no suitable status-`5` row exists, the only allowed manual transition is the guarded non-production
  `QXP_RUN.ID_STATUT_GENERATION` change from `1` to `5` described in section 6. Never update `QXP_SUIVI`, dates,
  document links, parameters or task associations by hand.
- Stop the batch, old .NET engine and Java engine before creating a run through the old UI. Stopping them only after
  clicking Generate leaves a race in which the batch can reserve or process the run first.
- A historical successful run is only a scenario/baseline selector. Never submit a historical run ID to
  `processRun`.
- Submit the validated Swagger run ID to `processRun` exactly once. If the HTTP client times out, do not submit it
  again; inspect
  application logs and `QOFF-03`/`QOFF-16` first.
- Do not start .NET and Java sequentially on the same run. Use an accepted historical .NET capture plus an
  equivalent unused Java run, or isolated equivalent database states.
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
      03_swagger_ready_run_candidates.csv
      04_ui_created_status1_candidates.csv
    run_<RUN_ID>_<SCENARIO>/
      00_manifest.md
      00_swagger_ready_candidates.csv
      00_pre_reservation_validation.csv
      00_reservation_console.txt
      00_baseline_candidate.csv
      00_selected_run_validation.csv
      01_pre_run_overview.csv
      02_parameters.csv
      03_tasks.csv
      04_selected_task_change_readiness.csv
      04_task_exceptions.csv
      05_template_metadata.csv
      05b_effective_gabarit_source.csv
      06_selected_task_documents.csv
      06b_previous_qxp_task_documents.csv
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

For the controlled old-UI path, prepare these settings while Java is stopped and start Java only after the status
`1` to `5` reservation has passed `QOFF-02B` and been committed. For an already reserved `QOFF-01B` run, Java may be
started during session preparation as long as Rabbit remains disabled and no POST is sent.

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

- QXPS: method, message types, HTTP status, duration and binary-byte/text-character count;
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

## 5. Choose Swagger run IDs from SQL

Use one of these paths:

1. **Preferred existing reservation:** run `QOFF-01B`. It returns status-`5` runs that are current for their suivi,
   have not started, have no generated-document links, and contain selected active change-capable tasks.
2. **Fresh old-UI run:** when no suitable status-`5` row exists, stop all consumers first, create the run normally
   in the old UI, and run `QOFF-01C`. It returns only status-`1` rows eligible for the controlled reservation path.
   A `QOFF-01C` ID is not Swagger-ready until `QOFF-02A`, the guarded reservation, and `QOFF-02B` all pass.

Run `QOFF-01` and `QOFF-01A` only when a historical successful `.NET` result is needed for comparison. IDs returned
by `QOFF-01`/`QOFF-01A` are status-`2` baselines and must never be posted. `QOFF-01B.SUGGESTED_BASELINE_RUN_ID` points
to the previous run when one exists; `QOFF-01C` provides the same baseline fields.

`CONFIGURED_CHANGE_SHAPE` describes selected task configuration:

- `UPDATE_AND_MODIFY_CONFIGURED`: at least one selected type-1 value-update task and at least one selected type-2
  through type-5 structure-modification task;
- `UPDATE_CONFIGURED`: value-update work only;
- `MODIFY_CONFIGURED`: structure-modification work only.

Prefer `UPDATE_AND_MODIFY_CONFIGURED` for broad cases. This still cannot guarantee a change: task SQL may return no
rows or a source block may be absent in the current document. `BASELINE_HAS_NONZERO_STEP_CHANGE=1` increases
confidence because the previous completed run changed blocks, but the current run is proven only by runtime task
counts and `QOFF-17`.

### 5.1 Select the three mandatory archetypes

| Archetype | Required candidate values (`QOFF-01B` or `QOFF-01C`) | Additional requirement before Java POST | Required proof after Java POST |
|---|---|---|---|
| Simple | `SCENARIO_CLASS=SIMPLE`, `SELECTED_ACTIVE_TASK_COUNT>0`, `SELECTED_CHANGE_TASK_COUNT>0` | `QOFF-02B=PASS`; `QOFF-05A` has selected SQL, document or QXP-block work | `QOFF-17=PASS`; complete trace has non-zero task/step changes |
| Dynamic | `SCENARIO_CLASS=DYNAMIC`, `DYNAMIC_TASKS>0` | `QOFF-02B=PASS`; `QOFF-05A` proves selected type 4; `QOFF-07` proves a non-empty dynamic template | Dynamic SQL fetched rows; generated blocks; `QOFF-17=PASS` |
| Compartment | `SCENARIO_CLASS=COMPARTMENT`, `COMPARTMENT_TASKS>0` | `QOFF-02B=PASS`; `QOFF-05A` proves selected type 5; `QOFF-09` proves ordered child selection | Expected child generation/reuse/incorporation; parent `QOFF-17=PASS` |

For compartment coverage, select separate mode `1`, `2` and `3` candidates when each mode is present in current
data. Do not treat one mode as proof for another.

### 5.2 Cover all reachable report families

Use the `ID_TYPE_RAPPORT` and `REPORT_TYPE_LABEL` values returned by `QOFF-01B`/`QOFF-01C`; do not rely only on
remembered code meanings. The expected current families are:

| Report type | Family | Required campaign coverage |
|---|---|---|
| 1 | Annual report | At least one valid Swagger case |
| 2 | Plaquette | At least one valid Swagger case when a candidate can be created or already exists |
| 3 | Prospectus | At least one valid Swagger case when a candidate can be created or already exists |
| 4 | Compartment report | Cover through a valid parent/child compartment candidate returned by SQL |
| 5 | DICI | At least one valid Swagger case when a candidate can be created or already exists |

If `QOFF-01B` has no row, create a valid run through the old UI and try `QOFF-01C`. If neither path returns the
required report/archetype combination, save the zero-row evidence and record it as not currently reachable. Do not
invent rows, alter task associations, or force a report through an unsupported path.

Prefer the smallest set of unused runs that covers the largest number of branches, but do not select only Annual
Report runs. A single run may satisfy multiple live cases only when its pre-run exports prove every claimed branch.

### 5.3 Detailed connected run campaign

| Live case | Required Swagger-run characteristic | How to confirm before POST |
|---|---|---|
| L01 — broad normal run | Multiple task types and normal DID processing; prefer both update and modify configuration | `QOFF-05`, `QOFF-05A`; use a matching historical baseline only when its inputs are equivalent |
| L02 — SQL formatting | SQL task with date/port binds, decimal formatting, zero/null marker and exceptions | `QOFF-04` to `QOFF-06`; task 53/run 509199 is a known historical shape |
| L03 — three-parameter SQL/storage | Port/date/gabarit or port/date/unit and `STORE_DATA=1` | `QOFF-04`, `QOFF-05A`; known historical shapes include tasks 133 and 206 |
| L04 — DOC EOS QXP value | Type-2 task, selected format QXP, `CONSERVER_STYLE=0` | `QOFF-05A`, `QOFF-08` |
| L05 — DOC EOS QXP style | Type-2 task, selected format QXP, `CONSERVER_STYLE=1` | `QOFF-05A`, `QOFF-08` |
| L06 — DOC EOS PDF/image | Type-2 PDF and image inputs; include rotated/cropped or multipage input if reachable | `QOFF-05A`, `QOFF-08` |
| L07 — Bloc QXP/previous | Type-3 task, preferably explicit and hierarchy/level variants | `QOFF-05A`, `QOFF-08B` |
| L08 — dynamic normal | Type-4 task with returned data | `QOFF-05A`; console/trace must show fetched rows and created processing steps |
| L09 — dynamic complex | Type-4 task with page/column break rules, double pagination or overflow control | `QOFF-03`, `QOFF-05A`; require `PAGINATION_DOUBLE=1` and/or `CONTROL_OVERFLOW=1` where available |
| L10 — compartment generate | Type-5 task with `MODE_COMPART=1` | `QOFF-03`, `QOFF-05A`, `QOFF-09` |
| L11 — compartment incorporate | Type-5 task with `MODE_COMPART=2` | `QOFF-03`, `QOFF-05A`, `QOFF-09` |
| L12 — compartment both | Type-5 task with `MODE_COMPART=3` | `QOFF-03`, `QOFF-05A`, `QOFF-09` |
| L13 — document storage | Gabarit `STORE_DATA_TYPE` contains bit 2 | `QOFF-03`, then verify `QOFF-14A/B` after execution |
| L14 — accepted nonblocking errors | A normal business run known to record Critique/Unspecified task errors but continue | Historical trace/errors plus unused equivalent run; verify later tasks still execute |
| L15 — all starting-document sources | Separate reachable runs with `GABARIT_SOURCE` 1, 2, 3 and 4 | `QOFF-03`, `QOFF-07B`; source ID and byte size must be non-null |
| L16 — output formats | QXP and PDF on every normal run; DOC when `GENERATE_TO_WORD=1` | `QOFF-07`, then `QOFF-13` and artifact hashes |
| L17 — report-family coverage | Report types 1, 2, 3, 4 and 5 where the UI/configuration supports them | Candidate query plus `QOFF-03`; do not infer type from the run name |
| L18 — large document | Representative 66-200 MiB source after normal cases pass | `QOFF-07B` byte size, JVM/GC evidence and all ordinary post-run checks |

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

## 6. Create/select and reserve the Swagger run ID

### 6.1 Path A: an existing status-5 run is available

1. Run `QOFF-01B` and save `03_swagger_ready_run_candidates.csv`.
2. Choose the required `SIMPLE`, `DYNAMIC` or `COMPARTMENT` row. For compartment coverage, also check `MODE_COMPART`.
3. Use `SWAGGER_RUN_ID`, never `SUGGESTED_BASELINE_RUN_ID`, as the execution ID.
4. Set `RUN_ID` in the evidence SQL file.
5. Run `QOFF-02B` and save `00_selected_run_validation.csv`.
6. Continue only when `BASIC_ADMISSION_RESULT=PASS`.

Because the batch may already have published this status-`5` ID, keep Rabbit disabled and preserve the queue-depth
evidence. Classify the pending message before Rabbit is enabled later.

### 6.2 Path B: create a fresh run through the old UI

Use this path only in non-production when Path A has no suitable case.

1. Stop/disable the **batch**, the **old .NET engine**, and the **Java engine** before clicking Generate in the UI.
   Keep only the UI/backend components needed to call `QXP_PK_WEB.InsertRun` available. Confirm all three consumers
   are stopped; stopping them after creation is too late because the batch can race the operator.
2. In the old UI, select the real fund/unit, report, date, language, gabarit/source mode, compartment mode and active
   tasks needed for the case. Select tasks normally in the UI; never add rows directly to `QXP_ASSO_RUN_TACHES`.
3. Submit/plan the run through the normal UI flow. `InsertRun` creates or refreshes the current `QXP_RUN` with status
   `1`, sets `QXP_SUIVI.ID_RUN_SUIVANT`, sets `QXP_SUIVI.ID_STATUT_GENERATION=1`, and `InsertRunTaches` records the
   selected tasks.
4. Run `QOFF-01C` and save `04_ui_created_status1_candidates.csv`. Choose `UI_CREATED_RUN_ID` for the intended
   scenario/report/mode. Prefer `CONFIGURED_CHANGE_SHAPE=UPDATE_AND_MODIFY_CONFIGURED` and
   `BASELINE_HAS_NONZERO_STEP_CHANGE=1` when available.
5. Set `RUN_ID` in the evidence SQL file. Run `QOFF-02A` and save `00_pre_reservation_validation.csv`. Continue only
   when `PRE_RESERVATION_RESULT=PASS`.
6. Before changing status, run `QOFF-03` through `QOFF-09`, including `QOFF-05A`. This catches a wrong report, empty
   dynamic template, missing task document or bad compartment child while rollback is still simple.
7. In SQL Developer/SQLcl, turn **autocommit off**. In the same Oracle session, open
   `EOS_Quark_NonProd_Swagger_Run_Reservation.sql`, set both `RUN_ID` and `CONFIRM_RUN_ID`, execute it once, and save
   DBMS output/result as `00_reservation_console.txt`.
8. The script must print `RESERVATION_UPDATED_ROWS=1`, `QXP_RUN_STATUS=5`, and `TRANSACTION IS UNCOMMITTED`. Its
   post-check must be `PASS`.
9. Before committing, run `QOFF-02B` in that same session. If it is not `PASS`, execute `ROLLBACK`; do not repair any
   other row. If it is `PASS`, execute `COMMIT` manually.
10. Run `QOFF-02B` again after commit and save the final result as `00_selected_run_validation.csv`.
11. Start Java with `engine.input.rabbit.enabled=false`. Keep the batch and old .NET engine stopped until all
   pre/post evidence for that run is complete.

### 6.3 Which table is changed and why

Change only `QXP_RUN.ID_STATUT_GENERATION` from `1` to `5` through the guarded script.

Do **not** change `QXP_SUIVI.ID_STATUT_GENERATION` to `5`. The supplied Oracle package proves the lifecycle:

- `QXP_PK_WEB.InsertRun` sets the run and suivi to status `1` and links `ID_RUN_SUIVANT`;
- `QXP_PK_BATCH.Get_Runs`/`Get_Runs_Initials` reserve work by updating only `QXP_RUN` to status `5`;
- Java `Start_Run` changes `QXP_RUN` to running status `4`;
- terminal `End_Run`/`Update_Status_Run` updates the final run state and then moves/updates the suivi.

Changing `QXP_SUIVI` to `5` would create a state the real batch reservation does not create. Do not call
`Start_Run`, `Update_Runs_Status`, `End_Run`, or any package procedure manually for this campaign.

`QOFF-02` remains optional for narrowing by time/fund. A historical status-`2` run remains comparison evidence only.
Never POST it.

For either path, `BASIC_ADMISSION_RESULT=PASS` proves status `5`, suivi status `1`, current-run linkage, exactly one
run-property association, an active gabarit, non-empty direct content for source mode `1`, selected active
type-1-to-type-5 work, no generation dates and no output links. `QOFF-07B` separately proves the effective binary for
source modes `2` through `4`. If admission says `STOP`, do not call GET or POST. Roll back only if the guarded transaction is still open;
after commit, stop and ask for review rather than making further manual changes.

Run `QOFF-03` immediately before starting Java and confirm the business identity, `ID_RUN_SUIVANT`, status, empty
start/end dates and empty output links. `Start_Run` will change `QXP_RUN` to status `4` when processing begins.

Create `00_manifest.md` with:

```markdown
# Run evidence manifest

- Live case IDs:
- Selection path (existing status 5 / old UI + guarded reservation):
- Swagger Java run ID:
- Suivi ID:
- Historical .NET/baseline run ID:
- Fund/unit:
- Report type:
- Due date:
- Language:
- Gabarit ID/source:
- Expected task branches:
- Configured change shape:
- QOFF-02A result (Path B only):
- Reservation updated rows/committed at (Path B only):
- QOFF-02B result:
- Selected at:
- Optional GET sent at:
- POST sent at:
- HTTP completed at:
- Operator:
- Build/commit reference:
- Notes (no secrets):
```

## 7. Mandatory read-only checks before POST

"Export Oracle inputs" means run the listed `SELECT` queries and save their result grids as CSV/text. It does not
mean exporting the database, changing rows, or downloading BLOB content. These files tell us exactly what Java was
given: run identity, parameter values, selected tasks, source documents and compartment children. Without them, a
different result cannot be separated into an input-data difference versus a Java logic difference.

Before calling the endpoint, run and save:

| Query | Evidence | Mandatory check |
|---|---|---|
| `QOFF-02A` | UI-created pre-reservation admission (Path B only) | `PRE_RESERVATION_RESULT=PASS` before status change |
| `QOFF-02B` | selected-run admission | `BASIC_ADMISSION_RESULT=PASS` and selected TODO task count is greater than zero |
| `QOFF-03` | run/suivi/gabarit overview | exact business identity, admission status and links |
| `QOFF-04` | all parameters | names, types, values and count match the run; keep 3- and 4-parameter shapes when present |
| `QOFF-05` | task inventory/config | every expected task exists; SQL text is not exported |
| `QOFF-05A` | selected change readiness | expected update/modify task shape; no `STOP` readiness result |
| `QOFF-06` | SQL exception rules | duplicates and whole-table/indexed rules are preserved |
| `QOFF-07` | gabarit/template metadata | configured size, pagination, storage and dynamic-template flags |
| `QOFF-07B` | effective starting gabarit | exact template/upload/previous/certified source ID and byte size selected by source modes 1–4 |
| `QOFF-08` | selected DOC EOS documents | expected format; `MATCHED_DOCUMENT_COUNT` should normally be 1 per type-2 task |
| `QOFF-08B` | selected previous certified QXP | non-empty QXP and `PREVIOUS_QXP_READINESS=PASS` per type-3 task |
| `QOFF-09` | compartment children | exact child order/run/status for type-5 runs; otherwise zero rows |

Stop before POST and report the evidence if:

- any expected input parameter is missing or has an unexpected type/shape;
- `QOFF-02B` is not `PASS`;
- the run has no expected tasks, `QOFF-05` has no expected row with `TODO=1`, or `QOFF-05A` has no selected
  change-capable task;
- a simple case has no selected SQL/document/QXP-block task;
- a dynamic case has no selected type-4 task or no usable dynamic-template content;
- a compartment case has no selected type-5 task;
- a type-2 task has `MATCHED_DOCUMENT_COUNT=0` or greater than 1, unless that edge is the deliberately selected test;
- a compartment case has the wrong mode, child order, missing child, or wrong selected previous/next child;
- a generated document ID or generation end date is already present on the selected unused run;
- the run identity or handoff status/link is not the expected normal-flow result.

## 8. REST execution and live log capture

The current route is intentionally left as already implemented for this phase:

```text
GET  /api/v1/EngineService/fetchRunProperties/{runId}
POST /api/v1/EngineService/processRun/{runId}
```

Use Swagger, Postman or the approved authenticated internal client. Never save an access token in the evidence
folder.

### 8.1 Properties GET exactly once

The GET endpoint does not execute the run. It only proves that Java can read and map the selected Oracle run
properties. After `QOFF-02B=PASS`, call exactly once in Swagger:

```text
GET /api/v1/EngineService/fetchRunProperties/{runId}
```

Save the HTTP status/JSON as `08_fetch_run_properties_http.txt`. Compare its non-binary fields to `QOFF-03` and
`QOFF-04`.

Expected success is HTTP 200. A 500, missing property or mapping difference is a failed case; do not continue to
`processRun` until it is understood.

Do not repeat the GET to investigate a difference; use the saved response and Oracle export. Continue to POST only
after the GET returns the expected mapped identity.

### 8.2 Process exactly once

In Swagger, use the validated `SWAGGER_RUN_ID`. Record the send timestamp, then call exactly once:

```text
POST /api/v1/EngineService/processRun/{runId}
```

Save the HTTP status and response body as `08_process_run_http.txt`.

- HTTP 200 with terminal `GENERATED` means the service reports successful completion.
- HTTP 500 with a body containing terminal `ERROR` means processing completed and persisted a run error; capture
  all evidence and classify the cause.
- HTTP 500 with an empty body means the adapter did not receive a usable terminal result; capture all logs and DB
  state.
- An HTTP timeout is unknown, not permission to retry. Check logs and `QOFF-03`/`QOFF-16`.

Copy the complete console interval from the controller line `Processing run with runId: <ID>` through
`Run completed: runId=<ID>, status=...` into `08_run_console.log`. If the final line is absent, copy from
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
3. for SQL tasks, `SQL task completed: taskId=<TASK_ID>, runId=<RUN_ID>, sqlChars=<C>, bindCount=<B>, rowCount=<N>, durationMs=<MS>` with `N > 0` for the chosen success case;
4. for document tasks, selected document ID/format and PDF page count where applicable;
5. task trace lines with `updateCount` and `modifyCount`;
6. step lines with `add`, `update` and `excluded`, with at least one non-zero value across the run;
7. safe QXPS completion summaries corresponding to the step and final renders;
8. final QXP byte count, End attempt and terminal status.

If all selected tasks return no data or produce zero blocks, keep the evidence but select another run for the valid
simple parity case.

### 8.5 Expected evidence for a dynamic run

The pre-run files must show a selected type-4 task and a non-empty dynamic template. During execution, capture:

1. `Dynamic SQL task completed: taskId=<TASK_ID>, runId=<RUN_ID>, sqlChars=<C>, bindCount=<B>, rowCount=<N>, durationMs=<MS>`, with `N > 0`;
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

These are read-only `SELECT` queries executed after the POST. Their purpose is to show what the engine persisted:
final status, errors, audit, generated document IDs/sizes, optional stored data, compartment child results and the
complete run trace. They do not change Oracle data.

Wait for the HTTP response or terminal log line, then run and save:

1. `QOFF-03` as `10_post_run_overview.csv`;
2. `QOFF-11` as `11_errors.csv`;
3. `QOFF-12` as `12_audit.csv`;
4. `QOFF-13` as `13_documents.csv`;
5. `QOFF-14A` and `QOFF-14B` as storage summary/rows;
6. `QOFF-15` as the complete chunked persisted trace;
7. `QOFF-09` again as `15_post_compartment_children.csv`;
8. `QOFF-16` as `16_completion_check.csv`;
9. `QOFF-17` as `17_trace_milestones.csv`.

For a non-compartment run, `QOFF-09` should return zero rows. For a run without storage flags, `QOFF-14A/B` should
return zero rows. Save those empty results with headers because they confirm that no unexpected rows were written.

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

This section is an implementation record and verification checklist; a Markdown file does not modify Java code.
The logging code described below is already applied only in the Java workspace from which this guide was produced.
Any separate office-laptop clone must receive the corresponding Java/resource/test changes and pass
`mvn clean install` before these lines can be expected during a Swagger run.

The existing logs are sufficient for an initial diagnostic run only when all four sources are captured together:

1. console/ECS application logs;
2. persisted `QXP_RUN.LOG_TRACE`;
3. pre/post Oracle exports;
4. generated binaries and comparison notes.

The implementation now provides the bounded run-load, selected-task, static/dynamic SQL, QXPS, QXPSM and terminal
summaries defined in sections 13.1 through 13.5. These lines are safe to capture at `INFO`: they contain IDs,
types, counts, statuses, byte/character sizes and durations, but no SQL text, bind values, document paths or
transport payloads.

The following admission logs remain future work and must be implemented together with the duplicate guard and
configurable root-run limiter, not as part of the current Swagger evidence logging change:

1. **Run admission:** source (`REST` or `RABBIT`), run ID, persisted status, claim accepted/rejected and redelivery
   flag. Do not log parameter values.
2. **Concurrency permit:** permit acquired/released, run ID and active root count. Do not emit a repeating waiting
   line while a run is queued.

INFO plus persisted trace now expose one safe run-load summary containing gabarit source/size, parameter count,
task-type counts, selected task count and selected document-task count. Parameter types and all names/values that can
contain business data remain in the protected Oracle exports, not ordinary logs.

For every QXPS modification or render request, the request-start evidence and completion evidence must pair by
`runId`, `taskId`/`stepIndex` where applicable, and operation category. A missing completion event means unknown
transport outcome and must be investigated before retrying the run.

Do not spend the final office session collecting parity evidence until the current branch is built in the normal
corporate Maven environment and the tests in section 13.5 pass there. The source and focused fallback verification
do not replace the Jenkins/Maven build.

### 13.1 Run load and terminal summary

Location: `ProcessRunServiceImpl.load`, immediately before `Run loading completed`, and the root-run `finally`
immediately before `Run completed`.

```java
var taskTypeCounts = run.getTasks().values().stream()
        .collect(java.util.stream.Collectors.groupingBy(
                task -> task.getClass().getSimpleName(),
                java.util.TreeMap::new,
                java.util.stream.Collectors.counting()));
long selectedTasks = run.getTasks().values().stream().filter(TaskBase::isTodo).count();
long selectedDocumentTasks = run.getTasks().values().stream()
        .filter(TaskBase::isTodo)
        .filter(TaskDocument.class::isInstance)
        .count();

log.info("Run load summary: runId={}, suiviId={}, reportTypeCode={}, gabaritSource={}, "
                + "gabaritBytes={}, degraded={}, inParamCount={}, taskCount={}, "
                + "todoTaskCount={}, todoDocumentTaskCount={}, templateCount={}, "
                + "taskTypeCounts={}, dynamicTemplateBytes={}",
        run.getId(), runProperties.getIdSuivi(), runProperties.getTypeRapportCode(),
        runProperties.getGabaritSource(), documentBytes(run.getGabarit()),
        runProperties.isModeDegrade(), run.getInParams().size(), run.getTasks().size(),
        selectedTasks, selectedDocumentTasks, run.getTemplates().size(), taskTypeCounts,
        documentBytes(run.getGabaritTemplate()));
```

```java
log.info("Run completed: runId={}, status={}, durationMs={}, errorCount={}, "
                + "terminalStatePersisted={}, finalQxpBytes={}, finalPdfBytes={}, finalJpgBytes={}",
        run.getId(), run.getStatus(), durationMillis(run.getStartDate(), run.getEndDate()),
        run.getErrors().size(),
        run.isTerminalStatePersisted(), documentBytes(run.getResult().getFinalQxp()),
        documentBytes(run.getResult().getFinalPdf()),
        documentBytes(run.getResult().getFinalJpg()));

private static int documentBytes(DocumentDomain document) {
    return document == null || document.getData() == null ? 0 : document.getData().length;
}
```

These lines contain counts, enum/code values and byte sizes only. Do not add parameter names/values, task comments,
document names or paths.

### 13.2 Per-task result and bounded SQL metrics

Location: `ProcessTasksServiceImpl.processTasks`, in the first-pass `finally` after the persisted trace, and
immediately before skipping a selected task already marked in error by prepare. This produces exactly one line per
selected task without reprocessing a prepare failure.

```java
log.info("Task result: taskId={}, taskType={}, inError={}, updateBlocks={}, "
                + "modifyBlocks={}, storedDataRows={}",
        task.getId(), task.getClass().getSimpleName(), task.isInError(),
        task.getBlocsUpdate().size(), task.getBlocsModify().size(),
        task.getDataNamesValues().size());
```

Location: `ProcessSqlBusiness.execute` and the dynamic SQL stage. Measure around the DAO call and replace the
row-count-only line with this bounded shape:

```java
int sqlChars = task.getSql() == null ? 0 : task.getSql().length();
long sqlStartedNanos = System.nanoTime();
List<Map<String, Object>> rows = taskSqlDao.executeSql(task.getSql(), parameters);
log.info("SQL task completed: taskId={}, runId={}, sqlChars={}, bindCount={}, "
                + "rowCount={}, durationMs={}",
        task.getId(), task.getRun().getId(), sqlChars,
        parameters == null ? 0 : parameters.size(), rows.size(),
        java.util.concurrent.TimeUnit.NANOSECONDS.toMillis(
                System.nanoTime() - sqlStartedNanos));
```

The dynamic path uses the same fields with the prefix `Dynamic SQL task completed:`. Calculate `sqlChars` before
the log call. Never pass `task.getSql()` to a logger, and never log a row map, bind names/values, block names/values
or the JDBC exception message when it embeds SQL. `SQL_LENGTH` in `QOFF-05` is the database-side equivalent.

Row/cell-level anomalies remain separate persisted `RunError` entries for parity, but console logging aggregates
them into at most one line per task:

```text
SQL row anomalies: taskId=<ID>, runId=<ID>, duplicateBlocks=<COUNT>, failedRows=<COUNT>
Dynamic cell anomalies: taskId=<ID>, runId=<ID>, duplicateBlocks=<COUNT>, unsupportedCells=<COUNT>, failedCells=<COUNT>
```

No duplicate block name, cell value, row map or exception message is printed. This prevents thousands of malformed
rows or cells from producing thousands of console lines while preserving the total counts needed for diagnosis.

### 13.3 QXPS request completion

Location: `QxpsResponseInfo` and `QxpsHttpClient.executeCombined`/`handleResponse`. Add the status code to the safe
response metadata, set it from `clientResponse.statusCode()`, then pair the existing start line with this completion:

```java
// QxpsResponseInfo
private int httpStatus;
```

```java
// handleResponse, after QxpsResponseInfo is created
response.setHttpStatus(status.value());
```

```java
// executeCombined: start metadata contains no URI or document name
log.info("QXPS call: method={}, messageTypes={}, queryParameterCount={}, requestBytes={}",
        requestInfo.getMethod(), messageTypes, queryParameterCount,
        requestInfo.getData() == null ? 0 : requestInfo.getData().length);

long startedNanos = System.nanoTime();
try {
    QxpsResponseInfo response = requestInfo.getMethod() == HttpMethod.POST
            ? executePost(requestInfo) : executeGet(requestInfo);
    log.info("QXPS completed: method={}, messageTypes={}, httpStatus={}, durationMs={}, "
                    + "responseCategory={}, responseBytes={}, responseChars={}",
            requestInfo.getMethod(), messageTypes, response.getHttpStatus(),
            elapsedMillis(startedNanos), responseCategory(response),
            responseBytes(response), responseChars(response));
    return response;
} catch (RuntimeException failure) {
    log.error("QXPS failed: method={}, messageTypes={}, durationMs={}, causeType={}",
            requestInfo.getMethod(), messageTypes,
            elapsedMillis(startedNanos), failure.getClass().getSimpleName());
    throw failure;
}
```

```java
private static long elapsedMillis(long startedNanos) {
    return java.util.concurrent.TimeUnit.NANOSECONDS.toMillis(
            System.nanoTime() - startedNanos);
}

private static int responseBytes(QxpsResponseInfo response) {
    return response.getBinaryResponse() == null ? 0 : response.getBinaryResponse().length;
}

private static int responseChars(QxpsResponseInfo response) {
    return response.getTextResponse() == null ? 0 : response.getTextResponse().length();
}
```

No URI path is logged because the QXPS path ends with the document name and can expose business identifiers. Never
log `documentName`, `requestInfo.getUri()`, `getPath()`, `getRawQuery()`, request/response content, multipart bytes
or XML. Text responses use `responseChars`; converting a very large text response back to UTF-8 only to count bytes
would create an avoidable second allocation. Binary responses use the exact `responseBytes` count.

### 13.4 QXPSM completion

Location: `QxpsmSoapClient.executeStep`, around `stub.processRequest(context)`, and `getProject`, around
`stub.getXPressDOM(documentName)`.

```java
long startedNanos = System.nanoTime();
int nameValueCount = nameValues == null ? 0 : nameValues.size();
int modifierLayoutCount = project == null || project.getLayouts() == null
        ? 0 : project.getLayouts().length;
log.info("QXPSM started: operation=processRequest, nameValueCount={}, modifierLayoutCount={}",
        nameValueCount, modifierLayoutCount);
QContentData result = stub.processRequest(context);
log.info("QXPSM completed: operation=processRequest, durationMs={}, nameValueCount={}, "
                + "modifierLayoutCount={}, streamBytes={}, textChars={}, multipartCount={}",
        elapsedMillis(startedNanos), nameValues == null ? 0 : nameValues.size(),
        project == null || project.getLayouts() == null ? 0 : project.getLayouts().length,
        result == null || result.getStreamValue() == null ? 0 : result.getStreamValue().length,
        result == null || result.getTextData() == null ? 0 : result.getTextData().length(),
        result == null || result.getMultipartResponse() == null
                ? 0 : result.getMultipartResponse().length);
```

```java
long startedNanos = System.nanoTime();
log.info("QXPSM started: operation=getXPressDOM");
Project result = stub.getXPressDOM(documentName);
log.info("QXPSM completed: operation=getXPressDOM, durationMs={}, layoutCount={}, contentCount={}",
        elapsedMillis(startedNanos),
        result == null || result.getLayouts() == null ? 0 : result.getLayouts().length,
        result == null || result.getContents() == null ? 0 : result.getContents().length);
return result;
```

Failures use `QXPSM failed: operation=<operation>, durationMs=<MS>, causeType=<TYPE>`. Do not log
`documentName`, `saveAsPath`, `saveAsName`, exception messages, SOAP request/response objects or modifier contents.
The client uses the same private `elapsedMillis(long)` helper shown in section 13.3.

### 13.5 Required log tests

Focused tests use Spring Boot `OutputCaptureExtension` rather than Logback classes, preserving the repository rule
that code and tests depend on SLF4J rather than a logging implementation. They assert:

- QXPS success and failure lines include method, operation types, duration and count/size metadata;
- QXPS/QXPSM lines do not contain a known query value, SQL fragment, document path, XML marker or response text;
- run-load/task/terminal lines include the expected IDs/counts and no parameter/block values;
- every mocked successful request produces exactly one start and one completion line;
- every mocked failed request produces one start and one bounded failure line, never a body/wire dump.

### 13.6 Logging level and volume

Keep these summaries at `INFO`; keep per-row/per-block detail absent. Keep full SQL/JDBC bind logging, WebClient wire
logging, Axis SOAP dumps and payload logging disabled. One line per run-load, selected task, QXPS/QXPSM call and
terminal run is bounded even for large reports; never add a line per SQL row, XML node, page box or binary chunk.

The implemented `logback-spring.xml` pins the relevant framework categories so ordinary evidence collection cannot
print the SQL stored in `QXP_TACHE`, JDBC bind values, or Axis HTTP/SOAP wire content:

```xml
<logger name="org.springframework.jdbc.core" level="WARN" />
<logger name="org.hibernate.SQL" level="OFF" />
<logger name="org.hibernate.orm.jdbc.bind" level="OFF" />
<logger name="org.apache.axis.transport.http" level="WARN" />
<logger name="org.apache.commons.httpclient" level="WARN" />
<logger name="httpclient.wire" level="OFF" />
<logger name="reactor.netty.http.client" level="WARN" />
```

`spring.jpa.show-sql` must remain `false`. The application-owned dynamic-query debug line contains only
`bindCount`; parameter names, types and values are deliberately excluded. Do not enable datasource-proxy/P6Spy,
Reactor Netty wiretap, Apache HTTP wire logging or the temporary Axis transport DEBUG setting during evidence runs.

## 14. What to bring back for analysis

For each run, bring the complete folder listed in section 3. At minimum, a run cannot be analyzed conclusively
without:

- manifest and exact Java Swagger run ID;
- `QOFF-01B` existing candidate, or `QOFF-01C` plus `QOFF-02A` and reservation output for the old-UI path;
- final `QOFF-02B=PASS` selected-run validation;
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

1. Publish four different valid unused run IDs and prove only three roots are active at once.
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
