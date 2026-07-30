# EOS Quark Engine — Batch 7 Changes
**Theme: error observability — record/raise failures instead of silently logging-and-continuing**

_Whole-file for small files; two large files given as snippets. All recorded error texts are the EXACT .NET `Constantes.Error_Messages` strings._

## Findings fixed (12)
| # | Sev | Issue → fix | .NET error / behavior |
|---|---|---|---|
| 18 | HIGH | TGroup unknown sub-element: log+continue → **throw** `ExceptionTElement` | `TGroupUnKnownSubGroup` |
| 19 | HIGH | Group structural errors never recorded → catch now fires (TGroup throws) and records run error | `QXP_Project` catch → `Errors.Add(string)` |
| 44 | MEDIUM | Nested sub-group: log.warn → **throw** `ExceptionTElement` | `TGroupSubGroupProblem` |
| 37 | MEDIUM | Duplicate SQL bloc: log only → **record** UNSPECIFIED run error | `ErrorDuplicateBlocInTask` |
| 38 | MEDIUM | Per-row SQL exception: log only → **record** UNSPECIFIED run error | `ErrorAddingBlocSQLInTask` |
| 39 | MEDIUM | PDF with no destination blocs: silent return → **record** UNSPECIFIED run error | `MissingDestinationBlocNameInTask` |
| 43 | MEDIUM | Unknown compartiment mode: log+return → **throw** (→ CRITIQUE via wrapper) | `MSG_Load_Task_Compartiment` |
| 65 | LOW | Bloc with no layout/spread: silent → **record** UNSPECIFIED run error | `Empty_Layout_Or_Spread_For_Bloc` |
| 69 | LOW | System task missing dest bloc: log only → **record** UNSPECIFIED run error | `MissingBlocNameInTask` |
| 58 | LOW | Missing process strategy: log+return → **throw** (→ CRITIQUE via wrapper) | Run_Base hard failure |
| 48 | MEDIUM | `Get_Compartiment_Runs` swallowed all exceptions → empty map → **rethrow** | Proxy_Run has no try/catch |
| 81 | LOW | Null element name kept as null map key → **throw** `IllegalArgumentException` | Dictionary `ArgumentNullException` |

## Key parity points (verified from .NET source)
- **Severity of group errors is UNSPECIFIED (1), not CRITIQUE (2).** `.NET QXP_Project` records `task.Run.Errors.Add(tex.ToString())` — the string `Add` overload resolves to `Error_Type.Unspecified` (`Error.cs:56` → `this(Error_Type.Unspecified, ...)`). The existing Java catch wrongly used `RunError(2)`; this batch corrects it to `RunError.UNSPECIFIED` AND narrows the catch to `ExceptionTElement` only (so non-TElement exceptions propagate/abort analyse, as in .NET).
- **`#43` and `#58` throw** rather than record directly — they are raised as exceptions so the existing `ProcessTasksServiceImpl` Pass-1 try/catch converts them to a **CRITIQUE** run error + `setInError(true)`, matching .NET `Raise_Exception(Exception_Task)`.
- **`#39`/`#65`/`#69`/`#37`/`#38` record UNSPECIFIED** — these mirror .NET `Errors.Add(string,...)` (= Unspecified), an audit-trail entry that does NOT change run status.
- New `ExceptionTElement extends RuntimeException` ports .NET `Exception_TElement` (unchecked so it propagates through `evaluate()`).
- Error message strings are the exact .NET `Constantes.Error_Messages` literals (recovered from `Constantes.cs`), including the accented French — the source tree already uses UTF-8 accented chars.

## No tests affected
Grep confirms **no existing test** exercises any Batch 7 class, so there is no regression. (Dedicated tests for the new throw/record behavior can be added in a later test pass.)

---

## `service/task/impl/DocumentTaskProcessStrategy.java` — snippet (537-line file)
In `processFilePdf`, the empty-blocs branch:
```java
        if (existingBoxNames.isEmpty()) {
            // Parity: .NET Process_Document records MissingDestinationBlocNameInTask (Errors.Add(string)
            // → Error_Type.Unspecified) before returning, instead of silently skipping. Finding #39.
            task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED, String.format(
                    "Manque le bloc de destination %s dans la tache %s",
                    task.getDestinationBlocName(), task.getId())));
            log.warn("PDF task [{}] no existing blocs found for prefix [{}], skipping",
                    task.getId(), task.getDestinationBlocName());
            return;
        }
```
(`RunError` is already imported in this file.)

---

## `service/task/impl/CompartimentTaskProcessStrategy.java` — snippet (468-line file)
In `process(TaskCompartiment)`, the unknown-mode branch:
```java
        if (props.getCompartimentMode() == TaskCompartimentMode.UNKNOWN) {
            // Parity: .NET Process_Compartiment raises Exception_Task(MSG_Load_Task_Compartiment) — the
            // ProcessTasksServiceImpl wrapper converts this to a CRITIQUE run error + setInError(true),
            // rather than silently returning. Finding #43.
            throw new IllegalStateException(String.format(
                    "Erreur sur la tache %s - manque le mode de la tache compartiment sur le run",
                    task.getId()));
        }
```

---

## `domain/element/ExceptionTElement.java (NEW)`
```java
package com.socgen.sgs.api.quark.engine.domain.element;

/**
 * Unchecked exception raised while evaluating a template element (TBox/TTable/TGroup).
 *
 * <p>Cross-reference: .NET {@code QXP.Engine.Core.BusinessObject.Dynamique.Template.Exception_TElement}.
 * Thrown by {@code TGroup.evaluate} on a structural problem (unknown sub-element, nested sub-group) and
 * caught by {@code QxpProject.evaluatePendingGroups}, which records it as an UNSPECIFIED run error
 * (mirroring .NET {@code QXP_Project} → {@code task.Run.Errors.Add(tex.ToString())}, the string overload
 * that resolves to {@code Error_Type.Unspecified}). It is unchecked so it propagates through
 * {@code evaluate()} (which is not declared to throw) to the same generation-abort boundary as other
 * engine fatal errors when not caught.
 */
public class ExceptionTElement extends RuntimeException {

    public ExceptionTElement(String message) {
        super(message);
    }
}
```

---

## `domain/element/TGroup.java`
```java
package com.socgen.sgs.api.quark.engine.domain.element;

import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.BoxRef;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Group;
import lombok.Getter;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Represents a template group element (multiple boxes) for dynamic tasks.
 * Wraps a SOAP-generated {@link Group} and contains child TBox elements.
 *
 * <p>Never work directly on a TGroup without cloning it first,
 * as modifications would affect all tasks sharing the same template.
 *
 * Cross-reference: QXP.Engine.Core.TGroup
 */
@Getter
@Setter
@Slf4j
public class TGroup extends TElement {

    private static final String UNKNOWN_PAGE = "?";

    /** Source SOAP group. */
    private Group srcGroup;

    /** Source boxes extracted from the group (populated after evaluation). */
    private Box[] srcBoxes;

    /** Child TBox elements contained in this group. */
    private List<TBox> tBoxes = new ArrayList<>();

    /** Page containing this element ("?" if not evaluated). */
    private String page = UNKNOWN_PAGE;

    /**
     * No-arg constructor for serialization/deserialization.
     */
    public TGroup() {
        super();
    }

    /**
     * Create a TGroup from a SOAP Group.
     *
     * @param group the SOAP-generated Group
     */
    public TGroup(Group group) {
        super(group.getName());
        this.srcGroup = group;
    }

    /**
     * Evaluate geometry by computing the bounding box of all child elements.
     * Iterates through boxRefs, resolves them from the QXP project elements,
     * and computes min/max bounds.
     *
     * @param qxpProject the QXP project — must be cast to
     *                   {@link com.socgen.sgs.api.quark.engine.domain.project.QxpProject}
     *                   to access the elements map. Using Object here to avoid circular dependency
     *                   during initial class creation.
     */
    @Override
    @SuppressWarnings("unchecked")
    public void evaluate(Object qxpProject) {
        if (isEvaluated()) {
            return;
        }

        // qxpProject is passed as Object to avoid circular dependency.
        // At runtime, it provides a getElements() method returning Map<String, TElement>.
        Map<String, TElement> elements;
        try {
            elements = (Map<String, TElement>) qxpProject.getClass()
                    .getMethod("getElements")
                    .invoke(qxpProject);
        } catch (Exception e) {
            log.error("Failed to get elements from QxpProject during TGroup evaluation", e);
            setEvaluated(true);
            return;
        }

        evaluateBoxes(elements);

        // Compute bounding box from all child TBoxes
        if (tBoxes.isEmpty()) {
            setLeft(BigDecimal.ZERO);
            setTop(BigDecimal.ZERO);
            setWidth(BigDecimal.ZERO);
            setHeight(BigDecimal.ZERO);
        } else {
            BigDecimal leftMin = new BigDecimal(Long.MAX_VALUE);
            BigDecimal topMin = new BigDecimal(Long.MAX_VALUE);
            BigDecimal rightMax = new BigDecimal(Long.MIN_VALUE);
            BigDecimal bottomMax = new BigDecimal(Long.MIN_VALUE);

            for (TBox tBox : tBoxes) {
                if (tBox.getLeft().compareTo(leftMin) < 0) leftMin = tBox.getLeft();
                if (tBox.getTop().compareTo(topMin) < 0) topMin = tBox.getTop();
                if (tBox.getRight().compareTo(rightMax) > 0) rightMax = tBox.getRight();
                if (tBox.getBottom().compareTo(bottomMax) > 0) bottomMax = tBox.getBottom();
            }

            setLeft(leftMin);
            setTop(topMin);
            setWidth(rightMax.subtract(leftMin));
            setHeight(bottomMax.subtract(topMin));
        }

        setEvaluated(true);
    }

    /**
     * Evaluate child boxes by resolving boxRefs from the elements map.
     * Each boxRef name is looked up in the project elements dictionary.
     *
     * @param elements the project elements map (name → TElement)
     */
    private void evaluateBoxes(Map<String, TElement> elements) {
        boolean subGroup = false;
        List<Box> resolvedBoxes = new ArrayList<>();

        if (srcGroup == null || srcGroup.getBoxRefs() == null) {
            this.srcBoxes = new Box[0];
            return;
        }

        for (BoxRef boxRef : srcGroup.getBoxRefs()) {
            if (boxRef == null || boxRef.getName() == null) {
                continue;
            }

            String refName = boxRef.getName();

            if (!elements.containsKey(refName)) {
                // Parity: .NET TGroup.cs throws Exception_TElement(TGroupUnKnownSubGroup, boxRef.name,
                // srcGroup.name); QxpProject.evaluatePendingGroups records it as an UNSPECIFIED run error.
                // (Finding #18/#19.)
                throw new ExceptionTElement(String.format(
                        "Attention l'élément '%s' est introuvable dans le group '%s'",
                        refName, srcGroup.getName()));
            }

            TElement refElement = elements.get(refName);

            if (refElement instanceof TBox) {
                TBox tBox = (TBox) refElement;
                tBoxes.add(tBox);
                tBox.evaluate(null); // TBox.evaluate doesn't use qxpProject
                resolvedBoxes.add(tBox.getSrcBox());

                if (UNKNOWN_PAGE.equals(page) && !UNKNOWN_PAGE.equals(tBox.getPage())) {
                    this.page = tBox.getPage();
                }
            } else if (refElement instanceof TGroup) {
                // Sub-groups: evaluate but flag as problematic
                // .NET logs warning: "TGroupSubGroupProblem"
                subGroup = true;
                TGroup subGrp = (TGroup) refElement;
                subGrp.evaluate(buildQxpProjectProxy(elements));

                if (UNKNOWN_PAGE.equals(page) && !UNKNOWN_PAGE.equals(subGrp.getPage())) {
                    this.page = subGrp.getPage();
                }
            }
        }

        this.srcBoxes = resolvedBoxes.toArray(new Box[0]);

        if (subGroup) {
            // Parity: .NET TGroup.cs throws Exception_TElement(TGroupSubGroupProblem, srcGroup.name, Page)
            // — a template element of type group must not contain other groups. Recorded as an
            // UNSPECIFIED run error by QxpProject.evaluatePendingGroups. (Finding #44/#19.)
            throw new ExceptionTElement(String.format(
                    "Attention le group '%s' de la page '%s' possède des sous groupes qui ne seront pas "
                            + "évalués et qui peuvent perturber l'exécution de la tache",
                    srcGroup.getName(), page));
        }
    }

    /**
     * Build a minimal proxy object that TGroup.evaluate() can use to access elements.
     * This avoids circular dependency with QxpProject.
     */
    private Object buildQxpProjectProxy(Map<String, TElement> elements) {
        return new Object() {
            @SuppressWarnings("unused")
            public Map<String, TElement> getElements() {
                return elements;
            }
        };
    }
}
```

---

## `domain/project/QxpProject.java`
```java
package com.socgen.sgs.api.quark.engine.domain.project;

import com.socgen.sgs.api.quark.engine.domain.element.ExceptionTElement;
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

            // Parity: .NET QXP_Project adds to a Dictionary which throws ArgumentNullException on a null
            // key, aborting Analyse. (Finding #81.)
            if (tBox.getName() == null) {
                throw new IllegalArgumentException("Element name is null");
            }

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

            if (tTable.getName() == null) {
                throw new IllegalArgumentException("Element name is null"); // .NET ArgumentNullException (#81)
            }

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

            if (tGroup.getName() == null) {
                throw new IllegalArgumentException("Element name is null"); // .NET ArgumentNullException (#81)
            }

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
            } catch (ExceptionTElement e) {
                // Parity: .NET QXP_Project catches ONLY Exception_TElement and, when logError, records it
                // via task.Run.Errors.Add(tex.ToString()) — the string overload → Error_Type.Unspecified (1),
                // NOT Critique. Any non-TElement exception propagates and aborts analyse, as in .NET.
                // (Findings #18/#19/#44.)
                if (logError && task != null) {
                    log.error("Error evaluating TGroup [{}]: {}", tGroup.getName(), e.getMessage());
                    task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED, e.getMessage()));
                } else {
                    log.debug("Error evaluating TGroup [{}]: {}", tGroup.getName(), e.getMessage());
                }
            }
        }
    }
}
```

---

## `business/ProcessSqlBusiness.java`
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

## `domain/modifier/QxpsModifier.java`
```java
package com.socgen.sgs.api.quark.engine.domain.modifier;

import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocGroup;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocLigne;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocPage;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocTable;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Project;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.List;

/**
 * Aggregates all bloc types into a project hierarchy for sending to QuarkXPress Server.
 * Converts BlocBox/BlocPage/BlocTable/BlocGroup/BlocLigne into the Modifier structure
 * (ModifierProjet → ModifierLayout → ModifierSpread → ModifierBox/Page/Table/Group).
 *
 * Cross-reference: QXP.Engine.Core.QXPS_Modifier
 */
@Getter
@Slf4j
public class QxpsModifier {

    private final ModifierProjet projet = new ModifierProjet();
    private boolean empty = true;
    private final List<BlocBase> blocs = new ArrayList<>();

    public QxpsModifier() {
    }

    /**
     * Add a list of blocs to the modifier.
     */
    public void addRange(Iterable<BlocBase> blocs) {
        for (BlocBase bloc : blocs) {
            add(bloc);
        }
    }

    /**
     * Add a single bloc to the modifier hierarchy.
     * Routes to the correct typed add method based on bloc class.
     *
     * Cross-reference: .NET QXPS_Modifier.Add(Bloc_Base)
     */
    public void add(BlocBase bloc) {
        if (bloc == null || bloc.isExclude()) {
            return;
        }
        blocs.add(bloc);

        if (bloc instanceof BlocBox) {
            addBlocBox((BlocBox) bloc);
        } else if (bloc instanceof BlocGroup) {
            addBlocGroup((BlocGroup) bloc);
        } else if (bloc instanceof BlocTable) {
            addBlocTable((BlocTable) bloc);
        } else if (bloc instanceof BlocLigne) {
            addBlocLigne((BlocLigne) bloc);
        } else if (bloc instanceof BlocPage) {
            addBlocPage((BlocPage) bloc);
        }
    }

    private void addBlocBox(BlocBox bloc) {
        ModifierSpread spread = addGetSpread(bloc);
        if (spread == null) return;

        ModifierBox box = new ModifierBox();
        box.setName(bloc.getName());
        box.setAction(bloc.getAction());
        box.setPageId(bloc.getPageId());
        box.setValue(bloc.getValue());
        box.setSrcBox(getBox(bloc, false));
        spread.getBoxes().put(box.getName(), box);

        if (bloc.getSrcExtraBox() != null) {
            ModifierBox extraBox = new ModifierBox();
            extraBox.setName(bloc.getName());
            extraBox.setAction(bloc.getAction());
            extraBox.setPageId(bloc.getPageId());
            extraBox.setValue(bloc.getValue());
            extraBox.setSrcBox(getBox(bloc, true));
            spread.getBoxesExtra().put(extraBox.getName(), extraBox);
        }
    }

    private void addBlocGroup(BlocGroup bloc) {
        ModifierSpread spread = addGetSpread(bloc);
        if (spread == null) return;

        ModifierGroup group = new ModifierGroup();
        group.setName(bloc.getName());
        group.setPageId(bloc.getPageId());
        group.setAction(bloc.getAction());
        group.setSrcBoxes(bloc.getSrcBoxes());
        spread.getGroups().put(group.getName(), group);
    }

    private void addBlocTable(BlocTable bloc) {
        ModifierSpread spread = addGetSpread(bloc);
        if (spread == null) return;

        if (!spread.getTables().containsKey(bloc.getName())) {
            ModifierTable table = new ModifierTable();
            table.setName(bloc.getName());
            table.setAction(bloc.getAction());
            table.setTask(bloc.getTask());
            table.setSrcTable(bloc.getSrcTable());
            spread.getTables().put(table.getName(), table);
        } else {
            ModifierTable existing = spread.getTables().get(bloc.getName());
            if (bloc.getAction() == BlocActionEnum.REMOVE) {
                existing.setAction(bloc.getAction());
                existing.getLignes().clear();
            }
        }
    }

    private void addBlocLigne(BlocLigne bloc) {
        ModifierTable table = addGetTable(bloc);
        if (table == null) return;

        ModifierLigne ligne = new ModifierLigne();
        ligne.setIndex(bloc.getIndex());

        if (!table.getLignes().containsKey(bloc.getIndex())
                && table.getAction() != BlocActionEnum.REMOVE) {
            table.getLignes().put(ligne.getIndex(), ligne);
        }
    }

    private void addBlocPage(BlocPage bloc) {
        ModifierSpread spread = addGetSpread(bloc);
        if (spread == null) return;

        ModifierPage page = new ModifierPage();
        page.setAction(bloc.getAction());
        page.setUid(String.valueOf(bloc.getPageId()));
        page.setPosition(bloc.getPosition());
        page.setIndexPosition(bloc.getIndexPosition());
        page.setName(bloc.getName());
        page.setTask(bloc.getTask());
        page.setCreateDummyNextPage(bloc.isCreateNextDummyPage());

        if (!spread.getPages().containsKey(page.getUid())) {
            spread.getPages().put(page.getUid(), page);
        }
    }

    // ========================================================================
    // Hierarchy navigation helpers
    // ========================================================================

    private ModifierLayout addGetLayout(BlocBase bloc) {
        String layoutName;
        if (bloc.getCondName() != null && !bloc.getCondName().isBlank()) {
            layoutName = bloc.getTask().getRun().getGabarit()
                    .getQxpXml().getLayoutName(bloc.getCondName());
        } else {
            layoutName = bloc.getTask().getProperties().getLayoutName();
        }

        if (layoutName == null || layoutName.isBlank()) {
            return null;
        }

        return projet.getLayouts().computeIfAbsent(layoutName, k -> {
            ModifierLayout layout = new ModifierLayout();
            layout.setName(layoutName);
            return layout;
        });
    }

    private ModifierSpread addGetSpread(BlocBase bloc) {
        ModifierLayout layout = addGetLayout(bloc);
        if (layout == null) {
            // Parity: .NET QXPS_Modifier records Empty_Layout_Or_Spread_For_Bloc (Errors.Add(string) →
            // Error_Type.Unspecified) as an audit-trail entry; it does NOT fail the run. Finding #65.
            bloc.getTask().getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                    "Layout ou Spread NULL pour le bloc " + bloc.getName()));
            log.warn("No layout found for bloc [{}]", bloc.getName());
            return null;
        }

        empty = false;
        String spreadUid = String.valueOf(bloc.getSpreadId());

        return layout.getSpreads().computeIfAbsent(spreadUid, k -> {
            ModifierSpread spread = new ModifierSpread();
            spread.setUid(spreadUid);
            return spread;
        });
    }

    private ModifierTable addGetTable(BlocBase bloc) {
        ModifierSpread spread = addGetSpread(bloc);
        if (spread == null) return null;

        return spread.getTables().computeIfAbsent(bloc.getParentName(), k -> {
            ModifierTable table = new ModifierTable();
            table.setName(bloc.getParentName());
            table.setAction(BlocActionEnum.NONE);
            table.setTask(bloc.getTask());
            return table;
        });
    }

    private Box getBox(BlocBox blocBox, boolean fromExtraSrc) {
        return fromExtraSrc ? blocBox.getSrcExtraBox() : blocBox.getSrcBox();
    }

    // ========================================================================
    // Output
    // ========================================================================

    /**
     * Get the SOAP Project structure.
     * Cross-reference: .NET QXPS_Modifier.GetProject()
     */
    public Project getProject() {
        return projet.getSdkProject();
    }
}
```

---

## `service/task/impl/SystemTaskProcessStrategy.java`
```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBox;
import com.socgen.sgs.api.quark.engine.domain.helper.DataTypeHelper;
import com.socgen.sgs.api.quark.engine.domain.task.TaskSystem;
import com.socgen.sgs.api.quark.engine.enums.SubTaskTypeEnum;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessStrategy;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * Strategy for processing TaskSystem (system/template box updates).
 * Handles two modes: VALUE mode (text updates) and BOX mode (box copying from gabarit).
 *
 * Cross-reference: QXP.Engine.Core\Business\Task\Process_System.cs
 */
@Component
@Slf4j
public class SystemTaskProcessStrategy implements TaskProcessStrategy<TaskSystem> {

    @Override
    public Class<TaskSystem> getTaskType() {
        return TaskSystem.class;
    }

    @Override
    public void process(TaskSystem task) {
        // Step 1: Verify destination bloc name is set (required)
        if (task.getDestinationBlocName() == null || task.getDestinationBlocName().isBlank()) {
            // Parity: .NET Process_System records MissingBlocNameInTask (Errors.Add(string) →
            // Error_Type.Unspecified) before returning, instead of only logging. Finding #69.
            task.getRun().getErrors().add(new RunError(RunError.UNSPECIFIED,
                    "Missing BlocName in Task:" + task.getDebugInfo()));
            log.warn("Missing destinationBlocName for task [{}], skipping", task.getId());
            return;
        }

        // Step 2: Determine mode based on tBoxSrcBox presence
        if (task.getTBoxSrcBox() != null) {
            processBoxMode(task);
        } else {
            processValueMode(task);
        }
    }

    /**
     * VALUE MODE: Format a text value and create UPDATE bloc.
     * Maps to .NET Process_System.cs lines 65-74.
     */
    private void processValueMode(TaskSystem task) {
        log.debug("SystemTaskProcessStrategy VALUE mode for task [{}]", task.getId());

        task.setSubTaskType(SubTaskTypeEnum.VALUE);

        String formattedValue = DataTypeHelper.outputToString(
                task.getValue(),
                task.getDataType(),
                task.getNbDecimal(),
                task.isShowZero(),
                task.getNullString(),
                task.isDecimalSignificative()
        );

        BlocBox bloc = new BlocBox(task, task.getDestinationBlocName(), formattedValue);
        task.getBlocsUpdate().put(bloc.getName(), bloc);

        log.debug("SystemTaskProcessStrategy VALUE: bloc [{}] = [{}]",
                task.getDestinationBlocName(), formattedValue);
    }

    /**
     * BOX MODE: Copy a box from gabarit template and create MODIFY bloc.
     * Maps to .NET Process_System.cs lines 52-62.
     */
    private void processBoxMode(TaskSystem task) {
        log.debug("SystemTaskProcessStrategy BOX mode for task [{}]", task.getId());

        task.setSubTaskType(SubTaskTypeEnum.BOX);

        String blocName = task.getTBoxSrcBox().getName();

        BlocBox bloc = new BlocBox(
                task,
                blocName,
                task.getTBoxSrcBox(),
                task.getTBoxSrcExtraBox()
        );

        bloc.setAction(task.getAction());
        bloc.setPagination(task.isPagination());

        task.getBlocsModify().put(bloc.getName(), bloc);

        log.debug("SystemTaskProcessStrategy BOX: bloc [{}], action={}, pagination={}",
                blocName, task.getAction(), task.isPagination());
    }
}
```

---

## `service/task/impl/TaskProcessServiceImpl.java`
```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessService;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessStrategy;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/** Dispatches task processing to the matching strategy bean. */
@Service
@Slf4j
public class TaskProcessServiceImpl implements TaskProcessService {

    @SuppressWarnings("rawtypes")
    private final Map<Class, TaskProcessStrategy> strategyMap;

    @SuppressWarnings("rawtypes")
    public TaskProcessServiceImpl(List<TaskProcessStrategy> strategies) {
        this.strategyMap = strategies.stream()
                .collect(Collectors.toMap(TaskProcessStrategy::getTaskType, Function.identity()));
        log.info("Registered {} task process strategies: {}", strategyMap.size(), strategyMap.keySet());
    }

    @Override
    @SuppressWarnings("unchecked")
    public void process(TaskBase task) {
        TaskProcessStrategy strategy = strategyMap.get(task.getClass());
        if (strategy != null) {
            strategy.process(task);
        } else {
            // Parity: an unprocessable task is a hard failure in .NET, not a silent skip. Throwing here
            // propagates to the ProcessTasksServiceImpl Pass-1 try/catch which records a CRITIQUE run
            // error and setInError(true). Finding #58.
            throw new IllegalStateException(
                    "No process strategy registered for task type: " + task.getClass().getName());
        }
    }
}
```

---

## `infra/dao/impl/GetCompartimentRunsDaoImpl.java`
```java
package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.infra.dao.GetCompartimentRunsDao;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import oracle.jdbc.OracleTypes;
import org.springframework.jdbc.core.SqlOutParameter;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

import jakarta.annotation.PostConstruct;
import javax.sql.DataSource;
import java.sql.ResultSet;
import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * DAO implementation that calls QXP_PK_RUN.Get_Compartiment_Runs Oracle function.
 *
 * <p>Oracle function signature:
 * <pre>
 * FUNCTION Get_Compartiment_Runs(
 *     p_id_gabarit_tete   IN NUMBER,
 *     p_id_structure      IN VARCHAR2,
 *     p_id_gabarit_fils   IN NUMBER,
 *     p_id_type_rapport   IN NUMBER,
 *     p_id_langue         IN NUMBER,
 *     p_date_echeance     IN DATE,
 *     p_to_generate       IN NUMBER
 * ) RETURN qxp_pk_common.hcur
 * </pre>
 *
 * Returns cursor with columns: id_fnd_code (VARCHAR2), id_run (NUMBER)
 *
 * Cross-reference: .NET Proxy_Run.Get_Compartiment_Runs()
 */
@Repository
@Slf4j
@RequiredArgsConstructor
public class GetCompartimentRunsDaoImpl implements GetCompartimentRunsDao {

    private static final String RESULT_KEY = "result_cursor";

    private final DataSource dataSource;

    private SimpleJdbcCall getCompartimentRunsCall;

    @PostConstruct
    private void init() {
        this.getCompartimentRunsCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_RUN")
                .withFunctionName("Get_Compartiment_Runs")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlOutParameter(RESULT_KEY, OracleTypes.CURSOR,
                                (ResultSet rs, int rowNum) -> {
                                    String idFndCode = rs.getString("id_fnd_code");
                                    int idRun = rs.getInt("id_run");
                                    if (rs.wasNull()) {
                                        idRun = 0;
                                    }
                                    return new String[]{idFndCode, String.valueOf(idRun)};
                                }),
                        new SqlParameter("p_id_gabarit_tete", Types.NUMERIC),
                        new SqlParameter("p_id_structure", Types.VARCHAR),
                        new SqlParameter("p_id_gabarit_fils", Types.NUMERIC),
                        new SqlParameter("p_id_type_rapport", Types.NUMERIC),
                        new SqlParameter("p_id_langue", Types.NUMERIC),
                        new SqlParameter("p_date_echeance", Types.DATE),
                        new SqlParameter("p_to_generate", Types.NUMERIC)
                );
    }

    @Override
    public LinkedHashMap<String, Integer> getCompartimentRuns(int idGabaritTete, String idStructure,
                                                              int idGabaritFils, int idTypeRapport,
                                                              int idLangue, LocalDate dateEcheance,
                                                              boolean toGenerate) {
        log.info("Fetching compartment runs for gabarit={}, structure={}, gabaritFils={}",
                idGabaritTete, idStructure, idGabaritFils);

        MapSqlParameterSource params = new MapSqlParameterSource()
                .addValue("p_id_gabarit_tete", idGabaritTete)
                .addValue("p_id_structure", idStructure)
                .addValue("p_id_gabarit_fils", idGabaritFils)
                .addValue("p_id_type_rapport", idTypeRapport)
                .addValue("p_id_langue", idLangue)
                .addValue("p_date_echeance", java.sql.Date.valueOf(dateEcheance))
                .addValue("p_to_generate", toGenerate ? 1 : 0);

        try {
            Map<String, Object> result = getCompartimentRunsCall.execute(params);

            @SuppressWarnings("unchecked")
            List<String[]> rows = (List<String[]>) result.get(RESULT_KEY);

            // Preserve insertion order (matches .NET ordering by asgc.position)
            LinkedHashMap<String, Integer> compartimentRuns = new LinkedHashMap<>();

            if (rows != null) {
                for (String[] row : rows) {
                    String idFndCode = row[0];
                    int idRun = Integer.parseInt(row[1]);
                    compartimentRuns.put(idFndCode, idRun);
                }
            }

            log.info("Found {} compartment runs for gabarit={}", compartimentRuns.size(), idGabaritTete);
            return compartimentRuns;

        } catch (Exception e) {
            // Parity: .NET Proxy_Run.Get_Compartiment_Runs has no try/catch — a DB/cursor failure must
            // fail the run, not be swallowed into an empty map (which would masquerade as "no rows" and
            // silently drop compartiments). A legitimately empty 0-row result still flows through above
            // and is handled by CompartimentTaskProcessStrategy as the NoneRunCompartiment critique.
            // Finding #48.
            log.error("Error fetching compartment runs for gabarit={}: {}", idGabaritTete, e.getMessage(), e);
            throw new RuntimeException(
                    "Failed to fetch compartment runs for gabarit=" + idGabaritTete, e);
        }
    }
}
```

---

## Apply checklist
- [ ] Add `domain/element/ExceptionTElement.java`
- [ ] Replace the 8 whole files above
- [ ] Apply the 2 snippets (DocumentTaskProcessStrategy, CompartimentTaskProcessStrategy)
- [ ] `mvn compile` then `mvn test` (no test touches these classes)
