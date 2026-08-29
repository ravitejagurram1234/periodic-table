# EOS Quark Wave 10E - Bounded Logging Office Apply Guide

Revision: 2026-08-30. Apply after the complete Wave 10D code is present.

## Important

`EOS_Quark_Office_Live_Run_Evidence_Capture_Guide.md` is documentation; it does not modify the Java repository.
The Wave 10E code is present in this workspace only. A separate office-laptop clone does not contain it until the
files below are transferred or the equivalent commit is applied.

Do not reconstruct these changes by copying isolated snippets. Copy the complete files from this workspace onto the
same Wave 10D baseline, review `git diff`, verify the checksums, and run Maven. If the office clone has additional
changes in any listed file, merge instead of overwriting.

## Files To Apply

Production and resources:

1. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java`
2. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImpl.java`
3. `src/main/java/com/socgen/sgs/api/quark/engine/business/ProcessSqlBusiness.java`
4. `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/DynamiqueTaskProcessStrategy.java`
5. `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/DynamicQueryPortImpl.java`
6. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/client/QxpsHttpClient.java`
7. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/model/QxpsResponseInfo.java`
8. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxpsm/QxpsmSoapClient.java`
9. `src/main/resources/logback-spring.xml`

Tests:

1. `src/test/java/com/socgen/sgs/api/quark/engine/business/ProcessSqlBusinessTest.java`
2. `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImplTest.java`
3. `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImplTest.java`
4. `src/test/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/client/QxpsHttpClientTest.java`
5. `src/test/java/com/socgen/sgs/api/quark/engine/infra/interop/qxpsm/QxpsmSoapClientTest.java`
6. `src/test/java/com/socgen/sgs/api/quark/engine/diagnostic/LoggingSourcePolicyTest.java`

`application.yaml` is not replaced by Wave 10E. Keep the single existing main file and verify:

```yaml
spring:
  jpa:
    show-sql: false
engine:
  input:
    rabbit:
      enabled: false
```

## Verification

From the Java repository root, with `EOS_Quark_Wave10E_Bounded_Logging.sha256` placed beside `pom.xml`:

```bash
shasum -a 256 -c EOS_Quark_Wave10E_Bounded_Logging.sha256
mvn clean install
```

All checksum lines and the Maven build must pass before a Swagger evidence run. Then verify the effective logging
configuration contains these protections:

```bash
rg -n 'show-sql:|engine:|rabbit:|enabled:' src/main/resources/application.yaml
rg -n 'springframework.jdbc.core|hibernate.SQL|hibernate.orm.jdbc.bind|axis.transport.http|httpclient.wire|reactor.netty.http.client' src/main/resources/logback-spring.xml
```

The productive evidence volume is bounded to one run-load line, one selected-task result line per selected task,
two lines per QXPS/QXPSM call, one optional anomaly summary per affected task, and one terminal run line. It does not
print `QXP_TACHE.SQL`, SQL rows, bind names/values, block values, XML, document paths, request/response bodies or
binary content. Existing row/cell errors remain persisted for parity but are aggregated in console logs.

## Use The Temporary DB Connection Now

Do not execute `EOS_Quark_Office_Live_Run_Evidence_Queries.sql` as one complete script. Execute and export only these
labelled blocks first:

1. `QOFF-00` for environment reference values.
2. `QOFF-01A` for successful historical baseline candidates by simple, dynamic and compartment scenario.
3. `QOFF-01B` for untouched status-5 Swagger candidates.
4. Set `RUN_ID` to each shortlisted status-5 ID and require `QOFF-02B.BASIC_ADMISSION_RESULT=PASS`.

For a shortlisted ID, also run `QOFF-03`, `QOFF-04`, `QOFF-05`, `QOFF-05A`, `QOFF-07`, and `QOFF-07B`. Run
`QOFF-08` for document tasks, `QOFF-08B` for previous-QXP tasks, and `QOFF-09` for compartment tasks. These are
read-only queries. `QOFF-05` intentionally exports only `SQL_LENGTH`, never the SQL CLOB.

If `QOFF-01B` has no suitable row, do not update an old run. Stop batch, old .NET engine and Java engine; create a
fresh run through the old UI; select it with `QOFF-01C`; require `QOFF-02A=PASS`; use
`EOS_Quark_NonProd_Swagger_Run_Reservation.sql`; then require `QOFF-02B=PASS`. The guarded reservation updates only
`QXP_RUN` from status 1 to 5 and does not update `QXP_SUIVI`.

Do not call Swagger until Wave 10E is applied, `mvn clean install` passes, Rabbit remains disabled, and the selected
run passes all applicable prechecks.
