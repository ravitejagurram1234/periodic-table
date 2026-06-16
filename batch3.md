# EOS Quark — Batch 3 Changes (copy-paste)

**Batch 3 = DID post-process correctness.** The DID (Document Identity) update was broken: it produced an empty/no bloc and never routed through system bloc-creation. This restores full .NET parity (`Task_DID.PostProcess` → `Process_System.Process`).

**What changed & why:**
- **DID logic relocated** out of the `TaskDid` domain class into `DidTaskPostProcessStrategy` (service) — consistent with every other task, and required because creating the bloc must call `SystemTaskProcessStrategy` (the domain cannot).
- **MOVE mode** now builds the `MOVE_BLOC_VALUE` box with real geometry (left/top/right/bottom), UID, and value from the gabarit XML, then creates a MOVE bloc.
- **NAME_VALUE mode** now actually produces an UPDATE bloc (was a no-op).
- **MissingDID** validation restored (UID-not-found → Critique error, no bloc).
- `TaskDid` is now a pure state holder; `DidTaskProcessStrategy.process` is a no-op (matches .NET `Task_DID.Process()`).

## How to apply
Each section is one file. Replace the entire file contents with the block (create if missing). Paths are relative to the `quark-engine` module root. Then `mvn -DskipTests compile` and `mvn test`.

## Checklist (3 files)
- [ ] `domain/task/TaskDid.java` — CHANGED
- [ ] `service/task/impl/DidTaskProcessStrategy.java` — CHANGED
- [ ] `service/task/impl/DidTaskPostProcessStrategy.java` — CHANGED

---

## 1. `src/main/java/com/socgen/sgs/api/quark/engine/domain/task/TaskDid.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.domain.task;

import com.socgen.sgs.api.quark.engine.domain.Run;

/**
 * Represents the DID (Document Identity) update task in a QuarkXPress run.
 * <p>
 * This task is always executed ({@code todo=true}, {@code allwaysReprocess=true}) and its
 * destination bloc is always the {@code "DID"} bloc.
 * <p>
 * It is a pure state holder: the update logic lives in
 * {@code DidTaskPostProcessStrategy}. The DID can only be computed once every other task's
 * pagination is known (post-process), and it must be turned into a bloc by the system
 * bloc-creation path — both of which belong in the service layer. This mirrors .NET
 * {@code Task_DID}, whose {@code PostProcess()} delegates to {@code Process_System.Process(this)}.
 *
 * <p>Translated from .NET {@code Task_DID} — {@code QXP.Engine.Core}.</p>
 */
public class TaskDid extends TaskSystem {

    private static final String DID_BLOC_NAME = "DID";
    public static final int DID_TASK_ID = 0;

    /**
     * Creates a new TaskDid, always bound to the "DID" bloc.
     *
     * @param id  the task identifier
     * @param run the run that created this task
     */
    public TaskDid(int id, Run run) {
        super(id, run);
        // This task is always to be executed
        this.setTodo(true);
        // Always the same destination
        this.setDestinationBlocName(DID_BLOC_NAME);
        // This task will be re-executed at each processing cycle
        this.setAllwaysReprocess(true);
        // Debug comment
        this.setCommentaire("DID updater");
    }
}
```

## 2. `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/DidTaskProcessStrategy.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.domain.task.TaskDid;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessStrategy;
import org.springframework.stereotype.Component;

/** DID task has no processing logic — all happens in post-process. */
@Component
public class DidTaskProcessStrategy implements TaskProcessStrategy<TaskDid> {

    @Override
    public Class<TaskDid> getTaskType() {
        return TaskDid.class;
    }

    @Override
    public void process(TaskDid task) {
        // Nothing at process time — the DID is computed in post-process, after every other
        // task's pagination is known. Cross-reference: .NET Task_DID.Process() (empty body).
    }
}

```

## 3. `src/main/java/com/socgen/sgs/api/quark/engine/service/task/impl/DidTaskPostProcessStrategy.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.service.task.impl;

import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.bloc.BlocBase;
import com.socgen.sgs.api.quark.engine.domain.dynamic.report.DBlocInfo;
import com.socgen.sgs.api.quark.engine.domain.element.TBox;
import com.socgen.sgs.api.quark.engine.domain.helper.DocumentIdentityHelper;
import com.socgen.sgs.api.quark.engine.domain.helper.TElementHelper;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.domain.task.TaskDid;
import com.socgen.sgs.api.quark.engine.enums.BlocActionEnum;
import com.socgen.sgs.api.quark.engine.enums.StaticTElementNameEnum;
import com.socgen.sgs.api.quark.engine.integration.soap.generated.Box;
import com.socgen.sgs.api.quark.engine.service.task.TaskPostProcessStrategy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * DID post-processing — chooses MOVE vs NAME_VALUE mode, builds the DID identity, and produces
 * the DID bloc by routing through the standard system bloc-creation path.
 *
 * <p>Cross-reference: .NET {@code Task_DID.PostProcess()} → {@code Business.Process_System.Process(this)}.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class DidTaskPostProcessStrategy implements TaskPostProcessStrategy<TaskDid> {

    private static final String DID_BLOC_NAME = "DID";
    /** RunError categories: 1=Bloquante, 2=Critique, 3=Warning. */
    private static final int CRITIQUE = 2;

    /** Reused to actually create the bloc, exactly like .NET delegates to Process_System. */
    private final SystemTaskProcessStrategy systemTaskProcessStrategy;

    @Override
    public Class<TaskDid> getTaskType() {
        return TaskDid.class;
    }

    @Override
    public void postProcess(TaskDid task) {
        // 1. Choose update mode.
        // If any task produced a paginated modify bloc (page create/remove) it may shift the DID's
        // position, so the DID is repositioned + revalued via MOVE; otherwise just its value changes.
        // Cross-reference: .NET Task_DID.PostProcess() mode selection.
        boolean modifier = false;
        modeSelection:
        for (TaskBase other : task.getRun().getTasks().values()) {
            for (BlocBase bloc : other.getBlocsModify().values()) {
                if (bloc.isPagination()) {
                    modifier = true;
                    break modeSelection;
                }
            }
        }

        // 2. Build the new identity value.
        String didValue = DocumentIdentityHelper.getNewIdentity(task.getRun());
        log.debug("New DID identity for run [{}]: {}", task.getRun().getId(), didValue);

        if (modifier) {
            // MOVE mode — keep the DID box on the page where it currently is, with the new value.
            task.setAction(BlocActionEnum.MOVE);
            task.setPagination(true);

            DBlocInfo didInfo = task.getRun().getGabarit().getQxpXml().getBlocInfo(DID_BLOC_NAME);

            // A box with no UID does not exist (every Quark box, even unnamed, has a UID).
            if (didInfo == null || didInfo.getUid() == null || didInfo.getUid().isBlank()) {
                task.getRun().getErrors().add(new RunError(CRITIQUE,
                        "DID introuvable dans le document (UID manquant) pour le bloc " + DID_BLOC_NAME));
                log.warn("Missing DID box (no UID) for run [{}] — DID not updated", task.getRun().getId());
                return;
            }

            // To move a box, QuarkXPress needs at least its position + UID (the page is set later in
            // the modifier). Cross-reference: .NET TElement_Helper.Get_TElement(MOVE_BLOC_VALUE, dest).
            TBox tBox = (TBox) TElementHelper.getTElement(
                    StaticTElementNameEnum.MOVE_BLOC_VALUE, task.getDestinationBlocName());
            Box box = tBox.getSrcBox();
            box.getGeometry().getPosition().setLeft(didInfo.getLeft().toString());
            box.getGeometry().getPosition().setTop(didInfo.getTop().toString());
            box.getGeometry().getPosition().setRight(didInfo.getRight().toString());
            box.getGeometry().getPosition().setBottom(didInfo.getBottom().toString());
            box.setUID(didInfo.getUid());
            box.getContent().setValue(didValue);

            // Drives SystemTaskProcessStrategy BOX mode → a MOVE bloc in blocsModify.
            task.setTBoxSrcBox(box);
            log.info("DID update mode: MOVE for run [{}]", task.getRun().getId());

        } else {
            // NAME_VALUE mode — update the DID value only.
            String didUid = task.getRun().getGabarit().getQxpXml().getUID(DID_BLOC_NAME);
            if (didUid == null || didUid.isBlank()) {
                task.getRun().getErrors().add(new RunError(CRITIQUE,
                        "DID introuvable dans le document (UID manquant) pour le bloc " + DID_BLOC_NAME));
                log.warn("Missing DID box (no UID) for run [{}] — DID not updated", task.getRun().getId());
                return;
            }
            // tBoxSrcBox stays null → SystemTaskProcessStrategy VALUE mode → an UPDATE bloc in blocsUpdate.
            task.setValue(didValue);
            log.info("DID update mode: NAME_VALUE for run [{}]", task.getRun().getId());
        }

        // 3. Create the actual bloc as a standard system task.
        // Cross-reference: .NET Task_DID.PostProcess() → Business.Process_System.Process(this).
        systemTaskProcessStrategy.process(task);

        log.info("DID task post-process completed for run [{}]", task.getRun().getId());
    }
}
```

