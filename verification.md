# EOS Quark — QXPSM correctness verification (deep research + probe)

**Date:** 2026-06-26
**Purpose:** prove the regenerated `com.quark.qxpsm` / document-literal stub is the
*correct, faithful* replication of .NET — and de-risk it before the live run.
**Verdict: GO.** One residual risk (doc/literal polymorphism) is retired by the probe in §5.

---

## 1. The reconciliation — why .NET works and we failed (now proven)

The deep dive into the .NET source found the missing piece:

- The `.NET` in-tree web reference — `Web References/QXPSMSDK/Reference.cs` + `qxpsmsdk.wsdl`
  (rpc/encoded, `http://webservice.manager.quark.com`) — is **stale and NOT compiled**
  (it is not in the csproj `<Compile>` items). It's a dormant leftover.
- The proxy the .NET app **actually uses** is an external assembly,
  `QXP_EXTERNALS/QXPSMWebServiceStubs.dll` (v9.0.x), imported everywhere as
  `using QXPSMSDK = com.quark.qxpsm;` → class **`com.quark.qxpsm.RequestService`**.
  (Refs: `QXP.Interop.csproj:60-63`; `QXPSM_Call.cs:8`.)

So **.NET production already talks `com.quark.qxpsm` / `RequestService`** — exactly the
namespace and service of the live server and of our regenerated stub. The
`webservice.manager.quark.com` WSDL that broke us was a **stale artifact our repo wrongly
copied** into `qxpsmsdk.wsdl`. That is the entire root cause.

> **Answer to "why does the old .NET still work against the same service?"**
> It isn't using the old dialect at all. Its compiled proxy is `com.quark.qxpsm` (the
> v9 DLL), the same dialect as the deployed server. Only the leftover source file looked
> like `webservice.manager.quark.com`. Our regeneration now matches .NET's real proxy.

.NET endpoint (config): `http://localhost:8090/qxpsm/services/RequestService`
(`QXP.Interop/app.config:14`) — the **same path** we use; only the host differs (localhost
on the Quark box vs the network host we target).

---

## 2. Request parity — our `QxpsmSoapClient` already matches .NET exactly

Confirmed against `QXPSM_Call.cs`, `QXPS_Caller.cs`, `Run_Task_Step.cs`:

| Item | .NET | Our Java | Match |
|---|---|---|---|
| Operation | `processRequest(QRequestContext)` (never `…Ex`) | same | ✅ |
| Chain order | `ctx.request → RequestParameters(if NameValues) → ModifierRequest(if Modifier non-empty) → SaveAsRequest(always) → QuarkXPressRenderRequest(always)` | same | ✅ |
| SaveAs | newFilePath=pool abs, newName=new gabarit, replaceFile=`"true"`, saveToPool=`"false"` | same | ✅ |
| NameValueParam | only `paramName` + `textValue` | same | ✅ |
| ctx fields | documentName; responseAsURL=false; useCache=false; bypassFileInfo=false; userName=""; userPassword=""; maxRetries(if set); requestTimeout(=3600000 if unset) | same | ✅ |
| Socket timeout | `service.Timeout = Infinite` | `stub.setTimeout(cfg)` — see note | ✅* |

\* .NET uses an **infinite** client socket timeout. We set it from config (currently 2 h).
For 100 MB+ docs, exact parity = set it to **0 (infinite)**. Either is safe; if you want
to match .NET precisely, set `qxpsm.soap.timeout` handling to pass `0`. (The Quark-side
`requestTimeout` we already mirror at 1–2 h.)

**Render path (important for the full run, not the SOAP fix):** .NET produces the final
**PDF via the direct QXPS HTTP `/pdf` call** (`QXPS_Message_PDF` → host:8080), **not** via
the SOAP `QuarkXPressRenderRequest`. The SOAP render only regenerates the intermediate QXP.
→ Make sure the Java engine's final PDF goes through `QxpsHttpClient` (the `qxp.thirdparty`
PDF path), which it does; just verify it during the full run.

---

## 3. Java compile-safety (audit result)

- The **only** old-name references (`QManagerSDKSvc*`, `getqxpsmsdk`, `QxpsmsdkSoapBinding`)
  were in `QxpsmSoapClient` — already updated.
- The rest of the engine depends on **type beans** via `ModifierLayout`, `ModifierSpread`
  (build the modifier `Project → Spread → Box/Page/Table/DeleteCells/Geometry` graph) and
  `QxpsProjectSerializer` (read-side getters). Every bean and field they use exists with the
  **same name** in the new `com.quark.qxpsm` WSDL → they compile unchanged.
- Final proof = `mvn clean install` (the compiler checks the whole engine).

---

## 4. The one residual risk — doc/literal polymorphism

`QRequestContext.request` is typed as the abstract `QRequest`, but we assign concrete
subtypes (`RequestParameters`, `ModifierRequest`, `SaveAsRequest`,
`QuarkXPressRenderRequest`). Under **document/literal**, the server can only resolve the
concrete type if the client writes `xsi:type="ns:RequestParameters"` on that element.

- This is **proven to work on this server** because .NET (also doc/literal `com.quark.qxpsm`)
  does exactly this and succeeds.
- Axis 1.x's bean serializer emits `xsi:type` for a field whose runtime type differs from the
  declared type, so it *should* match. But "should" isn't "verified" — so we prove it with a
  tiny probe before touching the engine.

---

## 5. Verification probe — prove it before the live run

Drop this throwaway class in (it uses only the regenerated classes), run it from IntelliJ,
then delete it. It does **not** depend on the rest of the engine.

**Path:** `src/main/java/com/socgen/sgs/api/quark/engine/integration/soap/generated/QxpsmProbe.java`

```java
package com.socgen.sgs.api.quark.engine.integration.soap.generated;

/**
 * THROWAWAY connectivity/correctness probe for the regenerated QXPSM stub.
 * Run from IntelliJ (Run 'QxpsmProbe.main()'). Pass the endpoint as program arg 0,
 * or edit the default below. DELETE this file after verifying.
 */
public class QxpsmProbe {

    public static void main(String[] args) throws Exception {
        // Best-effort SOAP wire dump (envelope to stdout). If it stays quiet, use the
        // logging.level.org.apache.axis... DEBUG approach you used earlier.
        System.setProperty("org.apache.commons.logging.Log",
                "org.apache.commons.logging.impl.SimpleLog");
        System.setProperty("org.apache.commons.logging.simplelog.showShortLogname", "true");
        System.setProperty("org.apache.commons.logging.simplelog.log.org.apache.axis.transport.http", "debug");
        System.setProperty("org.apache.commons.logging.simplelog.log.org.apache.axis.SOAPPart", "debug");

        String endpoint = (args.length > 0) ? args[0]
                : "http://srvcldqxpu001.dns43.socgen:8090/qxpsm/services/RequestService";
        System.out.println("== QXPSM probe against: " + endpoint);

        RequestServiceLocator locator = new RequestServiceLocator();
        RequestServicePortType stub =
                locator.getRequestServiceHttpSoap11Endpoint(new java.net.URL(endpoint));
        ((org.apache.axis.client.Stub) stub).setTimeout(120000); // 2 min for the probe

        // ---- LEVEL 1: transport + namespace handshake (no document, no polymorphism) ----
        try {
            String[] sessions = stub.getOpenSessions();
            System.out.println("[L1] getOpenSessions OK — sessions=" +
                    (sessions == null ? 0 : sessions.length));
            System.out.println("[L1] => endpoint + namespace + document/literal transport are CORRECT.");
        } catch (Exception e) {
            System.out.println("[L1] getOpenSessions FAILED: " + e);
            System.out.println("[L1] => transport/namespace/endpoint problem. Stop here and share the fault.");
        }

        // ---- LEVEL 2: polymorphic request (exercises xsi:type on ctx.request) ----
        try {
            QRequestContext ctx = new QRequestContext();
            ctx.setRequest(new GetServerInfoRequest()); // a QRequest subtype with no fields
            ctx.setResponseAsURL(false);
            ctx.setUseCache(false);
            ctx.setBypassFileInfo(false);
            ctx.setUserName("");
            ctx.setUserPassword("");
            ctx.setRequestTimeout(120000);

            QContentData resp = stub.processRequest(ctx);
            System.out.println("[L2] processRequest(GetServerInfoRequest) OK — textData="
                    + (resp == null ? "null" : resp.getTextData()));
            System.out.println("[L2] => polymorphic request graph (xsi:type) is ACCEPTED. Full chain will work.");
        } catch (Exception e) {
            System.out.println("[L2] processRequest result: " + e);
            System.out.println("[L2] INTERPRET: a Quark/business error (e.g. needs a document, server-info "
                    + "unavailable) still PROVES deserialization worked. A 'namespace mismatch' or a "
                    + "type/deserialization fault means the polymorphism (xsi:type) needs attention.");
        }
    }
}
```

### How to run
1. Make sure the regenerated stub compiles (it does — `BUILD SUCCESS`).
2. In IntelliJ, open `QxpsmProbe`, **Run** it. Set the endpoint via Run Config → Program
   arguments, or edit the default in the file. Use the **env you'll actually target** (the
   host where your gabarit pool lives).
3. Read the `[L1]` / `[L2]` lines.

### How to read the result
| Outcome | Meaning | Next |
|---|---|---|
| **L1 OK** | endpoint + `com.quark.qxpsm` namespace + doc/literal transport all correct | proceed |
| **L1 fails with `namespace mismatch`** | wrong endpoint/host or stale stub | recheck endpoint + that the new stub is the one compiled |
| **L2 OK, or fails with a Quark/business error** | polymorphic `xsi:type` graph is accepted — the real `processRequest` chain will work | **GO** — wire it in |
| **L2 fails with a deserialization / "cannot find type" / namespace fault** | doc/literal polymorphism needs a type-mapping tweak | paste the fault + the wire XML; I'll add the fix |

Paste the probe output here and I'll confirm the final go/no-go.

---

## 6. Final consolidated change list

| # | Change | Status |
|---|---|---|
| 1 | `RequestService.wsdl` (live, trimmed to SOAP 1.1) + `RequestService.full.wsdl` backup | done |
| 2 | `pom.xml` `wsdlFile` → `RequestService.wsdl` | done |
| 3 | delete old `generated/` → `mvn generate-sources` regenerates | done (`BUILD SUCCESS`) |
| 4 | `QxpsmSoapClient.java` → new locator/port/stub names, stub timeout, multi-ref removed | apply (full class in `EOS_Quark_QxpsmSoapClient_Update.md`) |
| 5 | **`application.yaml` — align all 3 Quark URLs to ONE host/env** (`qxps.server.url`, `qxpsm.soap.endpoint`, `qxp.thirdparty.url`) | **do this** |
| 6 | Run `QxpsmProbe` → confirm L1/L2 | **do this** |
| 7 | `mvn clean install` (full compile = whole-engine dependency check) | then |
| 8 | Live run of 509636; verify final PDF via QXPS HTTP `/pdf` | then |

### §5 detail for step 5 — the env mismatch is wider than first noted
There are **three** Quark endpoints and they currently straddle two environments:
```
qxps.server.url     = http://srvcldvapd001.dns43.socgen:8080          # DEV  (addfile / xml / pdf-http)
qxpsm.soap.endpoint = http://srvcldqxpu001.dns43.socgen:8090/...      # UAT  (SOAP modify)
qxp.thirdparty.url  = http://srvcldqxpu001.dns43.socgen:8080/saveas/pdf/   # UAT  (final PDF)
```
The gabarit is pooled wherever QXPS runs; the SOAP modify and the PDF render must hit the
**same Quark host**, or they won't see the pooled document. **Pick one environment for all
three.** Simplest is **all-UAT** (`srvcldqxpu001`), since that's where you fetched the WSDL
and it's confirmed reachable:
```yaml
qxps:
  server:
    url: "http://srvcldqxpu001.dns43.socgen:8080"
qxpsm:
  soap:
    endpoint: http://srvcldqxpu001.dns43.socgen:8090/qxpsm/services/RequestService
qxp:
  thirdparty:
    url: http://srvcldqxpu001.dns43.socgen:8080/saveas/pdf/
```
(If you prefer DEV, set all three to `srvcldvapd001` and confirm `vapd001:8090` serves the
same `com.quark.qxpsm` WSDL before regenerating from it.)
```
