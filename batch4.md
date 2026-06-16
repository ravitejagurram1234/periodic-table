# EOS Quark — Batch 4 Changes (copy-paste)

**Batch 4 = Modify-XML serializer completeness.** `QxpsProjectSerializer` was lossy — it emitted only basic box/text and dropped ~20 element/attribute groups, so anything beyond a simple text box was under-serialized in the XML sent to QuarkXPress. This is now a **full, faithful port** of .NET `QXP_Project_Serializer` (every element, attribute, ordering and conditional matched).

**Now included (previously missing):**
- **Layout-level** boxes & tables (not just spreads).
- **Table** detail: COLUMNCOUNT/ROWCOUNT/COLOR/SHADE/OPACITY/ANCHOREDIN/AUTOFIT(+MAXLIMIT), ADDCELLS, COLSPEC/COLUMN, GRIDLINE, TABLEBREAK, table-level FRAME/GEOMETRY/SHADOW; full ROW & CELL attributes.
- **Text**: gutterWidth, interParagraphMax, firstBaseLineMin, offset, runTextAroundAllSides, textAlign(+withLine), flipText, **INSET**.
- **Story**: story-level RICHTEXT[] and LIST[]; **Paragraph**: parachar, merge, **TABSPEC/TAB, RULE, FORMAT** (+ KEEPLINESTOGETHER, DROPCAP).
- **RichText**: full character formatting incl. all OpenType (OT_*) attributes.
- **Picture**: skew, PICCOLOR, shade, opacity, flips, SUPRESSPICT, FULLRES, MASK.
- **Geometry**: move/grow/shrink element values, **LINESTYLE**, **SPLINESHAPE → CONTOURS → CONTOUR → VERTICES → VERTEX** (+ control points), full **RUNAROUND**.
- **Shadow** (skew/scale/blur/knockout/sync/runaround/multiply/inheritOpacity) and **Frame** (gapColor/gapShade/gapOpacity) full attributes.

> Intentional deviation: .NET `Add_Vertex` writes `SYMMVERTEX` twice (a copy-paste bug that would throw a duplicate-attribute error); here it is written once.

## How to apply
Replace the entire file with the block below (path relative to the `quark-engine` module root). Then `mvn -DskipTests compile` and `mvn test`.

## Checklist (1 file)
- [ ] `infra/interop/qxps/helper/QxpsProjectSerializer.java` — CHANGED

---

## 1. `src/main/java/com/socgen/sgs/api/quark/engine/infra/interop/qxps/helper/QxpsProjectSerializer.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.infra.interop.qxps.helper;

import com.socgen.sgs.api.quark.engine.integration.soap.generated.*;
import lombok.extern.slf4j.Slf4j;

import javax.xml.stream.XMLOutputFactory;
import javax.xml.stream.XMLStreamException;
import javax.xml.stream.XMLStreamWriter;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Serializes a SOAP Project (the Quark Modifier DOM) into XML for the QXPS HTTP "modify" command.
 * Uses StAX (XMLStreamWriter) for high-performance streaming XML generation.
 *
 * <p>Faithful, full port of .NET {@code QXP.Engine.Core.QXP_Project_Serializer} — every element,
 * attribute, ordering and conditional matches the original. Attributes/elements are written only
 * when set; {@code SUPPRESSOUTPUT} is omitted when "false" (the server default).
 *
 * <p>One intentional deviation from .NET: {@code Add_Vertex} writes the {@code SYMMVERTEX} attribute
 * twice (a copy-paste bug that would throw a duplicate-attribute error); here it is written once.
 */
@Slf4j
public final class QxpsProjectSerializer {

    private static final String DEF_FALSE_VALUE = "false";

    private QxpsProjectSerializer() {
    }

    /** Serialize Project to an XML string. */
    public static String toXml(Project project) {
        try {
            ByteArrayOutputStream os = new ByteArrayOutputStream();
            XMLOutputFactory factory = XMLOutputFactory.newInstance();
            XMLStreamWriter w = factory.createXMLStreamWriter(os, "UTF-8");

            w.writeStartDocument("UTF-8", "1.0");
            writeProject(w, project);
            w.writeEndDocument();
            w.close();

            return os.toString(StandardCharsets.UTF_8);
        } catch (XMLStreamException e) {
            throw new RuntimeException("Failed to serialize Project to XML", e);
        }
    }

    /** Serialize Project to UTF-8 bytes for HTTP POST. */
    public static byte[] toBytes(Project project) {
        return toXml(project).getBytes(StandardCharsets.UTF_8);
    }

    // ========================================================================
    // Project / Layout / Spread / Page / Box / ID
    // ========================================================================

    private static void writeProject(XMLStreamWriter w, Project project) throws XMLStreamException {
        if (project == null) return;
        w.writeStartElement("PROJECT");
        if (project.getLayouts() != null) {
            for (Layout layout : project.getLayouts()) {
                writeLayout(w, layout);
            }
        }
        w.writeEndElement();
    }

    private static void writeLayout(XMLStreamWriter w, Layout layout) throws XMLStreamException {
        if (layout == null) return;
        w.writeStartElement("LAYOUT");
        writeId(w, layout.getUID(), layout.getName());
        if (layout.getSpreads() != null) {
            for (Spread spread : layout.getSpreads()) {
                writeSpread(w, spread);
            }
        }
        if (layout.getBoxes() != null) {
            for (Box box : layout.getBoxes()) {
                writeBox(w, box);
            }
        }
        if (layout.getTables() != null) {
            for (Table table : layout.getTables()) {
                writeTable(w, table);
            }
        }
        w.writeEndElement();
    }

    private static void writeSpread(XMLStreamWriter w, Spread spread) throws XMLStreamException {
        if (spread == null) return;
        w.writeStartElement("SPREAD");
        writeAttr(w, "OPERATION", spread.getOperation());
        writeId(w, spread.getUID(), spread.getName());
        if (spread.getPages() != null) {
            for (Page page : spread.getPages()) {
                writePage(w, page);
            }
        }
        if (spread.getBoxes() != null) {
            for (Box box : spread.getBoxes()) {
                writeBox(w, box);
            }
        }
        if (spread.getTables() != null) {
            for (Table table : spread.getTables()) {
                writeTable(w, table);
            }
        }
        w.writeEndElement();
    }

    private static void writePage(XMLStreamWriter w, Page page) throws XMLStreamException {
        if (page == null) return;
        w.writeStartElement("PAGE");
        writeAttr(w, "OPERATION", page.getOperation());
        writeAttr(w, "MASTER", page.getMaster());
        writeAttr(w, "POSITION", page.getPosition());
        writeId(w, page.getUID(), page.getName());
        w.writeEndElement();
    }

    private static void writeBox(XMLStreamWriter w, Box box) throws XMLStreamException {
        if (box == null) return;
        w.writeStartElement("BOX");
        writeAttr(w, "OPERATION", box.getOperation());
        writeAttr(w, "BOXTYPE", box.getBoxType());
        writeAttr(w, "COLOR", box.getColor());
        writeAttr(w, "SHADE", box.getShade());
        writeAttr(w, "OPACITY", box.getOpacity());
        writeAttr(w, "ANCHOREDIN", box.getAnchoredIn());
        writeId(w, box.getUID(), box.getName());
        writeText(w, box.getText());
        writePicture(w, box.getPicture());
        writeGeometry(w, box.getGeometry());
        writeContent(w, box.getContent());
        writeShadow(w, box.getShadow());
        writeFrame(w, box.getFrame());
        w.writeEndElement();
    }

    private static void writeId(XMLStreamWriter w, String uid, String name) throws XMLStreamException {
        if ((uid == null || uid.isEmpty()) && (name == null || name.isEmpty())) return;
        w.writeStartElement("ID");
        writeAttr(w, "NAME", name);
        writeAttr(w, "UID", uid);
        w.writeEndElement();
    }

    // ========================================================================
    // Table
    // ========================================================================

    private static void writeTable(XMLStreamWriter w, Table table) throws XMLStreamException {
        if (table == null) return;
        w.writeStartElement("TABLE");
        writeAttr(w, "OPERATION", table.getOperation());
        writeAttr(w, "COLUMNCOUNT", table.getColumnCount());
        writeAttr(w, "ROWCOUNT", table.getRowCount());
        writeAttr(w, "MAINTAINGEOMETRY", table.getMaintainGeometry());
        writeAttr(w, "COLOR", table.getColor());
        writeAttr(w, "SHADE", table.getShade());
        writeAttr(w, "OPACITY", table.getOpacity());
        writeAttr(w, "ANCHOREDIN", table.getAnchoredIn());
        writeAttr(w, "AUTOFIT", table.getAutofit());
        writeAttr(w, "AUTOFITMAXLIMIT", table.getAutofitMaxLimit());
        writeId(w, table.getUID(), table.getName());
        if (table.getAddCells() != null) {
            for (AddCells ac : table.getAddCells()) {
                writeAddCells(w, ac);
            }
        }
        if (table.getDeleteCells() != null) {
            for (DeleteCells dc : table.getDeleteCells()) {
                writeDeleteCells(w, dc);
            }
        }
        writeColSpec(w, table.getColSpec());
        if (table.getRows() != null) {
            for (Row row : table.getRows()) {
                writeRow(w, row);
            }
        }
        writeTableBreak(w, table.getTableBreak());
        writeFrame(w, table.getFrame());
        writeGeometry(w, table.getGeometry());
        writeShadow(w, table.getShadow());
        w.writeEndElement();
    }

    private static void writeAddCells(XMLStreamWriter w, AddCells ac) throws XMLStreamException {
        if (ac == null) return;
        w.writeStartElement("ADDCELLS");
        writeAttr(w, "TYPE", ac.getType());
        writeAttr(w, "BASEINDEX", ac.getBaseIndex());
        writeAttr(w, "INSERTCOUNT", ac.getInsertCount());
        writeAttr(w, "INSERTPOSITION", ac.getInsertPosition());
        writeAttr(w, "KEEPATTRIBUTE", ac.getKeepAttribute());
        w.writeEndElement();
    }

    private static void writeDeleteCells(XMLStreamWriter w, DeleteCells dc) throws XMLStreamException {
        if (dc == null) return;
        w.writeStartElement("DELETECELLS");
        writeAttr(w, "TYPE", dc.getType());
        writeAttr(w, "BASEINDEX", dc.getBaseIndex());
        writeAttr(w, "DELETECOUNT", dc.getDeleteCount());
        w.writeEndElement();
    }

    private static void writeColSpec(XMLStreamWriter w, ColSpec colSpec) throws XMLStreamException {
        if (colSpec == null) return;
        w.writeStartElement("COLSPEC");
        if (colSpec.getColumns() != null) {
            for (Column column : colSpec.getColumns()) {
                writeColumn(w, column);
            }
        }
        w.writeEndElement();
    }

    private static void writeColumn(XMLStreamWriter w, Column column) throws XMLStreamException {
        if (column == null) return;
        w.writeStartElement("COLUMN");
        writeAttr(w, "COLUMNCOUNT", column.getColumnCount());
        writeAttr(w, "COLUMNWIDTH", column.getColumnWidth());
        writeAttr(w, "COLOR", column.getColor());
        writeAttr(w, "SHADE", column.getShade());
        writeAttr(w, "OPACITY", column.getOpacity());
        writeAttr(w, "MERGECOLSPAN", column.getMergeColSpan());
        writeAttr(w, "SPLIT", column.getSplit());
        writeAttr(w, "AUTOFIT", column.getAutofit());
        writeAttr(w, "AUTOFITMAXLIMIT", column.getAutofitMaxLimit());
        if (column.getGridLines() != null) {
            for (GridLine gl : column.getGridLines()) {
                writeGridLine(w, gl);
            }
        }
        w.writeEndElement();
    }

    private static void writeRow(XMLStreamWriter w, Row row) throws XMLStreamException {
        if (row == null) return;
        w.writeStartElement("ROW");
        writeAttr(w, "AUTOFIT", row.getAutofit());
        writeAttr(w, "AUTOFITMAXLIMIT", row.getAutofitMaxLimit());
        writeAttr(w, "COLOR", row.getColor());
        writeAttr(w, "MERGEROWSPAN", row.getMergeRowSpan());
        writeAttr(w, "OPACITY", row.getOpacity());
        writeAttr(w, "ROWCOUNT", row.getRowCount());
        writeAttr(w, "ROWHEIGHT", row.getRowHeight());
        writeAttr(w, "SHADE", row.getShade());
        writeAttr(w, "SPLIT", row.getSplit());
        if (row.getCells() != null) {
            for (Cell cell : row.getCells()) {
                writeCell(w, cell);
            }
        }
        if (row.getGridLines() != null) {
            for (GridLine gl : row.getGridLines()) {
                writeGridLine(w, gl);
            }
        }
        w.writeEndElement();
    }

    private static void writeCell(XMLStreamWriter w, Cell cell) throws XMLStreamException {
        if (cell == null) return;
        w.writeStartElement("CELL");
        writeAttr(w, "BOXTYPE", cell.getBoxType());
        writeAttr(w, "COLOR", cell.getColor());
        writeAttr(w, "COLUMNCOUNT", cell.getColumnCount());
        writeAttr(w, "MERGECOLSPAN", cell.getMergeColSpan());
        writeAttr(w, "MERGEROWSPAN", cell.getMergeRowSpan());
        writeAttr(w, "OPACITY", cell.getOpacity());
        writeAttr(w, "SHADE", cell.getShade());
        writeAttr(w, "SPLIT", cell.getSplit());
        writeContent(w, cell.getContent());
        writeText(w, cell.getText());
        writePicture(w, cell.getPicture());
        w.writeEndElement();
    }

    private static void writeGridLine(XMLStreamWriter w, GridLine gl) throws XMLStreamException {
        if (gl == null) return;
        w.writeStartElement("GRIDLINE");
        writeAttr(w, "STYLE", gl.getStyle());
        writeAttr(w, "WIDTH", gl.getWidth());
        writeAttr(w, "COLOR", gl.getColor());
        writeAttr(w, "SHADE", gl.getShade());
        writeAttr(w, "OPACITY", gl.getOpacity());
        writeAttr(w, "GAPCOLOR", gl.getGapColor());
        writeAttr(w, "GAPSHADE", gl.getGapShade());
        writeAttr(w, "GAPOPACITY", gl.getGapOpacity());
        w.writeEndElement();
    }

    private static void writeTableBreak(XMLStreamWriter w, TableBreak tableBreak) throws XMLStreamException {
        if (tableBreak == null) return;
        w.writeStartElement("TABLEBREAK");
        w.writeEndElement();
    }

    // ========================================================================
    // Text / Story / Paragraph / RichText / List
    // ========================================================================

    private static void writeText(XMLStreamWriter w, Text text) throws XMLStreamException {
        if (text == null) return;
        w.writeStartElement("TEXT");
        writeAttr(w, "ANGLE", text.getAngle());
        writeAttr(w, "SKEW", text.getSkew());
        writeAttr(w, "COLUMNS", text.getColumns());
        writeAttr(w, "GUTTERWIDTH", text.getGutterWidth());
        writeAttr(w, "FLIPVERTICAL", text.getFlipVertical());
        writeAttr(w, "FLIPHORIZONTAL", text.getFlipHorizontal());
        writeAttr(w, "VERTICALALIGNMENT", text.getVerticalAlignment());
        writeAttr(w, "INTERPARAGRAPHMAX", text.getInterParagraphMax());
        writeAttr(w, "FIRSTBASELINEMIN", text.getFirstBaseLineMin());
        writeAttr(w, "OFFSET", text.getOffset());
        writeAttr(w, "RUNTEXTAROUNDALLSIDES", text.getRunTextAroundAllSides());
        writeAttr(w, "TEXTORIENTATION", text.getTextOrientation());
        writeAttr(w, "TEXTALIGN", text.getTextAlign());
        writeAttr(w, "TEXTALIGNWITHLINE", text.getTextAlignWithLine());
        writeAttr(w, "FLIPTEXT", text.getFlipText());
        writeInset(w, text.getInset());
        writeStory(w, text.getStory());
        w.writeEndElement();
    }

    private static void writeInset(XMLStreamWriter w, Inset inset) throws XMLStreamException {
        if (inset == null) return;
        w.writeStartElement("INSET");
        writeAttr(w, "MULTIPLEINSETS", inset.getMultipleInsets());
        writeAttr(w, "TOP", inset.getTop());
        writeAttr(w, "BOTTOM", inset.getBottom());
        writeAttr(w, "RIGHT", inset.getRight());
        writeAttr(w, "LEFT", inset.getLeft());
        writeAttr(w, "ALLEDGES", inset.getAllEdges());
        w.writeEndElement();
    }

    private static void writeStory(XMLStreamWriter w, Story story) throws XMLStreamException {
        if (story == null) return;
        w.writeStartElement("STORY");
        writeAttr(w, "CLEAROLDTEXT", story.getClearOldText());
        writeAttr(w, "FITTEXTTOBOX", story.getFitTextToBox());
        writeAttr(w, "FILE", story.getFile());
        writeAttr(w, "CONVERTQUOTES", story.getConvertQuotes());
        writeAttr(w, "INCLUDESTYLESHEETS", story.getIncludeStylesheets());
        if (story.getParagraphs() != null) {
            for (Paragraph p : story.getParagraphs()) {
                writeParagraph(w, p);
            }
        }
        if (story.getRichText() != null) {
            for (RichText rt : story.getRichText()) {
                writeRichText(w, rt);
            }
        }
        if (story.getLists() != null) {
            for (List list : story.getLists()) {
                writeList(w, list);
            }
        }
        w.writeEndElement();
    }

    private static void writeList(XMLStreamWriter w, List list) throws XMLStreamException {
        if (list == null) return;
        w.writeStartElement("LIST");
        writeAttr(w, "OPERATION", list.getOperation());
        writeAttr(w, "LISTSTYLE", list.getListStyle());
        if (list.getParagraphs() != null) {
            for (Paragraph p : list.getParagraphs()) {
                writeParagraph(w, p);
            }
        }
        if (list.getRichText() != null) {
            for (RichText rt : list.getRichText()) {
                writeRichText(w, rt);
            }
        }
        w.writeEndElement();
    }

    private static void writeParagraph(XMLStreamWriter w, Paragraph paragraph) throws XMLStreamException {
        if (paragraph == null) return;
        w.writeStartElement("PARAGRAPH");
        writeAttr(w, "PARASTYLE", paragraph.getParaStyle());
        writeAttr(w, "PARACHAR", paragraph.getParachar());
        writeAttr(w, "MERGE", paragraph.getMerge());
        if (paragraph.getTabspecs() != null) {
            for (TabSpec ts : paragraph.getTabspecs()) {
                writeTabSpec(w, ts);
            }
        }
        if (paragraph.getRules() != null) {
            for (Rule rule : paragraph.getRules()) {
                writeRule(w, rule);
            }
        }
        writeFormat(w, paragraph.getFormat());
        if (paragraph.getRichText() != null) {
            for (RichText rt : paragraph.getRichText()) {
                writeRichText(w, rt);
            }
        }
        w.writeEndElement();
    }

    private static void writeTabSpec(XMLStreamWriter w, TabSpec tabSpec) throws XMLStreamException {
        if (tabSpec == null) return;
        w.writeStartElement("TABSPEC");
        if (tabSpec.getTabs() != null) {
            for (Tab tab : tabSpec.getTabs()) {
                writeTab(w, tab);
            }
        }
        w.writeEndElement();
    }

    private static void writeTab(XMLStreamWriter w, Tab tab) throws XMLStreamException {
        if (tab == null) return;
        w.writeStartElement("TAB");
        writeAttr(w, "POSITION", tab.getPosition());
        writeAttr(w, "FILL", tab.getFill());
        writeAttr(w, "ALIGNMENT", tab.getAlignment());
        writeAttr(w, "ALIGNON", tab.getAlignOn());
        writeAttr(w, "ENABLED", tab.getEnabled());
        w.writeEndElement();
    }

    private static void writeRule(XMLStreamWriter w, Rule rule) throws XMLStreamException {
        if (rule == null) return;
        w.writeStartElement("RULE");
        writeAttr(w, "ENABLED", rule.getEnabled());
        writeAttr(w, "POSITION", rule.getPosition());
        writeAttr(w, "LENGTH", rule.getLength());
        writeAttr(w, "LEFT", rule.getLeft());
        writeAttr(w, "RIGHT", rule.getRight());
        writeAttr(w, "OFFSET", rule.getOffset());
        writeAttr(w, "WIDTH", rule.getWidth());
        writeAttr(w, "COLOR", rule.getColor());
        writeAttr(w, "SHADE", rule.getShade());
        writeAttr(w, "OPACITY", rule.getOpacity());
        writeAttr(w, "STYLE", rule.getStyle());
        w.writeEndElement();
    }

    private static void writeFormat(XMLStreamWriter w, Format format) throws XMLStreamException {
        if (format == null) return;
        w.writeStartElement("FORMAT");
        writeAttr(w, "SPACEBEFORE", format.getSpaceBefore());
        writeAttr(w, "SPACEAFTER", format.getSpaceAfter());
        writeAttr(w, "LEFTINDENT", format.getLeftIndent());
        writeAttr(w, "RIGHTINDENT", format.getRightIndent());
        writeAttr(w, "FIRSTLINE", format.getFirstLine());
        writeAttr(w, "LEADING", format.getLeading());
        writeAttr(w, "ALIGNMENT", format.getAlignment());
        writeAttr(w, "HANDJ", format.getHAndJ());
        writeAttr(w, "KEEPWITHNEXT", format.getKeepWithNext());
        writeKeepLinesTogether(w, format.getKeepLinesTogether());
        writeDropCap(w, format.getDropCap());
        w.writeEndElement();
    }

    private static void writeKeepLinesTogether(XMLStreamWriter w, KeepLinesTogether klt) throws XMLStreamException {
        if (klt == null) return;
        w.writeStartElement("KEEPLINESTOGETHER");
        writeAttr(w, "ENABLED", klt.getEnabled());
        writeAttr(w, "ALLLINESINPARA", klt.getAllLinesInPara());
        writeAttr(w, "STARTLINE", klt.getStartLine());
        writeAttr(w, "ENDLINE", klt.getEndLine());
        w.writeEndElement();
    }

    private static void writeDropCap(XMLStreamWriter w, DropCap dropCap) throws XMLStreamException {
        if (dropCap == null) return;
        w.writeStartElement("DROPCAP");
        writeAttr(w, "CHARCOUNT", dropCap.getCharCount());
        writeAttr(w, "LINECOUNT", dropCap.getLineCount());
        w.writeEndElement();
    }

    private static void writeRichText(XMLStreamWriter w, RichText rt) throws XMLStreamException {
        if (rt == null) return;
        w.writeStartElement("RICHTEXT");
        writeAttr(w, "CHARSTYLE", rt.getCharStyle());
        writeAttr(w, "PLAIN", rt.getPlain());
        writeAttr(w, "MERGE", rt.getMerge());
        writeAttr(w, "BOLD", rt.getBold());
        writeAttr(w, "ITALIC", rt.getItalic());
        writeAttr(w, "FONT", rt.getFont());
        writeAttr(w, "SIZE", rt.getSize());
        writeAttr(w, "COLOR", rt.getColor());
        writeAttr(w, "SHADE", rt.getShade());
        writeAttr(w, "OPACITY", rt.getOpacity());
        writeAttr(w, "NONBREAKING", rt.getNonBreaking());
        writeAttr(w, "UNDERLINE", rt.getUnderline());
        writeAttr(w, "WORDUNDERLINE", rt.getWordUnderline());
        writeAttr(w, "SMALLCAPS", rt.getSmallCaps());
        writeAttr(w, "ALLCAPS", rt.getAllCaps());
        writeAttr(w, "SUPERSCRIPT", rt.getSuperScript());
        writeAttr(w, "SUBSCRIPT", rt.getSubScript());
        writeAttr(w, "SUPERIOR", rt.getSuperior());
        writeAttr(w, "OUTLINE", rt.getOutline());
        writeAttr(w, "SHADOW", rt.getShadow());
        writeAttr(w, "STRIKETHRU", rt.getStrikeThru());
        writeAttr(w, "BASELINESHIFT", rt.getBaselineShift());
        writeAttr(w, "HORIZONTALSCALE", rt.getHorizontalScale());
        writeAttr(w, "VERTICALSCALE", rt.getVerticalScale());
        writeAttr(w, "TRACKAMOUNT", rt.getTrackAmount());
        writeAttr(w, "KERNAMOUNT", rt.getKernAmount());
        writeAttr(w, "LIGATURES", rt.getLigatures());
        writeAttr(w, "OT_STANDARD_LIGATURES", rt.getOTStandardLigatures());
        writeAttr(w, "OT_DISCRETIONARY_LIGATURES", rt.getOTDiscretionaryLigatures());
        writeAttr(w, "OT_ORDINALS", rt.getOTOrdinals());
        writeAttr(w, "OT_TITLING_ALTERNATES", rt.getOTTitlingAlternates());
        writeAttr(w, "OT_ALL_SMALL_CAPS", rt.getOTAllSmallCaps());
        writeAttr(w, "OT_FRACTIONS", rt.getOTFractions());
        writeAttr(w, "OT_SWASHES", rt.getOTSwashes());
        writeAttr(w, "OT_SMALL_CAPS", rt.getOTSmallCaps());
        writeAttr(w, "OT_CONTEXTUAL_ALTERNATIVES", rt.getOTContextualAlternatives());
        writeAttr(w, "OT_TABULAR_FIGURES", rt.getOTTabularFigures());
        writeAttr(w, "OT_PROPORTIONAL_FIGURES", rt.getOTProportionalFigures());
        writeAttr(w, "OT_LINING_FIGURES", rt.getOTLiningFigures());
        // OT_NONE is intentionally not written (commented out in .NET).
        writeAttr(w, "OT_SUPERSCRIPT", rt.getOTSuperscript());
        writeAttr(w, "OT_SUBSCRIPT", rt.getOTSubscript());
        writeAttr(w, "OT_NUMERATOR", rt.getOTNumerator());
        writeAttr(w, "OT_DENOMINATOR", rt.getOTDenominator());
        writeAttr(w, "OT_OLDSTYLE_FIGURES", rt.getOTOldStyleFigures());
        writeAttr(w, "LANGUAGE", rt.getLanguage());
        if (rt.getValue() != null && !rt.getValue().isEmpty()) {
            w.writeCharacters(rt.getValue());
        }
        w.writeEndElement();
    }

    // ========================================================================
    // Picture
    // ========================================================================

    private static void writePicture(XMLStreamWriter w, Picture picture) throws XMLStreamException {
        if (picture == null) return;
        w.writeStartElement("PICTURE");
        writeAttr(w, "FIT", picture.getFit());
        writeAttr(w, "SCALEACROSS", picture.getScaleAcross());
        writeAttr(w, "SCALEDOWN", picture.getScaleDown());
        writeAttr(w, "OFFSETACROSS", picture.getOffsetAcross());
        writeAttr(w, "OFFSETDOWN", picture.getOffsetDown());
        writeAttr(w, "ANGLE", picture.getAngle());
        writeAttr(w, "SKEW", picture.getSkew());
        writeAttr(w, "PICCOLOR", picture.getPictureColor());
        writeAttr(w, "SHADE", picture.getShade());
        writeAttr(w, "OPACITY", picture.getOpacity());
        writeAttr(w, "FLIPVERTICAL", picture.getFlipVertical());
        writeAttr(w, "FLIPHORIZONTAL", picture.getFlipHorizontal());
        writeAttr(w, "SUPRESSPICT", picture.getSupressPicture());
        writeAttr(w, "FULLRES", picture.getFullResolution());
        writeAttr(w, "MASK", picture.getMask());
        w.writeEndElement();
    }

    // ========================================================================
    // Geometry (+ Runaround, LineStyle, SplineShape, Contours, Position)
    // ========================================================================

    private static void writeGeometry(XMLStreamWriter w, Geometry geometry) throws XMLStreamException {
        if (geometry == null) return;
        w.writeStartElement("GEOMETRY");
        writeAttr(w, "SHAPE", geometry.getShape());
        writeAttr(w, "PAGE", geometry.getPage());
        writeAttr(w, "ANGLE", geometry.getAngle());
        writeAttr(w, "LAYER", geometry.getLayer());
        writePosition(w, geometry.getPosition());
        writeElem(w, "MOVEUP", geometry.getMoveUp());
        writeElem(w, "MOVEDOWN", geometry.getMoveDown());
        writeElem(w, "MOVELEFT", geometry.getMoveLeft());
        writeElem(w, "MOVERIGHT", geometry.getMoveRight());
        writeElem(w, "GROWACROSS", geometry.getGrowAcross());
        writeElem(w, "GROWDOWN", geometry.getGrowDown());
        writeElem(w, "SHRINKACROSS", geometry.getShrinkAcross());
        writeElem(w, "SHRINKDOWN", geometry.getShrinkDown());
        writeElem(w, "ALLOWBOXONTOPASTEBOARD", geometry.getAllowBoxOnToPasteboard());
        writeElem(w, "ALLOWBOXOFFPAGE", geometry.getAllowBoxOffPage());
        writeElem(w, "STACKINGORDER", geometry.getStackingOrder());
        // SUPPRESSOUTPUT is omitted when "false" (the server default).
        writeElemSkipFalse(w, "SUPPRESSOUTPUT", geometry.getSuppressOutput());
        writeRunaround(w, geometry.getRunaround());
        writeLineStyle(w, geometry.getLinestyle());
        writeSplineShape(w, geometry.getSplineShape());
        w.writeEndElement();
    }

    private static void writeRunaround(XMLStreamWriter w, Runaround ra) throws XMLStreamException {
        if (ra == null) return;
        w.writeStartElement("RUNAROUND");
        writeAttr(w, "TYPE", ra.getType());
        writeAttr(w, "TOP", ra.getTop());
        writeAttr(w, "RIGHT", ra.getRight());
        writeAttr(w, "LEFT", ra.getLeft());
        writeAttr(w, "BOTTOM", ra.getBottom());
        writeAttr(w, "PATHNAME", ra.getPathName());
        writeAttr(w, "OUTSET", ra.getOutset());
        writeAttr(w, "NOISE", ra.getNoise());
        writeAttr(w, "THRESHOLD", ra.getThreshold());
        writeAttr(w, "SMOOTHNESS", ra.getSmoothness());
        writeAttr(w, "OUTSIDEONLY", ra.getOutsideOnly());
        writeAttr(w, "RESTRICTTOBOX", ra.getRestrictToBox());
        writeAttr(w, "INVERT", ra.getInvert());
        w.writeEndElement();
    }

    private static void writeLineStyle(XMLStreamWriter w, LineStyle lineStyle) throws XMLStreamException {
        if (lineStyle == null) return;
        w.writeStartElement("LINESTYLE");
        writeAttr(w, "ARROWHEADS", lineStyle.getArrowHeads());
        w.writeEndElement();
    }

    private static void writeSplineShape(XMLStreamWriter w, SplineShape ss) throws XMLStreamException {
        if (ss == null) return;
        w.writeStartElement("SPLINESHAPE");
        writeAttr(w, "RECTSHAPE", ss.getRectShape());
        writeAttr(w, "INVERTEDSHAPE", ss.getInvertedShape());
        writeAttr(w, "HASSPLINES", ss.getHasSplines());
        writeAttr(w, "HASHOLES", ss.getHasHoles());
        writeAttr(w, "NEWFORMAT", ss.getNewFormat());
        writeAttr(w, "MORETHANONETOPLEVELCONTOUR", ss.getMoreThanOneTopLevelContour());
        writeAttr(w, "CLOSEDSHAPE", ss.getClosedShape());
        writeAttr(w, "WELLFORMED", ss.getWellformed());
        writeAttr(w, "TAGSALLOCATED", ss.getTagsAllocated());
        writeAttr(w, "INCOMPLETE", ss.getIncomplete());
        writeAttr(w, "VERTSELECTED", ss.getVertSelected());
        writeContours(w, ss.getContours());
        w.writeEndElement();
    }

    private static void writeContours(XMLStreamWriter w, Contours contours) throws XMLStreamException {
        if (contours == null) return;
        w.writeStartElement("CONTOURS");
        if (contours.getContours() != null) {
            for (Contour c : contours.getContours()) {
                writeContour(w, c);
            }
        }
        w.writeEndElement();
    }

    private static void writeContour(XMLStreamWriter w, Contour contour) throws XMLStreamException {
        if (contour == null) return;
        w.writeStartElement("CONTOUR");
        writeAttr(w, "CURVEDEDGES", contour.getCurvedEdges());
        writeAttr(w, "RECTCONTOUR", contour.getRectContour());
        writeAttr(w, "INVERTEDCONTOUR", contour.getInvertedContour());
        writeAttr(w, "TOPLEVEL", contour.getTopLevel());
        writeAttr(w, "SELFINTERSECTED", contour.getSelfIntersected());
        writeAttr(w, "POLYCONTOUR", contour.getPolyContour());
        writeAttr(w, "VERTEXTAGEXISTS", contour.getVertexTagExists());
        writeVertices(w, contour.getVertices());
        w.writeEndElement();
    }

    private static void writeVertices(XMLStreamWriter w, Vertices vertices) throws XMLStreamException {
        if (vertices == null) return;
        w.writeStartElement("VERTICES");
        if (vertices.getVertices() != null) {
            for (Vertex v : vertices.getVertices()) {
                writeVertex(w, v);
            }
        }
        w.writeEndElement();
    }

    private static void writeVertex(XMLStreamWriter w, Vertex vertex) throws XMLStreamException {
        if (vertex == null) return;
        w.writeStartElement("VERTEX");
        writeAttr(w, "SMOOTHVERTEX", vertex.getSmoothVertex());
        writeAttr(w, "STRAIGHTEDGE", vertex.getStraightEdge());
        // .NET writes SYMMVERTEX twice (a bug that would throw a duplicate-attribute error); written once here.
        writeAttr(w, "SYMMVERTEX", vertex.getSymmVertex());
        writeAttr(w, "CUSPVERTEX", vertex.getCuspVertex());
        writeAttr(w, "TWISTED", vertex.getTwisted());
        writeAttr(w, "VERTEXSELECTED", vertex.getVertexSelected());
        writeLeftControlPoint(w, vertex.getLeftControlPoint());
        writeVertexPoint(w, vertex.getVertexPoint());
        writeRightControlPoint(w, vertex.getRightControlPoint());
        w.writeEndElement();
    }

    private static void writeLeftControlPoint(XMLStreamWriter w, LeftControlPoint p) throws XMLStreamException {
        if (p == null) return;
        w.writeStartElement("LEFTCONTROLPOINT");
        writeAttr(w, "X", p.getX());
        writeAttr(w, "Y", p.getY());
        w.writeEndElement();
    }

    private static void writeRightControlPoint(XMLStreamWriter w, RightControlPoint p) throws XMLStreamException {
        if (p == null) return;
        w.writeStartElement("RIGHTCONTROLPOINT");
        writeAttr(w, "X", p.getX());
        writeAttr(w, "Y", p.getY());
        w.writeEndElement();
    }

    private static void writeVertexPoint(XMLStreamWriter w, VertexPoint p) throws XMLStreamException {
        if (p == null) return;
        w.writeStartElement("VERTEXPOINT");
        writeAttr(w, "X", p.getX());
        writeAttr(w, "Y", p.getY());
        writeAttr(w, "TAG", p.getTag());
        w.writeEndElement();
    }

    private static void writePosition(XMLStreamWriter w, Position pos) throws XMLStreamException {
        if (pos == null) return;
        w.writeStartElement("POSITION");
        writeElem(w, "TOP", pos.getTop());
        writeElem(w, "LEFT", pos.getLeft());
        writeElem(w, "BOTTOM", pos.getBottom());
        writeElem(w, "RIGHT", pos.getRight());
        w.writeEndElement();
    }

    // ========================================================================
    // Content / Shadow / Frame
    // ========================================================================

    private static void writeContent(XMLStreamWriter w, Content content) throws XMLStreamException {
        if (content == null) return;
        w.writeStartElement("CONTENT");
        writeAttr(w, "CONVERTQUOTES", content.getConvertQuotes());
        writeAttr(w, "INCLUDESTYLESHEETS", content.getIncludeStyleSheets());
        writeAttr(w, "FONTNAME", content.getFontName());
        if (content.getValue() != null && !content.getValue().isEmpty()) {
            w.writeCharacters(content.getValue());
        }
        w.writeEndElement();
    }

    private static void writeShadow(XMLStreamWriter w, Shadow shadow) throws XMLStreamException {
        if (shadow == null) return;
        w.writeStartElement("SHADOW");
        writeAttr(w, "COLOR", shadow.getColor());
        writeAttr(w, "SHADE", shadow.getShade());
        writeAttr(w, "OPACITY", shadow.getOpacity());
        writeAttr(w, "ANGLE", shadow.getAngle());
        writeAttr(w, "DISTANCE", shadow.getDistance());
        writeAttr(w, "SKEW", shadow.getSkew());
        writeAttr(w, "SCALE", shadow.getScale());
        writeAttr(w, "BLUR", shadow.getBlur());
        writeAttr(w, "KNOCKOUTSHADOW", shadow.getKnockoutShadow());
        writeAttr(w, "SYNCHRONIZEANGLE", shadow.getSynchronizeAngle());
        writeAttr(w, "RUNAROUNDSHADOW", shadow.getRunaroundShadow());
        writeAttr(w, "MULTIPLYSHADOW", shadow.getMultiplyShadow());
        writeAttr(w, "INHERITOPACITY", shadow.getInheritOpacity());
        w.writeEndElement();
    }

    private static void writeFrame(XMLStreamWriter w, Frame frame) throws XMLStreamException {
        if (frame == null) return;
        w.writeStartElement("FRAME");
        writeAttr(w, "STYLE", frame.getStyle());
        writeAttr(w, "WIDTH", frame.getWidth());
        writeAttr(w, "COLOR", frame.getColor());
        writeAttr(w, "SHADE", frame.getShade());
        writeAttr(w, "OPACITY", frame.getOpacity());
        writeAttr(w, "GAPCOLOR", frame.getGapColor());
        writeAttr(w, "GAPSHADE", frame.getGapShade());
        writeAttr(w, "GAPOPACITY", frame.getGapOpacity());
        w.writeEndElement();
    }

    // ========================================================================
    // Utility
    // ========================================================================

    /** Writes an attribute only when the value is set (non-null, non-empty). */
    private static void writeAttr(XMLStreamWriter w, String name, String value) throws XMLStreamException {
        if (value != null && !value.isEmpty()) {
            w.writeAttribute(name, value);
        }
    }

    /** Writes a simple element with text content only when the value is set. */
    private static void writeElem(XMLStreamWriter w, String name, String value) throws XMLStreamException {
        if (value != null && !value.isEmpty()) {
            w.writeStartElement(name);
            w.writeCharacters(value);
            w.writeEndElement();
        }
    }

    /** Writes a simple element, but skips it when the value is missing or equals "false". */
    private static void writeElemSkipFalse(XMLStreamWriter w, String name, String value) throws XMLStreamException {
        if (value != null && !value.isEmpty() && !DEF_FALSE_VALUE.equals(value)) {
            w.writeStartElement(name);
            w.writeCharacters(value);
            w.writeEndElement();
        }
    }
}
```

