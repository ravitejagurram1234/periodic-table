# EOS Quark — Batch 12 (REDO) Changes

**Apply on top of Batch 11 (redo).** Supersedes the original Batch 12.

## Scope
Single file — **`domain/xml/QxpXml.java`** (XPath read-side of the gabarit document). Six findings, all
hardening the page/box/table parsing. **No deferred items in this batch.**

- **.NET-free code policy**: identifiers + Batch-12 comments carry no .NET references; the .NET source
  mapping lives only in the table below.
- **Comment-scrub scope** ("only Batch 12's own"): de-.NET'd the comments at the six finding sites
  (#46/#78/#79/#77/#80). **Left as inherited**: the section header at the top of the XPath-constants block
  (`// XPath patterns — direct mapping from .NET QXP_XML constants`) — predates Batch 12, treated like a
  class header. Say the word to strip it.

## Findings in this batch

| Finding | Method | What changed | .NET source (reference only) |
|---|---|---|---|
| #46 | `getPageNum` | not-found / unparseable page → `Integer.MIN_VALUE` (not 0), via the shared lenient parser | `QXP_XML.GetPageNum` returns `int.MinValue` |
| #78 | `parseIntSafe` | lenient parse: strip trailing `*`, strip spaces, `,`→`.`, `BigDecimal`; `MIN_VALUE` on null/blank/unparseable | `ConversionInvariante.ToInt` |
| #77 | box / table page loops | guard `!= Integer.MIN_VALUE` (not `> 0`) so a genuine **page 0 / pasteboard** still counts | `QXP_File.IsSet` page check |
| #45 | table-cell counting | reach the owning element via `((Attr) pageAttr).getOwnerElement()` — `getParentNode()` on an attribute is always `null`, which is why table cells were never counted | `GetBlocInfo` table-cell walk |
| #79 | `getBlocInfo` position read | read **all** descendants (`.//*`) so `LEFT/TOP/RIGHT/BOTTOM` nested under `POSITION` are found | `SelectDescendants(Element)` |
| #80 | `evaluateNodeListAsStrings` | keep blank / whitespace names (no blank-filter) | name collection keeps blanks |

> No automated test references `QxpXml` (see Doc 3 gap list), so no test file changes.

---

## File (full content — whole-file copy-paste)

### 1. `domain/xml/QxpXml.java`
```java
package com.socgen.sgs.api.quark.engine.domain.xml;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBlocInfo;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DProjectInfo;
import lombok.extern.slf4j.Slf4j;

import javax.xml.xpath.XPath;
import javax.xml.xpath.XPathConstants;
import javax.xml.xpath.XPathExpressionException;
import javax.xml.xpath.XPathFactory;
import java.io.StringReader;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

import org.w3c.dom.Document;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;

/**
 * Stores and analyses the XML structure of a QuarkXPress document.
 * Provides XPath-based queries for bloc values, names, pages, layouts, and structural info.
 *
 * <p>Usage:
 * <pre>
 *   QxpXml xml = QxpXml.createFromXml(xmlString);
 *   String value = xml.getValue("MY_BLOC_NAME");
 *   List&lt;String&gt; names = xml.getListBoxNameStartWith("PDF_");
 *   int pageNum = xml.getPageNum("MY_BLOC_NAME");
 * </pre>
 *
 * Cross-reference: QXP.Engine.Core.QXP_XML
 */
@Slf4j
public class QxpXml {

    // ========================================================================
    // XPath patterns — direct mapping from .NET QXP_XML constants
    // ========================================================================

    /** Retrieves the text value inside a named box: //ID[@NAME='X']/..//PARAGRAPH/RICHTEXT/text() */
    private static final String BLOC_VALUE_PATTERN =
            "//ID[@NAME='%s']/..//PARAGRAPH/RICHTEXT/text()";

    /** All CT_TEXT box/cell names: (//CELL | //BOX)[@BOXTYPE='CT_TEXT']/ID/@NAME */
    private static final String CT_TEXT_BOX_NAMES_PATTERN =
            "(//CELL | //BOX)[@BOXTYPE='CT_TEXT']/ID/@NAME";

    /** Relative path from a box ID to its RICHTEXT value */
    private static final String CT_BOX_VALUE_RELATIVE_BOX_ID =
            "../..//PARAGRAPH/RICHTEXT/text()";

    /** UID of a named bloc: //ID[@NAME='X']/@UID */
    private static final String UID_BLOC_PATTERN =
            "//ID[@NAME='%s']/@UID";

    /** Page ID of a named bloc (searches BOX, TABLE, and TABLE containing CELL): */
    private static final String PAGE_ID_BLOC_PATTERN =
            "(//BOX[ID[@NAME='%s']] | //TABLE[ID[@NAME='%s']] | //TABLE[ROW/CELL/ID[@NAME='%s']])/GEOMETRY/@PAGE";

    /** Position of a named bloc: /PROJECT/LAYOUT/SPREAD/BOX[ID[@NAME='X']]/GEOMETRY/POSITION */
    private static final String POSITION_BLOC_PATTERN =
            "/PROJECT/LAYOUT/SPREAD/BOX[ID[@NAME='%s']]/GEOMETRY/POSITION";

    /** Layout name containing a named bloc: /PROJECT/LAYOUT[//ID[@NAME='X']]/ID/@NAME */
    private static final String LAYOUT_NAME_BLOC_PATTERN =
            "/PROJECT/LAYOUT[//ID[@NAME='%s']]/ID/@NAME";

    /** Box names starting with a prefix: //ID[starts-with(@NAME,'X')]/@NAME */
    private static final String BOX_NAME_START_WITH_PATTERN =
            "//ID[starts-with(@NAME,'%s')]/@NAME";

    /** Box names containing a string: //ID[contains(@NAME,'X')]/@NAME */
    private static final String BOX_NAME_CONTAINS_PATTERN =
            "//ID[contains(@NAME,'%s')]/@NAME";

    /** Overflow box names: //OVERMATTER/../../../ID/@NAME */
    private static final String BOX_NAME_OVERFLOW_PATTERN =
            "//OVERMATTER/../../../ID/@NAME";

    /** Check if a specific box is in overflow: //OVERMATTER/../../../ID[@NAME='X'] */
    private static final String IS_BOX_OVERFLOW_PATTERN =
            "//OVERMATTER/../../../ID[@NAME='%s']";

    /** Number of rows in a named table: //TABLE[ID[@NAME='X']]//ROW */
    private static final String NB_LIGNES_IN_TABLE_PATTERN =
            "//TABLE[ID[@NAME='%s']]//ROW";

    /** Project root: /PROJECT */
    private static final String PROJECT_PATTERN = "/PROJECT";

    /** All spread IDs: //SPREAD/ID */
    private static final String SPREAD_ID_PATTERN = "//SPREAD/ID";

    /** All box geometries (direct in spread): //BOX/GEOMETRY */
    private static final String BOX_GEOMETRY_PATTERN = "//BOX/GEOMETRY";

    /** Table geometry page attributes: //TABLE/GEOMETRY/@PAGE */
    private static final String BOX_TABLE_GEOMETRY_PAGE_PATTERN = "//TABLE/GEOMETRY/@PAGE";

    /** Relative path from table geometry to cell IDs: ../../ROW/CELL/ID */
    private static final String BOX_TABLE_RELATIVE_TABLE_GEOMETRY_PAGE_PATTERN =
            "../../ROW/CELL/ID";

    /** Master process ID: /PROCESSID/MASTER/ID/text() */
    private static final String MASTER_PROCESS_ID_PATTERN = "/PROCESSID/MASTER/ID/text()";

    // Position element names
    private static final String LEFT_KEY = "LEFT";
    private static final String TOP_KEY = "TOP";
    private static final String RIGHT_KEY = "RIGHT";
    private static final String BOTTOM_KEY = "BOTTOM";

    /** BOM character that sometimes prefixes XML from QuarkXPress server */
    private static final char BOM_CHAR = 65279;

    /** Empty project XML structure */
    private static final String EMPTY_PROJECT_XML =
            "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?><PROJECT></PROJECT>";

    /** Singleton empty QxpXml instance (non-null but contains no data) */
    public static final QxpXml EMPTY = createFromXml(EMPTY_PROJECT_XML);

    // ========================================================================
    // Instance fields
    // ========================================================================

    private final Document xmlDocument;
    private final XPath xpath;
    private DProjectInfo projectInfo;

    // ========================================================================
    // Constructor (private — use static factories)
    // ========================================================================

    private QxpXml(Document xmlDocument) {
        this.xmlDocument = xmlDocument;
        this.xpath = XPathFactory.newInstance().newXPath();
    }

    // ========================================================================
    // Static factories
    // ========================================================================

    /**
     * Create a QxpXml instance from a raw XML string.
     *
     * @param xml the XML content (from QXPS server XML command)
     * @return a QxpXml instance, or EMPTY if parsing fails
     */
    public static QxpXml createFromXml(String xml) {
        if (xml == null || xml.isBlank()) {
            log.warn("Cannot create QxpXml from null/blank XML");
            return null;
        }
        try {
            String fixedXml = fixXml(xml);
            DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
            // Security: disable external entities
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
            DocumentBuilder builder = factory.newDocumentBuilder();
            Document doc = builder.parse(new InputSource(new StringReader(fixedXml)));
            return new QxpXml(doc);
        } catch (Exception e) {
            log.error("Failed to parse QXP XML", e);
            return null;
        }
    }

    /**
     * Fix XML by removing BOM character if present.
     * The QuarkXPress server sometimes prepends a BOM character to XML responses.
     *
     * @param xml the raw XML string
     * @return the cleaned XML string
     */
    private static String fixXml(String xml) {
        if (xml.length() > 0 && xml.charAt(0) == BOM_CHAR) {
            return xml.substring(1);
        }
        return xml;
    }

    // ========================================================================
    // Bloc value queries
    // ========================================================================

    /**
     * Get the text value contained in a named bloc (box).
     *
     * @param blocName the box name
     * @return the value if found, otherwise empty string
     */
    public String getValue(String blocName) {
        String expression = String.format(BLOC_VALUE_PATTERN, blocName);
        return evaluateString(expression, "");
    }

    /**
     * Get the UID (unique identifier) of a named bloc.
     *
     * @param blocName the box name
     * @return the UID if found, otherwise empty string
     */
    public String getUID(String blocName) {
        String expression = String.format(UID_BLOC_PATTERN, blocName);
        return evaluateString(expression, "");
    }

    /**
     * Check if a named element exists in the document.
     *
     * @param name the element name
     * @return true if the element exists
     */
    public boolean existName(String name) {
        String uid = getUID(name);
        return uid != null && !uid.isBlank();
    }

    // ========================================================================
    // Box name queries
    // ========================================================================

    /**
     * Get the list of box names starting with the given prefix.
     *
     * @param name the prefix to search for
     * @return list of matching box names
     */
    public List<String> getListBoxNameStartWith(String name) {
        String expression = String.format(BOX_NAME_START_WITH_PATTERN, name);
        return evaluateNodeListAsStrings(expression);
    }

    /**
     * Get the list of box names ending with the given suffix.
     *
     * @param suffix the suffix to search for
     * @return list of matching box names
     */
    public List<String> getListBoxNameEndWith(String suffix) {
        // XPath 1.0 has no ends-with, so we use contains + Java filter
        String expression = String.format(BOX_NAME_CONTAINS_PATTERN, suffix);
        List<String> allMatches = evaluateNodeListAsStrings(expression);
        List<String> filtered = new ArrayList<>();
        for (String match : allMatches) {
            if (match.endsWith(suffix)) {
                filtered.add(match);
            }
        }
        return filtered;
    }

    /**
     * Get the list of box names containing the given string.
     *
     * @param name the string to search for
     * @return list of matching box names
     */
    public List<String> getListBoxNameContains(String name) {
        String expression = String.format(BOX_NAME_CONTAINS_PATTERN, name);
        return evaluateNodeListAsStrings(expression);
    }

    /**
     * Get the list of box names that are in overflow state.
     *
     * @return list of overflow box names
     */
    public List<String> getOverflowBoxes() {
        return evaluateNodeListAsStrings(BOX_NAME_OVERFLOW_PATTERN);
    }

    /**
     * Check if a named box is in overflow state.
     *
     * @param name the box name
     * @return true if the box is in overflow
     */
    public boolean checkBoxOverflow(String name) {
        String expression = String.format(IS_BOX_OVERFLOW_PATTERN, name);
        try {
            NodeList nodes = (NodeList) xpath.evaluate(expression, xmlDocument, XPathConstants.NODESET);
            return nodes.getLength() > 0;
        } catch (XPathExpressionException e) {
            log.warn("XPath error checking overflow for [{}]", name, e);
            return false;
        }
    }

    // ========================================================================
    // Page and layout queries
    // ========================================================================

    /**
     * Get the real page number for a named bloc.
     * Strips trailing '*' characters (left/right page indicators) before parsing.
     *
     * @param blocName the box name
     * @return the page number, or 0 if not found
     */
    public int getPageNum(String blocName) {
        // Returns Integer.MIN_VALUE (not 0) for a not-found / unparseable page, and parses leniently
        // (trailing '*' page markers, decimals, spaces). Delegates to the shared lenient parser.
        // Findings #46 / #78.
        return parseIntSafe(getPageID(blocName));
    }

    /**
     * Get the raw page ID for a named bloc.
     * May contain '*' suffixes indicating page position relative to spine.
     *
     * @param blocName the box name
     * @return the page ID string, or empty string if not found
     */
    public String getPageID(String blocName) {
        String expression = String.format(PAGE_ID_BLOC_PATTERN, blocName, blocName, blocName);
        return evaluateString(expression, "");
    }

    /**
     * Get the layout name containing a named bloc.
     *
     * @param blocName the box name
     * @return the layout name, or empty string if not found
     */
    public String getLayoutName(String blocName) {
        String expression = String.format(LAYOUT_NAME_BLOC_PATTERN, blocName);
        return evaluateString(expression, "");
    }

    // ========================================================================
    // Bloc info queries
    // ========================================================================

    /**
     * Get position and identification info for a named bloc.
     *
     * @param blocName the box name
     * @return a DBlocInfo with name, page, UID, and position coordinates
     */
    public DBlocInfo getBlocInfo(String blocName) {
        DBlocInfo info = new DBlocInfo();

        // 1 - Name
        info.setName(blocName);

        // 2 - Page number
        info.setPage(getPageNum(blocName));

        // 3 - UID
        info.setUid(getUID(blocName));

        // 4 - Position coordinates
        String expression = String.format(POSITION_BLOC_PATTERN, blocName);
        try {
            NodeList positionNodes = (NodeList) xpath.evaluate(expression, xmlDocument, XPathConstants.NODESET);
            if (positionNodes.getLength() > 0) {
                Node positionNode = positionNodes.item(0);
                // Read ALL descendant elements (not just direct children) so LEFT/TOP/RIGHT/BOTTOM
                // nested below POSITION are found, not only direct children. #79
                NodeList children = (NodeList) xpath.evaluate(".//*", positionNode, XPathConstants.NODESET);
                for (int i = 0; i < children.getLength(); i++) {
                    Node child = children.item(i);
                    String nodeName = child.getNodeName();
                    String nodeValue = child.getTextContent();
                    switch (nodeName) {
                        case LEFT_KEY:
                            info.setLeft(parseBigDecimal(nodeValue));
                            break;
                        case TOP_KEY:
                            info.setTop(parseBigDecimal(nodeValue));
                            break;
                        case RIGHT_KEY:
                            info.setRight(parseBigDecimal(nodeValue));
                            break;
                        case BOTTOM_KEY:
                            info.setBottom(parseBigDecimal(nodeValue));
                            break;
                        default:
                            break;
                    }
                }
            }
        } catch (XPathExpressionException e) {
            log.warn("XPath error getting bloc info for [{}]", blocName, e);
        }

        return info;
    }

    // ========================================================================
    // Table queries
    // ========================================================================

    /**
     * Get the number of rows in a named table.
     *
     * @param tableName the table name
     * @return the number of rows
     */
    public int getNbLignes(String tableName) {
        String expression = String.format(NB_LIGNES_IN_TABLE_PATTERN, tableName);
        try {
            NodeList nodes = (NodeList) xpath.evaluate(expression, xmlDocument, XPathConstants.NODESET);
            return nodes.getLength();
        } catch (XPathExpressionException e) {
            log.warn("XPath error counting rows for table [{}]", tableName, e);
            return 0;
        }
    }

    // ========================================================================
    // Project info
    // ========================================================================

    /**
     * Get structural information about the project (spreads, boxes per page, etc.).
     * Result is cached after first computation.
     *
     * @return the project info
     */
    public DProjectInfo getProjectInfo() {
        if (this.projectInfo != null) {
            return this.projectInfo;
        }
        this.projectInfo = buildProjectInfo();
        return this.projectInfo;
    }

    /**
     * Build project info by analyzing the XML structure.
     * Counts spreads, boxes per page (both direct boxes and boxes inside tables).
     */
    private DProjectInfo buildProjectInfo() {
        DProjectInfo info = new DProjectInfo();

        try {
            // 1 - Project name and XML version
            NodeList projectNodes = (NodeList) xpath.evaluate(PROJECT_PATTERN, xmlDocument, XPathConstants.NODESET);
            if (projectNodes.getLength() > 0) {
                Node projectNode = projectNodes.item(0);
                String projectName = getAttributeValue(projectNode, "PROJECTNAME");
                String xmlVersion = getAttributeValue(projectNode, "XMLVERSION");
                info.setName(projectName);
                info.setXmlVersion(xmlVersion);
            }

            // 2 - Count spreads
            NodeList spreadNodes = (NodeList) xpath.evaluate(SPREAD_ID_PATTERN, xmlDocument, XPathConstants.NODESET);
            info.setNbSpread(spreadNodes.getLength());

            // 3 - Count boxes directly in spreads
            NodeList boxGeometryNodes = (NodeList) xpath.evaluate(BOX_GEOMETRY_PATTERN, xmlDocument, XPathConstants.NODESET);
            int totalBoxes = 0;
            for (int i = 0; i < boxGeometryNodes.getLength(); i++) {
                Node geomNode = boxGeometryNodes.item(i);
                String pageStr = getAttributeValue(geomNode, "PAGE");
                int currentPage = parseIntSafe(pageStr);
                if (currentPage != Integer.MIN_VALUE) { // page 0 / pasteboard counts too; only MIN_VALUE means "no page". #77
                    info.getPageBoxes().merge(currentPage, 1, Integer::sum);
                }
                totalBoxes++;
            }

            // 4 - Count boxes inside tables
            NodeList tableGeomPages = (NodeList) xpath.evaluate(BOX_TABLE_GEOMETRY_PAGE_PATTERN, xmlDocument, XPathConstants.NODESET);
            for (int i = 0; i < tableGeomPages.getLength(); i++) {
                Node pageAttr = tableGeomPages.item(i);
                int currentPage = parseIntSafe(pageAttr.getNodeValue());
                if (currentPage != Integer.MIN_VALUE) { // page 0 / pasteboard counts too; only MIN_VALUE means "no page". #77
                    // Count cell IDs relative to this table. pageAttr is an ATTRIBUTE node, whose owning
                    // element is reached via getOwnerElement() — getParentNode() on an attribute is ALWAYS
                    // null, which is why table cells were never counted. Finding #45.
                    Node tableGeomNode = (pageAttr instanceof org.w3c.dom.Attr)
                            ? ((org.w3c.dom.Attr) pageAttr).getOwnerElement()   // GEOMETRY
                            : pageAttr.getParentNode();
                    if (tableGeomNode != null && tableGeomNode.getParentNode() != null) {
                        Node tableNode = tableGeomNode.getParentNode(); // TABLE
                        NodeList cellIds = findCellIds(tableNode);
                        for (int j = 0; j < cellIds.getLength(); j++) {
                            info.getPageBoxes().merge(currentPage, 1, Integer::sum);
                            totalBoxes++;
                        }
                    }
                }
            }

            info.setNbBox(totalBoxes);

        } catch (XPathExpressionException e) {
            log.error("XPath error building project info", e);
        }

        return info;
    }

    // ========================================================================
    // Process ID queries (used with getprocessid command XML)
    // ========================================================================

    /**
     * Get the master process ID from a getprocessid XML response.
     *
     * @return the master process ID, or empty string if not found
     */
    public String getMasterProcessID() {
        return evaluateString(MASTER_PROCESS_ID_PATTERN, "");
    }

    // ========================================================================
    // Name-value extraction (all CT_TEXT boxes)
    // ========================================================================

    /**
     * Get all box names and their text values from the document.
     * Only includes CT_TEXT boxes with defined names.
     *
     * @return list of name-value pairs as String arrays [name, value]
     */
    public List<String[]> getNamesValuesBoxes() {
        List<String[]> result = new ArrayList<>();
        try {
            NodeList nameNodes = (NodeList) xpath.evaluate(CT_TEXT_BOX_NAMES_PATTERN, xmlDocument, XPathConstants.NODESET);
            for (int i = 0; i < nameNodes.getLength(); i++) {
                Node nameNode = nameNodes.item(i);
                String name = nameNode.getNodeValue();
                if (name == null || name.isBlank()) {
                    continue;
                }

                // Evaluate relative XPath from the NAME attribute node to get the value
                String value = "";
                try {
                    Node valueNode = (Node) xpath.evaluate(CT_BOX_VALUE_RELATIVE_BOX_ID, nameNode, XPathConstants.NODE);
                    if (valueNode != null) {
                        value = valueNode.getNodeValue();
                        if (value == null) {
                            value = "";
                        }
                    }
                } catch (XPathExpressionException e) {
                    // Value not found, use empty string
                }

                result.add(new String[]{name, value});
            }
        } catch (XPathExpressionException e) {
            log.warn("XPath error getting names/values", e);
        }
        return result;
    }

    // ========================================================================
    // Private helper methods
    // ========================================================================

    /**
     * Evaluate an XPath expression and return the first matching string.
     *
     * @param expression the XPath expression
     * @param defaultValue the default value if no match
     * @return the first match or defaultValue
     */
    private String evaluateString(String expression, String defaultValue) {
        try {
            NodeList nodes = (NodeList) xpath.evaluate(expression, xmlDocument, XPathConstants.NODESET);
            if (nodes.getLength() > 0) {
                Node node = nodes.item(0);
                String value = node.getNodeValue();
                if (value == null) {
                    value = node.getTextContent();
                }
                return value != null ? value : defaultValue;
            }
        } catch (XPathExpressionException e) {
            log.warn("XPath evaluation error for expression [{}]", expression, e);
        }
        return defaultValue;
    }

    /**
     * Evaluate an XPath expression and return all matching values as a string list.
     *
     * @param expression the XPath expression
     * @return list of matched string values
     */
    private List<String> evaluateNodeListAsStrings(String expression) {
        List<String> result = new ArrayList<>();
        try {
            NodeList nodes = (NodeList) xpath.evaluate(expression, xmlDocument, XPathConstants.NODESET);
            for (int i = 0; i < nodes.getLength(); i++) {
                Node node = nodes.item(i);
                String value = node.getNodeValue();
                if (value == null) {
                    value = node.getTextContent();
                }
                if (value != null) { // keep blank/whitespace names too — do not blank-filter. #80
                    result.add(value);
                }
            }
        } catch (XPathExpressionException e) {
            log.warn("XPath evaluation error for expression [{}]", expression, e);
        }
        return result;
    }

    /**
     * Find all CELL/ID nodes within a TABLE node.
     */
    private NodeList findCellIds(Node tableNode) {
        try {
            return (NodeList) xpath.evaluate(".//ROW/CELL/ID", tableNode, XPathConstants.NODESET);
        } catch (XPathExpressionException e) {
            log.warn("XPath error finding cell IDs in table", e);
            return new EmptyNodeList();
        }
    }

    /**
     * Get an attribute value from a node.
     */
    private String getAttributeValue(Node node, String attributeName) {
        if (node.getAttributes() != null) {
            Node attr = node.getAttributes().getNamedItem(attributeName);
            if (attr != null) {
                return attr.getNodeValue();
            }
        }
        return "";
    }

    /**
     * Parse a string to BigDecimal safely.
     * Handles comma-separated decimals (French locale) by replacing comma with dot.
     */
    private BigDecimal parseBigDecimal(String value) {
        if (value == null || value.isBlank()) {
            return BigDecimal.ZERO;
        }
        try {
            // QuarkXPress may use comma as decimal separator (French locale)
            String normalized = value.replace(',', '.');
            return new BigDecimal(normalized);
        } catch (NumberFormatException e) {
            log.warn("Cannot parse BigDecimal from [{}]", value);
            return BigDecimal.ZERO;
        }
    }

    /**
     * Parse a string to int safely.
     */
    private int parseIntSafe(String value) {
        // Lenient int parse: strip trailing '*' page markers and ALL spaces, normalize the decimal comma,
        // parse leniently (decimals/signs OK), and return Integer.MIN_VALUE (NOT 0) for null/blank/unparseable
        // — so a genuine page 0 is distinguishable from a parse failure.
        // Findings #46 / #77 / #78.
        if (value == null) {
            return Integer.MIN_VALUE;
        }
        String s = value.replaceAll("\\*+$", "").replace(" ", "").replace(',', '.');
        if (s.isEmpty()) {
            return Integer.MIN_VALUE;
        }
        try {
            return new java.math.BigDecimal(s).toBigInteger().intValue();
        } catch (NumberFormatException e) {
            log.warn("Cannot parse int from [{}]", value);
            return Integer.MIN_VALUE;
        }
    }

    // ========================================================================
    // Empty NodeList implementation (for null-safe returns)
    // ========================================================================

    /**
     * Empty NodeList implementation for null-safe fallback.
     */
    private static class EmptyNodeList implements NodeList {
        @Override
        public Node item(int index) {
            return null;
        }

        @Override
        public int getLength() {
            return 0;
        }
    }
}
```

---

## Apply checklist
- [ ] `domain/xml/QxpXml.java`
- [ ] `mvn test` (no QxpXml test exists; confirm dependent tests — e.g. anchor/page paths — still pass)
