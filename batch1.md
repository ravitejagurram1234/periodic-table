# EOS Quark — Batch 1 Changes (copy-paste)

**Batch 1 = QXPS combined-URL HTTP + document-pool vertical** (the one-URL/one-call rewrite, `saveToPool=false`, `Change_Document` via `literal`, 6 PDF params, pool `inform()`).

## How to apply
Each numbered section below is **one file**. In your repo, open the file at the given path (create it if it does not exist) and **replace its entire contents** with the code block. Paths are relative to the `quark-engine` module root (the folder containing `pom.xml`). When all 18 are pasted, run `mvn -DskipTests compile`, then `mvn test`.

## Checklist (18 files)
- [ ] 1. `infra/interop/qxps/message/MessagePriority.java` — NEW
- [ ] 2. `infra/interop/qxps/message/QxpsMessage.java` — CHANGED
- [ ] 3. `infra/interop/qxps/message/AddFileMessage.java` — CHANGED
- [ ] 4. `infra/interop/qxps/message/DeleteMessage.java` — CHANGED
- [ ] 5. `infra/interop/qxps/message/FetchXmlMessage.java` — CHANGED
- [ ] 6. `infra/interop/qxps/message/LiteralMessage.java` — CHANGED
- [ ] 7. `infra/interop/qxps/message/ParamsValueMessage.java` — CHANGED
- [ ] 8. `infra/interop/qxps/message/SaveAsMessage.java` — CHANGED
- [ ] 9. `infra/interop/qxps/message/ModifyMessage.java` — CHANGED
- [ ] 10. `infra/interop/qxps/message/QxpRenderMessage.java` — CHANGED
- [ ] 11. `infra/interop/qxps/message/PdfRenderMessage.java` — CHANGED
- [ ] 12. `infra/interop/qxps/message/JpegRenderMessage.java` — CHANGED
- [ ] 13. `infra/interop/qxps/request/QxpsRequestBuilder.java` — CHANGED
- [ ] 14. `infra/interop/qxps/client/QxpsHttpClient.java` — CHANGED
- [ ] 15. `infra/interop/qxps/pool/FilePoolService.java` — CHANGED
- [ ] 16. `domain/port/FilePoolPort.java` — CHANGED
- [ ] 17. `domain/DocumentDomain.java` — CHANGED
- [ ] 18. `service/impl/QxpsCallerServiceImpl.java` — CHANGED

---

## 1. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/MessagePriority.java`  — **NEW**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

/**
 * Priority levels for QXPS direct-call messages.
 * <p>
 * When several messages are combined into a single QuarkXPress Server URL, they are
 * sorted by ascending priority: the lower the code, the earlier the message's path/query
 * fragment appears in the combined URL.
 *
 * <p>Cross-reference: .NET QXP.Interop.QuarkServer.Message_Priority
 * (Lowest=1, BelowNormal=2, Normal=3, AboveNormal=4, Highest=5).
 */
public enum MessagePriority {

    LOWEST(1),
    BELOW_NORMAL(2),
    NORMAL(3),
    ABOVE_NORMAL(4),
    HIGHEST(5);

    private final int code;

    MessagePriority(int code) {
        this.code = code;
    }

    public int getCode() {
        return code;
    }
}
```

## 2. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/QxpsMessage.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

/**
 * Contract for a message that can be sent to QuarkXPress Server.
 * URL pattern: {baseUrl}/{path}/{documentName}?{query}
 * When path is null: {baseUrl}/{documentName}?{query}
 *
 * Cross-reference: .NET QXPS_Message_Base
 */
public interface QxpsMessage {

    /** Path segment before document name. Null means no path segment. */
    String getCommandPath();

    /** Query string after the ?. Null means no query. */
    String getCommandQuery();

    /** Binary data for POST requests. Null for GET. */
    byte[] getData();

    /** True = HTTP POST, False = HTTP GET. */
    boolean isPost();

    /**
     * Priority that determines the message's position when several messages are
     * combined into a single QuarkXPress Server URL (ascending = earlier in the URL).
     *
     * Cross-reference: .NET QXPS_Message_Base.Priority
     */
    MessagePriority getPriority();

    /**
     * Optional document-name override. When set (non-null/non-empty), it replaces the
     * caller-supplied document name in the combined URL. Defaults to no override.
     *
     * Cross-reference: .NET QXPS_Message_Base.Get_Document()
     */
    default String getCommandDocument() {
        return null;
    }
}
```

## 3. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/AddFileMessage.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

@Getter
@RequiredArgsConstructor
public class AddFileMessage implements QxpsMessage {

    private static final String MESSAGE_PATH = "addfile";

    private final byte[] data;

    @Override
    public String getCommandPath() {
        return MESSAGE_PATH;
    }

    @Override
    public String getCommandQuery() {
        return null;
    }

    @Override
    public boolean isPost() {
        return true;
    }

    @Override
    public MessagePriority getPriority() {
        return MessagePriority.LOWEST;
    }
}

```

## 4. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/DeleteMessage.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

/**
 * QXPS POST message for deleting a file from the document pool.
 *
 * URL: {baseUrl}/delete/{documentName}
 *
 * Cross-reference: .NET QXPS_Message_Delete
 */
public class DeleteMessage implements QxpsMessage {

    private static final String MESSAGE_PATH = "delete";

    @Override
    public String getCommandPath() {
        return MESSAGE_PATH;
    }

    @Override
    public String getCommandQuery() {
        return null;
    }

    @Override
    public byte[] getData() {
        return null;
    }

    @Override
    public boolean isPost() {
        return true;
    }

    @Override
    public MessagePriority getPriority() {
        return MessagePriority.LOWEST;
    }
}
```

## 5. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/FetchXmlMessage.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

import lombok.Getter;

/**
 * QXPS GET message for fetching XML content from a document.
 *
 * Two modes:
 * - With boxName: {baseUrl}/xml/{documentName}?box={boxName} (single box XML)
 * - Without boxName: {baseUrl}/xml/{documentName} (full document XML)
 *
 * Cross-reference: .NET QXP_XML.Create_From_File() uses full document XML
 */
@Getter
public class FetchXmlMessage implements QxpsMessage {

    private static final String MESSAGE_PATH = "xml";

    private final String boxName;

    /**
     * Fetch full document XML (no box filter).
     * Used by Check step for overflow detection and data collection.
     */
    public FetchXmlMessage() {
        this.boxName = null;
    }

    /**
     * Fetch XML for a specific box.
     * Used for DID parsing, specific value reads.
     *
     * @param boxName the box name to filter
     */
    public FetchXmlMessage(String boxName) {
        this.boxName = boxName;
    }

    @Override
    public String getCommandPath() {
        return MESSAGE_PATH;
    }

    @Override
    public String getCommandQuery() {
        if (boxName != null && !boxName.isEmpty()) {
            return "box=" + boxName;
        }
        return null;
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
        return MessagePriority.LOWEST;
    }
}
```

## 6. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/LiteralMessage.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

/**
 * QXPS GET message for fetching a file from the pool without modification.
 * Used to retrieve a previously saved QXP file.
 *
 * URL: {baseUrl}/literal/{documentName}
 *
 * Cross-reference: .NET QXPS_Message_Literal
 */
public class LiteralMessage implements QxpsMessage {

    private static final String MESSAGE_PATH = "literal";

    @Override
    public String getCommandPath() {
        return MESSAGE_PATH;
    }

    @Override
    public String getCommandQuery() {
        return null;
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

## 7. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/ParamsValueMessage.java`  — **CHANGED**

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
            args.add(nv.getParamName() + "=" + nv.getTextValue());
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

## 8. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/SaveAsMessage.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

import lombok.Getter;

import java.util.ArrayList;
import java.util.List;

/**
 * QXPS GET message for saving the document with a new name.
 *
 * URL: {baseUrl}/saveas/{documentName}?newname={name}&path={path}
 * NOTE: replace and savetopool default to true — only added to query when false.
 *
 * Cross-reference: .NET QXPS_Message_SaveAs
 */
@Getter
public class SaveAsMessage implements QxpsMessage {

    private static final String MESSAGE_PATH = "saveas";

    private final String newName;
    private final String path;
    private final boolean replace;
    private final boolean saveToPool;

    public SaveAsMessage(String path, String newName, boolean replace, boolean saveToPool) {
        this.path = path;
        this.newName = newName;
        this.replace = replace;
        this.saveToPool = saveToPool;
    }

    /** Convenience constructor with defaults: replace=true, saveToPool=true */
    public SaveAsMessage(String path, String newName) {
        this(path, newName, true, true);
    }

    @Override
    public String getCommandPath() {
        return MESSAGE_PATH;
    }

    @Override
    public String getCommandQuery() {
        List<String> args = new ArrayList<>();
        if (newName != null && !newName.isEmpty()) {
            args.add("newname=" + newName);
        }
        // Only add when false (default is true on server side)
        if (!replace) {
            args.add("replace=false");
        }
        if (!saveToPool) {
            args.add("savetopool=false");
        }
        if (path != null && !path.isEmpty()) {
            args.add("path=" + path);
        }
        return args.isEmpty() ? null : String.join("&", args);
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

## 9. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/ModifyMessage.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * QXPS GET message for applying structural modifications to a document.
 * The modify XML file must have been previously uploaded via AddFileMessage.
 *
 * URL: {baseUrl}/{documentName}?modify=file:{modifyFileName}
 * NOTE: path is NULL — modify goes in the query string, not the path.
 *
 * Cross-reference: .NET QXPS_Message_Modify
 */
@Getter
@RequiredArgsConstructor
public class ModifyMessage implements QxpsMessage {

    private static final String QUERY_PATTERN = "modify=file:%s";

    /** The pool path of the previously uploaded modify XML file. */
    private final String modifyFileName;

    @Override
    public String getCommandPath() {
        return null;
    }

    @Override
    public String getCommandQuery() {
        return String.format(QUERY_PATTERN, modifyFileName);
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
        return MessagePriority.NORMAL;
    }
}
```

## 10. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/QxpRenderMessage.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

import lombok.Getter;

/**
 * QXPS GET message for rendering the document as QXP binary (native QuarkXPress format).
 *
 * URL: {baseUrl}/qxpdoc/{documentName}
 * NOTE: path is "qxpdoc", NOT "qxp".
 *
 * Cross-reference: .NET QXPS_Message_QXP
 */
@Getter
public class QxpRenderMessage implements QxpsMessage {

    private static final String MESSAGE_PATH = "qxpdoc";

    @Override
    public String getCommandPath() {
        return MESSAGE_PATH;
    }

    @Override
    public String getCommandQuery() {
        return null;
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
        return MessagePriority.ABOVE_NORMAL;
    }
}
```

## 11. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/PdfRenderMessage.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

import lombok.Getter;
import lombok.Setter;

import java.util.ArrayList;
import java.util.List;

/**
 * QXPS GET message for rendering the document as PDF.
 *
 * URL: {baseUrl}/pdf/{documentName}?colorimagedownsample=X&colorcompression=Y&...
 *
 * Cross-reference: .NET QXPS_Message_PDF
 */
@Getter
@Setter
public class PdfRenderMessage implements QxpsMessage {

    private static final String MESSAGE_PATH = "pdf";

    private String colorImageDownSample;
    private String grayscaleImageDownSample;
    private String monochromeImageDownSample;
    private String colorCompression;
    private String grayscaleCompression;
    private String monochromeCompression;

    public PdfRenderMessage() {
    }

    @Override
    public String getCommandPath() {
        return MESSAGE_PATH;
    }

    @Override
    public String getCommandQuery() {
        List<String> args = new ArrayList<>();
        if (colorImageDownSample != null && !colorImageDownSample.isEmpty()) {
            args.add("colorimagedownsample=" + colorImageDownSample);
        }
        if (grayscaleImageDownSample != null && !grayscaleImageDownSample.isEmpty()) {
            args.add("grayscaleimagedownsample=" + grayscaleImageDownSample);
        }
        if (monochromeImageDownSample != null && !monochromeImageDownSample.isEmpty()) {
            args.add("monochromeImagedownSample=" + monochromeImageDownSample);
        }
        if (colorCompression != null && !colorCompression.isEmpty()) {
            args.add("colorcompression=" + colorCompression);
        }
        if (grayscaleCompression != null && !grayscaleCompression.isEmpty()) {
            args.add("grayscalecompression=" + grayscaleCompression);
        }
        if (monochromeCompression != null && !monochromeCompression.isEmpty()) {
            args.add("monochromecompression=" + monochromeCompression);
        }
        return args.isEmpty() ? null : String.join("&", args);
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
        return MessagePriority.ABOVE_NORMAL;
    }
}

```

## 12. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/message/JpegRenderMessage.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.message;

import lombok.Getter;
import lombok.Setter;

import java.util.ArrayList;
import java.util.List;

/**
 * QXPS GET message for rendering the document as JPEG.
 *
 * URL: {baseUrl}/jpeg/{documentName}?page=X&spread=Y&box=Z
 *
 * Cross-reference: .NET QXPS_Message_JPEG
 */
@Getter
@Setter
public class JpegRenderMessage implements QxpsMessage {

    private static final String MESSAGE_PATH = "jpeg";

    private String page;
    private String spread;
    private String box;

    public JpegRenderMessage() {
    }

    @Override
    public String getCommandPath() {
        return MESSAGE_PATH;
    }

    @Override
    public String getCommandQuery() {
        List<String> args = new ArrayList<>();
        if (page != null && !page.isEmpty()) {
            args.add("page=" + page);
        }
        if (spread != null && !spread.isEmpty()) {
            args.add("spread=" + spread);
        }
        if (box != null && !box.isEmpty()) {
            args.add("box=" + box);
        }
        return args.isEmpty() ? null : String.join("&", args);
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
        return MessagePriority.ABOVE_NORMAL;
    }
}
```

## 13. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/request/QxpsRequestBuilder.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.request;

import com.socgen.sgs.api.quark.engine.infra.interop.qxps.config.QxpsProperties;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.QxpsMessage;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsRequestInfo;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpMethod;
import org.springframework.stereotype.Component;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * Builds the QuarkXPress Server call URL from one or more messages.
 *
 * <p>Cross-reference: .NET QXPS_Request_Message.Get_Request_Message_Info().
 * Messages are sorted by ascending priority, their paths are concatenated with '/',
 * the document name is appended last, and their queries are concatenated with '&' —
 * producing ONE URL for ONE HTTP call (not one call per message).
 */
@Component
@RequiredArgsConstructor
public class QxpsRequestBuilder {

    private final QxpsProperties qxpsProperties;

    /**
     * Single-message convenience overload (standalone calls: addfile, literal, xml, delete...).
     * Cross-reference: .NET QXPS_Helper one-message QXPS_Call.
     */
    public QxpsRequestInfo build(String documentName, QxpsMessage message) {
        return buildCombined(documentName, List.of(message));
    }

    /**
     * Combines several messages into a single QuarkXPress Server URL.
     * Cross-reference: .NET QXPS_Request_Message.Get_Request_Message_Info().
     */
    public QxpsRequestInfo buildCombined(String documentName, List<QxpsMessage> messages) {
        // A small ascending sort is required: the order of fragments in the call path matters.
        // Java's List.sort is stable, so messages of equal priority keep their insertion order.
        List<QxpsMessage> sorted = new ArrayList<>(messages);
        sorted.sort(Comparator.comparingInt(m -> m.getPriority().getCode()));

        List<String> paths = new ArrayList<>();
        List<String> queries = new ArrayList<>();
        String docName = documentName;
        boolean httpPost = false;
        byte[] data = new byte[0];

        for (QxpsMessage message : sorted) {
            String p = message.getCommandPath();
            String q = message.getCommandQuery();
            String d = message.getCommandDocument();
            if (isSet(p)) {
                paths.add(p);
            }
            if (isSet(d)) {
                docName = d;
            }
            if (isSet(q)) {
                queries.add(q);
            }
            if (message.isPost()) {
                httpPost = true;
                if (data.length > 0) {
                    throw new IllegalStateException("Only one POST stream is allowed per request message");
                }
                data = message.getData() != null ? message.getData() : new byte[0];
            }
        }

        // Document name is appended at the END of the path segments.
        paths.add(docName);

        String rawPath = String.join("/", paths);
        String rawQuery = String.join("&", queries);

        // Rebuild on the bare server URI (scheme://host:port), clearing any path/query — same as .NET.
        UriComponentsBuilder uriBuilder = UriComponentsBuilder
                .fromHttpUrl(qxpsProperties.getServer().getUrl())
                .replacePath("/" + rawPath);
        if (!rawQuery.isEmpty()) {
            uriBuilder.replaceQuery(rawQuery);
        }
        // build() then encode(): '/' and '&'/'=' stay as separators, while illegal characters
        // (spaces, backslashes in Windows pool paths, ...) are percent-encoded so the URI is valid.
        // QuarkXPress Server decodes them back to the original literal values.
        URI uri = uriBuilder.build().encode().toUri();

        HttpMethod method = httpPost ? HttpMethod.POST : HttpMethod.GET;
        return new QxpsRequestInfo(uri, method, httpPost ? data : null);
    }

    private static boolean isSet(String value) {
        return value != null && !value.isEmpty();
    }
}
```

## 14. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/client/QxpsHttpClient.java`  — **CHANGED**

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
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, timeout)
                .doOnConnected(conn ->
                        conn.addHandlerLast(new ReadTimeoutHandler(timeout, TimeUnit.MILLISECONDS))
                )
                .responseTimeout(Duration.ofMillis(timeout));

        this.webClient = WebClient.builder()
                .clientConnector(new ReactorClientHttpConnector(httpClient))
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
        if (contentType == null || contentType.isEmpty()) return true;
        String lower = contentType.toLowerCase();
        return TEXT_CONTENT_TYPES.stream().anyMatch(t -> !t.isEmpty() && lower.startsWith(t));
    }
}

```

## 15. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/pool/FilePoolService.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.pool;

import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.helper.QxpsHelper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

@Slf4j
@Service
@RequiredArgsConstructor
public class FilePoolService implements FilePoolPort {

    private final QxpsHelper qxpsHelper;
    private final Set<String> addedFiles = ConcurrentHashMap.newKeySet();

    public void addFile(String documentName, byte[] data) {
        if (addedFiles.contains(documentName)) {
            log.debug("File already added to pool, skipping: {}", documentName);
            return;
        }

        qxpsHelper.addFile(documentName, data);
        addedFiles.add(documentName);
        log.info("File added to pool: {}", documentName);
    }

    /**
     * Registers a pool file as already known WITHOUT uploading it.
     * Used after a SaveAs/Change_Document so a later addFile() for the same name is skipped.
     *
     * Cross-reference: .NET QXPS_File_Manager.Addfile_Inform(poolName).
     */
    @Override
    public void inform(String documentName) {
        addedFiles.add(documentName);
    }

    public void clear() {
        addedFiles.clear();
    }
}


```

## 16. `src/main/java/com/socgen/sgs/api/quark/engine/domain/port/FilePoolPort.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.domain.port;

/** Port for uploading files to the QuarkXPress Server document pool. */
public interface FilePoolPort {
    void addFile(String documentName, byte[] data);

    /**
     * Registers a pool file as already present without uploading it.
     * Cross-reference: .NET QXPS_File_Manager.Addfile_Inform(poolName).
     */
    void inform(String documentName);
}

```

## 17. `src/main/java/com/socgen/sgs/api/quark/engine/domain/DocumentDomain.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.domain;

import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import java.util.ArrayList;
import java.util.List;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.AccessLevel;

/**
 * Domain entity representing a Document.
 * Encapsulates document metadata and content.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DocumentDomain {

    // File prefix constants
    public static final String FILE_DOCUMENT_PREFIX = "D";
    public static final String FILE_GABARIT_PREFIX = "G";
    public static final String FILE_DOCUMENT_GABARIT_PREFIX = "DG";
    public static final String FILE_DOCUMENT_CERTIFIE_GABARIT_PREFIX = "DCG";
    public static final String FILE_DOCUMENT_FINAL_PREFIX = "DF";
    public static final String FILE_GABARIT_TEMPLATE_PREFIX = "GT";

    // File naming patterns
    private static final String FILE_NAME_PREFIX_PATTERN = "%s_%d.%s";

    // Document properties
    private Integer id;
    private byte[] data;
    private String name;
    private String format;
    private String prefix;
    private Integer idLangue;
    private String fileName;
    private String filePoolPath;
    private String fileFullPath;
    private boolean gabarit;
    private boolean modeDegrade = false;
    private DocumentIdentity documentIdentity;

    // ========================================================================
    // XML and Project structure (lazy-loaded)
    // Cross-reference: .NET Document._xml, Document._project, Document._pdfs
    // ========================================================================

    /** Parsed XML structure of this QXP document (lazy-loaded). */
    @Getter(AccessLevel.NONE)
    @Setter(AccessLevel.NONE)
    private QxpXml qxpXml;

    /** Parsed project structure for element analysis (lazy-loaded). */
    @Getter(AccessLevel.NONE)
    @Setter(AccessLevel.NONE)
    private QxpProject qxpProject;

    /** List of PDF page file paths (for multi-page PDF documents). */
    private List<String> pdfFiles = new ArrayList<>();

    /**
     * Constructor for creating a document with full details.
     *
     * @param id the document ID
     * @param name the document name
     * @param format the document format (e.g., QXP, PDF)
     * @param prefix the file prefix
     * @param data the document content
     */
    public DocumentDomain(Integer id, String name, String format, String prefix, byte[] data) {
        this.id = id;
        this.name = name;
        this.format = format;
        this.prefix = prefix;
        this.data = data;
        this.idLangue = 1;  // Default language ID
        this.gabarit = false;
        generateFileNames();
    }

    // ========================================================================
    // XML access (lazy-loaded from QXPS server)
    // Cross-reference: .NET Document.XML property
    // ========================================================================

    /**
     * Get the parsed XML structure of this document.
     * In the .NET code, this is lazy-loaded via QXPS_File_Manager.Get_XML(this).
     * In Java, the XML content must be set externally (via setQxpXml or initXmlFromContent).
     *
     * @return the QxpXml instance, or QxpXml.EMPTY if not available
     */
    public QxpXml getQxpXml() {
        if (this.qxpXml == null) {
            return QxpXml.EMPTY;
        }
        return this.qxpXml;
    }

    /**
     * Set the parsed XML structure.
     *
     * @param qxpXml the QxpXml instance
     */
    public void setQxpXml(QxpXml qxpXml) {
        this.qxpXml = qxpXml;
    }

    /**
     * Initialize QxpXml from a raw XML string.
     * Convenience method to create and set the QxpXml in one call.
     *
     * @param xmlContent the raw XML content from QXPS server
     */
    public void initXmlFromContent(String xmlContent) {
        this.qxpXml = QxpXml.createFromXml(xmlContent);
    }

    // ========================================================================
    // Project access (lazy-loaded from QXPS server)
    // Cross-reference: .NET Document.QXPProject property
    // ========================================================================

    /**
     * Get the parsed project structure for element analysis.
     * In the .NET code, this is lazy-loaded via QXPS_File_Manager.Get_Project(this).
     * In Java, the project must be set externally (via setQxpProject or initProjectFromSoap).
     *
     * @return the QxpProject instance, or QxpProject.EMPTY if not available
     */
    public QxpProject getQxpProject() {
        if (this.qxpProject == null) {
            return QxpProject.EMPTY;
        }
        return this.qxpProject;
    }

    /**
     * Set the parsed project structure.
     *
     * @param qxpProject the QxpProject instance
     */
    public void setQxpProject(QxpProject qxpProject) {
        this.qxpProject = qxpProject;
    }

    /**
     * Initialize QxpProject from a SOAP Project object.
     * Convenience method to create and set the QxpProject in one call.
     *
     * @param soapProject the SOAP-generated Project from QXPS server
     */
    public void initProjectFromSoap(Project soapProject) {
        this.qxpProject = new QxpProject(soapProject);
    }

    // ========================================================================
    // PDF files (for multi-page PDF documents)
    // Cross-reference: .NET Document.PDFFiles property
    // ========================================================================

    /**
     * Get the list of PDF page file paths.
     *
     * @return the list of PDF file paths
     */
    public List<String> getPdfFiles() {
        return this.pdfFiles;
    }

    /**
     * Set the list of PDF page file paths.
     *
     * @param pdfFiles the list of PDF file paths
     */
    public void setPdfFiles(List<String> pdfFiles) {
        this.pdfFiles = pdfFiles;
    }

    /**
     * Get the absolute pool path for a PDF page file.
     * Used by Process_Document PDF handling.
     *
     * Cross-reference: .NET Document.GetPDFFileAbsolutePath(file)
     *
     * @param pdfFileName the PDF file name
     * @param documentPoolBasePath the base path for document pool
     * @return the absolute path to the PDF file
     */
    public String getPdfFileAbsolutePath(String pdfFileName, String documentPoolBasePath) {
        if (pdfFileName == null || documentPoolBasePath == null) {
            return pdfFileName;
        }
        return documentPoolBasePath + "/" + pdfFileName;
    }

    /**
     * Swap this document to a newly-saved version: update name/pool path, replace the
     * binary content with the freshly-downloaded bytes, and purge the cached XML/Project.
     *
     * <p>In .NET, Document.Change_Document() downloads the bytes itself via
     * QXPS_Helper.GetFileData (a 'literal' HTTP call). To keep the domain free of I/O,
     * the caller (service layer) performs the download and passes the bytes here.
     *
     * Cross-reference: .NET Document.Change_Document(newDocumentName).
     *
     * @param newFileName      new file name (with extension), e.g. G_45_1.qxp
     * @param newFilePoolPath  pool-relative path of the new file
     * @param newData          freshly-downloaded binary content of the new file
     */
    public void changeDocument(String newFileName, String newFilePoolPath, byte[] newData) {
        this.fileName = newFileName;
        this.filePoolPath = newFilePoolPath;
        this.data = newData;
        purgeXmlAndProject();
    }

    /**
     * Purge cached XML and project data.
     * Called when the document content changes (e.g., after Change_Document).
     *
     * Cross-reference: .NET Document.Change_Document() — purges _xml and _project
     */
    public void purgeXmlAndProject() {
        this.qxpXml = null;
        this.qxpProject = null;
    }

    /**
     * Generate file names from document properties.
     */
    private void generateFileNames() {
        if (this.id != null && this.prefix != null && this.format != null) {
            this.fileName = String.format(FILE_NAME_PREFIX_PATTERN, this.prefix, this.id, this.format.toLowerCase());
        }
    }
}

```

## 18. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/QxpsCallerServiceImpl.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunTaskStep;
import com.socgen.sgs.api.quark.engine.domain.modifier.QxpsModifier;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.client.QxpsHttpClient;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.config.QxpsProperties;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.helper.QxpsProjectSerializer;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.*;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsResponseInfo;
import com.socgen.sgs.api.quark.engine.infra.interop.qxpsm.QxpsmSoapClient;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.NameValueParam;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.QContentData;
import com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult;
import com.socgen.sgs.api.quark.engine.service.QxpsCallerService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * Orchestrates the execution of RunTaskSteps against QuarkXPress Server.
 * Handles both HTTP (direct call) and SOAP (via QXPSM) communication paths.
 *
 * Cross-reference: QXP.Engine.Core.QXPS_Caller
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class QxpsCallerServiceImpl implements QxpsCallerService {

    private static final String MODIFY_NAME_PATTERN = "Modify_%s.xml";
    private static final String NEW_GABARIT_NAME_WITH_ID_PATTERN = "%s_%d_%d.%s";
    private static final String NEW_GABARIT_NAME_PATTERN = "%s_%d.%s";
    private static final DateTimeFormatter TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("HHmmssSSS");

    private final QxpsHttpClient qxpsHttpClient;
    private final QxpsmSoapClient qxpsmSoapClient;
    private final QxpsProperties qxpsProperties;
    private final FilePoolPort filePool;

    // ========================================================================
    // Process — execute all steps
    // Cross-reference: QXPS_Caller.Process()
    // ========================================================================

    @Override
    public void process(Run run) {
        if (run.getRunProperties().isModeDegrade()) {
            log.info("Mode degrade detected — no modifications executed for run [{}]", run.getId());
            return;
        }

        List<RunTaskStep> steps = run.getRunTask().getSteps();
        boolean stopProcess = false;
        int executionCount = 1;

        log.info("Starting step execution for run [{}] with {} steps", run.getId(), steps.size());

        for (RunTaskStep step : steps) {
            log.info("Preparing step [{}] for run [{}]", step.getIndex(), run.getId());

            step.prepare(stopProcess);

            log.info("Executing step [{}]: add={} update={} excluded={}",
                    step.getIndex(), step.getNbBoxAdded(),
                    step.getNbBoxUpdate(), step.getNbBoxExcluded());

            if (step.isFullExclude()) {
                log.info("Step [{}] fully excluded — nothing to execute", step.getIndex());
            } else {
                if (step.getPrepareStep() != null) {
                    log.info("Executing prepare sub-step for step [{}]", step.getIndex());
                    executionCount = executeStep(run, step.getPrepareStep(), executionCount);
                }
                executionCount = executeStep(run, step, executionCount);
            }

            stopProcess = stopProcess || step.isPartialExclude();
            log.info("Step [{}] completed for run [{}]", step.getIndex(), run.getId());
        }

        int nbExcluded = run.getRunTask().getNbExcludeBoxes();
        if (nbExcluded > 0) {
            log.warn("Run [{}]: {} boxes were excluded due to document size limits",
                    run.getId(), nbExcluded);
        }

        log.info("All steps completed for run [{}]", run.getId());
    }

    // ========================================================================
    // Execute — single step
    // Cross-reference: QXPS_Caller.Execute(Run_Task_Step)
    // ========================================================================

    private int executeStep(Run run, RunTaskStep step, int executionCount) {
        DocumentDomain gabarit = run.getGabarit();
        String currentDocName = gabarit.getFilePoolPath();
        String newGabaritName = getNewGabaritNameExt(gabarit, executionCount);
        String poolBasePath = qxpsProperties.getPool().getDefaultPath();
        String saveAsPath = run.getRunProperties().getPoolPathAbsolute("", poolBasePath);

        QxpsModifier modifier = new QxpsModifier();
        modifier.addRange(step.getBlocsModify());

        if (step.isDirectCall()) {
            executeDirectCall(run, step, modifier, currentDocName, saveAsPath, newGabaritName);
        } else {
            executeSoapCall(step, modifier, currentDocName, saveAsPath, newGabaritName);
        }

        updateGabaritAfterStep(run, newGabaritName, currentDocName);

        return executionCount + 1;
    }

    // ========================================================================
    // HTTP (directCall=true)
    // ========================================================================

    private void executeDirectCall(Run run, RunTaskStep step, QxpsModifier modifier,
                                   String documentName, String saveAsPath,
                                   String newGabaritName) {
        // All messages for this step are combined into ONE QuarkXPress Server URL and sent
        // as ONE HTTP call (sorted by priority by the request builder), exactly like .NET
        // QXPS_Caller.Execute(): ParamsValue + Modify + SaveAs + QXP rendered in a single call.
        // Cross-reference: QXPS_Caller.Execute(Run_Task_Step).
        List<QxpsMessage> messages = new ArrayList<>();

        // 1. ParamsValue (name/value updates) — query only, no path.
        if (!step.getNameValues().isEmpty()) {
            NameValueParam[] nvArray = step.getNameValues().toArray(new NameValueParam[0]);
            messages.add(new ParamsValueMessage(nvArray));
            log.debug("ParamsValue queued with {} entries", nvArray.length);
        }

        // 2. Modify — the modify XML is uploaded as a SEPARATE standalone POST first
        //    (matching .NET QXPS_File_Manager.Addfile), then referenced by the combined call.
        if (!modifier.isEmpty()) {
            Project project = modifier.getProject();
            byte[] modifyXml = QxpsProjectSerializer.toBytes(project);
            String modifyFileName = String.format(MODIFY_NAME_PATTERN,
                    LocalDateTime.now().format(TIMESTAMP_FORMAT));

            // Standalone upload of the modify XML to the document pool.
            qxpsHttpClient.execute(modifyFileName, new AddFileMessage(modifyXml));

            // Reference to the uploaded modify file (added to the combined call).
            messages.add(new ModifyMessage(modifyFileName));
        }

        // 3. SaveAs — replace=true, saveToPool=false (matches .NET Execute(): the file is written
        //    to the absolute pool dir on the Quark host, but not registered in the server pool).
        messages.add(new SaveAsMessage(saveAsPath, newGabaritName, true, false));

        // 4. QXP render — forces QuarkXPress to render/save the document as QXP before SaveAs.
        messages.add(new QxpRenderMessage());

        // ONE combined call.
        qxpsHttpClient.executeCombined(documentName, messages);
    }

    // ========================================================================
    // SOAP (directCall=false)
    // ========================================================================

    private void executeSoapCall(RunTaskStep step, QxpsModifier modifier,
                                 String documentName, String saveAsPath,
                                 String newGabaritName) {
        Project project = modifier.isEmpty() ? null : modifier.getProject();

        QContentData result = qxpsmSoapClient.executeStep(
                documentName, step.getNameValues(), project,
                saveAsPath, newGabaritName);

        if (result != null && result.getStreamValue() != null) {
            log.debug("SOAP call returned {} bytes of QXP data",
                    result.getStreamValue().length);
        }
    }

    // ========================================================================
    // Render — final outputs
    // Cross-reference: QXPS_Caller.Render()
    // ========================================================================

    @Override
    public QxpsCallerResult render(Run run, boolean renderPdf, boolean renderJpg,
                                   boolean renderQxp, String compression, String downsample) {
        String documentName = run.getGabarit().getFilePoolPath();
        QxpsCallerResult result = new QxpsCallerResult();

        log.info("Starting final renders for run [{}]", run.getId());

        if (renderJpg) {
            try {
                QxpsResponseInfo response = qxpsHttpClient.execute(
                        documentName, new JpegRenderMessage());
                result.setJpgData(response.getBinaryResponse());
                log.info("JPEG render completed for run [{}]", run.getId());
            } catch (Exception e) {
                log.error("JPEG render failed for run [{}]: {}", run.getId(), e.getMessage(), e);
            }
        }

        // PDF render errors (e.g. empty document) must NOT block the run render — non-blocking.
        // Cross-reference: QXPS_Caller.Render() try/catch on QXPS_Exception.
        if (renderPdf) {
            try {
                PdfRenderMessage pdfMessage = new PdfRenderMessage();
                // All three down-sample params take the down-sample value; all three compression
                // params take the compression value (matches .NET: ColorImageDownSample =
                // GrayscaleImageDownSample = MonochromeImagedownSample = Value_Compression;
                // ColorCompression = GrayscaleCompression = MonochromeCompression = Compression).
                pdfMessage.setColorImageDownSample(downsample);
                pdfMessage.setGrayscaleImageDownSample(downsample);
                pdfMessage.setMonochromeImageDownSample(downsample);
                pdfMessage.setColorCompression(compression);
                pdfMessage.setGrayscaleCompression(compression);
                pdfMessage.setMonochromeCompression(compression);
                QxpsResponseInfo response = qxpsHttpClient.execute(documentName, pdfMessage);
                result.setPdfData(response.getBinaryResponse());
                log.info("PDF render completed for run [{}]", run.getId());
            } catch (Exception e) {
                log.error("PDF render failed for run [{}]: {}", run.getId(), e.getMessage(), e);
            }
        }

        if (renderQxp) {
            try {
                // The latest QXP version is already saved in the pool — fetch it via a 'literal'
                // call (no re-render), exactly like .NET: QXPS_Helper.GetFileData(Gabarit.FilePoolPath).
                QxpsResponseInfo response = qxpsHttpClient.execute(
                        documentName, new LiteralMessage());
                result.setQxpData(response.getBinaryResponse());
                log.info("QXP fetched (literal) for run [{}]", run.getId());
            } catch (Exception e) {
                log.error("QXP fetch failed for run [{}]: {}", run.getId(), e.getMessage(), e);
            }
        }

        log.info("All renders completed for run [{}]", run.getId());
        return result;
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    private void updateGabaritAfterStep(Run run, String newGabaritName, String previousDocName) {
        DocumentDomain gabarit = run.getGabarit();
        String newPoolPath = run.getRunProperties().getPoolPath(newGabaritName);

        // Download the freshly-saved QXP binary via a 'literal' call (no re-render), exactly
        // like .NET Document.Change_Document() → QXPS_Helper.GetFileData(filePoolPath).
        byte[] newData = qxpsHttpClient.execute(newPoolPath, new LiteralMessage()).getBinaryResponse();

        // Swap the gabarit to the new version (updates name/pool path + binary, purges cached XML/Project).
        gabarit.changeDocument(newGabaritName, newPoolPath, newData);

        // Register the new pool file as known so it is not re-uploaded later.
        // Cross-reference: .NET QXPS_File_Manager.Addfile_Inform(newPoolName).
        filePool.inform(newPoolPath);

        log.debug("Gabarit changed: [{}] → [{}] ({} bytes)",
                previousDocName, newPoolPath, newData != null ? newData.length : 0);
    }

    private String getNewGabaritNameExt(DocumentDomain gabarit, int executionCount) {
        if (gabarit.getId() != null && gabarit.getId() > 0) {
            return String.format(NEW_GABARIT_NAME_WITH_ID_PATTERN,
                    gabarit.getPrefix(), gabarit.getId(), executionCount,
                    gabarit.getFormat() != null ? gabarit.getFormat().toLowerCase() : "qxp");
        } else {
            return String.format(NEW_GABARIT_NAME_PATTERN,
                    gabarit.getName(), executionCount,
                    gabarit.getFormat() != null ? gabarit.getFormat().toLowerCase() : "qxp");
        }
    }
}
```

