# Batch Service — .NET Parity Gap Fixes (new changes)

> This file contains ONLY the new changes from the .NET parity audit round (upload-flow gaps + English
> messages with the document name). The full consolidated document remains `BATCH_CHANGES_AND_REVIEW.md`.
>
> Build note: not compiled here (internal Artifactory unreachable). Run `mvn clean test` on the corporate
> network to confirm.

---

## 1. Gaps fixed (aligned to the old `UploadManager.Check()`)

| ID | Gap | Fix |
|----|-----|-----|
| D3 | A single failed/null blob load aborted the whole pass (NPE) | Skip that upload, log it, continue the pass |
| D1 | Errors were written before runs were queued | Queue runs to RabbitMQ **before** writing errors |
| D4 | A DID with `<6` parts threw | Treated as not-defined (soft error), no throw |
| D11 | A `Create_Run_Upload` DB exception hit a generic catch | Normalised to code 0 → create-error message |
| D9 | Run ids de-duplicated only at send time | De-duplicated as collected; added row-count-mismatch warning |
| D7/D8/D13 | Error messages lacked the document name | Messages/logs kept in **English**, now include the document name |

Files touched: `CheckUploadsServiceImpl.java`, `QuarkXPressServerXmlServiceImpl.java`,
`CheckUploadsServiceImplTest.java`, `QuarkXPressServerXmlServiceImplTest.java`.

---

## 2. `service/impl/CheckUploadsServiceImpl.java` (full final content)

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
import java.util.LinkedHashSet;
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
        // 1–3: Get new uploads, exit if none
        List<UploadDocumentDTO> newUploads = getNewUploads();
        logger.info("Found {} new upload(s)", newUploads.size());
        if (newUploads.isEmpty()) {
            return List.of();
        }

        // 4: Load blob content. A single upload whose load fails or returns no row is skipped; the rest of
        // the pass still runs.
        List<UploadDocumentDTO> uploadDocuments = getUploadDocuments(newUploads);
        logger.info("Processing {} uploads with content", uploadDocuments.size());

        // 5: Accumulators. Run ids are de-duplicated as they are collected.
        LinkedHashSet<Integer> runIdsToBeLaunched = new LinkedHashSet<>();
        List<UploadErrorDTO> uploadErrors = new ArrayList<>();
        int successCount = 0;
        int failureCount = 0;

        // 6: Per-upload processing loop
        for (UploadDocumentDTO doc : uploadDocuments) {
            Integer uploadId = doc.getUploadId();
            String documentName = constructDocumentName(uploadId);
            try {
                // 6a: S3 upload is best-effort — a failure must not block run creation, so it is caught here.
                try {
                    String s3Key = s3UploadService.uploadDocument(uploadId, doc.getContenu());
                    logger.info("Uploaded to S3. Upload ID: {}, S3 Key: {}", uploadId, s3Key);
                } catch (Exception e) {
                    logger.warn("S3 upload failed for Upload ID {} (non-critical, continuing)", uploadId, e);
                }

                boolean addedToPool = false;
                try {
                    // 6b: Add file to QuarkXPress Server document pool
                    qxpsDocumentPoolService.addFileToPool(documentName, doc.getContenu());
                    addedToPool = true;

                    // 6c: Fetch the DID box and parse the identity. An empty box or a not-defined identity
                    // is treated as a DID-field error.
                    String xmlContent = qxpsDocumentPoolService.fetchXmlForBox(documentName, "DID");
                    String didValue = (xmlContent == null || xmlContent.isBlank())
                            ? null
                            : quarkXPressServerXmlService.getElementValueByIdName(xmlContent, "DID");
                    DocumentIdentity identity = (didValue == null || didValue.isBlank())
                            ? null
                            : quarkXPressServerXmlService.parseDocumentIdentity(didValue);

                    if (identity == null || !identity.isDefined()) {
                        String errorMsg = "Invalid DID field(s) in document " + documentName;
                        logger.error("{}. Upload ID: {}", errorMsg, uploadId);
                        uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                        failureCount++;
                        continue;
                    }

                    Integer idSuivi = Integer.parseInt(identity.getIdSuivi());
                    logger.info("Extracted metadata. Upload ID: {}, Suivi ID: {}", uploadId, idSuivi);

                    // 6d: Create run via stored procedure. A DB failure is normalised to code 0, producing
                    // the create-error message below.
                    CreateRunUploadResultDTO result;
                    try {
                        result = createRunUploadBusiness.createRunUpload(idSuivi, uploadId);
                    } catch (Exception e) {
                        logger.error("Error during run upload creation. Upload ID: {}", uploadId, e);
                        result = new CreateRunUploadResultDTO(0);
                    }

                    // 6e: Handle result codes
                    if (result.isSuccess()) {
                        logger.info("Run created. Upload ID: {}, Run ID: {}", uploadId, result.getRunId());
                        runIdsToBeLaunched.add(result.getRunId());
                        successCount++;
                    } else if (result.isRunInExecution()) {
                        String errorMsg = "Run already taken by batch for document " + documentName;
                        logger.error("{}. Upload ID: {}, Suivi ID: {}", errorMsg, uploadId, idSuivi);
                        uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                        failureCount++;
                    } else if (result.isSuiviLocked()) {
                        String errorMsg = "Suivi is locked for document " + documentName;
                        logger.error("{}. Upload ID: {}, Suivi ID: {}", errorMsg, uploadId, idSuivi);
                        uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                        failureCount++;
                    } else {
                        String errorMsg = "Error creating run upload for document " + documentName;
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
                String errorMsg = "Failed to retrieve XML or DID field not found for document " + documentName;
                logger.error("{}. Upload ID: {}. Continuing.", errorMsg, uploadId, e);
                uploadErrors.add(new UploadErrorDTO(uploadId, errorMsg));
                failureCount++;
            }
        }

        // 7: Queue successful run IDs to RabbitMQ (done before writing errors).
        for (Integer runId : runIdsToBeLaunched) {
            try {
                rabbitMqProducer.sendRunId(runId);
                logger.info("Run ID {} queued to RabbitMQ", runId);
            } catch (Exception e) {
                logger.error("Failed to queue Run ID {}.", runId, e);
            }
        }

        // 8: Flag error uploads in the database.
        if (!uploadErrors.isEmpty()) {
            try {
                Integer rowsUpdated = uploadErrorBusiness.updateUploadsWithErrors(uploadErrors);
                logger.info("Updated {} upload records with error status", rowsUpdated);
                if (rowsUpdated != null && rowsUpdated != uploadErrors.size()) {
                    logger.warn("Error count ({}) does not match rows updated in qxp_document_upload ({})",
                            uploadErrors.size(), rowsUpdated);
                }
            } catch (Exception e) {
                logger.error("Failed to update error uploads in database", e);
            }
        }

        logger.info("Completed: {} successful, {} failed", successCount, failureCount);
        return runIdsToBeLaunched.stream().map(RunIdDto::new).toList();
    }

    private String constructDocumentName(Integer uploadId) {
        return String.format("UP_%d.qxp", uploadId);
    }

    private List<UploadDocumentDTO> getNewUploads() {
        List<UploadDocumentDomain> uploadDocumentDomains = newUploadsBusiness.getNewUploadDocuments();
        return uploadDocumentDomains.stream().map(UploadDocumentMapper:: toDto).toList();
    }

    private List<UploadDocumentDTO> getUploadDocuments(List<UploadDocumentDTO> uploadIds) {
        List<UploadDocumentDTO> loaded = new ArrayList<>();
        for (UploadDocumentDTO uploadId : uploadIds) {
            try {
                UploadDocumentDomain domain = uploadDocumentBusiness.getUploadDocument(uploadId);
                if (domain != null) {
                    loaded.add(UploadDocumentMapper.toDto(domain));
                } else {
                    logger.error("Unable to load file {} from qxp_document_upload", uploadId.getUploadId());
                }
            } catch (Exception e) {
                logger.error("Unable to load file {} from qxp_document_upload", uploadId.getUploadId(), e);
            }
        }
        return loaded;
    }
}
```

---

## 3. `service/impl/QuarkXPressServerXmlServiceImpl.java` — one change (D4)

In `parseDocumentIdentity`, a DID with fewer than 6 parts returns an unpopulated identity
(`isDefined() == false`) instead of throwing. Replace the `< MIN_IDENTITY_PARTS` throw block with:

```java
        if (parts.length < MIN_IDENTITY_PARTS) {
            logger.warn("DID has {} part(s), fewer than the required {}: {}",
                    parts.length, MIN_IDENTITY_PARTS, identityString);
            return DocumentIdentity.builder().build();
        }
```

---

## 4. Test changes

### `test/.../service/impl/CheckUploadsServiceImplTest.java` — add this test

```java
    @Test
    void checkUploads_blobLoadReturnsNull_skipsUpload() {
        UploadDocumentDomain upload = new UploadDocumentDomain(100, null);
        when(newUploadsBusiness.getNewUploadDocuments()).thenReturn(List.of(upload));
        when(uploadDocumentBusiness.getUploadDocument(any())).thenReturn(null);
        List<RunIdDto> result = service.checkUploads();
        assertThat(result).isEmpty();
        verifyNoInteractions(qxpsDocumentPoolService, createRunUploadBusiness, rabbitMqProducer);
    }
```

### `test/.../service/impl/QuarkXPressServerXmlServiceImplTest.java` — replace the too-few-parts test

```java
    @Test
    void parseDocumentIdentity_tooFewParts_notDefined() {
        DocumentIdentity identity = service.parseDocumentIdentity("a|b|c");
        assertThat(identity.isDefined()).isFalse();
    }
```

---

## 5. Error messages (English, with document name)

| Situation | Stored / logged message |
|---|---|
| Suivi locked (`-2`) | `Suivi is locked for document UP_<id>.qxp` |
| Run already taken (`-1`) | `Run already taken by batch for document UP_<id>.qxp` |
| Create returns 0 / create exception | `Error creating run upload for document UP_<id>.qxp` |
| DID missing / empty / not-defined / `<6` parts | `Invalid DID field(s) in document UP_<id>.qxp` |
| XML fetch failure / general per-doc error | `Failed to retrieve XML or DID field not found for document UP_<id>.qxp` |
| Blob load failure (log only) | `Unable to load file <id> from qxp_document_upload` |

---

## 6. Intentional deviations from .NET (by design)

- **Dispatch:** publishes `run_id` to RabbitMQ instead of launching `QXP.Engine.exe` (rewrite design; the
  run-engine consumer must be idempotent per `id_run`).
- **Scheduling:** Spring `@Scheduled` crons (configurable) instead of the polling `Watcher` + planning window.
- **S3:** additive best-effort step, never blocks run creation.
- **Startup DB-failure liveness:** if `Get_Runs_Initials` fails at startup, .NET tears down the whole watcher;
  Java logs it and keeps the planned-run cron alive (more resilient). Tell me if you want strict fail-fast.
- **Messages:** English by choice (not the old French text), but each includes the document name.
