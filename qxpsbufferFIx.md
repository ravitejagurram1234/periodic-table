# EOS Quark — Live-Run Fix: QXPS response buffer + timeout

Fixes the live `runId=509636` failure and prepares for large/slow documents. **Config lives in yaml**
(`application.yaml` / env-specific yaml); the Java classes only *bind* and *use* the values.

## What went wrong (root cause)
Every error in the run was the same:
```
DataBufferLimitException: Exceeded limit on max bytes to buffer : 262144
```
`QxpsHttpClient` built its `WebClient` with **no buffer limit**, so it used the framework default of **256 KB**.
Real QXPS responses (full document XML, rendered PDF, literal QXP binary) are **megabytes**, so the client
received the data but refused to buffer it → the XML fetch, PDF render and literal QXP fetch all failed; the
literal failure flipped the run to ERROR. (The `box=DID` fetch worked only because that XML is tiny.)
This is a missing WebClient configuration — **not** a logic/parity issue and **not** related to the B11–B13 redo.

## Two changes
1. **Response buffer** — raise the reactive codec `maxInMemorySize` (yaml: `qxps.server.max-in-memory-size-bytes`,
   default **500 MB**). QXPS `/xml` can be several× the QXP binary size, so size generously; tune per-env.
2. **Timeout** — extended **1h → 2h** for both QXPS and QXPSM (yaml). See the .NET baseline below.

### .NET timeout baseline (verified)
- **QXPSM (SOAP):** `QXPSM_Call.InitContext()` sets the client socket timeout to **`Infinite`**
  (`_sdk_service.Timeout = System.Threading.Timeout.Infinite`) with a **1-hour** server-side `requestTimeout`
  budget — comment: *"no timeout on the request (otherwise it's 100 s)."* .NET deliberately never times out the
  client on long Quark ops.
- **QXPS (HTTP):** no explicit timeout set.

So **2 hours** is a safe, finite extension above .NET's 1h budget (and safer for a Kube pod than `Infinite`).
If a very large document needs longer, just raise the yaml values — no recompile.

## Files changed
- `infra/interop/qxps/config/QxpsProperties.java` — new bound field `maxInMemorySizeBytes` (fallback only; value in yaml)
- `infra/interop/qxps/client/QxpsHttpClient.java` — wire `ExchangeStrategies` codec limit from the property (+ import)
- `application.yaml` — `qxps.server.timeout` 1h→2h, new `qxps.server.max-in-memory-size-bytes`, `qxpsm.soap.timeout` 1h→2h

---

## 1. `infra/interop/qxps/config/QxpsProperties.java` (full)
```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Getter
@Setter
@Configuration
@ConfigurationProperties(prefix = "qxps")
public class QxpsProperties {

    private Server server = new Server();
    private Pool pool = new Pool();

    @Getter
    @Setter
    public static class Server {
        private String url;
        private int timeout = 3600000;
        // Max bytes buffered for a single QXPS response (full document XML / rendered PDF / literal QXP binary).
        // The operative value is set in application.yaml (qxps.server.max-in-memory-size-bytes); this initializer
        // is only a safety fallback. QXPS /xml responses can be several times the QXP binary size, so size it large.
        private int maxInMemorySizeBytes = 524288000;
    }

    @Getter
    @Setter
    public static class Pool {
        private String defaultPath = "D:\\Documents\\";
        private String currentPath = "";
    }
}

```

## 2. `infra/interop/qxps/client/QxpsHttpClient.java` (full)
```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.client;

import com.socgen.sgs.api.quark.engine.infra.interop.qxps.config.QxpsProperties;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.exception.QxpsException;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.QxpsMessage;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsRequestInfo;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsResponseInfo;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.request.QxpsRequestBuilder;
import io.netty.channel.ChannelOption;
import io.netty.handler.timeout.ReadTimeoutHandler;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.ClientResponse;
import org.springframework.web.reactive.function.client.ExchangeStrategies;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;
import reactor.netty.http.client.HttpClient;

import jakarta.annotation.PostConstruct;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Slf4j
@Component
public class QxpsHttpClient {

    private final QxpsRequestBuilder requestBuilder;
    private final QxpsProperties qxpsProperties;
    private WebClient webClient;

    private static final Set<String> TEXT_CONTENT_TYPES = Set.of(
            "text/plain", "text/xml", "text/html", ""
    );

    public QxpsHttpClient(QxpsRequestBuilder requestBuilder, QxpsProperties qxpsProperties) {
        this.requestBuilder = requestBuilder;
        this.qxpsProperties = qxpsProperties;
    }

    @PostConstruct
    void init() {
        int timeout = qxpsProperties.getServer().getTimeout();
        HttpClient httpClient = HttpClient.create()
                // Disable persistent connections to mimic .NET's HTTP/1.0 connection-close behaviour.
                // (Reactor Netty cannot pin the protocol to HTTP/1.0; the request body is a fixed byte[]
                //  so it is sent with a Content-Length, not chunked — matching .NET. Finding #64.)
                .keepAlive(false)
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, timeout)
                .doOnConnected(conn ->
                        conn.addHandlerLast(new ReadTimeoutHandler(timeout, TimeUnit.MILLISECONDS))
                )
                .responseTimeout(Duration.ofMillis(timeout));

        // QXPS responses can be large (full document XML, rendered PDF, literal QXP binary — 100 MB+).
        // Raise the reactive codec buffer above the framework's 256 KB default so large responses are not
        // rejected with DataBufferLimitException. The limit is configured in application.yaml
        // (qxps.server.max-in-memory-size-bytes).
        int maxInMemory = qxpsProperties.getServer().getMaxInMemorySizeBytes();
        this.webClient = WebClient.builder()
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .exchangeStrategies(ExchangeStrategies.builder()
                        .codecs(configurer -> configurer.defaultCodecs().maxInMemorySize(maxInMemory))
                        .build())
                .build();
    }

    /**
     * Single-message call (standalone calls such as addfile / literal / xml / delete).
     * Cross-reference: .NET QXPS_Helper one-message QXPS_Call.SDKCall().
     */
    public QxpsResponseInfo execute(String documentName, QxpsMessage message) {
        return executeCombined(documentName, List.of(message));
    }

    /**
     * Combines several messages into ONE QuarkXPress Server URL and makes ONE HTTP call.
     * Cross-reference: .NET QXPS_Call.SDKCall() over a populated QXPS_Request_Message.
     */
    public QxpsResponseInfo executeCombined(String documentName, List<QxpsMessage> messages) {
        QxpsRequestInfo requestInfo = requestBuilder.buildCombined(documentName, messages);
        log.info("QXPS call: {} {}", requestInfo.getMethod(), requestInfo.getUri());

        try {
            if (requestInfo.getMethod() == HttpMethod.POST) {
                return executePost(requestInfo);
            }
            return executeGet(requestInfo);
        } catch (QxpsException e) {
            throw e;
        } catch (Exception e) {
            throw new QxpsException(requestInfo, e);
        }
    }

    private QxpsResponseInfo executePost(QxpsRequestInfo requestInfo) {
        byte[] multipartBody = buildMultipartBody(requestInfo.getData());
        String boundary = extractBoundary(multipartBody);

        return webClient.post()
                .uri(requestInfo.getUri())
                .header(HttpHeaders.CONTENT_TYPE, "multipart/form-data; boundary=" + boundary)
                .bodyValue(multipartBody)
                .exchangeToMono(clientResponse -> handleResponse(requestInfo, clientResponse))
                .block();
    }

    private QxpsResponseInfo executeGet(QxpsRequestInfo requestInfo) {
        return webClient.get()
                .uri(requestInfo.getUri())
                .exchangeToMono(clientResponse -> handleResponse(requestInfo, clientResponse))
                .block();
    }

    private Mono<QxpsResponseInfo> handleResponse(QxpsRequestInfo requestInfo, ClientResponse clientResponse) {
        HttpStatusCode status = clientResponse.statusCode();
        if (status.isError()) {
            return clientResponse.bodyToMono(String.class)
                    .defaultIfEmpty("")
                    .flatMap(errorBody -> Mono.error(
                            new QxpsException(requestInfo, "HTTP " + status.value() + ": " + errorBody)));
        }

        QxpsResponseInfo response = new QxpsResponseInfo();
        MediaType contentType = clientResponse.headers().contentType().orElse(null);
        String contentTypeValue = contentType != null ? contentType.toString() : "";
        response.setContentType(contentTypeValue);

        if (isTextContentType(contentTypeValue)) {
            return clientResponse.bodyToMono(String.class)
                    .defaultIfEmpty("")
                    .map(text -> { response.setTextResponse(text); return response; });
        } else {
            return clientResponse.bodyToMono(byte[].class)
                    .defaultIfEmpty(new byte[0])
                    .map(bytes -> { response.setBinaryResponse(bytes); return response; });
        }
    }

    /** Builds multipart body matching the .NET WriteMultipart format exactly. */
    private byte[] buildMultipartBody(byte[] data) {
        String boundary = UUID.randomUUID().toString();
        String header = "--" + boundary + "\r\n"
                + "Content-Disposition: form-data; name=\"file\"; filename=\"fileData.bin\"\r\n"
                + "Content-Type: binary/octet-stream\r\n"
                + "\r\n";
        String footer = "\r\n--" + boundary + "--";

        byte[] headerBytes = header.getBytes(StandardCharsets.UTF_8);
        byte[] footerBytes = footer.getBytes(StandardCharsets.UTF_8);

        byte[] body = new byte[headerBytes.length + data.length + footerBytes.length];
        System.arraycopy(headerBytes, 0, body, 0, headerBytes.length);
        System.arraycopy(data, 0, body, headerBytes.length, data.length);
        System.arraycopy(footerBytes, 0, body, headerBytes.length + data.length, footerBytes.length);

        return body;
    }

    /** Extracts the boundary string from the already-built multipart body. */
    private String extractBoundary(byte[] multipartBody) {
        String start = new String(multipartBody, 0, Math.min(200, multipartBody.length), StandardCharsets.UTF_8);
        // Body starts with "--{boundary}\r\n", so boundary is between index 2 and the first \r\n
        int endIndex = start.indexOf("\r\n");
        return start.substring(2, endIndex);
    }

    private boolean isTextContentType(String contentType) {
        // Exact (full-string) match, mirroring .NET's switch(response.ContentType) which compares the raw
        // header verbatim — e.g. "text/xml;charset=utf-8" is NOT text (falls to binary), as in .NET.
        // Finding #63.
        if (contentType == null || contentType.isEmpty()) return true;
        return TEXT_CONTENT_TYPES.contains(contentType.toLowerCase());
    }
}

```

## 3. `application.yaml` — change these two blocks

**`qxps` block** (replace):
```yaml
qxps:
  server:
    url: "http://srvcldvapd001.dns43.socgen:8080"
    # 2 hours — generous budget for long QXPS render/fetch calls on large (100 MB+) documents.
    timeout: 7200000
    # Max bytes to buffer for a single QXPS response (full document XML / rendered PDF / literal QXP binary).
    # 500 MB. The /xml response can be several times the QXP binary size; raise per-env for very large gabarits.
    max-in-memory-size-bytes: 524288000
  pool:
    default-path: "D:\\Documents\\"
    current-path: ""
```

**`qxpsm.soap.timeout`** (change the one line):
```yaml
    # 2 hours — generous budget for long modifier/render calls on large documents.
    timeout: 7200000
```

> For an **env-specific yaml** (e.g. a prod overlay), set the same keys there to override per environment —
> e.g. bump `qxps.server.max-in-memory-size-bytes` higher if a site has gabarits whose XML exceeds 500 MB.

---

## Apply checklist
- [ ] `infra/interop/qxps/config/QxpsProperties.java`
- [ ] `infra/interop/qxps/client/QxpsHttpClient.java` (incl. the new `ExchangeStrategies` import)
- [ ] `application.yaml` — qxps timeout + buffer, qxpsm timeout
- [ ] `mvn clean install`
- [ ] Re-run a Plaquette `runId` (ideally one **with** SQL/System tasks) and confirm the `/xml`, `/pdf`, `/literal` calls succeed

## Still to verify on the next run (not caused by this fix)
- **0 tasks** for 509636 — confirm a `DOCUMENT_COURANT` Plaquette is expected to have no SQL/System tasks (try a runId that loads tasks).
- **"Missing DID box (no UID)"** should disappear once the full gabarit XML loads (it failed only due to the buffer).
- **PDF `compression=true`** in the render URL — confirm the PDF comes out correct now that the response can be buffered.
