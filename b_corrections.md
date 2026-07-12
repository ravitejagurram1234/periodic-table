# Quark Batch Job — Review Corrections (copy‑paste ready)

Date: 2026‑07‑11

This file contains **full, ready-to-paste** corrected sources for every fix you asked for,
plus the loophole analysis for the daily‑midnight re‑initiate job.

**Not changing (per your decision):**
- #3 daily‑midnight `re-initiate-pending-runs` → **kept** (see loophole analysis at the bottom).
- #4 hourly polling crons → **kept** (you'll tighten in the deployed config).
- #5 planning window removal → **kept as intended (24/7)**.

**Applied in this file:**
1. 🔴 `UploadErrorDaoImpl` — fix PL/SQL associative‑array binding (was guaranteed runtime failure).
2. 🔴 Liquibase — disable the template changelog so it can't touch the prod QXP schema.
3. 🟡 `CheckUploadsServiceImpl` — make S3 non‑critical, null‑safe upload load, faithful DID completeness check.
4. 🟡 `BatchServiceController` — `executeRuns` also runs the upload check (parity with old `ExecuteRuns`).
5. 🟢 Delete dead `ProcessRunsService` / `ProcessRunsServiceImpl`.
6. 🟢 Secrets / timezone / scheduler notes (guidance).

---

## 1. 🔴 `UploadErrorDaoImpl` — correct associative‑array binding

**Why:** `QXP_PK_BATCH.Update_Upload_With_Errors(p_error_ids IN NumberArray, p_error_msgs IN VarCharArray)`
uses PL/SQL **associative arrays** (`TABLE OF ... INDEX BY BINARY_INTEGER`). The old code bound them with
`Types.ARRAY` + SQL type names `NUMBER_ARRAY` / `VARCHAR_ARRAY` **which do not exist** in the DB — this throws
at runtime, and because the caller swallows the exception, **failed uploads were never marked with status 2 +
message** (they got stuck at status 4 forever, invisible to users). This mirrors the working
`UpdateRunsStatusDaoImpl` and uses `setPlsqlIndexTable`.

**File:** `src/main/java/com/socgen/sgs/api/quark/batch/infra/dao/impl/UploadErrorDaoImpl.java`

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

    // QXP_PK_BATCH.VarCharArray is TABLE OF VARCHAR2(200) — clamp messages to avoid ORA-06502.
    private static final int ERROR_MESSAGE_MAX_LEN = 200;

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

        final int size = uploadErrors.size();
        int[] errorIds = new int[size];
        String[] errorMessages = new String[size];

        for (int i = 0; i < size; i++) {
            errorIds[i] = uploadErrors.get(i).getUploadId();
            String msg = uploadErrors.get(i).getErrorMessage();
            if (msg != null && msg.length() > ERROR_MESSAGE_MAX_LEN) {
                msg = msg.substring(0, ERROR_MESSAGE_MAX_LEN);
            }
            errorMessages[i] = msg;
        }

        logger.info("Marking {} upload(s) with error status via Update_Upload_With_Errors", size);

        // Function: { ? = call QXP_PK_BATCH.Update_Upload_With_Errors(?, ?) }
        //   param 1 = RETURN (rowcount), param 2 = p_error_ids, param 3 = p_error_msgs
        try (Connection conn = dataSource.getConnection();
             CallableStatement cs = conn.prepareCall(
                     "{ ? = call QXP_PK_BATCH.Update_Upload_With_Errors(?, ?) }")) {

            OracleCallableStatement oraCs = cs.unwrap(OracleCallableStatement.class);

            oraCs.registerOutParameter(1, OracleTypes.NUMBER);

            // PL/SQL associative arrays (INDEX BY BINARY_INTEGER) => setPlsqlIndexTable, NOT Types.ARRAY.
            oraCs.setPlsqlIndexTable(2, errorIds, size, size, OracleTypes.NUMBER, 0);
            oraCs.setPlsqlIndexTable(3, errorMessages, size, size, OracleTypes.VARCHAR, ERROR_MESSAGE_MAX_LEN);

            oraCs.execute();

            int affected = oraCs.getInt(1);

            // Parity with old DocumentProxy.UpdateUploadErrors: warn on count mismatch.
            if (affected != size) {
                logger.warn("Error-upload count mismatch: {} provided but {} row(s) updated in QXP_DOCUMENT_UPLOAD",
                        size, affected);
            } else {
                logger.info("Successfully marked {} upload(s) with error status", affected);
            }
            return affected;
        } catch (Exception e) {
            logger.error("Error updating uploads with errors", e);
            throw new RuntimeException("Failed to update uploads with errors", e);
        }
    }
}
```

> Note: like `UpdateRunsStatusDaoImpl`, this opens its own JDBC connection (autocommit) rather than joining a
> Spring transaction. That's fine here — it's a single atomic proc call. `UploadErrorBusinessImpl` therefore
> does **not** need `@Transactional`; leave it as is.

---

## 2. 🔴 Disable Liquibase (template changelog must not run against the QXP schema)

**Why:** `db/changelog/20230101_init-db.xml` is still the archetype example
(`<!-- EXAMPLE CHANGELOG: REMOVE AND REPLACE... -->`) creating a table named `${entityNameInSnakeCase}`.
With `liquibase.enabled: true`, first boot against the real `qxp` Oracle schema will either fail or create junk
tables (`DATABASECHANGELOG`, the bogus table). This service does not own that schema.

**File:** `src/main/resources/application.yaml`

Change:

```yaml
  liquibase.enabled: true
```

to:

```yaml
  liquibase.enabled: false
```

If a local/test profile genuinely needs Liquibase against H2, re‑enable it **only** in that profile
(`application-local.yaml` / `application-test.yaml`) after replacing the template changelog with a real one.

---

## 3. 🟡 `CheckUploadsServiceImpl` — S3 non‑critical, null‑safe load, faithful DID check

**Why:**
- **S3 is your future‑enhancement add‑on** but it sat first in the critical path and threw on failure, so an S3
  outage marked every upload as an error and created **no runs**. It's now best‑effort (log + continue).
- `getUploadDocuments` could `NPE` if an upload row vanished between `Get_New_Upload` and `Get_Upload_Document`
  (old `LoadUploadDocuments` skipped nulls). Now null‑safe.
- The old `Document_Identity.Is_Defined` rejected a DID unless `Id_Fnd_Code`, `Id_Suivi`, `Id_Run`, `Id_Langue`
  were all present/non‑zero and both dates parsed. The vibe‑coded version only checked `idSuivi`. Restored to
  match old behavior (a partial DID → recorded as an error, not turned into a run).

**File:** `src/main/java/com/socgen/sgs/api/quark/batch/service/impl/CheckUploadsServiceImpl.java`

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
import java.util.Objects;

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
        // 1–3: Get new uploads (Get_New_Upload flips status 1 -> 4), log, exit if empty
        List<UploadDocumentDTO> newUploads = getNewUploads();
        logger.info("Found {} new upload(s)", newUploads.size());
        if (newUploads.isEmpty()) {
            return List.of();
        }

        // 4: Fetch blob content from DB (null-safe: a vanished row is skipped, not an NPE)
        List<UploadDocumentDTO> uploadDocuments = getUploadDocuments(newUploads);
        logger.info("Processing {} uploads with content", uploadDocuments.size());

        // 5: Accumulators
        List<RunIdDto> runIdsToBeLaunched = new ArrayList<>();
        List<UploadErrorDTO> uploadErrors = new ArrayList<>();
        int successCount = 0;
        int failureCount = 0;

        // 6: Per-upload processing loop
        for (UploadDocumentDTO doc : uploadDocuments) {
            Integer uploadId = doc.getUploadId();
            try {
                // 6a: Upload to S3 — NON-CRITICAL (future enhancement). Never fail the upload because of S3.
                try {
                    String s3Key = s3UploadService.uploadDocument(uploadId, doc.getContenu());
                    logger.info("Uploaded to S3. Upload ID: {}, S3 Key: {}", uploadId, s3Key);
                } catch (Exception s3Ex) {
                    logger.warn("S3 upload failed for Upload ID {} — continuing (S3 is non-critical): {}",
                            uploadId, s3Ex.getMessage());
                }

                // 6a2: Add file to QuarkXPress Server document pool
                String documentName = constructDocumentName(uploadId);
                qxpsDocumentPoolService.addFileToPool(documentName, doc.getContenu());

                // 6b: Fetch XML metadata (DID box) from QuarkXPress Server
                String xmlContent = qxpsDocumentPoolService.fetchXmlForBox(documentName, "DID");
                if (xmlContent == null || xmlContent.isBlank()) {
                    failureCount = recordError(uploadErrors, uploadId, "Empty XML response from QXPS", failureCount);
                    continue;
                }
                logger.debug("XML content received for Upload ID {}: length={}", uploadId, xmlContent.length());

                String didValue = quarkXPressServerXmlService.getElementValueByIdName(xmlContent, "DID");
                if (didValue == null || didValue.isBlank()) {
                    failureCount = recordError(uploadErrors, uploadId, "DID not found in XML", failureCount);
                    continue;
                }

                DocumentIdentity identity = quarkXPressServerXmlService.parseDocumentIdentity(didValue);

                // Parity with old Document_Identity.Is_Defined: reject incomplete DIDs (e.g. templates/gabarits).
                if (!isIdentityDefined(identity)) {
                    failureCount = recordError(uploadErrors, uploadId,
                            "Invalid/incomplete DID field", failureCount);
                    continue;
                }

                Integer idSuivi = Integer.parseInt(identity.getIdSuivi().trim());
                logger.info("Extracted metadata. Upload ID: {}, Suivi ID: {}", uploadId, idSuivi);

                // 6c: Create run via stored procedure
                CreateRunUploadResultDTO result = createRunUploadBusiness.createRunUpload(idSuivi, uploadId);

                // 6d: Handle result codes (matches old switch: >0 ok, -1 in-exec, -2 locked, else error)
                if (result.isSuccess()) {
                    logger.info("Run created. Upload ID: {}, Run ID: {}", uploadId, result.getRunId());
                    runIdsToBeLaunched.add(new RunIdDto(result.getRunId()));
                    successCount++;
                } else if (result.isRunInExecution()) {
                    failureCount = recordError(uploadErrors, uploadId, "Run already in execution", failureCount);
                } else if (result.isSuiviLocked()) {
                    failureCount = recordError(uploadErrors, uploadId, "Follow-up is locked", failureCount);
                } else {
                    failureCount = recordError(uploadErrors, uploadId, "Error creating run", failureCount);
                }
            } catch (Exception e) {
                logger.error("Failed processing Upload ID: {}. Continuing.", uploadId, e);
                uploadErrors.add(new UploadErrorDTO(uploadId, "Failed processing: " + e.getMessage()));
                failureCount++;
            }
        }

        // 7: Update database with all errors (if any)
        if (!uploadErrors.isEmpty()) {
            try {
                Integer rowsUpdated = uploadErrorBusiness.updateUploadsWithErrors(uploadErrors);
                logger.info("Updated {} upload record(s) with error status", rowsUpdated);
            } catch (Exception e) {
                logger.error("Failed to update error uploads in database", e);
            }
        }

        // 8: Send successful run IDs to RabbitMQ
        for (RunIdDto runIdDto : runIdsToBeLaunched) {
            try {
                rabbitMqProducer.sendRunId(runIdDto.getRunId());
                logger.info("Run ID {} queued to RabbitMQ", runIdDto.getRunId());
            } catch (Exception e) {
                logger.error("Failed to queue Run ID {}.", runIdDto.getRunId(), e);
            }
        }

        logger.info("Completed: {} successful, {} failed", successCount, failureCount);
        return runIdsToBeLaunched;
    }

    private int recordError(List<UploadErrorDTO> uploadErrors, Integer uploadId, String msg, int failureCount) {
        logger.error("{}. Upload ID: {}", msg, uploadId);
        uploadErrors.add(new UploadErrorDTO(uploadId, msg));
        return failureCount + 1;
    }

    /**
     * Faithful port of QXP.Engine.Core Document_Identity.Is_Defined:
     * Id_Fnd_Code, Id_Suivi, Id_Run, Id_Langue must all be present/non-zero,
     * and both dates must be parsed (parseDocumentIdentity guarantees non-null dates or throws).
     */
    private boolean isIdentityDefined(DocumentIdentity id) {
        return isNonBlank(id.getIdFndCode())
                && parsesToNonZeroInt(id.getIdSuivi())
                && parsesToNonZeroInt(id.getIdRun())
                && parsesToNonZeroInt(id.getIdLangue())
                && id.getDueDate() != null
                && id.getGenerationDateTime() != null;
    }

    private boolean isNonBlank(String s) {
        return s != null && !s.trim().isEmpty();
    }

    // Old code used ConversionInvariante.ToInt (non-numeric -> 0) then required != 0.
    private boolean parsesToNonZeroInt(String s) {
        if (s == null) {
            return false;
        }
        try {
            return Integer.parseInt(s.trim()) != 0;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    private String constructDocumentName(Integer uploadId) {
        return String.format("UP_%d.qxp", uploadId);
    }

    private List<UploadDocumentDTO> getNewUploads() {
        List<UploadDocumentDomain> uploadDocumentDomains = newUploadsBusiness.getNewUploadDocuments();
        return uploadDocumentDomains.stream().map(UploadDocumentMapper::toDto).toList();
    }

    private List<UploadDocumentDTO> getUploadDocuments(List<UploadDocumentDTO> uploadIds) {
        return uploadIds.stream()
                .map(uploadId -> {
                    UploadDocumentDomain domain = uploadDocumentBusiness.getUploadDocument(uploadId);
                    if (domain == null) {
                        logger.warn("Upload document {} not found in DB (row vanished) — skipping",
                                uploadId.getUploadId());
                        return null;
                    }
                    return UploadDocumentMapper.toDto(domain);
                })
                .filter(Objects::nonNull)
                .toList();
    }
}
```

> If you'd rather NOT restore the strict DID check (keep the looser vibe‑coded behavior), just delete the
> `isIdentityDefined(...)` block and its three helper methods. Everything else stands on its own.

---

## 4. 🟡 `BatchServiceController.executeRuns` — run the upload check (parity with old `ExecuteRuns`)

**Why:** Old `Service.ExecuteRuns` did `Update_Runs_Status` **+ `UploadManager.Check()`** + enqueue. The rewrite
dropped the upload check. Restored, but made best‑effort so a QXPS/upload hiccup can't fail the requested runs.

**File:** `src/main/java/com/socgen/sgs/api/quark/batch/infra/api/v1/BatchServiceController.java`

Replace the `executeRuns` method with:

```java
    @PostMapping(path = "/executeRuns")
    @Operation(summary = "Execute runs", description = "Execute processing runs for the provided run IDs")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Runs executed successfully"),
            @ApiResponse(responseCode = "400", description = "Bad request"),
            @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    public ResponseEntity<String> executeRuns(@RequestBody List<Integer> runIds) {
        List<RunIdDto> runIdDtos = runIds.stream()
                .map(RunIdDto::new)
                .toList();

        // 1. Mark requested runs as taken by batch (ID_STATUT_GENERATION = 5) — old: Update_Runs_Status
        updateRunsStatusBusiness.updateRunsStatus(runIdDtos);

        // 2. Opportunistically process pending uploads — old: UploadManager.Check().
        //    Best-effort: an upload-check failure must not fail the requested run execution.
        try {
            checkUploadsService.checkUploads();
        } catch (Exception e) {
            logger.error("Upload check during executeRuns failed (continuing to queue requested runs)", e);
        }

        // 3. Queue the explicitly requested runs — old: Run_Queue.Enqueue(run_ids)
        rabbitMqProducer.sendRunIds(runIdDtos);

        return ResponseEntity.ok().body("Runs executed successfully for " + runIds.size() + " run IDs");
    }
```

(`checkUploadsService` is already injected in this controller — no constructor change needed.)

---

## 5. 🟢 Delete dead code: `ProcessRunsService`

`processRuns(...)` is an empty stub referenced nowhere. **Delete both files:**

```
src/main/java/com/socgen/sgs/api/quark/batch/service/ProcessRunsService.java
src/main/java/com/socgen/sgs/api/quark/batch/service/impl/ProcessRunsServiceImpl.java
```

If any test references them, delete those tests too (none do at the time of review).

---

## 6. 🟢 Guidance (no code needed, but do these before prod)

**a. Secrets out of `application.yaml`.** `spring.datasource.password`, `s3.secretKey`, and `spring.rabbitmq.*`
credentials are committed in plaintext. Move them to `src/main/config/secrets/<env>/application-secrets.yml`
(already exist) or env vars, and reference with `${...}`.

**b. Scheduler timezone.** The crons fire in the JVM/container local time. A UTC container makes
`0 0 0 * * ?` fire at 01:00/02:00 Paris. Pin it explicitly, e.g. add `zone` to each `@Scheduled`:

```java
@Scheduled(cron = "${scheduler.re-initiate-pending-runs.cron}", zone = "Europe/Paris")
```

**c. Keep the scheduler single‑threaded.** Spring's default single scheduling thread is what prevents the
midnight `re-initiate` and hourly `planned-runs` jobs from racing on the same rows. Do **not** set
`spring.task.scheduling.pool.size > 1` without re‑reading the loophole notes below.

---

## Loophole analysis — daily‑midnight `re-initiate-pending-runs` (you're keeping this)

`reInitiatePendingRuns()` = `Reset_Runs_Status` (RUN 4/5 → 1, DOCUMENT_UPLOAD 4 → 1) then `Get_Runs_Initials`
(picks status‑1 runs, flips to 5, sends to RabbitMQ). Old code ran this **once at startup**; you now run it
**every midnight**. That's fine as an enhancement, but watch these:

1. **Duplicate generation of genuinely in‑flight runs (biggest risk).**
   Because you run 24/7 (no planning window), a run can be status 4 (being generated) or 5 (already queued in
   RabbitMQ) exactly at 00:00. Reset flips it to 1, then `Get_Runs_Initials` re‑queues it → the run engine
   generates it **twice**. Old startup‑only reset never hit this (nothing was running at boot).
   - **Mitigation:** make the run‑engine **consumer idempotent** — before generating, re‑check the run's
     `ID_STATUT_GENERATION` (skip if already generated/completed), or de‑dupe on `id_run`. This is the single
     most important safeguard because RabbitMQ (unlike the old in‑memory `Run_Queue`, which did
     `if(!_queue.Contains(item))`) does **not** de‑duplicate messages.

2. **No RabbitMQ de‑dup across jobs.**
   The hourly `planned-runs` (`Get_Runs`) and the midnight `re-initiate` (`Get_Runs_Initials`) can both target a
   run whose `DATE_PLANIFICATION < SYSDATE` (their WHERE clauses overlap). Serialization by the single scheduler
   thread + the atomic `1 → 5` flip inside each function prevents a true double‑pick **as long as** reset isn't
   interleaved between them. Keep the scheduler single‑threaded (see 6c). If you ever call these via the REST
   endpoints at the same time as the schedulers, you reintroduce the race — the idempotent consumer (point 1)
   is your backstop.

3. **`DOCUMENT_UPLOAD` 4 → 1 reset causes upload re‑processing.**
   Reset also flips uploads from 4 → 1, so the next `checkUploads` re‑fetches them, re‑POSTs to QXPS and retries
   `Create_Run_Upload`. For an already‑processed upload whose run is now 4/5, `Create_Run_Upload` returns
   `-1 (run in execution)` → the upload gets marked as an error. So a harmless upload can end up flagged as an
   error purely because of the midnight reset. If you see that noise, scope the reset to exclude uploads that
   already produced a run.

4. **Timezone.** See 6b — confirm midnight means the midnight you intend.

5. **Optional hardening (DB‑side, out of scope of these edits).** If duplicate generation is unacceptable,
   consider narrowing `Reset_Runs_Status` to only reset **stuck** rows (e.g., status 5 whose queue timestamp is
   older than N minutes, or status 4 with a stale `DATE_CREATION_RUN`) instead of a blanket 4/5 → 1. That keeps
   your daily recovery while leaving truly in‑flight runs alone. This needs a timestamp column and a package
   change — flag it if you want me to draft the PL/SQL.

**Bottom line:** the daily job is safe to keep **if** the run‑engine consumer is idempotent and the scheduler
stays single‑threaded. Those two things close the real holes.

---

## Quick checklist

- [ ] Replace `UploadErrorDaoImpl.java` (fix #1)
- [ ] `application.yaml`: `liquibase.enabled: false` (fix #2)
- [ ] Replace `CheckUploadsServiceImpl.java` (fix #3)
- [ ] Replace `executeRuns` in `BatchServiceController.java` (fix #4)
- [ ] Delete `ProcessRunsService.java` + `ProcessRunsServiceImpl.java` (fix #5)
- [ ] Move secrets, pin scheduler `zone`, keep scheduler pool size = 1 (guidance #6)
- [ ] Ensure the run‑engine consumer is **idempotent** on `id_run` (loophole #1/#2)
```
