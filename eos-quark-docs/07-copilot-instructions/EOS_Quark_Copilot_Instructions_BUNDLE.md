# EOS Quark Engine — GitHub Copilot Custom Instructions (copy-paste bundle)

This single file bundles **9 instruction files** for the `quark-engine-service` repository. Copy each block
into the path shown in its heading, on your work laptop.

## Where to paste (read this first)

1. All files live under a **`.github/`** folder placed at your **repository root** — the directory that
   contains `pom.xml`, `src/`, and `Jenkinsfile` (i.e. the `quark-engine` project root). This is the exact
   layout already validated in this audit.

   ```
   <repo-root>/
   ├── pom.xml
   ├── src/
   └── .github/
       ├── copilot-instructions.md                 ← repo-wide, always loaded
       └── instructions/
           ├── domain.instructions.md
           ├── services-and-business.instructions.md
           ├── persistence.instructions.md
           ├── integration.instructions.md
           ├── api-and-messaging.instructions.md
           ├── enums.instructions.md
           ├── testing.instructions.md
           └── config-security-migrations.instructions.md
   ```

2. Create the folders first:
   - `mkdir -p .github/instructions`

3. `copilot-instructions.md` is loaded on **every** request. The `*.instructions.md` files are loaded only
   when you edit a file matching their `applyTo:` glob (the YAML frontmatter at the top of each) — that is why
   they are split by layer.

4. **Enablement (only if your IDE doesn't auto-detect them):** in VS Code settings, ensure
   `"github.copilot.chat.codeGeneration.useInstructionFiles": true`. The path-scoped `*.instructions.md` files
   are discovered automatically from `.github/instructions/`. On github.com and the CLI, repository custom
   instructions are picked up automatically once committed.

5. Commit the `.github/` folder to the repo so the whole team (and Copilot code review) gets them.

## What Copilot will know after this
- This is a **RabbitMQ-driven document-generation engine ported line-for-line from .NET** — not a CRUD REST app.
- The layering rules ArchUnit enforces, the stored-procedure/`SimpleJdbcCall` persistence model (no JPA/no
  Liquibase), hand-written mappers (no MapStruct), the strategy/business/command patterns, the QXPS/QXPSM
  integration rules, and the real Oracle date-binding / WebClient-buffer / SOAP-namespace pitfalls the team
  already fixed.

The 9 files follow. Each is shown inside a `~~~~markdown` box; copy the **inside** of the box.

---

## 📄 `.github/copilot-instructions.md`

> Create this file at: **`.github/copilot-instructions.md`** (relative to your repo root). Copy everything inside the box below (do **not** include the outer `~~~~` fence lines).

~~~~markdown
# Quark Engine Service — Copilot Instructions

## What this project is
`quark-engine-service` is a **RabbitMQ-driven document-generation batch engine**, ported
**line-for-line from a legacy .NET application** ("QXP Engine Core"). It consumes a run id, executes an
8-step pipeline (start → load → prepare → process tasks → QXPS modify → check → render → end) that builds
QuarkXPress documents, and persists results to Oracle. **It is not a CRUD REST service** — there is exactly
one REST controller (`infra/api/v1/EngineServiceController`) and one queue listener
(`listener/RunMessageListener`), and both just trigger the same `ProcessRunService.runProcessor(...)`.

Stack: Spring Boot 2.7.18, Java 11, parent `com.socgen.sgs.sgs-stack:sgs-api-core:11.0.1` (SocGen internal),
Spring Web + WebFlux (one WebClient) + Spring AMQP, Spring JDBC on **Oracle stored procedures**, Apache Axis
1.4 SOAP, Lombok, PDFBox. Build: Maven (`mvn clean install`).

## The single most important rule: .NET parity is the correctness spec
This code intentionally mirrors the .NET engine's behavior, **even where that is not idiomatic Java**.
Preserve that. Concretely:
- Keep the `// Cross-reference: .NET <Class>.<Method>` / `// Parity: .NET <file.cs:line>` / `// Finding #NN`
  comments, and add them when you port or change behavior. See `domain/Run.java`,
  `service/impl/ProcessRunServiceImpl.java` for the format.
- When behavior is ambiguous, **verify against the .NET source; do not "clean it up" or guess.** A run
  finalizing `GENERATED` despite recorded per-task errors is deliberate parity, not a bug to fix.
- French domain vocabulary is kept verbatim in code: `gabarit`, `bloc`, `compartiment`, `ligne`, `tache`,
  `maquette`, `échéance`, `modeDegrade`. Do not translate these to English.

## Architecture & the dependency rule (enforced by ArchUnit — do not break)
`CleanArchitectureLayersTest` + `WrongFrameworksTest` fail the build if you violate these:
- `domain..` must **not** depend on `service..` or `infra..`.
- `service..` must **not** depend on `infra..`.
- `domain..` and `service..` must **not** import: Jackson, `com.socgen.apibank`, Swagger, servlet,
  `org.springframework.web/http`, `java.sql`, `jakarta.persistence`, Spring `data/transaction/scheduling/
  security/validation`. They stay framework-free (only Spring `stereotype`/`beans` allowed).
- Logging is **SLF4J only** (`@Slf4j`). No log4j/logback/JUL/commons-logging imports. `@Transactional` must be
  Spring's, never `jakarta.transaction`. Use `java.time`, never Joda.

Layering & call flow:
```
listener / controller  →  service (interface + impl)  →  business (@Component, use-case step)  →  infra/dao
                                        ↓ uses
                                     domain  ←—(ports impl'd in infra)— domain/port interfaces
```
- `business/` is the **only** layer allowed to import `infra..` (ArchUnit does not cover it). It is the bridge
  from service to DAO. Reference: `business/GetRunPropertiesBusiness.java`.
- The domain is a **rich model with behavior**; ports (`domain/port/*`) are passed **into** domain methods as
  parameters, not injected as fields. Reference: `domain/Run.java#prepareGabarit`.

## Module map (where things go)
| Package | Role |
|---|---|
| `listener/` | `@RabbitListener` entry point (`RunMessageListener`) |
| `infra/api/v1/` | the single REST controller |
| `service/` + `service/impl/` | orchestration; interface in `service/`, `@Service` impl in `service/impl/` |
| `service/task/` + `service/task/impl/` | **Strategy pattern**, one strategy per task type |
| `business/` | `@Component` use-case steps (bridge to DAO) |
| `domain/` (+ `task/ bloc/ element/ modifier/ dynamic/report/ helper/ port/`) | rich domain model |
| `enums/` | legacy Oracle code ↔ enum, via `fromCode(int)` |
| `mapper/` | **hand-written** JDBC-row → domain mappers (NOT MapStruct) |
| `infra/dao/` + `infra/dao/impl/` | Oracle stored-proc access via `SimpleJdbcCall` |
| `infra/interop/qxps/` | QXPS HTTP integration (the one WebClient) |
| `infra/interop/qxpsm/` | QXPSM SOAP integration (Axis 1.4) |
| `integration/soap/generated/` | Axis `wsdl2java` output — **generated at build, never hand-edit** |
| `infra/pdf/` | PDFBox page splitting |

## Non-negotiable conventions
- **Dependency injection:** constructor injection only, via Lombok `@RequiredArgsConstructor` + `private final`
  fields. Do not use `@Autowired` on fields.
- **Persistence:** there are **no JPA entities and no Spring Data repositories**, and Liquibase is disabled.
  All DB access is `SimpleJdbcCall`/`JdbcTemplate` against `QXP_PK_*` Oracle packages. **Never generate JPA
  `@Entity`, `JpaRepository`, or Liquibase changesets** — the schema is Oracle-owned and external.
- **Mapping:** MapStruct is on the classpath but **unused**. Write mappers as `@Component` classes with
  null-safe helpers. Reference: `mapper/TaskMapper.java`.
- **Dates → Oracle:** never let Oracle infer a date format. Bind `LocalDate` as `java.sql.Date` + `Types.DATE`,
  `LocalDateTime` as `Timestamp` + `Types.TIMESTAMP`, and **dynamic-SQL date in-params as `oracle.sql.DATE`**.
  Unset numeric/date params bind as a *typed SQL NULL* (`new SqlParameterValue(Types.X, null)`), not a sentinel
  number. The Oracle session is pinned to `NLS_DATE_FORMAT='DD/MM/YYYY'`; all date literals are day-first.
  Reference: `mapper/InParamSqlMapper.java`. (See `.github/instructions/persistence.instructions.md`.)
- **Errors:** the pipeline never throws to its caller. It accumulates `domain/RunError` (severity ints
  `UNSPECIFIED=1`, `CRITIQUE=2`, `BLOQUANTE=3` — persisted, load-bearing) on the `Run` and always runs
  `End_Run`. Reference: `service/impl/ProcessRunServiceImpl.java#runProcessor`.
- **Null-handling:** **no `Optional` anywhere.** Guard with `x != null && !x.isBlank()`; return EMPTY/DEFAULT
  singletons or `Integer.MIN_VALUE` sentinels instead of null/0. `IllegalStateException` = broken invariant,
  `IllegalArgumentException` = bad input.
- **Logging:** `@Slf4j`, `{}` placeholders, throwable as the last arg. Always include the run id in the message.
  There is no MDC/correlation-id; traceability is the run id plus `run.trace(...)`.
- **Config:** externalized to `application.yaml` + per-env overlays under `src/main/config/env/{dev,uat,prod}`
  and secrets under `src/main/config/secrets/*`. Inject scalars with `@Value("${key:default}")` (always a
  default); use `@ConfigurationProperties` beans for grouped infra config (`QxpsProperties`).

## Common pitfalls (these are real bugs the team already fixed — don't reintroduce them)
- Binding a DATE in-param as `Timestamp` → `ORA-01858/01843/01830`. Bind `oracle.sql.DATE`.
- `Integer.parseInt` on legacy tokens (e.g. `"5L1"`) throws. Use a lenient `toInt` via
  `new BigDecimal(v.replace(" ","")).intValue()` returning `Integer.MIN_VALUE` on failure (mirrors .NET
  `Conversion.ToInt`). Reference: `mapper/InParamSqlMapper`, `domain/dynamic/report/DBreakRule`.
- WebClient default 256 KB buffer → `DataBufferLimitException` on multi-MB responses. Always set
  `maxInMemorySize`. Reference: `infra/interop/qxps/client/QxpsHttpClient`.
- QXPSM SOAP: the live server is namespace `http://com.quark.qxpsm`, service `RequestService`. Never reference
  the obsolete `qxpsmsdk.wsdl` / `webservice.manager.quark.com`. The `PROP_DOMULTIREFS` multi-ref hypothesis
  was disproven and reverted — do not reintroduce it.
- All three Quark endpoints (`qxps.server.url`, `qxpsm.soap.endpoint`, `qxp.thirdparty.url`) must point at the
  **same environment** or the SOAP step can't see the pooled document.

## Known inconsistencies (do NOT copy these as patterns)
- `infra/api/exception/GlobalExceptionHandler.java` is fully commented out; the controller does inline
  try/catch returning raw strings. `problem-spring-web` is a dependency but unused. Follow the controller's
  existing style; do not invent a new `@ControllerAdvice` unless asked.
- Stray/dead code exists: `business/testbusinessFile.java`, empty `domain/task/TaskBaseTest.java`. Don't imitate.
- The controller path is `ap/v1/EngineService` while the security config secures `/api/v1/**` — a real mismatch.
- Credentials are hardcoded in the committed `application.yaml`. Do not add more; put secrets in the
  `config/secrets/*` overlays.
- Log message format drifts (`Run [{}]` vs `runId: {}`) and a few RunError severities are hardcoded as `2`
  instead of `RunError.CRITIQUE`. Prefer the named constant and the `Run [{}]` form.

Layer-specific rules live in `.github/instructions/*.instructions.md` and load automatically per file path.
~~~~

---

## 📄 `.github/instructions/domain.instructions.md`

> Create this file at: **`.github/instructions/domain.instructions.md`** (relative to your repo root). Copy everything inside the box below (do **not** include the outer `~~~~` fence lines).

~~~~markdown
---
applyTo: "**/engine/domain/**/*.java"
---

# Domain layer

The domain is a **rich model with behavior**, ported from .NET. It must stay framework-free
(ArchUnit forbids `service..`/`infra..` imports and Jackson/web/sql/jpa/security/etc.).

## Class shape & Lombok
- Mutable entity/holder → `@Getter @Setter`. Reference: `domain/task/TaskBase`, `domain/bloc/BlocBase`.
- Immutable value object → `@Getter` **only**, `final` fields, an explicit constructor, **no `@Setter`**.
  Reference: `domain/InParam`, `domain/RunError`, `domain/bloc/BlocBox`.
- `@Slf4j` only on classes that actually log (`domain/Run`, `domain/xml/QxpXml`) — never on pure data classes.
- Use Lombok `@Builder` if you need a builder (only `domain/DocumentDomain` has one). **Do not hand-roll
  builders** — the hand-written builder in `DocumentIdentity` is the anti-pattern to avoid.
- To customize a single accessor, use `@Getter(AccessLevel.NONE)` + a hand-written lazy getter that returns an
  EMPTY singleton. Reference: `DocumentDomain.getQxpXml()`.

## Behavior & ports
- When a domain method needs I/O, **pass the port (`domain/port/*`) in as a method parameter**, do not hold it
  as a field. Reference: `Run.prepareGabarit(GetGabaritBusiness, GetGabaritXmlBusiness, FilePoolPort,
  DocumentIdentityPort)`. (The one exception is `TaskDynamique.filePoolService` — don't generalize it.)
- Ports are interfaces implemented in `infra`; they may have `default` methods (`DynamicQueryPort.existColumn`).

## Task hierarchy
- `TaskBase` is abstract with abstract `prepare()`; overridable hooks default to false/no-op
  (`isModeDegrade`, `isDirectCall`, `evaluateInfo`, `resetProcess`). Subclass constructors are always
  `TaskX(int id, Run run) { super(id, run); }`.
- Dispatch on concrete type with `instanceof` (reference: `domain/modifier/QxpsModifier.add`). New task types
  add a `TaskBase` subclass **and** a matching strategy in `service/task/impl/` and a `createTaskByType` branch
  in `mapper/TaskMapper`.

## Collections
- Insertion-order-significant maps → `private final LinkedHashMap<>` initialized inline
  (`TaskBase.blocsModify`, `Run.tasks`). Order-irrelevant → `HashMap` (`DBreakRules.rules`). Lists →
  `final ArrayList<>`. Collection fields are never reassigned.

## Null-handling
- **No `Optional`.** Guard with `x != null && !x.isBlank()`.
- Return EMPTY/DEFAULT singletons or `Integer.MIN_VALUE` sentinels rather than null/0. Reference:
  `QxpXml.EMPTY`, `DMasterPage.DEFAULT`, `QxpXml.parseIntSafe`.
- `IllegalStateException` = broken invariant (`Run.prepareGabarit` when runProperties null);
  `IllegalArgumentException` = bad input/unknown enum.

## RunError (error model)
- Immutable; severity is an int constant: `UNSPECIFIED = 1`, `CRITIQUE = 2`, `BLOQUANTE = 3`. These values are
  persisted to Oracle and are load-bearing — use the named constants, never the literals.
- Non-fatal audit idiom: `run.getErrors().add(new RunError(RunError.UNSPECIFIED, "<French message>"))`.

## Enums referenced from domain
See `.github/instructions/enums.instructions.md`. In short: `private final int code` + `fromCode(int)` that
loops `values()` and returns a sentinel (`UNKNOWN`/`NONE`/`UNSPECIFIED`) on a miss — **never throws, never
returns null** (only `RunStatus.fromCode` throws). `[Flags]` enums keep the raw int and expose static
`hasFlag(int, flag)` bit-tests (`domain/StoreDataType`).

## .NET parity comments (mandatory)
Every non-trivial class/method carries `Cross-reference: .NET <Class>.<Member>` (or `QXP.Engine.Core.<Class>`);
behavioral deviations use `Parity: .NET <file.cs:line>`; remediation items are tagged `Finding #NN`. Keep and
extend these. Reference: `domain/Run`, `domain/helper/DataTypeHelper`.

## Naming
- Keep French terms verbatim (`gabarit`, `bloc`, `compartiment`, `ligne`, `maquette`, `échéance`).
- Prefix families: `D…` (dynamic report model), `T…` (template elements), `Modifier…`, `Bloc…`, `Task…`,
  `Run…`, `Qxp…`. Suffixes: `…Base` (abstract), `…Info` (geometry holder), `…Port` (port interface),
  `…Helper` (`final` class, private ctor, all-static), `…Domain` (name-clash disambiguation, e.g.
  `DocumentDomain`).

## Don't do this (real anti-patterns in the tree)
- Don't fully-qualify `java.util.*` inline when an import exists (seen in `Run`).
- Don't leave stray comments (`RunProperties:18` has `/*sup bro*/`) or dead blocks (`RunTaskStep`
  `localPrepareStep`).
- Don't drop fields in `clone`/`cloneInfo` methods (`DRowInfo.cloneInfo` omits width/column — a bug).
- Don't add yet another empty-string sentinel; the tree already mixes `" "`, `"aucun"`, `""` — reuse the
  existing one for the type you're touching.
- Don't dodge circular dependencies with reflection (`TGroup.evaluate` does — avoid).
~~~~

---

## 📄 `.github/instructions/services-and-business.instructions.md`

> Create this file at: **`.github/instructions/services-and-business.instructions.md`** (relative to your repo root). Copy everything inside the box below (do **not** include the outer `~~~~` fence lines).

~~~~markdown
---
applyTo: "**/engine/service/**/*.java, **/engine/business/**/*.java"
---

# Service & business (orchestration) layer

Call flow: `service → business → infra/dao`; `service → domain`. ArchUnit forbids `service..` from importing
`infra..`, so services reach the DB **only** through `business/` components. `business/` is the sole layer
allowed to import `infra..`.

## Services (interface + impl)
- Interface in `service/` (or `service/task/`), implementation in `service/impl/` (or `service/task/impl/`).
  Name `FooService` → `FooServiceImpl`.
- Impl annotations: `@Service` + `@Slf4j` + `@RequiredArgsConstructor`, `private final` collaborators.
  Reference: `service/impl/LoadTasksServiceImpl`. **Every service has an interface** — do not put `@Service`
  on a bare class. (Only exception: the two Strategy dispatchers, which use an explicit constructor because
  they build a lookup Map.)
- Interfaces are thin and Javadoc'd, usually with a `Cross-reference: .NET ...` line.

## Business components
- Package `business/`, always `@Component` (**never `@Service`**) + `@RequiredArgsConstructor` + `@Slf4j`,
  with `private final` DAO/port/client dependencies. Reference: `business/GetRunPropertiesBusiness`,
  `business/EndRunBusiness`.
- One primary public use-case method. Thin delegators name it `execute(...)` (`GetTasksBusiness.execute`), but
  domain verbs are common and fine (`getProject`, `fetchXml`, `loadDocuments`, `process`, `render`). **Do not
  assume the method is literally `execute`.** Keep business classes thin — prefer delegating to a DAO/port over
  embedding logic (some existing ones, e.g. `QxpsCallerBusiness` at ~293 LOC, over-reach; don't use them as the
  model).

## Strategy pattern (task processing)
- `TaskProcessStrategy<T extends TaskBase>` / `TaskPostProcessStrategy<T>` each expose
  `Class<T> getTaskType()` and `process(T)` / `postProcess(T)`.
- Strategy impls are `@Component` (add `@Slf4j`/`@RequiredArgsConstructor` only if needed) and return the
  concrete `TaskXxx.class` from `getTaskType()`. Reference: `service/task/impl/SqlTaskProcessStrategy`.
- The dispatcher injects `List<Strategy>` in its constructor and builds
  `Collectors.toMap(Strategy::getTaskType, identity())`, then looks up by `task.getClass()`. Reference:
  `service/task/impl/TaskProcessServiceImpl`. A missing **process** strategy throws `IllegalStateException`;
  a missing **post-process** strategy logs at debug and is a no-op.
- Adding a task type = new strategy `@Component` + register nothing else (auto-collected via `List<Strategy>`).

## The pipeline orchestrator
`service/impl/ProcessRunServiceImpl.runProcessor(RunIdDto)` is the reference for run-level control flow:
- The whole 8-step pipeline is one `try / catch(Exception) / finally`. It **never throws to the caller and
  always returns the `Run`.**
- Top-level failure → `run.setStatus(RunStatus.ERROR)` + `run.getErrors().add(new RunError(RunError.BLOQUANTE,
  ...))`.
- The `finally` block **always** runs `endRunBusiness.execute(run)` (End_Run), with a single retry that only
  logs on failure.
- Per-task failures are caught individually, recorded as `RunError.CRITIQUE`, `task.setInError(true)`, and the
  loop continues.

## Config injection
- `@Value("${key:default}")` on a field, **always with an inline default** (`engine.step-limit:5000`,
  `engine.nb-box-max:17500`, `documentpool.basePath:D:\\Documents`).
- Prefer `@ConfigurationProperties` beans (e.g. `infra/interop/qxps/config/QxpsProperties`) for grouped infra
  config.

## Transactions
- Exactly **one** `@Transactional` exists in the codebase: `business/EndRunBusiness.execute`. Do not sprinkle
  `@Transactional` elsewhere — DB work is stored-proc calls whose atomicity is owned by Oracle. Add it only
  when a single business method issues multiple related writes that must commit together, and justify it.

## Logging
- `@Slf4j`. `info` = step boundaries, `debug` = per-task detail + stack traces, `warn` = skips, `error` =
  failures with the throwable as the **last** argument. Always include the run id. No MDC/correlation id;
  traceability is the run id plus `run.trace(...)` accumulation.

## Exceptions
- No custom exception types in this layer. Use `IllegalStateException` for broken invariants; wrap unexpected
  causes in `RuntimeException("Failed to ...", e)` (`business/ProcessSqlBusiness`). Prefer accumulating a
  `RunError` on the `Run` over throwing.

## Don't do this
- Don't add a `@Service` impl without an interface.
- Don't copy `business/RunStartUpdateBusiness` (manual logger + hand-written ctor, off-pattern) or
  `business/GetDocumentByIdBusiness` (missing `@Slf4j`).
- Don't hardcode a RunError severity as `2` — use `RunError.CRITIQUE` (some strategies currently hardcode it).
- Delete, don't imitate, `business/testbusinessFile.java`.
~~~~

---

## 📄 `.github/instructions/persistence.instructions.md`

> Create this file at: **`.github/instructions/persistence.instructions.md`** (relative to your repo root). Copy everything inside the box below (do **not** include the outer `~~~~` fence lines).

~~~~markdown
---
applyTo: "**/engine/infra/dao/**/*.java, **/engine/mapper/**/*.java"
---

# Persistence: DAOs & mappers (Oracle stored procedures)

There are **no JPA entities and no Spring Data repositories**. All DB access is Spring JDBC against Oracle
stored procedures/functions in `QXP_PK_*` packages. Liquibase is disabled; the schema is Oracle-owned and
external. **Never generate `@Entity`, `JpaRepository`, or Liquibase changesets.**

## DAO shape
Interface in `infra/dao/`, impl in `infra/dao/impl/`. Reference: `GetRunPropertiesDaoImpl`, `GetGabaritDaoImpl`.
- Annotate the impl `@Repository @Slf4j`; add `@RequiredArgsConstructor` when you use a `@PostConstruct init()`.
- Build a `SimpleJdbcCall(dataSource)` **once** and cache it in a field (in the constructor or `@PostConstruct
  init()`), never per call. The chain is always:
  ```
  new SimpleJdbcCall(dataSource)
      .withCatalogName("QXP_PK_RUN")            // Oracle package
      .withFunctionName("Get_Run_Properties")   // function returning a REF CURSOR / value ...
      // OR .withProcedureName("...")           // ... procedure with OUT params
      .withoutProcedureColumnMetaDataAccess()   // MANDATORY on every call (deterministic binds)
      .declareParameters(/* in declared order matching the proc signature */);
  ```
- A REF CURSOR is the **first** declared parameter:
  `new SqlOutParameter("result_cursor", OracleTypes.CURSOR, rowMapper)`; read it back with
  `result.get("result_cursor")` and a `@SuppressWarnings("unchecked")` cast to `List<...>`.
- **Declared parameter order must match the procedure signature.**

## Parameter binding
- Named binds via `new MapSqlParameterSource().addValue("p_snake_case", value)` (insert DAOs may use a plain
  `HashMap`). Reference: `GetCompartimentRunsDaoImpl`.
- **Dates (critical — the ORA-01843/01830/01858 class of bugs). Never let Oracle infer the format:**
  - `LocalDate` → declare `Types.DATE`, bind `java.sql.Date.valueOf(d)`, **null-guarded**
    (`InsertDocumentDaoImpl`).
  - `LocalDateTime` → declare `Types.TIMESTAMP`, bind `Timestamp.valueOf(dt)`, null-guarded (`AuditDaoImpl`,
    `EndRunDaoImpl`).
  - **Dynamic gabarit-SQL date in-params → `new oracle.sql.DATE(timestamp)`** (time-preserving) so `to_date(?)`
    round-trips under any session `NLS_DATE_FORMAT`. Reference: `mapper/InParamSqlMapper`.
  - An unset numeric/date param binds as a **typed SQL NULL** (`new SqlParameterValue(Types.NUMERIC, null)` /
    `Types.DATE`), **not** a MIN_VALUE sentinel number (that forces `TO_NUMBER` over text columns → ORA-01722).
  - FK id fields carrying `Integer.MIN_VALUE` bind as SQL NULL.
- The session date format is pinned to `DD/MM/YYYY` by Hikari `connection-init-sql`. Emit only day-first date
  literals in any SQL.

## Row mapping
- REF CURSOR mappers implement `mapFromResultSet(ResultSet) throws SQLException`, reading columns **by name**,
  using `rs.wasNull()` to substitute sentinels (`Integer.MIN_VALUE`, enum `UNKNOWN`). Reference:
  `mapper/RunPropertiesMapper`.
- For raw rows, use `new ColumnMapRowMapper()` to get `Map<String,Object>` (keys are **UPPERCASE** Oracle
  column names) and hand it to a `mapToX(Map<String,Object> row)` mapper. Reference: `mapper/TaskMapper`.
- Preserve raw `[Flags]` int values from the DB — never collapse them to a single enum.

## Mappers (`mapper/`)
- `@Component` (add `@RequiredArgsConstructor` only if it has dependencies, e.g. `TaskMapper` needs
  `FilePoolPort`). **Not MapStruct.**
- Use null-safe extraction helpers: `getInt/getBoolean/getBigDecimal/getString/isSet`. These are currently
  copy-pasted across `TaskMapper`/`TemplateMapper` — **reuse an existing mapper's helpers rather than pasting a
  fourth copy.**
- `createTaskByType`-style factories switch on the enum and return `null` + `log.warn` for unknown types.

## Inserts / OUT params / arrays
- Scalar return (generated id) → declare a `Types.NUMERIC` "RETURN" out param (`EndRunDaoImpl`).
- BLOB → `SqlTypeValue` + `setBinaryStream` (`InsertDocumentDaoImpl`).
- PL/SQL associative arrays → drop to a raw `JdbcTemplate` + `OraclePreparedStatement.setPlsqlIndexTable`
  (SimpleJdbcCall + `ARRAY` does **not** work here). Reference: `InsertDataStorageDaoImpl.setPlsqlIndexTable`,
  `EndRunDaoImpl.insertRunErrors`.

## Exceptions & empty results
- Reader DAOs wrap in try/catch: rethrow `IllegalArgumentException` on an empty/missing required row; wrap other
  causes in `RuntimeException("Failed to ...", e)`. Optional-document readers return `null`; list readers return
  `Collections.emptyList()`. SLF4J `{}` logging with the run/task id.

## DynamicQueryPortImpl & TaskSqlDao
- `DynamicQueryPortImpl` implements a **domain port**, delegates to `TaskSqlDao` + `InParamSqlMapper`, and must
  **never surface raw SQL text in error messages** — log only the ORA line (via `NestedExceptionUtils`).
- `TaskSqlDaoImpl` chooses positional (`?`) vs named (`:x`) binding by scanning the SQL string. Match that when
  extending it.

## DTOs
- Plain Lombok POJOs: `@Getter @Setter @AllArgsConstructor @NoArgsConstructor`. No records, no Jackson
  annotations. Reference: `dto/RunIdDto` (the queue message shape).
~~~~

---

## 📄 `.github/instructions/integration.instructions.md`

> Create this file at: **`.github/instructions/integration.instructions.md`** (relative to your repo root). Copy everything inside the box below (do **not** include the outer `~~~~` fence lines).

~~~~markdown
---
applyTo: "**/engine/infra/interop/**/*.java, **/engine/integration/soap/**/*.java, **/engine/infra/pdf/**/*.java"
---

# External integration: QXPS (HTTP), QXPSM (SOAP), PDF

This layer talks to QuarkXPress Server. It is a faithful .NET port — keep the `Cross-reference: .NET <Type>`
Javadoc and `Finding #NN` comments, and prefer behavioral parity over idiomatic reactive Java.

## QXPS HTTP client (`infra/interop/qxps/client/QxpsHttpClient`)
- This is the app's **only** `WebClient`. Build it lazily in `@PostConstruct init()` (not as a `@Bean`), on
  Reactor Netty with `keepAlive(false)`, a single `timeout` (ms) driving connect/read/response, and
  **`ExchangeStrategies` with `maxInMemorySize` wired from `qxps.server.max-in-memory-size-bytes`** (~500 MB).
  Omitting the buffer limit throws `DataBufferLimitException` on multi-MB documents — always set it.
- Calls are **synchronous**: reactive chains end in `.block()`, using `.exchangeToMono(...)` (not `.retrieve()`).
  No retry, no resilience4j.
- Response type is chosen by an exact lowercase `Content-Type` match against
  `{text/plain, text/xml, text/html, ""}` → `String`, otherwise `byte[]`.
- POST bodies are hand-built multipart `byte[]`.
- Wrap non-`QxpsException` failures in `new QxpsException(requestInfo, cause)`.

## QXPS message model (`infra/interop/qxps/message/`, `request/`)
- `QxpsMessage` is an interface (Cross-ref .NET `QXPS_Message_Base`); subtypes are **command/value objects, not
  builders**. Each supplies `getCommandPath/Query/Data`, `isPost`, `getPriority`.
- Data commands: `@Getter @RequiredArgsConstructor`. Render commands: `@Getter @Setter` + no-arg ctor, building
  the query by conditionally appending to an `ArrayList<String>` then `String.join("&", args)`, returning
  `null` when empty.
- `MessagePriority` is a 1–5 code enum. `QxpsRequestBuilder.buildCombined` stable-sorts by priority, appends
  the document name **last**, allows at most one POST, then `UriComponentsBuilder...build().encode()`.

## QXPSM SOAP client (`infra/interop/qxpsm/QxpsmSoapClient`)
- Uses Apache Axis 1.4 stubs in `integration/soap/generated/` — **generated at build via `wsdl2java`; never
  hand-edit them.** They are regenerated from `src/main/resources/wsdl/RequestService.wsdl` (namespace
  `http://com.quark.qxpsm`, service `RequestService`, trimmed to one SOAP 1.1 binding/port with the
  `QException` fault stripped). **Do not reference the obsolete `qxpsmsdk.wsdl` /
  `webservice.manager.quark.com` namespace.**
- Create the stub **per call** via `RequestServiceLocator.getRequestServiceHttpSoap11Endpoint(url)`; set the
  timeout by casting to `org.apache.axis.client.Stub` and calling `setTimeout(...)` (`0` = infinite, matching
  .NET). Build the request chain last→first: `QuarkXPressRenderRequest` ← `SaveAsRequest` ← optional
  `ModifierRequest` ← optional `RequestParameters`, linked via `QRequest.request`. Credentials are **empty
  strings, not null**.
- **Do not reintroduce `PROP_DOMULTIREFS` / multi-ref** — that hypothesis was disproven and reverted.
- Errors are currently thrown as a bare `RuntimeException` (there is no `QxpsmException`).

## Ports & pool paths
- `FilePoolService` (implements `FilePoolPort`) and `DocumentIdentityService` (implements
  `DocumentIdentityPort`) are `@Service @RequiredArgsConstructor`. They go through `QxpsHelper`, not the
  `WebClient` directly.
- The pool path convention lives in `domain/RunProperties`: relative `R_<runId>/<file>`, absolute
  `D:\Documents\...` with `/`→`\` for the Windows Quark host. Address pooled documents by
  `DocumentDomain.getFilePoolPath()` end to end.

## Serialization
- Serializers (`QxpsProjectSerializer`, `qxpsm/NameValueSerializer`) are `final` utility classes using **StAX
  `XMLStreamWriter`** — never JAXB or string concatenation for XML. Skip null/empty attributes.

## Config properties
- `@Getter @Setter @Configuration @ConfigurationProperties(prefix = "...")` with nested `static` classes and
  field-level defaults (no bean validation). Reference: `QxpsProperties` (`qxps`), `QxpsmProperties`
  (`qxpsm.soap`).

## PDF (`infra/pdf/PdfSplitter`)
- PDFBox `Splitter`; wrap every closeable in try-with-resources (including `try (page; baos)`).

## Config coupling (operational)
All three Quark endpoints — `qxps.server.url`, `qxpsm.soap.endpoint`, `qxp.thirdparty.url` — **must point at the
same environment**, or the SOAP step cannot see the document the HTTP step pooled.

## Don't do this (present in the tree, not to be copied blindly)
- `.block()` on the WebClient, hardcoded Windows paths, per-call SOAP stub creation, and effectively-infinite
  timeouts with no retry/circuit-breaker are existing realities — match them for consistency but do not
  amplify. Don't invent an inconsistent new exception hierarchy (the layer already mixes rich `QxpsException`
  vs bare `RuntimeException`); prefer `QxpsException` for the HTTP path.
~~~~

---

## 📄 `.github/instructions/api-and-messaging.instructions.md`

> Create this file at: **`.github/instructions/api-and-messaging.instructions.md`** (relative to your repo root). Copy everything inside the box below (do **not** include the outer `~~~~` fence lines).

~~~~markdown
---
applyTo: "**/engine/infra/api/**/*.java, **/engine/listener/**/*.java, **/engine/config/**/*.java"
---

# API & messaging (entry points)

There are exactly two entry points, and both delegate to `ProcessRunService.runProcessor(RunIdDto)`. Keep them
thin — no business logic here.

## REST controller (`infra/api/v1/EngineServiceController`)
- `@RestController @RequestMapping("ap/v1/EngineService") @RequiredArgsConstructor @Slf4j`, with an OpenAPI
  `@Tag`. Inject the service interface as a `private final` field.
- Handlers log the run id, wrap the call in try/catch, and return a `ResponseEntity` — `HttpStatus.OK` with a
  message on success, `HttpStatus.INTERNAL_SERVER_ERROR` on failure (body = message string, or `null` for the
  fetch endpoint). This is the existing convention; **there is no active `@ControllerAdvice`** (the
  `GlobalExceptionHandler` is commented out and `problem-spring-web` is unused). Match the inline try/catch
  style; do not introduce a global handler unless explicitly asked.
- New endpoints go under `service/impl` for logic; the controller only adapts HTTP ↔ service.

> Note: the mapping is `ap/v1/...` while security secures `/api/v1/**` — a known mismatch. If you add endpoints
> meant to be secured, put them under `/api/v1/**` and confirm against `sg.security.paths` in `application.yaml`.

## Queue listener (`listener/RunMessageListener`)
- `@Component @RequiredArgsConstructor @Slf4j`. Method annotated `@RabbitListener(queues = "${queue.runqueue}")`
  taking the deserialized `RunIdDto`.
- Log receipt with the run id, call the service in try/catch, log success, and **rethrow on failure** so the
  broker applies its policy (`spring.rabbitmq.listener.simple.default-requeue-rejected: false` → failed
  messages are not requeued). Reference: `RunMessageListener.receiveMessage`.

## RabbitMQ config (`config/RabbitMqConfig`)
- The only local `@Configuration`. It registers a `Jackson2JsonMessageConverter` and a `RabbitTemplate` wired
  to that converter — messages are JSON. `RunIdDto` must stay a plain Jackson-serializable POJO. Keep this
  minimal; broker connection settings live in `application.yaml` under `spring.rabbitmq`.

## Conventions
- Constructor injection via `@RequiredArgsConstructor` + `final`. `@Slf4j` logging with `{}` and the run id.
- Don't add JPA, security annotations, or web concerns into `service`/`domain` from here — keep framework
  coupling in this entry-point layer only.
~~~~

---

## 📄 `.github/instructions/enums.instructions.md`

> Create this file at: **`.github/instructions/enums.instructions.md`** (relative to your repo root). Copy everything inside the box below (do **not** include the outer `~~~~` fence lines).

~~~~markdown
---
applyTo: "**/engine/enums/**/*.java"
---

# Enums (legacy Oracle code ↔ enum)

Enums map legacy .NET/Oracle integer codes (and sometimes French text labels) to type-safe constants. There is
**no shared base class or lookup map** — each enum carries its own factory.

## Legacy-int enums (the common case)
- `@Getter` (Lombok) + `private final int code` + a constructor + a `static fromCode(int)` that does a linear
  `for (values())` scan and **returns a fallback constant on a miss** — `UNKNOWN` / `NONE` / `UNSPECIFIED` /
  `SYSTEM`. Reference: `DataTypeEnum`, `TaskTypeEnum`, `TaskCompartimentMode`.
- **Never throw and never return null from `fromCode`.** The sole exception is `RunStatus.fromCode`, which
  throws — do not use it as the template for new enums.

## Label-based lookups
- Add a `String label` field and a `fromLabel`/`fromString` factory only when the legacy data stores text.
  Match with `equalsIgnoreCase`, guard null/blank, fall back to a constant. **Preserve the legacy strings
  verbatim, including typos** (e.g. `GabaritSourceEnum`/`TypeRapportEnum` keep `"Propectus"`).
- Name-only enums: `valueOf(x.toUpperCase())` wrapped in try/catch → fallback constant, null/blank guarded.

## `[Flags]` / bitmask enums
- Port .NET `[Flags]` enums as hex values and expose static `hasFlag(int, flag)` / `hasXxx()` bit-tests. Do
  **not** add a `fromValue` — callers keep and test the raw int. Reference: `domain/StoreDataType`,
  `enums/TBoxTypeEnum`.

## General
- Keep French labels separate from `name()`; `name()` stays an ASCII identifier.
- One factory returns null against convention: `DocumentFormatEnum.fromFormat`. Don't copy that; return a
  fallback constant instead.
~~~~

---

## 📄 `.github/instructions/testing.instructions.md`

> Create this file at: **`.github/instructions/testing.instructions.md`** (relative to your repo root). Copy everything inside the box below (do **not** include the outer `~~~~` fence lines).

~~~~markdown
---
applyTo: "**/src/test/**/*.java"
---

# Testing conventions

Stack: **JUnit 5 (Jupiter) + Mockito**. Assertions are `org.junit.jupiter.api.Assertions.*`. **Do not use
AssertJ or Hamcrest** (neither is used here), and do not write JUnit 4 tests.

## Naming & structure (universal)
- Test class `{ClassName}Test`, package-private, with `@DisplayName("Xxx Tests")`. Reference:
  `business/GetRunPropertiesBusinessTest`.
- Test methods are camelCase `shouldXxxWhenYyy()`, each with its own `@DisplayName("Should ...")`.
- Fixtures are set up inline in a `@BeforeEach setUp()`; use local `buildBaseRow(...)`-style helpers. There are
  **no test-data builder classes** and no `@Nested`/`@ParameterizedTest` in the suite — follow that.

## Per-layer approach
- **Business / Service:** pure Mockito unit tests — `@ExtendWith(MockitoExtension.class)` + `@InjectMocks` on
  the class under test + `@Mock` collaborators. Reference: `service/impl/ProcessRunServiceImplTest`.
- **DAO:** the database is **fully mocked** — no H2, no Testcontainers. `@Mock DataSource`, `@Mock
  SimpleJdbcCall`; construct the impl by hand in `setUp()` and inject the cached proc-call field with
  `ReflectionTestUtils.setField(dao, "getRunPropertiesCall", simpleJdbcCall)`; stub
  `simpleJdbcCall.execute(any(SqlParameterSource.class))` to return `Map.of("result_cursor", List.of(...))`.
  Cover the empty/null cursor and the exception-wrapping paths. Reference:
  `infra/dao/impl/GetRunPropertiesDaoImplTest`.
- **Mapper:** plain JUnit, construct with `new Mapper(...)` and `mock(...)` collaborators; row-mapper tests use
  a `@Mock ResultSet` stubbed per **uppercase** Oracle column name (`"ID_TACHE"`). Reference: `mapper/TaskMapperTest`.
- **Domain / Enum:** plain POJO tests, no mocks.
- **Controller:** the only Spring slice test — `@WebMvcTest(TheController.class)` + `@WithMockUser` +
  `@MockBean` for the service + `MockMvc`. POST requests add `.with(csrf())`; assert with
  `status()` / `content()` / `jsonPath()`. Reference: `infra/api/v1/EngineServiceControllerTest`.
- A full-context IT base exists (`SpringBootITProfileWithTransactionalAndMockMvc`:
  `@SpringBootTest` + `@AutoConfigureMockMvc` + `@ActiveProfiles("test")` + `@Transactional`) but is currently
  unused — reuse it only for genuine end-to-end tests.

## Architecture governance tests (keep them green)
- `CleanArchitectureLayersTest` and `WrongFrameworksTest` (ArchUnit) enforce the layering and
  framework/logging rules described in the repo-wide instructions. New code must not break them.
- `performance/GatlingRunner` is a perf-test stub — leave it unless doing perf work.

## Don't do this
- Don't leave empty test classes (`domain/task/TaskBaseTest` is 0 bytes — a gap to fill, not a pattern).
- Don't introduce AssertJ/Hamcrest, `@Disabled` tests, or mix JUnit 4 and 5.
- Don't spin up a real DB for DAO tests — mock `DataSource`/`SimpleJdbcCall` as above.
~~~~

---

## 📄 `.github/instructions/config-security-migrations.instructions.md`

> Create this file at: **`.github/instructions/config-security-migrations.instructions.md`** (relative to your repo root). Copy everything inside the box below (do **not** include the outer `~~~~` fence lines).

~~~~markdown
---
applyTo: "**/resources/**, **/src/main/config/**, **/*.yaml, **/*.yml, **/pom.xml"
---

# Config, security & migrations

## Config layout
- Base config is `src/main/resources/application.yaml`. Per-environment overrides live in
  `src/main/config/env/{dev,uat,prod}/application-env.yaml`; secrets in
  `src/main/config/secrets/{dev,uat,prod}/application-secrets.yml`; local dev in
  `src/main/config/local/application-local.yaml`.
- Put new secrets in the `config/secrets/*` overlays, **not** in `application.yaml`. (The committed
  `application.yaml` currently hardcodes datasource/RabbitMQ credentials — a known issue; don't add more.)
- Reference config in code with `@Value("${key:default}")` (always a default) or an
  `@ConfigurationProperties` bean for grouped infra settings.

## Config that is load-bearing (don't remove/relax without understanding)
- `spring.datasource.hikari.connection-init-sql: ALTER SESSION SET NLS_DATE_FORMAT='DD/MM/YYYY'` — pins the
  Oracle session date format on every pooled connection. The gabarit SQL has day-first date literals; removing
  this reintroduces ORA-01843/01830.
- `qxps.server.max-in-memory-size-bytes: 524288000` (500 MB) and `qxps.server.timeout` / `qxpsm.soap.timeout`
  (2h) — sized for 100 MB+ documents; do not shrink casually.
- All three Quark endpoints (`qxps.server.url`, `qxpsm.soap.endpoint`, `qxp.thirdparty.url`) must point at the
  **same environment**.
- `spring.jpa.hibernate.ddl-auto: none` and `spring.liquibase.enabled: false` — intentional. See Migrations.

## Security
- **There is no local Spring Security Java configuration.** Auth is provided by the parent
  `sgs-api-core:11.0.1` starter + `apibank-starter-security-client` (SG Connect OAuth2). **Do not author a
  `SecurityFilterChain` / `@EnableWebSecurity` / `WebSecurityConfigurerAdapter`.**
- Configure access declaratively in `application.yaml`: `sg.security.paths` (pattern → scopes, e.g.
  `/api/v1/**` → `api.quark.v1`), `sg.security.sgconnect.enabled`, `sg.oauth2`. There is no `@PreAuthorize` /
  method security — don't add it unless asked.
- Rate limiting is configured under `rate-limiter` (apibank `http-rate-limiter`).

## Logging
- `src/main/resources/logback-spring.xml` — SLF4J only (ArchUnit-enforced), structured **ECS-JSON** via the
  Elastic `ecs-file-appender` plus a console appender. Don't hand-craft log patterns or MDC; use `@Slf4j`.

## Migrations / schema
- **The schema is Oracle-owned and external.** Liquibase is disabled and the changelog files
  (`resources/db/changelog/*`) are un-replaced SGS placeholders that are not applied at runtime. **Do not
  generate Liquibase changesets, JPA entities, or DDL.** New DB operations are exposed as `QXP_PK_*` stored
  procedures/functions and consumed via `SimpleJdbcCall` DAOs (see
  `.github/instructions/persistence.instructions.md`).

## Build (`pom.xml`)
- Maven, parent `sgs-api-core:11.0.1`. The `axistools-maven-plugin` generates the QXPSM SOAP client from
  `src/main/resources/wsdl/RequestService.wsdl` into `integration/soap/generated/` at `generate-sources` —
  regenerated on `mvn clean install`. When changing the SOAP contract, edit the WSDL and regenerate; never
  hand-edit generated stubs. MapStruct and `problem-spring-web` are declared but unused — don't rely on them.
~~~~
