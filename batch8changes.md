# EOS Quark Engine — Batch 8 Changes
**Theme: per-run pool isolation + QXPS/QXPSM wire & config parity**

_Snippets for the large `QxpsCallerBusiness`; whole-file for the small QXPSM/HTTP/config files._

## Findings fixed (10) + 1 flagged deviation
| # | Sev | Fix |
|---|---|---|
| 27/31 | HIGH/MED | Modify XML now uploaded+referenced under `R_<runId>/Modify_*.xml` (per-run isolation) via `getPoolPath` |
| 11 | HIGH | QXPSM request timeout default 30s → **1h** in application.yaml (matches .NET effective budget; code already had the 1h fallback) |
| 33 | MEDIUM | `maxRetries` default 3 → **0**, and `setMaxRetries` only when >0 (leave SDK default, matching .NET) |
| 62 | LOW | Modify timestamp `HHmmssSSS` → `HHmmssSS` (.NET `HHmmssff`, 2 fraction digits) |
| 63 | LOW | Response text/binary now uses **exact** content-type match (mirrors .NET `switch(ContentType)`), not `startsWith` |
| 64 | LOW | HTTP client `keepAlive(false)` to mimic .NET HTTP/1.0 connection-close (body already fixed-length, not chunked) |
| 66 | LOW | `QRequestContext.userName/userPassword` set to `""` (empty elements, not nil) — matches .NET `string.Empty` |
| 68 | LOW | Removed never-applied `namespace`/`connectionTimeout`/`retryBackoffInterval` from properties + yaml |
| 32 | MEDIUM | `ParamsValueMessage` null `textValue` → `""` (not the literal "null") |

## ⚠️ #67 — flagged deviation (Java architecture, no code change)
`#67` asks that `getProject` flip the document to **mode-degrade** on a DOM-fetch failure (mirroring .NET `Document.QXPProject` which sets `_mode_degrade=true` only in its catch). This is **not replicated**, for two structural reasons in the Java port:
1. `GetDocumentProjectBusiness` is a **stateless bridge** that takes a `documentName` (String) — it has no handle on the `DocumentDomain` to flip.
2. Java models mode-degrade on `RunProperties` (per-run), not per-`DocumentDomain`, so there is no per-document degrade flag to set (.NET sets it on the Document).
The **functional outcome is preserved**: a DOM-fetch failure returns `QxpProject.EMPTY`, which `CompartimentTaskProcessStrategy` already reports as the empty-child error. Only the (per-document) degrade flag — which doesn't exist in the Java model — is not set. Replicating it faithfully would require introducing a per-document degrade field + threading failure-vs-empty through the bridge; flagged for your decision rather than implemented silently.

## No tests affected (grep-verified).

---

## `business/QxpsCallerBusiness.java` — snippets
**Line ~43 (timestamp format):**
```java
    // .NET uses {0:HHmmssff} (2 fractional-second digits); Java 'SS' = 2 fraction digits. Finding #62.
    private static final DateTimeFormatter TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("HHmmssSS");
```
**In `executeDirectCall`, the modify-upload block:**
```java
            byte[] modifyXml = QxpsProjectSerializer.toBytes(project);
            // Scope the modify file to the run's pool directory (R_<runId>/Modify_xxx.xml) for per-run
            // isolation, mirroring .NET GetPoolPath. Both the upload and the reference use the same
            // scoped name. Findings #27/#31.
            String modifyFileName = run.getRunProperties().getPoolPath(
                    String.format(MODIFY_NAME_PATTERN, LocalDateTime.now().format(TIMESTAMP_FORMAT)));

            qxpsHttpClient.execute(modifyFileName, new AddFileMessage(modifyXml));
            messages.add(new ModifyMessage(modifyFileName));
```

---

## `application.yaml` — qxpsm section (replace)
```yaml
qxpsm:
  soap:
    endpoint: http://srvcldqxpu001.dns43.socgen:8090/qxpsm/services/RequestService
    # 1 hour — mirrors .NET's effective request timeout for long modifier/render calls. Finding #11.
    timeout: 3600000
    # 0 = leave the SDK default (no forced retries), matching .NET. Finding #33.
    max-retries: 0
```

---

## `infra/interop/qxpsm/QxpsmProperties.java`
```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxpsm;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * Configuration properties for QXPSM SOAP endpoint.
 */
@Configuration
@ConfigurationProperties(prefix = "qxpsm.soap")
@Getter
@Setter
public class QxpsmProperties {

    private String endpoint;
    // Request timeout (ms). 0/unset → QxpsmSoapClient falls back to .NET's effective 1h budget.
    private int timeout = 30000;
    // 0 = leave the SDK default (no forced retries), matching .NET where MaxRetries is not set at runtime.
    // Finding #33.
    private int maxRetries = 0;
    // NOTE: namespace, connectionTimeout and retryBackoffInterval were removed (Finding #68) — they were
    // never applied: the namespace is fixed by the generated WSDL locator and there is no retry/backoff
    // loop. Re-add (and wire them to the Axis stub) only if those behaviours are actually implemented.
}
```

---

## `infra/interop/qxps/message/ParamsValueMessage.java`
```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

import com.socgen.sgs.api.quark.engine.integration.soap.generated.NameValueParam;
import lombok.Getter;

import java.util.ArrayList;
import java.util.List;

/**
 * QXPS GET message for setting name/value parameters on a document.
 * Each NameValueParam becomes a query parameter: paramName=textValue
 *
 * URL: {baseUrl}/{documentName}?name1=value1&name2=value2
 * NOTE: path is NULL — params go directly in the query string.
 * NOTE: This is a GET, not a POST.
 *
 * Cross-reference: .NET QXPS_Message_ParamsValue
 */
@Getter
public class ParamsValueMessage implements QxpsMessage {

    private final NameValueParam[] nameValues;

    public ParamsValueMessage(NameValueParam[] nameValues) {
        this.nameValues = nameValues != null ? nameValues : new NameValueParam[0];
    }

    @Override
    public String getCommandPath() {
        return null;
    }

    @Override
    public String getCommandQuery() {
        if (nameValues.length == 0) {
            return null;
        }
        List<String> args = new ArrayList<>();
        for (NameValueParam nv : nameValues) {
            // Coalesce a null textValue to "" to match .NET string.Format semantics (avoids the literal
            // "null" appearing in the ParamsValue query). Finding #32.
            String value = nv.getTextValue() != null ? nv.getTextValue() : "";
            args.add(nv.getParamName() + "=" + value);
        }
        return String.join("&", args);
    }

    @Override
    public byte[] getData() {
        return null;
    }

    @Override
    public boolean isPost() {
        return false;
    }

    @Override
    public MessagePriority getPriority() {
        return MessagePriority.BELOW_NORMAL;
    }
}
```

---

## `infra/interop/qxpsm/QxpsmSoapClient.java` — snippet (context build)
```java
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
```

---

## `infra/interop/qxps/client/QxpsHttpClient.java` — snippets
**`init()` HttpClient build:**
```java
        HttpClient httpClient = HttpClient.create()
                // Disable persistent connections to mimic .NET's HTTP/1.0 connection-close behaviour.
                .keepAlive(false)
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, timeout)
```
**`isTextContentType`:**
```java
    private boolean isTextContentType(String contentType) {
        // Exact (full-string) match, mirroring .NET's switch(response.ContentType). Finding #63.
        if (contentType == null || contentType.isEmpty()) return true;
        return TEXT_CONTENT_TYPES.contains(contentType.toLowerCase());
    }
```

## Apply checklist
- [ ] QxpsCallerBusiness (2 snippets) · application.yaml (qxpsm) · QxpsmProperties (whole) · QxpsmSoapClient (snippet) · QxpsHttpClient (2 snippets) · ParamsValueMessage (whole)
- [ ] `mvn compile` + `mvn test`
