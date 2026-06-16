# EOS Quark — Batch 5 Changes (copy-paste)

**Batch 5 = TElement_Helper geometry + true deep clone.** Dynamic-report boxes/groups were positioned wrong and group clones were broken. Restores .NET parity.

**What changed & why (1 file: `TElementHelper.java`):**
- **TRUE deep clone** of the SOAP bean graph via in-memory object serialization (mirrors .NET `Clone<T>` which uses XML serialization). The old manual copy shared nested objects (story/frame/shadow) and `cloneTGroup` produced a group with **no boxes** — both fixed. Updating a clone no longer corrupts the shared template.
- **`Update_Position(TBox)`** implemented (was a `// would go here` stub): sets box position from the cell zone (left/top, right=left+width, bottom=top+height) and `BRINGTOFRONT` for absolute boxes.
- **`Update_Position(TGroup)`** implemented: relative shift of every group box by (zone.top − group.top, zone.left − group.left).
- **`Update_Name_Value(TGroup)`** implemented: per-box name/value by `C_<index>_` data-index, else `Rename_Bloc` (clear UID + unique name); group takes first box name.
- **`getBloc`** now clones AND updates both TBox and TGroup (the group path previously skipped the update entirely).
- Invalid group box/geometry now **throws** (caught by the 3-pass loop → task in error), matching .NET `Raise_Exception`.

> Parity-exception (approved): clone uses **Java native serialization** instead of .NET XML serialization — identical deep-clone result, different mechanism. All cloned beans are Serializable; we only ever deserialize bytes we just serialized in-memory (a SAST scan may still flag `ObjectInputStream` — safe to justify). No name-keyed serialization cache (perf optimization) is used; output is identical, slightly more CPU per clone.
> Not included: `Get_Bloc_AndMove`/`Get_Bloc_AndCreate` have NO callers in the current Java code, so they were intentionally omitted (would be dead code depending on the still-stubbed `getBlocInfo`).

## How to apply
Replace the entire file with the block below (path relative to the `quark-engine` module root). Then `mvn -DskipTests compile` and `mvn test`.

## Checklist (1 file)
- [ ] `domain/helper/TElementHelper.java` — CHANGED

---

## 1. `src/main/java/com/socgen/sgs/api/quark/engine/domain/helper/TElementHelper.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.domain.helper;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocGroup;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBlocInfo;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DCell;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DZone;
import com.socgen.sgs.api.quark.engine.domain.element.TBox;
import com.socgen.sgs.api.quark.engine.domain.element.TElement;
import com.socgen.sgs.api.quark.engine.domain.element.TGroup;
import com.socgen.sgs.api.quark.engine.domain.element.TTable;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.enums.StaticTElementNameEnum;
import com.socgen.sgs.api.quark.engine.enums.TBoxTypeEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Content;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Geometry;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Paragraph;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Picture;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Position;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Row;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Cell;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Runaround;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Story;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Table;
import lombok.extern.slf4j.Slf4j;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.math.BigDecimal;
import java.util.EnumMap;
import java.util.Map;
import java.util.UUID;

/**
 * Helper for creating, cloning, and manipulating TElements during bloc generation.
 * Maintains a static cache of pre-built template elements (IMG, PDF, DOC, ...) that are
 * cloned and customized for each task/cell.
 *
 * <p>Cloning is a TRUE deep clone of the underlying SOAP bean graph (via in-memory object
 * serialization), so updating a clone's position/name/value never affects the shared template
 * or other clones. This mirrors .NET {@code TElement_Helper.Clone&lt;T&gt;} (which uses XML
 * serialization); the result is identical, only the mechanism differs.
 *
 * Cross-reference: QXP.Engine.Core.TElement_Helper
 */
@Slf4j
public final class TElementHelper {

    private static final int NEW_BLOC_NAME_SIZE = 29;

    /** Prefix for data-bearing boxes inside groups (e.g., "C_0_GroupBox1"). */
    public static final String DATA_BLOC_PREFIX = "C_";

    /** z-order value forcing an absolute box in front of relative ones. .NET StackingOrder.BRINGTOFRONT. */
    private static final String STACKING_BRING_TO_FRONT = "BRINGTOFRONT";

    private static final Map<StaticTElementNameEnum, TElement> STATIC_ELEMENTS =
            new EnumMap<>(StaticTElementNameEnum.class);

    static {
        try {
            loadStaticElements();
        } catch (Exception e) {
            log.error("Unable to load StaticElements", e);
        }
    }

    private TElementHelper() {
    }

    // ========================================================================
    // Public API — Element retrieval
    // ========================================================================

    /**
     * Get a cloned copy of a static TElement with a new name.
     * Cross-reference: .NET TElement_Helper.Get_TElement(Static_TElement_Name, newName).
     */
    public static TElement getTElement(StaticTElementNameEnum tElementName, String newName) {
        TElement defaultElement = getDefaultTElement(tElementName);
        if (defaultElement == null) {
            log.warn("Static TElement not found for [{}]", tElementName);
            return null;
        }

        if (defaultElement instanceof TBox) {
            TBox cloned = cloneTBox((TBox) defaultElement);
            cloned.setName(newName);
            cloned.getSrcBox().setName(newName);
            if (cloned.getSrcExtraBox() != null) {
                cloned.getSrcExtraBox().setName(newName);
            }
            return cloned;
        } else if (defaultElement instanceof TGroup) {
            TGroup cloned = cloneTGroup((TGroup) defaultElement);
            cloned.setName(newName);
            return cloned;
        } else if (defaultElement instanceof TTable) {
            TTable cloned = cloneTTable((TTable) defaultElement);
            cloned.setName(newName);
            return cloned;
        }

        return null;
    }

    // ========================================================================
    // Public API — Bloc creation from DCell
    // Cross-reference: .NET TElement_Helper.Get_Bloc(DCell, Task_Dynamique)
    // ========================================================================

    /** Build a bloc (BlocBox or BlocGroup) from a dynamic-report cell. */
    public static BlocBase getBloc(DCell cell, TaskDynamique task) {
        if (cell.getTElement() instanceof TBox) {
            TBox tBox = cloneTBox((TBox) cell.getTElement());
            return updateAndGetBlocBox(tBox, cell, task);
        } else if (cell.getTElement() instanceof TGroup) {
            TGroup tGroup = cloneTGroup((TGroup) cell.getTElement());
            return updateAndGetBlocGroup(tGroup, cell, task);
        }
        return null;
    }

    /**
     * Build a MOVE bloc to reposition an existing anchor onto a new page.
     * Cross-reference: .NET TElement_Helper.Get_Move_Anchor().
     */
    public static BlocBox getMoveAnchor(TaskBase task, DBlocInfo anchor, int newRelativePage) {
        TElement tElement = getTElement(StaticTElementNameEnum.MOVE_BLOC, anchor.getName());
        if (!(tElement instanceof TBox)) {
            log.warn("Cannot get MOVE_BLOC template for anchor [{}]", anchor.getName());
            return null;
        }

        TBox tBox = (TBox) tElement;
        Box box = tBox.getSrcBox();
        if (box.getGeometry() != null && box.getGeometry().getPosition() != null) {
            box.getGeometry().getPosition().setLeft(anchor.getLeft().toPlainString());
            box.getGeometry().getPosition().setTop(anchor.getTop().toPlainString());
            box.getGeometry().getPosition().setRight(anchor.getRight().toPlainString());
            box.getGeometry().getPosition().setBottom(anchor.getBottom().toPlainString());
        }
        box.setUID(anchor.getUid());

        BlocBox bloc = new BlocBox(task, tBox.getSrcBox().getName(), tBox.getSrcBox(), tBox.getSrcExtraBox());
        bloc.setAction(BlocActionEnum.MOVE);
        bloc.setRelativePage(newRelativePage);
        bloc.setPagination(true);
        return bloc;
    }

    // ========================================================================
    // Public API — Style/Value transfer (QXP_Data STYLE mode)
    // ========================================================================

    /** Copy style+value from a source TBox into a fresh destination TBox. */
    public static TBox getNewTBoxStyleValueFromTBox(TBox srcTBox, String newName) {
        TElement destElement = getTElement(StaticTElementNameEnum.EMPTY_BLOC, newName);
        if (!(destElement instanceof TBox)) {
            log.warn("Cannot create destination TBox for style transfer to [{}]", newName);
            return null;
        }

        TBox destTBox = (TBox) destElement;
        Box srcBox = srcTBox.getSrcBox();
        Box destBox = destTBox.getSrcBox();

        switch (srcTBox.getType()) {
            case CT_TEXT:
                destBox.setBoxType(TBoxTypeEnum.CT_TEXT.name());
                if (srcBox.getText() != null && srcBox.getText().getStory() != null) {
                    destBox.setText(srcBox.getText());
                    destBox.getText().getStory().setClearOldText("true");
                    // Remove linkedBoxes — destination may have different linking
                    destBox.getText().getStory().setLinkedBoxes(null);
                }
                break;
            case CT_PICT:
                destBox.setBoxType(TBoxTypeEnum.CT_PICT.name());
                destBox.setPicture(srcBox.getPicture());
                destBox.setContent(srcBox.getContent());
                break;
            default:
                break;
        }
        return destTBox;
    }

    /** Copy style+value from a source TTable into a fresh destination TTable. */
    public static TTable getNewTTableStyleValueFromTTable(TTable srcTTable, String newName) {
        TElement destElement = getTElement(StaticTElementNameEnum.EMPTY_TABLE, newName);
        if (!(destElement instanceof TTable)) {
            log.warn("Cannot create destination TTable for style transfer to [{}]", newName);
            return null;
        }

        TTable destTTable = (TTable) destElement;
        Table srcTable = srcTTable.getSrcTable();

        destTTable.getSrcTable().setMaintainGeometry("false");

        if (srcTable.getRows() != null) {
            destTTable.getSrcTable().setRows(srcTable.getRows());
            for (Row row : destTTable.getSrcTable().getRows()) {
                if (row == null || row.getCells() == null) {
                    continue;
                }
                for (Cell cell : row.getCells()) {
                    if (cell != null && cell.getText() != null && cell.getText().getStory() != null) {
                        cell.getText().getStory().setClearOldText("true");
                    }
                }
            }
        }
        return destTTable;
    }

    // ========================================================================
    // Public API — name/value + naming helpers
    // ========================================================================

    /** Update a TBox's box name and text value. Cross-reference: .NET Update_Name_Value(TBox,...). */
    public static void updateNameValue(TBox tBox, String newName, String newValue) {
        Box srcBox = tBox.getSrcBox();
        if (srcBox == null) {
            throw new IllegalStateException("SrcBox is null for TBox update with name [" + newName + "]");
        }
        if (srcBox.getText() != null && srcBox.getText().getStory() != null) {
            Story story = srcBox.getText().getStory();
            Paragraph[] paragraphs = story.getParagraphs();
            if (paragraphs == null || paragraphs.length == 0
                    || paragraphs[0].getRichText() == null || paragraphs[0].getRichText().length == 0) {
                story.setParagraphs(createWarningParagraph());
            }
            story.getParagraphs()[0].getRichText()[0].setValue(newValue);
        }
        srcBox.setName(newName);
        tBox.setName(newName);
    }

    /** Generate a unique 29-char bloc name. Cross-reference: .NET NewBlocName(). */
    public static String newBlocName() {
        String uuid = UUID.randomUUID().toString().replace("-", "");
        return uuid.length() > NEW_BLOC_NAME_SIZE ? uuid.substring(0, NEW_BLOC_NAME_SIZE) : uuid;
    }

    /** Parse the data index from a box name "C_X_..." (e.g. "C_0_Group1" → 0); -1 if not parseable. */
    public static int getIndexBox(String boxName) {
        if (boxName == null || boxName.length() < 5) {
            return -1;
        }
        String sub = boxName.substring(2);
        int underscoreIdx = sub.indexOf('_');
        if (underscoreIdx <= 0) {
            return -1;
        }
        try {
            return Integer.parseInt(sub.substring(0, underscoreIdx));
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    /** A bold-red default paragraph, used when a box has no paragraph structure. */
    public static Paragraph[] createWarningParagraph() {
        Paragraph paragraph = new Paragraph();
        com.socgen.sgs.api.quark.engine.integration.soap.generated.RichText richText =
                new com.socgen.sgs.api.quark.engine.integration.soap.generated.RichText();
        richText.setBold("true");
        richText.setColor("Rouge");
        paragraph.setRichText(new com.socgen.sgs.api.quark.engine.integration.soap.generated.RichText[]{richText});
        return new Paragraph[]{paragraph};
    }

    // ========================================================================
    // Private — TBox update + bloc build
    // ========================================================================

    /** Cross-reference: .NET Update_TElement(TBox, DCell). */
    private static void updateTElement(TBox tBox, DCell cell) {
        // 1 - name + value (a single-box cell must carry exactly one name)
        if (cell.getNewNames().size() == 1) {
            updateNameValue(tBox, cell.getNewNames().get(0), cell.getValues().get(0));
        } else {
            throw new IllegalStateException(
                    "TElement [" + cell.getTElement().getName() + "] needs exactly one name");
        }
        // 2 - position
        updatePosition(tBox, cell);
    }

    /** Cross-reference: .NET Update_Position(TBox, DCell). */
    private static void updatePosition(TBox tBox, DCell cell) {
        Box srcBox = tBox.getSrcBox();
        if (srcBox == null) {
            return;
        }
        if (srcBox.getGeometry() == null) {
            srcBox.setGeometry(new Geometry());
        }
        if (srcBox.getGeometry().getPosition() == null) {
            srcBox.getGeometry().setPosition(new Position());
        }
        // An absolute box must sit in front of the relative ones.
        if (cell.getTemplate().isAbsolute()) {
            srcBox.getGeometry().setStackingOrder(STACKING_BRING_TO_FRONT);
        }
        DZone zone = cell.getInfo().getZone();
        Position pos = srcBox.getGeometry().getPosition();
        pos.setLeft(zone.getLeft().toPlainString());
        pos.setTop(zone.getTop().toPlainString());
        pos.setRight(zone.getLeft().add(zone.getWidth()).toPlainString());
        pos.setBottom(zone.getTop().add(zone.getHeight()).toPlainString());
    }

    /** Cross-reference: .NET Update_And_Get_Bloc_Box(TBox, DCell, Task_Dynamique). */
    private static BlocBox updateAndGetBlocBox(TBox tBox, DCell cell, TaskDynamique task) {
        updateTElement(tBox, cell);
        BlocBox blocBox = new BlocBox(task, tBox.getName(), tBox.getSrcBox(), tBox.getSrcExtraBox());
        blocBox.setAction(BlocActionEnum.CREATE);
        blocBox.setRelativePage(cell.getInfo().getPage() - 1); // relative pages are 0-indexed
        return blocBox;
    }

    // ========================================================================
    // Private — TGroup update + bloc build
    // ========================================================================

    /** Cross-reference: .NET Update_TElement(TGroup, DCell). */
    private static void updateTElement(TGroup tGroup, DCell cell) {
        // 1 - names + values across the group's boxes
        if (!cell.getNewNames().isEmpty()) {
            try {
                updateNameValue(tGroup,
                        cell.getNewNames().toArray(new String[0]),
                        cell.getValues().toArray(new String[0]));
            } catch (Exception ex) {
                throw new IllegalStateException(
                        "Failed to update names/values for group [" + cell.getTElement().getName() + "]", ex);
            }
        } else {
            throw new IllegalStateException(
                    "TElement [" + cell.getTElement().getName() + "] needs at least one name");
        }
        // 2 - position (relative shift of all boxes)
        updatePosition(tGroup, cell);
    }

    /** Cross-reference: .NET Update_Name_Value(TGroup, names[], values[]). */
    private static void updateNameValue(TGroup tGroup, String[] newNames, String[] newValues) {
        if (tGroup.getSrcBoxes() != null) {
            for (Box box : tGroup.getSrcBoxes()) {
                if (box == null) {
                    continue;
                }
                // only CT_TEXT/CT_PICT boxes carry data — not CT_NONE
                if (!TBoxTypeEnum.CT_NONE.name().equals(box.getBoxType())) {
                    String boxName = box.getName();
                    if (boxName != null && boxName.startsWith(DATA_BLOC_PREFIX)) {
                        int index = getIndexBox(boxName);
                        if (index >= 0) {
                            if (index < newNames.length) {
                                box.setName(newNames[index]);
                                if (box.getText() != null && box.getText().getStory() != null) {
                                    Story story = box.getText().getStory();
                                    Paragraph[] paras = story.getParagraphs();
                                    if (paras == null || paras.length == 0
                                            || paras[0].getRichText() == null || paras[0].getRichText().length == 0) {
                                        story.setParagraphs(createWarningParagraph());
                                    }
                                    story.getParagraphs()[0].getRichText()[0].setValue(newValues[index]);
                                } else {
                                    throw new IllegalStateException("Invalid box structure for [" + boxName + "]");
                                }
                            } else {
                                // more boxes than names → just rename so the bloc stays unique
                                renameBloc(box);
                            }
                        } else {
                            throw new IllegalStateException("Invalid box (no index in name) [" + boxName + "]");
                        }
                    } else {
                        renameBloc(box);
                    }
                } else {
                    renameBloc(box);
                }
            }
        }
        // the group takes the name of its first box
        if (newNames.length > 0) {
            tGroup.setName(newNames[0]);
        }
    }

    /** Cross-reference: .NET Update_Position(TGroup, DCell) — relative shift, no scaling. */
    private static void updatePosition(TGroup tGroup, DCell cell) {
        DZone zone = cell.getInfo().getZone();
        BigDecimal relativeTop = zone.getTop().subtract(tGroup.getTop());
        BigDecimal relativeLeft = zone.getLeft().subtract(tGroup.getLeft());

        if (tGroup.getSrcBoxes() == null) {
            return;
        }
        for (Box box : tGroup.getSrcBoxes()) {
            if (box != null && box.getGeometry() != null && box.getGeometry().getPosition() != null) {
                if (cell.getTemplate().isAbsolute()) {
                    box.getGeometry().setStackingOrder(STACKING_BRING_TO_FRONT);
                }
                Position p = box.getGeometry().getPosition();
                p.setLeft(parseDecimal(p.getLeft()).add(relativeLeft).toPlainString());
                p.setTop(parseDecimal(p.getTop()).add(relativeTop).toPlainString());
                p.setRight(parseDecimal(p.getRight()).add(relativeLeft).toPlainString());
                p.setBottom(parseDecimal(p.getBottom()).add(relativeTop).toPlainString());
            } else {
                throw new IllegalStateException(
                        "Invalid box/group or geometry in group [" + tGroup.getName() + "]");
            }
        }
    }

    /** Rename a box sequentially (clear UID + unique name) so clones don't collide. .NET Rename_Bloc(). */
    private static void renameBloc(Box box) {
        box.setUID("");
        box.setName(newBlocName());
    }

    /** Cross-reference: .NET Update_And_Get_Bloc_Group(TGroup, DCell, Task_Dynamique). */
    private static BlocGroup updateAndGetBlocGroup(TGroup tGroup, DCell cell, TaskDynamique task) {
        updateTElement(tGroup, cell);
        BlocGroup blocGroup = new BlocGroup(task, tGroup.getName(), tGroup.getSrcBoxes());
        blocGroup.setAction(BlocActionEnum.CREATE);
        blocGroup.setRelativePage(cell.getInfo().getPage() - 1); // relative pages are 0-indexed
        return blocGroup;
    }

    // ========================================================================
    // Private — Cloning (TRUE deep clone of the SOAP bean graph)
    // Cross-reference: .NET TElement_Helper.Clone<T> (serialize/deserialize deep clone)
    // ========================================================================

    private static TBox cloneTBox(TBox source) {
        Box clonedBox = deepClone(source.getSrcBox());
        Box clonedExtra = deepClone(source.getSrcExtraBox());
        TBox cloned = clonedExtra != null ? new TBox(clonedBox, clonedExtra) : new TBox(clonedBox);
        copyTElementGeometry(source, cloned);
        cloned.setType(source.getType());
        cloned.setPage(source.getPage());
        cloned.setName(source.getName());
        return cloned;
    }

    private static TGroup cloneTGroup(TGroup source) {
        TGroup cloned = new TGroup();
        cloned.setSrcGroup(deepClone(source.getSrcGroup()));
        cloned.setSrcBoxes(deepClone(source.getSrcBoxes()));
        cloned.setPage(source.getPage());
        copyTElementGeometry(source, cloned);
        cloned.setName(source.getName());
        return cloned;
    }

    private static TTable cloneTTable(TTable source) {
        Table clonedTable = deepClone(source.getSrcTable());
        TTable cloned = new TTable(clonedTable != null ? clonedTable : new Table());
        copyTElementGeometry(source, cloned);
        cloned.setName(source.getName());
        return cloned;
    }

    /** Carry the already-computed wrapper geometry onto the clone (used as base for relative group shifts). */
    private static void copyTElementGeometry(TElement source, TElement target) {
        target.setLeft(source.getLeft());
        target.setTop(source.getTop());
        target.setRight(source.getRight());
        target.setBottom(source.getBottom());
        target.setWidth(source.getWidth());
        target.setHeight(source.getHeight());
        target.setEvaluated(source.isEvaluated());
    }

    /**
     * In-memory deep clone of a Serializable object graph (the SOAP beans). Produces a fully
     * independent copy, identical in result to .NET's serialize/deserialize clone.
     * Note: only ever used on data beans we just produced — never on external/untrusted input.
     */
    @SuppressWarnings("unchecked")
    private static <T> T deepClone(T obj) {
        if (obj == null) {
            return null;
        }
        try {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            try (ObjectOutputStream oos = new ObjectOutputStream(bos)) {
                oos.writeObject(obj);
            }
            try (ObjectInputStream ois = new ObjectInputStream(new ByteArrayInputStream(bos.toByteArray()))) {
                return (T) ois.readObject();
            }
        } catch (IOException | ClassNotFoundException e) {
            throw new IllegalStateException("Failed to deep-clone " + obj.getClass().getName(), e);
        }
    }

    private static BigDecimal parseDecimal(String value) {
        if (value == null || value.isBlank()) {
            return BigDecimal.ZERO;
        }
        try {
            return new BigDecimal(value.trim());
        } catch (NumberFormatException e) {
            return BigDecimal.ZERO;
        }
    }

    // ========================================================================
    // Private — Static element initialization
    // Cross-reference: .NET TElement_Helper.LoadStaticElements()
    // ========================================================================

    private static void loadStaticElements() {
        Box box;
        Box boxExtra;
        Picture picture;
        Table table;

        // ---- EMPTY_BLOC ----
        box = new Box();
        STATIC_ELEMENTS.put(StaticTElementNameEnum.EMPTY_BLOC, new TBox(box));

        // ---- IMG ----
        box = new Box();
        picture = new Picture();
        box.setContent(new Content());
        picture.setFit("FITPICTURETOBOXPRO");
        box.setPicture(picture);
        STATIC_ELEMENTS.put(StaticTElementNameEnum.IMG, new TBox(box));

        // ---- PDF_1 (first PDF page — update existing box) ----
        box = new Box();
        picture = new Picture();
        box.setContent(new Content());
        picture.setFit("FITPICTURETOBOXPRO");
        box.setPicture(picture);
        box.setGeometry(new Geometry());
        box.getGeometry().setAllowBoxOffPage("true");
        box.getGeometry().setAllowBoxOnToPasteboard("true");
        boxExtra = new Box();
        boxExtra.setPicture(new Picture());
        STATIC_ELEMENTS.put(StaticTElementNameEnum.PDF_1, new TBox(box, boxExtra));

        // ---- PDF_N (subsequent PDF pages — may be create or update) ----
        box = new Box();
        box.setContent(new Content());
        picture = new Picture();
        box.setGeometry(new Geometry());
        picture.setFit("FITPICTURETOBOXPRO");
        box.setPicture(picture);
        Runaround runaround = new Runaround();
        runaround.setType("NONE");
        box.getGeometry().setRunaround(runaround);
        box.setBoxType(TBoxTypeEnum.CT_PICT.name());
        box.getGeometry().setPosition(new Position());
        boxExtra = new Box();
        boxExtra.setPicture(new Picture());
        STATIC_ELEMENTS.put(StaticTElementNameEnum.PDF_N, new TBox(box, boxExtra));

        // ---- RTF_DOC_XTG ----
        box = new Box();
        box.setContent(new Content());
        box.getContent().setConvertQuotes("true");
        box.getContent().setIncludeStyleSheets("true");
        STATIC_ELEMENTS.put(StaticTElementNameEnum.RTF_DOC_XTG, new TBox(box));

        // ---- MOVE_BLOC ----
        box = new Box();
        box.setGeometry(new Geometry());
        box.getGeometry().setPosition(new Position());
        box.getGeometry().setAllowBoxOffPage("true");
        box.getGeometry().setAllowBoxOnToPasteboard("true");
        STATIC_ELEMENTS.put(StaticTElementNameEnum.MOVE_BLOC, new TBox(box));

        // ---- MOVE_BLOC_VALUE ----
        box = new Box();
        box.setGeometry(new Geometry());
        box.getGeometry().setPosition(new Position());
        box.getGeometry().setAllowBoxOffPage("true");
        box.getGeometry().setAllowBoxOnToPasteboard("true");
        box.setContent(new Content());
        STATIC_ELEMENTS.put(StaticTElementNameEnum.MOVE_BLOC_VALUE, new TBox(box));

        // ---- EMPTY_TABLE ----
        table = new Table();
        STATIC_ELEMENTS.put(StaticTElementNameEnum.EMPTY_TABLE, new TTable(table));
    }

    private static TElement getDefaultTElement(StaticTElementNameEnum elementName) {
        return STATIC_ELEMENTS.get(elementName);
    }
}
```

