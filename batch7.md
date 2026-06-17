# EOS Quark — Batch 7 Changes (copy-paste)

**Batch 7 (part A) = self-contained correctness fixes.** The remaining Batch 7 items depend on missing sub-systems or decisions and are flagged below (NOT half-implemented).

**Implemented (3 files, verified vs .NET):**
- **SQL exception validations** (`ProcessSqlBusiness.checkTaskExceptions`) — restored the three .NET guards: bloc-name `Exist_Name` (else `InvalidCondBloc` error + skip), table `Exist_Name` (else `TableNotExist` error), and LINE `GetNbLignes(table) >= maxRow` (else `MissingTableRows` error). Was emitting REMOVE blocs for non-existent tables/rows with no error.
- **Run-error propagation** (`QxpProject.evaluatePendingGroups`) — TGroup evaluation failures are now recorded on the run (was a TODO/log-only) — .NET `task.Run.Errors.Add`.
- **ModifierSpread page operation** (`ModifierSpread.getSdkPages`) — now driven by `Task.Properties.Task_Action` first (NONE → bloc action, REMOVE → DELETE, else → CREATE), matching .NET `Spread.GetSDKPages()`. Was switching on the bloc action only → wrong page `operation` in some cases.

## How to apply
Each section is one file — replace its entire contents with the block. Paths relative to the `quark-engine` module root. Then `mvn -DskipTests compile` and `mvn test`.

## Checklist (3 files)
- [ ] `business/ProcessSqlBusiness.java` — CHANGED
- [ ] `domain/project/QxpProject.java` — CHANGED
- [ ] `domain/modifier/ModifierSpread.java` — CHANGED

---

## 1. `src/main/java/com/socgen/sgs/api/quark/engine/business/ProcessSqlBusiness.java`  — **CHANGED**

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

    /** RunError categories: 1=Bloquante, 2=Critique, 3=Warning. */
    private static final int CRITIQUE = 2;

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
        boolean storeData = task.isStoreData()
                && (task.getRun().getRunProperties().getStoreDataType().getCode() & StoreDataType.SQL.getCode()) != 0;

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

## 2. `src/main/java/com/socgen/sgs/api/quark/engine/domain/project/QxpProject.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.domain.project;

import com.socgen.sgs.api.quark.engine.domain.element.TBox;
import com.socgen.sgs.api.quark.engine.domain.element.TElement;
import com.socgen.sgs.api.quark.engine.domain.element.TGroup;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.element.TTable;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Group;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Layout;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Spread;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Table;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Represents an advanced structure of a QuarkXPress project.
 * Analyses the SOAP Project object model to build a dictionary of named elements
 * (TBox, TTable, TGroup) that can be looked up by name.
 *
 * <p>The {@link #analyse(TaskBase, boolean)} method iterates through all
 * layouts → spreads → boxes/tables/groups and populates the elements dictionary.
 * This dictionary is then used by tasks (e.g., QXP_Data STYLE mode) to find
 * and clone source elements.
 *
 * <p>Usage:
 * <pre>
 *   QxpProject project = new QxpProject(soapProject);
 *   project.analyse(task, false);
 *   TElement element = project.getElements().get("MY_BOX_NAME");
 * </pre>
 *
 * Cross-reference: QXP.Engine.Core.QXP_Project
 */
@Getter
@Slf4j
public class QxpProject {

    /** The underlying SOAP project structure. */
    private final Project project;

    /** Named elements dictionary, populated by {@link #analyse(TaskBase, boolean)}. */
    private Map<String, TElement> elements;

    /** Whether the project has already been analysed. */
    private boolean analysed = false;

    /** Empty QxpProject singleton (non-null but contains no elements). */
    public static final QxpProject EMPTY = new QxpProject(new Project());

    /**
     * Create a QxpProject from a SOAP Project.
     *
     * @param project the SOAP-generated Project
     */
    public QxpProject(Project project) {
        this.project = project;
    }

    /**
     * Analyse the project structure to build the elements dictionary.
     * Iterates through all layouts → spreads → boxes/tables/groups,
     * creating TBox/TTable/TGroup instances and adding them to the elements map.
     *
     * <p>This method is idempotent — calling it multiple times has no effect
     * after the first successful analysis.
     *
     * @param task     a reference to the calling task (for error logging to run)
     * @param logError if true, structural errors are logged to the run's error list;
     *                 if false, errors are silently ignored
     */
    public void analyse(TaskBase task, boolean logError) {
        // Don't re-analyse if already done
        if (analysed) {
            return;
        }

        elements = new LinkedHashMap<>();
        List<TGroup> pendingGroups = new ArrayList<>();

        if (project.getLayouts() == null) {
            analysed = true;
            return;
        }

        for (Layout layout : project.getLayouts()) {
            if (layout == null || layout.getSpreads() == null) {
                continue;
            }

            for (Spread spread : layout.getSpreads()) {
                if (spread == null) {
                    continue;
                }

                // Process boxes
                processBoxes(spread);

                // Process tables
                processTables(spread);

                // Process groups (collect first, evaluate after all elements are registered)
                processGroups(spread, pendingGroups);
            }
        }

        // Evaluate all groups after all boxes/tables are in the elements map.
        // Groups reference boxes by name via boxRefs, so boxes must be registered first.
        evaluatePendingGroups(pendingGroups, task, logError);

        analysed = true;
    }

    /**
     * Process all boxes in a spread.
     * Creates TBox instances and adds them to the elements dictionary.
     */
    private void processBoxes(Spread spread) {
        if (spread.getBoxes() == null) {
            return;
        }

        for (Box box : spread.getBoxes()) {
            if (box == null) {
                continue;
            }

            TBox tBox = new TBox(box);

            // Some documents have duplicate box names (legacy QXP Server 7 bug)
            if (!elements.containsKey(tBox.getName())) {
                elements.put(tBox.getName(), tBox);
                tBox.evaluate(this);
            } else {
                log.debug("Duplicate box name [{}] — skipping", tBox.getName());
            }
        }
    }

    /**
     * Process all tables in a spread.
     * Creates TTable instances and adds them to the elements dictionary.
     */
    private void processTables(Spread spread) {
        if (spread.getTables() == null) {
            return;
        }

        for (Table table : spread.getTables()) {
            // QXP Server v9 bug: there's always a null table even when none exist
            if (table == null) {
                continue;
            }

            TTable tTable = new TTable(table);

            if (!elements.containsKey(tTable.getName())) {
                elements.put(tTable.getName(), tTable);
                tTable.evaluate(this);
            } else {
                log.debug("Duplicate table name [{}] — skipping", tTable.getName());
            }
        }
    }

    /**
     * Process all groups in a spread.
     * Creates TGroup instances, adds them to the elements dictionary,
     * and collects them for deferred evaluation.
     *
     * <p>Groups are evaluated after all boxes and tables are registered
     * because groups reference child elements via boxRefs.
     */
    private void processGroups(Spread spread, List<TGroup> pendingGroups) {
        if (spread.getGroups() == null) {
            return;
        }

        for (Group group : spread.getGroups()) {
            // QXP Server v9 bug: there's always a null group even when none exist
            if (group == null) {
                continue;
            }

            TGroup tGroup = new TGroup(group);

            if (!elements.containsKey(tGroup.getName())) {
                elements.put(tGroup.getName(), tGroup);
                pendingGroups.add(tGroup);
            } else {
                log.debug("Duplicate group name [{}] — skipping", tGroup.getName());
            }
        }
    }

    /**
     * Evaluate all pending groups.
     * Called after all boxes/tables/groups are registered in the elements map.
     *
     * @param pendingGroups the groups to evaluate
     * @param task          the calling task (for error logging)
     * @param logError      whether to log structural errors to the run
     */
    private void evaluatePendingGroups(List<TGroup> pendingGroups, TaskBase task, boolean logError) {
        for (TGroup tGroup : pendingGroups) {
            try {
                tGroup.evaluate(this);
            } catch (Exception e) {
                if (logError && task != null) {
                    log.error("Error evaluating TGroup [{}]: {}", tGroup.getName(), e.getMessage());
                    // Cross-reference: .NET QXP_Project — task.Run.Errors.Add(tex.ToString()). (2 = Critique)
                    task.getRun().getErrors().add(new RunError(2,
                            "Erreur evaluation du groupe [" + tGroup.getName() + "] : " + e.getMessage()));
                } else {
                    log.debug("Error evaluating TGroup [{}]: {}", tGroup.getName(), e.getMessage());
                }
            }
        }
    }
}
```

## 3. `src/main/java/com/socgen/sgs/api/quark/engine/domain/modifier/ModifierSpread.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.domain.modifier;

import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.enums.TaskActionTypeEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.DeleteCells;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Geometry;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Page;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Spread;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Table;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import lombok.Getter;
import lombok.Setter;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Represents a spread in a modifier project hierarchy.
 * Aggregates boxes, pages, tables, and groups, then converts them to SOAP SDK objects.
 *
 * Cross-reference: QXP.Engine.Core.Spread (Modifier namespace)
 */
@Getter
@Setter
public class ModifierSpread {

    private static final String BLOC_OPERATION_CREATE = "CREATE";
    private static final String BLOC_OPERATION_DELETE = "DELETE";

    private String uid;
    private final Map<String, ModifierBox> boxes = new LinkedHashMap<>();
    private final Map<String, ModifierBox> boxesExtra = new LinkedHashMap<>();
    private final Map<String, ModifierGroup> groups = new LinkedHashMap<>();
    private final Map<String, ModifierTable> tables = new LinkedHashMap<>();
    private final Map<String, ModifierPage> pages = new LinkedHashMap<>();
    private boolean create = false;

    public ModifierSpread() {
    }

    /**
     * Build SDK Box array from normal boxes.
     * Cross-reference: .NET Spread.GetSDKBoxes()
     */
    public Box[] getSdkBoxes() {
        List<Box> destBoxes = new ArrayList<>();

        // Normal boxes
        destBoxes.addAll(evaluateSdkBoxes(boxes, false));

        // Groups
        for (ModifierGroup grp : groups.values()) {
            if (grp.getSrcBoxes() != null) {
                for (Box newBox : grp.getSrcBoxes()) {
                    newBox.setOperation(BLOC_OPERATION_CREATE);
                    newBox.setUID("");
                    destBoxes.add(newBox);
                    if (newBox.getGeometry() == null) {
                        newBox.setGeometry(new Geometry());
                    }
                    newBox.getGeometry().setPage(String.valueOf(grp.getPageId()));
                }
            }
        }

        return destBoxes.toArray(new Box[0]);
    }

    /**
     * Build SDK Box array from extra boxes.
     * Cross-reference: .NET Spread.GetSDKBoxesExtra()
     */
    public Box[] getSdkBoxesExtra() {
        List<Box> destBoxes = new ArrayList<>(evaluateSdkBoxes(boxesExtra, true));
        return destBoxes.toArray(new Box[0]);
    }

    private List<Box> evaluateSdkBoxes(Map<String, ModifierBox> boxMap, boolean ignoreOperation) {
        List<Box> destBoxes = new ArrayList<>();
        for (ModifierBox bx : boxMap.values()) {
            Box box = bx.getSrcBox();
            switch (bx.getAction()) {
                case CREATE:
                    if (!ignoreOperation) {
                        box.setOperation(BLOC_OPERATION_CREATE);
                    }
                    box.setUID("");
                    if (box.getGeometry() == null) {
                        box.setGeometry(new Geometry());
                    }
                    box.getGeometry().setPage(String.valueOf(bx.getPageId()));
                    break;
                case MOVE:
                    if (box.getGeometry() != null) {
                        box.getGeometry().setPage(String.valueOf(bx.getPageId()));
                    }
                    break;
                default:
                    break;
            }
            destBoxes.add(box);
        }
        return destBoxes;
    }

    /**
     * Build SDK Table array.
     * Cross-reference: .NET Spread.GetSDKTables()
     */
    public Table[] getSdkTables() {
        List<Table> sdkTables = new ArrayList<>();

        for (ModifierTable tab : tables.values()) {
            if (tab.getAction() == BlocActionEnum.REMOVE) {
                Table table = new Table();
                table.setName(tab.getName());
                table.setOperation(BLOC_OPERATION_DELETE);
                sdkTables.add(table);
            } else if (tab.getTask() != null
                    && tab.getTask().getSubTaskType() == SubTaskTypeEnum.FILE_QXP_PREVIOUS
                    && tab.getSrcTable() != null) {
                Table table = tab.getSrcTable();
                table.setName(tab.getName());
                sdkTables.add(table);
            } else {
                Table table = new Table();
                table.setName(tab.getName());

                List<ModifierLigne> lignes = new ArrayList<>(tab.getLignes().values());
                lignes.sort(Comparator.comparingInt(ModifierLigne::getIndex).reversed());

                List<DeleteCells> deleteCellsList = new ArrayList<>();
                for (ModifierLigne ligne : lignes) {
                    DeleteCells dc = new DeleteCells();
                    dc.setType("ROW");
                    dc.setBaseIndex(String.valueOf(ligne.getIndex()));
                    dc.setDeleteCount("1");
                    deleteCellsList.add(dc);
                }
                if (!deleteCellsList.isEmpty()) {
                    table.setDeleteCells(deleteCellsList.toArray(new DeleteCells[0]));
                    sdkTables.add(table);
                }
            }
        }

        return sdkTables.toArray(new Table[0]);
    }

    /**
     * Build SDK Page array.
     * Cross-reference: .NET Spread.GetSDKPages()
     */
    public Page[] getSdkPages() {
        List<Page> sdkPages = new ArrayList<>();

        for (ModifierPage pg : pages.values()) {
            Page page = new Page();
            page.setUID(pg.getUid());

            // Page operation is driven first by the task's action, then (only when NONE) by the
            // bloc that created the page. Cross-reference: .NET Spread.GetSDKPages().
            TaskActionTypeEnum taskAction = (pg.getTask() != null && pg.getTask().getProperties() != null)
                    ? pg.getTask().getProperties().getTaskAction()
                    : TaskActionTypeEnum.NONE;

            String operation = null;
            switch (taskAction) {
                case NONE:
                    switch (pg.getAction()) {
                        case REMOVE:
                            operation = BLOC_OPERATION_DELETE;
                            break;
                        case CREATE:
                            operation = BLOC_OPERATION_CREATE;
                            break;
                        default:
                            break;
                    }
                    break;
                case REMOVE:
                    operation = BLOC_OPERATION_DELETE;
                    break;
                default: // UPDATE / CREATE → page creation
                    operation = BLOC_OPERATION_CREATE;
                    break;
            }

            page.setOperation(operation);

            if (BLOC_OPERATION_CREATE.equals(operation)) {
                if (pg.getTask() != null && pg.getTask().getMasterPage() != null) {
                    page.setMaster(pg.getTask().getMasterPage().getMasterPageId(0));
                }
                page.setPosition(pg.getPosition());

                if (pg.getIndexPosition() == 0) {
                    this.create = true;
                }
            }
            sdkPages.add(page);

            // Dummy page handling for double-page layouts
            if (pg.isCreateDummyNextPage()) {
                String nextPageId = String.valueOf(Integer.parseInt(pg.getUid()) + 1);

                Page dummyCreate = new Page();
                dummyCreate.setUID(nextPageId);
                dummyCreate.setOperation(BLOC_OPERATION_CREATE);
                sdkPages.add(dummyCreate);

                Page dummyDelete = new Page();
                dummyDelete.setUID(nextPageId);
                dummyDelete.setOperation(BLOC_OPERATION_DELETE);
                sdkPages.add(dummyDelete);
            }
        }

        return sdkPages.toArray(new Page[0]);
    }
}
```

---

## Deferred / needs decision (NOT in this file)
1. **End_Run audit insert** — .NET calls `QXP_PK_AUDIT.InsertAuditRun` (p_id_run, p_id_suivi, p_run_type, p_start/end_date, p_duration, p_end_status, p_message). Needs: confirm the `QXP_PK_AUDIT` package exists in your Oracle, a Java `Audit` object + DAO, and how `run_type` maps. Tell me and I will add it.
2. **End_Run trace log (CLOB `p_log_trace`)** — .NET passes `Run.Trace_Context.All_Logs` (the accumulated in-memory run log). Java uses slf4j (no in-memory accumulation). Needs a small run-scoped trace collector. Currently passed empty/null. Want me to build the collector?
3. **Compartiment** Run vs Run_Previous distinction + `EmptyRunChildQXP`/`EmptyRunChildProject` errors — moderate; planned as a focused follow-up.
4. **Dynamique page-break else-branch** (`__current_Break_Rows`) — header/break-row reuse on page break; planned as a focused follow-up.
5. **DocumentTaskProcessStrategy** QXP_Data source/dest **count-mismatch** error — needs the exact .NET behavior confirmed.
6. **Word/DOC generation** — intentionally skipped in BOTH .NET (commented) and Java (idDoc=MIN_VALUE). No change = parity.
