# EOS Quark — QXPSM SOAP Fix: SINGLE SOURCE OF TRUTH

**Date:** 2026-06-26
**This document supersedes and consolidates:**
`EOS_Quark_QxpsmSoap_MultiRef_Fix.md` (obsolete — wrong hypothesis),
`EOS_Quark_QXPSM_WSDL_Fix.md`, `EOS_Quark_QxpsmSoapClient_Update.md`,
`EOS_Quark_QXPSM_Correctness_Verification.md`.
Follow **only this file**.

---

## A. What was wrong (one paragraph)

The QXPSM SOAP call failed with `namespace mismatch require http://com.quark.qxpsm found
http://webservice.manager.quark.com`. Root cause: our stub was generated from the wrong
WSDL (`qxpsmsdk.wsdl`, rpc/encoded, `webservice.manager.quark.com`) — a **stale, never-compiled
leftover** copied from the .NET source. The **deployed** QXPSM (and the proxy .NET actually
runs, from `QXPSMWebServiceStubs.dll`) is **Axis2, document/literal, namespace
`com.quark.qxpsm`, service `RequestService`**. Fix = regenerate the stub from the live WSDL
and update the client to the new class names. (Also: all three Quark URLs must point at one
environment.)

This is a **faithful** match to .NET — same request graph, same operation; only the wire
dialect/class names follow the deployed server, which .NET's real proxy already does.

---

## B. STATUS — what's done vs pending

| # | Step | Status |
|---|---|---|
| 1 | Fetch live WSDL → `RequestService.wsdl` (+ `RequestService.full.wsdl` backup) | ✅ done |
| 2 | Trim WSDL to the SOAP 1.1 binding/port only | ✅ done |
| 3 | `pom.xml` `wsdlFile` → `RequestService.wsdl` | ✅ done |
| 4 | Delete old `generated/`, `mvn generate-sources` regenerates | ✅ done (BUILD SUCCESS) |
| 5 | Update `QxpsmSoapClient.java` (new names, stub timeout, no multi-ref) | ✅ done (verified correct) |
| 6 | `application.yaml`: `qxps` + `qxpsm` on same host (DEV) | ✅ done |
| 7 | `application.yaml`: `qxp.thirdparty.url` → same host (DEV) | ⬜ **pending** (§D) |
| 8 | Add + run `QxpsmProbe` to verify server contract | ⬜ **pending** (§E) |
| 9 | `mvn clean install` (full compile = whole-engine check) | ⬜ pending (§F) |
| 10 | Live run of 509636; remove temp Axis DEBUG logging | ⬜ pending (§G) |

You are at **step 7/8**.

---

## C. Files changed (reference)

| File | Change |
|---|---|
| `src/main/resources/wsdl/RequestService.wsdl` | NEW — live WSDL, trimmed to SOAP 1.1 |
| `src/main/resources/wsdl/RequestService.full.wsdl` | NEW — untouched vendor original |
| `src/main/resources/wsdl/qxpsmsdk.wsdl` | obsolete (no longer referenced) |
| `pom.xml` | `wsdlFile` → `RequestService.wsdl` |
| `src/main/java/.../integration/soap/generated/` | regenerated (RequestService, RequestServiceLocator, RequestServicePortType, RequestServiceSoap11BindingStub, + type beans) |
| `.../infra/interop/qxpsm/QxpsmSoapClient.java` | new locator/port/stub names; stub timeout; multi-ref removed |
| `src/main/resources/application.yaml` | 3 Quark URLs aligned to one host; (temp) Axis DEBUG logging |

---

## D. Step 7 — finish the environment alignment (`application.yaml`)

All three Quark endpoints must be on the **same host**, or the SOAP modify / PDF render
won't see the pooled document. You've already set `qxps` and `qxpsm` to DEV
(`srvcldvapd001`). Make the PDF URL match:

```yaml
qxp:
  thirdparty:
    url: http://srvcldvapd001.dns43.socgen:8080/saveas/pdf/   # was srvcldqxpu001 (UAT)

qxps:
  server:
    url: "http://srvcldvapd001.dns43.socgen:8080"             # DEV (already set)

qxpsm:
  soap:
    endpoint: http://srvcldvapd001.dns43.socgen:8090/qxpsm/services/RequestService  # DEV (already set)
```

> Not needed for the probe (the probe only hits `qxpsm`), but required before the full run.
> Keep the `logging.level.org.apache.axis.transport.http: DEBUG` block for now — it dumps
> the SOAP envelope during the probe. Remove it in step 10.

---

## E. Step 8 — verify the server contract with `QxpsmProbe`

This proves, **before** the live run, that the regenerated stub talks to the server
correctly — including the one residual risk: **document/literal polymorphism** (the
`QRequestContext.request` field is the abstract `QRequest` holding a concrete subtype, so
the client must emit `xsi:type` for the server to resolve it). .NET does this and works;
the probe confirms our Axis stub does too.

### E.1 — Create this throwaway class (delete after)

**Path:** `src/main/java/com/socgen/sgs/api/quark/engine/integration/soap/generated/QxpsmProbe.java`

```java
package com.socgen.sgs.api.quark.engine.integration.soap.generated;

/**
 * THROWAWAY connectivity/correctness probe for the regenerated QXPSM stub.
 * Run from IntelliJ (Run 'QxpsmProbe.main()'). Endpoint = program arg 0, or the default below.
 * DELETE this file after verifying.
 */
public class QxpsmProbe {

    public static void main(String[] args) throws Exception {
        // Best-effort SOAP wire dump to stdout.
        System.setProperty("org.apache.commons.logging.Log",
                "org.apache.commons.logging.impl.SimpleLog");
        System.setProperty("org.apache.commons.logging.simplelog.showShortLogname", "true");
        System.setProperty("org.apache.commons.logging.simplelog.log.org.apache.axis.transport.http", "debug");
        System.setProperty("org.apache.commons.logging.simplelog.log.org.apache.axis.SOAPPart", "debug");

        String endpoint = (args.length > 0) ? args[0]
                : "http://srvcldvapd001.dns43.socgen:8090/qxpsm/services/RequestService";
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
            System.out.println("[L1] => transport/namespace/endpoint problem. Stop and share the fault.");
        }

        // ---- LEVEL 2: polymorphic request (exercises xsi:type on ctx.request) ----
        try {
            QRequestContext ctx = new QRequestContext();
            ctx.setRequest(new GetServerInfoRequest()); // a QRequest subtype, no fields
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
            System.out.println("[L2] INTERPRET: a Quark/business error (needs a document, server-info "
                    + "unavailable, etc.) still PROVES deserialization worked. A 'namespace mismatch' or a "
                    + "type/deserialization fault means polymorphism (xsi:type) needs attention.");
        }
    }
}
```

### E.2 — Run it

- **IntelliJ:** open `QxpsmProbe.java`, click ▶ next to `main` → **Run 'QxpsmProbe.main()'**.
  Endpoint via **Run → Edit Configurations → Program arguments**, or edit the default line.
- **Maven (if `exec` plugin is present):**
  ```powershell
  mvn -q compile exec:java "-Dexec.mainClass=com.socgen.sgs.api.quark.engine.integration.soap.generated.QxpsmProbe" "-Dexec.args=http://srvcldvapd001.dns43.socgen:8090/qxpsm/services/RequestService"
  ```

### E.3 — Read the result

| Outcome | Meaning | Next |
|---|---|---|
| **L1 OK** | endpoint + `com.quark.qxpsm` namespace + doc/literal transport correct | proceed |
| **L1 → `namespace mismatch`** | wrong endpoint/host, or the new stub isn't the one compiled | recheck endpoint + regen |
| **L2 OK, or fails with a Quark/business error** | polymorphic `xsi:type` graph accepted → real chain will work | **GO** |
| **L2 → deserialization / "cannot find type" / namespace fault** | doc/literal polymorphism needs a type-mapping fix | paste fault + SOAP XML |

Paste the `[L1]`/`[L2]` output (and the dumped SOAP envelope) before the full run.

---

## F. Step 9 — full build (whole-engine dependency check)

```powershell
mvn clean install
```

`BUILD SUCCESS` confirms nothing else depended on the old stub names (the modifier-graph
builders `ModifierLayout`/`ModifierSpread` and `QxpsProjectSerializer` use type beans that
are unchanged in the new WSDL, so they compile). If there are errors, paste them.

---

## G. Step 10 — live run + cleanup

1. Run **runId 509636** (Plaquette, DOCUMENT_COURANT). Expected: addfile → `/xml` → **QXPSM
   `processRequest` now accepted** → SaveAs → final PDF via QXPS HTTP `/pdf`.
   (Note: .NET produces the final PDF via the **direct QXPS HTTP `/pdf`** call, not via the
   SOAP render — confirm the Java engine's PDF step uses the `qxp.thirdparty` path.)
2. Delete `src/main/java/.../integration/soap/generated/QxpsmProbe.java`.
3. Remove the temp logging from `application.yaml`:
   ```yaml
   logging:
     level:
       org.apache.axis.transport.http: DEBUG   # <-- delete this block
   ```

---

## H. Reference — final `QxpsmSoapClient.java` (already applied & verified)

This is the version you have; included here so this doc is self-contained.

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxpsm;

import com.socgen.sgs.api.quark.engine.integration.soap.generated.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.net.URL;
import java.util.List;

/**
 * SOAP client for communicating with QuarkXPress Server Manager (QXPSM).
 * Uses the Axis 1.x generated stub (regenerated from the deployed server's
 * document/literal WSDL — service RequestService, namespace http://com.quark.qxpsm)
 * to call processRequest / getXPressDOM.
 *
 * <p>Used for UPDATE steps (directCall=false) where text value changes
 * and structural modifications are sent via SOAP.
 *
 * <p>Request chain built inside QRequestContext:
 * RequestParameters → ModifierRequest → SaveAsRequest → QuarkXPressRenderRequest
 * (each linked via the inherited QRequest.request field)
 *
 * Cross-reference: .NET QXPSM_Call.SDKCall() / QXPS_Caller.Execute()
 */
@Component
@Slf4j
public class QxpsmSoapClient {

    private final QxpsmProperties qxpsmProperties;

    public QxpsmSoapClient(QxpsmProperties qxpsmProperties) {
        this.qxpsmProperties = qxpsmProperties;
    }

    public QContentData executeStep(String documentName,
                                    List<NameValueParam> nameValues,
                                    Project project,
                                    String saveAsPath,
                                    String saveAsName) {
        log.info("QXPSM SOAP processRequest for document [{}]", documentName);

        try {
            // Get the Axis-generated stub (regenerated from the live document/literal WSDL).
            RequestServiceLocator locator = new RequestServiceLocator();
            RequestServicePortType stub =
                    locator.getRequestServiceHttpSoap11Endpoint(new URL(qxpsmProperties.getEndpoint()));

            // Long QXPSM modify/render calls on large (100 MB+) docs: set the Axis client socket
            // timeout from config (ms); 0 = infinite, matching .NET (_sdk_service.Timeout = Infinite).
            int stubTimeoutMs = qxpsmProperties.getTimeout();
            ((org.apache.axis.client.Stub) stub).setTimeout(stubTimeoutMs > 0 ? stubTimeoutMs : 0);

            // Build the request chain (last → first, then link)
            QuarkXPressRenderRequest qxpRender = new QuarkXPressRenderRequest();

            SaveAsRequest saveAs = new SaveAsRequest();
            saveAs.setNewFilePath(saveAsPath);
            saveAs.setNewName(saveAsName);
            saveAs.setReplaceFile("true");
            saveAs.setSaveToPool("false");
            saveAs.setRequest(qxpRender);

            QRequest currentHead = saveAs;
            if (project != null && project.getLayouts() != null && project.getLayouts().length > 0) {
                ModifierRequest modifier = new ModifierRequest();
                modifier.setProject(project);
                modifier.setRequest(saveAs);
                currentHead = modifier;
            }

            if (nameValues != null && !nameValues.isEmpty()) {
                RequestParameters params = new RequestParameters();
                params.setParams(nameValues.toArray(new NameValueParam[0]));
                params.setRequest(currentHead);
                currentHead = params;
            }

            QRequestContext context = new QRequestContext();
            context.setDocumentName(documentName);
            context.setRequest(currentHead);
            context.setResponseAsURL(false);
            context.setUseCache(false);
            context.setBypassFileInfo(false);
            context.setUserName("");
            context.setUserPassword("");
            if (qxpsmProperties.getMaxRetries() > 0) {
                context.setMaxRetries(qxpsmProperties.getMaxRetries());
            }
            int timeout = qxpsmProperties.getTimeout();
            context.setRequestTimeout(timeout > 0 ? timeout : 3600 * 1000);

            log.debug("QXPSM calling processRequest with chain: {} → ... → QXPRender",
                    currentHead.getClass().getSimpleName());

            QContentData result = stub.processRequest(context);

            log.info("QXPSM processRequest completed for document [{}]", documentName);
            return result;

        } catch (Exception e) {
            log.error("QXPSM SOAP call failed for document [{}]: {}", documentName, e.getMessage(), e);
            throw new RuntimeException("QXPSM SOAP call failed for document: " + documentName, e);
        }
    }

    public Project getProject(String documentName) {
        log.info("QXPSM getXPressDOM for document [{}]", documentName);
        try {
            RequestServiceLocator locator = new RequestServiceLocator();
            RequestServicePortType stub =
                    locator.getRequestServiceHttpSoap11Endpoint(new URL(qxpsmProperties.getEndpoint()));
            return stub.getXPressDOM(documentName);
        } catch (Exception e) {
            log.error("QXPSM getXPressDOM failed for document [{}]: {}", documentName, e.getMessage(), e);
            throw new RuntimeException("QXPSM getXPressDOM failed for document: " + documentName, e);
        }
    }
}
```
