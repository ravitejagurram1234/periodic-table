# EOS Quark — Batch 7C Changes (copy-paste) — task #15

**Task #15 = page-break + Document count-mismatch + Compartiment list-errors + runtype column.**

**Implemented (4 files):**
- **`runtype` column fix** (`RunPropertiesMapper`) — verified against the real `Get_Run_Properties` cursor in ora.txt: the column is **`runtype`** (a CASE expr: Upload/Plannifiee/Manuelle). The code now reads `runtype` (NOT `runtime`, which would throw `SQLException: invalid column name` on every run-properties load). **If your copy still reads `"runtime"`, this is the critical one to apply.**
- **Dynamique page-break** (`DynamiquePageBreakHelper`) — the break-rows list is now RETAINED (set only when a row is retrieved, reused in the else branch) instead of recomputed from each loop row. Matches .NET `__current_Break_Rows`; fixes wrong header/break rows being repeated on a page/column break.
- **Document QXP_Data count-mismatch** (`DocumentTaskProcessStrategy`) — when the source and destination pipe-lists differ in length, a clear run error is recorded and only the safe overlap is processed. NOTE: .NET has an unresolved TODO here and would actually crash (IndexOutOfRange) on a mismatch — this is safer than .NET.
- **Compartiment list errors** (`CompartimentTaskProcessStrategy`) — added `NoneRunCompartiment` (no child runs) and `EmptyRunCompartiment` (a compartment with no run id) run errors (were log-only).

**DEFERRED (tracked as a separate task — partial subsystem, not a quick fix):**
- Compartiment **Run_Previous** reuse (load a child's previously-generated document instead of regenerating, for INCORPORATE-only mode), reading the child's **result final-QXP parsed into a project** (Java currently reads the child gabarit project; parsing a generated QXP into a project is itself unwired), and the per-child `EmptyRunChildQXP` / `EmptyRunChildProject` errors on that correct source. Adding those errors now (against the wrong source) would be misleading, so they are deferred.

## How to apply
Each section is one file — replace its entire contents with the block. Paths relative to the `quark-engine` module root. Then `mvn -DskipTests compile` and `mvn test`.

## Checklist (4 files)
- [ ] `mapper/RunPropertiesMapper.java` — FIX (runtype column)
- [ ] `domain/helper/DynamiquePageBreakHelper.java` — CHANGED
- [ ] `service/task/impl/DocumentTaskProcessStrategy.java` — CHANGED
- [ ] `service/task/impl/CompartimentTaskProcessStrategy.java` — CHANGED

---

## 1. `src/main/java/com/socgen/sgs/api/quark/engine/mapper/RunPropertiesMapper.java`  — **FIX (runtype column)**

```java
package com.socgen.sgs.api.quark.engine.mapper;

import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.StoreDataType;
import com.socgen.sgs.api.quark.engine.domain.TaskCompartimentMode;
import com.socgen.sgs.api.quark.engine.enums.GabaritSourceEnum;
import com.socgen.sgs.api.quark.engine.enums.TypeRapportEnum;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * Mapper class for converting database ResultSet or column maps to {@link RunProperties}.
 * This mapper can be reused for DTO conversions and other transformations.
 */
@Component
@Slf4j
public class RunPropertiesMapper {

    /**
     * Maps a ResultSet row to a RunProperties domain object.
     * Used by returningResultSet RowMapper in SimpleJdbcCall.
     *
     * @param rs the ResultSet positioned at the current row
     * @return a populated RunProperties object
     * @throws SQLException if a database access error occurs
     */
    public RunProperties mapFromResultSet(ResultSet rs) throws SQLException {
        RunProperties props = new RunProperties();
        int intVal;

        intVal = rs.getInt("id_type_rapport");
        props.setTypeRapport(rs.wasNull() ? TypeRapportEnum.UNKNOWN : TypeRapportEnum.fromCode(intVal));

        props.setIdFndCode(rs.getString("id_fnd_code"));
        props.setIdUnitCode(rs.getString("id_unit_code"));

        java.sql.Date dateEcheance = rs.getDate("date_echeance");
        if (dateEcheance != null) {
            props.setDateEcheance(dateEcheance.toLocalDate());
        }

        props.setIdSuivi(rs.getInt("id_suivi"));
        props.setIdLangue(rs.getInt("id_langue"));
        props.setSociete(rs.getString("societe"));
        props.setCodeLangue(rs.getString("code_langue"));

        intVal = rs.getInt("gabarit_source");
        props.setGabaritSource(rs.wasNull() ? GabaritSourceEnum.UNKNOWN : GabaritSourceEnum.fromCode(intVal));

        intVal = rs.getInt("id_suivi_gabarit_source");
        props.setIdSuiviGabaritSource(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        props.setIntegrerN1(rs.getInt("integrer_n1") != 0);

        intVal = rs.getInt("mode_compart");
        props.setCompartimentMode(rs.wasNull() ? TaskCompartimentMode.UNKNOWN
                : TaskCompartimentMode.fromCode(intVal));

        props.setRunType(rs.getString("runtype"));
        props.setGenerateToWord(rs.getInt("generate_to_word") != 0);

        intVal = rs.getInt("id_gabarit");
        props.setIdGabarit(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        intVal = rs.getInt("id_gabarit_template");
        props.setIdGabaritTemplate(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        intVal = rs.getInt("id_doc_pdf");
        props.setIdLastPdf(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        intVal = rs.getInt("id_doc_qxp");
        props.setIdLastQxp(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        intVal = rs.getInt("id_doc_doc");
        props.setIdLastDoc(rs.wasNull() ? Integer.MIN_VALUE : intVal);

        props.setNbPageBySpread(rs.getInt("pagination_double") != 0
                ? RunProperties.PAGINATION_DOUBLE
                : RunProperties.PAGINATION_SIMPLE);

        intVal = rs.getInt("store_data_type");
        props.setStoreDataType(rs.wasNull() ? StoreDataType.NONE
                : StoreDataType.fromCode(intVal));

        return props;
    }
}




```

## 2. `src/main/java/com/socgen/sgs/api/quark/engine/domain/helper/DynamiquePageBreakHelper.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.domain.helper;

import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBreakRule;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBreakRules;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DCell;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DReport;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DRow;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.PrepareReportParameters;
import lombok.extern.slf4j.Slf4j;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

/**
 * Handles page/column break row evaluation during dynamic report preparation.
 * When a row causes a page or column overflow, this helper determines:
 * <ul>
 *   <li>Which previous rows should be "brought along" to the new page (via break rules)</li>
 *   <li>Which header rows (page break rows) should be repeated on the new page</li>
 *   <li>Position updates for all affected rows and cells</li>
 * </ul>
 *
 * Cross-reference: QXP.Engine.Core.Dynamique_Page_Break_Helper
 */
@Slf4j
public final class DynamiquePageBreakHelper {

    private DynamiquePageBreakHelper() {
    }

    /**
     * Update rows when a page or column break occurs.
     * Handles both rule-based row retrieval and break row (header) duplication.
     *
     * @param report    the report being prepared
     * @param tableRows the rows of the current table
     * @param currentRow the row that triggered the break
     * @param prp       the prepare report parameters (page, column, cursor state)
     * @param pageBreak true for page break, false for column break
     * @param left      left position offset (0 for page break, accumulated width for column break)
     */
    public static void updateRows(DReport report, List<DRow> tableRows, DRow currentRow,
                                  PrepareReportParameters prp, boolean pageBreak, BigDecimal left) {

        // Get applicable break rules
        DBreakRule rules;
        int previousPageColumn;

        if (pageBreak) {
            rules = report.getPageBreakRules().getRule(currentRow.getLevel());
            previousPageColumn = prp.getPage() - 1;
        } else {
            rules = report.getColumnBreakRules().getRule(currentRow.getLevel());
            previousPageColumn = prp.getColumn() - 1;
        }

        // Row retrieval counters
        int nbRowsRetrieves = -1; // Start at -1 because currentRow is in the loop but shouldn't count
        int nbRowsMinRetrieves = 0;

        // Check for negative values in bring levels (means "bring N rows regardless of level")
        for (int val : rules.getBringLevels()) {
            if (val < 0) {
                nbRowsMinRetrieves = Math.max(nbRowsMinRetrieves, -val);
            }
        }

        // Heights and widths tracking
        BigDecimal breakHeight = BigDecimal.ZERO;
        BigDecimal breakWidth = BigDecimal.ZERO;
        BigDecimal retrievesRowsHeight = BigDecimal.ZERO;
        BigDecimal retrievesRowsWidth = currentRow.getInfo().getWidth();

        // Lists for processing
        List<DRow> retrievedRows = new ArrayList<>();
        DRow firstRow = currentRow;
        List<DRow> breakRows;
        // Break-rows of the LAST RETRIEVED row — retained across iterations, NOT recomputed per loop row.
        // Cross-reference: .NET __current_Break_Rows (set in the retrieve branch, reused in the else branch).
        List<DRow> currentBreakRows = null;
        List<Integer> rowlevelRemoveBreak = new ArrayList<>();
        boolean activeRules = true;

        // ====================================================================
        // Phase 1: Rules — retrieve previous rows based on break rules
        // ====================================================================

        int currentRowIndex = tableRows.indexOf(currentRow);

        // Reverse iterate from currentRow upward
        for (int i = currentRowIndex; i >= 0; i--) {
            DRow row = tableRows.get(i);

            // Skip break rows (header repetition rows)
            if (isRowBreak(row)) {
                continue;
            }

            int currentPageColumn;
            if (pageBreak) {
                currentPageColumn = currentRow.getInfo().getPage();
            } else {
                currentPageColumn = currentRow.getInfo().getColumn();
            }

            // Retrieve row if:
            // 1. It's the current row (always included)
            // 2. Rules are active AND its level matches bring_levels AND it's on the previous page
            // 3. We haven't yet retrieved the minimum number of rows
            boolean isCurrentRow = (row == currentRow);
            boolean matchesRules = activeRules
                    && rules.getBringLevels().contains(row.getLevel())
                    && (currentPageColumn == previousPageColumn);
            boolean belowMinimum = (nbRowsRetrieves < nbRowsMinRetrieves);

            if (isCurrentRow || matchesRules || belowMinimum) {
                // Retain THIS retrieved row's break rows; the else branch on later rows reuses it.
                currentBreakRows = pageBreak ? row.getPageBreakRows() : row.getColumnBreakRows();
                firstRow = row;
                retrievedRows.add(row);
                retrievesRowsHeight = retrievesRowsHeight.add(row.getInfo().getHeight());
                retrievesRowsWidth = retrievesRowsWidth.max(row.getInfo().getWidth());
                nbRowsRetrieves++;

                int indexBreak = indexRowTypeBreak(currentBreakRows, row.getLevel());
                if (indexBreak >= 0 && !rowlevelRemoveBreak.contains(row.getLevel())) {
                    rowlevelRemoveBreak.add(row.getLevel());
                }
            } else {
                int indexBreak = indexRowTypeBreak(currentBreakRows, row.getLevel());
                activeRules = false;

                // If this row matches a break row level, still retrieve it
                if (indexBreak >= 0) {
                    firstRow = row;
                    retrievedRows.add(row);
                    retrievesRowsHeight = retrievesRowsHeight.add(row.getInfo().getHeight());
                    retrievesRowsWidth = retrievesRowsWidth.max(row.getInfo().getWidth());
                    nbRowsRetrieves++;

                    if (!rowlevelRemoveBreak.contains(row.getLevel())) {
                        rowlevelRemoveBreak.add(row.getLevel());
                    }
                } else {
                    // No more rules apply — stop
                    break;
                }
            }
        }

        // ====================================================================
        // Phase 2: Pre-process — check rows AFTER currentRow for break duplicates
        // ====================================================================

        List<DRow> currentBreakRowsForCheck = pageBreak
                ? currentRow.getPageBreakRows()
                : currentRow.getColumnBreakRows();

        for (int i = currentRowIndex + 1; i < tableRows.size(); i++) {
            DRow row = tableRows.get(i);
            if (!isRowBreak(row)) {
                int indexBreak = indexRowTypeBreak(currentBreakRowsForCheck, row.getLevel());
                if (indexBreak >= 0) {
                    if (!rowlevelRemoveBreak.contains(row.getLevel())) {
                        rowlevelRemoveBreak.add(row.getLevel());
                    }
                } else {
                    break;
                }
            }
        }

        // ====================================================================
        // Phase 3: Breaks — duplicate and insert header rows on new page/column
        // ====================================================================

        List<DRow> firstRowBreakRows = pageBreak
                ? new ArrayList<>(firstRow.getPageBreakRows())
                : new ArrayList<>(firstRow.getColumnBreakRows());

        // Remove break rows whose level conflicts with retrieved rows
        firstRowBreakRows.removeIf(row -> rowlevelRemoveBreak.contains(row.getLevel()));

        breakRows = firstRowBreakRows;

        if (!breakRows.isEmpty()) {
            int firstNewRowIndex = tableRows.indexOf(firstRow);

            for (DRow breakRow : breakRows) {
                DRow duplicateRow = duplicateUpdateDRow(breakRow, prp.getPage(), prp.getColumn());

                // Update cell positions for the duplicated break row
                BigDecimal anchorBottom = prp.getTask().getStartAnchor().getBottom();
                BigDecimal anchorRight = prp.getTask().getStartAnchor().getRight();

                for (DCell cell : duplicateRow.getCells()) {
                    cell.getInfo().getZone().setTop(
                            breakHeight.add(anchorBottom).add(cell.getTemplate().getTop()));
                    cell.getInfo().getZone().setLeft(
                            left.add(anchorRight).add(cell.getTemplate().getLeft()));
                    cell.getInfo().setPage(prp.getPage());
                    cell.getInfo().setColumn(prp.getColumn());
                }

                // Insert at the correct position
                tableRows.add(firstNewRowIndex, duplicateRow);

                breakHeight = breakHeight.add(breakRow.getInfo().getHeight());
                breakWidth = breakWidth.max(breakRow.getInfo().getWidth());
            }
        }

        // ====================================================================
        // Phase 4: Update positions of retrieved rows on new page
        // ====================================================================

        BigDecimal top = breakHeight;
        BigDecimal anchorBottom = prp.getTask().getStartAnchor().getBottom();
        BigDecimal anchorRight = prp.getTask().getStartAnchor().getRight();

        // Check if there's enough space on the new page for all retrieved rows
        BigDecimal totalNeeded = retrievesRowsHeight.add(top).add(currentRow.getInfo().getHeight());

        if (totalNeeded.compareTo(prp.getAvailableHeight()) < 0) {
            // Enough space — update all retrieved rows (reverse order → top to bottom)
            for (int i = retrievedRows.size() - 1; i >= 0; i--) {
                DRow row = retrievedRows.get(i);
                row.getInfo().setPage(prp.getPage());
                row.getInfo().setColumn(prp.getColumn());

                for (DCell cell : row.getCells()) {
                    cell.getInfo().getZone().setTop(
                            top.add(anchorBottom).add(cell.getTemplate().getTop()));
                    cell.getInfo().getZone().setLeft(
                            left.add(anchorRight).add(cell.getTemplate().getLeft()));
                    cell.getInfo().setPage(prp.getPage());
                    cell.getInfo().setColumn(prp.getColumn());
                }
                top = top.add(row.getInfo().getHeight());
            }
        } else {
            // Not enough space — only update the current row that triggered the break
            currentRow.getInfo().setPage(prp.getPage());
            currentRow.getInfo().setColumn(prp.getColumn());

            for (DCell cell : currentRow.getCells()) {
                cell.getInfo().getZone().setTop(
                        top.add(anchorBottom).add(cell.getTemplate().getTop()));
                cell.getInfo().getZone().setLeft(
                        left.add(anchorRight).add(cell.getTemplate().getLeft()));
                cell.getInfo().setPage(prp.getPage());
                cell.getInfo().setColumn(prp.getColumn());
            }
            top = top.add(currentRow.getInfo().getHeight());

            log.warn("Break rule ignored — not enough space on page {} column {} for task [{}]",
                    prp.getPage(), prp.getColumn(), prp.getTask().getId());
        }

        // ====================================================================
        // Update results
        // ====================================================================

        prp.setCurrentTableHeight(top);
        prp.setCurrentTableWidth(breakWidth.max(retrievesRowsWidth));
        prp.setNbRowsAdded(breakRows.size());
    }

    // ========================================================================
    // Private helpers
    // ========================================================================

    /**
     * Check if a row's level matches any of the break rows' levels.
     *
     * @param breakRows the list of break rows
     * @param rowLevel  the level to check
     * @return the index of the matching break row, or -1 if not found
     */
    private static int indexRowTypeBreak(List<DRow> breakRows, int rowLevel) {
        if (breakRows == null) {
            return -1;
        }
        for (int i = 0; i < breakRows.size(); i++) {
            if (breakRows.get(i).getLevel() == rowLevel) {
                return i;
            }
        }
        return -1;
    }

    /**
     * Check if a row is a break row (page break or column break).
     *
     * @param row the row to check
     * @return true if the row has page break or column break behavior
     */
    private static boolean isRowBreak(DRow row) {
        return row.isPageBreak() || row.isColumnBreak();
    }

    /**
     * Duplicate a break row with updated page and column info.
     *
     * @param row    the row to clone
     * @param page   the new page number
     * @param column the new column number
     * @return a cloned row with updated page/column
     */
    private static DRow duplicateUpdateDRow(DRow row, int page, int column) {
        DRow newRow = row.cloneRow();
        newRow.getInfo().setPage(page);
        newRow.getInfo().setColumn(column);
        for (DCell cell : newRow.getCells()) {
            cell.getInfo().setPage(page);
            cell.getInfo().setColumn(column);
        }
        return newRow;
    }
}
```

## 3. `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/DocumentTaskProcessStrategy.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocPage;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocTable;
import com.socgen.sgs.api.quark.engine.domain.element.TBox;
import com.socgen.sgs.api.quark.engine.domain.element.TElement;
import com.socgen.sgs.api.quark.engine.domain.element.TGroup;
import com.socgen.sgs.api.quark.engine.domain.element.TTable;
import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDocument;
import com.socgen.sgs.api.quark.engine.domain.task.TaskImageOffset;
import com.socgen.sgs.api.quark.engine.domain.task.TaskImagePosition;
import com.socgen.sgs.api.quark.engine.domain.xml.QxpXml;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.enums.StaticTElementNameEnum;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessStrategy;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/**
 * Strategy for processing TaskDocument (document/image insertion into blocs).
 * Handles document formats: IMG, PDF, DOC/RTF/XTG, QXP_Data.
 *
 * <p>Each format has distinct processing logic matching .NET Process_Document.cs exactly:
 * <ul>
 *   <li>IMG: Get TElement template, set image path, create BlocBox in blocsModify</li>
 *   <li>PDF: Multi-page with UPDATE/CREATE logic based on existing blocs in gabarit</li>
 *   <li>DOC/RTF/XTG: Get TElement template, set file path with "file:" prefix, create BlocBox</li>
 *   <li>QXP_Data (value mode): Extract value from source document XML, create BlocBox in blocsUpdate</li>
 *   <li>QXP_Data (style mode): Analyse source project, clone TElement, create bloc in blocsModify</li>
 * </ul>
 *
 * Cross-reference: QXP.Engine.Core.Business.Process_Document
 */
@Component
@Slf4j
public class DocumentTaskProcessStrategy implements TaskProcessStrategy<TaskDocument> {

    // Constants matching .NET Process_Document
    private static final String SOURCE_FILE_ABSOLU_PATTERN = "%s";
    private static final String SOURCE_FILE_DOC_POOL_PATTERN = "file:%s";
    private static final String PDF_BLOC_NAME_PATTERN = "%s_%d";    // 0=prefix, 1=bloc number
    private static final String PDF_PAGE_NAME_PATTERN = "P%d_%s";   // 0=page, 1=bloc name
    private static final String PICTURE_ROTATION_90 = "90";

    @Override
    public Class<TaskDocument> getTaskType() {
        return TaskDocument.class;
    }

    @Override
    public void process(TaskDocument task) {
        log.debug("DocumentTaskProcessStrategy processing task [{}] format={}",
                task.getId(), task.getFormatDocument());

        // Validate destination bloc name
        if (task.getDestinationBlocName() == null || task.getDestinationBlocName().isBlank()) {
            log.warn("Missing destinationBlocName for document task [{}], skipping", task.getId());
            return;
        }

        BlocBox blocBox = null;

        SubTaskTypeEnum subTaskType = task.getSubTaskType();
        if (subTaskType == null) {
            log.warn("Document task [{}] has null sub-task type, skipping", task.getId());
            return;
        }

        switch (subTaskType) {
            case FILE_IMG:
                blocBox = processImg(task);
                break;
            case FILE_PDF:
                processFilePdf(task);
                break;
            case FILE_DOC:
            case FILE_RTF:
            case FILE_XTG:
                blocBox = processDocumentFile(task);
                break;
            case FILE_QXP_DATA:
                processFileQxpData(task);
                break;
            default:
                log.warn("Unsupported sub-task type [{}] for document task [{}]",
                        subTaskType, task.getId());
                return;
        }

        // IMG and DOC/RTF/XTG return a single blocBox to add to blocsModify
        // PDF and QXP_Data handle their own bloc additions internally
        if (blocBox != null) {
            task.getBlocsModify().put(blocBox.getName(), blocBox);
        }
    }

    // ========================================================================
    // IMG format
    // Cross-reference: Process_Document.cs lines 43-48
    // ========================================================================

    /**
     * IMG format: Get TElement template, set image file path, handle rotation.
     * Uses Static_TElement_Name.IMG template.
     * Action is NOT explicitly set (uses default from BlocBase constructor = NONE).
     */
    private BlocBox processImg(TaskDocument task) {
        log.debug("DocumentTaskProcessStrategy IMG: task [{}]", task.getId());

        DocumentDomain doc = task.getDocument();
        if (doc == null) {
            log.warn("IMG task [{}] has no document loaded, skipping", task.getId());
            return null;
        }

        // Get a clone of the IMG TElement template
        TElement tElement = TElementHelper.getTElement(
                StaticTElementNameEnum.IMG, task.getDestinationBlocName());
        if (!(tElement instanceof TBox)) {
            log.warn("IMG task [{}] could not get TBox template", task.getId());
            return null;
        }

        TBox tBox = (TBox) tElement;

        // Set image file path as content value (absolute path)
        // .NET: __tBox.SrcBox.content.value = string.Format(SourceFileAbsoluPattern, task.Document.FileFullPath)
        if (tBox.getSrcBox().getContent() != null) {
            tBox.getSrcBox().getContent().setValue(
                    String.format(SOURCE_FILE_ABSOLU_PATTERN, doc.getFileFullPath()));
        }

        // Handle image rotation
        // .NET: if (task.Rotation_Image) __tBox.SrcBox.picture.angle = "90"
        if (task.isRotationImage() && tBox.getSrcBox().getPicture() != null) {
            tBox.getSrcBox().getPicture().setAngle(PICTURE_ROTATION_90);
        }

        // Create BlocBox from TBox (extracts srcBox and srcExtraBox)
        BlocBox blocBox = new BlocBox(task, task.getDestinationBlocName(),
                tBox.getSrcBox(), tBox.getSrcExtraBox());

        log.debug("IMG bloc [{}] created with path [{}]",
                task.getDestinationBlocName(), doc.getFileFullPath());

        return blocBox;
    }

    // ========================================================================
    // DOC/RTF/XTG format
    // Cross-reference: Process_Document.cs lines 52-58
    // ========================================================================

    /**
     * DOC/RTF/XTG format: Get TElement template, set file path with "file:" prefix.
     * Uses Static_TElement_Name.RTF_DOC_XTG template.
     * Action is NOT explicitly set (uses default = NONE).
     */
    private BlocBox processDocumentFile(TaskDocument task) {
        log.debug("DocumentTaskProcessStrategy DOC/RTF/XTG: task [{}] subType={}",
                task.getId(), task.getSubTaskType());

        DocumentDomain doc = task.getDocument();
        if (doc == null) {
            log.warn("Document file task [{}] has no document loaded, skipping", task.getId());
            return null;
        }

        // Get a clone of the RTF_DOC_XTG TElement template
        TElement tElement = TElementHelper.getTElement(
                StaticTElementNameEnum.RTF_DOC_XTG, task.getDestinationBlocName());
        if (!(tElement instanceof TBox)) {
            log.warn("DOC/RTF/XTG task [{}] could not get TBox template", task.getId());
            return null;
        }

        TBox tBox = (TBox) tElement;

        // Set file path with "file:" prefix as content value
        // .NET: __tBox.SrcBox.content.value = string.Format(SourceFileDocPoolPattern, task.Document.FileFullPath)
        if (tBox.getSrcBox().getContent() != null) {
            tBox.getSrcBox().getContent().setValue(
                    String.format(SOURCE_FILE_DOC_POOL_PATTERN, doc.getFileFullPath()));
        }

        // Create BlocBox from TBox
        BlocBox blocBox = new BlocBox(task, task.getDestinationBlocName(),
                tBox.getSrcBox(), tBox.getSrcExtraBox());

        log.debug("DOC/RTF/XTG bloc [{}] created with path [{}]",
                task.getDestinationBlocName(), doc.getFileFullPath());

        return blocBox;
    }

    // ========================================================================
    // PDF format
    // Cross-reference: Process_Document.cs Process_File_PDF() lines 165-250
    // ========================================================================

    /**
     * PDF format: Multi-page handling with UPDATE/CREATE logic.
     * Compares PDF page count with existing box count in gabarit to determine:
     * - More blocs than PDFs → remove excess pages
     * - Same count → update existing blocs
     * - More PDFs than blocs → create new blocs and pages
     */
    private void processFilePdf(TaskDocument task) {
        log.debug("DocumentTaskProcessStrategy PDF: task [{}]", task.getId());

        DocumentDomain doc = task.getDocument();
        if (doc == null || doc.getPdfFiles().isEmpty()) {
            log.warn("PDF task [{}] has no PDF files, skipping", task.getId());
            return;
        }

        // Get list of existing box names starting with destination prefix in gabarit
        // .NET: task.Run.Gabarit.XML.GetListBoxNameStartWith(task.DestinationBlocName)
        QxpXml gabaritXml = task.getRun().getGabarit().getQxpXml();
        List<String> existingBoxNames = gabaritXml.getListBoxNameStartWith(task.getDestinationBlocName());

        if (existingBoxNames.isEmpty()) {
            log.warn("PDF task [{}] no existing blocs found for prefix [{}], skipping",
                    task.getId(), task.getDestinationBlocName());
            return;
        }

        int pdfFileCount = doc.getPdfFiles().size();
        int existingBoxCount = existingBoxNames.size();

        // Initialize image offset helper
        // .NET: task.Image_Offset = new Task_Image_Offset(task.Offset_Values)
        TaskImageOffset imageOffset = task.getImageOffset();
        if (imageOffset == null && task.getOffsetValues() != null) {
            imageOffset = new TaskImageOffset(task.getOffsetValues());
            task.setImageOffset(imageOffset);
        }

        // Initialize image position helper
        // .NET: task.Image_Position = new Task_Image_Position(task.Position_Values)
        TaskImagePosition imagePosition = task.getImagePosition();
        if (imagePosition == null && task.getPositionValues() != null) {
            imagePosition = new TaskImagePosition(task.getPositionValues());
            task.setImagePosition(imagePosition);
        }

        int maxPages = Math.max(pdfFileCount, existingBoxCount);

        for (int i = 0; i < maxPages; i++) {

            // CASE 1: More existing blocs than PDF pages → remove excess pages
            // .NET: if(__i < __lstBoxName.Count && __i >= task.Document.PDFFiles.Count)
            if (i < existingBoxCount && i >= pdfFileCount) {
                String blocName = String.format(PDF_BLOC_NAME_PATTERN,
                        task.getDestinationBlocName(), i + 1);
                BlocPage blocPage = new BlocPage(task, blocName);
                blocPage.setRelativePage(i);
                blocPage.setAction(BlocActionEnum.REMOVE);
                task.getBlocsModify().put(blocPage.getName(), blocPage);
            }
            // CASE 2: PDF page exists → create or update bloc
            else {
                String pdfFile = doc.getPdfFiles().get(i);
                String blocName = String.format("%s_%d", task.getDestinationBlocName(), i + 1);

                // Select template: PDF_1 for first page, PDF_N for subsequent
                StaticTElementNameEnum templateName;
                if (i == 0) {
                    templateName = StaticTElementNameEnum.PDF_1;
                } else {
                    templateName = StaticTElementNameEnum.PDF_N;
                }

                TElement tElement = TElementHelper.getTElement(templateName, blocName);
                if (!(tElement instanceof TBox)) {
                    log.warn("PDF task [{}] could not get TBox template for page [{}]",
                            task.getId(), i + 1);
                    continue;
                }

                TBox tBox = (TBox) tElement;

                // Set PDF file path as content value
                // .NET: __tBox.SrcBox.content.value = __doc.GetPDFFileAbsolutePath(__file)
                if (tBox.getSrcBox().getContent() != null) {
                    tBox.getSrcBox().getContent().setValue(pdfFile);
                }

                // Create BlocBox from TBox
                BlocBox blocBox = new BlocBox(task, blocName,
                        tBox.getSrcBox(), tBox.getSrcExtraBox());
                blocBox.setRelativePage(i);

                Box srcBox = blocBox.getSrcBox();
                Box extraBox = blocBox.getSrcExtraBox();

                // Set position for pages after the first
                // .NET: if (__i > 0) { set geometry position from Image_Position }
                if (i > 0 && imagePosition != null && srcBox != null
                        && srcBox.getGeometry() != null && srcBox.getGeometry().getPosition() != null) {
                    srcBox.getGeometry().getPosition().setLeft(imagePosition.getLeft());
                    srcBox.getGeometry().getPosition().setTop(imagePosition.getTop());
                    srcBox.getGeometry().getPosition().setRight(imagePosition.getRight());
                    srcBox.getGeometry().getPosition().setBottom(imagePosition.getBottom());
                }

                // Handle rotation and offset
                if (task.isRotationImage()) {
                    // Rotation: set angle on srcBox picture
                    if (tBox.getSrcBox() != null && tBox.getSrcBox().getPicture() != null) {
                        tBox.getSrcBox().getPicture().setAngle(PICTURE_ROTATION_90);
                    }
                    // Offset across on extraBox when rotated
                    if (extraBox != null && extraBox.getPicture() != null && imageOffset != null) {
                        extraBox.getPicture().setOffsetAcross(imageOffset.getOffset(i));
                    }
                } else {
                    // Offset down on extraBox when not rotated
                    if (extraBox != null && extraBox.getPicture() != null && imageOffset != null) {
                        extraBox.getPicture().setOffsetDown(imageOffset.getOffset(i));
                    }
                }

                // Determine action: UPDATE if box exists, CREATE if new
                // .NET: if(__i < __lstBoxName.Count) → UPDATE, else → CREATE (with new page)
                if (i < existingBoxCount) {
                    blocBox.setAction(BlocActionEnum.UPDATE);
                } else {
                    // Need to create a new page first
                    String pageName = String.format(PDF_PAGE_NAME_PATTERN, i, blocName);
                    BlocPage blocPage = new BlocPage(task, pageName);
                    blocPage.setAction(BlocActionEnum.CREATE);
                    blocPage.setRelativePage(i);
                    task.getBlocsModify().put(blocPage.getName(), blocPage);

                    // Then create the box
                    blocBox.setAction(BlocActionEnum.CREATE);
                }

                task.getBlocsModify().put(blocBox.getName(), blocBox);

                log.debug("PDF page [{}] bloc [{}] action={}", i + 1, blocName, blocBox.getAction());
            }
        }
    }

    // ========================================================================
    // QXP_Data format
    // Cross-reference: Process_Document.cs Process_File_QXP_Data() lines 86-162
    // ========================================================================

    /**
     * QXP_Data: Copy content from a previous QXP document.
     * Two modes based on conserverStyle flag:
     * - false (VALUE mode): Extract text value from source XML, store in blocsUpdate
     * - true (STYLE mode): Analyse source project, clone elements, store in blocsModify
     */
    private void processFileQxpData(TaskDocument task) {
        log.debug("DocumentTaskProcessStrategy QXP_DATA: task [{}] conserverStyle={}",
                task.getId(), task.isConserverStyle());

        // Both source and destination must be set
        if (task.getSourceBlocName() == null || task.getSourceBlocName().isBlank()
                || task.getDestinationBlocName() == null || task.getDestinationBlocName().isBlank()) {
            log.warn("QXP_DATA task [{}] requires both source and destination bloc names", task.getId());
            return;
        }

        DocumentDomain doc = task.getDocument();
        if (doc == null) {
            log.warn("QXP_DATA task [{}] has no document loaded, skipping", task.getId());
            return;
        }

        // If style mode, analyse the project structure first
        // .NET: if(task.Conserver_Style) { task.Document.QXPProject.Analyse(task, false); }
        if (task.isConserverStyle()) {
            doc.getQxpProject().analyse(task, false);
        }

        // Split pipe-separated source and destination names
        String[] sourceNames = task.getSourceBlocName().split("\\|");
        String[] destNames = task.getDestinationBlocName().split("\\|");

        // .NET has an unresolved TODO here: it iterates the SOURCE length and indexes the
        // DESTINATION array, so a mismatch would throw IndexOutOfRange. We instead surface a clear
        // run error and process only the safe overlap (no crash, no silent drop). (2 = Critique)
        if (sourceNames.length != destNames.length) {
            task.getRun().getErrors().add(new RunError(2,
                    "QXP_Data: nombre de blocs source (" + sourceNames.length
                            + ") different de la destination (" + destNames.length
                            + ") pour la tache " + task.getId()));
            log.warn("QXP_Data source/destination count mismatch ({} vs {}) for task [{}]",
                    sourceNames.length, destNames.length, task.getId());
        }
        int count = Math.min(sourceNames.length, destNames.length);

        for (int i = 0; i < count; i++) {
            String sourceName = sourceNames[i].trim();
            String destName = destNames[i].trim();

            if (sourceName.isEmpty() || destName.isEmpty()) {
                continue;
            }

            if (task.isConserverStyle()) {
                processQxpDataStyle(task, doc, sourceName, destName);
            } else {
                processQxpDataValue(task, doc, sourceName, destName);
            }
        }
    }

    /**
     * QXP_Data VALUE mode: Extract text value from source document XML.
     * Creates BlocBox in blocsUpdate with action UPDATE.
     *
     * Cross-reference: Process_Document.cs lines 152-158
     */
    private void processQxpDataValue(TaskDocument task, DocumentDomain doc,
                                     String sourceName, String destName) {
        // Extract value from source document's XML structure
        // .NET: string __bloc_Value = __doc.XML.GetValue(__sourceName)
        String blocValue = doc.getQxpXml().getValue(sourceName);

        BlocBox blocBox = new BlocBox(task, destName, blocValue);
        blocBox.setAction(BlocActionEnum.UPDATE);

        task.getBlocsUpdate().put(blocBox.getName(), blocBox);

        log.debug("QXP_DATA VALUE: bloc [{}] = [{}] from source [{}]",
                destName, blocValue, sourceName);
    }

    /**
     * QXP_Data STYLE mode: Clone element structure from source project.
     * Looks up source element in QXPProject.Elements, creates appropriate bloc type.
     * Supports TBox, TTable, and TGroup (TGroup not yet treated in .NET either).
     *
     * Cross-reference: Process_Document.cs lines 118-149
     */
    private void processQxpDataStyle(TaskDocument task, DocumentDomain doc,
                                     String sourceName, String destName) {
        Map<String, TElement> elements = doc.getQxpProject().getElements();

        if (elements == null || !elements.containsKey(sourceName)) {
            log.warn("QXP_DATA STYLE task [{}] source element [{}] not found in project",
                    task.getId(), sourceName);
            return;
        }

        TElement tElement = elements.get(sourceName);

        // Case 1: Source is a TBox
        // .NET: Bloc_Box __blocBox = new Bloc_Box(task, __destinationName, __tBox);
        //       __blocBox.Action = Bloc_Action.UPDATE;
        if (tElement instanceof TBox) {
            TBox srcTBox = (TBox) tElement;

            // Create a new TBox with style+value transferred from source
            TBox destTBox = TElementHelper.getNewTBoxStyleValueFromTBox(srcTBox, destName);
            if (destTBox == null) {
                log.warn("QXP_DATA STYLE task [{}] could not transfer TBox style for [{}]",
                        task.getId(), sourceName);
                return;
            }

            BlocBox blocBox = new BlocBox(task, destName,
                    destTBox.getSrcBox(), destTBox.getSrcExtraBox());
            blocBox.setAction(BlocActionEnum.UPDATE);

            // Check for duplicate bloc names
            if (task.getBlocsModify().containsKey(blocBox.getName())) {
                log.warn("QXP_DATA STYLE task [{}] duplicate bloc name [{}]",
                        task.getId(), blocBox.getName());
            } else {
                task.getBlocsModify().put(blocBox.getName(), blocBox);
            }

            log.debug("QXP_DATA STYLE TBox: bloc [{}] cloned from source [{}]",
                    destName, sourceName);
        }
        // Case 2: Source is a TTable
        // .NET: Bloc_Table __blocTable = new Bloc_Table(task, __destinationName, __tTable);
        //       __blocTable.Action = Bloc_Action.UPDATE;
        else if (tElement instanceof TTable) {
            TTable srcTTable = (TTable) tElement;

            TTable destTTable = TElementHelper.getNewTTableStyleValueFromTTable(srcTTable, destName);
            if (destTTable == null) {
                log.warn("QXP_DATA STYLE task [{}] could not transfer TTable style for [{}]",
                        task.getId(), sourceName);
                return;
            }

            BlocTable blocTable = new BlocTable(task, destName, destTTable.getSrcTable());
            blocTable.setAction(BlocActionEnum.UPDATE);

            if (task.getBlocsModify().containsKey(blocTable.getName())) {
                log.warn("QXP_DATA STYLE task [{}] duplicate bloc name [{}]",
                        task.getId(), blocTable.getName());
            } else {
                task.getBlocsModify().put(blocTable.getName(), blocTable);
            }

            log.debug("QXP_DATA STYLE TTable: bloc [{}] cloned from source [{}]",
                    destName, sourceName);
        }
        // Case 3: Source is a TGroup — not yet treated
        // .NET: "Pas traité pour le moment"
        else if (tElement instanceof TGroup) {
            log.debug("QXP_DATA STYLE TGroup: not yet treated for source [{}]", sourceName);
        }
    }
}
```

## 4. `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/CompartimentTaskProcessStrategy.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.business.GetCompartimentRunsBusiness;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.TaskCompartimentMode;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocPage;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBlocInfo;
import com.socgen.sgs.api.quark.engine.domain.element.TBox;
import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;
import com.socgen.sgs.api.quark.engine.domain.project.QxpProject;
import com.socgen.sgs.api.quark.engine.domain.task.TaskCompartiment;
import com.socgen.sgs.api.quark.engine.dto.RunIdDto;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Layout;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Spread;
import com.socgen.sgs.api.quark.engine.service.ProcessRunService;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessStrategy;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.SortedMap;
import java.util.TreeMap;

/**
 * Strategy for processing TaskCompartiment (sub-document generation and merging).
 *
 * <p>Three phases:
 * <ol>
 *   <li>Prepare_Runs: Load child run IDs from database, create Run objects</li>
 *   <li>Execute_Runs: Launch each child run through the full pipeline</li>
 *   <li>Render_Runs: Extract blocs from child QXP projects, rename, create pages</li>
 * </ol>
 *
 * Cross-reference: QXP.Engine.Core.Business.Process_Compartiment
 */
@Component
@Slf4j
public class CompartimentTaskProcessStrategy implements TaskProcessStrategy<TaskCompartiment> {

    /** Report type for compartiment child runs. */
    private static final int TYPE_RAPPORT_COMPARTIMENT = 4;

    /** Maximum length for old box names before adding suffix. */
    private static final int MAX_OLD_NAME_SIZE = 24;

    private static final String SUFFIXE_PATTERN = "_%s";
    private static final String NEW_PAGE_PATTERN = "T%d_P%d";
    private static final String DEF_BOX_NAME_PATTERN = "Box%s";
    private static final String OUT_OF_PAGE_CHAR = "*";
    private static final String QXPSDK_FALSE = "false";

    private final GetCompartimentRunsBusiness getCompartimentRunsBusiness;
    private final ProcessRunService processRunService;

    /**
     * Constructor with @Lazy on ProcessRunService to break circular dependency.
     * Circular: ProcessRunService → ProcessTasksService → strategies → this → ProcessRunService
     */
    public CompartimentTaskProcessStrategy(
            GetCompartimentRunsBusiness getCompartimentRunsBusiness,
            @Lazy ProcessRunService processRunService) {
        this.getCompartimentRunsBusiness = getCompartimentRunsBusiness;
        this.processRunService = processRunService;
    }

    @Override
    public Class<TaskCompartiment> getTaskType() {
        return TaskCompartiment.class;
    }

    @Override
    public void process(TaskCompartiment task) {
        log.debug("CompartimentTaskProcessStrategy processing task [{}]", task.getId());

        RunProperties props = task.getRun().getRunProperties();

        if (props.getCompartimentMode() == TaskCompartimentMode.UNKNOWN) {
            log.error("Unknown compartiment mode for task [{}]", task.getId());
            return;
        }

        // Phase 1: Prepare child runs
        if (task.isEvaluateRuns()) {
            prepareRuns(task);
        }

        // Phase 2: Execute child runs
        executeRuns(task);

        // Phase 3: Render — extract blocs from child run results
        renderRuns(task);

        // Free memory
        task.getChildRuns().clear();
    }

    // ========================================================================
    // Phase 1: Prepare_Runs
    // Cross-reference: Process_Compartiment.Prepare_Runs() lines 71-112
    // ========================================================================

    private void prepareRuns(TaskCompartiment task) {
        RunProperties props = task.getRun().getRunProperties();

        boolean toGenerate = (props.getCompartimentMode() == TaskCompartimentMode.GENERATE
                || props.getCompartimentMode() == TaskCompartimentMode.GENERATE_AND_INCORPORATE);

        LinkedHashMap<String, Integer> compartimentRuns = getCompartimentRunsBusiness.execute(
                props.getIdGabarit(),
                props.getIdFndCode(),
                task.getIdGabaritFils(),
                TYPE_RAPPORT_COMPARTIMENT,
                props.getIdLangue(),
                props.getDateEcheance(),
                toGenerate);

        if (compartimentRuns.isEmpty()) {
            // .NET: NoneRunCompartiment (2 = Critique)
            task.getRun().getErrors().add(new RunError(2,
                    "Aucun run compartiment trouve pour la tache " + task.getId()
                            + " (run " + task.getRun().getId() + ")"));
            log.warn("No compartment runs found for task [{}] in run [{}]",
                    task.getId(), task.getRun().getId());
            return;
        }

        for (Map.Entry<String, Integer> entry : compartimentRuns.entrySet()) {
            String compartimentCode = entry.getKey();
            int runId = entry.getValue();

            if (runId > 0) {
                Run childRun = new Run();
                childRun.setId(runId);
                RunProperties childProps = new RunProperties();
                childProps.setIdFndCode(compartimentCode);
                childProps.setRunId(runId);
                childRun.setRunProperties(childProps);
                task.getChildRuns().add(childRun);
            } else {
                // .NET: EmptyRunCompartiment (2 = Critique)
                task.getRun().getErrors().add(new RunError(2,
                        "Compartiment [" + compartimentCode + "] sans run pour la tache "
                                + task.getId() + " (run " + task.getRun().getId() + ")"));
                log.warn("No run found for compartment [{}] in task [{}], run [{}]",
                        compartimentCode, task.getId(), task.getRun().getId());
            }
        }
    }

    // ========================================================================
    // Phase 2: Execute_Runs
    // Cross-reference: Process_Compartiment.Execute_Runs() lines 118-132
    // ========================================================================

    private void executeRuns(TaskCompartiment task) {
        for (Run childRun : task.getChildRuns()) {
            try {
                log.info("Launching child run [{}] for compartiment task [{}]",
                        childRun.getId(), task.getId());
                processRunService.runProcessor(new RunIdDto(childRun.getId()));
                log.info("Child run [{}] completed for compartiment task [{}]",
                        childRun.getId(), task.getId());
            } catch (Exception e) {
                log.error("Error executing child run [{}] for task [{}]: {}",
                        childRun.getId(), task.getId(), e.getMessage(), e);
            }
        }
    }

    // ========================================================================
    // Phase 3: Render_Runs
    // Cross-reference: Process_Compartiment.Render_Runs() lines 138-195
    // ========================================================================

    private void renderRuns(TaskCompartiment task) {
        int lastPage = 0;

        RunProperties props = task.getRun().getRunProperties();
        boolean incorporate = (props.getCompartimentMode() == TaskCompartimentMode.INCORPORATE
                || props.getCompartimentMode() == TaskCompartimentMode.GENERATE_AND_INCORPORATE);

        if (!incorporate) {
            // Nothing to incorporate — mark task as not todo
            task.setTodo(false);
            return;
        }

        // Extract blocs from each child run
        for (Run childRun : task.getChildRuns()) {
            lastPage = addRunBlocs(task, childRun, lastPage);
        }

        // 1. If no blocs generated, create one empty page
        if (task.getBlocsModify().isEmpty()) {
            BlocPage blocPage = new BlocPage(task,
                    String.format(NEW_PAGE_PATTERN, task.getId(), 0));
            blocPage.setAction(BlocActionEnum.CREATE);
            blocPage.setRelativePage(0);
            task.getBlocsModify().put(blocPage.getName(), blocPage);
            lastPage++;
        }

        // 2. Get anchor info
        DBlocInfo startInfo = task.getStartAnchor();
        DBlocInfo endInfo = task.getEndAnchor();

        // 3. Remove old pages between anchors (inclusive: <= not <)
        // .NET: for (int __i = 0; __i <= __nb_Ancien_Page; __i++)
        int nbAnciennePage = endInfo.getPage() - startInfo.getPage();
        for (int i = 0; i <= nbAnciennePage; i++) {
            int relativeRemovePage = lastPage + i;
            BlocPage blocPage = new BlocPage(task,
                    String.format(NEW_PAGE_PATTERN, task.getId(), relativeRemovePage));
            blocPage.setAction(BlocActionEnum.REMOVE);
            blocPage.setRelativePage(relativeRemovePage);
            task.getBlocsModify().put(blocPage.getName(), blocPage);
        }

        // 4. Move start anchor to first new page
        BlocBox blocStart = TElementHelper.getMoveAnchor(task, startInfo, 0);
        if (blocStart != null) {
            blocStart.setPagination(true);
            task.getBlocsModify().put(blocStart.getName(), blocStart);
        }

        // 5. Move end anchor to last new page
        BlocBox blocEnd = TElementHelper.getMoveAnchor(task, endInfo, lastPage - 1);
        if (blocEnd != null) {
            blocEnd.setPagination(true);
            task.getBlocsModify().put(blocEnd.getName(), blocEnd);
        }
    }

    // ========================================================================
    // Add_Run_Blocs + Add_Blocs
    // Cross-reference: Process_Compartiment.Add_Run_Blocs() lines 203-220
    //                  Process_Compartiment.Add_Blocs() lines 230-330
    // ========================================================================

    private int addRunBlocs(TaskCompartiment task, Run childRun, int lastPage) {
        if (childRun.getGabarit() == null) {
            log.warn("Child run [{}] has no gabarit (final QXP), skipping", childRun.getId());
            return lastPage;
        }

        QxpProject qxpProject = childRun.getGabarit().getQxpProject();
        if (qxpProject == null || qxpProject == QxpProject.EMPTY) {
            log.warn("Child run [{}] has no QXP project, skipping", childRun.getId());
            return lastPage;
        }

        return addBlocs(task, qxpProject, childRun, lastPage);
    }

    private int addBlocs(TaskCompartiment task, QxpProject qxpProject,
                         Run childRun, int lastPage) {
        Project project = qxpProject.getProject();
        String standardSuffix = childRun.getRunProperties().getIdFndCode();

        // Group boxes by page (sorted by page number for correct ordering)
        SortedMap<Integer, List<BlocBox>> boxesByPage = new TreeMap<>();

        log.debug("Analysing child run [{}] project structure", childRun.getId());

        if (project.getLayouts() != null) {
            for (Layout layout : project.getLayouts()) {
                if (layout == null || layout.getSpreads() == null) {
                    continue;
                }
                for (Spread spread : layout.getSpreads()) {
                    if (spread == null || spread.getBoxes() == null) {
                        continue;
                    }
                    for (Box box : spread.getBoxes()) {
                        if (box == null || box.getGeometry() == null
                                || box.getGeometry().getPage() == null) {
                            continue;
                        }

                        String pageName = box.getGeometry().getPage();

                        // Skip boxes on pasteboard (page ends with *)
                        if (pageName.endsWith(OUT_OF_PAGE_CHAR)) {
                            continue;
                        }

                        int currentPageId;
                        try {
                            currentPageId = Integer.parseInt(pageName.trim());
                        } catch (NumberFormatException e) {
                            log.warn("Cannot parse page [{}] for box [{}]", pageName, box.getName());
                            continue;
                        }

                        // Rename box (must be BEFORE clearing UID)
                        box.setName(renameBloc(box, standardSuffix));

                        // Clear UID (must be AFTER rename)
                        box.setUID(null);

                        // Create BlocBox with CREATE action
                        BlocBox blocBox = new BlocBox(task, box.getName(), box, null);
                        blocBox.setAction(BlocActionEnum.CREATE);

                        boxesByPage.computeIfAbsent(currentPageId, k -> new ArrayList<>())
                                .add(blocBox);
                    }
                }
            }
        }

        // Process pages in order — only include pages with at least one visible box
        // .NET: suppressOutput == "false" means the box IS visible (not suppressed)
        for (Map.Entry<Integer, List<BlocBox>> entry : boxesByPage.entrySet()) {
            List<BlocBox> pageBoxes = entry.getValue();

            boolean hasVisibleBox = pageBoxes.stream()
                    .anyMatch(bloc -> {
                        Box srcBox = bloc.getSrcBox();
                        return srcBox != null
                                && srcBox.getGeometry() != null
                                && QXPSDK_FALSE.equals(srcBox.getGeometry().getSuppressOutput());
                    });

            if (hasVisibleBox) {
                // Create page
                BlocPage blocPage = new BlocPage(task,
                        String.format(NEW_PAGE_PATTERN, task.getId(), lastPage));
                blocPage.setAction(BlocActionEnum.CREATE);
                blocPage.setRelativePage(lastPage);
                task.getBlocsModify().put(blocPage.getName(), blocPage);

                // Add all boxes on this page
                for (BlocBox blocBox : pageBoxes) {
                    blocBox.setRelativePage(lastPage);
                    task.getBlocsModify().put(blocBox.getName(), blocBox);
                }

                lastPage++;
            }
        }

        log.debug("Extracted boxes from child run [{}], lastPage=[{}]", childRun.getId(), lastPage);
        return lastPage;
    }

    // ========================================================================
    // Rename_Bloc
    // Cross-reference: Process_Compartiment.Rename_Bloc() lines 340-365
    // ========================================================================

    private String renameBloc(Box box, String suffix) {
        String oldName = box.getName();
        String defName = String.format(DEF_BOX_NAME_PATTERN, box.getUID());
        String suffixStr = String.format(SUFFIXE_PATTERN, suffix);

        // Check if name is defined and not the default Quark pattern "BoxUID"
        if (oldName != null && !oldName.isBlank() && !oldName.equals(defName)) {
            // Truncate to max length
            String newName = oldName.length() > MAX_OLD_NAME_SIZE
                    ? oldName.substring(0, MAX_OLD_NAME_SIZE)
                    : oldName;

            // Only add suffix if not already present
            if (!newName.endsWith(suffixStr)) {
                newName = newName + suffixStr;
            }
            return newName;
        } else {
            return TElementHelper.newBlocName();
        }
    }
}
```

