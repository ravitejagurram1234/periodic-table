# Test Fixes — 9 failing tests (build compiles; failures are all test-side)

Date: 2026-07-13. `mvn clean package` compiled 58 sources fine. The 9 failures are stale tests, from two root causes:

| Root cause | Why it fails | Tests affected |
|---|---|---|
| **A. `sendRunId` (singular) expected, but prod batches via `sendRunIds(list)`** | The mock records `sendRunIds(...)`; the internal per-run `sendRunId` is never invoked on a mock → "Wanted but not invoked" + unused-stub errors | `BatchServiceControllerTest` (3), `ReInitiatePendingRunsServiceImplTest` (2) |
| **B. DID-completeness check** (`isIdentityDefined`) added in the corrections | Test `DocumentIdentity` builders omit `dueDate`/`generationDateTime` (and some omit `idFndCode/idRun/idLangue`) → identity is rejected → run skipped (size 0) and the `createRunUpload` stub goes unused | `CheckUploadsServiceImplTest` (4) |

**Decision applied:** keep the stricter DID validation (it restores old `Is_Defined` parity) and **fix the fixtures** to supply complete identities — the correct direction. Resilience-to-broker-failure coverage is moved to `RabbitMqProducerTest`, where that behavior actually lives (inside `sendRunIds`).

Nothing in `src/main` changes. Replace the four test files below in full.

> Note: `CheckUploadsServiceImpl` publishes with `sendRunId` **(singular, in a loop)**, so the `verify(...).sendRunId(500)` in `CheckUploadsServiceImplTest` is **correct and stays**. Only `ReInitiatePendingRunsServiceImpl` and `BatchServiceController.executeRuns` use `sendRunIds` (batch) — those are the ones whose verifications change.

---

## 1. `src/test/java/com/socgen/sgs/api/quark/batch/service/impl/CheckUploadsServiceImplTest.java`

Only the four `DocumentIdentity` builders change (completed via a `validIdentity(...)` helper) + one import. Full file:

```java
package com.socgen.sgs.api.quark.batch.service.impl;

import com.socgen.sgs.api.quark.batch.business.*;
import com.socgen.sgs.api.quark.batch.domain.DocumentIdentity;
import com.socgen.sgs.api.quark.batch.domain.UploadDocumentDomain;
import com.socgen.sgs.api.quark.batch.dto.CreateRunUploadResultDTO;
import com.socgen.sgs.api.quark.batch.dto.RunIdDto;
import com.socgen.sgs.api.quark.batch.service.DocumentPoolService;
import com.socgen.sgs.api.quark.batch.service.QuarkXPressServerXmlService;
import com.socgen.sgs.api.quark.batch.service.S3UploadService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class CheckUploadsServiceImplTest {

    @Mock private NewUploadsBusiness newUploadsBusiness;
    @Mock private UploadDocumentBusiness uploadDocumentBusiness;
    @Mock private S3UploadService s3UploadService;
    @Mock private QuarkXPressServerXmlService quarkXPressServerXmlService;
    @Mock private DocumentPoolService qxpsDocumentPoolService;
    @Mock private CreateRunUploadBusiness createRunUploadBusiness;
    @Mock private RabbitMqProducer rabbitMqProducer;
    @Mock private UploadErrorBusiness uploadErrorBusiness;
    @InjectMocks private CheckUploadsServiceImpl service;

    /** A DID that satisfies isIdentityDefined(): all id fields non-zero + both dates present. */
    private DocumentIdentity validIdentity(String idSuivi) {
        return DocumentIdentity.builder()
                .idFndCode("101")
                .idSuivi(idSuivi)
                .idRun("300")
                .idLangue("1")
                .dueDate(LocalDateTime.of(2024, 12, 1, 0, 0, 0))
                .generationDateTime(LocalDateTime.of(2025, 6, 25, 6, 31, 36))
                .idUnitCode("101223")
                .build();
    }

    @Test
    void checkUploads_noNewUploads_returnsEmpty() {
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(Collections.emptyList());
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
    }

    @Test
    void checkUploads_successfulFlow_returnsRunIds() throws Exception {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        UploadDocumentDomain withContent = new UploadDocumentDomain(100, new byte[]{1, 2, 3});
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(withContent);
        when(s3UploadService.uploadDocument(eq(100), any())).thenReturn("s3key");
        when(qxpsDocumentPoolService.fetchXmlForBox(eq("UP_100.qxp"), eq("DID"))).thenReturn("<xml>content</xml>");
        when(quarkXPressServerXmlService.getElementValueByIdName(anyString(), eq("DID")))
                .thenReturn("101|200|300|1|12/01/2024 00:00:00|06/25/2025 06:31:36|101223");
        when(quarkXPressServerXmlService.parseDocumentIdentity(anyString())).thenReturn(validIdentity("200"));
        when(createRunUploadBusiness.createRunUpload(200, 100)).thenReturn(new CreateRunUploadResultDTO(500));
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).hasSize(1);
        assertThat(result.get(0).getRunId()).isEqualTo(500);
        verify(rabbitMqProducer).sendRunId(500);
    }

    @Test
    void checkUploads_emptyXmlResponse_addsError() throws Exception {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        UploadDocumentDomain withContent = new UploadDocumentDomain(100, new byte[]{1});
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(withContent);
        when(s3UploadService.uploadDocument(eq(100), any())).thenReturn("key");
        when(qxpsDocumentPoolService.fetchXmlForBox(anyString(), eq("DID"))).thenReturn("");
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
        verify(uploadErrorBusiness).updateUploadsWithErrors(anyList());
    }

    @Test
    void checkUploads_didNotFoundInXml_addsError() throws Exception {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        UploadDocumentDomain withContent = new UploadDocumentDomain(100, new byte[]{1});
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(withContent);
        when(s3UploadService.uploadDocument(eq(100), any())).thenReturn("key");
        when(qxpsDocumentPoolService.fetchXmlForBox(anyString(), eq("DID"))).thenReturn("<xml/>");
        when(quarkXPressServerXmlService.getElementValueByIdName(anyString(), eq("DID"))).thenReturn(null);
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
        verify(uploadErrorBusiness).updateUploadsWithErrors(anyList());
    }

    @Test
    void checkUploads_runInExecution_addsError() throws Exception {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        UploadDocumentDomain withContent = new UploadDocumentDomain(100, new byte[]{1});
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(withContent);
        when(s3UploadService.uploadDocument(eq(100), any())).thenReturn("key");
        when(qxpsDocumentPoolService.fetchXmlForBox(anyString(), eq("DID"))).thenReturn("<xml/>");
        when(quarkXPressServerXmlService.getElementValueByIdName(anyString(), eq("DID"))).thenReturn("val");
        when(quarkXPressServerXmlService.parseDocumentIdentity(anyString())).thenReturn(validIdentity("200"));
        when(createRunUploadBusiness.createRunUpload(200, 100)).thenReturn(new CreateRunUploadResultDTO(-1));
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
        verify(uploadErrorBusiness).updateUploadsWithErrors(anyList());
    }

    @Test
    void checkUploads_suiviLocked_addsError() throws Exception {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        UploadDocumentDomain withContent = new UploadDocumentDomain(100, new byte[]{1});
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(withContent);
        when(s3UploadService.uploadDocument(eq(100), any())).thenReturn("key");
        when(qxpsDocumentPoolService.fetchXmlForBox(anyString(), eq("DID"))).thenReturn("<xml/>");
        when(quarkXPressServerXmlService.getElementValueByIdName(anyString(), eq("DID"))).thenReturn("val");
        when(quarkXPressServerXmlService.parseDocumentIdentity(anyString())).thenReturn(validIdentity("200"));
        when(createRunUploadBusiness.createRunUpload(200, 100)).thenReturn(new CreateRunUploadResultDTO(-2));
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
        verify(uploadErrorBusiness).updateUploadsWithErrors(anyList());
    }

    @Test
    void checkUploads_exceptionDuringProcessing_addsError() throws Exception {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        UploadDocumentDomain withContent = new UploadDocumentDomain(100, new byte[]{1});
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(withContent);
        // QXPS pool add throws -> whole upload fails (S3 is non-critical and must NOT be the failure trigger)
        when(s3UploadService.uploadDocument(eq(100), any())).thenReturn("key");
        doThrow(new RuntimeException("qxps fail"))
                .when(qxpsDocumentPoolService).addFileToPool(anyString(), any());
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
        verify(uploadErrorBusiness).updateUploadsWithErrors(anyList());
    }

    @Test
    void checkUploads_rabbitMqFailsForRun_doesNotThrow() throws Exception {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        UploadDocumentDomain withContent = new UploadDocumentDomain(100, new byte[]{1});
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(withContent);
        when(s3UploadService.uploadDocument(eq(100), any())).thenReturn("key");
        when(qxpsDocumentPoolService.fetchXmlForBox(anyString(), eq("DID"))).thenReturn("<xml/>");
        when(quarkXPressServerXmlService.getElementValueByIdName(anyString(), eq("DID"))).thenReturn("val");
        when(quarkXPressServerXmlService.parseDocumentIdentity(anyString())).thenReturn(validIdentity("200"));
        when(createRunUploadBusiness.createRunUpload(200, 100)).thenReturn(new CreateRunUploadResultDTO(500));
        doThrow(new RuntimeException("mq fail")).when(rabbitMqProducer).sendRunId(500);
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).hasSize(1);
    }

    @Test
    void checkUploads_errorUpdateFails_doesNotThrow() throws Exception {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        UploadDocumentDomain withContent = new UploadDocumentDomain(100, new byte[]{1});
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(withContent);
        when(s3UploadService.uploadDocument(eq(100), any())).thenReturn("key");
        doThrow(new RuntimeException("qxps fail"))
                .when(qxpsDocumentPoolService).addFileToPool(anyString(), any());
        when(uploadErrorBusiness.updateUploadsWithErrors(anyList())).thenThrow(new RuntimeException("db error"));
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
    }
}
```

> Two tests (`exceptionDuringProcessing`, `errorUpdateFails`) originally forced the failure via `s3UploadService...thenThrow`. Since the corrected code makes **S3 non-critical** (it no longer fails the upload), those must now trigger the failure through a critical step — `qxpsDocumentPoolService.addFileToPool(...)`. Updated above. (If you left S3 in the critical path, revert those two to the S3 `thenThrow` form — but then the "S3 is non-critical" fix is gone.)

---

## 2. `src/test/java/com/socgen/sgs/api/quark/batch/service/impl/ReInitiatePendingRunsServiceImplTest.java`

`sendRunId(x)` → `sendRunIds(anyList())`. The old `reInitiatePendingRuns_rabbitMqFails_continuesProcessing` is removed — that resilience now lives in `sendRunIds` and is covered in `RabbitMqProducerTest` (§4). Full file:

```java
package com.socgen.sgs.api.quark.batch.service.impl;

import com.socgen.sgs.api.quark.batch.business.RunResetAndInitiateBusiness;
import com.socgen.sgs.api.quark.batch.domain.RunDomain;
import com.socgen.sgs.api.quark.batch.dto.RunIdDto;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ReInitiatePendingRunsServiceImplTest {

    @Mock
    private RunResetAndInitiateBusiness runResetAndInitiateBusiness;
    @Mock
    private RabbitMqProducer rabbitMqProducer;
    @InjectMocks
    private ReInitiatePendingRunsServiceImpl service;

    @Test
    void reInitiatePendingRuns_withRuns_sendsToRabbitMq() {
        when(runResetAndInitiateBusiness.getRunsToBeInitiated())
                .thenReturn(Arrays.asList(new RunDomain(10), new RunDomain(20)));
        List<RunIdDto> result = service.reInitiatePendingRuns();
        assertThat(result).hasSize(2);
        verify(runResetAndInitiateBusiness).resetRunsStatus();
        verify(rabbitMqProducer).sendRunIds(anyList());
    }

    @Test
    void reInitiatePendingRuns_emptyRuns_noRabbitMqCalls() {
        when(runResetAndInitiateBusiness.getRunsToBeInitiated()).thenReturn(Collections.emptyList());
        List<RunIdDto> result = service.reInitiatePendingRuns();
        assertThat(result).isEmpty();
        verify(runResetAndInitiateBusiness).resetRunsStatus();
        verifyNoInteractions(rabbitMqProducer);
    }

    @Test
    void reInitiatePendingRuns_nullRuns_returnsEmpty() {
        when(runResetAndInitiateBusiness.getRunsToBeInitiated()).thenReturn(null);
        List<RunIdDto> result = service.reInitiatePendingRuns();
        assertThat(result).isEmpty();
    }

    @Test
    void reInitiatePendingRuns_resetThrows_propagatesException() {
        doThrow(new RuntimeException("reset failed")).when(runResetAndInitiateBusiness).resetRunsStatus();
        assertThatThrownBy(() -> service.reInitiatePendingRuns())
                .isInstanceOf(RuntimeException.class).hasMessage("reset failed");
    }
}
```

---

## 3. `src/test/java/com/socgen/sgs/api/quark/batch/infra/api/v1/BatchServiceControllerTest.java`

`executeRuns_success` now verifies `sendRunIds`. The two `*_handledGracefully` tests (which stubbed the never-called `sendRunId`) are replaced by one that exercises the real graceful path added in the corrections — `executeRuns` keeps going even if `checkUploads()` throws. Full file:

```java
package com.socgen.sgs.api.quark.batch.infra.api.v1;

import com.socgen.sgs.api.quark.batch.business.UpdateRunsStatusBusiness;
import com.socgen.sgs.api.quark.batch.dto.RunIdDto;
import com.socgen.sgs.api.quark.batch.service.CheckUploadsService;
import com.socgen.sgs.api.quark.batch.service.ProcessPlannedRunsService;
import com.socgen.sgs.api.quark.batch.service.QuarkXPressServerXmlService;
import com.socgen.sgs.api.quark.batch.service.ReInitiatePendingRunsService;
import com.socgen.sgs.api.quark.batch.service.impl.RabbitMqProducer;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class BatchServiceControllerTest {

    @Mock private CheckUploadsService checkUploadsService;
    @Mock private ProcessPlannedRunsService processPlannedRunsService;
    @Mock private ReInitiatePendingRunsService reInitiatePendingRunsService;
    @Mock private QuarkXPressServerXmlService quarkXPressServerXmlService;
    @Mock private UpdateRunsStatusBusiness updateRunsStatusBusiness;
    @Mock private RabbitMqProducer rabbitMqProducer;
    @InjectMocks private BatchServiceController controller;

    @Test
    void getNewUploads_returnsOk() {
        when(checkUploadsService.checkUploads()).thenReturn(List.of(new RunIdDto(1)));
        ResponseEntity<List<RunIdDto>> response = controller.getNewUploads();
        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody()).hasSize(1);
    }

    @Test
    void fetchPlannedRuns_returnsOk() {
        when(processPlannedRunsService.ProcessPlannedRuns()).thenReturn(List.of(new RunIdDto(2)));
        ResponseEntity<List<RunIdDto>> response = controller.fetchPlannedRuns();
        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody()).hasSize(1);
    }

    @Test
    void reInitiatePendingRuns_returnsOk() {
        when(reInitiatePendingRunsService.reInitiatePendingRuns()).thenReturn(List.of());
        ResponseEntity<List<RunIdDto>> response = controller.reInitiatePendingRuns();
        assertThat(response.getStatusCode().value()).isEqualTo(200);
    }

    @Test
    void executeRuns_success() {
        ResponseEntity<String> response = controller.executeRuns(List.of(1, 2));
        verify(updateRunsStatusBusiness).updateRunsStatus(anyList());
        verify(checkUploadsService).checkUploads();
        verify(rabbitMqProducer).sendRunIds(anyList());
        assertThat(response.getBody()).contains("2 run IDs");
        assertThat(response.getStatusCode().value()).isEqualTo(200);
    }

    @Test
    void executeRuns_checkUploadsFails_stillQueuesRuns() {
        doThrow(new RuntimeException("upload check boom")).when(checkUploadsService).checkUploads();
        ResponseEntity<String> response = controller.executeRuns(List.of(1, 2));
        assertThat(response.getStatusCode().value()).isEqualTo(200);
        verify(updateRunsStatusBusiness).updateRunsStatus(anyList());
        verify(rabbitMqProducer).sendRunIds(anyList());
    }
}
```

> `quarkXPressServerXmlService` is kept as a `@Mock` field only because `@InjectMocks` expects the controller's constructor args to be satisfiable; unused `@Mock` fields don't trigger strict-stubbing errors. If the controller constructor does **not** take it, delete that field + import.

---

## 4. `src/test/java/com/socgen/sgs/api/quark/batch/service/impl/RabbitMqProducerTest.java`

Adds the broker-failure resilience coverage that used to live (incorrectly) in the service/controller tests — here `rabbitMqProducer` is the real object and `rabbitTemplate` is the mock, so we can actually simulate a per-run failure. Full file:

```java
package com.socgen.sgs.api.quark.batch.service.impl;

import com.socgen.sgs.api.quark.batch.config.RabbitMqConfig;
import com.socgen.sgs.api.quark.batch.dto.RunIdDto;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.amqp.AmqpIOException;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import java.io.IOException;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class RabbitMqProducerTest {

    @Mock
    private RabbitTemplate rabbitTemplate;

    @InjectMocks
    private RabbitMqProducer rabbitMqProducer;

    @Test
    void sendRunId_sendsToCorrectQueue() throws Exception {
        RabbitMqConfig.BATCH_RUN_QUEUE = "test-queue";
        rabbitMqProducer.sendRunId(42);
        verify(rabbitTemplate).convertAndSend("", "test-queue", 42);
    }

    @Test
    void sendRunIds_whenOneRunFails_continuesWithoutThrowing() {
        RabbitMqConfig.BATCH_RUN_QUEUE = "test-queue";
        doThrow(new AmqpIOException(new IOException("boom")))
                .when(rabbitTemplate).convertAndSend("", "test-queue", 1);
        assertDoesNotThrow(() ->
                rabbitMqProducer.sendRunIds(List.of(new RunIdDto(1), new RunIdDto(2))));
        // the second run is still attempted despite the first failing
        verify(rabbitTemplate).convertAndSend("", "test-queue", 2);
    }

    @Test
    void sendRunIds_emptyList_doesNothing() {
        rabbitMqProducer.sendRunIds(List.of());
        verifyNoInteractions(rabbitTemplate);
    }
}
```

> This assumes `RabbitMqConfig.BATCH_RUN_QUEUE` is a `public static` field (the existing test already assigns it directly, so it must be). If yours is `private` with a setter, swap the two `RabbitMqConfig.BATCH_RUN_QUEUE = "test-queue";` lines for `new RabbitMqConfig().setBatchRunQueue("test-queue");`.

---

## After applying

```
mvn -q clean test
```
Expected: `Tests run: 92, Failures: 0, Errors: 0` (was 93 run / 5 failures / 4 errors — the count drops by 1 because the redundant `reInitiatePendingRuns_rabbitMqFails_continuesProcessing` is removed and 2 broker-resilience tests are added to `RabbitMqProducerTest`, while 2 controller tests collapse into 1).

## One thing to confirm (not a blocker)
The `[WARNING] setPlsqlIndexTable(...) has been deprecated` lines on `UpdateRunsStatusDaoImpl` and `UploadErrorDaoImpl` are **expected** — that Oracle API is marked deprecated but is still the correct/only way to bind PL/SQL associative arrays. No action; just don't "fix" the warning by switching to `Types.ARRAY` (that's the bug we removed).
