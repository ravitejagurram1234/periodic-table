# EOS Quark — Batch 2 Changes (copy-paste)

**Batch 2 = Pipeline correctness** — adds the missing Prepare phase, persists `RUNNING` before `Start_Run`, and fixes the 3-pass loop (degraded tasks reported as fail-soft Critique errors and not reset; per-task errors recorded on the run).

> Note: render flags were reviewed and **left unchanged** — `render(run, true, false, true, "true", "300")` already matches the fixed .NET defaults (QXP+PDF on, JPG off, 300 DPI, compression "true"); .NET never overrides them. Changing it would *diverge* from .NET.

## How to apply
Each section is one file. Replace the entire file contents with the block (create if missing). Paths are relative to the `quark-engine` module root. Then `mvn -DskipTests compile` and `mvn test`.

## Checklist (3 files)
- [ ] `service/ProcessTasksService.java` — CHANGED
- [ ] `service/impl/ProcessTasksServiceImpl.java` — CHANGED
- [ ] `service/impl/ProcessRunServiceImpl.java` — CHANGED

---

## 1. `src/main/java/com/socgen/sgs/api/quark/engine/service/ProcessTasksService.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.service;

import com.socgen.sgs.api.quark.engine.domain.Run;

/** Orchestrates prepare, process, post-process, and verification of all tasks in a run. */
public interface ProcessTasksService {

    /**
     * Prepare phase: calls {@code prepare()} on every task before processing.
     * Cross-reference: .NET Run_Base.Launch_Prepare() / Run_Base.Prepare().
     */
    void prepareTasks(Run run);

    void processTasks(Run run);
}

```

## 2. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessTasksServiceImpl.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunError;
import com.socgen.sgs.api.quark.engine.domain.RunTask;
import com.socgen.sgs.api.quark.engine.domain.task.TaskBase;
import com.socgen.sgs.api.quark.engine.service.ProcessTasksService;
import com.socgen.sgs.api.quark.engine.service.task.TaskPostProcessService;
import com.socgen.sgs.api.quark.engine.service.task.TaskProcessService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Implements the Prepare phase and the 3-pass task processing loop.
 * Cross-reference: .NET Run_Base.Prepare() and Run_Base.Process().
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ProcessTasksServiceImpl implements ProcessTasksService {

    /** RunError categories: 1=Bloquante, 2=Critique, 3=Warning. */
    private static final int CRITIQUE = 2;

    private final TaskProcessService taskProcessService;
    private final TaskPostProcessService taskPostProcessService;

    /**
     * Prepare phase — call prepare() on EVERY task (not just todo), before processing.
     * Per-task failures are recorded as Critique errors and flag the task in error.
     * Cross-reference: .NET Run_Base.Prepare() (iterates _tasks.Values).
     */
    @Override
    public void prepareTasks(Run run) {
        log.info("Preparing tasks for runId: {}", run.getId());

        for (TaskBase task : run.getTasks().values()) {
            try {
                log.debug("Preparing task {}", task.getId());
                task.prepare();
            } catch (Exception ex) {
                task.setInError(true);
                run.getErrors().add(new RunError(CRITIQUE,
                        "Erreur lors de la preparation de la tache " + task.getId() + " : " + ex.getMessage()));
                log.error("Error preparing task {}: {}", task.getId(), ex.getMessage(), ex);
            }
        }

        log.info("Task preparation completed for runId: {}", run.getId());
    }

    @Override
    public void processTasks(Run run) {
        log.info("Processing tasks for runId: {}", run.getId());

        // Fresh step aggregator for this processing pass.
        // Cross-reference: .NET Run_Base.Process() — `_run_Task = new Run_Task(this)`.
        run.setRunTask(new RunTask(run));

        // Pass 1: Reset + Process each task
        for (TaskBase task : run.getTasks().values()) {
            if (!task.isTodo()) continue;
            if (task.isInError()) continue;
            try {
                // A task in degraded mode is NOT reset/processed; it is reported as a fail-soft error.
                // Cross-reference: .NET Process() — Errors.Add(Critique, TaskFailSoftMode) and skip.
                if (task.isModeDegrade()) {
                    run.getErrors().add(new RunError(CRITIQUE,
                            "Tache " + task.getId() + " en mode degrade (fail-soft) : non traitee"));
                    log.warn("Task {} is in degraded mode (fail-soft), not processed", task.getId());
                    continue;
                }
                log.debug("Processing task {}", task.getId());
                task.resetProcess();
                taskProcessService.process(task);
                log.debug("Task {} produced {} blocsUpdate, {} blocsModify",
                        task.getId(), task.getBlocsUpdate().size(), task.getBlocsModify().size());
            } catch (Exception ex) {
                task.setInError(true);
                run.getErrors().add(new RunError(CRITIQUE,
                        "Erreur lors du traitement de la tache " + task.getId() + " : " + ex.getMessage()));
                log.error("Error processing task {}: {}", task.getId(), ex.getMessage(), ex);
            }
        }

        // Pass 2: Post-process each task (e.g. DID, which needs all other tasks done first)
        for (TaskBase task : run.getTasks().values()) {
            if (!task.isTodo()) continue;
            if (task.isInError() || task.isModeDegrade()) continue;
            try {
                log.debug("Post-processing task {}", task.getId());
                taskPostProcessService.postProcess(task);
                log.debug("Task {} post-process: {} blocsUpdate, {} blocsModify",
                        task.getId(), task.getBlocsUpdate().size(), task.getBlocsModify().size());
            } catch (Exception ex) {
                task.setInError(true);
                run.getErrors().add(new RunError(CRITIQUE,
                        "Erreur lors du post-traitement de la tache " + task.getId() + " : " + ex.getMessage()));
                log.error("Error post-processing task {}: {}", task.getId(), ex.getMessage(), ex);
            }
        }

        // Pass 3: Verify — a task with no blocs is an error; otherwise register its blocs
        for (TaskBase task : run.getTasks().values()) {
            if (!task.isTodo()) continue;
            if (task.isInError() || task.isModeDegrade()) continue;
            if (task.getBlocsUpdate().isEmpty() && task.getBlocsModify().isEmpty()) {
                run.getErrors().add(new RunError(CRITIQUE,
                        "La tache " + task.getId() + " ne genere aucun bloc"));
                log.warn("Task {} has no blocs after processing", task.getDebugInfo());
            } else {
                run.getRunTask().addTask(task);
                log.debug("Task {} added to RunTask with {} blocsUpdate, {} blocsModify",
                        task.getId(), task.getBlocsUpdate().size(), task.getBlocsModify().size());
            }
        }

        log.info("Task processing completed for runId: {}", run.getId());
    }
}
```

## 3. `src/main/java/com/socgen/sgs/api/quark/engine/service/impl/ProcessRunServiceImpl.java`  — **CHANGED**

```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.business.*;
import com.socgen.sgs.api.quark.engine.domain.*;
import com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort;
import com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort;
import com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult;
import com.socgen.sgs.api.quark.engine.dto.RunIdDto;
import com.socgen.sgs.api.quark.engine.service.*;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;

@Service
@Slf4j
@RequiredArgsConstructor
public class ProcessRunServiceImpl implements ProcessRunService {

    private final RunStartUpdateBusiness   runStartUpdateBusiness;
    private final GetRunPropertiesBusiness getRunPropertiesBusiness;
    private final GetGabaritBusiness       getGabaritBusiness;
    private final GetInParamsBusiness      getInParamsBusiness;
    private final LoadTasksService         loadTasksService;
    private final FilePoolPort             filePoolPort;
    private final DocumentIdentityPort     documentIdentityPort;
    private final ProcessTasksService      processTasksService;
    private final QxpsCallerService        qxpsCallerService;
    private final CheckService             checkService;
    private final LoadTemplatesBusiness    loadTemplatesBusiness;
    private final EndRunBusiness           endRunBusiness;

    @Value("${engine.gabarit.size-limit-before-fail-soft:10485760}")
    private long sizeLimitBeforeFailSoft;

    @Override
    public void runProcessor(RunIdDto runIdDto) {
        log.info("Processing run with runId: {}", runIdDto.getRunId());
        Run run = new Run(sizeLimitBeforeFailSoft);
        run.setId(runIdDto.getRunId());
        run.setStatus(RunStatus.TO_GENERATE);
        run.setStartDate(LocalDateTime.now());

        try {
            // Step 1: Start — status must be RUNNING before it is persisted by Start_Run.
            // Cross-reference: .NET Run_Base.Launch() sets _status = Running BEFORE Launch_Start().
            run.setStatus(RunStatus.RUNNING);
            runStartUpdateBusiness.execute(run);
            log.info("Run started successfully with runId: {}", runIdDto.getRunId());

            // Step 2: Load
            load(run);

            if (!run.getRunProperties().isModeDegrade()) {
                // Step 3: Prepare — call prepare() on every task before processing.
                // Cross-reference: .NET Run_Base.Launch_Prepare() / Prepare().
                processTasksService.prepareTasks(run);

                // Step 4: Process tasks (3-pass loop)
                processTasksService.processTasks(run);

                // Step 5: Execute modification steps against QXPS
                qxpsCallerService.process(run);

                // Step 6: Check — overflow detection + data collection
                checkService.check(run);
            }

            // Step 7: Render final outputs
            QxpsCallerResult renderResult = qxpsCallerService.render(
                    run, true, false, true, "true", "300");

            // Build RunResult from render data
            buildRunResult(run, renderResult);

            run.setStatus(RunStatus.GENERATED);

        } catch (Exception ex) {
            log.error("Run [{}] failed: {}", runIdDto.getRunId(), ex.getMessage(), ex);
            run.setStatus(RunStatus.ERROR);
            run.getErrors().add(new RunError(1, ex.getMessage()));
        } finally {
            // Step 8: End — finalize run (always executes)
            try {
                endRunBusiness.execute(run);
            } catch (Exception ex) {
                log.error("End_Run failed for run [{}]: {}", runIdDto.getRunId(), ex.getMessage(), ex);
                // Retry with error status
                run.setStatus(RunStatus.ERROR);
                try {
                    endRunBusiness.execute(run);
                } catch (Exception ex2) {
                    log.error("End_Run retry failed for run [{}]: {}",
                            runIdDto.getRunId(), ex2.getMessage(), ex2);
                }
            }
            log.info("Run completed for runId: {} with status: {}",
                    runIdDto.getRunId(), run.getStatus());
        }
    }

    /**
     * Build RunResult from render output.
     * Cross-reference: .NET Run_Base.Render() — wraps binary data in Document objects
     */
    private void buildRunResult(Run run, QxpsCallerResult renderResult) {
        String docNamePrefix = String.format("DF_%d", run.getId());

        if (renderResult.getJpgData() != null) {
            run.getResult().setFinalJpg(new DocumentDomain(
                    run.getId(), docNamePrefix, "JPEG",
                    DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, renderResult.getJpgData()));
        }
        if (renderResult.getPdfData() != null) {
            run.getResult().setFinalPdf(new DocumentDomain(
                    run.getId(), docNamePrefix, "PDF",
                    DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, renderResult.getPdfData()));
        }
        if (renderResult.getQxpData() != null) {
            run.getResult().setFinalQxp(new DocumentDomain(
                    run.getId(), docNamePrefix, "QXP",
                    DocumentDomain.FILE_DOCUMENT_FINAL_PREFIX, renderResult.getQxpData()));
        }
    }

    public void load(Run run) {
        log.info("Loading run with runId: {}", run.getId());

        // Step 1: Fetch and set run properties
        RunProperties runProperties = getRunProperties(new RunIdDto(run.getId()));
        runProperties.setRunId(run.getId());
        run.setRunProperties(runProperties);

        // Step 2: Delegate gabarit preparation entirely to run domain
        run.prepareGabarit(getGabaritBusiness, filePoolPort, documentIdentityPort);

        // Step 3: Inject and execute GetInParamsBusiness
        getInParamsBusiness.execute(run);

        // Step 4: Load tasks
        loadTasksService.loadTasks(run);

        //step 5: load templates for dynamic tasks
        loadTemplatesBusiness.execute(run);
        //pending implementation
        log.info("Run loading completed for runId: {}", run.getId());
    }

    @Override
    public RunProperties getRunProperties(RunIdDto runIdDto) {
        log.info("Retrieving properties for runId: {}", runIdDto.getRunId());
        RunProperties runProperties = getRunPropertiesBusiness.execute(runIdDto);
        log.info("Successfully retrieved properties for runId: {}", runIdDto.getRunId());
        return runProperties;
    }

    @Override
    public List<Integer> fetchActiveRunIds() {
        return Collections.emptyList();
    }
}
```

