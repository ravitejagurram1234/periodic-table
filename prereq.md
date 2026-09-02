# EOS Quark Production Readiness Prerequisites

Status: working production-readiness checklist  
Prepared: 2026-09-03  
Scope: Java backend, Java engine, Java batch, Angular UI, Oracle, RabbitMQ, QXPS/QXPSM,
networking, observability, unchanged .NET coexistence, release, rollback, and support readiness

## 1. Purpose

This is the single team-facing list of prerequisites for deploying the new EOS Quark Java services and Angular UI
while the existing .NET application remains available during the stability period.

This document is a readiness checklist, not evidence that an item is complete. Completion requires the acceptance
evidence stated for the item. Production approval is blocked by every incomplete P0 item.

The live .NET-to-Java parity work remains controlled by
`EOS_Quark_Engine_Parity_Goal_Rules_and_Master_Plan.md`. The return point is recorded in section 18 of this document.

## 2. Status And Priority Rules

| Value | Meaning |
|---|---|
| P0 | Mandatory before production or coexistence enablement |
| P1 | Mandatory for operational acceptance unless explicitly waived |
| P2 | Improvement that may follow after production stability |
| APPLIED DEV | Present and verified only in DEV; production migration remains pending |
| IMPLEMENTED | Present in source, but still requires build/deployment/runtime proof where stated |
| REPORTED | Reported by the user but not independently tied to an immutable artifact |
| PENDING | Required work or evidence is not complete |
| TO CONFIRM | The exact production value or owner is not available in the current workspace |
| BLOCKED | Production must not proceed until the stated dependency is resolved |

## 3. Executive Summary

### 3.1 Current confirmed position

| Area | Current state |
|---|---|
| Engine Wave 10E | Applied on the office system; `mvn clean install` reported successful |
| Immutable engine release identity | PENDING |
| Oracle COMPAT-01 | APPLIED DEV; production deployment pending |
| Oracle COMPAT-02 | APPLIED DEV; production deployment pending |
| Configurable three-root execution limit | PENDING; not implemented |
| Atomic duplicate-run protection | PENDING; not implemented |
| Engine diagnostic MDC | IMPLEMENTED for `runId`, `suiviId`, `taskId`, `stepIndex`, and `childRunId` |
| Physical log file per run | Not implemented; current output is console plus one ECS JSON log file |
| Logical per-run log isolation | PENDING runtime certification; `rootRunId` must be added or otherwise made explicit |
| Rabbit engine input | Implemented behind configuration and disabled for Swagger testing; broker certification pending |
| Rabbit message shape | Batch publishes scalar integer; authoritative Wave 10E listener consumes scalar integer |
| Three near-200-MiB run test | PENDING |
| XML, PDF splitting, QXPS transport parity | PENDING P0 parity corrections and evidence |
| Backend compartment creation | BLOCKED by wrong run-ID use until fixed and tested |
| Backend nullable `InsertRun` parameters | BLOCKED by `Map.of` null handling until fixed and tested |
| Angular source/build audit | BLOCKED because the Angular repository is not present in this workspace |
| .NET coexistence | PENDING; .NET must remain unchanged and be regression-tested after shared DB changes |

### 3.2 Mandatory no-go conditions

Production is NO-GO if any of the following remains unresolved:

1. The exact source commit, dependency set, container image, configuration, and database migration are not frozen.
2. The same run can be processed simultaneously by .NET and Java, by REST and Rabbit, or by multiple Java replicas.
3. More than three Java root execution trees can enter the engine, or a compartment child can consume a second root
   permit and deadlock.
4. Three representative near-200-MiB runs have not completed with safe heap, RSS, GC, temporary-storage, and QXPS
   headroom.
5. One run's application logs cannot be isolated without unrelated run events, or execution context leaks between
   concurrent runs.
6. COMPAT-01/02 are not deployed as reviewed additive changes with valid package objects and rollback source.
7. The unchanged .NET application fails run creation, translation, task association, compartment, or document
   generation after the Oracle migration.
8. XML conversion, PDF page splitting, QXPS transport, or final rendered output has an unexplained .NET/Java
   difference.
9. Required Oracle, RabbitMQ, QXPS, QXPSM, authentication, object-storage, logging, and ingress network flows are not
   open and tested from the deployed namespace.
10. Credentials remain committed, packaged, logged, or unrotated.

## 4. Master Release Checklist

| ID | Priority | Component | Prerequisite | Owner | Current status | Acceptance evidence |
|---|---|---|---|---|---|---|
| REL-01 | P0 | All | Confirm authoritative repository and release branch for backend, engine, batch, and UI | Release Manager | PENDING | Approved repository URLs and branch names |
| REL-02 | P0 | All | Freeze an immutable commit/tag for every deployed component | Development | PENDING | Commit SHAs and protected tags |
| REL-03 | P0 | All | Build every artifact only from the recorded commit | CI/CD | PENDING | Jenkins build URL mapped to commit SHA |
| REL-04 | P0 | All | Record artifact and container-image SHA-256 digests | CI/CD | PENDING | Digest manifest |
| REL-05 | P0 | All | Produce a software bill of materials and vulnerability scan | Security/CI | PENDING | Approved SBOM and scan report |
| REL-06 | P0 | All | Externalize and rotate every Oracle, Rabbit, S3, OAuth, monitoring, and certificate secret | Security/Platform | PENDING | Secret-store references and rotation evidence; no plaintext values |
| REL-07 | P0 | All | Confirm Java runtime and base-image support level | Architecture/Platform | PENDING | Approved JDK/base image and runtime report |
| REL-08 | P0 | All | Define DEV, UAT, PROD configuration ownership without changing the current parity-work rule of one main engine YAML | Release Manager | TO CONFIRM | Approved deployment configuration map |
| REL-09 | P0 | All | Validate health, readiness, liveness, startup, and graceful-shutdown behavior | Platform/SRE | PENDING | Probe and termination test evidence |
| REL-10 | P0 | All | Prepare and rehearse component and database rollback | Release Manager/DBA | PENDING | Timed rollback rehearsal |
| REL-11 | P1 | All | Create operational dashboards and alerts | SRE | PENDING | Dashboard links and alert tests |
| REL-12 | P1 | All | Define support ownership, on-call contacts, and incident escalation | Operations | PENDING | Approved runbook/contact list |

## 5. Oracle And Database Prerequisites

### 5.1 Required package migration

| ID | Priority | Object | Production action | Current status | Acceptance evidence |
|---|---|---|---|---|---|
| DB-01 | P0 | `QXP_PK_SUIVI` | Deploy COMPAT-01 additive `InsertRun` compatibility overloads | APPLIED DEV | Package and body VALID; old and new signatures visible |
| DB-02 | P0 | `QXP_PK_SUIVI` | Deploy COMPAT-01 `InsertSuiviTraduction` compatibility and corrected named call | APPLIED DEV | Both translation contracts compile and execute |
| DB-03 | P0 | `QXP_PK_SUIVI` | Deploy COMPAT-02 `InsertRunTaches` overload for `QXP_PK_COMMON.NumberArray` while retaining `TABLE_NUMBER` | APPLIED DEV | Both collection contracts visible and executable |
| DB-04 | P0 | `QXP_PK_COMMON` | Preserve and validate `NumberArray`, conversion helpers, and other required array contracts | Existing | Package and body VALID |
| DB-05 | P0 | `TABLE_NUMBER` | Preserve the SQL nested-table type required by the Java backend contract | Existing | Type exists and Java connected contract test passes |
| DB-06 | P0 | `QXP_PK_RUN` | Validate all engine routines and cursor aliases against the deployed Java DAO contract | PENDING | Connected DAO contract suite passes |
| DB-07 | P0 | `QXP_PK_DATA_STORAGE` | Validate `Insert_Data` associative-array and cleanup semantics | PENDING | Connected storage test passes |
| DB-08 | P0 | `QXP_PK_AUDIT` | Validate `InsertAuditRun` and backend audit routines | PENDING | Connected audit test passes |
| DB-09 | P0 | `QXP_PK_BATCH` | Validate reservation, planned-run, upload, and recovery contracts | PENDING | Connected batch integration test passes |
| DB-10 | P0 | `QXP_PK_CHARGEMENT` | Validate backend creation and document-maintenance routines | PENDING | Connected backend test suite passes |
| DB-11 | P0 | `QXP_PK_GP` | Validate compartment and structure routines | PENDING | Connected compartment test passes |
| DB-12 | P0 | `QXP_PK_HABILITATION` | Validate backend authorization-related routines still in use | PENDING | Connected authorization contract test passes |

Production deployment must modify only the reviewed members. Do not replace an entire package with an old source
copy because that can remove unrelated production changes. Export the current production specification and body,
apply the additive member changes, compile, compare the resulting member signatures, and retain the pre-change
source as rollback evidence.

### 5.2 Table and schema position

| ID | Priority | Requirement | Current status | Acceptance evidence |
|---|---|---|---|---|
| DB-13 | P0 | Do not deploy speculative table alterations | No general table alter approved | Signed migration inventory explicitly states `NONE` unless claim design changes it |
| DB-14 | P0 | Preserve `QXP_UTILISATEUR` during .NET/Java coexistence | Confirmed requirement | Existing table and foreign keys remain enabled |
| DB-15 | P0 | Preserve numeric `ID_CREATEUR` contracts and existing document/run foreign keys | Confirmed requirement | Unchanged .NET creation tests pass |
| DB-16 | P0 | Decide the authoritative atomic run-claim design | PENDING | Approved design and concurrent connected test |
| DB-17 | P0 | If atomic claim needs a new table/column, deploy it only through a reviewed migration with rollback | TO CONFIRM | Approved DDL, constraints, grants, cleanup, rollback, and load test |
| DB-18 | P0 | Validate sequences, triggers, constraints, synonyms, grants, and execute permissions for service identities | PENDING | Object/grant inventory and service-account smoke tests |
| DB-19 | P0 | Validate BLOB/CLOB sizes, temporary tablespace, undo, and transaction limits for large reports | PENDING | Three-run capacity evidence and DBA metrics |
| DB-20 | P0 | Set and prove pooled-session date and numeric NLS behavior | PENDING | Values captured from an actual Java pooled connection |
| DB-21 | P1 | Validate backup, restore, data retention, and purge behavior | PENDING | Restore and retention evidence |

The preferred atomic-claim design is an Oracle-authoritative conditional transition that grants one execution owner
for a run. A process-local guard alone is insufficient across replicas, restarts, and .NET/Java coexistence. If the
existing tables cannot safely represent ownership and fencing, a dedicated claim object may be required; that is a
design decision, not a currently approved table alteration.

## 6. Java Engine Prerequisites

| ID | Priority | Requirement | Current status | Acceptance evidence |
|---|---|---|---|---|
| ENG-01 | P0 | Freeze the exact Wave 10E source used by the successful office build | PENDING | Tag or complete checksum manifest |
| ENG-02 | P0 | Correct Jenkins application/workspace identity before deployment | Current Jenkins values require review | Dry-run targets the engine application, not backend/batch |
| ENG-03 | P0 | Keep one main `application.yaml` until deployment separation is explicitly approved | Confirmed requirement | Source and packaged-resource inspection |
| ENG-04 | P0 | Add `engine.execution.max-concurrent-run-trees` with production default `3` | PENDING | Effective configuration reports `3` |
| ENG-05 | P0 | Implement one fair root-run limiter shared by REST and Rabbit | PENDING | Combined-entry concurrency test never exceeds three roots |
| ENG-06 | P0 | Make compartment children inherit the parent root permit | PENDING | Limit-one compartment test completes without deadlock |
| ENG-07 | P0 | Add same-run process-local single-flight protection | PENDING | Concurrent duplicate invokes lifecycle once |
| ENG-08 | P0 | Integrate the Oracle atomic claim before any state-changing lifecycle work | PENDING | Multi-thread/multi-replica duplicate test has one owner |
| ENG-09 | P0 | Keep one engine replica until distributed admission with fencing is proved | Current deployment indicates one replica | Deployment manifest plus runtime replica count |
| ENG-10 | P0 | Reject or backlog excess work predictably | PENDING | REST returns approved response; Rabbit leaves work safely queued |
| ENG-11 | P0 | Align Rabbit listener concurrency and prefetch with the shared limit | PENDING | Consumer and engine metrics remain within three |
| ENG-12 | P0 | Preserve a separate `RunExecutionContext` and `R_<rootRunId>` workspace per root | Implemented design; not certified concurrently | Three-run workspace isolation test |
| ENG-13 | P0 | Detect recursive and cross-root compartment dependency cycles | PENDING | Synthetic cycle tests terminate without deadlock |
| ENG-14 | P0 | Use the approved 200-MiB source-document threshold | Required target; checked source copies are inconsistent | Effective runtime property and boundary tests |
| ENG-15 | P0 | Retain the approved 500-MiB single QXPS response cap unless changed by capacity review | Configured | Boundary test and effective property evidence |
| ENG-16 | P0 | Complete XML malformed/unusual-value parity | PENDING | Direct .NET contract tests and golden outputs |
| ENG-17 | P0 | Complete PDF page-selection, rotation, and splitting parity | PENDING | Golden intermediate/final PDF tests |
| ENG-18 | P0 | Complete QXPS HTTP transport parity, including HTTP version and request ordering | PENDING | Wire-level comparison |
| ENG-19 | P0 | Complete every required simple, mixed, dynamic, document, previous-QXP, and compartment scenario | PENDING | Full certification matrix |
| ENG-20 | P0 | Perform three concurrent representative near-200-MiB runs | PENDING | Heap, RSS, GC, duration, temporary files, QXPS and restart evidence |
| ENG-21 | P0 | Size Hikari pool, JVM heap, container memory, CPU, ephemeral storage, and timeouts from measured load | PENDING | Approved capacity report and manifests |
| ENG-22 | P0 | Verify deterministic QXPS file cleanup after success, failure, timeout, and restart | PENDING | Pool inspection before/after tests |
| ENG-23 | P1 | Expose admission, active-root, rejected-root, duration, memory, QXPS, and failure metrics | PENDING | Dashboard and alert tests |

### 6.1 Three-root acceptance contract

1. Three different root runs may execute concurrently.
2. A fourth REST request receives the approved bounded response, normally HTTP 429, or waits only if a reviewed
   deadlock-safe scheduler is implemented.
3. A fourth Rabbit run remains safely broker-backed rather than occupying an uncontrolled application thread.
4. REST and Rabbit consume the same capacity budget.
5. A compartment child stays inside its parent's root permit.
6. The same run ID is never executed twice concurrently.
7. Every permit is released after success, controlled failure, unexpected exception, cancellation, and shutdown.
8. One-JVM configuration is not called a global limit when multiple replicas are running.
9. The combined migration-era capacity of Java and .NET against QXPS/QXPSM is separately approved. Java's limit of
   three does not constrain .NET workers.

## 7. Per-Run Logging And Observability

### 7.1 Required design

The production recommendation is logical per-run separation in the central ECS logging platform, backed by the
durable per-run Oracle trace. A physical file per run is not required when operations can reliably filter and export
one run using structured fields. Physical `SiftingAppender` files should be introduced only if operations explicitly
require them and persistent storage, file-handle limits, rotation, and cleanup have been approved.

| ID | Priority | Requirement | Current status | Acceptance evidence |
|---|---|---|---|---|
| LOG-01 | P0 | Include structured `rootRunId` and current run/child/task/step identifiers on every relevant event | `rootRunId` not explicit in current pattern | ECS field inspection |
| LOG-02 | P0 | Establish MDC at REST and Rabbit entry and restore it in `finally`/scoped close | Partially implemented | Success/failure tests show empty MDC afterward |
| LOG-03 | P0 | Propagate context safely to any executor, async callback, or child thread | PENDING audit | Async/concurrency tests |
| LOG-04 | P0 | Keep child run identity distinct while retaining parent root identity | PENDING certification | Compartment log sequence |
| LOG-05 | P0 | Preserve bounded chronological `QXP_RUN.LOG_TRACE` for each run | Implemented design; runtime proof pending | Oracle post-run trace |
| LOG-06 | P0 | Prevent cross-run contamination under three concurrent runs | PENDING | Three independently filtered log bundles |
| LOG-07 | P0 | Never log SQL text, binds, row maps, block values, XML, modifiers, HTTP/SOAP bodies, BLOBs, document content, tokens, or secrets | Policy implemented; audit pending | Automated scan and runtime log review |
| LOG-08 | P0 | Bound stack traces, repeated anomalies, event sizes, and final persisted trace | Implemented design; runtime proof pending | Failure and truncation tests |
| LOG-09 | P0 | Configure log retention, rotation, index lifecycle, access, and PII handling | PENDING | Operations approval |
| LOG-10 | P0 | Alert on duplicate claim rejection, capacity rejection, QXPS timeout, Oracle persistence failure, Rabbit rejection, and terminal-status failure | PENDING | Alert injection tests |
| LOG-11 | P1 | Provide a standard run-ID query/export procedure for support | PENDING | One-command or dashboard export demonstration |
| LOG-12 | P1 | If physical per-run files are mandatory, implement and load-test `SiftingAppender` with persistent storage | Conditional | Rotation, cleanup, restart, and file-count evidence |

Current `logback-spring.xml` writes to console and one ECS JSON file. This is acceptable only after structured-field
isolation is proved. Merely including a run ID inside message text is not sufficient.

## 8. Java Batch And RabbitMQ Prerequisites

| ID | Priority | Requirement | Current status | Acceptance evidence |
|---|---|---|---|---|
| BAT-01 | P0 | Freeze the exact batch repository, branch, artifact, and image | PENDING | Commit and image digest |
| BAT-02 | P0 | Ensure only one scheduler instance reserves/publishes a given run | PENDING | Multi-replica scheduler test or enforced replica count one |
| BAT-03 | P0 | Make Oracle reservation and Rabbit publication recoverable as one operational workflow | PENDING | Broker-failure recovery test |
| BAT-04 | P0 | Add publisher confirms and returned-message handling | PENDING | Positive and negative publish evidence |
| BAT-05 | P0 | Review startup recovery before production | Current code resets/reinitiates pending runs | Active work is not reset or duplicated during rolling restart |
| BAT-06 | P0 | Do not silently leave a status-5 run unpublished | PENDING | Reconciliation job/test identifies and republishes safely |
| BAT-07 | P0 | Configure scheduler timezone and daylight-saving behavior | Europe/Paris configured in source | DST boundary tests |
| BAT-08 | P0 | Confirm queue, exchange/default exchange, routing, durability, permissions, and vhost | PENDING | Broker configuration export |
| BAT-09 | P0 | Use separate .NET and Java routes during coexistence | PENDING | Routing diagram and end-to-end tests |
| BAT-10 | P0 | Prove scalar integer run-ID serialization from batch to engine | Source contracts align; broker proof pending | Real Rabbit publish/consume test |
| BAT-11 | P0 | Configure acknowledgement, rejection, no-requeue, dead-lettering, and malformed-message policy | Partially configured | Redelivery and DLQ tests |
| BAT-12 | P0 | Align engine listener concurrency/prefetch with root limit three | PENDING | Runtime broker/engine metrics |
| BAT-13 | P0 | Classify stale messages before enabling Java Rabbit input | PENDING | Queue inventory and approved purge/re-route decision |
| BAT-14 | P0 | Keep `engine.input.rabbit.enabled=false` during Swagger evidence work | Confirmed requirement | Effective runtime configuration |
| BAT-15 | P0 | Enable Rabbit only after duplicate, concurrency, capacity, DLQ, and coexistence gates pass | PENDING | Signed gate approval |
| BAT-16 | P0 | Confirm whether Redis is actually required and configure its production endpoint securely | Dependency exists; endpoint not identified | Architecture decision and connectivity test |
| BAT-17 | P0 | Confirm object-storage requirement, bucket policy, encryption, lifecycle, and credentials | Config exists | Production object-storage test |
| BAT-18 | P1 | Remove unused Redis, QXPSM, mail, or other dependencies/configuration when not part of the production flow | TO CONFIRM | Dependency/configuration review |

## 9. Java Backend Prerequisites

The current workspace contains multiple backend copies. The exact deployable repository and tag must be confirmed
before these findings are closed.

| ID | Priority | Requirement | Current status | Acceptance evidence |
|---|---|---|---|---|
| BE-01 | P0 | Freeze the authoritative backend repository and branch | BLOCKED/TO CONFIRM | Approved repo and commit SHA |
| BE-02 | P0 | Replace nullable `Map.of` parameter construction in `SimpleJDBCTDBInsertRun` | Defect confirmed | Null date, creator, and source connected tests pass |
| BE-03 | P0 | Pass created `idRun`, not `effectiveSuiviId`, to `InsertRunTaches` for compartment runs | Defect confirmed | Created run owns expected task associations |
| BE-04 | P0 | Add the created `idRun`, not suivi ID, to the returned/audited compartment run list | Defect confirmed | UI response and audit contain real run IDs |
| BE-05 | P0 | Prove `Long[]`/Oracle ARRAY binding against `TABLE_NUMBER` | PENDING | Connected Oracle test |
| BE-06 | P0 | Move H2 to test scope and remove archetype/demo database behavior | PENDING | Production dependency tree has no compile/runtime H2 |
| BE-07 | P0 | Replace obsolete `ojdbc6` with the approved driver compatible with the selected Java runtime and Oracle version | PENDING | Dependency/security review and connected tests |
| BE-08 | P0 | Disable placeholder Liquibase execution unless a reviewed backend migration is supplied | Current config enables Liquibase in reviewed candidate | Production startup cannot execute demo DDL |
| BE-09 | P0 | Decide and standardize the supported backend Java version | Reviewed copies differ | CI, container, and runtime report agree |
| BE-10 | P0 | Validate every `QXP_PK_SUIVI`, `QXP_PK_CHARGEMENT`, `QXP_PK_GP`, `QXP_PK_AUDIT`, and `QXP_PK_HABILITATION` call | PENDING | Connected package-contract suite |
| BE-11 | P0 | Use SGIAM/SG Connect for new user identity while retaining legacy `QXP_UTILISATEUR` compatibility | Confirmed transition requirement | New-user and unchanged .NET tests |
| BE-12 | P0 | Validate production CORS, scopes, authorization, upload limits, and error handling | PENDING | Security and browser integration tests |
| BE-13 | P1 | Replace unsafe raw exception messages returned to users/logs with bounded safe errors | PENDING audit | Security/error-path tests |

## 10. Angular UI And SGIAM Prerequisites

The Angular source is not present in the current workspace. The items below are mandatory, but their current source
status cannot be verified yet.

| ID | Priority | Requirement | Current status | Acceptance evidence |
|---|---|---|---|---|
| UI-01 | P0 | Provide and freeze the authoritative Angular repository, branch, lockfile, and build tool versions | BLOCKED | Repo, commit, Node/npm versions, immutable lockfile |
| UI-02 | P0 | Configure production backend URL and HTTPS-only access | TO CONFIRM | Production browser network trace |
| UI-03 | P0 | Register production SG Connect client, redirect URIs, logout URIs, scopes, and subscriptions | TO CONFIRM | IAM registration and login/logout tests |
| UI-04 | P0 | Align backend CORS allowlist with only approved production origins | TO CONFIRM | Allowed and rejected origin tests |
| UI-05 | P0 | Validate SGIAM user identity, roles, permissions, and audit attribution | TO CONFIRM | Role matrix tests |
| UI-06 | P0 | Validate all run-creation modes against the Java backend and shared Oracle packages | PENDING | Simple, dynamic, document, translation, and compartment UI tests |
| UI-07 | P0 | Verify file-upload size, timeout, progress, cancellation, and error behavior | PENDING | Boundary and failure tests |
| UI-08 | P0 | Configure CSP, HSTS, secure cookies, frame policy, content types, and cache headers | PENDING | Security-header scan |
| UI-09 | P0 | Disable public production Swagger or restrict it to approved support users | PENDING | Access-control test |
| UI-10 | P1 | Disable or secure production source maps | PENDING | Deployed asset inspection |
| UI-11 | P1 | Implement versioned assets/cache busting and UI rollback | PENDING | Upgrade/rollback browser test |
| UI-12 | P1 | Complete accessibility and supported-browser testing | PENDING | Test report |

## 11. Network And Firewall Matrix

### 11.1 Network-rule standard

Every production network request must specify the exact source namespace/workload, destination FQDN/IP, direction,
protocol, port, TLS requirement, environment, owner, and expiry/review rule. Do not request broad `any-to-any` access.

A port is considered ready only when all of these pass from the deployed workload or build agent that will use it:

1. DNS resolution;
2. TCP connection;
3. TLS handshake and trust-chain validation where applicable;
4. authentication;
5. one safe application-level operation;
6. timeout/failure behavior;
7. evidence retained with date, source pod, destination, and result.

### 11.2 Required and conditional flows

| ID | Priority | Source | Destination | Protocol/port | Purpose | Requirement/status | Acceptance test |
|---|---|---|---|---|---|---|---|
| NET-01 | P0 | Java engine pods | Oracle PROD listener | TCP `1522` currently configured | Run load, status, documents, storage, audit | PROD FQDN/service TO CONFIRM | Connect as engine service account and execute safe package smoke |
| NET-02 | P0 | Java backend pods | Oracle PROD listener | TCP `1522` currently configured | UI data and run creation | PROD FQDN/service TO CONFIRM | Connected backend contract test |
| NET-03 | P0 | Java batch pods | Oracle PROD listener | TCP `1522` currently configured | Reservation, upload, recovery | PROD FQDN/service TO CONFIRM | Connected batch contract test |
| NET-04 | P0 | Java engine pods | RabbitMQ PROD | AMQPS TCP `5671` | Consume run IDs | PROD broker/vhost TO CONFIRM | TLS plus controlled consume test |
| NET-05 | P0 | Java batch pods | RabbitMQ PROD | AMQPS TCP `5671` | Publish run IDs | PROD broker/vhost TO CONFIRM | Publisher-confirm and consume test |
| NET-06 | P0 | Java engine pods | QXPS Windows server(s) | HTTP TCP `8080` currently configured | Add/fetch/delete/XML/render/literal operations | PROD host/pool TO CONFIRM | Controlled add, fetch, render, delete sequence |
| NET-07 | P0 | Java engine pods | PDF/save-as Windows service | HTTP TCP `8080` currently configured | PDF conversion | PROD host TO CONFIRM | Controlled conversion with checksum |
| NET-08 | P0 | Java engine pods | QXPSM Windows server(s) | SOAP/HTTP TCP `8090` currently configured | Modifier operations | PROD host TO CONFIRM | Safe SOAP operation and timeout test |
| NET-09 | P0 | Java batch pods | QXPS Windows server | HTTP TCP `8080` where batch feature is retained | Upload/document diagnostics | Feature TO CONFIRM | Feature-level test or approved removal |
| NET-10 | P0 conditional | Java batch pods | QXPSM Windows server | TCP `8090` | Disabled batch integration | Do not open unless enabled | Approved enablement plus SOAP test |
| NET-11 | P0 | Java batch pods | Object storage/S3 | HTTPS TCP `443` | Upload/migration storage | PROD endpoint/bucket TO CONFIRM | Put/get/delete test with service identity |
| NET-12 | P0 | User browsers | Angular ingress/VIP | HTTPS TCP `443` | UI access | PROD DNS/certificate TO CONFIRM | Browser TLS and login test |
| NET-13 | P0 | User browsers/Angular | Backend ingress/VIP | HTTPS TCP `443` | REST API | PROD DNS/certificate TO CONFIRM | Authenticated API browser test |
| NET-14 | P0 | Ingress and platform probes | Backend, engine, batch services | Internal TCP `8080` by current default | Application and health traffic | TLS termination design TO CONFIRM | Readiness/liveness and API test |
| NET-15 | P0 | Backend/UI/service workloads | SG Connect/SGIAM | HTTPS TCP `443` | Login, token, user information | PROD endpoints/client TO CONFIRM | Token and userinfo tests |
| NET-16 | P0 | Java workloads | Monitoring/logging platform | HTTPS TCP `443` or platform-defined port | ECS logs, metrics, traces | Exact destination TO CONFIRM | Log/metric/trace arrival test |
| NET-17 | P0 | Jenkins/build agents | Git server | HTTPS TCP `443` | Source checkout | Existing/platform rule TO CONFIRM | Checkout exact commit |
| NET-18 | P0 | Jenkins/build agents | Maven/Node artifact repositories | HTTPS TCP `443` | Dependency resolution | Existing/platform rule TO CONFIRM | Offline-repeatable dependency build |
| NET-19 | P0 | Jenkins/build agents | Container registry | HTTPS TCP `443` | Image push/pull | Existing/platform rule TO CONFIRM | Push, scan, pull by digest |
| NET-20 | P0 | Jenkins/deployment agents | Kubernetes/deployment API | Platform-defined, commonly TCP `443`/`6443` | Deployment | Exact managed-platform value TO CONFIRM | Authenticated dry-run/deploy |
| NET-21 | P0 conditional | Java batch pods | Redis | Exact port TO CONFIRM | Redis dependency if retained | Usage undecided; do not assume `6379`/`6380` | Connected health/functional test or remove dependency |
| NET-22 | P0 conditional | Java/backend/batch | SMTP relay | Exact port TO CONFIRM | Email if retained | Usage/configuration TO CONFIRM | Controlled email test or remove feature |
| NET-23 | P0 conditional | Java/QXPS workloads | Windows file share | SMB TCP `445` only if architecture uses SMB | Shared QXP files | Do not open for the QXPS server's local `D:\Documents` path | Mount/read/write/cleanup test |
| NET-24 | P0 | All pods | Cluster DNS | UDP/TCP `53` through platform DNS | Resolve Oracle, Rabbit, Windows, IAM, storage | Platform rule required | Resolve every production FQDN from each namespace |
| NET-25 | P1 | Operations/support | Service/logging/admin endpoints | HTTPS TCP `443` | Support diagnosis | Approved restricted sources only | Role-based access test |

### 11.3 Windows QXPS/QXPSM server readiness

| ID | Priority | Requirement | Current status | Acceptance evidence |
|---|---|---|---|---|
| WIN-01 | P0 | Confirm production QXPS and QXPSM server FQDNs/IPs | TO CONFIRM | Approved inventory |
| WIN-02 | P0 | Open engine-to-QXPS TCP 8080 and engine-to-QXPSM TCP 8090 in both host firewall and network path | PENDING | Tests from production namespace |
| WIN-03 | P0 | Confirm Windows service accounts, service startup, recovery, and patch level | TO CONFIRM | Service configuration/export |
| WIN-04 | P0 | Confirm QXPS/QXPSM versions match the certified .NET environment | TO CONFIRM | Version evidence |
| WIN-05 | P0 | Confirm fonts, extensions, profiles, assets, licenses, and render settings are identical | TO CONFIRM | Environment checksum/inventory |
| WIN-06 | P0 | Confirm working pool path, permissions, free space, quotas, antivirus exclusions, and cleanup | TO CONFIRM | Three-run and failure cleanup tests |
| WIN-07 | P0 | Confirm maximum parallel sessions/jobs for Java plus .NET coexistence | TO CONFIRM | Vendor/server capacity test |
| WIN-08 | P0 | Monitor service availability, queue depth, disk, memory, CPU, job duration, failures, and license state | PENDING | Dashboard and alert tests |
| WIN-09 | P0 | Define QXPS/QXPSM restart/failover procedure without duplicate document generation | PENDING | Recovery rehearsal |

## 12. Unchanged .NET Coexistence Prerequisites

The .NET source must not be modified for this migration unless the user separately approves a .NET change. Shared
Oracle packages and routing must remain backward compatible.

| ID | Priority | Requirement | Current status | Acceptance evidence |
|---|---|---|---|---|
| NETCO-01 | P0 | Keep .NET binaries and configuration unchanged while validating shared changes | Confirmed requirement | Deployment checksum comparison |
| NETCO-02 | P0 | Retain `QXP_UTILISATEUR` and existing creator/document foreign-key contracts | Confirmed requirement | .NET connected tests |
| NETCO-03 | P0 | Validate .NET `InsertRun` after COMPAT-01 | Passed in DEV flow; PROD pending | Normal old-UI source-1 run creation |
| NETCO-04 | P0 | Validate .NET `InsertRunTaches` associative array after COMPAT-02 | Passed in DEV flow; PROD pending | Correct task associations |
| NETCO-05 | P0 | Validate both `InsertSuiviTraduction` overload paths | PENDING full scenario | Translation run and audit evidence |
| NETCO-06 | P0 | Route each run to exactly one engine | PENDING | Queue/routing evidence and duplicate protection |
| NETCO-07 | P0 | Keep separate Java and .NET queues or an equivalently strong dispatcher rule | PENDING | Architecture and broker configuration |
| NETCO-08 | P0 | Provide a tested switch that routes all new work back to .NET | PENDING | Rollback rehearsal |
| NETCO-09 | P0 | Define the combined Java plus .NET concurrency limit against Oracle and QXPS/QXPSM | PENDING | Capacity approval |
| NETCO-10 | P0 | Compare Oracle statuses, errors, audit, storage, documents, and trace for equivalent runs | PENDING | Scenario evidence dossier |
| NETCO-11 | P0 | Compare QXP/PDF/DOC outputs, page counts, geometry, text, images, pagination, rotation, and pixels | PENDING | Zero unexplained difference report |
| NETCO-12 | P0 | Keep .NET available for the agreed Java stability period | TO CONFIRM | Approved coexistence duration and exit criteria |

## 13. Required Functional And Coexistence Test Matrix

| ID | Priority | Scenario | .NET | Java | Coexistence/acceptance requirement |
|---|---|---|---|---|---|
| TEST-01 | P0 | Source 1 simple SQL/value update with non-zero updates | Required | Required | Same business values and rendered output |
| TEST-02 | P0 | Source 1 mixed value update and structural modification | Required | Required | Same modifier sequence and output |
| TEST-03 | P0 | Dynamic report with returned rows and non-zero modifications | Required | Required | Same geometry, breaks, pagination, and output |
| TEST-04 | P0 | Dynamic overflow/reprocessing | Required where configured | Required | Same second-pass decisions and output |
| TEST-05 | P0 | DOC EOS/PDF task, page selection, range, and rotated pages | Required | Required | Golden intermediate and final PDFs |
| TEST-06 | P0 | Source 3 previous-certified-QXP | Required | Required | Same previous document and final output |
| TEST-07 | P0 | Source 2 uploaded QXP | Required | Required | Same input bytes and output |
| TEST-08 | P0 | Source 4 suivi/document source | Required | Required | Same source selection and output |
| TEST-09 | P0 | Compartment mode 1 generated children | Required | Required | Child IDs, order, incorporation, and parent output match |
| TEST-10 | P0 | Compartment mode 2 previous-document reuse | Required | Required | Same reused bytes and incorporation |
| TEST-11 | P0 | Translation run creation | Required | Backend/shared package required | Both legacy/new identity paths work |
| TEST-12 | P0 | Zero-row SQL and configured fail-soft branches | Required | Required | Same continuation/error behavior |
| TEST-13 | P0 | Malformed/unusual XML values | Required | Required | Same conversion or controlled error |
| TEST-14 | P0 | QXPS timeout/unavailable | Required | Required | Same run outcome, cleanup, and bounded logs |
| TEST-15 | P0 | End persistence first-attempt failure | Characterize | Required | Safe retry and final persisted state |
| TEST-16 | P0 | Duplicate same run through REST/Rabbit/replica | Protection target | Required | One lifecycle owner only |
| TEST-17 | P0 | Three different Java roots concurrently | N/A | Required | Maximum active roots equals three |
| TEST-18 | P0 | Fourth Java root | N/A | Required | Safe HTTP rejection or broker backlog |
| TEST-19 | P0 | Three near-200-MiB Java roots | N/A | Required | Safe memory/performance headroom |
| TEST-20 | P0 | Simultaneous distinct .NET and Java runs | Required | Required | No shared DB/workspace/QXPS corruption |
| TEST-21 | P0 | Rolling restart/startup recovery | Required coexistence | Required | No reset of active work and no duplicate publish |
| TEST-22 | P0 | Rollback to .NET-only routing | Required | Disable Java route | New work continues without manual DB repair |

Equivalent input proof is mandatory. A generated PDF existing in both systems is not sufficient. Final acceptance
requires document-level, structural, visual, and Oracle-side comparison.

## 14. Security And Configuration Prerequisites

| ID | Priority | Requirement | Current status | Acceptance evidence |
|---|---|---|---|---|
| SEC-01 | P0 | Remove usable secrets from Git history/current source and packaged resources | PENDING | Secret scan reports no active credentials |
| SEC-02 | P0 | Rotate every credential that was committed, even if later deleted | PENDING | Rotation timestamps and owners |
| SEC-03 | P0 | Use separate least-privilege production identities for backend, engine, batch, broker, object storage, and monitoring | TO CONFIRM | Access matrix and tests |
| SEC-04 | P0 | Configure certificate stores, trust chains, hostname verification, renewal, and expiry alerts | PENDING | TLS tests and expiry dashboard |
| SEC-05 | P0 | Restrict Oracle grants to required objects/actions | PENDING | Grant review |
| SEC-06 | P0 | Restrict Rabbit permissions to required vhost/queues/exchanges | PENDING | Broker permission export |
| SEC-07 | P0 | Disable SQL display and payload-bearing debug/wire logs in every environment | Partially implemented | Source/config scan and runtime test |
| SEC-08 | P0 | Restrict actuator, diagnostics, Swagger, and administrative endpoints | PENDING | Unauthorized/authorized tests |
| SEC-09 | P0 | Validate dependency licenses and known vulnerabilities | PENDING | Approved scan |
| SEC-10 | P1 | Define personal-data handling and log/audit retention | PENDING | Security/compliance approval |

## 15. Capacity, Reliability, And Operations

| ID | Priority | Requirement | Current status | Acceptance evidence |
|---|---|---|---|---|
| OPS-01 | P0 | Size engine memory from three-run measurements, not current defaults | PENDING | Capacity report with headroom |
| OPS-02 | P0 | Validate Oracle connection-pool capacity for all services and coexistence | PENDING | Pool and DB-session metrics |
| OPS-03 | P0 | Validate QXPS/QXPSM timeout budgets against long reports | PENDING | Long-run timing evidence |
| OPS-04 | P0 | Validate pod termination grace period exceeds safe checkpoint/cleanup needs | PENDING | Controlled termination test |
| OPS-05 | P0 | Define stuck-run detection and explicit status-4 recovery | PENDING | Runbook and rehearsal |
| OPS-06 | P0 | Define dead-letter replay and duplicate-safe operational procedure | PENDING | Runbook and replay test |
| OPS-07 | P0 | Monitor queue depth, active roots, rejected roots, Oracle pool, JVM, QXPS, document sizes, and run duration | PENDING | Dashboards |
| OPS-08 | P0 | Alert on no-progress, repeated terminal errors, storage pressure, QXPS failure, and package invalidation | PENDING | Alert tests |
| OPS-09 | P1 | Define log, audit, generated-document, temporary-file, and queue retention | PENDING | Retention matrix |
| OPS-10 | P1 | Define production support evidence bundle for one run | PENDING | Sample support bundle |

## 16. Recommended Deployment Sequence

1. Freeze backend, engine, batch, UI, Oracle migration, and deployment configuration identities.
2. Fix and certify backend run creation, compartment run-ID handling, dependencies, and Liquibase behavior.
3. Complete engine XML, PDF, QXPS transport, duplicate claim, three-root admission, context isolation, and logging work.
4. Complete the full .NET/Java parity campaign before Rabbit production enablement.
5. Apply the reviewed additive Oracle package changes in a production-like environment.
6. Run unchanged .NET regression tests against those shared packages.
7. Validate every required network flow from the actual deployment namespaces.
8. Validate QXPS/QXPSM Windows configuration, fonts, assets, licenses, pool, and combined capacity.
9. Run three near-200-MiB Java roots and the approved coexistence load.
10. Deploy backend and UI with production SGIAM/SG Connect configuration.
11. Deploy batch with scheduler singleton, publish confirmation, reconciliation, and recovery protections.
12. Enable Java Rabbit consumption only after stale-queue review and one-engine-per-run routing are approved.
13. Start with a controlled canary set of Java runs while .NET remains the rollback path.
14. Expand traffic only when Oracle, QXPS/QXPSM, logging, document parity, and operations evidence remain clean.
15. Decommission .NET only after the agreed stability period and explicit approval.

## 17. Final Go/No-Go Evidence Package

The release decision must include:

1. source commit/tag and complete artifact/image checksums;
2. dependency/SBOM/security results;
3. reviewed configuration and secret references without secret values;
4. Oracle migration member diff, object validity, grants, and rollback source;
5. network/firewall matrix with successful source-to-destination evidence;
6. QXPS/QXPSM environment and capacity evidence;
7. backend, batch, Rabbit, SGIAM, Angular, and service integration results;
8. three-root concurrency, duplicate, cycle, restart, and near-200-MiB load results;
9. per-run application logs and Oracle traces with no cross-run contamination or unsafe payloads;
10. complete .NET/Java scenario matrix with Oracle pre/post evidence;
11. intermediate and final QXP/PDF/DOC artifacts, hashes, structural comparisons, and pixel comparisons;
12. accepted differences, with the 200-MiB Java source threshold explicitly documented;
13. rollback rehearsal and .NET-only routing proof;
14. signed application, database, infrastructure, security, operations, and business approval.

## 18. Preserved Engine-Parity Return Point

This production-readiness topic does not replace or advance the live-run evidence workflow.

Current return point:

1. Keep the batch, old .NET engine consumer, and Java engine consumer stopped while creating the controlled test run.
2. Create one fresh source-1, SQL-only run through the normal old UI.
3. Run `QOFF-01F` to confirm that the UI attempt committed a new run and task association.
4. Run `QOFF-01C` to classify the new candidate.
5. Do not reserve or execute the run until the immutable Wave 10E baseline is recorded and all admission checks pass.

Known candidate state remains:

| Run | Use |
|---|---|
| `505257` | Mixed source-1 run; not accepted as the first successful diagnostic because four document tasks lack usable input mapping; preserve as a possible negative scenario |
| `505255` | Valid source-3 SQL-only fallback with previous-certified-QXP evidence; keep untouched and unreserved unless the purpose-built source-1 run cannot be created |

The authoritative detailed procedure and query definitions remain in
`EOS_Quark_Office_Live_Run_Evidence_Capture_Guide.md` and its referenced SQL file. Any future query instruction must
state its purpose, expected result, and stop condition.
