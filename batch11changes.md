# EOS Quark Engine — Batch 11 Changes
**Theme: DAO robustness + persistence parity (audit, metadata-access, langue/format, file paths)**

_All snippets (localized edits across 8 files + 1 test). Two LOW findings deferred — see flags._

## Findings fixed (12) + 2 deferred
| # | Sev | Fix |
|---|---|---|
| 47/90 | MED/LOW | `InsertDocumentDaoImpl`: add `.withoutProcedureColumnMetaDataAccess()` → deterministic RETURN/param binding from the explicit list (param order matches `ora.txt`). |
| 91 | LOW | `EndRunDaoImpl`: same flag on `End_Run` + `Update_Status_Run` (Insert_Run_Errors already uses the Batch-4 raw `setPlsqlIndexTable` bind). |
| 89 | LOW | `InsertDocumentDaoImpl`: `p_date_document` null-safe (no NPE when dateEcheance null). |
| 57 | MEDIUM | `DocumentDomain.generateFileNames`: extension uses format VERBATIM (no `toLowerCase`) — matches .NET + the DAO name-builders. |
| 92 | LOW | `DocumentDomain.changeDocument` now also refreshes `fileFullPath` (new param); `QxpsCallerBusiness` passes the recomputed absolute path. |
| 73 | LOW | `GetDocumentDaoImpl`: sets `idLangue` from the input param (the Get_Document cursor has no langue column — verified in ora.txt). |
| 84 | LOW | `GetDocumentByIdDaoImpl`: reads `format` from the cursor VERBATIM (fallback "QXP") — the Get_Document_ByID cursor returns it (verified). |
| 53/82 | MED/LOW | `AuditDaoImpl`: DURATION = `Duration.toMillisPart()` (the 0-999 ms COMPONENT) to match .NET `TimeSpan.Milliseconds`. ⚠️ See quirk note. |
| 83/87 | LOW | `AuditDaoImpl`: END_STATUS = `RunStatus.getNetLabel()` (`ToGenerate/Generated/Error/Running`) — .NET `Run_Status.ToString()`, not Java `name()`. |

## ⚠️ #53/#82 — audit DURATION is a .NET quirk (flagged)
`.NET Audit.Duration` returns `((TimeSpan)(end-start)).Milliseconds` — the **sub-second millisecond component (0-999)**, NOT the total elapsed time. A 90-second run stores some value 0-999, losing the seconds. I replicated this for strict parity (`toMillisPart()`), but it's almost certainly a .NET bug. If you'd rather store **total** duration (`toMillis()` or seconds), say so — it's a deliberate, reversible choice.

## ⏸️ Deferred (LOW, intentionally not done)
- **#86** (store cleanup DELETE runs even with empty data): would require calling `Insert_Data` with **empty arrays** through the Batch-4 `setPlsqlIndexTable` bind. Touching the runtime-critical DAO with a 0-length index-table bind needs **live-DB verification** (some drivers reject `maxLen=0`). Deferred to the live-DB pass rather than risk the critical insert.
- **#88** (audit MESSAGE text format): exact `.NET buildAuditMessage`/`Errors.ToString()` wording is a free-text, truncated, forensic-only field — needs a **golden-file comparison** to match byte-for-byte. Deferred rather than approximate it.

---

## `domain/RunStatus.java` — add .NET label
```java
TO_GENERATE(1, "ToGenerate"),
GENERATED(2, "Generated"),
ERROR(3, "Error"),
RUNNING(4, "Running");
private final int statusCode;
private final String netLabel;          // @Getter → getNetLabel()
RunStatus(int statusCode, String netLabel) { this.statusCode = statusCode; this.netLabel = netLabel; }
```

---

## `infra/dao/impl/AuditDaoImpl.java` — duration + status
```java
int durationMs = 0;
if (run.getStartDate() != null && run.getEndDate() != null) {
    durationMs = Duration.between(run.getStartDate(), run.getEndDate()).toMillisPart(); // .NET ms component
}
... .addValue("p_duration", durationMs)
    .addValue("p_end_status", run.getStatus() != null ? run.getStatus().getNetLabel() : null) ...
```

---

## `infra/dao/impl/InsertDocumentDaoImpl.java`
```java
// after .withFunctionName("Insert_Document"):
.withoutProcedureColumnMetaDataAccess()
// and the date bind:
params.put("p_date_document", dateEcheance != null ? java.sql.Date.valueOf(dateEcheance) : null);
```

---

## `infra/dao/impl/EndRunDaoImpl.java`
```java
// after .withProcedureName("End_Run")  AND  after .withProcedureName("Update_Status_Run"):
.withoutProcedureColumnMetaDataAccess()
```

---

## `domain/DocumentDomain.java`
```java
// generateFileNames — verbatim extension (#57):
this.fileName = String.format(FILE_NAME_PREFIX_PATTERN, this.prefix, this.id, this.format);

// changeDocument — new newFileFullPath param (#92):
public void changeDocument(String newFileName, String newFilePoolPath,
                           String newFileFullPath, byte[] newData) {
    this.fileName = newFileName;
    this.filePoolPath = newFilePoolPath;
    this.fileFullPath = newFileFullPath;
    this.data = newData;
    purgeXmlAndProject();
}
```

---

## `business/QxpsCallerBusiness.java` — updateGabaritAfterStep (#92 caller)
```java
String newFullPath = run.getRunProperties().getPoolPathAbsolute(
        newGabaritName, qxpsProperties.getPool().getDefaultPath());
...
gabarit.changeDocument(newGabaritName, newPoolPath, newFullPath, newData);
```

---

## `infra/dao/impl/GetDocumentDaoImpl.java` (#73)
```java
DocumentDomain doc = rows.get(0);
doc.setIdLangue(idLangue);   // cursor has no langue column; .NET sets it from the input
return doc;
```

---

## `infra/dao/impl/GetDocumentByIdDaoImpl.java` (#84)
```java
String fmt = rs.getString("format");
doc.setFormat(fmt != null && !fmt.isBlank() ? fmt : "QXP");
```

---

## `src/test/.../domain/DocumentDomainTest.java` — update stale assertion (#57)
```java
assertEquals("G_100.QXP", doc.getFileName());   // was "G_100.qxp" (verbatim extension now)
```

## Apply checklist
- [ ] RunStatus · AuditDaoImpl · InsertDocumentDaoImpl · EndRunDaoImpl · DocumentDomain · QxpsCallerBusiness · GetDocumentDaoImpl · GetDocumentByIdDaoImpl · DocumentDomainTest
- [ ] `mvn compile` + `mvn test`
- [ ] (deferred) #86 + #88 on the live-DB / golden-file pass
