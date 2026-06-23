# EOS Quark Engine — Batch 5b (Stale-Test Fixes)
**Theme: bring outdated tests in line with already-shipped behavior (no production code changed)**

_Surfaced by the full `mvn test` run. All 10 failures are STALE TESTS lagging earlier batches — NOT logic regressions. Production code is unchanged in this batch._

## The 10 failures, triaged
| Test | Count | Root cause (pre-existing) |
|---|---|---|
| `GetGabaritBusinessTest` | 4 | Asserted old mixed-slash `D:\\Documents/R_10/...`; code now emits all-backslash (F4 / `getPoolPathAbsolute` `.replace("/","\\")`, matches .NET). Same class of fix as `RunPropertiesTest:114`. |
| `EngineServiceControllerTest` | 2 | `doNothing().when(svc).runProcessor(...)` — but `runProcessor` returns `Run` (since the #17 change), so Mockito rejects `doNothing()` on a non-void method. |
| `ProcessRunServiceImplTest` | 4 | `@InjectMocks` was missing mocks for deps added across batches (`qxpsCallerService`, `checkService`, `loadTemplatesBusiness`, `loadTaskDocumentsBusiness`, `endRunBusiness`, `getGabaritXmlBusiness`) → NPE; plus 2 assertions that predate the RUNNING-status and errors-don't-propagate behavior. |

## Why these are test-only (not bugs)
- **GetGabarit slash**: the engine deliberately produces all-backslash absolute pool paths for the Windows Quark host (.NET `QXPS_File_Manager.GetPoolPathAbsolute` does `.Replace("/","\\")`). The test asserted the pre-fix value.
- **Controller `doNothing`**: `runProcessor` legitimately returns the `Run` (so the parent can read child results — the #17 Compartiment change). The controller ignores the return; the test just needs a return stub.
- **ProcessRunServiceImpl**: the orchestrator grew real dependencies and now (matching .NET `Run_Base.Launch`) sets status RUNNING before Start, catches top-level errors → ERROR, and always runs End_Run instead of propagating. The old test asserted the opposite (transient TO_GENERATE; exception propagation).

---

## `GetGabaritBusinessTest.java` — 4 one-line changes
Change each `getFileFullPath()` expectation from mixed-slash to all-backslash (the `getFilePoolPath()` assertions stay forward-slash — that path is relative `R_<id>/<file>`):
```java
// line 57
assertEquals("D:\\Documents\\R_10\\G_1.QXP", result.getFileFullPath());
// line 87
assertEquals("D:\\Documents\\R_10\\G_200.QXP", result.getFileFullPath());
// line 115
assertEquals("D:\\Documents\\R_10\\G_300.QXP", result.getFileFullPath());
// line 143
assertEquals("D:\\Documents\\R_10\\G_400.QXP", result.getFileFullPath());
```

---

## `EngineServiceControllerTest.java` — 2 one-line changes
In `shouldReturn200WhenProcessRunSucceeds` and `shouldPassCorrectRunIdToProcessor`, replace the `doNothing()` stub:
```java
// BEFORE
doNothing().when(processRunService).runProcessor(any(RunIdDto.class));
// AFTER
when(processRunService.runProcessor(any(RunIdDto.class))).thenReturn(null);
```

---

## `ProcessRunServiceImplTest.java` — CHANGED (whole file)
Added the 6 missing `@Mock` dependencies, a lenient `render()` stub (so the full pipeline completes instead of NPE-ing in `buildRunResult`), and corrected the two stale assertions.
```java
package com.socgen.sgs.api.quark.engine.service.impl;

import com.socgen.sgs.api.quark.engine.business.GetGabaritBusiness;
import com.socgen.sgs.api.quark.engine.business.GetInParamsBusiness;
import com.socgen.sgs.api.quark.engine.business.GetRunPropertiesBusiness;
import com.socgen.sgs.api.quark.engine.business.RunStartUpdateBusiness;
import com.socgen.sgs.api.quark.engine.domain.Run;
import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.domain.RunStatus;
import com.socgen.sgs.api.quark.engine.dto.RunIdDto;
import com.socgen.sgs.api.quark.engine.enums.GabaritSourceEnum;
import com.socgen.sgs.api.quark.engine.service.LoadTasksService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("ProcessRunServiceImpl Tests")
class ProcessRunServiceImplTest {

    @InjectMocks
    private ProcessRunServiceImpl processRunService;

    @Mock
    private RunStartUpdateBusiness runStartUpdateBusiness;
    @Mock
    private GetRunPropertiesBusiness getRunPropertiesBusiness;
    @Mock
    private GetGabaritBusiness getGabaritBusiness;
    @Mock
    private GetInParamsBusiness getInParamsBusiness;
    @Mock
    private LoadTasksService loadTasksService;
    @Mock
    private com.socgen.sgs.api.quark.engine.domain.port.FilePoolPort filePoolPort;
    @Mock
    private com.socgen.sgs.api.quark.engine.domain.port.DocumentIdentityPort documentIdentityPort;
    @Mock
    private com.socgen.sgs.api.quark.engine.service.ProcessTasksService processTasksService;
    // Dependencies added across later batches — required so the orchestrator pipeline does not NPE.
    @Mock
    private com.socgen.sgs.api.quark.engine.service.QxpsCallerService qxpsCallerService;
    @Mock
    private com.socgen.sgs.api.quark.engine.service.CheckService checkService;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.LoadTemplatesBusiness loadTemplatesBusiness;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.LoadTaskDocumentsBusiness loadTaskDocumentsBusiness;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.EndRunBusiness endRunBusiness;
    @Mock
    private com.socgen.sgs.api.quark.engine.business.GetGabaritXmlBusiness getGabaritXmlBusiness;

    private RunProperties runProperties;

    @BeforeEach
    void setUp() {
        runProperties = new RunProperties();
        runProperties.setGabaritSource(GabaritSourceEnum.GABARIT);
        runProperties.setIdGabarit(10);
        // render() returns a result object; stub it (lenient — only the full-pipeline tests reach it)
        // so buildRunResult does not NPE on a null render result.
        lenient().when(qxpsCallerService.render(any(), anyBoolean(), anyBoolean(), anyBoolean(), any(), any()))
                .thenReturn(new com.socgen.sgs.api.quark.engine.dto.QxpsCallerResult());
    }

    // --- runProcessor ---

    @Test
    @DisplayName("Should initialise run with correct id, status and startDate then call load")
    void shouldInitialiseRunAndCallLoad() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        processRunService.runProcessor(new RunIdDto(42));

        ArgumentCaptor<Run> runCaptor = ArgumentCaptor.forClass(Run.class);
        verify(runStartUpdateBusiness).execute(runCaptor.capture());
        Run captured = runCaptor.getValue();

        assertEquals(42, captured.getId());
        // The captured Run is the same mutable instance the orchestrator drives to completion; with
        // all collaborators mocked the pipeline finishes successfully, so its final status is GENERATED.
        assertEquals(RunStatus.GENERATED, captured.getStatus());
        assertNotNull(captured.getStartDate());
    }

    @Test
    @DisplayName("Should call runStartUpdateBusiness before load")
    void shouldCallStartUpdateBeforeLoad() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        processRunService.runProcessor(new RunIdDto(1));

        verify(runStartUpdateBusiness, times(1)).execute(any(Run.class));
        verify(getRunPropertiesBusiness, times(1)).execute(any(RunIdDto.class));
        verify(loadTasksService, times(1)).loadTasks(any(Run.class));
    }

    // --- load ---

    @Test
    @DisplayName("Should set run properties and runId on the run")
    void shouldSetRunPropertiesAndRunId() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        Run run = new Run();
        run.setId(55);
        processRunService.load(run);

        assertEquals(55, run.getRunProperties().getRunId());
        assertSame(runProperties, run.getRunProperties());
    }

    @Test
    @DisplayName("Should call all four load steps in order")
    void shouldCallAllLoadStepsInOrder() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class))).thenReturn(runProperties);
        when(getGabaritBusiness.getAndPrepareGabarit(any(), any())).thenReturn(null);

        Run run = new Run();
        run.setId(10);
        processRunService.load(run);

        var order = inOrder(getRunPropertiesBusiness, getGabaritBusiness, getInParamsBusiness, loadTasksService);
        order.verify(getRunPropertiesBusiness).execute(any(RunIdDto.class));
        order.verify(getGabaritBusiness).getAndPrepareGabarit(any(), any());
        order.verify(getInParamsBusiness).execute(run);
        order.verify(loadTasksService).loadTasks(run);
    }

    @Test
    @DisplayName("Should record ERROR (not propagate) when runStartUpdateBusiness throws")
    void shouldPropagateExceptionFromStartUpdate() {
        doThrow(new RuntimeException("start failed")).when(runStartUpdateBusiness).execute(any(Run.class));

        // runProcessor catches top-level failures, marks the run ERROR, and still runs End_Run in the
        // finally block (parity: .NET Run_Base.Launch try/catch/finally) — it does NOT propagate.
        Run result = processRunService.runProcessor(new RunIdDto(1));

        assertEquals(RunStatus.ERROR, result.getStatus());
        verify(getRunPropertiesBusiness, never()).execute(any());
        verify(endRunBusiness, atLeastOnce()).execute(any(Run.class));
    }

    @Test
    @DisplayName("Should propagate exception thrown during load")
    void shouldPropagateExceptionFromLoad() {
        when(getRunPropertiesBusiness.execute(any(RunIdDto.class)))
                .thenThrow(new RuntimeException("properties failed"));

        Run run = new Run();
        run.setId(1);
        assertThrows(RuntimeException.class, () -> processRunService.load(run));
    }

    // --- getRunProperties ---

    @Test
    @DisplayName("Should return RunProperties from business layer")
    void shouldReturnRunPropertiesFromBusiness() {
        RunIdDto dto = new RunIdDto(99);
        when(getRunPropertiesBusiness.execute(dto)).thenReturn(runProperties);

        RunProperties result = processRunService.getRunProperties(dto);

        assertNotNull(result);
        assertSame(runProperties, result);
        verify(getRunPropertiesBusiness, times(1)).execute(dto);
    }

    // --- fetchActiveRunIds ---

    @Test
    @DisplayName("Should return empty list for fetchActiveRunIds")
    void shouldReturnEmptyListForFetchActiveRunIds() {
        List<Integer> result = processRunService.fetchActiveRunIds();

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }
}
```

---

## Apply checklist
- [ ] `GetGabaritBusinessTest.java` — 4 fileFullPath lines → all-backslash
- [ ] `EngineServiceControllerTest.java` — 2 `doNothing()` → `thenReturn(null)`
- [ ] Replace `ProcessRunServiceImplTest.java`
- [ ] `mvn test` → expect green (309 tests, 0 failures)
