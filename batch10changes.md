# EOS Quark Engine — Batch 10 Changes
**Theme: DID (Document Identity) lenient parsing — tolerate a gabarit with no DID**

_Single file: `infra/interop/qxps/identity/DocumentIdentityService.java` (whole-file)._

## Findings fixed (4)
| # | Sev | Fix |
|---|---|---|
| 16 | HIGH | `getElementValueByIdName`: null/blank XML or no match → returns `""` (was NPE on null / returned `null`). A gabarit with no DID box no longer crashes the prepareGabarit path. |
| 23 | HIGH | `parseDocumentIdentity`: null/blank input → empty `DocumentIdentity` (was `requireNonNull` NPE + empty-string throw). |
| 41 | MEDIUM | `parseDocumentIdentity`: fewer than 6 parts → empty identity (was a hard throw). |
| 42 | MEDIUM | `parseDateTime`: empty/unparseable → `DateTime.MinValue` (0001-01-01 00:00:00), no throw; lenient `M/d/uuuu H:mm:ss` pattern. |

## Why (the .NET truth)
- `.NET Document_Identity(string)` is **tolerant**: null/blank or `<6` parts → an empty identity (all fields default), never throws. Only populates fields when `Length >= 6` (unit code when `>= 7`).
- `.NET ConversionInvariante.ToDateTime` returns **`DateTime.MinValue`** for empty/unparseable, and `TryParse` is lenient about 1- vs 2-digit month/day/hour.
- `.NET QXP_XML.GetValue` returns `""` (not null) when the named element is absent.
These all matter because the gabarit DID is read on the **critical `Run.prepareGabarit` path** (`Run.cs:94 Evaluate_Document_Identity`) — a gabarit with no DID must yield an empty identity, not abort the run.

## Parity note on the sentinel
Uses `LocalDateTime.of(1,1,1,0,0,0)` to match .NET `DateTime.MinValue` exactly — **not** `LocalDateTime.MIN` (which is `-999999999-01-01`, and would diverge if ever formatted/compared).

## Genuinely-fatal errors preserved
A **malformed XML document** (not merely a missing DID box) still throws from `getElementValueByIdName`'s parse `catch` — only the *absence* of the DID is tolerated, matching .NET. No tests touch this class.

---

## `infra/interop/qxps/identity/DocumentIdentityService.java` — CHANGED (whole file)
```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.identity;

import com.socgen.sgs.api.quark.engine.domain.DocumentIdentity;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.message.FetchXmlMessage;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.client.QxpsHttpClient;
import com.socgen.sgs.api.quark.engine.infra.interop.qxps.model.QxpsResponseInfo;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import java.io.StringReader;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.Objects;

/**
 * Infra implementation of {@link DocumentIdentityPort}.
 * Fetches XML from QXPS and parses the document identity.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class DocumentIdentityService implements DocumentIdentityPort {

    private static final String ID_TAG = "ID";
    private static final String NAME_ATTRIBUTE = "NAME";

    private static final String PIPE_DELIMITER = "\\|";
    private static final int MIN_IDENTITY_PARTS = 6;
    private static final int IDX_FND_CODE = 0;
    private static final int IDX_SUIVI = 1;
    private static final int IDX_RUN = 2;
    private static final int IDX_LANGUE = 3;
    private static final int IDX_DUE_DATE = 4;
    private static final int IDX_GENERATION_DATETIME = 5;
    private static final int IDX_UNIT_CODE = 6;
    // Lenient pattern (1- or 2-digit month/day/hour), mirroring .NET invariant DateTime.TryParse.
    private static final DateTimeFormatter DATE_TIME_FORMATTER =
            DateTimeFormatter.ofPattern("M/d/uuuu H:mm:ss", Locale.ROOT);
    /** .NET DateTime.MinValue (0001-01-01 00:00:00) — the sentinel ConversionInvariante.ToDateTime returns. */
    private static final LocalDateTime DATE_MIN = LocalDateTime.of(1, 1, 1, 0, 0, 0);

    private final QxpsHttpClient qxpsHttpClient;

    /**
     * Fetches XML content for a named box of a document already in the QXPS pool.
     *
     * @param documentName the document name in the pool
     * @param boxName      the box name (e.g. "DID")
     * @return raw XML string
     */
    @Override
    public String fetchXmlForBox(String documentName, String boxName) {
        Objects.requireNonNull(documentName, "documentName must not be null");
        Objects.requireNonNull(boxName, "boxName must not be null");

        log.info("Fetching XML for document: {}, box: {}", documentName, boxName);

        FetchXmlMessage message = new FetchXmlMessage(boxName);
        QxpsResponseInfo response = qxpsHttpClient.execute(documentName, message);

        String xmlContent = response.getTextResponse();
        log.debug("Received XML content length={} for document: {}", xmlContent != null ? xmlContent.length() : 0, documentName);
        return xmlContent;
    }

    /**
     * Extracts text content from an XML string by matching the NAME attribute on an ID element.
     *
     * @param xmlContent the raw XML string
     * @param idName     the value of NAME attribute to search for
     * @return the text value, or null if not found
     */
    @Override
    public String getElementValueByIdName(String xmlContent, String idName) {
        Objects.requireNonNull(idName, "idName must not be null");
        // .NET QXP_XML.GetValue tolerates a gabarit with no DID box → returns "" so the document gets
        // an empty identity rather than an NPE on the critical prepareGabarit path. Finding #16.
        if (xmlContent == null || xmlContent.isBlank()) {
            return "";
        }

        // Strip BOM and leading non-XML characters
        xmlContent = xmlContent.strip();
        if (xmlContent.startsWith("\uFEFF")) {
            xmlContent = xmlContent.substring(1).strip();
        }
        int xmlDeclIndex = xmlContent.indexOf("<?xml");
        int rootIndex = xmlContent.indexOf("<");
        if (xmlDeclIndex > 0) {
            xmlContent = xmlContent.substring(xmlDeclIndex);
        } else if (rootIndex > 0) {
            xmlContent = xmlContent.substring(rootIndex);
        }

        try {
            DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
            // Security: disable external entities (XXE prevention)
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);

            DocumentBuilder builder = factory.newDocumentBuilder();
            Document document = builder.parse(new InputSource(new StringReader(xmlContent)));
            document.getDocumentElement().normalize();

            NodeList idElements = document.getElementsByTagName(ID_TAG);
            for (int i = 0; i < idElements.getLength(); i++) {
                Element idElement = (Element) idElements.item(i);
                if (idName.equals(idElement.getAttribute(NAME_ATTRIBUTE))) {
                    Element boxElement = (Element) idElement.getParentNode();
                    NodeList richTextElements = boxElement.getElementsByTagName("RICHTEXT");
                    if (richTextElements.getLength() > 0) {
                        String value = richTextElements.item(0).getTextContent();
                        log.debug("Found element value for ID NAME '{}': {}", idName, value);
                        return value;
                    }
                }
            }

            log.warn("No element found with ID NAME: {}", idName);
            return ""; // .NET returns "" (empty), not null, when the named element is absent. Finding #16.

        } catch (Exception e) {
            throw new IllegalStateException(
                    String.format("Error parsing XML content for ID NAME: %s", idName), e);
        }
    }

    /**
     * Parses a pipe-separated identity string into a {@link DocumentIdentity}.
     * Format: ID_Fnd_Code|ID_Suivi|ID_Run|ID_Langue|Due_Date|Generation_DateTime|ID_Unit_Code(optional)
     *
     * @param identityString the raw pipe-separated identity value
     * @return populated {@link DocumentIdentity}
     */
    @Override
    public DocumentIdentity parseDocumentIdentity(String identityString) {
        // .NET Document_Identity(string) is tolerant: a null/blank value, or one that splits into fewer
        // than 6 parts, yields an EMPTY identity (all fields default) — it never throws. This is the
        // critical prepareGabarit path, where a gabarit may legitimately have no DID. Findings #16/#23/#41.
        String s = (identityString == null) ? "" : identityString;
        String[] parts = s.split(PIPE_DELIMITER, -1);

        if (s.trim().isEmpty() || parts.length < MIN_IDENTITY_PARTS) {
            log.debug("Empty/short document identity ('{}') → default (empty) identity", identityString);
            return DocumentIdentity.builder().build();
        }

        log.debug("Parsing document identity string: {}", identityString);

        String idFndCode = parts[IDX_FND_CODE].trim();
        String idSuivi = parts[IDX_SUIVI].trim();
        String idRun = parts[IDX_RUN].trim();
        String idLangue = parts[IDX_LANGUE].trim();
        LocalDateTime dueDate = parseDateTime(parts[IDX_DUE_DATE].trim(), "Due Date");
        LocalDateTime generationDateTime = parseDateTime(parts[IDX_GENERATION_DATETIME].trim(), "Generation DateTime");

        String idUnitCode = null;
        if (parts.length > IDX_UNIT_CODE) {
            String unitCodeValue = parts[IDX_UNIT_CODE].trim();
            if (!unitCodeValue.isEmpty()) {
                idUnitCode = unitCodeValue;
            }
        }

        DocumentIdentity identity = DocumentIdentity.builder()
                .idFndCode(idFndCode)
                .idSuivi(idSuivi)
                .idRun(idRun)
                .idLangue(idLangue)
                .dueDate(dueDate)
                .generationDateTime(generationDateTime)
                .idUnitCode(idUnitCode)
                .build();

        log.info("Successfully parsed document identity: {}", identity);
        return identity;
    }

    private LocalDateTime parseDateTime(String dateTimeString, String fieldName) {
        // .NET ConversionInvariante.ToDateTime returns DateTime.MinValue for an empty/unparseable value
        // (it does NOT throw). Mirror that with the DATE_MIN sentinel. Finding #42.
        if (dateTimeString == null || dateTimeString.trim().isEmpty()) {
            return DATE_MIN;
        }
        try {
            return LocalDateTime.parse(dateTimeString.trim(), DATE_TIME_FORMATTER);
        } catch (Exception e) {
            log.warn("Lenient parse of {} '{}' failed → DateTime.MinValue", fieldName, dateTimeString);
            return DATE_MIN;
        }
    }
}
```

## Apply checklist
- [ ] Replace `DocumentIdentityService.java`
- [ ] `mvn compile` + `mvn test`
