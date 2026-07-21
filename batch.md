# Quark Batch Job — Final Changes + Review

> Single source of truth for every change applied to the working tree. All code is the **final** content
> (copy-paste ready); code comments contain only literal logic.
>
> **Build note:** the parent POM (`com.socgen.sgs.sgs-stack:sgs-api-core:11.4.0`) sits on SocGen’s internal
> Artifactory and was unreachable from my environment, so I could **not** compile/run tests here. Changes were
> made against the real Oracle package `QXP_PK_BATCH` and verified statically. **Run `mvn clean test` on the
> corporate network to confirm.**
>
> **Parity:** behavior matches the old .NET service. The upload/purge flow, DID validation, status codes, and
> startup recovery mirror the old code; the only intentional differences are the ones you approved
> (24/7 polling instead of the fixed planning window, hourly crons, RabbitMQ instead of the in-memory queue,
> and the additive S3 step).

---

## 1. Files to DELETE

```
src/main/java/com/socgen/sgs/api/quark/batch/service/ProcessRunsService.java
src/main/java/com/socgen/sgs/api/quark/batch/service/impl/ProcessRunsServiceImpl.java
src/test/java/com/socgen/sgs/api/quark/batch/service/impl/ProcessRunsServiceImplTest.java
src/main/java/com/socgen/sgs/api/quark/batch/scheduler/ReInitiatePendingRunsScheduler.java
src/test/java/com/socgen/sgs/api/quark/batch/scheduler/ReInitiatePendingRunsSchedulerTest.java
```

---

## 2. New / modified files (final content)

### 2.1 `infra/dao/impl/UploadErrorDaoImpl.java`

```java
package com.socgen.sgs.api.quark.batch.infra.dao.impl;

import com.socgen.sgs.api.quark.batch.dto.UploadErrorDTO;
import com.socgen.sgs.api.quark.batch.infra.dao.UploadErrorDao;
import oracle.jdbc.OracleCallableStatement;
import oracle.jdbc.OracleTypes;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.util.List;

@Repository
public class UploadErrorDaoImpl implements UploadErrorDao {

    private static final Logger logger = LoggerFactory.getLogger(UploadErrorDaoImpl.class);

    /** VarCharArray element type is VARCHAR2(200); clamp messages to avoid ORA-06502. */
    private static final int MAX_MESSAGE_LENGTH = 200;

    private final DataSource dataSource;

    @Autowired
    public UploadErrorDaoImpl(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @Override
    public Integer updateUploadsWithErrors(List<UploadErrorDTO> uploadErrors) {
        if (uploadErrors == null || uploadErrors.isEmpty()) {
            return 0;
        }

        // Build parallel arrays from upload errors
        int[] errorIds = new int[uploadErrors.size()];
        String[] errorMessages = new String[uploadErrors.size()];
        for (int i = 0; i < uploadErrors.size(); i++) {
            errorIds[i] = uploadErrors.get(i).getUploadId();
            errorMessages[i] = clampMessage(uploadErrors.get(i).getErrorMessage());
        }

        // UPDATE_UPLOAD_WITH_ERRORS is a function returning the updated row count. Its parameters are PL/SQL
        // associative arrays (TABLE OF ... INDEX BY BINARY_INTEGER), not SQL collection types, so they must
        // be bound with setPlsqlIndexTable rather than Types.ARRAY.
        try (Connection conn = dataSource.getConnection();
             CallableStatement cs = conn.prepareCall(
                     "{ ? = call QXP_PK_BATCH.UPDATE_UPLOAD_WITH_ERRORS(?, ?) }")) {

            OracleCallableStatement oraCs = cs.unwrap(OracleCallableStatement.class);
            oraCs.registerOutParameter(1, OracleTypes.NUMBER);
            oraCs.setPlsqlIndexTable(2, errorIds, errorIds.length, errorIds.length,
                    OracleTypes.NUMBER, 0);
            oraCs.setPlsqlIndexTable(3, errorMessages, errorMessages.length, errorMessages.length,
                    OracleTypes.VARCHAR, MAX_MESSAGE_LENGTH);

            oraCs.execute();
            int rowsUpdated = oraCs.getInt(1);
            logger.info("Flagged {} upload(s) with errors", rowsUpdated);
            return rowsUpdated;
        } catch (Exception e) {
            logger.error("Error updating uploads with errors", e);
            throw new RuntimeException("Failed to update uploads with errors", e);
        }
    }

    private static String clampMessage(String message) {
        if (message == null) {
            return "";
        }
        return message.length() > MAX_MESSAGE_LENGTH
                ? message.substring(0, MAX_MESSAGE_LENGTH)
                : message;
    }
}
```

### 2.2 `service/impl/CheckUploadsServiceImpl.java`

```java
package com.socgen.sgs.api.quark.batch.service.impl;

import com.socgen.sgs.api.quark.batch.business.CreateRunUploadBusiness;
import com.socgen.sgs.api.quark.batch.business.NewUploadsBusiness;
import com.socgen.sgs.api.quark.batch.business.UploadDocumentBusiness;
import com.socgen.sgs.api.quark.batch.business.UploadErrorBusiness;
import com.socgen.sgs.api.quark.batch.domain.DocumentIdentity;
import com.socgen.sgs.api.quark.batch.domain.UploadDocumentDomain;
import com.socgen.sgs.api.quark.batch.dto.CreateRunUploadResultDTO;
import com.socgen.sgs.api.quark.batch.dto.RunIdDto;
import com.socgen.sgs.api.quark.batch.dto.UploadDocumentDTO;
import com.socgen.sgs.api.quark.batch.dto.UploadErrorDTO;
import com.socgen.sgs.api.quark.batch.service.DocumentPoolService;
import com.socgen.sgs.api.quark.batch.mapper.UploadDocumentMapper;
import com.socgen.sgs.api.quark.batch.service.CheckUploadsService;
import com.socgen.sgs.api.quark.batch.service.QuarkXPressServerXmlService;
import com.socgen.sgs.api.quark.batch.service.S3UploadService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

@Service
public class CheckUploadsServiceImpl implements CheckUploadsService {

    private static final Logger logger = LoggerFactory.getLogger(CheckUploadsServiceImpl.class);

    private final NewUploadsBusiness newUploadsBusiness;
    private final UploadDocumentBusiness uploadDocumentBusiness;
    private final S3UploadService s3UploadService;
    private final QuarkXPressServerXmlService quarkXPressServerXmlService;
    private final DocumentPoolService qxpsDocumentPoolService;
    private final CreateRunUploadBusiness createRunUploadBusiness;
    private final RabbitMqProducer rabbitMqProducer;
    private final UploadErrorBusiness uploadErrorBusiness;

    public CheckUploadsServiceImpl(NewUploadsBusiness newUploadsBusiness,
                                   UploadDocumentBusiness uploadDocumentBusiness,
                                   S3UploadService s3UploadService,
                                   QuarkXPressServerXmlService quarkXPressServerXmlService,
                                   DocumentPoolService qxpsDocumentPoolService,
                                   CreateRunUploadBusiness createRunUploadBusiness,
                                   RabbitMqProducer rabbitMqProducer,
                                   UploadErrorBusiness uploadErrorBusiness) {
        this.newUploadsBusiness = newUploadsBusiness;
        this.uploadDocumentBusiness = uploadDocumentBusiness;
        this.s3UploadService = s3UploadService;
        this.quarkXPressServerXmlService = quarkXPressServerXmlService;
        this.qxpsDocumentPoolService = qxpsDocumentPoolService;
        this.createRunUploadBusiness = createRunUploadBusiness;
        this.rabbitMqProducer = rabbitMqProducer;
        this.uploadErrorBusiness = uploadErrorBusiness;
    }

    @Override
    public List<RunIdDto> checkUploads() {
        // 1–3: Get new uploads, log, exit if empty
        List<UploadDocumentDTO> newUploads = getNewUploads();
        logger.info("Found {} new upload(s)", newUploads.size());
        if (newUploads.isEmpty()) {
            return List.of();
        }

        // 4: Fetch blob content from DB
        List<UploadDocumentDTO> uploadDocuments = getUploadDocuments(newUploads);
        logger.info("Processing {} uploads with content", uploadDocuments.size());

        // 5: Accumulators for successful run IDs and errors
        List<RunIdDto> runIdsToBeLaunched = new ArrayList<>();
        List<UploadErrorDTO> uploadErrors = new ArrayList<>();
        int successCount = 0;
        int failureCount = 0;

        // 6: Per-upload processing loop
        for (UploadDocumentDTO doc : uploadDocuments) {
            Integer uploadId = doc.getUploadId();
            try {
                // 6a: Upload to S3 is best-effort — an S3 failure must not block run creation, so it is
                // caught and logged here rather than propagated.
                try {
                    String s3Key = s3UploadService.uploadDocument(uploadId, doc.getContenu());
                    logger.info("Uploaded to S3. Upload ID: {}, S3 Key: {}", uploadId, s3Key);
                } catch (Exception e) {
                    logger.warn("S3 upload failed for Upload ID {} (non-critical, continuing)", uploadId, e);
                }

                // 6a2: Add file to QuarkXPress Server document pool
                String documentName = constructDocumentName(uploadId);
                boolean addedToPool = false;
                try {
                    qxpsDocumentPoolService.addFileToPool(documentName, doc.getContenu());
                    addedToPool = true;

                    // 6b: Fetch XML metadata (DID box) from QuarkXPress Server
                    String xmlContent = qxpsDocumentPoolService.fetchXmlForBox(documentName, "DID");
                    if (xmlContent == null || xmlContent.isBlank()) {
                        String errorMsg = "Empty XML response from QXPS";
                        logger.error("{}. Upload ID: {}", errorMsg, uploadId);
                        uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                        failureCount++;
                        continue;
                    }
                    logger.debug("XML content received for Upload ID {}: length={}", uploadId, xmlContent.length());
                    String didValue = quarkXPressServerXmlService.getElementValueByIdName(xmlContent, "DID");
                    if (didValue == null || didValue.isBlank()) {
                        String errorMsg = "DID not found in XML";
                        logger.error("{}. Upload ID: {}", errorMsg, uploadId);
                        uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                        failureCount++;
                        continue;
                    }
                    DocumentIdentity identity = quarkXPressServerXmlService.parseDocumentIdentity(didValue);
                    if (!identity.isDefined()) {
                        String errorMsg = "Invalid DID fields";
                        logger.error("{}. Upload ID: {}", errorMsg, uploadId);
                        uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                        failureCount++;
                        continue;
                    }
                    Integer idSuivi = Integer.parseInt(identity.getIdSuivi());
                    logger.info("Extracted metadata. Upload ID: {}, Suivi ID: {}", uploadId, idSuivi);

                    // 6c: Create run via stored procedure
                    CreateRunUploadResultDTO result = createRunUploadBusiness.createRunUpload(idSuivi, uploadId);

                    // 6d: Handle result codes
                    if (result.isSuccess()) {
                        logger.info("Run created. Upload ID: {}, Run ID: {}", uploadId, result.getRunId());
                        runIdsToBeLaunched.add(new RunIdDto(result.getRunId()));
                        successCount++;
                    } else if (result.isRunInExecution()) {
                        String errorMsg = "Run already in execution";
                        logger.error("{}. Upload ID: {}, Suivi ID: {}", errorMsg, uploadId, idSuivi);
                        uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                        failureCount++;
                    } else if (result.isSuiviLocked()) {
                        String errorMsg = "Follow-up is locked";
                        logger.error("{}. Upload ID: {}, Suivi ID: {}", errorMsg, uploadId, idSuivi);
                        uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                        failureCount++;
                    } else {
                        String errorMsg = "Error creating run";
                        logger.error("{}. Upload ID: {}, Suivi ID: {}", errorMsg, uploadId, idSuivi);
                        uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                        failureCount++;
                    }
                } finally {
                    // Always remove the file added to the QXPS pool this pass.
                    if (addedToPool) {
                        try {
                            qxpsDocumentPoolService.deleteFileFromPool(documentName);
                        } catch (Exception ex) {
                            logger.warn("Failed to remove {} from QXPS pool", documentName, ex);
                        }
                    }
                }
            } catch (Exception e) {
                String errorMsg = "Failed processing: " + e.getMessage();
                logger.error("{}. Upload ID: {}. Continuing.", errorMsg, uploadId, e);
                uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                failureCount++;
            }
        }

        // 7: Update database with all errors (if any)
        if (!uploadErrors.isEmpty()) {
            try {
                Integer rowsUpdated = uploadErrorBusiness.updateUploadsWithErrors(uploadErrors);
                logger.info("Updated {} upload records with error status", rowsUpdated);
            } catch (Exception e) {
                logger.error("Failed to update error uploads in database", e);
            }
        }

        // 8: Send successful run IDs to RabbitMQ, de-duplicated within this pass. Two uploads for the same
        // suivi resolve to the same run id (Create_Run_Upload takes the update branch), so de-duplicating
        // here prevents publishing the same run id twice.
        java.util.LinkedHashSet<Integer> uniqueRunIds = new java.util.LinkedHashSet<>();
        for (RunIdDto runIdDto : runIdsToBeLaunched) {
            uniqueRunIds.add(runIdDto.getRunId());
        }
        for (Integer runId : uniqueRunIds) {
            try {
                rabbitMqProducer.sendRunId(runId);
                logger.info("Run ID {} queued to RabbitMQ", runId);
            } catch (Exception e) {
                logger.error("Failed to queue Run ID {}.", runId, e);
            }
        }

        logger.info("Completed: {} successful, {} failed", successCount, failureCount);
        return runIdsToBeLaunched;
    }

    private String constructDocumentName(Integer uploadId) {
        return String.format("UP_%d.qxp", uploadId);
    }

    private List<UploadDocumentDTO> getNewUploads() {
        List<UploadDocumentDomain> uploadDocumentDomains = newUploadsBusiness.getNewUploadDocuments();
        return uploadDocumentDomains.stream().map(UploadDocumentMapper:: toDto).toList();
    }

    private List<UploadDocumentDTO> getUploadDocuments(List<UploadDocumentDTO> uploadIds) {
        return uploadIds.stream()
                .map(uploadId -> {
                    UploadDocumentDomain domain = uploadDocumentBusiness.getUploadDocument(uploadId);
                    return UploadDocumentMapper.toDto(domain);
                })
                .toList();
    }
}
```

### 2.3 `infra/api/v1/BatchServiceController.java`

```java
package com.socgen.sgs.api.quark.batch.infra.api.v1;

import com.socgen.sgs.api.quark.batch.business.UpdateRunsStatusBusiness;
import com.socgen.sgs.api.quark.batch.dto.RunIdDto;
import com.socgen.sgs.api.quark.batch.service.CheckUploadsService;
import com.socgen.sgs.api.quark.batch.service.ProcessPlannedRunsService;
import com.socgen.sgs.api.quark.batch.service.ReInitiatePendingRunsService;
import com.socgen.sgs.api.quark.batch.service.impl.RabbitMqProducer;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping(value = "api/v1/batchService")
//@PreAuthorize("hasAuthority('api.quark.v1')")
@Tag(name = "All operations of Batch service", description = "All operations of Batch service")
public class BatchServiceController {

    private static final Logger logger = LoggerFactory.getLogger(BatchServiceController.class);

    private final CheckUploadsService checkUploadsService;
    private final ProcessPlannedRunsService processPlannedRunsService;
    private final ReInitiatePendingRunsService reInitiatePendingRunsService;
    private final UpdateRunsStatusBusiness updateRunsStatusBusiness;
    private final RabbitMqProducer rabbitMqProducer;

    public BatchServiceController(CheckUploadsService checkUploadsService,
                                  ProcessPlannedRunsService processPlannedRunsService,
                                  ReInitiatePendingRunsService reInitiatePendingRunsService,
                                  UpdateRunsStatusBusiness updateRunsStatusBusiness,
                                  RabbitMqProducer rabbitMqProducer) {
        this.checkUploadsService = checkUploadsService;
        this.processPlannedRunsService = processPlannedRunsService;
        this.reInitiatePendingRunsService = reInitiatePendingRunsService;
        this.updateRunsStatusBusiness = updateRunsStatusBusiness;
        this.rabbitMqProducer = rabbitMqProducer;
    }

    @GetMapping(path = "/newUploads")
    @Operation(summary = "Get new upload documents", description = "Triggers checkUploads process and returns the list of run IDs created")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Successfully retrieved new uploads"),
            @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    public ResponseEntity<List<RunIdDto>> getNewUploads() {
        List<RunIdDto> createdRunIds = checkUploadsService.checkUploads();
        return ResponseEntity.ok(createdRunIds);
    }

    @GetMapping(path = "/fetchPlannedRuns")
    @Operation(summary = "Get planned runs", description = "Retrieves a list of new planned runs that need to be processed")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Successfully retrieved new planned runs"),
            @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    public ResponseEntity<List<RunIdDto>> fetchPlannedRuns() {
        List<RunIdDto> plannedRuns = processPlannedRunsService.processPlannedRuns();
        return ResponseEntity.ok(plannedRuns);
    }

    @GetMapping(path = "/reInitiatePendingRuns")
    @Operation(summary = "Re Initiate pending runs", description = "Retrieves a list of runs that fell into pending state and need to be re-initiated")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Successfully retrieved runs to be re-initiated"),
            @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    public ResponseEntity<List<RunIdDto>> reInitiatePendingRuns() {
        List<RunIdDto> runsToBeInitiated = reInitiatePendingRunsService.reInitiatePendingRuns();
        return ResponseEntity.ok(runsToBeInitiated);
    }

    @PostMapping(path = "/executeRuns")
    @Operation(summary = "Execute runs", description = "Execute processing runs for the provided run IDs")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Runs executed successfully"),
            @ApiResponse(responseCode = "400", description = "Bad request"),
            @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    public ResponseEntity<String> executeRuns(@RequestBody List<Integer> runIds) {
        // Convert Integer runIds to RunIdDto objects
        List<RunIdDto> runIdDtos = runIds.stream()
                .map(RunIdDto::new)
                .toList();

        // Update runs status through business layer
        updateRunsStatusBusiness.updateRunsStatus(runIdDtos);

        // Also sweep for new uploads. Best-effort — a failure here must not block the status update or
        // the queueing below.
        try {
            checkUploadsService.checkUploads();
        } catch (Exception e) {
            logger.error("checkUploads failed during executeRuns; continuing to queue the requested runs", e);
        }

        // Send run IDs to RabbitMQ queue
        rabbitMqProducer.sendRunIds(runIdDtos);

        return ResponseEntity.ok().body("Runs executed successfully for " + runIds.size() + " run IDs");
    }
}
```

### 2.4 `scheduler/ProcessPlannedRunsScheduler.java`

```java
package com.socgen.sgs.api.quark.batch.scheduler;

import com.socgen.sgs.api.quark.batch.dto.RunIdDto;
import com.socgen.sgs.api.quark.batch.service.ProcessPlannedRunsService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Scheduled job that dispatches planned runs on the configured cron schedule.
 */
@Component
public class ProcessPlannedRunsScheduler {

    private static final Logger logger = LoggerFactory.getLogger(ProcessPlannedRunsScheduler.class);

    private final ProcessPlannedRunsService processPlannedRunsService;

    public ProcessPlannedRunsScheduler(ProcessPlannedRunsService processPlannedRunsService) {
        this.processPlannedRunsService = processPlannedRunsService;
    }

    /**
     * Runs on the cron configured at scheduler.planned-runs.cron (Europe/Paris).
     * Cron format: second minute hour day month weekday.
     */
    @Scheduled(cron = "${scheduler.planned-runs.cron}", zone = "Europe/Paris")
    public void processPlannedRuns() {
        try {
            List<RunIdDto> processedRuns = processPlannedRunsService.processPlannedRuns();
            logger.info("Scheduled job completed successfully. Processed {} runs",
                processedRuns != null ? processedRuns.size() : 0);
        } catch (Exception e) {
            logger.error("Error occurred while processing planned runs in scheduled job", e);
        }
    }
}
```

### 2.5 `scheduler/CheckUploadsScheduler.java`

```java
package com.socgen.sgs.api.quark.batch.scheduler;

import com.socgen.sgs.api.quark.batch.service.CheckUploadsService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Scheduled job to check for new uploads every hour.
 */
@Component
public class CheckUploadsScheduler {

    private static final Logger logger = LoggerFactory.getLogger(CheckUploadsScheduler.class);

    private final CheckUploadsService checkUploadsService;

    public CheckUploadsScheduler(CheckUploadsService checkUploadsService) {
        this.checkUploadsService = checkUploadsService;
    }

    @Scheduled(cron = "${scheduler.check-uploads.cron}", zone = "Europe/Paris")
    public void checkUploads() {
        try {
            checkUploadsService.checkUploads();
            logger.info("Scheduled job CheckUploads completed successfully");
        } catch (Exception e) {
            logger.error("Error occurred during scheduled CheckUploads job", e);
        }
    }
}
```

### 2.6 `scheduler/StartupRecoveryRunner.java` (NEW)

```java
package com.socgen.sgs.api.quark.batch.scheduler;

import com.socgen.sgs.api.quark.batch.service.ReInitiatePendingRunsService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.annotation.Profile;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Resets stuck runs/uploads and re-initiates pending runs once when the application is ready, recovering
 * any items left mid-flight by a previous shutdown. Also available on demand via
 * {@code GET /api/v1/batchService/reInitiatePendingRuns}.
 * <p>
 * Recovered run ids are re-published, so the run-engine consumer must be idempotent per id_run: a run
 * that is in-flight when this executes is reset (4/5 -> 1) and re-queued.
 */
@Component
@Profile("!test")
public class StartupRecoveryRunner {

    private static final Logger logger = LoggerFactory.getLogger(StartupRecoveryRunner.class);

    private final ReInitiatePendingRunsService reInitiatePendingRunsService;

    public StartupRecoveryRunner(ReInitiatePendingRunsService reInitiatePendingRunsService) {
        this.reInitiatePendingRunsService = reInitiatePendingRunsService;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void recoverOnStartup() {
        try {
            logger.info("Startup recovery: resetting stuck runs/uploads and re-initiating pending runs");
            reInitiatePendingRunsService.reInitiatePendingRuns();
        } catch (Exception e) {
            logger.error("Startup recovery failed (application will continue)", e);
        }
    }
}
```

### 2.7 `service/DocumentPoolService.java`

```java
package com.socgen.sgs.api.quark.batch.service;

/**
 * Port interface for interacting with QuarkXPress Server document pool.
 * Implementations reside in the infra layer.
 */
public interface DocumentPoolService {

    /**
     * Adds a file to the document pool.
     */
    void addFileToPool(String documentName, byte[] fileContent);

    /**
     * Fetches XML content for a given box from the document pool.
     */
    String fetchXmlForBox(String documentName, String boxName);

    /**
     * Removes a file from the document pool.
     */
    void deleteFileFromPool(String documentName);
}
```

### 2.8 `infra/interop/qxps/QxpsDocumentPoolService.java` — one change

Add `@Override` on the existing `deleteFileFromPool` method (it now implements the interface method):

```java
    /**
     * Deletes a file from the QuarkXPress Server document pool.
     * POST http://host:port/delete/Upload/{documentName}
     */
    @Override
    public void deleteFileFromPool(String documentName) {
        // ... existing body unchanged ...
    }
```

### 2.9 `domain/DocumentIdentity.java` — add `isDefined()`

Add these methods to the class (e.g. after `hasUnitCode()`):

```java
    /**
     * Returns true when the required identity fields are present: fund code non-empty; suivi, run and
     * langue parseable as integers; and both dates present.
     */
    public boolean isDefined() {
        return isNonBlank(idFndCode)
                && isParsableInt(idSuivi)
                && isParsableInt(idRun)
                && isParsableInt(idLangue)
                && dueDate != null
                && generationDateTime != null;
    }

    private static boolean isNonBlank(String value) {
        return value != null && !value.trim().isEmpty();
    }

    private static boolean isParsableInt(String value) {
        if (value == null || value.trim().isEmpty()) {
            return false;
        }
        try {
            Integer.parseInt(value.trim());
            return true;
        } catch (NumberFormatException e) {
            return false;
        }
    }
```

### 2.10 `service/impl/QuarkXPressServerXmlServiceImpl.java` — lenient DID date parsing

**(a)** add imports:
```java
import java.util.List;
import java.util.Locale;
```
**(b)** replace the single `DATE_TIME_FORMATTER` constant with the accepted-formats list:
```java
    // DID dates arrive in US/invariant style; accept the common variants (zero-padded or not, 24-hour or
    // 12-hour with AM/PM). An unparseable value yields null, which marks the identity as undefined.
    private static final List<DateTimeFormatter> DATE_TIME_FORMATTERS = List.of(
            DateTimeFormatter.ofPattern("MM/dd/yyyy HH:mm:ss", Locale.US),
            DateTimeFormatter.ofPattern("M/d/yyyy H:mm:ss", Locale.US),
            DateTimeFormatter.ofPattern("MM/dd/yyyy hh:mm:ss a", Locale.US),
            DateTimeFormatter.ofPattern("M/d/yyyy h:mm:ss a", Locale.US));
```
**(c)** the two calls inside `parseDocumentIdentity` drop the second argument:
```java
            LocalDateTime dueDate = parseDateTime(parts[IDX_DUE_DATE].trim());
            LocalDateTime generationDateTime = parseDateTime(parts[IDX_GENERATION_DATETIME].trim());
```
**(d)** replace the `parseDateTime` method:
```java
    /** Parses a DID date-time, trying each accepted format. Returns null when empty or unparseable. */
    private LocalDateTime parseDateTime(String dateTimeString) {
        if (dateTimeString == null || dateTimeString.trim().isEmpty()) {
            return null;
        }
        String value = dateTimeString.trim();
        for (DateTimeFormatter formatter : DATE_TIME_FORMATTERS) {
            try {
                return LocalDateTime.parse(value, formatter);
            } catch (DateTimeParseException ignored) {
                // try the next accepted format
            }
        }
        logger.warn("Unparseable DID date-time: {}", value);
        return null;
    }
```

### 2.11 `infra/dao/impl/PlannedRunsDaoImpl.java`

```java
package com.socgen.sgs.api.quark.batch.infra.dao.impl;

import com.socgen.sgs.api.quark.batch.domain.RunDomain;
import com.socgen.sgs.api.quark.batch.infra.dao.PlannedRunsDao;
import com.socgen.sgs.api.quark.batch.mapper.RunMapper;
import oracle.jdbc.OracleTypes;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.CallableStatementCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

@Repository
public class PlannedRunsDaoImpl implements PlannedRunsDao {

    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public PlannedRunsDaoImpl(DataSource dataSource) {
        this.jdbcTemplate = new JdbcTemplate(dataSource);
    }

    @Override
    public List<RunDomain> getPlannedRuns() {
        // GET_RUNS is a function returning a REF CURSOR of run ids. Register the return as an Oracle CURSOR,
        // then read the ResultSet before the statement closes.
        return jdbcTemplate.execute(
                "{ ? = call QXP_PK_BATCH.GET_RUNS() }",
                (CallableStatementCallback<List<RunDomain>>) cs -> {
                    cs.registerOutParameter(1, OracleTypes.CURSOR);
                    cs.execute();
                    List<RunDomain> runs = new ArrayList<>();
                    try (ResultSet rs = (ResultSet) cs.getObject(1)) {
                        while (rs.next()) {
                            runs.add(RunMapper.mapResult(rs));
                        }
                    }
                    return runs;
                });
    }
}
```

### 2.12 `infra/dao/impl/NewUploadDocumentsDaoImpl.java`

```java
package com.socgen.sgs.api.quark.batch.infra.dao.impl;

import com.socgen.sgs.api.quark.batch.domain.UploadDocumentDomain;
import com.socgen.sgs.api.quark.batch.infra.dao.NewUploadDocumentsDao;
import com.socgen.sgs.api.quark.batch.mapper.UploadDocumentMapper;
import oracle.jdbc.OracleTypes;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.CallableStatementCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

@Repository
public class NewUploadDocumentsDaoImpl implements NewUploadDocumentsDao {

    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public NewUploadDocumentsDaoImpl(DataSource dataSource) {
        this.jdbcTemplate = new JdbcTemplate(dataSource);
    }

    @Override
    public List<UploadDocumentDomain> getNewUploadDocuments() {
        // GET_NEW_UPLOAD is a function returning a REF CURSOR of upload ids.
        return jdbcTemplate.execute(
                "{ ? = call QXP_PK_BATCH.GET_NEW_UPLOAD() }",
                (CallableStatementCallback<List<UploadDocumentDomain>>) cs -> {
                    cs.registerOutParameter(1, OracleTypes.CURSOR);
                    cs.execute();
                    List<UploadDocumentDomain> uploads = new ArrayList<>();
                    try (ResultSet rs = (ResultSet) cs.getObject(1)) {
                        while (rs.next()) {
                            uploads.add(UploadDocumentMapper.mapResult(rs));
                        }
                    }
                    return uploads;
                });
    }
}
```

### 2.13 `infra/dao/impl/UploadDocumentDaoImpl.java`

```java
package com.socgen.sgs.api.quark.batch.infra.dao.impl;

import com.socgen.sgs.api.quark.batch.domain.UploadDocumentDomain;
import com.socgen.sgs.api.quark.batch.dto.UploadDocumentDTO;
import com.socgen.sgs.api.quark.batch.infra.dao.UploadDocumentDao;
import com.socgen.sgs.api.quark.batch.mapper.UploadDocumentMapper;
import oracle.jdbc.OracleTypes;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.CallableStatementCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.ResultSet;

@Repository
public class UploadDocumentDaoImpl implements UploadDocumentDao {

    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public UploadDocumentDaoImpl(DataSource dataSource) {
        this.jdbcTemplate = new JdbcTemplate(dataSource);
    }

    @Override
    public UploadDocumentDomain getUploadDocument(UploadDocumentDTO uploadId) {
        // GET_UPLOAD_DOCUMENT(p_id_upload) returns a REF CURSOR of (id_upload, CONTENU) for one upload.
        return jdbcTemplate.execute(
                "{ ? = call QXP_PK_BATCH.GET_UPLOAD_DOCUMENT(?) }",
                (CallableStatementCallback<UploadDocumentDomain>) cs -> {
                    cs.registerOutParameter(1, OracleTypes.CURSOR);
                    cs.setInt(2, uploadId.getUploadId());
                    cs.execute();
                    try (ResultSet rs = (ResultSet) cs.getObject(1)) {
                        if (rs.next()) {
                            return UploadDocumentMapper.mapResultWithContenu(rs);
                        }
                        return null;
                    }
                });
    }
}
```

### 2.14 `infra/dao/impl/RunResetAndInitiateDaoImpl.java`

```java
package com.socgen.sgs.api.quark.batch.infra.dao.impl;

import com.socgen.sgs.api.quark.batch.domain.RunDomain;
import com.socgen.sgs.api.quark.batch.infra.dao.RunResetAndInitiateDao;
import com.socgen.sgs.api.quark.batch.mapper.RunMapper;
import oracle.jdbc.OracleTypes;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.CallableStatementCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

@Repository
public class RunResetAndInitiateDaoImpl implements RunResetAndInitiateDao {

    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public RunResetAndInitiateDaoImpl(DataSource dataSource) {
        this.jdbcTemplate = new JdbcTemplate(dataSource);
    }

    @Override
    public void resetRunsStatus() {
        // RESET_RUNS_STATUS is a procedure with no parameters or return value.
        jdbcTemplate.execute(
                "{ call QXP_PK_BATCH.RESET_RUNS_STATUS() }",
                (CallableStatementCallback<Void>) cs -> {
                    cs.execute();
                    return null;
                });
    }

    @Override
    public List<RunDomain> getRunsToBeInitiated() {
        // GET_RUNS_INITIALS is a function returning a REF CURSOR of run ids.
        return jdbcTemplate.execute(
                "{ ? = call QXP_PK_BATCH.GET_RUNS_INITIALS() }",
                (CallableStatementCallback<List<RunDomain>>) cs -> {
                    cs.registerOutParameter(1, OracleTypes.CURSOR);
                    cs.execute();
                    List<RunDomain> runs = new ArrayList<>();
                    try (ResultSet rs = (ResultSet) cs.getObject(1)) {
                        while (rs.next()) {
                            runs.add(RunMapper.mapResult(rs));
                        }
                    }
                    return runs;
                });
    }
}
```

### 2.15 `resources/application.yaml` — two changed regions

**(a) Liquibase** (under `spring:`) — was `liquibase.enabled: true`:
```yaml
  # This service connects to the existing qxp schema which it does NOT own — it must not run DDL/changelogs
  # against it. Keep Liquibase off by default; override with LIQUIBASE_ENABLED=true only if intentionally owning a schema.
  liquibase.enabled: ${LIQUIBASE_ENABLED:false}
```

**(b) `scheduler:` block** — `re-initiate-pending-runs` cron removed:
```yaml
scheduler:
  planned-runs:
    cron: "0 0 * * * ?"  # Runs once per hour at minute 0 (Europe/Paris)
  check-uploads:
    cron: "0 0 * * * ?"  # Runs once per hour at minute 0 (Europe/Paris)
  # re-initiate (Reset_Runs_Status + Get_Runs_Initials) has no scheduled cron: it runs at application
  # startup (StartupRecoveryRunner) and on demand via GET /api/v1/batchService/reInitiatePendingRuns
```

### 2.16 `test/.../infra/api/v1/BatchServiceControllerTest.java`

```java
package com.socgen.sgs.api.quark.batch.infra.api.v1;

import com.socgen.sgs.api.quark.batch.business.UpdateRunsStatusBusiness;
import com.socgen.sgs.api.quark.batch.dto.RunIdDto;
import com.socgen.sgs.api.quark.batch.service.CheckUploadsService;
import com.socgen.sgs.api.quark.batch.service.ProcessPlannedRunsService;
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
        when(processPlannedRunsService.processPlannedRuns()).thenReturn(List.of(new RunIdDto(2)));
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

### 2.17 `test/.../service/impl/ProcessPlannedRunsServiceImplTest.java`

```java
package com.socgen.sgs.api.quark.batch.service.impl;

import com.socgen.sgs.api.quark.batch.business.PlannedRunsBusiness;
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
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ProcessPlannedRunsServiceImplTest {

    @Mock
    private PlannedRunsBusiness plannedRunsBusiness;

    @Mock
    private RabbitMqProducer rabbitMqProducer;

    @InjectMocks
    private ProcessPlannedRunsServiceImpl service;

    @Test
    void processPlannedRuns_withRuns_sendsToRabbitMq() {
        when(plannedRunsBusiness.getPlannedRuns()).thenReturn(Arrays.asList(new RunDomain(1), new RunDomain(2)));

        List<RunIdDto> result = service.processPlannedRuns();

        assertThat(result).hasSize(2);
        verify(rabbitMqProducer).sendRunIds(anyList());
    }

    @Test
    void processPlannedRuns_emptyList_returnsEmpty() {
        when(plannedRunsBusiness.getPlannedRuns()).thenReturn(Collections.emptyList());

        List<RunIdDto> result = service.processPlannedRuns();

        assertThat(result).isEmpty();
        verifyNoInteractions(rabbitMqProducer);
    }

    @Test
    void processPlannedRuns_nullList_returnsEmpty() {
        when(plannedRunsBusiness.getPlannedRuns()).thenReturn(null);

        List<RunIdDto> result = service.processPlannedRuns();

        assertThat(result).isEmpty();
        verifyNoInteractions(rabbitMqProducer);
    }

    @Test
    void processPlannedRuns_nullRunDomainInList_filtersOut() {
        List<RunDomain> runs = Arrays.asList(new RunDomain(1), null, new RunDomain(null));
        when(plannedRunsBusiness.getPlannedRuns()).thenReturn(runs);

        List<RunIdDto> result = service.processPlannedRuns();

        assertThat(result).hasSize(1);
        assertThat(result.get(0).getRunId()).isEqualTo(1);
    }
}
```

### 2.18 `test/.../service/impl/ReInitiatePendingRunsServiceImplTest.java`

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
        when(runResetAndInitiateBusiness.getRunsToBeInitiated()).thenReturn(Arrays.asList(new RunDomain(10), new RunDomain(20)));
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

### 2.19 `test/.../service/impl/RabbitMqProducerTest.java`

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

    @Mock
    private RabbitTemplate rabbitTemplate;

    @InjectMocks
    private RabbitMqProducer rabbitMqProducer;

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
        verify(rabbitTemplate).convertAndSend("", "test-queue", 2);
    }

    @Test
    void sendRunIds_emptyList_doesNothing() {
        rabbitMqProducer.sendRunIds(List.of());
        verifyNoInteractions(rabbitTemplate);
    }
}
```

### 2.20 `test/.../scheduler/ProcessPlannedRunsSchedulerTest.java`

```java
package com.socgen.sgs.api.quark.batch.scheduler;

import com.socgen.sgs.api.quark.batch.service.ProcessPlannedRunsService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ProcessPlannedRunsSchedulerTest {

    @Mock private ProcessPlannedRunsService processPlannedRunsService;
    @InjectMocks private ProcessPlannedRunsScheduler scheduler;

    @Test
    void processPlannedRuns_callsService() {
        when(processPlannedRunsService.processPlannedRuns()).thenReturn(List.of());
        scheduler.processPlannedRuns();
        verify(processPlannedRunsService).processPlannedRuns();
    }

    @Test
    void processPlannedRuns_exceptionHandled() {
        when(processPlannedRunsService.processPlannedRuns()).thenThrow(new RuntimeException("err"));
        scheduler.processPlannedRuns();
    }
}
```

### 2.21 `test/.../service/impl/CheckUploadsServiceImplTest.java`

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

    /** A fully-populated identity that satisfies isDefined() (idSuivi = 200). */
    private DocumentIdentity definedIdentity() {
        return DocumentIdentity.builder()
                .idFndCode("101").idSuivi("200").idRun("300").idLangue("1")
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
        when(quarkXPressServerXmlService.getElementValueByIdName(anyString(), eq("DID"))).thenReturn("101|200|300|1|12/01/2024 00:00:00|06/25/2025 06:31:36|101223");
        when(quarkXPressServerXmlService.parseDocumentIdentity(anyString())).thenReturn(definedIdentity());
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
    void checkUploads_invalidDidFields_addsError() throws Exception {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        UploadDocumentDomain withContent = new UploadDocumentDomain(100, new byte[]{1});
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(withContent);
        when(s3UploadService.uploadDocument(eq(100), any())).thenReturn("key");
        when(qxpsDocumentPoolService.fetchXmlForBox(anyString(), eq("DID"))).thenReturn("<xml/>");
        when(quarkXPressServerXmlService.getElementValueByIdName(anyString(), eq("DID"))).thenReturn("val");
        // Missing dates and other fields -> not defined -> rejected before createRunUpload
        when(quarkXPressServerXmlService.parseDocumentIdentity(anyString()))
                .thenReturn(DocumentIdentity.builder().idSuivi("200").build());
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
        verify(uploadErrorBusiness).updateUploadsWithErrors(anyList());
        verifyNoInteractions(createRunUploadBusiness);
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
        when(quarkXPressServerXmlService.parseDocumentIdentity(anyString())).thenReturn(definedIdentity());
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
        when(quarkXPressServerXmlService.parseDocumentIdentity(anyString())).thenReturn(definedIdentity());
        when(createRunUploadBusiness.createRunUpload(200, 100)).thenReturn(new CreateRunUploadResultDTO(-2));
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
    }

    @Test
    void checkUploads_exceptionDuringProcessing_addsError() throws Exception {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        UploadDocumentDomain withContent = new UploadDocumentDomain(100, new byte[]{1});
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(withContent);
        when(s3UploadService.uploadDocument(eq(100), any())).thenReturn("key");
        // A failure in the critical QXPS step fails the upload.
        doThrow(new RuntimeException("qxps fail")).when(qxpsDocumentPoolService).addFileToPool(anyString(), any());
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
        when(quarkXPressServerXmlService.parseDocumentIdentity(anyString())).thenReturn(definedIdentity());
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
        doThrow(new RuntimeException("qxps fail")).when(qxpsDocumentPoolService).addFileToPool(anyString(), any());
        when(uploadErrorBusiness.updateUploadsWithErrors(anyList())).thenThrow(new RuntimeException("db error"));
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
    }
}
```

### 2.22 `test/.../service/impl/QuarkXPressServerXmlServiceImplTest.java` — one changed test

Replace `parseDocumentIdentity_invalidDate_throwsException` with:

```java
    @Test
    void parseDocumentIdentity_invalidDate_notDefined() {
        String input = "101|975|747|49|INVALID|06/25/2025 06:31:36|101223";
        DocumentIdentity identity = service.parseDocumentIdentity(input);
        assertThat(identity.getDueDate()).isNull();
        assertThat(identity.isDefined()).isFalse();
    }
```

---

## 3. Correctness / parity notes

- **UploadErrorDaoImpl** — `UPDATE_UPLOAD_WITH_ERRORS` binds two `INDEX BY BINARY_INTEGER` associative arrays
  (message element `VARCHAR2(200)`, clamped) with `setPlsqlIndexTable`, index-aligned, non-empty guarded.
- **Cursor DAOs (2.11–2.14)** — call the `Get_*` functions and `Reset_Runs_Status` explicitly via `JdbcTemplate`
  + `OracleTypes.CURSOR`, reading the `ResultSet` before the statement closes. Transaction-aware through the
  `@Transactional` business layer. Same functions, same mappers (`id_run`, `id_upload`, `CONTENU`), same status
  side-effects (runs 1→5, uploads 1→4). `CreateRunUploadDaoImpl` is left on `SimpleJdbcCall` — it calls a
  scalar-returning function (`Create_Run_Upload`), which is the reliable, non-cursor case.
- **Upload flow** — S3 is best-effort; the QXPS pool file is always removed after processing; a DID that is not
  fully defined (fund code, suivi/run/langue, both dates) is rejected before a run is created; run ids are
  de-duplicated within a pass before publishing. This mirrors the old service (add → read DID → validate →
  create run → purge the pool file).
- **DID dates** — parsed leniently across the common US/invariant formats; an unparseable value becomes null and
  the identity is treated as undefined (rejected), matching the old behavior.
- **Startup recovery** — reset + re-initiate runs once at startup and on demand via the endpoint; no daily cron.
- **Result codes** — `Create_Run_Upload` returns -2 (locked), -1 (in execution), or a positive run id; handled
  correctly, and a thrown DB error is caught per upload and recorded.

---

## 4. Remaining item (not applied)

### F7 — Secrets in `application.yaml`
`spring.datasource.password`, `s3.secretKey`, `spring.rabbitmq.password` are plaintext. Move to env vars
(`${...}`) or the environment-specific secrets file. Security only, not a runtime error.

---

## 5. Verify (run on the corporate network)

```bash
mvn clean test
```
Expected `BUILD SUCCESS`, 0 failures.

**Recommended smoke test against the dev Oracle** (proves the cursor DAOs, which cannot be unit-tested): booting
the app runs `Get_Runs_Initials` (startup recovery); then call each endpoint once and confirm no errors + the
expected status flips in the DB:
- `GET /api/v1/batchService/fetchPlannedRuns` → `Get_Runs` (runs 1→5)
- `GET /api/v1/batchService/newUploads` → `Get_New_Upload` + `Get_Upload_Document` (uploads 1→4)
- `GET /api/v1/batchService/reInitiatePendingRuns` → `Reset_Runs_Status` + `Get_Runs_Initials`
