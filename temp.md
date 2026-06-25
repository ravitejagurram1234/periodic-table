# EOS Quark — QXPSM SOAP fix: disable Axis multi-ref (+ temp wire debug)

Next step after the buffer fix. The live run now reaches the **QXPSM SOAP update step** and fails there:
```
AxisFault: namespace mismatch require http://com.quark.qxpsm found http://webservice.manager.quark.com
```

## Diagnosis (why)
- Namespace **and** endpoint match the **working .NET** client exactly:
  `http://webservice.manager.quark.com` + `…:8090/qxpsm/services/RequestService`.
- `http://com.quark.qxpsm` is in **none** of our WSDL / stub / config — it appears only in the server's
  **fault response** at runtime. So the **server is faulting on our request**, and Axis then chokes parsing
  that fault.
- The request is a chained object graph (`RequestParameters → Modifier → SaveAs → QXPRender`, linked via
  `QRequestContext.request`). **Axis 1.x defaults to SOAP multi-reference encoding** (`id=`/`href=` pointers);
  **.NET inlines** everything. Quark's server expects the inlined form and rejects Axis's multi-ref XML.
  → Same namespace, same endpoint, only the request *shape* differs. Classic Axis↔.NET RPC/encoded break.

> Environment note: the legacy .NET client and Quark run on the **same Windows host**; this Java app runs
> locally (and later in the cloud). This issue is **serialization-level**, independent of where the client
> runs — the fix carries to the cloud unchanged.

---

## STEP 1 — Confirm with a temporary wire log (yaml only; delete afterwards)

Add to your active profile yaml (e.g. `src/main/config/local/application.yaml` or `application.yaml`):
```yaml
logging:
  level:
    # TEMP-DEBUG-RT: dump the raw SOAP request + response/fault to confirm multi-ref. REMOVE after diagnosis.
    org.apache.axis.transport.http: DEBUG
```
Re-run `runId 509636` and inspect the **outgoing** SOAP request in the console:
- If you see attributes like `href="#id0"` and elements carrying `id="id0"` → **multi-ref confirmed** (apply Step 2).
- You'll also see the server's real fault text, in case it's something else.

*(Tip: if console DEBUG is too noisy or the envelope isn't clearly printed, run `org.apache.axis.utils.tcpmon`
or Fiddler as a local proxy to capture the exact request/response XML.)*

---

## STEP 2 — The fix: disable Axis multi-ref (one statement in `QxpsmSoapClient`)

Right after the stub is created in `executeStep(...)`:
```java
QManagerSDKSvc stub = locator.getqxpsmsdk(new URL(qxpsmProperties.getEndpoint()));

// Axis 1.x defaults to SOAP multi-reference encoding (id=/href=) for object graphs, which the QuarkXPress
// Manager server rejects (it expects values inlined). Disable multi-ref to match the legacy client.
((org.apache.axis.client.Stub) stub)._setProperty(
        org.apache.axis.AxisEngine.PROP_DOMULTIREFS, Boolean.FALSE);
```
`QxpsmsdkSoapBindingStub extends org.apache.axis.client.Stub`, so the cast is safe. Fully-qualified names are
used so no new imports are needed.

### Full file — `infra/interop/qxpsm/QxpsmSoapClient.java`
```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxpsm;

import com.socgen.sgs.api.quark.engine.integration.soap.generated.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.net.URL;
import java.util.List;

/**
 * SOAP client for communicating with QuarkXPress Server Manager (QXPSM).
 * Uses the Axis 1.x generated stub to call processRequest.
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

    /**
     * Execute a complete step via SOAP using the Axis-generated stub.
     * Builds the QRequest chain and calls processRequest on the QXPSM web service.
     *
     * @param documentName  the current document name in the pool
     * @param nameValues    name-value params to set (may be null or empty)
     * @param project       modification project (may be null if no structural changes)
     * @param saveAsPath    path for saving (e.g., pool absolute path)
     * @param saveAsName    new file name for the saved document
     * @return QContentData response containing streamValue (QXP binary) and/or textData
     */
    public QContentData executeStep(String documentName,
                                    List<NameValueParam> nameValues,
                                    Project project,
                                    String saveAsPath,
                                    String saveAsName) {
        log.info("QXPSM SOAP processRequest for document [{}]", documentName);

        try {
            // Get the Axis-generated stub
            QManagerSDKSvcServiceLocator locator = new QManagerSDKSvcServiceLocator();
            QManagerSDKSvc stub = locator.getqxpsmsdk(new URL(qxpsmProperties.getEndpoint()));

            // The request is an object graph (RequestParameters -> Modifier -> SaveAs -> QXPRender chained via
            // QRequestContext.request). Axis 1.x defaults to SOAP multi-reference encoding (id=/href= pointers),
            // which the QuarkXPress Manager server does not accept (it expects the values inlined). Disable
            // multi-ref so the request is serialized inline, matching the request the legacy client sends.
            ((org.apache.axis.client.Stub) stub)._setProperty(
                    org.apache.axis.AxisEngine.PROP_DOMULTIREFS, Boolean.FALSE);

            // Build the request chain (last → first, then link)
            // 4. QXP Render (last in chain)
            QuarkXPressRenderRequest qxpRender = new QuarkXPressRenderRequest();

            // 3. SaveAs → chains to QXP Render
            SaveAsRequest saveAs = new SaveAsRequest();
            saveAs.setNewFilePath(saveAsPath);
            saveAs.setNewName(saveAsName);
            saveAs.setReplaceFile("true");
            saveAs.setSaveToPool("false");
            saveAs.setRequest(qxpRender);

            // 2. Modifier → chains to SaveAs (only if project has modifications)
            QRequest currentHead = saveAs;
            if (project != null && project.getLayouts() != null && project.getLayouts().length > 0) {
                ModifierRequest modifier = new ModifierRequest();
                modifier.setProject(project);
                modifier.setRequest(saveAs);
                currentHead = modifier;
            }

            // 1. RequestParameters → chains to Modifier or SaveAs (only if there are name-values)
            if (nameValues != null && !nameValues.isEmpty()) {
                RequestParameters params = new RequestParameters();
                params.setParams(nameValues.toArray(new NameValueParam[0]));
                params.setRequest(currentHead);
                currentHead = params;
            }

            // Build QRequestContext — set the same fields as .NET QXPSM_Call.InitContext.
            QRequestContext context = new QRequestContext();
            context.setDocumentName(documentName);
            context.setRequest(currentHead);
            // .NET QXPS_Call_Info defaults (set explicitly to document intent / match the wire).
            context.setResponseAsURL(false);
            context.setUseCache(false);
            context.setBypassFileInfo(false);
            // .NET leaves credentials as string.Empty (serialized as empty elements, not nil). Finding #66.
            context.setUserName("");
            context.setUserPassword("");
            // .NET does not set MaxRetries at runtime — leave the SDK default unless explicitly configured
            // (>0). Finding #33.
            if (qxpsmProperties.getMaxRetries() > 0) {
                context.setMaxRetries(qxpsmProperties.getMaxRetries());
            }
            // .NET: if no timeout is configured, use 3600s (1h) instead of the SOAP default of 100s.
            int timeout = qxpsmProperties.getTimeout();
            context.setRequestTimeout(timeout > 0 ? timeout : 3600 * 1000);

            // Execute SOAP call
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

    /**
     * Fetch the QuarkXPress DOM (Project) of a pooled document via getXPressDOM.
     * Used to read a child run's generated QXP structure for compartiment incorporation.
     *
     * <p>Cross-reference: .NET QXPS_File_Manager.Get_Project / Document.QXPProject.
     * NOTE: this is a live QuarkXPress Server Manager call — must be validated against a running server.
     *
     * @param documentName the pool path / document name of the saved QXP
     * @return the QuarkXPress DOM as a SOAP Project
     */
    public Project getProject(String documentName) {
        log.info("QXPSM getXPressDOM for document [{}]", documentName);
        try {
            QManagerSDKSvcServiceLocator locator = new QManagerSDKSvcServiceLocator();
            QManagerSDKSvc stub = locator.getqxpsmsdk(new URL(qxpsmProperties.getEndpoint()));
            return stub.getXPressDOM(documentName);
        } catch (Exception e) {
            log.error("QXPSM getXPressDOM failed for document [{}]: {}", documentName, e.getMessage(), e);
            throw new RuntimeException("QXPSM getXPressDOM failed for document: " + documentName, e);
        }
    }
}
```

---

## STEP 3 — Rebuild, re-run, verify, clean up
1. `mvn clean install`
2. Re-run a Plaquette `runId` (ideally one **with** SQL/System tasks so an update step fires).
3. Expect the QXPSM `processRequest` to succeed (no `AxisFault`); the run should proceed to render/EndRun.
4. **Remove the `TEMP-DEBUG-RT` logging block** from Step 1.

## If it still fails after Step 2 (fallback)
The wire log decides the next move:
- Multi-ref gone but server still faults → capture **.NET's** outgoing SOAP request (Fiddler/tcpmon on the
  Windows host where .NET works) and **diff** it against the Java request. Likely secondary differences:
  - `xsi:type` attributes — suppress with
    `((org.apache.axis.client.Stub) stub)._setProperty(org.apache.axis.client.Call.SEND_TYPE_ATTR, Boolean.FALSE);`
  - empty vs nil elements (e.g. `userName`/`userPassword`), element ordering, or SOAP 1.1 vs 1.2.
- Share the captured request + fault and I'll pinpoint the exact remaining difference.

## Apply checklist
- [ ] STEP 1: add `TEMP-DEBUG-RT` Axis DEBUG logging (yaml), re-run, confirm multi-ref in the request
- [ ] STEP 2: `QxpsmSoapClient` multi-ref disable
- [ ] `mvn clean install` + re-run + verify QXPSM succeeds
- [ ] STEP 3: remove the temp logging block
