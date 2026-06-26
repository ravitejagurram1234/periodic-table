# EOS Quark — QxpsmSoapClient update (new doc/literal stub)

**Date:** 2026-06-26
**Context:** the QXPSM stub was regenerated from the deployed server's live WSDL
(`RequestService.wsdl`, document/literal, namespace `http://com.quark.qxpsm`). This
updates `QxpsmSoapClient` to the new generated class names. **No business logic changes
— the request graph sent to the server is identical to .NET.**

---

## 1. Why the WSDL is different (cross-verified)

| Aspect | OLD `qxpsmsdk.wsdl` (previous stub) | NEW live `RequestService.wsdl` |
|---|---|---|
| `targetNamespace` | `http://webservice.manager.quark.com` | `http://com.quark.qxpsm` |
| binding `style` | `rpc` | `document` |
| body `use` | `encoded` | `literal` |
| portType | `QManagerSDKSvc` | `RequestServicePortType` |
| binding | `qxpsmsdkSoapBinding` | `RequestServiceSoap11Binding` |
| service | `QManagerSDKSvcService` | `RequestService` |
| port | `qxpsmsdk` | `RequestServiceHttpSoap11Endpoint` |

The deployed Quark Manager (UAT/DEV) is a newer Axis2 service. The old WSDL matched the
Quark instance .NET talks to; the deployed one we call speaks document/literal. The data
model (`QRequestContext`, `RequestParameters`, `NameValueParam`, `ModifierRequest`,
`SaveAsRequest`, `QuarkXPressRenderRequest`, `Project`, `QContentData`) is the same in both
— same fields — so the request-building logic is unchanged.

**Generated method signatures (confirmed):**
- `RequestServiceLocator.getRequestServiceHttpSoap11Endpoint(URL) → RequestServicePortType`
- `RequestServicePortType.processRequest(QRequestContext) → QContentData`
- `RequestServicePortType.getXPressDOM(String) → Project`

These match the existing calls exactly — only the locator/interface names change. Also added:
the Axis client **socket timeout** (from config; `0` = infinite, matching .NET
`_sdk_service.Timeout = Timeout.Infinite`) for long calls on 100 MB+ documents. The old
multi-ref `_setProperty(... PROP_DOMULTIREFS ...)` is removed (moot under document/literal).

---

## 2. Full class — copy-paste over `QxpsmSoapClient.java`

Path:
`src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxpsm/QxpsmSoapClient.java`

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
            // Get the Axis-generated stub (regenerated from the live document/literal WSDL).
            RequestServiceLocator locator = new RequestServiceLocator();
            RequestServicePortType stub =
                    locator.getRequestServiceHttpSoap11Endpoint(new URL(qxpsmProperties.getEndpoint()));

            // Long QXPSM modify/render calls on large (100 MB+) docs: set the Axis client socket
            // timeout from config (ms); 0 = infinite, matching .NET (_sdk_service.Timeout = Infinite).
            int stubTimeoutMs = qxpsmProperties.getTimeout();
            ((org.apache.axis.client.Stub) stub).setTimeout(stubTimeoutMs > 0 ? stubTimeoutMs : 0);

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

---

## 3. Don't forget the endpoint host (env mismatch)

In `application.yaml`, `qxpsm.soap.endpoint` must point at the **same Quark host** as
`qxps.server.url` (so the SOAP modify sees the pooled document). Current QXPS is DEV
(`srvcldvapd001:8080`), so:

```yaml
qxpsm:
  soap:
    endpoint: http://srvcldvapd001.dns43.socgen:8090/qxpsm/services/RequestService
```

(Or standardise both on UAT — but keep QXPS and QXPSM on one host.)

---

## 4. Build (authoritative dependency check)

```powershell
mvn clean install
```

The full compile is the real check for "any other code that depended on the old stub
names." If it's `BUILD SUCCESS`, nothing else referenced the old `QManagerSDKSvc*` classes.
If there are compile errors, they point exactly at the remaining references to fix.

---

## 5. Files in this change

| File | Change |
|---|---|
| `src/main/resources/wsdl/RequestService.wsdl` | NEW — live WSDL, trimmed to the SOAP 1.1 binding/port |
| `src/main/resources/wsdl/RequestService.full.wsdl` | NEW — untouched vendor original (reference) |
| `src/main/resources/wsdl/qxpsmsdk.wsdl` | obsolete (no longer referenced by the build) |
| `pom.xml` | `wsdlFile` → `RequestService.wsdl` |
| `src/main/java/.../integration/soap/generated/` | regenerated from the new WSDL |
| `.../infra/interop/qxpsm/QxpsmSoapClient.java` | new locator/port/stub names; stub timeout added; multi-ref removed |
| `application.yaml` | `qxpsm.soap.endpoint` → same host as QXPS |
```
