# EOS Quark — Batch 13 (REDO) Changes

**Apply on top of Batch 12 (redo).** Supersedes the original Batch 13. **Final batch.**

## Scope — cleanup / hardening, 6 findings across 5 files
- **.NET-free code policy**: identifiers + Batch-13 comments carry no .NET references; the .NET mapping
  lives only in the table below.
- **Comment-scrub scope** ("only Batch 13's own"): de-.NET'd the comments at the six finding sites
  (#59/#71/#74/#75/#76). **Left as inherited** (class headers / earlier-batch comments): the `Cross-reference: .NET …`
  headers in `TElementHelper`, `DocumentIdentityHelper`, `CheckServiceImpl`, and **all** the `.NET`
  comments in `ProcessSqlBusiness` (they belong to Findings #1/#37/#38 from earlier batches; #94 was a
  comment-wording fix on inherited text). Class headers left as-is per your standing decision.

## Findings in this batch

| Finding | File | What changed | .NET source (reference only) |
|---|---|---|---|
| #59 | `CheckServiceImpl.checkOverflow` | removed the redundant `run.setRunTask(new RunTask(run))` (immediately overwritten by `processTasks`) + its now-unused import | `Run_Base.Check()` — Process is sole RunTask creator on reprocess |
| #71 | `DocumentIdentityHelper` | null due-date → min date `01/01/0001 00:00:00` (always a date, never empty) | `Document_Identity_Helper` due-date = `DateTime.MinValue` |
| #74 | `TElementHelper.newBlocName` | wrap the 29-hex name in `[ … ]` (hook-name form) | `NewBlocName()` HookString `"[" + hex + "]"` |
| #75 | `TElementHelper.parseDecimal` | sentinel `-79228162514264337593543950335` (not 0) for null/blank/unparseable position values | `ConversionInvariante.ToDecimal` = `decimal.MinValue` |
| #76 | `BlocPage.getNbBox` | removed the swallow `try/catch` (returned 1 on error, corrupting counts); call `getNbBoxOnPage()` directly (0 for a missing page) | `Bloc_Page.Nb_Box` = `Project_Info.GetNbBoxOnPage()` |
| #94 | `ProcessSqlBusiness` | comment-wording correction (no logic change) | — |

## Deferred (NOT implemented — tracked in the Deferred Considerations Register)
- **#60** stale-XML parity nuance · **#61** overflow Todo-sweep flow · **#70** date patterns configurable (feature; defaults already correct) · **#72** `RunProperties` raw `id_type_rapport`.

> No automated test references these classes, so no test file changes.

---

## Files (full content — whole-file copy-paste)

### 1. `service/impl/CheckServiceImpl.java`
```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.DataNameValue;
import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.StoreDataType;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDynamique;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSql;
import com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.service.CheckService;
import com.socgen.sgs.api.quark.engine.service.ProcessTasksService;
import com.socgen.sgs.api.quark.engine.service.QxpsCallerService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * Step 6: CHECK — Overflow detection, re-processing, and data collection.
 *
 * <p>Three phases:
 * <ol>
 *   <li>Overflow detection: find overflowing boxes, re-process affected dynamic tasks</li>
 *   <li>SQL data collection: collect DataNameValues from TaskDynamique and TaskSql</li>
 *   <li>Document data collection: collect box name/values from final document XML</li>
 * </ol>
 *
 * Cross-reference: .NET Run_Base.Check()
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class CheckServiceImpl implements CheckService {

    private static final String BOX_AUTO_NAME_PREFIX = "Box";
    private static final String BRACKET_OPEN = "[";
    private static final String BRACKET_CLOSE = "]";

    private final GetGabaritXmlBusiness getGabaritXmlBusiness;
    private final ProcessTasksService processTasksService;
    private final QxpsCallerService qxpsCallerService;

    @Override
    public void check(Run run) {
        log.info("Starting Check step for run [{}]", run.getId());

        // Phase 1: Refresh gabarit XML from QXPS (it was purged after step execution)
        refreshGabaritXml(run);

        // Phase 2: Overflow detection and re-processing
        if (hasControlOverflow(run)) {
            checkOverflow(run);
        }

        // Phase 3 & 4: data collection — bitwise tests on the raw store-type code so a combined
        // value (0x03 = SQL|DOCUMENT) enables BOTH collections. (.NET Run_Base.cs:677/699 do two
        // independent (Store_Type & flag) == flag tests.) Finding #1.
        int storeCode = run.getRunProperties().getStoreDataTypeCode();

        // Phase 3: SQL data collection
        if (StoreDataType.hasFlag(storeCode, StoreDataType.SQL)) {
            collectSqlData(run);
        }

        // Phase 4: Document data collection
        if (StoreDataType.hasFlag(storeCode, StoreDataType.DOCUMENT)) {
            // Refresh XML again if overflow re-processing changed the document
            refreshGabaritXml(run);
            collectDocumentData(run);
        }

        log.info("Check step completed for run [{}]", run.getId());
    }

    // ========================================================================
    // Phase 1: Refresh gabarit XML
    // ========================================================================

    /**
     * Fetch the full document XML from QXPS and update the gabarit.
     * After step execution, the gabarit XML is purged (document content changed).
     * We need to fetch the latest XML for overflow detection and data collection.
     *
     * Cross-reference: .NET Document.XML property (lazy-loaded via QXPS_File_Manager.Get_XML)
     */
    private void refreshGabaritXml(Run run) {
        DocumentDomain gabarit = run.getGabarit();
        String documentName = gabarit.getFilePoolPath();

        log.debug("Refreshing gabarit XML from QXPS for document [{}]", documentName);

        // Fetch full document XML via the business bridge (the service must not call infra directly).
        String xmlContent = getGabaritXmlBusiness.fetchXml(documentName);
        if (xmlContent != null && !xmlContent.isEmpty()) {
            gabarit.initXmlFromContent(xmlContent);
            log.debug("Gabarit XML refreshed successfully for document [{}]", documentName);
        } else {
            log.warn("Gabarit XML refresh returned empty for document [{}]", documentName);
        }
    }

    // ========================================================================
    // Phase 2: Overflow detection
    // Cross-reference: .NET Run_Base.Check() — Control_Overflow section
    // ========================================================================

    /**
     * Check if any dynamic task in the run has overflow control enabled.
     */
    private boolean hasControlOverflow(Run run) {
        for (TaskBase task : run.getTasks().values()) {
            if (task instanceof TaskDynamique) {
                TaskDynamique dynTask = (TaskDynamique) task;
                if (dynTask.isTodo() && dynTask.isControlOverflow()) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Detect overflow boxes and re-process affected dynamic tasks.
     *
     * Cross-reference: .NET Run_Base.Check() overflow section
     */
    private void checkOverflow(Run run) {
        log.info("Run [{}] has overflow control enabled", run.getId());

        QxpXml xml = run.getGabarit().getQxpXml();
        List<String> overflowBoxes = xml.getOverflowBoxes();

        log.info("Document contains {} box(es) in overflow", overflowBoxes.size());

        if (overflowBoxes.isEmpty()) {
            return;
        }

        List<TaskBase> tasksToReprocess = new ArrayList<>();

        // Check each dynamic task with control_overflow
        for (TaskBase task : run.getTasks().values()) {
            if (!(task instanceof TaskDynamique)) continue;

            TaskDynamique dynTask = (TaskDynamique) task;
            if (!dynTask.isTodo() || !dynTask.isControlOverflow()) continue;

            log.debug("Task [{}] has overflow control enabled", dynTask.getId());

            // Clear previous overflow boxes
            dynTask.getOverflowBoxes().clear();

            // Find which of this task's box names are in overflow
            for (String boxName : dynTask.getBoxNames()) {
                if (overflowBoxes.contains(boxName)) {
                    dynTask.getOverflowBoxes().add(boxName);
                }
            }

            if (!dynTask.getOverflowBoxes().isEmpty()) {
                tasksToReprocess.add(dynTask);
                log.info("Task [{}] has {} box(es) in overflow — will be re-processed",
                        dynTask.getId(), dynTask.getOverflowBoxes().size());
            } else {
                log.debug("No overflow for task [{}]", dynTask.getId());
            }
        }

        // Set all tasks to todo=false, EXCEPT tasks to reprocess and allwaysReprocess tasks
        if (!tasksToReprocess.isEmpty()) {
            for (TaskBase task : run.getTasks().values()) {
                if (!tasksToReprocess.contains(task) && !task.isAllwaysReprocess()) {
                    task.setTodo(false);
                }
            }

            // Re-execute Process + Process_Steps
            log.info("Re-processing {} task(s) due to overflow", tasksToReprocess.size());

            // processTasks() creates and configures the RunTask itself (single source of truth, with the
            // step limit) — it is the sole creator during re-processing.
            // The previously redundant `run.setRunTask(new RunTask(run))` here was immediately overwritten. #59
            processTasksService.processTasks(run);
            qxpsCallerService.process(run);

            // Refresh XML after re-processing
            refreshGabaritXml(run);
        }
    }

    // ========================================================================
    // Phase 3: SQL data collection
    // Cross-reference: .NET Run_Base.Check() — Store_Data_Type.SQL section
    // ========================================================================

    private void collectSqlData(Run run) {
        log.debug("Collecting SQL data for run [{}]", run.getId());

        // From TaskDynamique
        for (TaskBase task : run.getTasks().values()) {
            if (task instanceof TaskDynamique) {
                TaskDynamique dynTask = (TaskDynamique) task;
                if (dynTask.isStoreData() && !dynTask.getDataNamesValues().isEmpty()) {
                    run.getSqlDataNamesValues().addAll(dynTask.getDataNamesValues());
                }
            }
        }

        // From TaskSql
        for (TaskBase task : run.getTasks().values()) {
            if (task instanceof TaskSql) {
                TaskSql sqlTask = (TaskSql) task;
                if (sqlTask.isStoreData() && !sqlTask.getDataNamesValues().isEmpty()) {
                    run.getSqlDataNamesValues().addAll(sqlTask.getDataNamesValues());
                }
            }
        }

        log.info("Collected {} SQL data entries for run [{}]",
                run.getSqlDataNamesValues().size(), run.getId());
    }

    // ========================================================================
    // Phase 4: Document data collection
    // Cross-reference: .NET Run_Base.Check() — Store_Data_Type.DOCUMENT section
    // ========================================================================

    private void collectDocumentData(Run run) {
        log.debug("Collecting document data for run [{}]", run.getId());

        QxpXml xml = run.getGabarit().getQxpXml();
        List<String[]> namesValues = xml.getNamesValuesBoxes();

        for (String[] nameValue : namesValues) {
            String name = nameValue[0];

            // Exclude auto-generated box names:
            // 1. Names starting with "Box" (QuarkXPress auto-naming)
            // 2. Names enclosed in brackets [name] (clone auto-naming)
            if (name.startsWith(BOX_AUTO_NAME_PREFIX)) {
                continue;
            }
            if (name.startsWith(BRACKET_OPEN) && name.endsWith(BRACKET_CLOSE)) {
                continue;
            }

            String value = nameValue.length > 1 ? nameValue[1] : "";
            run.getDocDataNamesValues().add(new DataNameValue(name, value));
        }

        log.info("Collected {} document data entries for run [{}]",
                run.getDocDataNamesValues().size(), run.getId());
    }
}
```

### 2. `domain/helper/DocumentIdentityHelper.java`
```java
package com.socgen.sgs.api.quark.engine.domain.helper;

import com.socgen.sgs.api.quark.engine.domain.DocumentIdentity;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.StringJoiner;

/**
 * Helper for Document Identity (DID) operations on QuarkXPress documents generated by the engine.
 * <p>
 * The identity string format is pipe-separated:
 * ID_Fnd_Code|ID_Suivi|ID_Run|ID_Langue|Due_Date|Generation_DateTime|ID_Unit_Code
 * </p>
 * <p>Translated from .NET {@code Document_Identity_Helper} — {@code QXP.Engine.Core}</p>
 *
 * @see DocumentIdentity
 */
public final class DocumentIdentityHelper {

    private static final String DID = "DID";
    private static final DateTimeFormatter DATE_TIME_FORMATTER =
            DateTimeFormatter.ofPattern("MM/dd/yyyy HH:mm:ss");

    private DocumentIdentityHelper() {
        // utility class
    }

    /**
     * Builds the new DID identity string for the given run, directly from run properties.
     * <p>
     * Format: ID_Fnd_Code|ID_Suivi|ID_Run|ID_Langue|Due_Date|Generation_DateTime|ID_Unit_Code
     * </p>
     * Equivalent to .NET: {@code Document_Identity_Helper.Get_New_Identity(Run_Base run)}
     *
     * @param run the current run
     * @return pipe-separated identity string
     */
    public static String getNewIdentity(Run run) {
        RunProperties props = run.getRunProperties();

        StringJoiner joiner = new StringJoiner("|");
        joiner.add(props.getIdFndCode() != null ? props.getIdFndCode() : "");
        joiner.add(String.valueOf(props.getIdSuivi()));
        joiner.add(run.getId() != null ? String.valueOf(run.getId()) : "");
        joiner.add(String.valueOf(props.getIdLangue()));
        // Always render a date here; a null due-date becomes the min date (01/01/0001 00:00:00),
        // not an empty field. Finding #71.
        joiner.add((props.getDateEcheance() != null ? props.getDateEcheance() : java.time.LocalDate.of(1, 1, 1))
                .atStartOfDay().format(DATE_TIME_FORMATTER));
        joiner.add(LocalDateTime.now().format(DATE_TIME_FORMATTER));
        joiner.add(props.getIdUnitCode() != null ? props.getIdUnitCode() : "");

        return joiner.toString();
    }

    /**
     * Retrieves the raw DID value string from a QuarkXPress document already in the QXPS pool.
     * <p>
     * Fetches the XML for the DID box and extracts the text value.
     * </p>
     * Equivalent to .NET: {@code Document_Identity_Helper.Get_Identity_Value(string documentName)}
     *
     * @param documentName         the name of the document in the QXPS pool
     * @param documentIdentityPort the port used to call QXPS and parse XML
     * @return the raw pipe-separated DID value string
     */
    public static String getIdentityValue(String documentName, DocumentIdentityPort documentIdentityPort) {
        String xmlDid = documentIdentityPort.fetchXmlForBox(documentName, DID);
        return documentIdentityPort.getElementValueByIdName(xmlDid, DID);
    }

    /**
     * Retrieves and parses the DID identity of a QuarkXPress document already in the QXPS pool.
     * <p>
     * Combines {@link #getIdentityValue} and parses the result into a {@link DocumentIdentity}.
     * </p>
     * Equivalent to .NET: {@code Document_Identity_Helper.Get_Identity(string documentName)}
     *
     * @param documentName         the name of the document in the QXPS pool
     * @param documentIdentityPort the port used to call QXPS and parse XML
     * @return a populated {@link DocumentIdentity}
     */
    public static DocumentIdentity getIdentity(String documentName, DocumentIdentityPort documentIdentityPort) {
        return documentIdentityPort.parseDocumentIdentity(getIdentityValue(documentName, documentIdentityPort));
    }
}
```

### 3. `domain/helper/TElementHelper.java`
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
        String body = uuid.length() > NEW_BLOC_NAME_SIZE ? uuid.substring(0, NEW_BLOC_NAME_SIZE) : uuid;
        // Wrap in square brackets to match the expected hook-name form ("[" + 29-hex + "]"). Finding #74.
        return "[" + body + "]";
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

    /** Sentinel returned for a null/unparseable position value (NOT 0, so it stays distinguishable). Finding #75. */
    private static final BigDecimal DECIMAL_MIN_VALUE = new BigDecimal("-79228162514264337593543950335");

    private static BigDecimal parseDecimal(String value) {
        // Lenient decimal parse: return the sentinel (not 0) for null/blank/unparseable.
        // Scoped to updatePosition's four position reads. Finding #75.
        if (value == null || value.isBlank()) {
            return DECIMAL_MIN_VALUE;
        }
        try {
            return new BigDecimal(value.trim());
        } catch (NumberFormatException e) {
            return DECIMAL_MIN_VALUE;
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

### 4. `domain/bloc/BlocPage.java`
```java
package com.socgen.sgs.api.quark.engine.domain.bloc;

import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import lombok.Getter;
import lombok.Setter;

/** Represents a page bloc for page creation/deletion in a QuarkXPress document. */
@Getter
@Setter
public class BlocPage extends BlocBase {

    private boolean createNextDummyPage = false;

    public BlocPage(TaskBase task, String name) {
        super(task, name);
        this.setPagination(true);
    }

    /** Page position relative to the spine (LEFTOFSPINE or empty). */
    public String getPosition() {
        RunProperties props = getTask().getRun().getRunProperties();
        if (props.getNbPageBySpread() != RunProperties.PAGINATION_SIMPLE
                && getPageId() != 1
                && getIndexPosition() == 0) {
            return "LEFTOFSPINE";
        }
        return "";
    }

    /** Index of the page position within its spread. */
    public int getIndexPosition() {
        RunProperties props = getTask().getRun().getRunProperties();
        if (getPageId() == 1) {
            return 0;
        }
        if (isLagSpread()) {
            return (getPageId() + 1) % props.getNbPageBySpread();
        }
        return getPageId() % props.getNbPageBySpread();
    }

    @Override
    public int getNbBox() {
        if (getAction() == BlocActionEnum.REMOVE) {
            // When removing a page, count the boxes on that page from the gabarit XML.
            // Return getNbBoxOnPage() directly, with no try/catch. getProjectInfo() is non-null (lazy) and
            // getNbBoxOnPage returns 0 for a missing page, so the previous catch silently returning 1
            // corrupted the box count. Finding #76.
            return getTask().getRun().getGabarit()
                    .getQxpXml().getProjectInfo().getNbBoxOnPage(getPageId());
        }
        return super.getNbBox();
    }
}

```

### 5. `business/ProcessSqlBusiness.java`
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

    /** RunError categories (see RunError / .NET Error_Type): 1=Unspecified, 2=Critique, 3=Bloquante. */
    private static final int CRITIQUE = RunError.CRITIQUE;

    private final TaskSqlDao taskSqlDao;
    private final InParamSqlMapper inParamSqlMapper;

    public void execute(TaskSql task) {
        Map<String, Object> parameters = inParamSqlMapper.toParameterMap(task.getRun().getInParams());

        try {
            List<Map<String, Object>> rows = taskSqlDao.executeSql(task.getSql(), parameters);

            if (rows.isEmpty()) {
                log.warn("No SQL data returned for task {}", task.getId());
            } else {
                addBlocs(task, rows);
            }

            checkTaskExceptions(task);
        } catch (Exception ex) {
            throw new RuntimeException("Error executing SQL for task " + task.getDebugInfo(), ex);
        }
    }

    private void addBlocs(TaskSql task, List<Map<String, Object>> rows) {
        boolean integrerN1 = task.getRun().getRunProperties().isIntegrerN1();
        // Bitwise SQL test on the raw store-type code (the enum collapsed combined values like 0x03
        // to NONE, losing the SQL bit). (.NET Run_Base.cs:677.) Finding #1.
        boolean storeData = task.isStoreData()
                && StoreDataType.hasFlag(task.getRun().getRunProperties().getStoreDataTypeCode(), StoreDataType.SQL);

        for (Map<String, Object> row : rows) {
            String blocName = "";
            try {
                blocName = toString(row.get(NAME_BLOC_COL));
                if (!integrerN1 && blocName.endsWith(N1_END_BLOC)) {
                    continue;
                }

                String blocValue = DataTypeHelper.outputToString(
                        row.get(VALUE_BLOC_COL), task.getDataType(), task.getNbDecimal(),
                        task.isShowZero(), task.getNullString(), task.isDecimalSignificative());

                if (task.getBlocsUpdate().containsKey(blocName)) {
                    // Parity: .NET Process_SQL records ErrorDuplicateBlocInTask (Errors.Add(string) →
                    // Error_Type.Unspecified). Finding #37.
                    task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED, String.format(
                            "Duplicate Name Bloc in task : %s bloc : %s", task.getDebugInfo(), blocName)));
                    log.warn("Duplicate bloc '{}' in task {}", blocName, task.getDebugInfo());
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
                // Parity: .NET Process_SQL records ErrorAddingBlocSQLInTask (Errors.Add(string) →
                // Error_Type.Unspecified) for a per-row failure instead of only logging. Finding #38.
                task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED, String.format(
                        "Error when adding bloc in task : %s bloc : %s", task.getDebugInfo(), blocName)));
                log.error("Error adding bloc '{}' in task {}", blocName, task.getDebugInfo(), e);
            }
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
                        || bloc.getValue().isBlank()
                        || bloc.getValue().equals(task.getNullString());
            } else {
                processRemove = true;
            }

            if (!processRemove) continue;

            // The conditional bloc to remove must exist in the document.
            // Cross-reference: .NET Process_SQL.Check_Task_Exception — Exist_Name guard.
            if (!xml.existName(exception.getName())) {
                task.getRun().getErrors().add(new RunError(CRITIQUE,
                        "Bloc conditionnel invalide [" + exception.getName() + "] (tache " + task.getId() + ")"));
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
                        task.getRun().getErrors().add(new RunError(CRITIQUE,
                                "Lignes manquantes dans la table [" + exception.getTableName()
                                        + "] pour le bloc [" + exception.getName() + "]"));
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
                task.getRun().getErrors().add(new RunError(CRITIQUE,
                        "Table inexistante [" + exception.getTableName() + "]"));
            }
        }

        if (!lastDestination.isEmpty()) {
            task.setDestinationBlocName(lastDestination);
        }
    }

    private static String toString(Object value) {
        return value != null ? value.toString() : "";
    }
}

```

---

## Apply checklist
- [ ] `service/impl/CheckServiceImpl.java` (also drop the now-unused `RunTask` import — #59)
- [ ] `domain/helper/DocumentIdentityHelper.java`
- [ ] `domain/helper/TElementHelper.java`
- [ ] `domain/bloc/BlocPage.java`
- [ ] `business/ProcessSqlBusiness.java`
- [ ] `mvn test`

## Redo series complete
Batches 11–13 redone .NET-free (code); all 13 batches now consistent with the no-.NET-reference policy.
Deferred items consolidated in `EOS_Quark_Deferred_Considerations_Register.md`.
