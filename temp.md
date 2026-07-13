# EOS Quark — Consolidated Change Log (post-batch stabilization)

**Scope:** every code/config change made after the batch port (Batches 1–13) while stabilizing live runs —
the dynamic-SQL date fix, the QXPSM SOAP client migration, the QXPS buffer/timeout fix, DAO/parse
robustness, and cleanup. Consolidated from the individual fix docs so you don't have to track them
separately.

**Two live runs drove all of this:**
- **509636** (Plaquette, QXPSM SOAP path) → exposed the buffer limit + the wrong-WSDL/namespace SOAP fault.
- **488654** (Dynamique, 24 tasks) → exposed the ORA-01843/01830 date failures + the `DBreakRule` parse crash.

**Precedence note:** for the QXPSM SOAP work, `EOS_Quark_QXPSM_FINAL.md` is the single source of truth;
it supersedes the earlier QXPSM WSDL / MultiRef / SoapClient / Correctness docs. The old **multi-ref
(`PROP_DOMULTIREFS`) hypothesis was disproven and reverted** — do not reintroduce it.

---

## Status at a glance

| Area | What | Applied (Mac copy) | In new repo `java repo 27-06` | Verified |
|---|---|---|---|---|
| A. Dynamic SQL date | NLS session format + Oracle DATE bind | ✅ | ❓ not confirmed by 27-06 verification | NLS-safety audit ✅ (this session) |
| B. QXPSM SOAP | Correct WSDL/namespace, client, endpoints | ✅ | ✅ verified present | Probe L1+L2 PASSED on DEV |
| C. QXPS buffer/timeout | 500 MB codec buffer, 2h timeouts | ✅ | ✅ verified present | — |
| D. DAO/parse robustness | `DBreakRule` lenient parse + date null-guards | ✅ (Mac) | ❌ **still missing — REQUIRED, crashes 488654** | — |
| E. Cleanup | remove temp DEBUG log, dead files | partial | pending | — |

---

## A. Dynamic-SQL date fix — ORA-01843 / ORA-01830 (run 488654)

**Symptom:** every Dynamique task SQL failed with `ORA-01843: not a valid month` / `ORA-01830: date
format picture ends before converting entire input string`; each task produced "no blocs", PDF came out
empty. The run still finalized `GENERATED` with 166 recorded errors (see open item O-1).

**Root cause — two independent date problems, BOTH required (neither alone fixes it):**
1. The gabarit SQL (stored in DB, shared verbatim with .NET) has hardcoded **day-first literals**
   (`'31/12/2199'`) compared to DATE columns → Oracle does `to_date(literal, <session NLS_DATE_FORMAT>)`,
   which only parses under `DD/MM/YYYY`. .NET ran a day-first session; Java set no NLS → thin driver took
   it from the JVM locale → failure.
2. DATE in-params were bound as `java.sql.Timestamp` → Oracle TIMESTAMP → `to_date(TIMESTAMP)` breaks.
   .NET binds them as native Oracle DATE.

| # | File | Action | Change | Type |
|---|---|---|---|---|
| A1 | `src/main/java/.../mapper/InParamSqlMapper.java` | EDIT | DATE case now `return toOracleDate(value)` → `new oracle.sql.DATE(toSqlTimestamp(value))` (time-preserving) instead of `java.sql.Timestamp`. Other types & sentinels unchanged. | code (REQUIRED) |
| A2 | `src/main/resources/application.yaml` | EDIT | Add `spring.datasource.hikari.connection-init-sql: ALTER SESSION SET NLS_DATE_FORMAT='DD/MM/YYYY'` — pins the date format on every pooled connection. | **config** (REQUIRED) |
| A3 | `src/test/java/.../mapper/InParamSqlMapperTest.java` | EDIT | Assert via `((oracle.sql.DATE) parsed).timestampValue()`; empty → DATETIME_MIN via `.timestampValue()`. | test |
| A4 | `src/main/java/.../integration/soap/client/EngineSoapClient.java`<br>`src/main/java/.../integration/soap/config/SoapConfig.java` | DELETE | Dead empty stubs naming the removed `qxpsmsdk.wsdl`; nothing references them. (Leave `integration/soap/generated/` alone.) | cleanup |

**NLS-safety audit (this session — is the `NLS_DATE_FORMAT` session setting safe?): YES.** Two passes over
the .NET tree confirmed:
- .NET **never** sets NLS / `ALTER SESSION` anywhere (0 hits); it inherits day-first implicitly from the
  Windows Oracle client (`NLS_LANG` registry / OS locale). Making it explicit in Java replaces a hidden
  dependency — it does not diverge from .NET.
- The whole codebase is **uniformly day-first**: 48 implicit `'31/12/2199'`-style literals, all DD/MM;
  every explicit mask is `dd/mm/yyyy`/`dd-mm-yyyy`/`mm/yyyy`. **Zero** month-first, **zero** ISO literals.
- All C# `DateTime` params bind as native `OracleDbType.Date` (binary, NLS-irrelevant); C# never builds a
  date literal into SQL text. So the session setting cannot break any other code path.
- Caveats: `NLS_DATE_FORMAT` covers DATE only (TIMESTAMP uses a separate `NLS_TIMESTAMP_FORMAT` — none in
  the shared SQL); one unmasked `to_date(p_date_exec)` at `QXP_PK_KII_BODY.sql:1857` is a DATE→DATE
  round-trip (drops the time component; behavior-preserving).
- **Not yet done:** sweep the Java repo for implicit date→string reads (`ResultSet.getString` on DATE
  columns, unmasked `to_char`/`to_date` in Java) that would now render DD/MM/YYYY. The .NET side is fully verified.

---

## B. QXPSM SOAP client migration — wrong WSDL / namespace (run 509636)

**Symptom:** `AxisFault: namespace mismatch require http://com.quark.qxpsm found
http://webservice.manager.quark.com`.

**Root cause:** the Java stub was generated from the wrong WSDL (`qxpsmsdk.wsdl` — Axis 1.x, RPC/encoded,
namespace `http://webservice.manager.quark.com`). The live deployed server is **Axis 2, document/literal,
namespace `http://com.quark.qxpsm`, service `RequestService`**. (Verified: .NET's real compiled proxy is
also `com.quark.qxpsm`/`RequestService`; the `webservice.manager.quark.com` file was a stale, never-compiled
leftover.) Secondary issue: the three Quark endpoints pointed at different environments (DEV vs UAT) so the
SOAP step couldn't see the DEV-pooled document.

| # | File | Action | Change | Type |
|---|---|---|---|---|
| B1 | `src/main/resources/wsdl/RequestService.wsdl` | CREATE | Fetched byte-exact from live server `…:8090/qxpsm/services/RequestService?wsdl`. Then **trimmed to the single SOAP 1.1 binding/port**, and **`<wsdl:fault name="QException">` stripped** from portType+binding (Axis 1.x couldn't generate `QException` → 42 `cannot find symbol` errors; faults still arrive as `AxisFault`). Final: 1 binding, 1 port, ns `com.quark.qxpsm`, 0 faults. | config/build |
| B2 | `src/main/resources/wsdl/RequestService.full.wsdl` | CREATE | Untouched vendor original kept as reference backup. | build |
| B3 | `pom.xml` (`axistools-maven-plugin`) | EDIT | `<wsdlFile>qxpsmsdk.wsdl</wsdlFile>` → `<wsdlFile>RequestService.wsdl</wsdlFile>`; stale comment updated. | build |
| B4 | `src/main/java/.../integration/soap/generated/` | REGEN | Deleted old wrong-namespace package, regenerated via `mvn clean install` → `RequestService`, `RequestServiceLocator`, `RequestServicePortType`, `RequestServiceSoap11BindingStub` + type beans. | build output |
| B5 | `infra/interop/qxpsm/QxpsmSoapClient.java` | EDIT | New locator/port names: `RequestServiceLocator.getRequestServiceHttpSoap11Endpoint(URL) → RequestServicePortType` (was `QManagerSDKSvcServiceLocator.getqxpsmsdk`). Added Axis client socket timeout `((org.apache.axis.client.Stub) stub).setTimeout(...)` (`0` = infinite, matching .NET `Timeout = Infinite`). **Multi-ref line removed.** Request logic unchanged. | code |
| B6 | `application.yaml` | EDIT | Align all three Quark URLs to the same env (DEV `srvcldvapd001`): `qxps.server.url`, `qxpsm.soap.endpoint` (`…:8090/qxpsm/services/RequestService`), `qxp.thirdparty.url` (`…:8080/saveas/pdf/`). `qxpsm.soap.max-retries: 0`. | **config** |

**Verified:** `QxpsmProbe` (throwaway `main()`, since deleted) ran L1 (`getOpenSessions` handshake) +
L2 (`processRequest` doc/literal polymorphism) — **both PASSED** on DEV `srvcldvapd001:8090`, server
QuarkXPress Server 21.0.2.0. The `java repo 27-06` verification confirmed this whole migration is present.

> Note: the final PDF is produced via the QXPS HTTP `/pdf` endpoint (`qxp.thirdparty.url`), not the SOAP
> `QuarkXPressRenderRequest`. Long-term option (deferred): migrate Axis 1.x → JAX-WS/CXF for this doc/literal service.

---

## C. QXPS buffer + timeout fix (run 509636)

**Root cause:** `QxpsHttpClient` built its `WebClient` with no buffer limit → framework default 256 KB →
`DataBufferLimitException: Exceeded limit on max bytes to buffer : 262144` on multi-MB responses
(`/xml`, `/pdf`, literal QXP). Config gap, not a parity issue. Documents can be 100 MB+.

| # | File | Action | Change | Type |
|---|---|---|---|---|
| C1 | `infra/interop/qxps/config/QxpsProperties.java` | EDIT | Added `Server.maxInMemorySizeBytes` (default `524288000` = 500 MB). | code |
| C2 | `infra/interop/qxps/client/QxpsHttpClient.java` | EDIT | In `init()`, wire the limit: `.exchangeStrategies(ExchangeStrategies.builder().codecs(c -> c.defaultCodecs().maxInMemorySize(maxInMemory)).build())`. | code |
| C3 | `application.yaml` | EDIT | `qxps.server.timeout` 1h→**2h** (`7200000`); **new** `qxps.server.max-in-memory-size-bytes: 524288000`; `qxpsm.soap.timeout` 1h→**2h**. (2h is finite & above .NET's 1h; safer than .NET's client-side infinite for a Kube pod.) | **config** |

**Verified:** present in `java repo 27-06`.

---

## D. DAO / parse robustness — pending in new repo ❌

Found during the `java repo 27-06` verification; **not yet applied there.** D1 is REQUIRED — it crashes 488654.

| # | File | Action | Change | Type |
|---|---|---|---|---|
| D1 | `src/main/java/.../domain/dynamic/report/DBreakRule.java` | EDIT | Strict `Integer.parseInt` throws `NumberFormatException` on tokens like `"5L1"`. Add lenient `toInt(String)` via `new java.math.BigDecimal(v).intValue()`, returning `Integer.MIN_VALUE` on null/empty/parse-fail (mirrors .NET `Conversion.ToInt`). `parseRuleValues`/`analyseRule` use `toInt`. | code **(REQUIRED)** |
| D2a | `infra/dao/impl/GetCompartimentRunsDaoImpl.java` (~L93) | EDIT | `p_date_echeance` null-guard: `dateEcheance != null ? java.sql.Date.valueOf(...) : null` with explicit `java.sql.Types.DATE`. | code (recommended) |
| D2b | `infra/dao/impl/EndRunDaoImpl.java` (~L57 and ~L86, BOTH) | EDIT | `p_date_fin` → `dateFin != null ? Timestamp.valueOf(dateFin) : null`. | code (recommended) |
| D2c | `infra/dao/impl/InsertDataStorageDaoImpl.java` (~L45) | EDIT | `ops.setTimestamp(3, dateGeneration != null ? Timestamp.valueOf(dateGeneration) : null)`. | code (recommended) |

---

## E. Cleanup / temporary items to remove

| # | File | Action | Note |
|---|---|---|---|
| E1 | `application.yaml` (~L70-73) | REMOVE | Temp `logging.level.org.apache.axis.transport.http: DEBUG` (`TEMP-DEBUG-RT`) — remove once SOAP diagnosis is done. |
| E2 | `src/main/resources/wsdl/qxpsmsdk.wsdl` | DELETE | Obsolete, no longer referenced. Keep `RequestService.full.wsdl` backup. |
| E3 | `pom.xml:290` | EDIT | Stale comment `qxpsmsdk.wsdl` → `RequestService.wsdl` (cosmetic). |
| E4 | `.../integration/soap/generated/QxpsmProbe.java` | DELETE | Throwaway probe — already deleted per verification. |

---

## Complete file-touch index

**Created:** `wsdl/RequestService.wsdl`, `wsdl/RequestService.full.wsdl`, (throwaway) `generated/QxpsmProbe.java`
**Edited (code):** `InParamSqlMapper.java`, `QxpsProperties.java`, `QxpsHttpClient.java`, `QxpsmSoapClient.java`,
`DBreakRule.java`†, `GetCompartimentRunsDaoImpl.java`†, `EndRunDaoImpl.java`†, `InsertDataStorageDaoImpl.java`†
**Edited (build/config):** `pom.xml`, `application.yaml`
**Regenerated:** `integration/soap/generated/` package
**Deleted:** `wsdl/qxpsmsdk.wsdl`, `generated/QxpsmProbe.java`, `soap/client/EngineSoapClient.java`, `soap/config/SoapConfig.java`
**Test:** `InParamSqlMapperTest.java`
† = still pending in `java repo 27-06`.

---

## Config that must live in yaml (application.yaml / env overlay)

`qxps.server.timeout=7200000` · `qxps.server.max-in-memory-size-bytes=524288000` ·
`qxpsm.soap.timeout=7200000` · `qxpsm.soap.endpoint` · `qxpsm.soap.max-retries=0` ·
`qxp.thirdparty.url` · `qxps.server.url` ·
`spring.datasource.hikari.connection-init-sql` (NLS_DATE_FORMAT) ·
(temporary) `logging.level.org.apache.axis.transport.http`

All three Quark endpoints (`qxps.server.url`, `qxpsm.soap.endpoint`, `qxp.thirdparty.url`) must point at the
**same environment** or the SOAP step can't see the pooled document.

---

## Open items / next steps

- **O-1 (verify, don't guess):** endpoint reports `GENERATED` even though per-task SQL failed (166 errors,
  empty PDF on 488654). May be .NET-faithful — check .NET `End_Run` before changing run/HTTP status semantics.
- **O-2:** apply D1 (**required**) + D2a-c to `java repo 27-06`, and confirm the Group-A date fixes are in
  that repo (the 27-06 verification predates/omits them).
- **O-3:** run the Java-side implicit-date-read sweep (see Group A audit caveat).
- **O-4:** `mvn clean install` + **re-run 488654** (date fix + DBreakRule) and **509636** (QXPSM path);
  509636 previously gave blank pages because it had 0 content tasks — validate rendering on content-ful 488654.
- **O-5:** untested live array-bind paths: `InsertDataStorageDaoImpl.setPlsqlIndexTable`,
  `EndRunDaoImpl.insertRunErrors`.
- **O-6:** do the Group-E cleanup once diagnosis is complete.
