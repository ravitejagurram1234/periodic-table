# Test Fixes — v2 (corrected)

Date: 2026-07-13. Build compiles; the 9 failures are stale test code. **v2 corrects two mistakes from v1:**
- ❌ v1 referenced `ProcessPlannedRunsService` in the controller test — that class was **deleted**, so it's removed here entirely (§3).
- ❌ v1 assigned `RabbitMqConfig.BATCH_RUN_QUEUE` directly — that field is **private**. §4 now sets it through the public setter `setBatchRunQueue(...)`.

Root causes of the original failures:

| Root cause | Tests affected |
|---|---|
| **A.** Prod publishes via `sendRunIds(list)`, tests expected `sendRunId(x)` (singular) | `BatchServiceControllerTest`, `ReInitiatePendingRunsServiceImplTest` |
| **B.** DID-completeness check rejects fixtures missing `dueDate`/`generationDateTime` (+ other id fields) | `CheckUploadsServiceImplTest` |

Replace the four test files below in full. No `src/main` change.

> `CheckUploadsServiceImpl` publishes with `sendRunId` **(singular, in a loop)**, so `verify(...).sendRunId(500)` in §1 is **correct and stays**. Only `ReInitiatePendingRunsServiceImpl` and `BatchServiceController.executeRuns` use `sendRunIds`.

---

## ⚠️ One thing to confirm before pasting §3

Since you deleted the `ProcessPlannedRuns*` vertical, the corrected `BatchServiceControllerTest` (§3) assumes the controller's **current constructor** takes exactly these four dependencies:

```
BatchServiceController(CheckUploadsService, ReInitiatePendingRunsService, UpdateRunsStatusBusiness, RabbitMqProducer)
```

If your controller constructor differs (e.g. still injects something else), tell me / paste the current `BatchServiceController.java` and I'll match it — I won't guess the constructor blind again.

**Ripple from deleting `ProcessPlannedRuns*`** — these also reference it and must be deleted/updated or the module won't compile (check on your laptop):
- `main`: `ProcessPlannedRunsScheduler`, `ProcessPlannedRunsServiceImpl`, `service/ProcessPlannedRunsService`
- `test`: `ProcessPlannedRunsSchedulerTest`, `ProcessPlannedRunsServiceImplTest`
- and the `fetchPlannedRuns` endpoint in `BatchServiceController`
- functional note (just confirming you intend this): with that vertical gone, the hourly `Get_Runs` planned-run dispatch no longer runs — planned runs would only move if another flow now covers them.

---

## 1. `src/test/java/com/socgen/sgs/api/quark/batch/service/impl/CheckUploadsServiceImplTest.java`

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

> The last two tests now trigger failure via `qxpsDocumentPoolService.addFileToPool(...)` (a critical step) instead of `s3UploadService...thenThrow`, because the corrected code makes S3 **non-critical**. If you kept S3 in the critical path, revert those two to the S3 `thenThrow` form.

---

## 2. `src/test/java/com/socgen/sgs/api/quark/batch/service/impl/ReInitiatePendingRunsServiceImplTest.java`

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

**All `ProcessPlannedRuns` references removed.** Assumes the 4-dependency constructor noted at the top.

```java
package com.socgen.sgs.api.quark.batch.infra.api.v1;

import com.socgen.sgs.api.quark.batch.business.UpdateRunsStatusBusiness;
import com.socgen.sgs.api.quark.batch.dto.RunIdDto;
import com.socgen.sgs.api.quark.batch.service.CheckUploadsService;
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
    @Mock private ReInitiatePendingRunsService reInitiatePendingRunsService;
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

> If `executeRuns` in your controller does **not** call `checkUploadsService.checkUploads()` (i.e. you didn't take that correction), delete the `verify(checkUploadsService).checkUploads();` line and the whole `executeRuns_checkUploadsFails_stillQueuesRuns` test.

---

## 4. `src/test/java/com/socgen/sgs/api/quark/batch/service/impl/RabbitMqProducerTest.java`

**Uses the public setter** — `BATCH_RUN_QUEUE` is private, so it's assigned via `new RabbitMqConfig().setBatchRunQueue(...)` (the setter writes the static field).

```java
package com.socgen.sgs.api.quark.batch.service.impl;

import com.socgen.sgs.api.quark.batch.config.RabbitMqConfig;
import com.socgen.sgs.api.quark.batch.dto.RunIdDto;
import org.junit.jupiter.api.BeforeEach;
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

    @Mock private RabbitTemplate rabbitTemplate;
    @InjectMocks private RabbitMqProducer rabbitMqProducer;

    @BeforeEach
    void setQueueName() {
        // BATCH_RUN_QUEUE has private access; set it via the public setter (it writes the static field).
        new RabbitMqConfig().setBatchRunQueue("test-queue");
    }

    @Test
    void sendRunId_sendsToCorrectQueue() throws Exception {
        rabbitMqProducer.sendRunId(42);
        verify(rabbitTemplate).convertAndSend("", "test-queue", 42);
    }

    @Test
    void sendRunIds_whenOneRunFails_continuesWithoutThrowing() {
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

> If your `RabbitMqConfig` setter is named differently, adjust the `setQueueName()` line accordingly. From the version I reviewed it is `public void setBatchRunQueue(String queueName)`.

---

## After applying
```
mvn -q clean test
```
Expected: 0 failures/0 errors (once the `ProcessPlannedRuns*` ripple files listed at the top are also removed on your side).
