# EOS Quark Core Parity - Wave 10E Copy Packet

Revision: 2026-08-30. Apply only after Wave 10D has been applied successfully.

This packet is the authoritative copy-paste source for every Java/resource/test change made after Wave 10D.
Replace each listed file completely with the corresponding fenced block, in serial order. Do not reconstruct
Wave 10E from the evidence-capture guide or from isolated snippets.

## Scope

Wave 10E changes logging and logging verification only:

- bounded run-load and terminal summaries;
- one bounded result per selected task;
- SQL length/bind/row/duration metrics without SQL text or values;
- bounded QXPS/QXPSM start, completion and failure metadata;
- one aggregate anomaly line per affected static SQL or dynamic task;
- framework SQL, bind and HTTP/SOAP wire logging suppression;
- regression tests that reject payload, path, SQL and raw-exception logging.

Wave 10E does not change rendering, task selection/order, Oracle procedure calls, QXPS/QXPSM request contents,
Rabbit behavior, concurrency, PDF/XML processing, or `application.yaml`. Keep the existing single main
`src/main/resources/application.yaml`, with Rabbit input disabled and JPA show-SQL false during Swagger evidence
collection.

## Apply Rules

1. Confirm the office repository already contains complete Wave 10D.
2. Confirm none of the 15 destination files has an unmerged office-only change.
3. Replace the complete files below in serial order.
4. Do not create a second `application.yaml` or environment-specific YAML.
5. Run the verification commands at the end before any Swagger POST.

## 1. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/model/QxpsResponseInfo.java`

SHA-256: `695aa5be3b64c999a3796e1671cb9c7e24beac4a085e3ce9852590ce59c77cb5`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.model;

import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class QxpsResponseInfo {

    private int httpStatus;
    private byte[] binaryResponse;
    private String textResponse;
    private String contentType;
}

```

## 2. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/client/QxpsHttpClient.java`

SHA-256: `3ac508d66fdb2fb4e827c12b15d5510edb5e75456b62469fa3195c2df1ba19a5`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.client;

import com.socgen.sgs.api.quark.engine.infra.interop.qxps.config.QxpsProperties;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.exception.QxpsException;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.QxpsMessage;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsRequestInfo;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsResponseInfo;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.request.QxpsRequestBuilder;
import io.netty.channel.ChannelOption;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatusCode;
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
import java.util.Objects;
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
        int connectTimeoutMs = qxpsProperties.getServer().getConnectTimeoutMs();
        int responseTimeoutMs = qxpsProperties.getServer().getResponseTimeoutMs();
        HttpClient httpClient = HttpClient.create()
                // Disable persistent connections to mimic .NET's HTTP/1.0 connection-close behaviour.
                // (Reactor Netty cannot pin the protocol to HTTP/1.0; the request body is a fixed byte[]
                //  so it is sent with a Content-Length, not chunked — matching .NET. Finding #64.)
                .keepAlive(false)
                .followRedirect(true)
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, connectTimeoutMs)
                .responseTimeout(Duration.ofMillis(responseTimeoutMs));

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
        String messageTypes = messages.stream()
                .map(message -> message.getClass().getSimpleName())
                .collect(java.util.stream.Collectors.joining(","));
        int queryParameterCount = requestInfo.getUri().getRawQuery() == null
                || requestInfo.getUri().getRawQuery().isEmpty()
                ? 0 : requestInfo.getUri().getRawQuery().split("&", -1).length;
        log.info("QXPS call: method={}, messageTypes={}, queryParameterCount={}, requestBytes={}",
                requestInfo.getMethod(), messageTypes,
                queryParameterCount, requestInfo.getData() == null ? 0 : requestInfo.getData().length);

        long callStartNanos = System.nanoTime();
        try {
            QxpsResponseInfo response = requestInfo.getMethod() == HttpMethod.POST
                    ? executePost(requestInfo) : executeGet(requestInfo);
            log.info("QXPS completed: method={}, messageTypes={}, httpStatus={}, durationMs={}, "
                            + "responseCategory={}, responseBytes={}, responseChars={}",
                    requestInfo.getMethod(), messageTypes, response.getHttpStatus(),
                    elapsedMillis(callStartNanos), responseCategory(response), responseBytes(response),
                    responseChars(response));
            return response;
        } catch (RuntimeException failure) {
            log.error("QXPS failed: method={}, messageTypes={}, durationMs={}, causeType={}",
                    requestInfo.getMethod(), messageTypes, elapsedMillis(callStartNanos),
                    failure.getClass().getSimpleName());
            throw failure;
        }
    }

    private QxpsResponseInfo executePost(QxpsRequestInfo requestInfo) {
        byte[] multipartBody = buildMultipartBody(requestInfo.getData());
        String boundary = extractBoundary(multipartBody);

        return Objects.requireNonNull(webClient.post()
                .uri(requestInfo.getUri())
                .header(HttpHeaders.CONTENT_TYPE, "multipart/form-data; boundary=" + boundary)
                .bodyValue(multipartBody)
                .exchangeToMono(clientResponse -> handleResponse(requestInfo, clientResponse))
                .block(), "QXPS POST completed without a response");
    }

    private QxpsResponseInfo executeGet(QxpsRequestInfo requestInfo) {
        return Objects.requireNonNull(webClient.get()
                .uri(requestInfo.getUri())
                .exchangeToMono(clientResponse -> handleResponse(requestInfo, clientResponse))
                .block(), "QXPS GET completed without a response");
    }

    private Mono<QxpsResponseInfo> handleResponse(QxpsRequestInfo requestInfo, ClientResponse clientResponse) {
        HttpStatusCode status = clientResponse.statusCode();
        if (status.isError()) {
            int declaredBodyBytes = boundedContentLength(
                    clientResponse.headers().asHttpHeaders().getContentLength());
            return clientResponse.releaseBody()
                    .then(Mono.error(new QxpsException(
                            requestInfo, status.value(), declaredBodyBytes)));
        }

        QxpsResponseInfo response = new QxpsResponseInfo();
        response.setHttpStatus(status.value());
        String rawContentType = clientResponse.headers().asHttpHeaders()
                .getFirst(HttpHeaders.CONTENT_TYPE);
        String contentTypeValue = rawContentType == null ? "" : rawContentType;
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
        return TEXT_CONTENT_TYPES.contains(contentType);
    }

    private static int boundedContentLength(long contentLength) {
        if (contentLength <= 0) {
            return 0;
        }
        return contentLength > Integer.MAX_VALUE ? Integer.MAX_VALUE : (int) contentLength;
    }

    private static long elapsedMillis(long startNanos) {
        return TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startNanos);
    }

    private static String responseCategory(QxpsResponseInfo response) {
        return response.getBinaryResponse() != null ? "BINARY" : "TEXT";
    }

    private static int responseBytes(QxpsResponseInfo response) {
        if (response.getBinaryResponse() != null) {
            return response.getBinaryResponse().length;
        }
        return 0;
    }

    private static int responseChars(QxpsResponseInfo response) {
        return response.getTextResponse() == null ? 0 : response.getTextResponse().length();
    }
}
```

## 3. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxpsm/QxpsmSoapClient.java`

SHA-256: `0fea43b6d825758bea9ed3d46341ccea98edb7cdaee0a5c4513f28114b16a274`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxpsm;

import com.socgen.sgs.api.quark.engine.integration.soap.generated.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.util.List;
import java.util.concurrent.TimeUnit;

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
        long callStartNanos = System.nanoTime();
        int nameValueCount = nameValues == null ? 0 : nameValues.size();
        int modifierLayoutCount = project == null || project.getLayouts() == null
                ? 0 : project.getLayouts().length;
        log.info("QXPSM started: operation=processRequest, nameValueCount={}, modifierLayoutCount={}",
                nameValueCount, modifierLayoutCount);

        try {
            RequestServicePortType stub = createStub(qxpsmProperties.getSocketTimeoutMs());

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
            context.setRequestTimeout(qxpsmProperties.getRequestTimeoutMs());

            // Execute SOAP call
            log.debug("QXPSM calling processRequest with chain: {} -> ... -> QXPRender",
                    currentHead.getClass().getSimpleName());

            QContentData result = stub.processRequest(context);

            log.info("QXPSM completed: operation=processRequest, durationMs={}, nameValueCount={}, "
                            + "modifierLayoutCount={}, streamBytes={}, textChars={}, multipartCount={}",
                    elapsedMillis(callStartNanos), nameValueCount, modifierLayoutCount,
                    result == null || result.getStreamValue() == null ? 0 : result.getStreamValue().length,
                    result == null || result.getTextData() == null ? 0 : result.getTextData().length(),
                    result == null || result.getMultipartResponse() == null
                            ? 0 : result.getMultipartResponse().length);
            return result;

        } catch (Exception e) {
            log.error("QXPSM failed: operation=processRequest, durationMs={}, causeType={}",
                    elapsedMillis(callStartNanos), e.getClass().getSimpleName());
            throw new QxpsmException("processRequest", e);
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
        long callStartNanos = System.nanoTime();
        log.info("QXPSM started: operation=getXPressDOM");
        try {
            RequestServicePortType stub = createStub(qxpsmProperties.getDomTimeoutMs());
            Project result = stub.getXPressDOM(documentName);
            log.info("QXPSM completed: operation=getXPressDOM, durationMs={}, layoutCount={}, contentCount={}",
                    elapsedMillis(callStartNanos),
                    result == null || result.getLayouts() == null ? 0 : result.getLayouts().length,
                    result == null || result.getContents() == null ? 0 : result.getContents().length);
            return result;
        } catch (Exception e) {
            log.error("QXPSM failed: operation=getXPressDOM, durationMs={}, causeType={}",
                    elapsedMillis(callStartNanos), e.getClass().getSimpleName());
            throw new QxpsmException("getXPressDOM", e);
        }
    }

    RequestServicePortType createStub(int socketTimeoutMs) throws Exception {
        RequestServiceLocator locator = new RequestServiceLocator();
        RequestServicePortType stub = locator.getRequestServiceHttpSoap11Endpoint(
                URI.create(qxpsmProperties.getEndpoint()).toURL());
        if (stub == null) {
            throw new IllegalStateException("QXPSM SOAP port is unavailable");
        }
        ((org.apache.axis.client.Stub) stub).setTimeout(socketTimeoutMs);
        return stub;
    }

    private static long elapsedMillis(long startNanos) {
        return TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startNanos);
    }
}
```

## 4. `src/main/java/com/socgen/sgs/api/quark/engine/infra/dao/impl/DynamicQueryPortImpl.java`

SHA-256: `ee2883f618ea6558ea9f3bb692506a1b7bb903c1c46ccc50062622288f9caeda`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.InParam;
import com.socgen.sgs.api.quark.engine.domain.port.DynamicQueryPort;
import com.socgen.sgs.api.quark.engine.infra.dao.TaskSqlDao;
import com.socgen.sgs.api.quark.engine.mapper.InParamSqlMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Repository;

import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * Infrastructure implementation of DynamicQueryPort.
 * Reuses existing TaskSqlDao for SQL execution and InParamSqlMapper for parameter conversion.
 *
 * Cross-reference: .NET Proxy_Generic.GetReader() used in Process_Dynamique.Get_Report()
 */
@Repository
@RequiredArgsConstructor
@Slf4j
public class DynamicQueryPortImpl implements DynamicQueryPort {

    private final TaskSqlDao taskSqlDao;
    private final InParamSqlMapper inParamSqlMapper;

    @Override
    public List<Map<String, Object>> executeQuery(String sql, Map<String, InParam> parameters) {
        log.debug("Executing Dynamic SQL; bindCount={}",
                parameters != null ? parameters.size() : 0);

        try {
            Map<String, Object> jdbcParams = inParamSqlMapper.toParameterMap(
                    parameters != null ? parameters : Collections.emptyMap());

            List<Map<String, Object>> results = taskSqlDao.executeSql(sql, jdbcParams);

            log.debug("DynamicQueryPort returned {} rows", results.size());
            return results;

        } catch (Exception e) {
            // Spring/JDBC exceptions can embed the entire statement and bind values. Preserve the
            // cause for type-based handling but never log or copy its raw message.
            log.error("Dynamic SQL execution failed; bind count [{}]", parameters != null ? parameters.size() : 0);
            throw new RuntimeException("Dynamic SQL execution failed", e);
        }
    }

}
```

## 5. `src/main/java/com/socgen/sgs/api/quark/engine/business/ProcessSqlBusiness.java`

SHA-256: `52c534652036746eb9fc94bf2049454debf8ca100e75456650e7e756b967411d`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.domain.DataNameValue;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.StoreDataType;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocLigne;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocTable;
import com.socgen.sgs.api.quark.engine.domain.helper.DataTypeHelper;
import com.socgen.sgs.api.quark.engine.domain.task.TaskException;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.enums.TaskExceptionTypeEnum;
import com.socgen.sgs.api.quark.engine.infra.dao.TaskSqlDao;
import com.socgen.sgs.api.quark.engine.mapper.InParamSqlMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/** Processes a SQL task: executes SQL, creates blocs, checks exceptions. */
@Component
@RequiredArgsConstructor
@Slf4j
public class ProcessSqlBusiness {

    private static final String NAME_BLOC_COL = "NOM_BLOC";
    private static final String VALUE_BLOC_COL = "VALEUR_BLOC";
    private static final String DESCRIPTION_BLOC_COL = "DESCRIPTION_BLOC";
    private static final String INFO_BLOC_COL = "INFO_BLOC";
    private static final String N1_END_BLOC = "N1";

    private final TaskSqlDao taskSqlDao;
    private final InParamSqlMapper inParamSqlMapper;
    private final DataTypeHelper dataTypeHelper;

    public void execute(TaskSql task) {
        Map<String, Object> parameters = inParamSqlMapper.toParameterMap(task.getRun().getInParams());
        int sqlChars = charCount(task.getSql());

        try {
            long queryStartNanos = System.nanoTime();
            List<Map<String, Object>> rows = taskSqlDao.executeSql(task.getSql(), parameters);
            log.info("SQL task completed: taskId={}, runId={}, sqlChars={}, bindCount={}, "
                            + "rowCount={}, durationMs={}",
                    task.getId(), task.getRun().getId(), sqlChars,
                    parameters == null ? 0 : parameters.size(),
                    rows.size(), TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - queryStartNanos));
            if (rows.isEmpty()) {
                log.warn("No SQL data returned for task {}", task.getId());
            } else {
                addBlocs(task, rows);
            }

            checkTaskExceptions(task);
        } catch (Exception ex) {
            // Carry the concise Oracle error (not the full SQL, which the driver embeds in the message)
            // so the upstream task-error log stays readable.
            throw new RuntimeException("SQL task " + task.getId() + " failed", ex);
        }
    }

    private void addBlocs(TaskSql task, List<Map<String, Object>> rows) {
        boolean integrerN1 = task.getRun().getRunProperties().isIntegrerN1();
        // Bitwise SQL test on the raw store-type code (the enum collapsed combined values like 0x03
        // to NONE, losing the SQL bit). (.NET Run_Base.cs:677.) Finding #1.
        boolean storeData = task.isStoreData()
                && StoreDataType.hasFlag(task.getRun().getRunProperties().getStoreDataTypeCode(), StoreDataType.SQL);
        int duplicateBlockCount = 0;
        int failedRowCount = 0;

        for (Map<String, Object> row : rows) {
            String blocName = "";
            try {
                blocName = toString(requiredValue(row, NAME_BLOC_COL));
                if (!integrerN1 && blocName.endsWith(N1_END_BLOC)) {
                    continue;
                }

                String blocValue = dataTypeHelper.outputOracleValueToString(
                        requiredValue(row, VALUE_BLOC_COL), task.getDataType(), task.getNbDecimal(),
                        task.isShowZero(), task.getNullString(), task.isDecimalSignificative());

                if (task.getBlocsUpdate().containsKey(blocName)) {
                    // Parity: .NET Process_SQL records ErrorDuplicateBlocInTask (Errors.Add(string) →
                    // Error_Type.Unspecified). Finding #37.
                    task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED, String.format(
                            "Duplicate Name Bloc in task : %s bloc : %s", task.getDebugInfo(), blocName)));
                    duplicateBlockCount++;
                    continue;
                }

                BlocBox bloc = new BlocBox(task, blocName, blocValue);
                bloc.setAction(BlocActionEnum.UPDATE);
                task.getBlocsUpdate().put(blocName, bloc);

                if (storeData) {
                    String desc = row.containsKey(DESCRIPTION_BLOC_COL) ? toString(row.get(DESCRIPTION_BLOC_COL)) : "";
                    String info = row.containsKey(INFO_BLOC_COL) ? toString(row.get(INFO_BLOC_COL)) : "";
                    task.getDataNamesValues().add(new DataNameValue(blocName, blocValue, desc, info));
                }

            } catch (Exception e) {
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED, String.format(
                        "Error when adding bloc in task : %s bloc : %s", task.getDebugInfo(), blocName)));
                failedRowCount++;
            }
        }

        if (duplicateBlockCount > 0 || failedRowCount > 0) {
            log.warn("SQL row anomalies: taskId={}, runId={}, duplicateBlocks={}, failedRows={}",
                    task.getId(), task.getRun().getId(), duplicateBlockCount, failedRowCount);
        }
    }

    private void checkTaskExceptions(TaskSql task) {
        if (task.getExceptions().isEmpty()) return;

        QxpXml xml = task.getRun().getGabarit().getQxpXml();
        String lastDestination = "";

        for (TaskException exception : task.getExceptions().values()) {
            boolean processRemove;

            if (task.getBlocsUpdate().containsKey(exception.getName())) {
                BlocBox bloc = (BlocBox) task.getBlocsUpdate().get(exception.getName());
                processRemove = bloc.getValue() == null
                        || bloc.getValue().isEmpty()
                        || bloc.getValue().equals(task.getNullString());
            } else {
                processRemove = true;
            }

            if (!processRemove) continue;

            // The conditional bloc to remove must exist in the document.
            // Cross-reference: .NET Process_SQL.Check_Task_Exception — Exist_Name guard.
            if (!xml.existName(exception.getName())) {
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "Invalid conditional block [" + exception.getName() + "] (task " + task.getId() + ")"));
                continue;
            }

            // The table being removed (or holding the rows) must exist.
            if (xml.existName(exception.getTableName())) {
                if (exception.getType() == TaskExceptionTypeEnum.LINE) {
                    // The table must hold at least the highest row index we want to remove.
                    int maxLigne = 0;
                    if (exception.getIndexLignes() != null) {
                        for (int ligne : exception.getIndexLignes()) {
                            maxLigne = Math.max(maxLigne, ligne);
                        }
                    }
                    if (xml.getNbLignes(exception.getTableName()) >= maxLigne) {
                        if (exception.getIndexLignes() != null) {
                            for (int idx : exception.getIndexLignes()) {
                                String ligneId = exception.getTableName() + "_" + idx;
                                if (!task.getBlocsModify().containsKey(ligneId)) {
                                    BlocLigne blocLigne = new BlocLigne(task, ligneId, exception.getTableName(), idx);
                                    blocLigne.setCondName(exception.getTableName());
                                    blocLigne.setAction(BlocActionEnum.REMOVE);
                                    task.getBlocsModify().put(ligneId, blocLigne);
                                    lastDestination = exception.getTableName();
                                }
                            }
                        }
                    } else {
                        task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                                "Missing rows in table [" + exception.getTableName()
                                        + "] for block [" + exception.getName() + "]"));
                    }
                } else {
                    if (!task.getBlocsModify().containsKey(exception.getTableName())) {
                        BlocTable blocTable = new BlocTable(task, exception.getTableName());
                        blocTable.setCondName(exception.getTableName());
                        blocTable.setAction(BlocActionEnum.REMOVE);
                        task.getBlocsModify().put(exception.getTableName(), blocTable);
                        lastDestination = exception.getTableName();
                    }
                }
            } else {
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "Table does not exist [" + exception.getTableName() + "]"));
            }
        }

        if (!lastDestination.isEmpty()) {
            task.setDestinationBlocName(lastDestination);
        }
    }

    private static String toString(Object value) {
        return value != null ? value.toString() : "";
    }

    private static Object requiredValue(Map<String, Object> row, String column) {
        if (!row.containsKey(column)) {
            throw new IllegalArgumentException("Required task result column is missing: " + column);
        }
        return row.get(column);
    }

    private static int charCount(String value) {
        return value == null ? 0 : value.length();
    }
}
```

## 6. `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/DynamiqueTaskProcessStrategy.java`

SHA-256: `49df30c97666886100cd4c4fe189408c2784309665a90061f9fc629844444271`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.config.EngineFormattingProperties;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DCell;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DMasterPage;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DPoint;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DReport;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DRow;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DSection;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DTable;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DZone;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.PrepareReportParameters;

import com.socgen.sgs.api.quark.engine.domain.dynamic.template.Template;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocPage;

import com.socgen.sgs.api.quark.engine.domain.element.TElement;

import com.socgen.sgs.api.quark.engine.domain.helper.DynamiqueGeometryHelper;

import com.socgen.sgs.api.quark.engine.domain.helper.DynamiquePageBreakHelper;

import com.socgen.sgs.api.quark.engine.domain.helper.MathHelper;

import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;
import com.socgen.sgs.api.quark.engine.domain.helper.CheckedDecimalArithmetic;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;

import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;

import com.socgen.sgs.api.quark.engine.domain.port.DynamicQueryPort;

import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.domain.exception.EngineException;
import com.socgen.sgs.api.quark.engine.domain.RunError;

import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;

import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;

import com.socgen.sgs.api.quark.engine.enums.AbsoluteRepeatType;

import com.socgen.sgs.api.quark.engine.service.task.TaskProcessStrategy;

import lombok.RequiredArgsConstructor;

import lombok.extern.slf4j.Slf4j;

import org.springframework.stereotype.Component;

import java.math.BigDecimal;

import java.util.ArrayList;

import java.util.Iterator;

import java.util.List;

import java.util.Map;

import java.util.concurrent.TimeUnit;

import java.util.stream.Collectors;

/**

 * Strategy for processing TaskDynamique (dynamic SQL-driven report generation).

 * Handles 4 stages:

 * <ol>

 *   <li>Get_Report: Execute SQL, build DReport structure from result rows</li>

 *   <li>Check_Report: Verify each DCell has a valid TElement from gabarit template</li>

 *   <li>Prepare_Report: Calculate geometry (position, page, column) for all elements</li>

 *   <li>Render_Boxes: Convert DReport elements into BlocBox/BlocPage for QXPS Modifier</li>

 * </ol>

 *

 * Cross-reference: QXP.Engine.Core.Business.Process_Dynamique

 */

@Component

@Slf4j

@RequiredArgsConstructor

public class DynamiqueTaskProcessStrategy implements TaskProcessStrategy<TaskDynamique> {

    // SQL column names matching .NET constants

    private static final String ID_SECTION_COL = "ID_SECTION";

    private static final String ID_TABLE_COL = "ID_TABLE";

    private static final String ID_GROUP_COL = "ID_GROUPE";

    private static final String ID_LIGNE_COL = "ID_LIGNE";

    private static final String NOM_BLOC_COL = "NOM_BLOC";

    private static final String VALEUR_BLOC_COL = "VALEUR_BLOC";

    private static final String TEMPLATE_COL = "TEMPLATE";

    private static final String ROW_LEVEL_COL = "ROW_LEVEL";

    private static final String DESCRIPTION_BLOC_COL = "DESCRIPTION_BLOC";

    private static final String INFO_BLOC_COL = "INFO_BLOC";

    // Naming patterns

    private static final String NEW_PAGE_PATTERN = "%s_P%d";

    private final DynamicQueryPort dynamicQueryPort;

    private final DocumentStructureBusiness documentStructureBusiness;
    private final EngineFormattingProperties formattingProperties;

    @Override

    public Class<TaskDynamique> getTaskType() {

        return TaskDynamique.class;

    }

    @Override

    public void process(TaskDynamique task) {

        log.debug("DynamiqueTaskProcessStrategy processing task [{}]", task.getId());

        DReport report = null;

        PrepareReportParameters prp = new PrepareReportParameters(task);

        if (task.getRun().getGabaritTemplate() == null) {
            throw new EngineException(RunError.CRITIQUE,
                    "Gabarit template is missing for dynamic task " + task.getId());

        }
        // ================================================================

        // Stage 1: Get_Report — Execute SQL and build DReport

        // ================================================================

        int sqlChars = charCount(task.getSql());
        try {

            long queryStartNanos = System.nanoTime();

            List<Map<String, Object>> rows = dynamicQueryPort.executeQuery(

                    task.getSql(), task.getRun().getInParams());

            log.info("Dynamic SQL task completed: taskId={}, runId={}, sqlChars={}, bindCount={}, "
                            + "rowCount={}, durationMs={}",
                    task.getId(), task.getRun().getId(), sqlChars,
                    task.getRun().getInParams().size(), rows != null ? rows.size() : 0,
                    TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - queryStartNanos));

            if (rows != null && !rows.isEmpty()) {

                report = getReport(prp, rows);

            } else {

                log.info("No SQL data for dynamic task [{}]", task.getId());

            }

        } catch (EngineException ex) {
            throw ex;
        } catch (Exception ex) {
            log.error("Dynamic SQL failed for task [{}], run [{}], cause [{}]",
                    task.getId(), task.getRun().getId(), ex.getClass().getSimpleName());
            throw new EngineException(RunError.CRITIQUE,
                    "Unable to execute Dynamic SQL for task " + task.getId(), ex);

        }

        // ================================================================

        // Stage 2: Check_Report — Verify TElements exist

        // ================================================================

        if (report != null) {

            checkReport(prp, report);

        }

        // ================================================================

        // Stage 3: Prepare_Report — Calculate geometry

        // ================================================================

        if (report != null) {

            prepareReport(prp, report);

        }

        // ================================================================

        // Stage 4: Render_Boxes — Build blocs from report

        // ================================================================

        renderBoxes(prp, report);

    }

    // ========================================================================

    // Stage 1: Get_Report

    // Cross-reference: Process_Dynamique.Get_Report() lines 95-220

    // ========================================================================

    private DReport getReport(PrepareReportParameters prp, List<Map<String, Object>> rows) {

        DReport report = new DReport();

        TaskDynamique task = prp.getTask();

        report.setPageBreakRules(task.getPageBreakRules());

        report.setColumnBreakRules(task.getColumnBreakRules());

        validateRequiredColumns(rows);

        // Check which optional columns exist

        boolean includeRowLevel = dynamicQueryPort.existColumn(ROW_LEVEL_COL, rows);

        boolean includeIdTable = dynamicQueryPort.existColumn(ID_TABLE_COL, rows);

        boolean includeIdSection = dynamicQueryPort.existColumn(ID_SECTION_COL, rows);

        boolean includeDescriptionBloc = dynamicQueryPort.existColumn(DESCRIPTION_BLOC_COL, rows);

        boolean includeInfoBloc = dynamicQueryPort.existColumn(INFO_BLOC_COL, rows);

        // Store data flag — bitwise SQL test so combined values (0x03 = SQL|DOCUMENT) and ALL (0xFF)
        // are both honoured. (.NET Run_Base.cs:677 (Store_Type & SQL) == SQL.) Finding #1.

        boolean storeData = task.isStoreData()
                && com.socgen.sgs.api.quark.engine.domain.StoreDataType.hasFlag(
                task.getRun().getRunProperties().getStoreDataTypeCode(),
                com.socgen.sgs.api.quark.engine.domain.StoreDataType.SQL);
        // Tracking state

        int lastIdSection = Integer.MIN_VALUE;

        int lastIdGroupe = Integer.MIN_VALUE;

        int lastIdTable = Integer.MIN_VALUE;

        int lastIdLigne = Integer.MIN_VALUE;

        DSection currentDSection = null;

        DCell currentDCell = null;

        DRow currentDRow = null;

        DTable currentDTable = null;

        Template currentTemplate = null;

        for (Map<String, Object> row : rows) {

            int idGroupe = getIntValue(row, ID_GROUP_COL);

            int idLigne = getIntValue(row, ID_LIGNE_COL);

            String newName = getStringValue(row, NOM_BLOC_COL);

            String data = getStringValue(row, VALEUR_BLOC_COL);

            String templateName = getStringValue(row, TEMPLATE_COL);

            int rowLevel = includeRowLevel ? getIntValue(row, ROW_LEVEL_COL) : Integer.MIN_VALUE;

            int idTable = includeIdTable ? getIntValue(row, ID_TABLE_COL) : Integer.MIN_VALUE;

            int idSection = includeIdSection ? getIntValue(row, ID_SECTION_COL) : Integer.MIN_VALUE;

            String descriptionBloc = includeDescriptionBloc ? getStringValue(row, DESCRIPTION_BLOC_COL) : "";

            String infoBloc = includeInfoBloc ? getStringValue(row, INFO_BLOC_COL) : "";

            // Change detection

            boolean newSection = (idSection != lastIdSection);

            boolean newGroup = (idGroupe != lastIdGroupe);

            boolean newLigne = (idLigne != lastIdLigne);

            boolean newTable = (idTable != lastIdTable);

            lastIdSection = idSection;

            lastIdGroupe = idGroupe;

            lastIdLigne = idLigne;

            lastIdTable = idTable;

            // New section

            if (currentDSection == null || newSection) {

                currentDSection = new DSection();

                report.getSections().add(currentDSection);

                newTable = true;

                newGroup = true;

                currentDTable = null;

            }

            // New group → resolve template

            if (newGroup) {

                if (task.getRun().getTemplates().containsKey(templateName)) {

                    currentTemplate = task.getRun().getTemplates().get(templateName);

                } else {

                    Template newTemplate = new Template();

                    newTemplate.setName(templateName);

                    newTemplate.setSrcName(templateName);

                    task.getRun().getTemplates().put(templateName, newTemplate);

                    currentTemplate = newTemplate;

                }

            }

            // New line or new group → create cell

            if (newLigne || newGroup) {

                currentDCell = new DCell(currentTemplate);

                if (currentTemplate.isAbsolute()) {

                    // Absolute: add directly to section cells

                    currentDSection.getCells().add(currentDCell);

                } else {

                    // Relative: add to table

                    if (currentDTable == null || newTable) {

                        currentDTable = new DTable();

                        currentDTable.setNewPage(task.isNewPageTable());

                        currentDSection.getTables().add(currentDTable);

                        newLigne = true;

                    }

                    if (newLigne) {

                        currentDRow = new DRow();

                        currentDTable.getRows().add(currentDRow);

                        if (rowLevel != Integer.MIN_VALUE) {

                            currentDRow.setLevel(rowLevel);

                        }

                    }

                    currentDRow.getCells().add(currentDCell);

                }

            }

            // Add value and name to current cell

            currentDCell.getValues().add(data);

            currentDCell.getNewNames().add(newName);

            // Store data if configured

            if (storeData) {

                task.getDataNamesValues().add(

                        new com.socgen.sgs.api.quark.engine.domain.DataNameValue(

                                newName, data, descriptionBloc, infoBloc));

            }

        }

        return report;

    }

    // ========================================================================

    // Stage 2: Check_Report

    // Cross-reference: Process_Dynamique.Check_Report() lines 225-295

    // ========================================================================

    private void checkReport(PrepareReportParameters prp, DReport report) {

        TaskDynamique task = prp.getTask();

        boolean activeOverflowTemplate = !task.getOverflowBoxes().isEmpty();

        // Accepted ordering: SQL first; only a non-empty report needs the template project.
        ensureTemplateProject(task);

        QxpProject qxpProject = task.getRun().getGabaritTemplate().getQxpProject();

        qxpProject.analyse(task, true);

        List<DSection> sections2Remove = new ArrayList<>();

        for (DSection section : report.getSections()) {

            // Check absolute cells

            List<DCell> cells2Remove = new ArrayList<>();

            for (DCell cell : section.getCells()) {

                cell.setOverflow(activeOverflowTemplate && cell.containsOneNewName(task.getOverflowBoxes()));

                cell.setTElement(evaluateTElement(task, cell));

                if (cell.getTElement() == null) {

                    cells2Remove.add(cell);

                }

            }

            section.getCells().removeAll(cells2Remove);

            // Check relative cells in tables

            List<DTable> tables2Remove = new ArrayList<>();

            for (DTable table : section.getTables()) {

                List<DRow> rows2Remove = new ArrayList<>();

                for (DRow row : table.getRows()) {

                    cells2Remove = new ArrayList<>();

                    for (DCell cell : row.getCells()) {

                        cell.setOverflow(activeOverflowTemplate && cell.containsOneNewName(task.getOverflowBoxes()));

                        cell.setTElement(evaluateTElement(task, cell));

                        if (cell.getTElement() == null) {

                            cells2Remove.add(cell);

                        }

                    }

                    row.getCells().removeAll(cells2Remove);

                    if (row.getCells().isEmpty()) {

                        rows2Remove.add(row);

                    }

                }

                table.getRows().removeAll(rows2Remove);

                if (table.getRows().isEmpty()) {

                    tables2Remove.add(table);

                }

            }

            section.getTables().removeAll(tables2Remove);

            if (section.getTables().isEmpty() && section.getCells().isEmpty()) {

                sections2Remove.add(section);

            }

        }

        report.getSections().removeAll(sections2Remove);

    }


    /**

     * Build and cache the gabarit-template document's project once per run. The template document

     * is uploaded to the pool during the Prepare phase; its structure is fetched and parsed here so

     * the report cells can resolve their specimen boxes against it.

     */

    private void ensureTemplateProject(TaskDynamique task) {

        DocumentDomain template = task.getRun().getGabaritTemplate();

        documentStructureBusiness.ensureProject(task.getRun(), template);

    }

    /**

     * Evaluate the TElement for a cell from the gabarit template project.

     * Selects srcName or srcNameOverflow based on cell.overflow flag.

     *

     * Cross-reference: TElement_Helper.Evaluate_TElement()

     */

    private TElement evaluateTElement(TaskDynamique task, DCell cell) {

        String srcName;

        if (cell.isOverflow()) {

            srcName = cell.getTemplate().getSrcNameOverflow();

        } else {

            srcName = cell.getTemplate().getSrcName();

        }

        QxpProject qxpProject = task.getRun().getGabaritTemplate().getQxpProject();

        Map<String, TElement> elements = qxpProject.getElements();

        if (elements != null && elements.containsKey(srcName)) {

            return elements.get(srcName);

        } else {
            task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                    "Dynamic template element is missing for task " + task.getId()));
            log.warn("Dynamic template element is missing for task [{}], run [{}]",
                    task.getId(), task.getRun().getId());
            return null;

        }

    }

    // ========================================================================

    // Stage 3: Prepare_Report

    // Cross-reference: Process_Dynamique.Prepare_Report() lines 300-530

    // ========================================================================

    private void prepareReport(PrepareReportParameters prp, DReport report) {

        TaskDynamique task = prp.getTask();

        // Evaluate available height between anchors

        if (task.getStartAnchor() != null && task.getEndAnchor() != null) {

            if (task.getStartAnchor().getBottom().compareTo(task.getEndAnchor().getTop()) < 0
                    && task.getStartAnchor().getLeft().compareTo(task.getStartAnchor().getRight()) < 0) {

                prp.setAvailableHeight(CheckedDecimalArithmetic.subtract(
                        task.getEndAnchor().getTop(), task.getStartAnchor().getBottom()));

                prp.setAvailableWidth(CheckedDecimalArithmetic.subtract(
                        task.getEndAnchor().getLeft(), task.getStartAnchor().getRight()));

            } else {

                throw new EngineException(RunError.BLOQUANTE,
                        "Dynamic task anchors are incoherent for task " + task.getId());

            }

        }

        for (DSection section : report.getSections()) {

            prepareReportSection(prp, report, section);

        }

        // If control overflow, memorize box names

        if (task.isControlOverflow()) {

            task.getBoxNames().clear();

            for (DSection section : report.getSections()) {

                for (DCell cell : section.getCells()) {

                    task.getBoxNames().addAll(cell.getNewNames());

                }

                for (DTable table : section.getTables()) {

                    for (DRow row : table.getRows()) {

                        for (DCell cell : row.getCells()) {

                            task.getBoxNames().addAll(cell.getNewNames());

                        }

                    }

                }

            }

        }

        report.getInfo().setNbPage(prp.getPage());

    }

    private void prepareReportSection(PrepareReportParameters prp, DReport report, DSection section) {

        TaskDynamique task = prp.getTask();

        int cellLogicalId = 0;

        boolean firstTable = true;

        BigDecimal tableHeight = BigDecimal.ZERO;

        BigDecimal tableWidth = BigDecimal.ZERO;

        BigDecimal maxWidth = BigDecimal.ZERO;

        DPoint cursor = new DPoint(task.getStartAnchor().getRight(), task.getStartAnchor().getBottom());

        DPoint cursorBreak = new DPoint(cursor);

        prp.reset();

        prp.setPage(prp.getPage() + 1);

        DMasterPage master = DMasterPage.DEFAULT;

        section.getInfo().setMasterPage(master);

        List<DRow> currentPageBreakRows = new ArrayList<>();

        List<DRow> currentColumnBreakRows = new ArrayList<>();

        // ---- Prepare absolute cells ----

        for (DCell cell : section.getCells()) {

            cell.getInfo().setPage(prp.getPage());

            cell.setLogicalId(++cellLogicalId);

            cell.getInfo().setZone(DynamiqueGeometryHelper.getZone(null, cell));

            int absRepeat = cell.getTemplate().getAbsoluteRepeat();

            if (AbsoluteRepeatType.hasOtherPage(absRepeat)) {

                prp.getRepeatedCells().add(cell);

                if (!AbsoluteRepeatType.hasFirstPage(absRepeat)
                        && absRepeat != 0) {

                    cell.downgradeGeneration();

                }

            }

            if (AbsoluteRepeatType.hasLastPage(absRepeat)) {

                prp.getLastCells().add(cell);

            }

        }

        // Remove absolute cells not on first page or default (raw 0 == .NET Absolute_Repeat_Type.Default)

        section.getCells().removeIf(cell ->

                !(AbsoluteRepeatType.hasFirstPage(cell.getTemplate().getAbsoluteRepeat())

                        || cell.getTemplate().getAbsoluteRepeat() == 0));
        // ---- Process relative cells in tables ----

        for (DTable table : section.getTables()) {

            if (!firstTable) {

                if (table.isNewPage()) {

                    prp.setPage(prp.getPage() + 1);

                    tableHeight = BigDecimal.ZERO;

                    prp.setColumn(1);

                    tableWidth = BigDecimal.ZERO;

                    maxWidth = BigDecimal.ZERO;

                    addAbsoluteCells(prp, section);

                    cursor.reset(task.getStartAnchor().getRight(), task.getStartAnchor().getBottom());

                }

            } else {

                firstTable = false;

                prp.setColumn(1);

                tableWidth = BigDecimal.ZERO;

                maxWidth = BigDecimal.ZERO;

            }

            int maxRows = table.getRows().size();

            for (int indexRow = 0; indexRow < maxRows; indexRow++) {

                DRow row = table.getRows().get(indexRow);

                // Handle break rows (page/column header repetition)

                if (row.isPageBreak() || row.isColumnBreak()) {

                    prp.getRows2Remove().add(row);

                    if (row.isPageBreak()) {

                        int existingIndex = findBreakRowByLevel(currentPageBreakRows, row.getLevel());

                        if (existingIndex >= 0) {

                            DRow oldRow = currentPageBreakRows.get(existingIndex);

                            transferRowCellsInfo(oldRow, row);

                            currentPageBreakRows = new ArrayList<>(currentPageBreakRows);

                            currentPageBreakRows.set(existingIndex, row);

                        } else {

                            prepareReportCells(prp, row, cursorBreak);

                            currentPageBreakRows = new ArrayList<>(currentPageBreakRows);

                            currentPageBreakRows.add(row);

                            cursorBreak.setLeft(task.getStartAnchor().getRight());

                            cursorBreak.setTop(CheckedDecimalArithmetic.add(
                                    cursorBreak.getTop(), row.getInfo().getHeight()));

                        }

                    }

                    if (row.isColumnBreak()) {

                        int existingIndex = findBreakRowByLevel(currentColumnBreakRows, row.getLevel());

                        if (existingIndex >= 0) {

                            DRow oldRow = currentColumnBreakRows.get(existingIndex);

                            transferRowCellsInfo(oldRow, row);

                            currentColumnBreakRows = new ArrayList<>(currentColumnBreakRows);

                            currentColumnBreakRows.set(existingIndex, row);

                        } else {

                            prepareReportCells(prp, row, cursorBreak);

                            currentColumnBreakRows = new ArrayList<>(currentColumnBreakRows);

                            currentColumnBreakRows.add(row);

                            cursorBreak.setLeft(task.getStartAnchor().getRight());

                            cursorBreak.setTop(CheckedDecimalArithmetic.add(
                                    cursorBreak.getTop(), row.getInfo().getHeight()));

                        }

                    }

                    downgradeReportCells(row);

                    continue;

                }

                // Normal row processing

                row.setPageBreakRows(currentPageBreakRows);

                row.setColumnBreakRows(currentColumnBreakRows);

                prepareReportCells(prp, row, cursor);

                tableHeight = CheckedDecimalArithmetic.add(tableHeight, row.getInfo().getHeight());

                // Check if overflow

                if (tableHeight.compareTo(prp.getAvailableHeight()) > 0) {

                    if (prp.getColumn() < task.getNbColumn()) {

                        // New column

                        prp.setColumn(prp.getColumn() + 1);

                        tableWidth = CheckedDecimalArithmetic.add(
                                CheckedDecimalArithmetic.add(tableWidth, maxWidth), task.getColumnSpace());

                        DynamiquePageBreakHelper.updateRows(report, table.getRows(), row, prp, false, tableWidth);

                        tableHeight = prp.getCurrentTableHeight();

                        maxWidth = prp.getCurrentTableWidth();

                        indexRow += prp.getNbRowsAdded();

                        maxRows += prp.getNbRowsAdded();

                    } else {

                        // New page

                        prp.setPage(prp.getPage() + 1);

                        prp.setColumn(1);

                        DynamiquePageBreakHelper.updateRows(report, table.getRows(), row, prp, true, BigDecimal.ZERO);

                        tableHeight = prp.getCurrentTableHeight();

                        tableWidth = BigDecimal.ZERO;

                        maxWidth = prp.getCurrentTableWidth();

                        indexRow += prp.getNbRowsAdded();

                        maxRows += prp.getNbRowsAdded();

                        addAbsoluteCells(prp, section);

                    }

                } else {

                    maxWidth = maxWidth.max(row.getInfo().getWidth());

                }

                cursor.setLeft(CheckedDecimalArithmetic.add(
                        task.getStartAnchor().getRight(), tableWidth));

                cursor.setTop(CheckedDecimalArithmetic.add(
                        task.getStartAnchor().getBottom(), tableHeight));

            }

            // Remove break rows from table

            table.getRows().removeAll(prp.getRows2Remove());

        }

        // Add last absolute cells

        addLastAbsoluteCells(prp, section);

    }

    private void prepareReportCells(PrepareReportParameters prp, DRow row, DPoint cursor) {

        BigDecimal rowHeight = BigDecimal.ZERO;

        BigDecimal rowWidth = BigDecimal.ZERO;

        boolean heightPercent = row.getInfo().getHeight().compareTo(BigDecimal.ZERO) != 0;

        for (DCell cell : row.getCells()) {

            cell.getInfo().setPage(prp.getPage());

            BigDecimal cellHeight;

            if (heightPercent) {

                cellHeight = MathHelper.getValPercent(row.getInfo().getHeight(), cell.getTemplate().getHeightPercent());

            } else {

                cellHeight = DynamiqueGeometryHelper.getCellHeightWithTop(cell);

            }

            rowHeight = rowHeight.max(cellHeight);

            rowWidth = CheckedDecimalArithmetic.add(
                    rowWidth, DynamiqueGeometryHelper.getCellWidthWithLeft(cell));

            cell.getInfo().setZone(DynamiqueGeometryHelper.getZoneAndUpdateCursor(cursor, cell));

        }

        row.getInfo().setHeight(rowHeight);

        row.getInfo().setWidth(rowWidth);

        row.getInfo().setPage(prp.getPage());

        row.getInfo().setColumn(prp.getColumn());

    }

    private void downgradeReportCells(DRow row) {

        for (DCell cell : row.getCells()) {

            cell.downgradeGeneration();

        }

    }

    private void transferRowCellsInfo(DRow oldRow, DRow newRow) {

        newRow.setInfo(oldRow.getInfo());

        for (int i = 0; i < oldRow.getCells().size(); i++) {

            newRow.getCells().get(i).setInfo(oldRow.getCells().get(i).getInfo());

        }

    }

    private void addAbsoluteCells(PrepareReportParameters prp, DSection section) {

        for (DCell srcCell : prp.getRepeatedCells()) {

            DCell newCell = srcCell.cloneCell();

            newCell.getInfo().setPage(prp.getPage());

            section.getCells().add(newCell);

        }

    }

    private void addLastAbsoluteCells(PrepareReportParameters prp, DSection section) {

        List<DCell> cellsInLastPage = section.getCells().stream()

                .filter(c -> c.getInfo().getPage() == prp.getPage())

                .collect(Collectors.toList());

        for (DCell srcCell : prp.getLastCells()) {

            boolean alreadyExists = cellsInLastPage.stream()

                    .anyMatch(c -> c.equalsCell(srcCell));

            if (!alreadyExists) {

                DCell newCell = srcCell.cloneCell();

                newCell.getInfo().setPage(prp.getPage());

                section.getCells().add(newCell);

            }

        }

    }

    private int findBreakRowByLevel(List<DRow> breakRows, int level) {

        for (int i = 0; i < breakRows.size(); i++) {

            if (breakRows.get(i).getLevel() == level) {

                return i;

            }

        }

        return -1;

    }

    // ========================================================================

    // Stage 4: Render_Boxes

    // Cross-reference: Process_Dynamique.Render_Boxes() lines 535-610

    // ========================================================================

    private void renderBoxes(PrepareReportParameters prp, DReport report) {

        TaskDynamique task = prp.getTask();

        int nbNewPage;

        if (report == null) {

            nbNewPage = 1;

        } else {

            nbNewPage = report.getInfo().getNbPage();

        }

        // 1. Create new pages

        for (int i = 0; i < nbNewPage; i++) {

            BlocPage blocPage = new BlocPage(task,

                    String.format(NEW_PAGE_PATTERN, task.getDestinationBlocName(), i));

            blocPage.setAction(BlocActionEnum.CREATE);

            blocPage.setRelativePage(i);

            task.getBlocsModify().put(blocPage.getName(), blocPage);

        }

        // 2. Remove old pages

        int nbAnciennePage = task.getNbAnciennePage();

        for (int i = 0; i < nbAnciennePage; i++) {

            int relativeRemovePage = nbNewPage + i;

            BlocPage blocPage = new BlocPage(task,

                    String.format(NEW_PAGE_PATTERN, task.getDestinationBlocName(), relativeRemovePage));

            blocPage.setAction(BlocActionEnum.REMOVE);

            blocPage.setRelativePage(relativeRemovePage);

            task.getBlocsModify().put(blocPage.getName(), blocPage);

        }

        // 3. Move start anchor to first new page

        BlocBox blocStart = TElementHelper.getMoveAnchor(
                task, task.getStartAnchor(), 0, formattingProperties.getDecimalSeparator());

        if (blocStart != null) {

            blocStart.setPagination(true);

            task.getBlocsModify().put(blocStart.getName(), blocStart);

        }

        // 4. Move end anchor to last new page

        BlocBox blocEnd = TElementHelper.getMoveAnchor(
                task, task.getEndAnchor(), nbNewPage - 1, formattingProperties.getDecimalSeparator());

        if (blocEnd != null) {

            blocEnd.setPagination(true);

            task.getBlocsModify().put(blocEnd.getName(), blocEnd);

        }

        // 5. Create blocs from report cells

        DynamicCellAnomalies cellAnomalies = new DynamicCellAnomalies();

        if (report != null) {

            for (DSection section : report.getSections()) {

                // Absolute cells

                for (DCell cell : section.getCells()) {

                    addDCellBlocs(cell, task, cellAnomalies);

                }

                // Relative cells

                for (DTable table : section.getTables()) {

                    for (DRow row : table.getRows()) {

                        for (DCell cell : row.getCells()) {

                            addDCellBlocs(cell, task, cellAnomalies);

                        }

                    }

                }

            }

        }

        if (cellAnomalies.hasAny()) {
            log.warn("Dynamic cell anomalies: taskId={}, runId={}, duplicateBlocks={}, "
                            + "unsupportedCells={}, failedCells={}",
                    task.getId(), task.getRun().getId(), cellAnomalies.duplicateBlocks,
                    cellAnomalies.unsupportedCells, cellAnomalies.failedCells);
        }

    }

    /**

     * Convert a DCell into bloc(s) and add to the task.

     *

     * Cross-reference: Process_Dynamique.Add_DCell_Blocs()

     */

    private void addDCellBlocs(DCell dCell, TaskDynamique task, DynamicCellAnomalies anomalies) {

        try {

            BlocBase bloc = TElementHelper.getBloc(dCell, task);

            if (bloc != null) {

                if (task.getBlocsModify().containsKey(bloc.getName())) {
                    task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                            "Duplicate generated block in dynamic task " + task.getId()));
                    anomalies.duplicateBlocks++;
                } else {

                    task.getBlocsModify().put(bloc.getName(), bloc);

                }

            } else {
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "Dynamic cell produced no supported block for task " + task.getId()));
                anomalies.unsupportedCells++;
            }

        } catch (Exception ex) {

            task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                    "Unable to add one Dynamic cell block for task " + task.getId()));
            anomalies.failedCells++;

        }

    }

    private static final class DynamicCellAnomalies {
        private int duplicateBlocks;
        private int unsupportedCells;
        private int failedCells;

        private boolean hasAny() {
            return duplicateBlocks > 0 || unsupportedCells > 0 || failedCells > 0;
        }
    }

    // ========================================================================

    // Utility methods

    // ========================================================================

    private int getIntValue(Map<String, Object> row, String column) {
        Object val = getColumnValue(row, column);

        if (val == null) return Integer.MIN_VALUE;

        try {
            BigDecimal decimal = val instanceof BigDecimal
                    ? (BigDecimal) val : new BigDecimal(val.toString().trim());
            return CheckedDecimalArithmetic.toInt32Truncate(decimal);
        } catch (NumberFormatException e) {

            return Integer.MIN_VALUE;

        }

    }

    private String getStringValue(Map<String, Object> row, String column) {
        Object val = getColumnValue(row, column);

        return val != null ? val.toString() : "";

    }

    private void validateRequiredColumns(List<Map<String, Object>> rows) {
        for (String required : List.of(
                ID_GROUP_COL, ID_LIGNE_COL, NOM_BLOC_COL, VALEUR_BLOC_COL, TEMPLATE_COL)) {
            if (!dynamicQueryPort.existColumn(required, rows)) {
                throw new IllegalStateException("Missing required Dynamic result column " + required);
            }
        }
    }

    private Object getColumnValue(Map<String, Object> row, String column) {
        for (Map.Entry<String, Object> entry : row.entrySet()) {
            if (entry.getKey() != null && entry.getKey().equalsIgnoreCase(column)) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static int charCount(String value) {
        return value == null ? 0 : value.length();
    }

}
```

## 7. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImpl.java`

SHA-256: `e56f68e58d0dacb12b02c9d73663dbb5e4d343e46ade9ab525b9f1d87044b5d0`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunTask;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.exception.EngineException;
import com.socgen.sgs.api.quark.engine.diagnostic.DiagnosticContext;
import com.socgen.sgs.api.quark.engine.service.ProcessTasksService;
import com.socgen.sgs.api.quark.engine.service.task.TaskPostProcessService;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Implements the Prepare phase and the 3-pass task processing loop.
 * Cross-reference: .NET Run_Base.Prepare() and Run_Base.Process().
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ProcessTasksServiceImpl implements ProcessTasksService {

    /** RunError categories, matching .NET Error_Type: 1=Unspecified, 2=Critique, 3=Bloquante. */
    private static final int CRITIQUE = RunError.CRITIQUE;

    private final TaskProcessService taskProcessService;
    private final TaskPostProcessService taskPostProcessService;

    /** Max blocs per modify step (.NET EngineCoreSetting Step_Limit). Configurable via application.yaml. */
    @Value("${engine.step-limit}")
    private int stepLimit;

    /**
     * Prepare phase — call prepare() on EVERY task (not just todo), before processing.
     * Per-task failures are recorded as Critique errors and flag the task in error.
     * Cross-reference: .NET Run_Base.Prepare() (iterates _tasks.Values).
     */
    @Override
    public void prepareTasks(Run run) {
        log.info("Preparing tasks for runId: {}", run.getId());

        for (TaskBase task : run.getTasks().values()) {
            try (DiagnosticContext ignored = DiagnosticContext.task(task.getId())) {
                run.trace("Task " + task.getId() + " prepare started, type="
                        + task.getClass().getSimpleName());
                log.debug("Preparing task {}", task.getId());
                executeTaskPhase(task::prepare,
                        "Error while preparing task " + task.getId() + " for " + run.getDebugInfo());
            } catch (EngineException controlled) {
                task.setInError(true);
                // Accepted Prepare persists only the safe outer phase message, not the inner chain.
                run.getErrors().add(new RunError(CRITIQUE, controlled.getMessage()));
                log.error("Task phase failed: phase [prepare], task [{}], run [{}], cause [{}]",
                        task.getId(), run.getId(), causeType(controlled));
            } finally {
                run.trace("Task " + task.getId() + " prepare ended, inError=" + task.isInError());
            }
        }

        log.info("Task preparation completed for runId: {}", run.getId());
    }

    @Override
    public void processTasks(Run run) {
        log.info("Processing tasks for runId: {}", run.getId());

        // Fresh step aggregator for this processing pass.
        // Cross-reference: .NET Run_Base.Process() — `_run_Task = new Run_Task(this)`.
        RunTask runTask = new RunTask(run, stepLimit);
        run.setRunTask(runTask);

        // Pass 1: Reset + Process each task
        for (TaskBase task : run.getTasks().values()) {
            if (!task.isTodo()) continue;
            if (task.isInError()) {
                logTaskResult(task);
                continue;
            }
            try (DiagnosticContext ignored = DiagnosticContext.task(task.getId())) {
                run.trace("Task " + task.getId() + " processing started, type="
                        + task.getClass().getSimpleName());
                // A task in degraded mode is NOT reset/processed; it is reported as a fail-soft error.
                // Cross-reference: .NET Process() — Errors.Add(Critique, TaskFailSoftMode) and skip.
                if (task.isModeDegrade()) {
                    run.getErrors().add(new RunError(CRITIQUE,
                            "Task " + task.getId() + " is in degraded mode (fail-soft) and was not processed"));
                    log.warn("Task {} is in degraded mode (fail-soft), not processed", task.getId());
                    continue;
                }
                log.debug("Processing task {}", task.getId());
                try {
                    executeTaskPhase(task::resetProcess,
                            "Error while resetting task " + task.getId() + " for " + run.getDebugInfo());
                } catch (EngineException controlled) {
                    recordTaskPhaseFailure(run, task, "reset", controlled);
                    continue;
                }
                try {
                    executeTaskPhase(() -> taskProcessService.process(task),
                            "Error while processing task " + task.getId() + " for " + run.getDebugInfo());
                } catch (EngineException controlled) {
                    recordTaskPhaseFailure(run, task, "process", controlled);
                    continue;
                }
                log.debug("Task {} produced {} update blocks and {} structural blocks",
                        task.getId(), task.getBlocsUpdate().size(), task.getBlocsModify().size());
            } catch (Exception ex) {
                task.setInError(true);
                run.getErrors().add(new RunError(CRITIQUE, "Unable to execute task " + task.getId()));
                log.error("Task processing failed: task [{}], run [{}], cause [{}]",
                        task.getId(), run.getId(), ex.getClass().getSimpleName());
            } finally {
                run.trace("Task " + task.getId() + " processing ended, inError=" + task.isInError()
                        + ", updateCount=" + task.getBlocsUpdate().size()
                        + ", modifyCount=" + task.getBlocsModify().size());
                logTaskResult(task);
            }
        }

        // Pass 2: Post-process each task (e.g. DID, which needs all other tasks done first)
        for (TaskBase task : run.getTasks().values()) {
            if (!task.isTodo()) continue;
            if (task.isInError() || task.isModeDegrade()) continue;
            try (DiagnosticContext ignored = DiagnosticContext.task(task.getId())) {
                run.trace("Task " + task.getId() + " post-processing started");
                log.debug("Post-processing task {}", task.getId());
                executeTaskPhase(() -> taskPostProcessService.postProcess(task),
                        "Error while post-processing task " + task.getId() + " for " + run.getDebugInfo());
                log.debug("Task {} post-process produced {} update blocks and {} structural blocks",
                        task.getId(), task.getBlocsUpdate().size(), task.getBlocsModify().size());
            } catch (EngineException controlled) {
                task.setInError(true);
                run.getErrors().add(new RunError(CRITIQUE, controlled.getSafeMessageChain()));
                log.error("Task phase failed: phase [post-process], task [{}], run [{}], cause [{}]",
                        task.getId(), run.getId(), causeType(controlled));
            } catch (Exception ex) {
                task.setInError(true);
                run.getErrors().add(new RunError(CRITIQUE, "Unable to execute task " + task.getId()));
                log.error("Task post-processing failed: task [{}], run [{}], cause [{}]",
                        task.getId(), run.getId(), ex.getClass().getSimpleName());
            } finally {
                run.trace("Task " + task.getId() + " post-processing ended, inError=" + task.isInError()
                        + ", updateCount=" + task.getBlocsUpdate().size()
                        + ", modifyCount=" + task.getBlocsModify().size());
            }
        }

        // Pass 3: Verify — a task with no blocs is an error; otherwise register its blocs
        for (TaskBase task : run.getTasks().values()) {
            if (!task.isTodo()) continue;
            if (task.isInError() || task.isModeDegrade()) continue;
            if (task.getBlocsUpdate().isEmpty() && task.getBlocsModify().isEmpty()) {
                // .NET Run_Base.Process pass 3: Errors.Add(TaskSansBloc, ...) → Unspecified (1), not Critique.
                run.getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "Task " + task.getId() + " did not generate any block"));
                log.warn("Task [{}] in run [{}] has no blocks after processing",
                        task.getId(), run.getId());
            } else {
                run.getRunTask().addTask(task);
                log.debug("Task {} added to its run step with {} update blocks and {} structural blocks",
                        task.getId(), task.getBlocsUpdate().size(), task.getBlocsModify().size());
            }
        }

        log.info("Task processing completed for runId: {}", run.getId());
    }

    private static void executeTaskPhase(Runnable phase, String safeMessage) {
        try {
            phase.run();
        } catch (Exception ex) {
            throw new EngineException(CRITIQUE, safeMessage, ex);
        }
    }

    private static String causeType(EngineException exception) {
        Throwable cause = exception.getCause();
        return cause != null ? cause.getClass().getSimpleName() : exception.getClass().getSimpleName();
    }

    private static void logTaskResult(TaskBase task) {
        log.info("Task result: taskId={}, taskType={}, inError={}, updateBlocks={}, "
                        + "modifyBlocks={}, storedDataRows={}",
                task.getId(), task.getClass().getSimpleName(), task.isInError(),
                task.getBlocsUpdate().size(), task.getBlocsModify().size(),
                task.getDataNamesValues().size());
    }

    private static void recordTaskPhaseFailure(
            Run run, TaskBase task, String phase, EngineException controlled) {
        task.setInError(true);
        run.getErrors().add(new RunError(CRITIQUE, controlled.getSafeMessageChain()));
        log.error("Task phase failed: phase [{}], task [{}], run [{}], cause [{}]",
                phase, task.getId(), run.getId(), causeType(controlled));
    }
}
```

## 8. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java`

SHA-256: `71395673300191d4a1e94347fa4dee2683f3ee8b0325190cfaa48a156789dd04`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.business.*;
import com.socgen.sgs.api.quark.engine.domain.*;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDocument;
import com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult;
import com.socgen.sgs.api.quark.engine.dto.RunIdDto;
import com.socgen.sgs.api.quark.engine.diagnostic.DiagnosticContext;
import com.socgen.sgs.api.quark.engine.diagnostic.SafeDiagnostic;
import com.socgen.sgs.api.quark.engine.service.*;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.TreeMap;

@Service
@Slf4j
@RequiredArgsConstructor
public class ProcessRunServiceImpl implements ProcessRunService {

    private final RunStartUpdateBusiness   runStartUpdateBusiness;
    private final GetRunPropertiesBusiness getRunPropertiesBusiness;
    private final GetGabaritBusiness       getGabaritBusiness;
    private final DocumentStructureBusiness documentStructureBusiness;
    private final GetInParamsBusiness      getInParamsBusiness;
    private final LoadTasksService         loadTasksService;
    private final FilePoolPort             filePoolPort;
    private final DocumentIdentityPort     documentIdentityPort;
    private final ProcessTasksService      processTasksService;
    private final QxpsCallerService        qxpsCallerService;
    private final CheckService             checkService;
    private final LoadTemplatesBusiness    loadTemplatesBusiness;
    private final LoadTaskDocumentsBusiness loadTaskDocumentsBusiness;
    private final GetDocumentByIdBusiness getDocumentByIdBusiness;
    private final EndRunBusiness           endRunBusiness;

    @Value("${qxps.pool.default-path}")
    private String qxpsPoolDefaultPath;

    private final RunFactory runFactory;
    private final SafeDiagnostic safeDiagnostic;

    @Override
    public Run runProcessor(RunIdDto runIdDto) {
        return runProcessor(runIdDto, new RunExecutionContext(runIdDto.getRunId()));
    }

    @Override
    public Run runChildProcessor(RunIdDto runIdDto, RunExecutionContext executionContext) {
        return runProcessor(runIdDto, executionContext);
    }

    @Override
    public Run runPreviousChildProcessor(RunIdDto runIdDto, RunExecutionContext executionContext) {
        Run run = runFactory.create();
        run.setId(runIdDto.getRunId());
        run.setExecutionContext(executionContext);
        run.setStatus(RunStatus.TO_GENERATE);
        run.setStartDate(LocalDateTime.now());
        run.setAudit(RunAudit.start(LocalDateTime.now()));

        DiagnosticContext diagnosticContext = DiagnosticContext.child(run.getId());
        try {
            // Run_Previous.Start is a no-op, but Launch still changes its in-memory status.
            run.setStatus(RunStatus.RUNNING);
            run.trace("Previous child run " + run.getId() + " started");

            RunProperties properties = getRunProperties(runIdDto);
            properties.setRunId(executionContext.getRootRunId());
            run.setRunProperties(properties);

            // Run_Previous inherits Run.LoadTasks and Run_Base.Prepare/Check. It overrides only
            // gabarit/in-param/template loading, Process, Process_Steps, Start and End.
            loadTasksService.loadTasks(run);
            processTasksService.prepareTasks(run);
            loadTaskDocumentsBusiness.loadDocuments(run);
            checkService.check(run);

            int idLastQxp = properties.getIdLastQxp();
            if (idLastQxp != Integer.MIN_VALUE) {
                DocumentDomain document = getDocumentByIdBusiness.getDocumentById(idLastQxp);
                if (document == null) {
                    // .NET assigns the null result then dereferences it during Addfile; Launch
                    // converts that unexpected failure into a blocking child-run error.
                    throw new IllegalStateException("Previous child QXP document is unavailable");
                }
                document.setFilePoolPath(run.getPoolPath(document.getFileName()));
                document.setFileFullPath(run.getPoolPathAbsolute(
                        document.getFileName(), qxpsPoolDefaultPath));
                filePoolPort.addFile(executionContext, document.getFilePoolPath(), document.getData());
                run.getResult().setFinalQxp(document);
            } else {
                run.getErrors().add(new RunError(RunError.UNSPECIFIED,
                        "Child run " + run.getId() + " has no generated QXP document"));
            }

            run.setStatus(RunStatus.GENERATED);
        } catch (Exception failure) {
            run.setStatus(RunStatus.ERROR);
            run.getErrors().add(new RunError(RunError.BLOQUANTE,
                    "Previous child run " + run.getId() + " failed"));
            run.trace("Previous child run failed; cause type "
                    + failure.getClass().getSimpleName());
            log.error("Previous child run [{}] failed; cause type [{}]",
                    run.getId(), failure.getClass().getSimpleName());
        } finally {
            // Run_Previous.End is intentionally a no-op: never call EndRunBusiness here.
            run.setEndDate(LocalDateTime.now());
            run.trace("Previous child run ended with status " + run.getStatus());
            diagnosticContext.close();
        }
        return run;
    }

    private Run runProcessor(RunIdDto runIdDto, RunExecutionContext executionContext) {
        log.info("Processing run with runId: {}", runIdDto.getRunId());
        Run run = runFactory.create();
        run.setId(runIdDto.getRunId());
        run.setExecutionContext(executionContext);
        run.setStatus(RunStatus.TO_GENERATE);
        run.setStartDate(LocalDateTime.now());
        // .NET creates Audit immediately after entering Launch and before Start_Run. It is a
        // distinct timestamp and its End method is never called in the accepted path.
        run.setAudit(RunAudit.start(LocalDateTime.now()));

        DiagnosticContext diagnosticContext = DiagnosticContext.run(run.getId());
        DiagnosticContext suiviContext = null;
        try {
            // Step 1: Start — status must be RUNNING before it is persisted by Start_Run.
            // Cross-reference: .NET Run_Base.Launch() sets _status = Running BEFORE Launch_Start().
            run.setStatus(RunStatus.RUNNING);
            runStartUpdateBusiness.execute(run);
            run.trace("Run " + run.getId() + " started");
            log.info("Run started successfully with runId: {}", runIdDto.getRunId());

            // Step 2: Load
            load(run);
            suiviContext = DiagnosticContext.suivi(run.getRunProperties().getIdSuivi());
            run.trace("Run loaded (modeDegrade=" + run.getRunProperties().isModeDegrade() + ")");

            if (!run.getRunProperties().isModeDegrade()) {
                // Step 3: Prepare — call prepare() on every task before processing.
                // Cross-reference: .NET Run_Base.Launch_Prepare() / Prepare().
                processTasksService.prepareTasks(run);

                // Step 3b: Load each task's reference/previous document and upload it to the pool
                // (PDFs split per page). In .NET this happens inside Task_Document.Prepare /
                // Task_QXP_Previous.Prepare; here it is a business step so the domain stays I/O-free.
                loadTaskDocumentsBusiness.loadDocuments(run);
                run.trace("Task documents loaded");

                // Step 4: Process tasks (3-pass loop)
                processTasksService.processTasks(run);
                run.trace("Tasks prepared and processed");

                // Step 5: Execute modification steps against QXPS
                qxpsCallerService.process(run);
                run.trace("Modification steps executed");

                // Step 6: Check — overflow detection + data collection
                checkService.check(run);
                run.trace("Check completed");
            }

            // Step 7: Render final outputs
            QxpsCallerResult renderResult = qxpsCallerService.render(
                    run, true, false, true, "true", "300");

            // Build RunResult from render data
            buildRunResult(run, renderResult);
            run.trace("Render completed");

            run.setStatus(RunStatus.GENERATED);

        } catch (Exception ex) {
            String safeFailure = safeDiagnostic.summarize(ex);
            log.error("Run [{}] failed; {}", runIdDto.getRunId(), safeFailure);
            run.setStatus(RunStatus.ERROR);
            // An unexpected top-level failure is Bloquante (3), matching .NET Run_Base.Launch
            // generic catch → Errors.Add(Error_Type.Bloquante, ...). (NOT 1/Unspecified.)
            run.getErrors().add(new RunError(RunError.BLOQUANTE, safeFailure));
        } finally {
            // One logical generation-end time is reused if the first transactional End attempt
            // rolls back and the Error retry runs.
            run.setEndDate(LocalDateTime.now());
            run.trace("Run ending with status " + run.getStatus());
            // A degraded run always records a Critique error before End.
            // Cross-reference: .NET Run_Base.Launch finally → if (Mode_Degrade) Errors.Add(Critique, RunInSafeMode).
            if (run.getRunProperties() != null && run.getRunProperties().isModeDegrade()) {
                run.getErrors().add(new RunError(RunError.CRITIQUE,
                        "Run execute en mode degrade (mode sans echec) : RunInSafeMode"));
            }
            // Step 8: End — finalize run (always executes)
            try {
                run.trace("End attempt=1, status=" + run.getStatus()
                        + ", errorCount=" + run.getErrors().size());
                endRunBusiness.execute(run);
                run.setTerminalStatePersisted(true);
            } catch (Exception ex) {
                String safeFailure = safeDiagnostic.summarize(ex);
                log.error("End_Run failed for run [{}]; {}", runIdDto.getRunId(), safeFailure);
                run.trace("End attempt=1 failed; " + safeFailure);
                // Retry with error status
                run.setStatus(RunStatus.ERROR);
                try {
                    run.trace("End attempt=2, status=" + run.getStatus()
                            + ", errorCount=" + run.getErrors().size());
                    endRunBusiness.execute(run);
                    run.setTerminalStatePersisted(true);
                } catch (Exception ex2) {
                    log.error("End_Run retry failed for run [{}]; {}",
                            runIdDto.getRunId(), safeDiagnostic.summarize(ex2));
                }
            }
            log.info("Run completed: runId={}, status={}, durationMs={}, errorCount={}, "
                            + "terminalStatePersisted={}, finalQxpBytes={}, finalPdfBytes={}, finalJpgBytes={}",
                    runIdDto.getRunId(), run.getStatus(), durationMillis(run.getStartDate(), run.getEndDate()),
                    run.getErrors().size(), run.isTerminalStatePersisted(),
                    documentBytes(run.getResult().getFinalQxp()),
                    documentBytes(run.getResult().getFinalPdf()),
                    documentBytes(run.getResult().getFinalJpg()));
            if (suiviContext != null) {
                suiviContext.close();
            }
            diagnosticContext.close();
        }
        return run;
    }

    /**
     * Build RunResult from render output.
     * Cross-reference: .NET Run_Base.Render() — wraps binary data in Document objects
     */
    private void buildRunResult(Run run, QxpsCallerResult renderResult) {
        String docNamePrefix = String.format("DF_%d", run.getId());

        if (isNotEmpty(renderResult.getJpgData())) {
            run.getResult().setFinalJpg(buildFinalDocument(
                    run, docNamePrefix, "JPEG", renderResult.getJpgData()));
        }
        if (isNotEmpty(renderResult.getPdfData())) {
            run.getResult().setFinalPdf(buildFinalDocument(
                    run, docNamePrefix, "PDF", renderResult.getPdfData()));
        }
        if (isNotEmpty(renderResult.getQxpData())) {
            run.getResult().setFinalQxp(buildFinalDocument(
                    run, docNamePrefix, "QXP", renderResult.getQxpData()));
        }
    }

    private DocumentDomain buildFinalDocument(Run run, String name, String format, byte[] data) {
        DocumentDomain document = new DocumentDomain(
                run.getId(), name, format, DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, data);
        document.setFilePoolPath(run.getPoolPath(document.getFileName()));
        document.setFileFullPath(run.getPoolPathAbsolute(document.getFileName(), qxpsPoolDefaultPath));
        return document;
    }

    private static boolean isNotEmpty(byte[] data) {
        return data != null && data.length > 0;
    }

    public void load(Run run) {
        log.info("Loading run with runId: {}", run.getId());

        // Step 1: Fetch and set run properties
        RunProperties runProperties = getRunProperties(new RunIdDto(run.getId()));
        // Retained for compatibility with remaining RunProperties callers during this wave; it is
        // the workspace ID, not the child's Oracle identity.
        runProperties.setRunId(run.requireExecutionContext().getRootRunId());
        run.setRunProperties(runProperties);

        // Step 2: Delegate gabarit preparation entirely to run domain.
        // prepareGabarit uploads the gabarit to the pool (unconditionally), sets Mode_Degrade if the
        // template is oversized, and — when not degraded — loads the full gabarit XML + the DID.
        run.prepareGabarit(getGabaritBusiness, documentStructureBusiness, filePoolPort, documentIdentityPort);

        // Steps 3-5: In degrade mode .NET does NOT load in-params/tasks/templates.
        // Parity: .NET Run_Base.Load:305-317 — "si nous sommes en mode dégradé nous ne préparons
        // pas les taches et leurs paramètres" — guards LoadInParams / LoadTasks / LoadTemplates with
        // if (!this.Mode_Degrade). Skipping them avoids wasted DB work and the spurious ERROR that
        // would otherwise break the degraded-render success path. (Finding #9.)
        if (!run.getRunProperties().isModeDegrade()) {
            // Step 3: Inject and execute GetInParamsBusiness
            getInParamsBusiness.execute(run);

            // Step 4: Load tasks
            loadTasksService.loadTasks(run);

            // Step 5: Load templates for dynamic tasks
            loadTemplatesBusiness.execute(run);
        }
        Map<String, Long> taskTypeCounts = run.getTasks().values().stream()
                .collect(java.util.stream.Collectors.groupingBy(
                        task -> task.getClass().getSimpleName(), TreeMap::new,
                        java.util.stream.Collectors.counting()));
        long todoTaskCount = run.getTasks().values().stream().filter(TaskBase::isTodo).count();
        long todoDocumentTaskCount = run.getTasks().values().stream()
                .filter(TaskBase::isTodo)
                .filter(TaskDocument.class::isInstance).count();
        log.info("Run load summary: runId={}, suiviId={}, reportTypeCode={}, gabaritSource={}, "
                        + "gabaritBytes={}, degraded={}, inParamCount={}, taskCount={}, "
                        + "todoTaskCount={}, todoDocumentTaskCount={}, templateCount={}, "
                        + "taskTypeCounts={}, dynamicTemplateBytes={}",
                run.getId(), runProperties.getIdSuivi(), runProperties.getTypeRapportCode(),
                runProperties.getGabaritSource(), documentBytes(run.getGabarit()),
                runProperties.isModeDegrade(),
                run.getInParams().size(), run.getTasks().size(), todoTaskCount,
                todoDocumentTaskCount, run.getTemplates().size(), taskTypeCounts,
                documentBytes(run.getGabaritTemplate()));
        log.info("Run loading completed for runId: {}", run.getId());
    }

    @Override
    public RunProperties getRunProperties(RunIdDto runIdDto) {
        log.info("Retrieving properties for runId: {}", runIdDto.getRunId());
        RunProperties runProperties = getRunPropertiesBusiness.execute(runIdDto);
        log.info("Successfully retrieved properties for runId: {}", runIdDto.getRunId());
        return runProperties;
    }

    private static int documentBytes(DocumentDomain document) {
        return document == null || document.getData() == null ? 0 : document.getData().length;
    }

    private static long durationMillis(LocalDateTime start, LocalDateTime end) {
        if (start == null || end == null) {
            return 0;
        }
        return Math.max(0, Duration.between(start, end).toMillis());
    }

}
```

## 9. `src/main/resources/logback-spring.xml`

SHA-256: `b950027498deaa81fffeead23be76098f534ab0596eac96e89e6ce2ef7242caf`

Replace the complete file with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE configuration><!-- Avoid non-justified warnings -->
<configuration>

  <property name="LOG_FILE" value="${LOG_FILE:-${LOG_PATH:-${LOG_TEMP:-${java.io.tmpdir:-/tmp}}}/spring.log}"/>
  <property name="CONSOLE_LOG_PATTERN"
            value="%d{yyyy-MM-dd HH:mm:ss.SSS} %-5level [%thread] [runId=%X{runId:-} suiviId=%X{suiviId:-} taskId=%X{taskId:-} stepIndex=%X{stepIndex:-} childRunId=%X{childRunId:-}] %logger{36} - %msg%n"/>

  <include resource="org/springframework/boot/logging/logback/defaults.xml" />
  <include resource="org/springframework/boot/logging/logback/console-appender.xml" />

  <include resource="co/elastic/logging/logback/boot/ecs-file-appender.xml" />

  <!-- Evidence logs must never include SQL, bind values, or SOAP/HTTP wire payloads. -->
  <logger name="org.springframework.jdbc.core" level="WARN" />
  <logger name="org.hibernate.SQL" level="OFF" />
  <logger name="org.hibernate.orm.jdbc.bind" level="OFF" />
  <logger name="org.apache.axis.transport.http" level="WARN" />
  <logger name="org.apache.commons.httpclient" level="WARN" />
  <logger name="httpclient.wire" level="OFF" />
  <logger name="reactor.netty.http.client" level="WARN" />

  <root level="INFO">
    <appender-ref ref="CONSOLE" />
    <appender-ref ref="ECS_JSON_FILE"/>
  </root>

</configuration>
```

## 10. `src/test/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/client/QxpsHttpClientTest.java`

SHA-256: `f8ff21ee23cab5707a4b48ab50b3dac0d5bdb92f6ae5479ff06048d0c436717b`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.client;

import com.socgen.sgs.api.quark.engine.infra.interop.qxps.config.QxpsProperties;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.exception.QxpsException;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.LiteralMessage;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsResponseInfo;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.request.QxpsRequestBuilder;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.*;

@ExtendWith(OutputCaptureExtension.class)
class QxpsHttpClientTest {

    private HttpServer server;

    @AfterEach
    void stopServer() {
        if (server != null) {
            server.stop(0);
        }
    }

    @Test
    void treatsOnlyExactLowercaseTextContentTypeAsText() throws Exception {
        startServer(exchange -> respond(exchange, 200, "text/plain", "plain"));

        QxpsResponseInfo response = client(serverPort(), 1024, 2_000)
                .execute("document.qxp", new LiteralMessage());

        assertEquals("text/plain", response.getContentType());
        assertEquals(200, response.getHttpStatus());
        assertEquals("plain", response.getTextResponse());
        assertNull(response.getBinaryResponse());
    }

    @Test
    void treatsCaseVariantAndCharsetContentTypesAsBinary() throws Exception {
        startServer(exchange -> {
            String path = exchange.getRequestURI().getPath();
            String contentType = path.contains("charset.qxp")
                    ? "text/plain; charset=UTF-8" : "Text/Plain";
            respond(exchange, 200, contentType, "bytes");
        });
        QxpsHttpClient client = client(serverPort(), 1024, 2_000);

        QxpsResponseInfo caseVariant = client.execute("case.qxp", new LiteralMessage());
        QxpsResponseInfo charsetVariant = client.execute("charset.qxp", new LiteralMessage());

        assertArrayEquals("bytes".getBytes(StandardCharsets.UTF_8), caseVariant.getBinaryResponse());
        assertNull(caseVariant.getTextResponse());
        assertArrayEquals("bytes".getBytes(StandardCharsets.UTF_8), charsetVariant.getBinaryResponse());
        assertNull(charsetVariant.getTextResponse());
    }

    @Test
    void followsRedirectLikeHttpWebRequest() throws Exception {
        startServer(exchange -> {
            if ("/target".equals(exchange.getRequestURI().getPath())) {
                respond(exchange, 200, "application/octet-stream", "final");
            } else {
                exchange.getResponseHeaders().add("Location", "/target");
                exchange.sendResponseHeaders(302, -1);
                exchange.close();
            }
        });

        QxpsResponseInfo response = client(serverPort(), 1024, 2_000)
                .execute("document.qxp", new LiteralMessage());

        assertArrayEquals("final".getBytes(StandardCharsets.UTF_8), response.getBinaryResponse());
    }

    @Test
    void classifiesResponseBearingHttpErrorAsQxpsExceptionWithoutPayload() throws Exception {
        startServer(exchange -> respond(exchange, 503, "text/plain", "server secret"));

        QxpsException failure = assertThrows(QxpsException.class,
                () -> client(serverPort(), 1024, 2_000)
                        .execute("document.qxp", new LiteralMessage()));

        assertEquals(503, failure.getHttpStatus());
        assertEquals("server secret".getBytes(StandardCharsets.UTF_8).length,
                failure.getResponseBodyBytes());
        assertFalse(failure.getMessage().contains("server secret"));
    }

    @Test
    void leavesConnectionFailureBlockingInsteadOfPdfFailSoftType() throws Exception {
        int closedPort;
        try (ServerSocket socket = new ServerSocket(0)) {
            closedPort = socket.getLocalPort();
        }

        RuntimeException failure = assertThrows(RuntimeException.class,
                () -> client(closedPort, 1024, 200)
                        .execute("document.qxp", new LiteralMessage()));

        assertFalse(failure instanceof QxpsException);
    }

    @Test
    void leavesResponseBufferOverflowBlockingInsteadOfPdfFailSoftType() throws Exception {
        startServer(exchange -> respond(exchange, 200, "application/octet-stream", "12345"));

        RuntimeException failure = assertThrows(RuntimeException.class,
                () -> client(serverPort(), 4, 2_000)
                        .execute("document.qxp", new LiteralMessage()));

        assertFalse(failure instanceof QxpsException);
    }

    @Test
    void logsBoundedSuccessMetadataWithoutDocumentOrResponsePayload(CapturedOutput output) throws Exception {
        String secretDocument = "TOP_SECRET_DOCUMENT.qxp";
        String secretResponse = "TOP_SECRET_RESPONSE";
        startServer(exchange -> respond(exchange, 200, "text/plain", secretResponse));

        client(serverPort(), 1024, 2_000).execute(secretDocument, new LiteralMessage());

        String logs = output.getAll();
        assertEquals(1, countLinesContaining(logs, "QXPS call:"));
        assertEquals(1, countLinesContaining(logs, "QXPS completed:"));
        assertTrue(logs.contains("httpStatus=200"));
        assertTrue(logs.contains("responseCategory=TEXT"));
        assertTrue(logs.contains("responseBytes=0"));
        assertTrue(logs.contains("responseChars=" + secretResponse.length()));
        assertFalse(logs.contains(secretDocument));
        assertFalse(logs.contains(secretResponse));
    }

    @Test
    void logsBoundedFailureMetadataWithoutDocumentOrErrorPayload(CapturedOutput output) throws Exception {
        String secretDocument = "TOP_SECRET_FAILURE_DOCUMENT.qxp";
        String secretResponse = "TOP_SECRET_FAILURE_RESPONSE";
        startServer(exchange -> respond(exchange, 503, "text/plain", secretResponse));

        assertThrows(QxpsException.class,
                () -> client(serverPort(), 1024, 2_000)
                        .execute(secretDocument, new LiteralMessage()));

        String logs = output.getAll();
        assertEquals(1, countLinesContaining(logs, "QXPS call:"));
        assertEquals(1, countLinesContaining(logs, "QXPS failed:"));
        assertTrue(logs.contains("causeType=QxpsException"));
        assertFalse(logs.contains(secretDocument));
        assertFalse(logs.contains(secretResponse));
    }

    private QxpsHttpClient client(int port, int maxInMemoryBytes, int timeoutMs) {
        QxpsProperties properties = new QxpsProperties();
        properties.getServer().setUrl("http://127.0.0.1:" + port);
        properties.getServer().setConnectTimeoutMs(timeoutMs);
        properties.getServer().setResponseTimeoutMs(timeoutMs);
        properties.getServer().setMaxInMemorySizeBytes(maxInMemoryBytes);
        QxpsHttpClient client = new QxpsHttpClient(new QxpsRequestBuilder(properties), properties);
        client.init();
        return client;
    }

    private void startServer(ExchangeHandler handler) throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            try {
                handler.handle(exchange);
            } catch (Exception failure) {
                exchange.close();
            }
        });
        server.start();
    }

    private int serverPort() {
        return server.getAddress().getPort();
    }

    private static void respond(HttpExchange exchange, int status, String contentType, String body)
            throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        if (contentType != null) {
            exchange.getResponseHeaders().set("Content-Type", contentType);
        }
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
        exchange.close();
    }

    private static long countLinesContaining(String logs, String value) {
        return logs.lines()
                .filter(message -> message.contains(value))
                .count();
    }

    @FunctionalInterface
    private interface ExchangeHandler {
        void handle(HttpExchange exchange) throws Exception;
    }
}
```

## 11. `src/test/java/com/socgen/sgs/api/quark/engine/infra/interop/qxpsm/QxpsmSoapClientTest.java`

SHA-256: `43f49500ff0ba3c7a37bf46023df9d353c7e9ddfbd52dfb190c18bf11a954e47`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxpsm;

import com.socgen.sgs.api.quark.engine.integration.soap.generated.*;
import org.apache.axis.client.Stub;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;

import java.rmi.RemoteException;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(OutputCaptureExtension.class)
class QxpsmSoapClientTest {

    private QxpsmProperties properties;
    private RequestServicePortType port;
    private QxpsmSoapClient client;

    @BeforeEach
    void setUp() throws Exception {
        properties = new QxpsmProperties();
        properties.setEndpoint("http://localhost:8090/qxpsm/services/RequestService");
        properties.setRequestTimeoutMs(3_600_000);
        properties.setSocketTimeoutMs(0);
        properties.setDomTimeoutMs(100_000);
        properties.setMaxRetries(0);

        port = mock(RequestServicePortType.class);
        client = spy(new QxpsmSoapClient(properties));
        doReturn(port).when(client).createStub(anyInt());
    }

    @Test
    void buildsAcceptedRequestChainAndUsesIndependentProcessTimeouts() throws Exception {
        NameValueParam value = new NameValueParam();
        value.setParamName("BLOC");
        value.setTextValue("VALUE");
        Project project = new Project();
        project.setLayouts(new Layout[]{new Layout()});
        QContentData expected = new QContentData();
        when(port.processRequest(any())).thenReturn(expected);

        QContentData actual = client.executeStep(
                "R_1/G_1.qxp", List.of(value), project,
                "D:\\Documents\\R_1", "G_2.qxp");

        assertSame(expected, actual);
        verify(client).createStub(0);
        ArgumentCaptor<QRequestContext> contextCaptor = ArgumentCaptor.forClass(QRequestContext.class);
        verify(port).processRequest(contextCaptor.capture());
        QRequestContext context = contextCaptor.getValue();
        assertEquals(3_600_000, context.getRequestTimeout());
        assertEquals("R_1/G_1.qxp", context.getDocumentName());
        assertEquals("", context.getUserName());
        assertEquals("", context.getUserPassword());
        assertInstanceOf(RequestParameters.class, context.getRequest());
        QRequest modifier = context.getRequest().getRequest();
        assertInstanceOf(ModifierRequest.class, modifier);
        QRequest saveAs = modifier.getRequest();
        assertInstanceOf(SaveAsRequest.class, saveAs);
        assertEquals("true", ((SaveAsRequest) saveAs).getReplaceFile());
        assertEquals("false", ((SaveAsRequest) saveAs).getSaveToPool());
        assertInstanceOf(QuarkXPressRenderRequest.class, saveAs.getRequest());
    }

    @Test
    void usesStandaloneDomTimeoutAndReturnsProject() throws Exception {
        Project expected = new Project();
        when(port.getXPressDOM("R_1/G_1.qxp")).thenReturn(expected);

        Project actual = client.getProject("R_1/G_1.qxp");

        assertSame(expected, actual);
        verify(client).createStub(100_000);
    }

    @Test
    void wrapsSoapFailureWithoutDocumentOrFaultPayload() throws Exception {
        when(port.processRequest(any())).thenThrow(new RemoteException("fault secret"));

        QxpsmException failure = assertThrows(QxpsmException.class,
                () -> client.executeStep("sensitive-document.qxp", List.of(), null,
                        "sensitive-path", "sensitive-name"));

        assertEquals("processRequest", failure.getOperation());
        assertFalse(failure.getMessage().contains("sensitive"));
        assertFalse(failure.getMessage().contains("fault secret"));
    }

    @Test
    void preservesNonThrowingNullProcessResponse() throws Exception {
        when(port.processRequest(any())).thenReturn(null);

        QContentData result = client.executeStep(
                "R_1/G_1.qxp", List.of(), null,
                "D:\\Documents\\R_1", "G_2.qxp");

        assertNull(result);
    }

    @Test
    void preservesNonThrowingNullDomResponseForDegradedStructureBoundary() throws Exception {
        when(port.getXPressDOM("R_1/G_1.qxp")).thenReturn(null);

        Project result = client.getProject("R_1/G_1.qxp");

        assertNull(result);
    }

    @Test
    void createdAxisStubReceivesConfiguredSocketTimeout() throws Exception {
        QxpsmSoapClient realClient = new QxpsmSoapClient(properties);

        RequestServicePortType created = realClient.createStub(12_345);

        assertEquals(12_345, ((Stub) created).getTimeout());
    }

    @Test
    void logsBoundedProcessMetadataWithoutRequestOrResponsePayload(CapturedOutput output) throws Exception {
        NameValueParam value = new NameValueParam();
        value.setParamName("TOP_SECRET_PARAM_NAME");
        value.setTextValue("TOP_SECRET_PARAM_VALUE");
        Project project = new Project();
        project.setLayouts(new Layout[]{new Layout()});
        QContentData response = new QContentData();
        response.setStreamValue(new byte[]{1, 2, 3});
        response.setTextData("TOP_SECRET_RESPONSE");
        response.setMultipartResponse(new QContentData[]{new QContentData(), new QContentData()});
        when(port.processRequest(any())).thenReturn(response);

        client.executeStep("TOP_SECRET_DOCUMENT", List.of(value), project,
                "TOP_SECRET_PATH", "TOP_SECRET_NAME");

        String logs = output.getAll();
        assertEquals(1, countLinesContaining(logs, "QXPSM started: operation=processRequest"));
        assertEquals(1, countLinesContaining(logs, "QXPSM completed: operation=processRequest"));
        assertTrue(logs.contains("nameValueCount=1"));
        assertTrue(logs.contains("modifierLayoutCount=1"));
        assertTrue(logs.contains("streamBytes=3"));
        assertTrue(logs.contains("textChars=19"));
        assertTrue(logs.contains("multipartCount=2"));
        assertFalse(logs.contains("TOP_SECRET"));
    }

    @Test
    void logsBoundedDomMetadataWithoutDocumentName(CapturedOutput output) throws Exception {
        Project response = new Project();
        response.setLayouts(new Layout[]{new Layout(), new Layout()});
        response.setContents(new Content[]{new Content()});
        when(port.getXPressDOM("TOP_SECRET_DOCUMENT")).thenReturn(response);

        client.getProject("TOP_SECRET_DOCUMENT");

        String logs = output.getAll();
        assertEquals(1, countLinesContaining(logs, "QXPSM started: operation=getXPressDOM"));
        assertEquals(1, countLinesContaining(logs, "QXPSM completed: operation=getXPressDOM"));
        assertTrue(logs.contains("layoutCount=2"));
        assertTrue(logs.contains("contentCount=1"));
        assertFalse(logs.contains("TOP_SECRET_DOCUMENT"));
    }

    private static long countLinesContaining(String logs, String value) {
        return logs.lines()
                .filter(message -> message.contains(value))
                .count();
    }
}
```

## 12. `src/test/java/com/socgen/sgs/api/quark/engine/business/ProcessSqlBusinessTest.java`

SHA-256: `376a717c39e0ff87d57cf8cbb25ff68a7b6bca9a139023ec2e740004ad0a4a66`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.business;

import com.socgen.sgs.api.quark.engine.TestRuns;

import com.socgen.sgs.api.quark.engine.config.EngineFormattingProperties;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocLigne;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocTable;
import com.socgen.sgs.api.quark.engine.domain.helper.DataTypeHelper;
import com.socgen.sgs.api.quark.engine.domain.task.TaskException;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.enums.DataTypeEnum;
import com.socgen.sgs.api.quark.engine.enums.TaskExceptionTypeEnum;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.infra.dao.TaskSqlDao;
import com.socgen.sgs.api.quark.engine.mapper.InParamSqlMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

@ExtendWith(OutputCaptureExtension.class)
class ProcessSqlBusinessTest {

    private TaskSqlDao dao;
    private ProcessSqlBusiness business;
    private TaskSql task;

    @BeforeEach
    void setUp() {
        dao = mock(TaskSqlDao.class);
        InParamSqlMapper parameterMapper = mock(InParamSqlMapper.class);
        when(parameterMapper.toParameterMap(any())).thenReturn(new LinkedHashMap<>());

        EngineFormattingProperties properties = new EngineFormattingProperties();
        properties.setDatePattern("dd/MM/yyyy");
        properties.setDateTimePattern("dd/MM/yyyy HH:mm:ss");
        properties.setDecimalSeparator(",");
        properties.setGroupSeparator(" ");
        properties.setCurrencySymbol("€");
        business = new ProcessSqlBusiness(dao, parameterMapper, new DataTypeHelper(properties));

        Run run = TestRuns.run();
        run.setId(509199);
        run.setRunProperties(new RunProperties());
        task = new TaskSql(53, run);
        task.setSql("select task result columns");
        task.setTodo(true);
        task.setDataType(DataTypeEnum.TEXT);
        task.setNullString("-");

    }

    @Test
    void keepsFirstDuplicateAndRecordsNonBlockingUnspecifiedError() {
        when(dao.executeSql(any(), any())).thenReturn(List.of(
                row("BLOCK_A", "first"), row("BLOCK_A", "second")));

        business.execute(task);

        assertEquals(1, task.getBlocsUpdate().size());
        assertEquals("first", ((BlocBox) task.getBlocsUpdate().get("BLOCK_A")).getValue());
        assertEquals(1, task.getRun().getErrors().size());
        assertEquals(1, task.getRun().getErrors().get(0).getCategory());
    }

    @Test
    void distinguishesMissingRequiredColumnFromPresentSqlNullAndContinuesRows() {
        Map<String, Object> missingName = new HashMap<>();
        missingName.put("VALEUR_BLOC", "ignored");
        Map<String, Object> nullValues = new HashMap<>();
        nullValues.put("NOM_BLOC", null);
        nullValues.put("VALEUR_BLOC", null);
        when(dao.executeSql(any(), any())).thenReturn(List.of(missingName, nullValues, row("B", "value")));

        business.execute(task);

        assertEquals(2, task.getBlocsUpdate().size());
        assertEquals("-", ((BlocBox) task.getBlocsUpdate().get("")).getValue());
        assertEquals("value", ((BlocBox) task.getBlocsUpdate().get("B")).getValue());
        assertEquals(1, task.getRun().getErrors().size());
        assertTrue(task.getRun().getErrors().get(0).getMessage().contains("adding bloc"));
    }

    @Test
    void optionalStorageMetadataMayBeAbsentPresentOrSqlNull() {
        task.setStoreData(true);
        task.getRun().getRunProperties().setStoreDataTypeCode(3);
        Map<String, Object> absent = row("A", "one");
        Map<String, Object> present = row("B", "two");
        present.put("DESCRIPTION_BLOC", "description");
        present.put("INFO_BLOC", "info");
        Map<String, Object> sqlNull = row("C", "three");
        sqlNull.put("DESCRIPTION_BLOC", null);
        sqlNull.put("INFO_BLOC", null);
        when(dao.executeSql(any(), any())).thenReturn(List.of(absent, present, sqlNull));

        business.execute(task);

        assertEquals(3, task.getDataNamesValues().size());
        assertEquals("", task.getDataNamesValues().get(0).getDescriptif());
        assertEquals("description", task.getDataNamesValues().get(1).getDescriptif());
        assertEquals("info", task.getDataNamesValues().get(1).getInfo());
        assertEquals("", task.getDataNamesValues().get(2).getDescriptif());
        assertEquals("", task.getDataNamesValues().get(2).getInfo());
    }

    @Test
    void whitespaceConditionIsARealValueAndDoesNotActivateRemoval() {
        QxpXml xml = attachXml();
        task.getExceptions().put("COND", new TaskException(
                "TABLE", "COND", new int[0], TaskExceptionTypeEnum.TABLE));
        when(dao.executeSql(any(), any())).thenReturn(List.of(row("COND", "   ")));

        business.execute(task);

        assertTrue(task.getBlocsModify().isEmpty());
        verify(xml, never()).existName(any());
    }

    @Test
    void absentConditionRecordsUnspecifiedErrorWithoutBlockingOtherWork() {
        QxpXml xml = attachXml();
        task.getExceptions().put("COND", new TaskException(
                "TABLE", "COND", new int[0], TaskExceptionTypeEnum.TABLE));
        when(dao.executeSql(any(), any())).thenReturn(List.of(row("OTHER", "value")));
        when(xml.existName("COND")).thenReturn(false);

        business.execute(task);

        assertEquals(1, task.getBlocsUpdate().size());
        assertEquals(1, task.getRun().getErrors().get(0).getCategory());
        assertTrue(task.getRun().getErrors().get(0).getMessage().startsWith("Invalid conditional block"));
    }

    @Test
    void selectedRowsAndWholeTableExceptionsCreateTheCorrectRemovalBlocs() {
        QxpXml xml = attachXml();
        task.getExceptions().put("LINE_COND", new TaskException(
                "TABLE_A", "LINE_COND", new int[]{2, 4}, TaskExceptionTypeEnum.LINE));
        task.getExceptions().put("TABLE_COND", new TaskException(
                "TABLE_B", "TABLE_COND", new int[0], TaskExceptionTypeEnum.TABLE));
        when(dao.executeSql(any(), any())).thenReturn(List.of());
        when(xml.existName(any())).thenReturn(true);
        when(xml.getNbLignes("TABLE_A")).thenReturn(4);

        business.execute(task);

        assertTrue(task.getBlocsModify().get("TABLE_A_2") instanceof BlocLigne);
        assertTrue(task.getBlocsModify().get("TABLE_A_4") instanceof BlocLigne);
        assertTrue(task.getBlocsModify().get("TABLE_B") instanceof BlocTable);
        assertTrue(task.getRun().getErrors().isEmpty());
    }

    @Test
    void missingRowsAndMissingTableAreSeparateNonBlockingErrors() {
        QxpXml xml = attachXml();
        task.getExceptions().put("ROWS", new TaskException(
                "SHORT_TABLE", "ROWS", new int[]{5}, TaskExceptionTypeEnum.LINE));
        task.getExceptions().put("MISSING", new TaskException(
                "NO_TABLE", "MISSING", new int[0], TaskExceptionTypeEnum.TABLE));
        when(dao.executeSql(any(), any())).thenReturn(List.of());
        when(xml.existName("ROWS")).thenReturn(true);
        when(xml.existName("SHORT_TABLE")).thenReturn(true);
        when(xml.getNbLignes("SHORT_TABLE")).thenReturn(4);
        when(xml.existName("MISSING")).thenReturn(true);
        when(xml.existName("NO_TABLE")).thenReturn(false);

        business.execute(task);

        assertEquals(2, task.getRun().getErrors().size());
        assertTrue(task.getRun().getErrors().get(0).getMessage().startsWith("Missing rows"));
        assertTrue(task.getRun().getErrors().get(1).getMessage().startsWith("Table does not exist"));
        assertTrue(task.getBlocsModify().isEmpty());
    }

    @Test
    void logsOnlyBoundedSqlMetadataWithoutSqlTextOrRowValues(CapturedOutput output) {
        String secretSql = "select TOP_SECRET_SQL from TOP_SECRET_TABLE";
        task.setSql(secretSql);
        when(dao.executeSql(any(), any())).thenReturn(List.of(row("TOP_SECRET_BLOCK", "TOP_SECRET_VALUE")));

        business.execute(task);

        String logs = output.getAll();
        assertTrue(logs.contains("SQL task completed: taskId=53, runId=509199"));
        assertTrue(logs.contains("sqlChars=" + secretSql.length()));
        assertTrue(logs.contains("bindCount=0"));
        assertTrue(logs.contains("rowCount=1"));
        assertTrue(logs.contains("durationMs="));
        assertFalse(logs.contains(secretSql));
        assertFalse(logs.contains("TOP_SECRET_BLOCK"));
        assertFalse(logs.contains("TOP_SECRET_VALUE"));
    }

    @Test
    void aggregatesSqlRowAnomaliesIntoOneBoundedLine(CapturedOutput output) {
        Map<String, Object> malformed = new HashMap<>();
        malformed.put("VALEUR_BLOC", "not-logged");
        when(dao.executeSql(any(), any())).thenReturn(List.of(
                row("DUPLICATE_SECRET", "first"),
                row("DUPLICATE_SECRET", "second"),
                row("DUPLICATE_SECRET", "third"),
                malformed));

        business.execute(task);

        String logs = output.getAll();
        String summary = "SQL row anomalies: taskId=53, runId=509199, duplicateBlocks=2, failedRows=1";
        assertTrue(logs.contains(summary));
        assertEquals(1, logs.split(java.util.regex.Pattern.quote(summary), -1).length - 1);
        assertFalse(logs.contains("DUPLICATE_SECRET"));
        assertFalse(logs.contains("not-logged"));
    }

    private QxpXml attachXml() {
        QxpXml xml = mock(QxpXml.class);
        DocumentDomain document = new DocumentDomain();
        document.setQxpXml(xml);
        task.getRun().setGabarit(document);
        return xml;
    }

    private static Map<String, Object> row(String name, Object value) {
        Map<String, Object> row = new HashMap<>();
        row.put("NOM_BLOC", name);
        row.put("VALEUR_BLOC", value);
        return row;
    }
}
```

## 13. `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImplTest.java`

SHA-256: `abedc69e3dc1adfc502f9ea343112816a191b2b25bfdab3e61e6142c7e61b90d`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.TestRuns;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.exception.EngineException;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.service.task.TaskPostProcessService;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(OutputCaptureExtension.class)
class ProcessTasksServiceImplTest {

    @Test
    void controlledAnchorFailureIsRecordedAndFollowingTaskStillRuns() {
        TaskProcessService processor = mock(TaskProcessService.class);
        TaskPostProcessService postProcessor = mock(TaskPostProcessService.class);
        ProcessTasksServiceImpl service = new ProcessTasksServiceImpl(processor, postProcessor);
        ReflectionTestUtils.setField(service, "stepLimit", 5000);
        Run run = TestRuns.run();
        run.setId(42);
        RunProperties properties = new RunProperties();
        properties.setIdSuivi(900);
        run.setRunProperties(properties);
        TaskBase failing = task(7, run);
        TaskBase following = task(8, run);
        run.getTasks().put(7, failing);
        run.getTasks().put(8, following);
        doThrow(new EngineException(RunError.BLOQUANTE,
                "Anchor positions are inconsistent: TOP anchor is lower than BOTTOM anchor"))
                .when(processor).process(failing);

        service.processTasks(run);

        assertTrue(failing.isInError());
        assertFalse(following.isInError());
        verify(processor).process(failing);
        verify(processor).process(following);
        RunError controlled = run.getErrors().stream()
                .filter(error -> error.getMessage().contains("Anchor positions"))
                .findFirst()
                .orElseThrow();
        assertEquals(RunError.CRITIQUE, controlled.getCategory());
        assertTrue(controlled.getMessage().contains("Error while processing task 7"));
        assertTrue(controlled.getMessage().contains("TOP"));
        assertTrue(controlled.getMessage().contains("BOTTOM"));
    }

    @Test
    void rawProcessFailureUsesSafePhaseMessageAndNeverPersistsPayload() {
        TaskProcessService processor = mock(TaskProcessService.class);
        TaskPostProcessService postProcessor = mock(TaskPostProcessService.class);
        ProcessTasksServiceImpl service = service(processor, postProcessor);
        Run run = run(43);
        TaskBase failing = task(7, run);
        TaskBase following = task(8, run);
        run.getTasks().put(7, failing);
        run.getTasks().put(8, following);
        doThrow(new IllegalStateException("SELECT secret_sql FROM secret_table value=PRIVATE"))
                .when(processor).process(failing);

        service.processTasks(run);

        String message = run.getErrors().stream()
                .map(RunError::getMessage)
                .filter(value -> value.contains("processing task 7"))
                .findFirst().orElseThrow();
        assertFalse(message.contains("SELECT"));
        assertFalse(message.contains("PRIVATE"));
        assertTrue(failing.isInError());
        verify(processor).process(following);
    }

    @Test
    void resetAndPostProcessKeepDistinctSafePhasesAndContinue() {
        TaskProcessService processor = mock(TaskProcessService.class);
        TaskPostProcessService postProcessor = mock(TaskPostProcessService.class);
        ProcessTasksServiceImpl service = service(processor, postProcessor);
        Run run = run(44);
        TaskBase resetFailure = spy(task(1, run));
        TaskBase postFailure = task(2, run);
        TaskBase following = task(3, run);
        run.getTasks().put(1, resetFailure);
        run.getTasks().put(2, postFailure);
        run.getTasks().put(3, following);
        doThrow(new IllegalStateException("reset payload")).when(resetFailure).resetProcess();
        doThrow(new EngineException(RunError.UNSPECIFIED, "Controlled post detail"))
                .when(postProcessor).postProcess(postFailure);

        service.processTasks(run);

        assertTrue(run.getErrors().stream().anyMatch(error ->
                error.getMessage().contains("resetting task 1")
                        && !error.getMessage().contains("reset payload")));
        assertTrue(run.getErrors().stream().anyMatch(error ->
                error.getMessage().contains("post-processing task 2")
                        && error.getMessage().contains("Controlled post detail")));
        verify(processor).process(following);
        verify(postProcessor).postProcess(following);
    }

    @Test
    void logsOneBoundedResultForEachSelectedTask(CapturedOutput output) {
        TaskProcessService processor = mock(TaskProcessService.class);
        TaskPostProcessService postProcessor = mock(TaskPostProcessService.class);
        ProcessTasksServiceImpl service = service(processor, postProcessor);
        Run run = run(45);
        TaskBase task = task(9, run);
        TaskBase prepareFailure = task(10, run);
        prepareFailure.setInError(true);
        run.getTasks().put(9, task);
        run.getTasks().put(10, prepareFailure);
        service.processTasks(run);

        List<String> taskResults = output.getAll().lines()
                .filter(message -> message.contains("Task result:"))
                .map(message -> message.substring(message.indexOf("Task result:")))
                .toList();
        assertEquals(2, taskResults.size());
        assertTrue(taskResults.stream().anyMatch(message ->
                message.contains("taskId=9") && message.contains("inError=false")));
        assertTrue(taskResults.stream().anyMatch(message ->
                message.contains("taskId=10") && message.contains("inError=true")));
        assertTrue(taskResults.stream().allMatch(message -> message.contains("taskType=")
                && message.contains("updateBlocks=0") && message.contains("modifyBlocks=0")
                && message.contains("storedDataRows=0")));
        verify(processor, never()).process(prepareFailure);
    }

    private static ProcessTasksServiceImpl service(TaskProcessService processor,
                                                   TaskPostProcessService postProcessor) {
        ProcessTasksServiceImpl service = new ProcessTasksServiceImpl(processor, postProcessor);
        ReflectionTestUtils.setField(service, "stepLimit", 5000);
        return service;
    }

    private static Run run(int id) {
        Run run = TestRuns.run();
        run.setId(id);
        RunProperties properties = new RunProperties();
        properties.setIdSuivi(900);
        run.setRunProperties(properties);
        return run;
    }

    private static TaskBase task(int id, Run run) {
        TaskBase task = new TaskBase(id, run) {
            @Override
            public void prepare() {
                // Nothing required for this processing-boundary test.
            }
        };
        task.setTodo(true);
        return task;
    }
}
```

## 14. `src/test/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImplTest.java`

SHA-256: `8e3a101108c27fcdc31543508a1866e92ba4ecb85245ac33b382b529670ff47f`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.TestRuns;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.GetDocumentByIdBusiness;
import com.socgen.sgs.api.quark.engine.business.GetDocumentProjectBusiness;
import com.socgen.sgs.api.quark.engine.business.DocumentStructureBusiness;
import com.socgen.sgs.api.quark.engine.business.GetInParamsBusiness;
import com.socgen.sgs.api.quark.engine.business.GetRunPropertiesBusiness;
import com.socgen.sgs.api.quark.engine.business.RunStartUpdateBusiness;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunExecutionContext;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.RunStatus;
import com.socgen.sgs.api.quark.engine.dto.RunIdDto;
import com.socgen.sgs.api.quark.engine.enums.GabaritSourceEnum;
import com.socgen.sgs.api.quark.engine.service.LoadTasksService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith({MockitoExtension.class, OutputCaptureExtension.class})
@DisplayName("ProcessRunServiceImpl Tests")
class ProcessRunServiceImplTest {

    @InjectMocks
    private ProcessRunServiceImpl processRunService;

    @Mock
    private RunStartUpdateBusiness runStartUpdateBusiness;
    @Mock
    private GetRunPropertiesBusiness getRunPropertiesBusiness;
    @Mock
    private GetGabaritBusiness getGabaritBusiness;
    @Mock
    private GetInParamsBusiness getInParamsBusiness;
    @Mock
    private LoadTasksService loadTasksService;
    @Mock
    private com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort filePoolPort;
    @Mock
    private com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort documentIdentityPort;
    @Mock
    private com.socgen.sgs.api.quark.engine.service.ProcessTasksService processTasksService;
    // Dependencies added across later batches — required so the orchestrator pipeline does not NPE.
    @Mock
    private com.socgen.sgs.api.quark.engine.service.QxpsCallerService qxpsCallerService;
    @Mock
    private com.socgen.sgs.api.quark.engine.service.CheckService checkService;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.LoadTemplatesBusiness loadTemplatesBusiness;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.LoadTaskDocumentsBusiness loadTaskDocumentsBusiness;
    @Mock
    private GetDocumentByIdBusiness getDocumentByIdBusiness;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.EndRunBusiness endRunBusiness;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness getGabaritXmlBusiness;
    @Mock
    private GetDocumentProjectBusiness getDocumentProjectBusiness;
    @Mock
    private com.socgen.sgs.api.quark.engine.service.RunFactory runFactory;
    @Mock
    private com.socgen.sgs.api.quark.engine.diagnostic.SafeDiagnostic safeDiagnostic;

    private RunProperties runProperties;

    @BeforeEach
    void setUp() {
        ReflectionTestUtils.setField(processRunService, "documentStructureBusiness",
                new DocumentStructureBusiness(filePoolPort, getGabaritXmlBusiness, getDocumentProjectBusiness));
        ReflectionTestUtils.setField(processRunService, "qxpsPoolDefaultPath", "D:\\Documents\\");
        lenient().when(runFactory.create()).thenAnswer(invocation -> TestRuns.run());
        lenient().when(safeDiagnostic.summarize(any())).thenAnswer(invocation ->
                "exceptionType=" + invocation.<Throwable>getArgument(0).getClass().getSimpleName());
        runProperties = new RunProperties();
        runProperties.setGabaritSource(GabaritSourceEnum.GABARIT);
        runProperties.setIdGabarit(10);
        // render() returns a result object; stub it (lenient — only the full-pipeline tests reach it)
        // so buildRunResult does not NPE on a null render result.
        lenient().when(qxpsCallerService.render(any(), anyBoolean(), anyBoolean(), anyBoolean(), any(), any()))
                .thenReturn(new com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult());
    }

    // --- runProcessor ---

    @Test
    @DisplayName("Should initialise run with correct id, status and startDate then call load")
    void shouldInitialiseRunAndCallLoad() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        processRunService.runProcessor(new RunIdDto(42));

        ArgumentCaptor<Run> runCaptor = ArgumentCaptor.forClass(Run.class);
        verify(runStartUpdateBusiness).execute(runCaptor.capture());
        Run captured = runCaptor.getValue();

        assertEquals(42, captured.getId());
        // The captured Run is the same mutable instance the orchestrator drives to completion; with
        // all collaborators mocked the pipeline finishes successfully, so its final status is GENERATED.
        assertEquals(RunStatus.GENERATED, captured.getStatus());
        assertNotNull(captured.getStartDate());
    }

    @Test
    @DisplayName("Child keeps its Oracle run id while inheriting the root execution workspace")
    void childRunInheritsRootExecutionContextWithoutChangingBusinessId() {
        RunExecutionContext rootContext = new RunExecutionContext(42);
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        Run child = processRunService.runChildProcessor(new RunIdDto(99), rootContext);

        assertEquals(99, child.getId());
        assertSame(rootContext, child.getExecutionContext());
        assertEquals("R_42/DF_99.QXP", child.getPoolPath("DF_99.QXP"));
    }

    @Test
    @DisplayName("Structural XML failure renders in degraded mode and finishes Generated")
    void xmlFailureCompletesThroughDegradedRenderPath() {
        DocumentDomain gabarit = DocumentDomain.builder()
                .id(10)
                .format("QXP")
                .data(new byte[]{1, 2, 3})
                .filePoolPath("R_42/G_10.QXP")
                .build();
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(gabarit);
        when(getGabaritXmlBusiness.fetchXml(gabarit.getFilePoolPath())).thenReturn("");

        Run result = processRunService.runProcessor(new RunIdDto(42));

        assertEquals(RunStatus.GENERATED, result.getStatus());
        assertTrue(result.isTerminalStatePersisted());
        assertTrue(result.getRunProperties().isModeDegrade());
        assertTrue(result.getErrors().stream().anyMatch(error -> error.getCategory() == RunError.CRITIQUE));
        verify(getInParamsBusiness, never()).execute(any());
        verify(loadTasksService, never()).loadTasks(any());
        verify(processTasksService, never()).prepareTasks(any());
        verify(qxpsCallerService).render(eq(result), eq(true), eq(false), eq(true), eq("true"), eq("300"));
        verify(endRunBusiness).execute(result);
    }

    @Test
    @DisplayName("Should call runStartUpdateBusiness before load")
    void shouldCallStartUpdateBeforeLoad() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        processRunService.runProcessor(new RunIdDto(1));

        verify(runStartUpdateBusiness, times(1)).execute(any(Run.class));
        verify(getRunPropertiesBusiness, times(1)).execute(any(RunIdDto.class));
        verify(loadTasksService, times(1)).loadTasks(any(Run.class));
    }

    // --- load ---

    @Test
    @DisplayName("Should set run properties and runId on the run")
    void shouldSetRunPropertiesAndRunId() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        Run run = TestRuns.run();
        run.setId(55);
        processRunService.load(run);

        assertEquals(55, run.getRunProperties().getRunId());
        assertSame(runProperties, run.getRunProperties());
    }

    @Test
    @DisplayName("Should call all four load steps in order")
    void shouldCallAllLoadStepsInOrder() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        Run run = TestRuns.run();
        run.setId(10);
        processRunService.load(run);

        var order = inOrder(getRunPropertiesBusiness, getGabaritBusiness, getInParamsBusiness, loadTasksService);
        order.verify(getRunPropertiesBusiness).execute(any(RunIdDto.class));
        order.verify(getGabaritBusiness).getAndPrepareGabarit(any(), any());
        order.verify(getInParamsBusiness).execute(run);
        order.verify(loadTasksService).loadTasks(run);
    }

    @Test
    @DisplayName("Should record ERROR (not propagate) when runStartUpdateBusiness throws")
    void shouldPropagateExceptionFromStartUpdate() {
        doThrow(new RuntimeException("start failed")).when(runStartUpdateBusiness).execute(any(Run.class));

        // runProcessor catches top-level failures, marks the run ERROR, and still runs End_Run in the
        // finally block (parity: .NET Run_Base.Launch try/catch/finally) — it does NOT propagate.
        Run result = processRunService.runProcessor(new RunIdDto(1));

        assertEquals(RunStatus.ERROR, result.getStatus());
        verify(getRunPropertiesBusiness, never()).execute(any());
        verify(endRunBusiness, atLeastOnce()).execute(any(Run.class));
    }

    @Test
    @DisplayName("Final documents require non-empty bytes and use the root execution workspace")
    void finalDocumentsUseRootPathsAndRejectEmptyRenderPayloads() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);
        com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult render =
                new com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult();
        render.setQxpData(new byte[]{1, 2});
        render.setPdfData(new byte[0]);
        when(qxpsCallerService.render(any(), anyBoolean(), anyBoolean(), anyBoolean(), any(), any()))
                .thenReturn(render);

        Run result = processRunService.runChildProcessor(
                new RunIdDto(99), new RunExecutionContext(42));

        assertNotNull(result.getResult().getFinalQxp());
        assertEquals("DF_99.QXP", result.getResult().getFinalQxp().getFileName());
        assertEquals("R_42/DF_99.QXP", result.getResult().getFinalQxp().getFilePoolPath());
        assertEquals("D:\\Documents\\R_42\\DF_99.QXP",
                result.getResult().getFinalQxp().getFileFullPath());
        assertNull(result.getResult().getFinalPdf());
        assertNull(result.getResult().getFinalJpg());
    }

    @Test
    @DisplayName("Previous child follows load/prepare/check/render order without database Start or End")
    void previousChildUsesAcceptedLifecycleWithoutPersistenceOrNormalRendering() {
        RunProperties previousProperties = new RunProperties();
        previousProperties.setIdLastQxp(700);
        DocumentDomain previousQxp = new DocumentDomain(700, "previous", "QXP",
                DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, new byte[]{1, 2, 3});
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(previousProperties);
        when(getDocumentByIdBusiness.getDocumentById(700)).thenReturn(previousQxp);

        Run result = processRunService.runPreviousChildProcessor(
                new RunIdDto(99), new RunExecutionContext(42));

        assertEquals(RunStatus.GENERATED, result.getStatus());
        assertSame(previousQxp, result.getResult().getFinalQxp());
        assertEquals("R_42/DF_700.QXP", previousQxp.getFilePoolPath());
        assertEquals("D:\\Documents\\R_42\\DF_700.QXP", previousQxp.getFileFullPath());

        var order = inOrder(getRunPropertiesBusiness, loadTasksService, processTasksService,
                loadTaskDocumentsBusiness, checkService, getDocumentByIdBusiness, filePoolPort);
        order.verify(getRunPropertiesBusiness).execute(
                argThat(dto -> dto != null && dto.getRunId() == 99));
        order.verify(loadTasksService).loadTasks(result);
        order.verify(processTasksService).prepareTasks(result);
        order.verify(loadTaskDocumentsBusiness).loadDocuments(result);
        order.verify(checkService).check(result);
        order.verify(getDocumentByIdBusiness).getDocumentById(700);
        order.verify(filePoolPort).addFile(eq(result.getExecutionContext()),
                eq("R_42/DF_700.QXP"), same(previousQxp.getData()));

        verifyNoInteractions(runStartUpdateBusiness, endRunBusiness);
        verify(qxpsCallerService, never()).process(any());
        verify(qxpsCallerService, never()).render(any(), anyBoolean(), anyBoolean(),
                anyBoolean(), any(), any());
    }

    @Test
    @DisplayName("Previous child records missing QXP locally and remains Generated")
    void previousChildWithUnsetLastQxpOwnsOneUnspecifiedError() {
        RunProperties previousProperties = new RunProperties();
        previousProperties.setIdLastQxp(Integer.MIN_VALUE);
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(previousProperties);

        Run result = processRunService.runPreviousChildProcessor(
                new RunIdDto(99), new RunExecutionContext(42));

        assertEquals(RunStatus.GENERATED, result.getStatus());
        assertEquals(1, result.getErrors().size());
        assertEquals(RunError.UNSPECIFIED, result.getErrors().get(0).getCategory());
        assertNull(result.getResult().getFinalQxp());
        verifyNoInteractions(getDocumentByIdBusiness, runStartUpdateBusiness, endRunBusiness);
    }

    @Test
    @DisplayName("Zero and negative previous document identifiers remain set legacy integers")
    void previousChildAcceptsZeroAndNegativeLastQxpIdentifiers() {
        for (int documentId : new int[]{0, -7}) {
            clearInvocations(getRunPropertiesBusiness, getDocumentByIdBusiness, loadTasksService,
                    processTasksService, loadTaskDocumentsBusiness, checkService, filePoolPort);
            RunProperties previousProperties = new RunProperties();
            previousProperties.setIdLastQxp(documentId);
            DocumentDomain document = new DocumentDomain(documentId, "previous", "QXP",
                    DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, new byte[]{1});
            when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(previousProperties);
            when(getDocumentByIdBusiness.getDocumentById(documentId)).thenReturn(document);

            Run result = processRunService.runPreviousChildProcessor(
                    new RunIdDto(99), new RunExecutionContext(42));

            assertEquals(RunStatus.GENERATED, result.getStatus());
            assertSame(document, result.getResult().getFinalQxp());
            verify(getDocumentByIdBusiness).getDocumentById(documentId);
        }
    }

    @Test
    @DisplayName("Missing previous document row fails only the child launch boundary")
    void previousChildWithMissingDocumentRowBecomesErrorWithoutPersistence() {
        RunProperties previousProperties = new RunProperties();
        previousProperties.setIdLastQxp(700);
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(previousProperties);
        when(getDocumentByIdBusiness.getDocumentById(700)).thenReturn(null);

        Run result = processRunService.runPreviousChildProcessor(
                new RunIdDto(99), new RunExecutionContext(42));

        assertEquals(RunStatus.ERROR, result.getStatus());
        assertEquals(1, result.getErrors().size());
        assertEquals(RunError.BLOQUANTE, result.getErrors().get(0).getCategory());
        assertNull(result.getResult().getFinalQxp());
        verifyNoInteractions(runStartUpdateBusiness, endRunBusiness);
    }

    @Test
    @DisplayName("End retry reuses one timestamp and launch audit exists before Start_Run")
    void endRetryReusesTimestampAndAuditStartsBeforeDatabaseStart() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);
        doAnswer(invocation -> {
            Run started = invocation.getArgument(0);
            assertNotNull(started.getAudit());
            assertNotNull(started.getAudit().getStartDate());
            return null;
        }).when(runStartUpdateBusiness).execute(any(Run.class));

        List<LocalDateTime> attemptedEndDates = new ArrayList<>();
        List<String> attemptedTraces = new ArrayList<>();
        doAnswer(invocation -> {
            Run ending = invocation.getArgument(0);
            attemptedEndDates.add(ending.getEndDate());
            attemptedTraces.add(ending.getTraceLog());
            if (attemptedEndDates.size() == 1) {
                throw new RuntimeException("first End failed");
            }
            return null;
        }).when(endRunBusiness).execute(any(Run.class));

        Run result = processRunService.runProcessor(new RunIdDto(42));

        assertEquals(RunStatus.ERROR, result.getStatus());
        assertTrue(result.isTerminalStatePersisted());
        assertEquals(2, attemptedEndDates.size());
        assertNotNull(attemptedEndDates.get(0));
        assertEquals(attemptedEndDates.get(0), attemptedEndDates.get(1));
        assertTrue(attemptedTraces.get(0).contains("End attempt=1"));
        assertFalse(attemptedTraces.get(0).contains("End attempt=1 failed"));
        assertTrue(attemptedTraces.get(1).contains("End attempt=1 failed"));
        assertTrue(attemptedTraces.get(1).contains("End attempt=2"));
        assertFalse(attemptedTraces.get(1).contains("first End failed"));
    }

    @Test
    @DisplayName("Both End failures leave terminal persistence unconfirmed")
    void bothEndFailuresLeaveTerminalPersistenceUnconfirmed() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);
        doThrow(new RuntimeException("first End failed"), new RuntimeException("second End failed"))
                .when(endRunBusiness).execute(any(Run.class));

        Run result = processRunService.runProcessor(new RunIdDto(42));

        assertEquals(RunStatus.ERROR, result.getStatus());
        assertFalse(result.isTerminalStatePersisted());
        verify(endRunBusiness, times(2)).execute(result);
    }

    @Test
    @DisplayName("Should log bounded load and terminal run summaries")
    void logsBoundedLoadAndTerminalSummaries(CapturedOutput output) {
        runProperties.setIdSuivi(7001);
        runProperties.setTypeRapportCode(8);
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);
        com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult render =
                new com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult();
        render.setQxpData(new byte[]{1, 2, 3});
        render.setPdfData(new byte[]{4, 5});
        when(qxpsCallerService.render(any(), anyBoolean(), anyBoolean(), anyBoolean(), any(), any()))
                .thenReturn(render);
        processRunService.runProcessor(new RunIdDto(42));

        String logs = output.getAll();
        assertTrue(logs.contains("Run load summary: runId=42, suiviId=7001, reportTypeCode=8"));
        assertTrue(logs.contains("degraded=false"));
        assertTrue(logs.contains("taskCount=0"));
        assertTrue(logs.contains("gabaritBytes=0"));
        assertTrue(logs.contains("todoDocumentTaskCount=0"));
        assertTrue(logs.contains("dynamicTemplateBytes=0"));
        assertTrue(logs.contains("Run completed: runId=42, status=GENERATED"));
        assertTrue(logs.contains("terminalStatePersisted=true"));
        assertTrue(logs.contains("finalQxpBytes=3"));
        assertTrue(logs.contains("finalPdfBytes=2"));
        assertTrue(logs.contains("finalJpgBytes=0"));
    }

    @Test
    @DisplayName("Should propagate exception thrown during load")
    void shouldPropagateExceptionFromLoad() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class)))
                .thenThrow(new RuntimeException("properties failed"));

        Run run = TestRuns.run();
        run.setId(1);
        assertThrows(RuntimeException.class, () -> processRunService.load(run));
    }

    // --- getRunProperties ---

    @Test
    @DisplayName("Should return RunProperties from business layer")
    void shouldReturnRunPropertiesFromBusiness() {
        RunIdDto dto = new RunIdDto(99);
        when(getRunPropertiesBusiness.execute(dto)).thenReturn(runProperties);

        RunProperties result = processRunService.getRunProperties(dto);

        assertNotNull(result);
        assertSame(runProperties, result);
        verify(getRunPropertiesBusiness, times(1)).execute(dto);
    }

}
```

## 15. `src/test/java/com/socgen/sgs/api/quark/engine/diagnostic/LoggingSourcePolicyTest.java`

SHA-256: `00cc9805a011a25d5124cdd2305d400890833368bdd350ce2f013d042abafcfc`

Replace the complete file with:

```java
package com.socgen.sgs.api.quark.engine.diagnostic;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class LoggingSourcePolicyTest {

    @Test
    void productionLoggingDoesNotUseRawThrowableOverloadsOrKnownPayloadPatterns() throws IOException {
        Path sourceRoot = Path.of("src/main/java");
        if (!Files.isDirectory(sourceRoot)) {
            return; // IDE/packaged execution can use a different working directory.
        }
        List<String> forbidden = List.of(
                "QXPS call: {} {}", "values: {}", "log.debug(\"Result map",
                "describeParamMetadata", "Duplicate SQL-result block in task",
                "Error adding one SQL row block", "Duplicate generated block in dynamic task [{}]",
                "Dynamic cell produced no supported block for task [{}]",
                "Unable to add one Dynamic cell block for task [{}]");
        try (Stream<Path> files = Files.walk(sourceRoot)) {
            List<String> violations = files.filter(path -> path.toString().endsWith(".java"))
                    .flatMap(path -> {
                        String source = read(path);
                        Stream<String> tokens = forbidden.stream()
                                .filter(source::contains)
                                .map(token -> path + " contains " + token);
                        java.util.regex.Matcher logCalls = java.util.regex.Pattern.compile(
                                "log\\.(?:error|warn|info|debug|trace)\\((?s:.*?)\\);")
                                .matcher(source);
                        boolean rawMessage = false;
                        boolean rawThrowable = false;
                        boolean rawSql = false;
                        boolean rawDocumentOrPath = false;
                        while (logCalls.find()) {
                            String call = logCalls.group();
                            rawMessage |= call.contains("getMessage()");
                            rawThrowable |= call.matches(
                                    "(?s).*,\\s*(?:e|ex|ex2|failure|exception)\\s*\\);");
                            rawSql |= java.util.regex.Pattern.compile(
                                            "task\\.getSql\\(\\)(?!\\.length\\(\\))")
                                    .matcher(call).find();
                            rawSql |= java.util.regex.Pattern.compile(
                                            "(?s),\\s*(?:sql|query)\\s*(?:,|\\))")
                                    .matcher(call).find();
                            rawDocumentOrPath |= call.contains("documentName")
                                    || call.contains("saveAsPath") || call.contains("saveAsName")
                                    || call.contains("getUri().getPath()");
                        }
                        Stream<String> patterns = Stream.of(
                                rawMessage ? path + " logs getMessage()" : null,
                                rawThrowable ? path + " logs a raw Throwable" : null,
                                rawSql ? path + " logs raw SQL" : null,
                                rawDocumentOrPath ? path + " logs a document name/path" : null)
                                .filter(java.util.Objects::nonNull);
                        return Stream.concat(tokens, patterns);
                    })
                    .toList();
            assertTrue(violations.isEmpty(), () -> "Unsafe logging source patterns: " + violations);
        }
    }

    @Test
    void runFactoryIsTheOnlyProductionRunConstructorCallSite() throws IOException {
        Path sourceRoot = Path.of("src/main/java");
        if (!Files.isDirectory(sourceRoot)) {
            return;
        }
        try (Stream<Path> files = Files.walk(sourceRoot)) {
            List<Path> violations = files.filter(path -> path.toString().endsWith(".java"))
                    .filter(path -> !path.getFileName().toString().equals("RunFactory.java"))
                    .filter(path -> read(path).matches("(?s).*new\\s+Run\\s*\\(.*"))
                    .toList();
            assertTrue(violations.isEmpty(),
                    () -> "Production Run instances must use RunFactory: " + violations);
        }
    }

    @Test
    void diagnosticLimitsAndCorrelationFieldsAreConfiguredInResources() throws IOException {
        Path application = Path.of("src/main/resources/application.yaml");
        Path logback = Path.of("src/main/resources/logback-spring.xml");
        if (!Files.isRegularFile(application) || !Files.isRegularFile(logback)) {
            return;
        }

        String yaml = Files.readString(application);
        assertTrue(yaml.contains("max-chars: 3145728"));
        assertTrue(yaml.contains("event-message-max-chars: 1000"));
        assertTrue(yaml.contains("exception-summary-max-chars: 2000"));

        String logging = Files.readString(logback);
        for (String key : List.of("runId", "suiviId", "taskId", "stepIndex", "childRunId")) {
            assertTrue(logging.contains("%X{" + key + ":-}"), () -> "Missing MDC field " + key);
        }
        assertTrue(logging.contains("ECS_JSON_FILE"));
        assertFalse(logging.contains("%ex"), "Console pattern must not print raw exception text");
        assertTrue(logging.contains("name=\"org.springframework.jdbc.core\" level=\"WARN\""));
        assertTrue(logging.contains("name=\"org.hibernate.SQL\" level=\"OFF\""));
        assertTrue(logging.contains("name=\"org.hibernate.orm.jdbc.bind\" level=\"OFF\""));
        assertTrue(logging.contains("name=\"org.apache.axis.transport.http\" level=\"WARN\""));
        assertTrue(logging.contains("name=\"org.apache.commons.httpclient\" level=\"WARN\""));
        assertTrue(logging.contains("name=\"httpclient.wire\" level=\"OFF\""));
        assertTrue(logging.contains("name=\"reactor.netty.http.client\" level=\"WARN\""));
    }

    @Test
    void boundedEvidenceSummaryLogsRemainPresent() throws IOException {
        Map<Path, List<String>> requiredTokens = Map.of(
                Path.of("src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java"),
                List.of("Run load summary:", "Run completed:", "terminalStatePersisted={}"),
                Path.of("src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImpl.java"),
                List.of("Task result:", "storedDataRows={}"),
                Path.of("src/main/java/com/socgen/sgs/api/quark/engine/business/ProcessSqlBusiness.java"),
                List.of("SQL task completed:", "sqlChars={}", "bindCount={}", "rowCount={}",
                        "SQL row anomalies:"),
                Path.of("src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/DynamiqueTaskProcessStrategy.java"),
                List.of("Dynamic SQL task completed:", "sqlChars={}", "bindCount={}", "rowCount={}",
                        "Dynamic cell anomalies:"),
                Path.of("src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/client/QxpsHttpClient.java"),
                List.of("QXPS call:", "QXPS completed:", "QXPS failed:", "responseChars={}"),
                Path.of("src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxpsm/QxpsmSoapClient.java"),
                List.of("QXPSM started:", "QXPSM completed:", "QXPSM failed:"));

        for (Map.Entry<Path, List<String>> entry : requiredTokens.entrySet()) {
            if (!Files.isRegularFile(entry.getKey())) {
                continue;
            }
            String source = Files.readString(entry.getKey());
            for (String token : entry.getValue()) {
                assertTrue(source.contains(token),
                        () -> entry.getKey() + " is missing bounded log token " + token);
            }
        }
    }

    private static String read(Path path) {
        try {
            return Files.readString(path);
        } catch (IOException failure) {
            throw new IllegalStateException("Cannot inspect " + path, failure);
        }
    }
}
```

## Verification

From the Java repository root:

```bash
mvn clean install
```

Required result:

- compilation succeeds;
- the complete Maven test suite succeeds;
- `LoggingSourcePolicyTest` succeeds;
- Rabbit remains disabled in the single main `application.yaml`;
- `spring.jpa.show-sql` remains false;
- no SQL text, bind value, document path, XML, request/response payload or binary data appears in captured logs.

Before the first Swagger run, verify the effective safety settings:

```bash
rg -n 'show-sql:|rabbit:|enabled:' src/main/resources/application.yaml
rg -n 'springframework.jdbc.core|hibernate.SQL|hibernate.orm.jdbc.bind|axis.transport.http|httpclient.wire|reactor.netty.http.client' src/main/resources/logback-spring.xml
```

