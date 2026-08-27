# EOS Quark — final backend plan for AMUNDI import and report filenames

## 1. Confirmed scope

- Backend only; the UI will be implemented separately.
- Implement only the import template `IT_AMUNDI_PERIMETER`.
- Add a separate `ReferentialController` for the “Importer un fichier en base” backend.
- Add a dashboard document-download backend for QXP, PDF, and DOC.
- Keep the normal filename rule unchanged for every report type.
- Apply the new AMUNDI filename only to Annual report (`RA`) and Plaquette (`IS`).
- Do not port the generic .NET import engine or its support for other templates.
- Keep the old .NET application fully operational during the several-month parallel run. Database and Java changes must be additive and must not change the legacy import XML, existing package result contract, or existing primary key for this Jira.

## 2. What the .NET “XML template” means

The uploaded file is not XML. It is delimited text data, normally called a CSV file.

The XML is configuration text stored in Oracle:

```text
QXP_TEMPLATE_IMPORT_DEF.NOM_TEMPLATE     = IT_AMUNDI_PERIMETER
QXP_TEMPLATE_IMPORT_DEF.CONTENU_TEMPLATE = <ImportTemplateDef ...>...</ImportTemplateDef>
```

At runtime, .NET calls `QXP_PK_IMPORT.GetImportTemplate`, reads `CONTENU_TEMPLATE`, and deserializes it. The XML tells the generic importer:

- the destination table: `QXP_AMUNDI_PERIMETER`;
- whether the uploaded file has a header;
- the ordered database columns;
- each column's data type;
- nullable and primary-key information.

The checked-in AMUNDI XML currently declares 10 positional columns:

```text
FUND_LABEL, ID_FUND_BWR, DECALOG, FUND_NAME, REPORT_TYPE,
REPORT_DATE, REPORT_LANGUAGE, LEGAL_FORM, EUROPEAN_NORM,
ENGAGEMENT_METHOD
```

It also declares `HasEnTete="false"` and the primary key as `FUND_NAME + REPORT_DATE + REPORT_LANGUAGE`.

The SQL script called “Insert Amundi Template” therefore creates metadata, not imported perimeter rows. It also grants role `3` access through `QXP_ASSO_ROLE_TEMPLATE_IMPORT`. The .NET page uses the signed-in user's role to populate its template dropdown.

For Java, no new XML engine is needed. Because only one template is in scope, Java should use a typed `AmundiPerimeterRecord`, a fixed column contract, and explicit SQL against `QXP_AMUNDI_PERIMETER`. This avoids accepting a table name or column names from the request.

## 3. File formats and parsing controls

### What current .NET accepts

| .NET page | Actual behavior |
|---|---|
| Generic `ImporterFichier` page | Does not validate extension or MIME type. It tries to read any uploaded file as ISO-8859-1 delimited text. It is therefore functionally a CSV/TXT importer, not an Excel, PDF, DOC, or XML importer. |
| `ImporterDonneesLux` page | Separately accepts only `.xls` and parses it through Aspose.Cells. This page is unrelated to `IT_AMUNDI_PERIMETER`. |
| Error-file download | Produces a `.csv` file. |

For the new Java AMUNDI endpoint, accept `.csv` only. Reject XLS, XLSX, XML, PDF, DOC, and binary content.

The .NET page does support a file named `.csv`: it does not validate the extension and treats the upload as delimited text. The limitation is the CSV structure, not the `.csv` suffix. The supplied file `PERIMETRE PROVISOIRE_SGSS_31.12.2025.csv` is UTF-8 with BOM, comma-separated, quote-aware CSV with one header row. That differs from the checked-in .NET configuration, which says no header, reads ISO-8859-1, and offers only `;` or `|||` as column separators. Therefore, the checked-in .NET implementation supports delimiter-separated “CSV-style” files, but cannot parse this exact supplied CSV correctly without different deployed code/configuration or prior file conversion.

### Meaning of the four .NET dropdowns

| Dropdown | .NET values and purpose | Java decision for `IT_AMUNDI_PERIMETER` |
|---|---|---|
| Format de date | `dd/MM/yyyy` or `MM/dd/yyyy`; used to convert `REPORT_DATE` | Implement. Default to `dd/MM/yyyy`, which matches the sample. Accept only the two enum values. |
| Séparateur décimal | `.` or `,`; used only when an XML column has decimal type | Do not apply. This template has no decimal column. The configuration response will mark it as not applicable so the UI can hide it. |
| Séparateur de colonne | `;` or `|||`; .NET uses raw `String.Split` | Do not expose an arbitrary separator. Use comma for the agreed CSV contract and a real quote-aware CSV parser. |
| Séparateur de fin de ligne | newline or `@@@`; .NET first uses `ReadLine`, then splits again | Do not expose it for standard CSV. Detect CRLF/LF automatically. `@@@` is excluded from this Java scope. |

There is commented .NET code intended to select `|||` and `@@@` automatically for AMUNDI, so those values were historically related to this template. However, its event registration and handler are commented out, and the agreed Java input is the supplied standard comma CSV. Legacy `|||`/`@@@` parsing will therefore not be implemented.

### Import modes and partial rows

The visible .NET import modes are:

- `DELETE`: delete rows matching the template key;
- `DELETE_AND_INSERT`: delete matching rows, then insert the uploaded values; this is the default;
- `UPDATE`: update non-key values of matching rows.

`DeleteAll_And_Insert` exists in an enum but is neither displayed nor handled by the page. It is out of scope.

The .NET page performs validation first, displays valid and invalid counts, and then imports only valid rows. Java will preserve that user-visible behavior. Invalid rows are skipped and returned with row number, column, rejected value, and reason. The valid-row database operation will be transactional so a failed replacement cannot delete an existing row without inserting its replacement.

## 4. Java AMUNDI import contract

### CSV columns

Map the ten supplied French headers to the existing columns:

| CSV header | Oracle column |
|---|---|
| `Nom "Fonds"` | `FUND_LABEL` |
| `Code BWR` | `ID_FUND_BWR` |
| `Code "Decalog"` | `DECALOG` |
| `Code Comptable` | `FUND_NAME` |
| `Type de rapport` | `REPORT_TYPE` |
| `Date de clotûre` | `REPORT_DATE` |
| `Langues` | `REPORT_LANGUAGE` |
| `Type de fonds` | `LEGAL_FORM` |
| `Normes Européennes` | `EUROPEAN_NORM` |
| `Méthode calcul d'engagement` | `ENGAGEMENT_METHOD` |

Add the confirmed new CSV field `Code Parapluie` as the eleventh column and map it to `CODE_PARAPLUIE`. Nom-Parapluie/FundName and Code-Parapluie are different values, as shown by `SG-ACTIONS-ETATS-UNIS` versus `UM11182`, but both are Oracle strings. `DECALOG` and `CODE_PARAPLUIE` also remain separate fields.

### Validation

The validation endpoint will:

- require a non-empty `.csv` upload and enforce a configurable, endpoint-level size limit;
- read UTF-8 and remove an optional BOM;
- parse quoted comma-separated CSV correctly, including commas inside quoted values;
- validate the expected header set and reject missing, duplicated, or unknown columns;
- trim text without losing accents;
- parse the selected date format strictly;
- accept only `RA` or `IS` for this scoped importer;
- normalize language to uppercase and require two characters, such as `FR`;
- require the `Code Parapluie` header but allow its row value to be empty;
- validate required fields and Oracle column lengths before database access;
- detect duplicate business keys within the uploaded file;
- verify that `FUND_NAME` exists in `OWB_DWH.REF_FUND`, because the download name needs its long name and currency;
- return total, valid, invalid, and duplicate counts plus detailed row errors.

### Backend endpoints

Under `ReferentialController`:

```text
GET  /api/v1/referential/import-templates
POST /api/v1/referential/amundi-perimeter/validate
POST /api/v1/referential/amundi-perimeter/import
```

The GET response contains only `IT_AMUNDI_PERIMETER` and its supported date formats, import modes, expected headers, CSV-only rule, and `decimalSeparatorApplicable=false`.

The validation call accepts the multipart CSV and date format and returns validation results without changing the database. The import call accepts the same file/options plus the selected mode, reparses it server-side, and executes only valid rows. A SHA-256 returned by validation can be sent back on import to prove that the same file was confirmed.

Both write endpoints require SGIAM/SG Connect authorization and an audit record containing user email, original filename, checksum, mode, counts, and result. The existing Java security configuration protects `/api/v1/**` with `api.quark.v1`, Spring exposes it as `SCOPE_api.quark.v1`, and `OAuth2AuthenticationService` reads `mail` directly from the SG Connect `BearerTokenAuthentication` claims. For this Jira, use the existing `SCOPE_api.quark.v1`; no new dedicated import authority is required. Java will use `mail` for audit and will not query `QXP_UTILISATEUR` or `QXP_ASSO_ROLE_TEMPLATE_IMPORT`. Interactive import must reject a token without a real `mail` value; the existing `external_api` client-credentials fallback is not a human audit identity.

### Required Java layers

```text
ReferentialController
  -> AmundiPerimeterImportSerInterface
  -> AmundiPerimeterImportService
  -> AmundiPerimeterImportBusiness (@Transactional for execution)
  -> AmundiPerimeterDao
  -> SimpleJDBCAmundiPerimeter
```

Use constructor injection, typed domain/DTO objects, explicit bind variables, and the strict quote-aware CSV parser included in the implementation bundle below. The parser uses only the JDK, so `pom.xml` does not change. Do not implement dynamic table or column SQL from XML.

## 5. Current and target report filenames

### Normal .NET filenames — unchanged

Fund-level document:

```text
<FundCode> - <FundLongName> - <DD-MM-YYYY> - <ReportCode>[ - <Language>][ - C].<extension>
```

Part-level document, when `ID_UNIT_CODE` is present:

```text
<FundCode> - <UnitCode> - <FundLongName> - <DD-MM-YYYY> - <ReportCode>[ - <Language>][ - C].<extension>
```

| Report type | Normal report code | Language segment |
|---|---|---|
| Annual report | `RA` | Yes |
| Plaquette | `IP` | Yes |
| Prospectus | `PB` | No |
| Rapport compartiment | `RC` | No |
| DICI | `DICI` | Yes |

`FundLongName` comes from `OWB_DWH.REF_FUND.FND_LNG_DESCRIPTION`. The optional `C` is used for a certified-CAC normal document. The current code replaces `/` and `\` with `-` before download.

### Existing .NET AMUNDI detection and filename

The current Oracle dashboard query left-joins `QXP_AMUNDI_PERIMETER` using:

```text
FUND_NAME = suivi.ID_FND_CODE
REPORT_TYPE = mapped dashboard report type
month/year(REPORT_DATE) = month/year(selected report date)
```

It does not match `REPORT_LANGUAGE`. It returns only `ID_FUND_BWR` from the perimeter. C# treats a non-empty `ID_FUND_BWR` as the AMUNDI indicator.

The legacy query maps Annual to `RA`, Plaquette to `IS`, Prospectus to `PB`, Compartiment to `RC`, and DICI to `DICI`. Despite that mapping, the new business scope is only Annual and Plaquette.

Current AMUNDI filename:

```text
<ReportCode>_<FundLongName>_<YYYYMM>_<UpperLanguageName>_<Currency>_<BWR>_xxx_<LanguageId>_xxx.<extension>
```

For an AMUNDI Plaquette, C# changes the normal `IP` code to `IS`. `FUND_LABEL`, `DECALOG`, and `REPORT_LANGUAGE` from the perimeter are not currently used to build this name. Fund name and currency still come from `REF_FUND`.

### New AMUNDI filename

```text
<ReportType>_<FundName>_<CodeParapluie>_<YYYYMMDD>_FRA_<Language>_<Currency>.<extension>
```

Examples:

```text
AnnualReport_ARCANCIA_UM14174_20241231_FRA_FR_EUR.pdf
PeriodicReport_SG-ACTIONS-ETATS-UNIS_UM11182_20250331_FRA_FR_EUR.pdf
```

| Segment | Rule/source |
|---|---|
| ReportType | Annual/`RA` -> `AnnualReport`; Plaquette/`IS` -> `PeriodicReport` |
| FundName | `REF_FUND.FND_LNG_DESCRIPTION`; trim and change spaces and unsafe filename separators to `-` |
| CodeParapluie | New `QXP_AMUNDI_PERIMETER.CODE_PARAPLUIE` column; convert Oracle `NULL` to an empty filename segment |
| YYYYMMDD | Matched perimeter `REPORT_DATE`, formatted `yyyyMMdd` |
| Country | Fixed literal `FRA` |
| Language | Matched perimeter `REPORT_LANGUAGE`, uppercase two-character code such as `FR` |
| Currency | `REF_FUND.FND_CURRENCY` |
| extension | The requested, whitelisted lowercase type: `qxp`, `pdf`, or `doc` |

### When the special rule applies

Java must derive the decision from `idSuivi`; the UI must not send `isAmundi`, fund name, currency, date, language, or Code-Parapluie.

Use the new AMUNDI formatter only when exactly one perimeter row matches:

```text
report is Annual or Plaquette
AND FUND_NAME = suivi.ID_FND_CODE
AND REPORT_TYPE = RA or IS respectively
AND report month/year matches the selected suivi report month/year
AND REPORT_LANGUAGE matches the suivi language
```

Decision:

```text
Not RA/IS                                  -> normal filename
RA/IS with zero perimeter rows            -> normal filename
RA/IS with one row and Code-Parapluie     -> new AMUNDI filename
RA/IS with one row but no Code-Parapluie  -> new AMUNDI filename with an empty segment and warning log
Duplicate/otherwise unusable match        -> normal filename and warning log
```

PB, RC, and DICI always keep normal naming, even if a legacy perimeter row exists for them.

### Download endpoint and layers

```text
GET /api/v1/tableau-de-bord/suivis/{idSuivi}/documents/{format}
```

`format` is an enum limited to QXP, PDF, and DOC. On every request, the service reloads the bytes and naming inputs from Oracle, applies one of the two filename strategies, sets a safe `Content-Disposition: attachment`, returns the correct content type with `Cache-Control: no-store`, and updates only the requested QXP/PDF/DOC visited flag after the document was successfully found. Re-querying and disabling caching ensure that a download immediately after a corrected CSV import receives the corrected filename.

```text
TableauDeBordController
  -> DocumentDownloadSerInterface
  -> DocumentDownloadService
  -> DocumentDownloadBusiness
  -> DocumentDownloadDao
  -> SimpleJDBCDocumentDownload
```

The existing Oracle `GetContenuDocument` and `UpdateStatutDocument` operations can be reused. Add a separate Java-specific metadata query/DAO operation for Code-Parapluie, perimeter date, and perimeter language. Do not change the existing .NET dashboard cursor/result contract during the parallel run.

## 6. Database changes and deployment safety

Add the new column first as nullable so the old .NET application can coexist during migration. Oracle requires a size for `VARCHAR2`; `VARCHAR2(50 CHAR)` is the current recommendation for the code identifier and leaves substantial room beyond examples such as `UM11182`:

```sql
ALTER TABLE QXP_AMUNDI_PERIMETER
ADD CODE_PARAPLUIE VARCHAR2(50 CHAR);
```

Then:

1. Confirm the live column definitions and key; checked-in SQL may not match production.
2. Leave existing `CODE_PARAPLUIE` values null; no automatic backfill is required.
3. Import the new 11-column CSV through Java when users provide Code-Parapluie.
4. Enable the new filename strategy after compatibility testing/UAT, preferably behind a configuration flag.
5. Keep the column during rollback; disable the new formatter rather than dropping data.

Risks to resolve:

- the checked-in primary key identifies a row using `FUND_NAME + REPORT_DATE + REPORT_LANGUAGE`. It does not include `REPORT_TYPE`. The supplied 148-row CSV contains no fund/date/language combination with both RA and IS, so no key change is required for this Jira. If that business case is introduced later, `REPORT_TYPE` must be added to the primary/unique key;
- the checked-in `FUND_NAME` is `VARCHAR2(6)` while live/sample values must be checked before coding length validation;
- the existing .NET XML has 10 fields and cannot provide Code-Parapluie, but its generated insert explicitly names those 10 columns, so the additional nullable column does not break the old import;
- Oracle stores a zero-character `VARCHAR2` value as `NULL`; Java must convert a null Code-Parapluie to `""` while formatting the filename;
- the old .NET default `DELETE_AND_INSERT` deletes the matched row and inserts only its 10 configured columns. If Java previously populated Code-Parapluie, that legacy re-import resets it to null. This does not crash either application: the next Java download shows an empty Code-Parapluie segment, and a new Java 11-column import restores it;
- keep Code-Parapluie nullable for the entire .NET/Java coexistence period;
- the Java Liquibase changelog is still an archetype example rather than an established Quark schema history.

The Java implementation does not require changing `QXP_TEMPLATE_IMPORT_DEF`. Update that XML only if the old .NET importer must also accept the new 11-column file during coexistence.

For this enhancement, an authorized developer/DBA can run the confirmed `ALTER TABLE` directly while connected to the correct QXP database, first in development, then UAT, then production. Keep the executed SQL and a documented rollback procedure with the source code. Check first that the column does not already exist, because the statement is intended to run once. Oracle commits DDL automatically, so an ordinary `ROLLBACK` cannot undo it. If deployment fails before data is imported, an explicit `ALTER TABLE ... DROP COLUMN` can remove it; after real data is stored, the safer rollback is to disable/roll back the Java feature and leave the harmless nullable column in place. The Java application then only reads and writes the table; it does not change the table automatically when the application starts.

Liquibase can be adopted later as the standard database-deployment tool, but the checked-in Quark Liquibase files are currently only an archetype example. Do not mix Liquibase and DBA scripts for the same change.

## 7. Implementation sequence

1. Run the nullable `CODE_PARAPLUIE` schema change; do not change the existing primary key in this Jira.
2. Copy the new Java files from section 12 into the work-laptop repository. No existing Java class or `pom.xml` changes are required.
3. Run the automated tests and the live-Oracle verification queries in section 13.
4. Test with the supplied CSV, null and populated Code-Parapluie values, the old .NET application, and exact QXP/PDF/DOC download names.
5. Enable the Java endpoints after UAT; normal naming remains the fallback whenever the AMUNDI match is absent, duplicated, or unusable.

## 8. Minimum acceptance tests

- The supplied UTF-8 BOM, quoted, comma-separated CSV validates successfully after the eleventh `Code Parapluie` header is supplied; its individual value may be empty.
- Header mismatch, wrong field count, invalid date, invalid language, duplicate key, excessive length, and unknown fund produce row-specific errors.
- Decimal separator is not requested or used.
- CRLF and LF both work; quoted commas are preserved.
- `DELETE`, `DELETE_AND_INSERT`, and `UPDATE` affect only the typed AMUNDI table and report accurate counts.
- Users without the existing `SCOPE_api.quark.v1` authority cannot validate or import; no `QXP_UTILISATEUR` lookup is performed.
- Normal RA, IP, PB, RC, and DICI filenames remain byte-for-byte compatible with .NET behavior.
- A complete RA match produces `AnnualReport_...` and a complete IS match produces `PeriodicReport_...`.
- PB, RC, and DICI never use the new formatter.
- The date is the matched perimeter date; country is `FRA`; language is two characters; currency is from `REF_FUND`.
- QXP, PDF, and DOC share the same basename and retain the requested extension.
- Zero or duplicate/unusable perimeter match uses the normal filename and writes a warning log.
- One RA/IS perimeter match with null Code-Parapluie still uses the AMUNDI formatter and produces a deliberate empty segment, for example `AnnualReport_ARCANCIA__20241231_FRA_FR_EUR.pdf`.
- After a Java import supplies Code-Parapluie, the next download re-queries Oracle and immediately uses the corrected filename.
- The old .NET importer and QXP/PDF/DOC downloads still work after adding the nullable column.
- An old .NET `DELETE_AND_INSERT` on a Java-populated row resets Code-Parapluie to null; the subsequent Java download/import follows the agreed empty-then-correct workflow.
- Only the downloaded format's visited flag is updated.

## 9. Confirmed database/data decisions

1. Add `CODE_PARAPLUIE VARCHAR2(50 CHAR)` directly to the live table as a nullable column.
2. Do not change the existing primary key or include `REPORT_TYPE` in it.
3. Do not backfill old rows. A missing value remains Oracle `NULL` and becomes an empty Code-Parapluie filename segment.
4. Users correct missing values by uploading the new 11-column CSV through Java and downloading the document again.
5. Preserve the old .NET application throughout the parallel run; do not change its 10-column XML template.

## 10. Estimate

Estimated backend and database effort for this narrowed scope: **8–12 developer-days**, including implementation, automated tests, deployment scripts, and UAT support. This excludes UI work and migration of the complete Tableau de bord page-2 list endpoint.

## 11. Main sources checked

- `QXP.WebSite/Import/ImporterFichier.cs`
- `QXP.WebSite/Import/ImporterDonneesLux.cs`
- `QXP.Import/Business/ImportLoader.cs`
- `QXP.Import/Proxy/ProxyImport.cs`
- `QXP.SQL/05 - Donnees/50 - Insert Amundi Template.sql`
- `QXP.SQL/06 - Packages/617 - QXP_PK_IMPORT/02 - QXP_PK_IMPORT_BODY.sql`
- `QXP.WebSite/Generation/TableauDeBord/DataList/TDB/DataListTDBItem.cs`
- `QXP.Web/Proxy/ProxySuivi.cs`
- `QXP.SQL/06 - Packages/607 - QXP_PK_SUIVI/02 - QXP_PK_SUIVI_BODY.sql`
- Java controller, service, business, DAO, authentication, transaction, download-response, architecture-test, and Liquibase examples in `quark-backend-api`

## 12. Copy-ready Java implementation

### 12.1 What changes and what does not

Create only the new files listed below in `quark-backend-api`. Do not modify an existing Java class, `pom.xml`, the .NET application, `QXP_TEMPLATE_IMPORT_DEF`, or `QXP_PK_SUIVI`. The implementation deliberately uses only dependencies already present in the Java project.

```text
src/main/java/com/socgen/sgs/api/quark/backend/api/
├── Business/
│   ├── AmundiCsvParser.java
│   ├── AmundiPerimeterImportBusiness.java
│   ├── DocumentDownloadBusiness.java
│   └── ReportFilenameBusiness.java
├── domain/
│   ├── AmundiImportModels.java
│   ├── FeatureExceptions.java
│   └── ReportDownloadModels.java
├── infra/
│   ├── api/
│   │   ├── exception/AmundiFeatureExceptionHandler.java
│   │   └── v1/
│   │       ├── ReferentialController.java
│   │       └── TableauDeBordDocumentController.java
│   └── dao/
│       ├── AmundiPerimeterDao.java
│       ├── DocumentDownloadDao.java
│       └── Impl/
│           ├── SimpleJDBCAmundiPerimeter.java
│           └── SimpleJDBCDocumentDownload.java
└── service/
    ├── AmundiPerimeterImportSerInterface.java
    ├── DocumentDownloadSerInterface.java
    └── Impl/
        ├── AmundiPerimeterImportService.java
        └── DocumentDownloadService.java
```

The two unit-test files are listed in section 12.18.

### 12.2 `domain/AmundiImportModels.java`

```java
package com.socgen.sgs.api.quark.backend.api.domain;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.ResolverStyle;
import java.util.List;
import java.util.Objects;

public final class AmundiImportModels {

    public static final String TEMPLATE_NAME = "IT_AMUNDI_PERIMETER";

    public static final List<String> EXPECTED_HEADERS = List.of(
            "Nom \"Fonds\"",
            "Code BWR",
            "Code \"Decalog\"",
            "Code Comptable",
            "Type de rapport",
            "Date de clotûre",
            "Langues",
            "Type de fonds",
            "Normes Européennes",
            "Méthode calcul d'engagement",
            "Code Parapluie"
    );

    private AmundiImportModels() {
    }

    public enum AmundiDateFormat {
        DD_MM_YYYY("dd/MM/uuuu"),
        MM_DD_YYYY("MM/dd/uuuu");

        private final DateTimeFormatter formatter;

        AmundiDateFormat(String pattern) {
            this.formatter = DateTimeFormatter.ofPattern(pattern)
                    .withResolverStyle(ResolverStyle.STRICT);
        }

        public LocalDate parse(String value) {
            return LocalDate.parse(value, formatter);
        }
    }

    public enum AmundiImportMode {
        DELETE,
        DELETE_AND_INSERT,
        UPDATE
    }

    public record UploadedFile(String originalFilename, byte[] content) {
        public UploadedFile {
            originalFilename = Objects.requireNonNullElse(originalFilename, "").trim();
            content = Objects.requireNonNull(content, "content").clone();
        }

        @Override
        public byte[] content() {
            return content.clone();
        }
    }

    public record AmundiPerimeterRecord(
            String fundLabel,
            String idFundBwr,
            String decalog,
            String fundName,
            String reportType,
            LocalDate reportDate,
            String reportLanguage,
            String legalForm,
            String europeanNorm,
            String engagementMethod,
            String codeParapluie) {

        public AmundiBusinessKey key() {
            return new AmundiBusinessKey(fundName, reportDate, reportLanguage);
        }
    }

    public record AmundiBusinessKey(
            String fundName,
            LocalDate reportDate,
            String reportLanguage) {
    }

    public record ParsedAmundiRow(long rowNumber, AmundiPerimeterRecord value) {
    }

    public record AmundiImportRowError(
            long rowNumber,
            String column,
            String rejectedValue,
            String reason) {
    }

    public record CsvParseResult(
            String checksumSha256,
            int totalRows,
            List<ParsedAmundiRow> validRows,
            List<AmundiImportRowError> errors,
            int duplicateRows) {
        public CsvParseResult {
            validRows = List.copyOf(validRows);
            errors = List.copyOf(errors);
        }
    }

    public record AmundiImportValidationResult(
            String templateName,
            String originalFilename,
            String checksumSha256,
            int totalRows,
            int validRows,
            int invalidRows,
            int duplicateRows,
            List<AmundiImportRowError> errors) {
        public AmundiImportValidationResult {
            errors = List.copyOf(errors);
        }
    }

    public record AmundiImportResult(
            AmundiImportValidationResult validation,
            AmundiImportMode mode,
            int deletedRows,
            int insertedRows,
            int updatedRows,
            int unchangedRows) {
    }

    public record AmundiImportTemplateConfiguration(
            String templateName,
            String acceptedFileExtension,
            String charset,
            String columnSeparator,
            boolean headerRequired,
            List<String> expectedHeaders,
            List<AmundiDateFormat> dateFormats,
            AmundiDateFormat defaultDateFormat,
            List<AmundiImportMode> importModes,
            AmundiImportMode defaultImportMode,
            boolean decimalSeparatorApplicable,
            boolean customLineSeparatorApplicable) {
        public AmundiImportTemplateConfiguration {
            expectedHeaders = List.copyOf(expectedHeaders);
            dateFormats = List.copyOf(dateFormats);
            importModes = List.copyOf(importModes);
        }
    }
}
```

### 12.3 `domain/ReportDownloadModels.java`

```java
package com.socgen.sgs.api.quark.backend.api.domain;

import java.time.LocalDate;
import java.util.Locale;
import java.util.Objects;

public final class ReportDownloadModels {

    private ReportDownloadModels() {
    }

    public enum DocumentFormat {
        QXP(1, "qxp", "application/quark-ps"),
        PDF(2, "pdf", "application/pdf"),
        DOC(3, "doc", "application/msword");

        private final int oracleValue;
        private final String extension;
        private final String mediaType;

        DocumentFormat(int oracleValue, String extension, String mediaType) {
            this.oracleValue = oracleValue;
            this.extension = extension;
            this.mediaType = mediaType;
        }

        public static DocumentFormat fromPath(String value) {
            try {
                return valueOf(Objects.requireNonNull(value, "format")
                        .trim().toUpperCase(Locale.ROOT));
            } catch (RuntimeException exception) {
                throw new IllegalArgumentException("format must be qxp, pdf, or doc", exception);
            }
        }

        public int oracleValue() {
            return oracleValue;
        }

        public String extension() {
            return extension;
        }

        public String mediaType() {
            return mediaType;
        }
    }

    public record ReportNamingContext(
            long idSuivi,
            String fundCode,
            String unitCode,
            int reportTypeId,
            int statusId,
            LocalDate reportDate,
            String fundName,
            String currency,
            String language,
            boolean fundBasedSuivi) {
    }

    public record AmundiFilenameMatch(
            LocalDate reportDate,
            String reportLanguage,
            String codeParapluie) {
    }

    public record ReportDownload(byte[] content, String filename, String mediaType) {
        public ReportDownload {
            content = Objects.requireNonNull(content, "content").clone();
            filename = Objects.requireNonNull(filename, "filename");
            mediaType = Objects.requireNonNull(mediaType, "mediaType");
        }

        @Override
        public byte[] content() {
            return content.clone();
        }
    }
}
```

### 12.4 `domain/FeatureExceptions.java`

```java
package com.socgen.sgs.api.quark.backend.api.domain;

public final class FeatureExceptions {

    private FeatureExceptions() {
    }

    public static final class ImportRejectedException extends RuntimeException {
        public ImportRejectedException(String message) {
            super(message);
        }

        public ImportRejectedException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    public static final class ResourceNotFoundException extends RuntimeException {
        public ResourceNotFoundException(String message) {
            super(message);
        }
    }

    public static final class FeatureConfigurationException extends RuntimeException {
        public FeatureConfigurationException(String message) {
            super(message);
        }
    }
}
```

### 12.5 `Business/AmundiCsvParser.java`

```java
package com.socgen.sgs.api.quark.backend.api.Business;

import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiBusinessKey;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiDateFormat;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportRowError;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiPerimeterRecord;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.CsvParseResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.ParsedAmundiRow;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.UploadedFile;
import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.FeatureConfigurationException;
import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.ImportRejectedException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import static com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.EXPECTED_HEADERS;

@Component
public class AmundiCsvParser {

    private static final List<String> DB_COLUMNS = List.of(
            "FUND_LABEL", "ID_FUND_BWR", "DECALOG", "FUND_NAME",
            "REPORT_TYPE", "REPORT_DATE", "REPORT_LANGUAGE", "LEGAL_FORM",
            "EUROPEAN_NORM", "ENGAGEMENT_METHOD", "CODE_PARAPLUIE"
    );

    private static final Set<Integer> OPTIONAL_COLUMNS = Set.of(9, 10);

    private final long maxFileSizeBytes;

    public AmundiCsvParser(
            @Value("${quark.referential.amundi.max-file-size-bytes:10485760}")
            long maxFileSizeBytes) {
        this.maxFileSizeBytes = maxFileSizeBytes;
    }

    public CsvParseResult parse(
            UploadedFile file,
            AmundiDateFormat dateFormat,
            Map<String, Integer> liveColumnLengths) {

        validateFile(file);
        verifyLiveSchema(liveColumnLengths);

        byte[] bytes = file.content();
        String checksum = sha256(bytes);
        String csv = decodeUtf8(bytes);
        if (!csv.isEmpty() && csv.charAt(0) == '\uFEFF') {
            csv = csv.substring(1);
        }

        List<List<String>> records = parseCsv(csv);
        records.removeIf(this::isCompletelyEmpty);
        if (records.isEmpty()) {
            throw new ImportRejectedException("The CSV file has no header row");
        }

        validateHeader(records.getFirst());

        List<ParsedAmundiRow> validRows = new ArrayList<>();
        List<AmundiImportRowError> errors = new ArrayList<>();
        Set<AmundiBusinessKey> keys = new HashSet<>();
        int duplicateRows = 0;
        int totalRows = 0;

        for (int index = 1; index < records.size(); index++) {
            List<String> values = records.get(index);
            long csvRowNumber = index + 1L;
            totalRows++;

            if (values.size() != EXPECTED_HEADERS.size()) {
                errors.add(new AmundiImportRowError(
                        csvRowNumber,
                        "_ROW",
                        Integer.toString(values.size()),
                        "Expected exactly 11 columns but found " + values.size()));
                continue;
            }

            List<AmundiImportRowError> rowErrors = new ArrayList<>();
            String[] normalized = values.stream()
                    .map(value -> value == null ? "" : value.trim())
                    .toArray(String[]::new);

            for (int columnIndex = 0; columnIndex < normalized.length; columnIndex++) {
                if (!OPTIONAL_COLUMNS.contains(columnIndex) && normalized[columnIndex].isBlank()) {
                    rowErrors.add(error(csvRowNumber, columnIndex, normalized[columnIndex], "Value is required"));
                }
                validateLength(csvRowNumber, columnIndex, normalized[columnIndex], liveColumnLengths, rowErrors);
            }

            String reportType = normalized[4].toUpperCase(Locale.ROOT);
            if (!reportType.equals("RA") && !reportType.equals("IS")) {
                rowErrors.add(error(csvRowNumber, 4, normalized[4], "Only RA and IS are supported"));
            }

            String language = normalized[6].toUpperCase(Locale.ROOT);
            if (!language.matches("[A-Z]{2}")) {
                rowErrors.add(error(csvRowNumber, 6, normalized[6], "Language must contain exactly two letters"));
            }

            LocalDate reportDate = null;
            try {
                reportDate = dateFormat.parse(normalized[5]);
            } catch (DateTimeParseException exception) {
                rowErrors.add(error(csvRowNumber, 5, normalized[5],
                        "Date does not match " + dateFormat));
            }

            if (!rowErrors.isEmpty()) {
                errors.addAll(rowErrors);
                continue;
            }

            AmundiPerimeterRecord record = new AmundiPerimeterRecord(
                    normalized[0],
                    normalized[1],
                    normalized[2],
                    normalized[3].toUpperCase(Locale.ROOT),
                    reportType,
                    reportDate,
                    language,
                    normalized[7],
                    normalized[8],
                    nullIfBlank(normalized[9]),
                    nullIfBlank(normalized[10])
            );

            if (!keys.add(record.key())) {
                duplicateRows++;
                errors.add(new AmundiImportRowError(
                        csvRowNumber,
                        "FUND_NAME/REPORT_DATE/REPORT_LANGUAGE",
                        record.fundName() + "/" + record.reportDate() + "/" + record.reportLanguage(),
                        "Duplicate business key in the uploaded file"));
                continue;
            }

            validRows.add(new ParsedAmundiRow(csvRowNumber, record));
        }

        return new CsvParseResult(checksum, totalRows, validRows, errors, duplicateRows);
    }

    private void validateFile(UploadedFile file) {
        String filename = file.originalFilename().toLowerCase(Locale.ROOT);
        if (!filename.endsWith(".csv")) {
            throw new ImportRejectedException("Only .csv files are accepted");
        }
        if (file.content().length == 0) {
            throw new ImportRejectedException("The CSV file is empty");
        }
        if (file.content().length > maxFileSizeBytes) {
            throw new ImportRejectedException(
                    "The CSV file exceeds the maximum size of " + maxFileSizeBytes + " bytes");
        }
    }

    private void verifyLiveSchema(Map<String, Integer> liveColumnLengths) {
        for (String column : DB_COLUMNS) {
            if (!liveColumnLengths.containsKey(column)) {
                throw new FeatureConfigurationException(
                        "Oracle column QXP_AMUNDI_PERIMETER." + column + " is missing");
            }
        }
    }

    private void validateHeader(List<String> actualHeader) {
        if (!EXPECTED_HEADERS.equals(actualHeader)) {
            throw new ImportRejectedException(
                    "CSV header must exactly match, in order: " + String.join(" | ", EXPECTED_HEADERS));
        }
    }

    private void validateLength(
            long rowNumber,
            int columnIndex,
            String value,
            Map<String, Integer> liveColumnLengths,
            List<AmundiImportRowError> errors) {

        if (value.isEmpty() || columnIndex == 5) {
            return;
        }
        Integer maximum = liveColumnLengths.get(DB_COLUMNS.get(columnIndex));
        if (maximum != null && maximum > 0 && value.length() > maximum) {
            errors.add(error(rowNumber, columnIndex, value,
                    "Maximum Oracle length is " + maximum + " characters"));
        }
    }

    private AmundiImportRowError error(long rowNumber, int columnIndex, String value, String reason) {
        return new AmundiImportRowError(
                rowNumber,
                EXPECTED_HEADERS.get(columnIndex),
                abbreviate(value),
                reason);
    }

    private String decodeUtf8(byte[] bytes) {
        try {
            return StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes))
                    .toString();
        } catch (CharacterCodingException exception) {
            throw new ImportRejectedException("The CSV file must be valid UTF-8", exception);
        }
    }

    private String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private List<List<String>> parseCsv(String csv) {
        List<List<String>> rows = new ArrayList<>();
        List<String> row = new ArrayList<>();
        StringBuilder field = new StringBuilder();
        boolean inQuotes = false;
        boolean afterClosingQuote = false;
        boolean fieldStarted = false;
        int physicalLine = 1;

        for (int index = 0; index < csv.length(); index++) {
            char current = csv.charAt(index);

            if (inQuotes) {
                if (current == '"') {
                    if (index + 1 < csv.length() && csv.charAt(index + 1) == '"') {
                        field.append('"');
                        index++;
                    } else {
                        inQuotes = false;
                        afterClosingQuote = true;
                    }
                } else if (current == '\r' || current == '\n') {
                    if (current == '\r' && index + 1 < csv.length() && csv.charAt(index + 1) == '\n') {
                        index++;
                    }
                    field.append('\n');
                    physicalLine++;
                } else {
                    field.append(current);
                }
                continue;
            }

            if (current == ',') {
                row.add(field.toString());
                field.setLength(0);
                fieldStarted = false;
                afterClosingQuote = false;
            } else if (current == '\r' || current == '\n') {
                if (current == '\r' && index + 1 < csv.length() && csv.charAt(index + 1) == '\n') {
                    index++;
                }
                row.add(field.toString());
                rows.add(row);
                row = new ArrayList<>();
                field.setLength(0);
                fieldStarted = false;
                afterClosingQuote = false;
                physicalLine++;
            } else if (current == '"') {
                if (fieldStarted || field.length() > 0 || afterClosingQuote) {
                    throw new ImportRejectedException("Malformed quote near CSV line " + physicalLine);
                }
                inQuotes = true;
                fieldStarted = true;
            } else if (afterClosingQuote) {
                if (!Character.isWhitespace(current)) {
                    throw new ImportRejectedException(
                            "Unexpected character after closing quote near CSV line " + physicalLine);
                }
            } else {
                field.append(current);
                fieldStarted = true;
            }
        }

        if (inQuotes) {
            throw new ImportRejectedException("Unclosed quoted field at end of CSV");
        }
        if (!row.isEmpty() || field.length() > 0 || fieldStarted || afterClosingQuote) {
            row.add(field.toString());
            rows.add(row);
        }
        return rows;
    }

    private boolean isCompletelyEmpty(List<String> row) {
        return row.stream().allMatch(value -> value == null || value.isBlank());
    }

    private String nullIfBlank(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    private String abbreviate(String value) {
        if (value == null || value.length() <= 200) {
            return value;
        }
        return value.substring(0, 197) + "...";
    }
}
```

### 12.6 `infra/dao/AmundiPerimeterDao.java`

```java
package com.socgen.sgs.api.quark.backend.api.infra.dao;

import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiPerimeterRecord;

import java.util.List;
import java.util.Map;
import java.util.Set;

public interface AmundiPerimeterDao {

    Map<String, Integer> findLiveColumnLengths();

    Set<String> findExistingFundCodes(Set<String> fundCodes);

    int deleteMatching(List<AmundiPerimeterRecord> records);

    int insert(List<AmundiPerimeterRecord> records);

    int update(List<AmundiPerimeterRecord> records);
}
```

### 12.7 `infra/dao/Impl/SimpleJDBCAmundiPerimeter.java`

```java
package com.socgen.sgs.api.quark.backend.api.infra.dao.Impl;

import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiPerimeterRecord;
import com.socgen.sgs.api.quark.backend.api.infra.dao.AmundiPerimeterDao;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.BatchPreparedStatementSetter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Repository
@RequiredArgsConstructor
public class SimpleJDBCAmundiPerimeter implements AmundiPerimeterDao {

    private static final int ORACLE_IN_LIMIT_SAFE_CHUNK = 900;

    private static final String COLUMN_METADATA_SQL = """
            SELECT COLUMN_NAME, CHAR_LENGTH
            FROM USER_TAB_COLUMNS
            WHERE TABLE_NAME = 'QXP_AMUNDI_PERIMETER'
            """;

    private static final String FUND_LOOKUP_SQL = """
            SELECT DISTINCT rf.ID_FND_CODE
            FROM OWB_DWH.REF_FUND rf
            WHERE rf.ID_FND_CODE IN (:fundCodes)
              AND rf.FND_END_VALIDITY = TO_DATE('31/12/2199', 'DD/MM/YYYY')
            """;

    private static final String DELETE_SQL = """
            DELETE FROM QXP_AMUNDI_PERIMETER
            WHERE FUND_NAME = ?
              AND REPORT_DATE = ?
              AND REPORT_LANGUAGE = ?
            """;

    private static final String INSERT_SQL = """
            INSERT INTO QXP_AMUNDI_PERIMETER (
                FUND_LABEL, ID_FUND_BWR, DECALOG, FUND_NAME, REPORT_TYPE,
                REPORT_DATE, REPORT_LANGUAGE, LEGAL_FORM, EUROPEAN_NORM,
                ENGAGEMENT_METHOD, CODE_PARAPLUIE
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """;

    private static final String UPDATE_SQL = """
            UPDATE QXP_AMUNDI_PERIMETER
            SET FUND_LABEL = ?,
                ID_FUND_BWR = ?,
                DECALOG = ?,
                REPORT_TYPE = ?,
                LEGAL_FORM = ?,
                EUROPEAN_NORM = ?,
                ENGAGEMENT_METHOD = ?,
                CODE_PARAPLUIE = ?
            WHERE FUND_NAME = ?
              AND REPORT_DATE = ?
              AND REPORT_LANGUAGE = ?
            """;

    private final JdbcTemplate jdbcTemplate;
    private final NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @Override
    public Map<String, Integer> findLiveColumnLengths() {
        Map<String, Integer> result = new HashMap<>();
        jdbcTemplate.query(COLUMN_METADATA_SQL, resultSet -> {
            Number length = (Number) resultSet.getObject("CHAR_LENGTH");
            result.put(resultSet.getString("COLUMN_NAME"), length == null ? null : length.intValue());
        });
        return result;
    }

    @Override
    public Set<String> findExistingFundCodes(Set<String> fundCodes) {
        if (fundCodes.isEmpty()) {
            return Set.of();
        }

        List<String> allCodes = new ArrayList<>(fundCodes);
        Set<String> existing = new HashSet<>();
        for (int start = 0; start < allCodes.size(); start += ORACLE_IN_LIMIT_SAFE_CHUNK) {
            int end = Math.min(start + ORACLE_IN_LIMIT_SAFE_CHUNK, allCodes.size());
            MapSqlParameterSource parameters = new MapSqlParameterSource(
                    "fundCodes", allCodes.subList(start, end));
            existing.addAll(namedParameterJdbcTemplate.queryForList(
                    FUND_LOOKUP_SQL, parameters, String.class));
        }
        return existing;
    }

    @Override
    public int deleteMatching(List<AmundiPerimeterRecord> records) {
        return affectedRows(jdbcTemplate.batchUpdate(DELETE_SQL, new BatchPreparedStatementSetter() {
            @Override
            public void setValues(PreparedStatement statement, int index) throws SQLException {
                AmundiPerimeterRecord row = records.get(index);
                statement.setString(1, row.fundName());
                statement.setDate(2, Date.valueOf(row.reportDate()));
                statement.setString(3, row.reportLanguage());
            }

            @Override
            public int getBatchSize() {
                return records.size();
            }
        }));
    }

    @Override
    public int insert(List<AmundiPerimeterRecord> records) {
        return affectedRows(jdbcTemplate.batchUpdate(INSERT_SQL, new BatchPreparedStatementSetter() {
            @Override
            public void setValues(PreparedStatement statement, int index) throws SQLException {
                AmundiPerimeterRecord row = records.get(index);
                statement.setString(1, row.fundLabel());
                statement.setString(2, row.idFundBwr());
                statement.setString(3, row.decalog());
                statement.setString(4, row.fundName());
                statement.setString(5, row.reportType());
                statement.setDate(6, Date.valueOf(row.reportDate()));
                statement.setString(7, row.reportLanguage());
                statement.setString(8, row.legalForm());
                statement.setString(9, row.europeanNorm());
                setNullableString(statement, 10, row.engagementMethod());
                setNullableString(statement, 11, row.codeParapluie());
            }

            @Override
            public int getBatchSize() {
                return records.size();
            }
        }));
    }

    @Override
    public int update(List<AmundiPerimeterRecord> records) {
        return affectedRows(jdbcTemplate.batchUpdate(UPDATE_SQL, new BatchPreparedStatementSetter() {
            @Override
            public void setValues(PreparedStatement statement, int index) throws SQLException {
                AmundiPerimeterRecord row = records.get(index);
                statement.setString(1, row.fundLabel());
                statement.setString(2, row.idFundBwr());
                statement.setString(3, row.decalog());
                statement.setString(4, row.reportType());
                statement.setString(5, row.legalForm());
                statement.setString(6, row.europeanNorm());
                setNullableString(statement, 7, row.engagementMethod());
                setNullableString(statement, 8, row.codeParapluie());
                statement.setString(9, row.fundName());
                statement.setDate(10, Date.valueOf(row.reportDate()));
                statement.setString(11, row.reportLanguage());
            }

            @Override
            public int getBatchSize() {
                return records.size();
            }
        }));
    }

    private void setNullableString(PreparedStatement statement, int position, String value)
            throws SQLException {
        if (value == null || value.isBlank()) {
            statement.setNull(position, Types.VARCHAR);
        } else {
            statement.setString(position, value);
        }
    }

    private int affectedRows(int[] counts) {
        int total = 0;
        for (int count : counts) {
            if (count > 0) {
                total += count;
            } else if (count == Statement.SUCCESS_NO_INFO) {
                total++;
            }
        }
        return total;
    }
}
```

### 12.8 `Business/AmundiPerimeterImportBusiness.java`

```java
package com.socgen.sgs.api.quark.backend.api.Business;

import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiDateFormat;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportMode;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportRowError;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportTemplateConfiguration;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportValidationResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiPerimeterRecord;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.CsvParseResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.ParsedAmundiRow;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.UploadedFile;
import com.socgen.sgs.api.quark.backend.api.domain.Audit;
import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.ImportRejectedException;
import com.socgen.sgs.api.quark.backend.api.infra.dao.AmundiPerimeterDao;
import com.socgen.sgs.api.quark.backend.api.infra.dao.AuditInsertTraceDao;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.EXPECTED_HEADERS;
import static com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.TEMPLATE_NAME;

@Slf4j
@Component
@RequiredArgsConstructor
public class AmundiPerimeterImportBusiness {

    private final AmundiCsvParser csvParser;
    private final AmundiPerimeterDao amundiPerimeterDao;
    private final AuditInsertTraceDao auditInsertTraceDao;

    public AmundiImportTemplateConfiguration configuration() {
        return new AmundiImportTemplateConfiguration(
                TEMPLATE_NAME,
                ".csv",
                "UTF-8 with optional BOM",
                ",",
                true,
                EXPECTED_HEADERS,
                List.of(AmundiDateFormat.values()),
                AmundiDateFormat.DD_MM_YYYY,
                List.of(AmundiImportMode.DELETE, AmundiImportMode.DELETE_AND_INSERT, AmundiImportMode.UPDATE),
                AmundiImportMode.DELETE_AND_INSERT,
                false,
                false);
    }

    @Transactional
    public AmundiImportValidationResult validate(
            UploadedFile file,
            AmundiDateFormat dateFormat,
            String userEmail,
            String clientIp) {

        long startedAt = System.nanoTime();
        try {
            CsvParseResult parsed = parseAndValidateFunds(file, dateFormat);
            AmundiImportValidationResult result = toValidation(file, parsed);
            writeAudit("ValidateAmundiPerimeter", file, result, null, userEmail, clientIp,
                    startedAt, 0, "Validation completed");
            return result;
        } catch (RuntimeException exception) {
            writeFailureAudit("ValidateAmundiPerimeter", file, null, userEmail, clientIp,
                    startedAt, exception);
            throw exception;
        }
    }

    @Transactional
    public AmundiImportResult importFile(
            UploadedFile file,
            AmundiDateFormat dateFormat,
            AmundiImportMode mode,
            String expectedChecksum,
            String userEmail,
            String clientIp) {

        long startedAt = System.nanoTime();
        try {
            CsvParseResult parsed = parseAndValidateFunds(file, dateFormat);
            AmundiImportValidationResult validation = toValidation(file, parsed);

            if (expectedChecksum == null
                    || !parsed.checksumSha256().equalsIgnoreCase(expectedChecksum.trim())) {
                throw new ImportRejectedException(
                        "The uploaded file is not the same file that was validated (SHA-256 mismatch)");
            }
            if (parsed.validRows().isEmpty()) {
                throw new ImportRejectedException("There are no valid rows to import");
            }

            List<AmundiPerimeterRecord> rows = parsed.validRows().stream()
                    .map(ParsedAmundiRow::value)
                    .toList();

            int deleted = 0;
            int inserted = 0;
            int updated = 0;

            switch (mode) {
                case DELETE -> deleted = amundiPerimeterDao.deleteMatching(rows);
                case DELETE_AND_INSERT -> {
                    deleted = amundiPerimeterDao.deleteMatching(rows);
                    inserted = amundiPerimeterDao.insert(rows);
                }
                case UPDATE -> updated = amundiPerimeterDao.update(rows);
            }

            int primaryAffected = switch (mode) {
                case DELETE -> deleted;
                case DELETE_AND_INSERT -> inserted;
                case UPDATE -> updated;
            };
            int unchanged = Math.max(0, rows.size() - primaryAffected);

            AmundiImportResult result = new AmundiImportResult(
                    validation, mode, deleted, inserted, updated, unchanged);
            writeAudit("ImportAmundiPerimeter", file, validation, mode, userEmail, clientIp,
                    startedAt, 0,
                    "Import completed; deleted=" + deleted + ", inserted=" + inserted
                            + ", updated=" + updated + ", unchanged=" + unchanged);
            return result;
        } catch (RuntimeException exception) {
            writeFailureAudit("ImportAmundiPerimeter", file, mode, userEmail, clientIp,
                    startedAt, exception);
            throw exception;
        }
    }

    private CsvParseResult parseAndValidateFunds(UploadedFile file, AmundiDateFormat dateFormat) {
        Map<String, Integer> lengths = amundiPerimeterDao.findLiveColumnLengths();
        CsvParseResult parsed = csvParser.parse(file, dateFormat, lengths);

        Set<String> requestedCodes = parsed.validRows().stream()
                .map(row -> row.value().fundName())
                .collect(HashSet::new, Set::add, Set::addAll);
        Set<String> existingCodes = amundiPerimeterDao.findExistingFundCodes(requestedCodes);

        List<ParsedAmundiRow> stillValid = new ArrayList<>();
        List<AmundiImportRowError> errors = new ArrayList<>(parsed.errors());
        for (ParsedAmundiRow row : parsed.validRows()) {
            if (existingCodes.contains(row.value().fundName())) {
                stillValid.add(row);
            } else {
                errors.add(new AmundiImportRowError(
                        row.rowNumber(),
                        "Code Comptable",
                        row.value().fundName(),
                        "No active fund exists in OWB_DWH.REF_FUND"));
            }
        }

        return new CsvParseResult(
                parsed.checksumSha256(),
                parsed.totalRows(),
                stillValid,
                errors,
                parsed.duplicateRows());
    }

    private AmundiImportValidationResult toValidation(UploadedFile file, CsvParseResult parsed) {
        int invalidRows = (int) parsed.errors().stream()
                .map(AmundiImportRowError::rowNumber)
                .distinct()
                .count();
        return new AmundiImportValidationResult(
                TEMPLATE_NAME,
                file.originalFilename(),
                parsed.checksumSha256(),
                parsed.totalRows(),
                parsed.validRows().size(),
                invalidRows,
                parsed.duplicateRows(),
                parsed.errors());
    }

    private void writeFailureAudit(
            String function,
            UploadedFile file,
            AmundiImportMode mode,
            String userEmail,
            String clientIp,
            long startedAt,
            RuntimeException exception) {
        AmundiImportValidationResult empty = new AmundiImportValidationResult(
                TEMPLATE_NAME, file.originalFilename(), "unavailable", 0, 0, 0, 0, List.of());
        writeAudit(function, file, empty, mode, userEmail, clientIp, startedAt, 1,
                "Failed: " + abbreviate(exception.getMessage(), 500));
    }

    private void writeAudit(
            String function,
            UploadedFile file,
            AmundiImportValidationResult validation,
            AmundiImportMode mode,
            String userEmail,
            String clientIp,
            long startedAt,
            int status,
            String message) {
        try {
            BigDecimal seconds = BigDecimal.valueOf((System.nanoTime() - startedAt) / 1_000_000_000d)
                    .setScale(3, RoundingMode.HALF_UP);
            Audit audit = new Audit(
                    abbreviate(clientIp, 100),
                    LocalDate.now(),
                    LocalDate.now(),
                    "referential/importer-un-fichier",
                    abbreviate(userEmail, 200),
                    "Referential",
                    function,
                    abbreviate(message, 1000),
                    "template=" + TEMPLATE_NAME,
                    "file=" + abbreviate(file.originalFilename(), 300),
                    "checksum=" + validation.checksumSha256(),
                    "mode=" + (mode == null ? "VALIDATE" : mode),
                    "total=" + validation.totalRows() + ", valid=" + validation.validRows()
                            + ", invalid=" + validation.invalidRows(),
                    seconds,
                    status,
                    0,
                    "QXP");
            auditInsertTraceDao.insertTrace(audit);
        } catch (RuntimeException auditException) {
            log.error("AMUNDI audit failed for function={} user={}", function, userEmail, auditException);
        }
    }

    private String abbreviate(String value, int maximum) {
        String safe = value == null ? "" : value;
        return safe.length() <= maximum ? safe : safe.substring(0, maximum - 3) + "...";
    }
}
```

### 12.9 `service/AmundiPerimeterImportSerInterface.java`

```java
package com.socgen.sgs.api.quark.backend.api.service;

import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiDateFormat;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportMode;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportTemplateConfiguration;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportValidationResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.UploadedFile;

public interface AmundiPerimeterImportSerInterface {

    AmundiImportTemplateConfiguration configuration();

    AmundiImportValidationResult validate(
            UploadedFile file,
            AmundiDateFormat dateFormat,
            String userEmail,
            String clientIp);

    AmundiImportResult importFile(
            UploadedFile file,
            AmundiDateFormat dateFormat,
            AmundiImportMode mode,
            String expectedChecksum,
            String userEmail,
            String clientIp);
}
```

### 12.10 `service/Impl/AmundiPerimeterImportService.java`

```java
package com.socgen.sgs.api.quark.backend.api.service.Impl;

import com.socgen.sgs.api.quark.backend.api.Business.AmundiPerimeterImportBusiness;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiDateFormat;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportMode;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportTemplateConfiguration;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportValidationResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.UploadedFile;
import com.socgen.sgs.api.quark.backend.api.service.AmundiPerimeterImportSerInterface;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class AmundiPerimeterImportService implements AmundiPerimeterImportSerInterface {

    private final AmundiPerimeterImportBusiness business;

    @Override
    public AmundiImportTemplateConfiguration configuration() {
        return business.configuration();
    }

    @Override
    public AmundiImportValidationResult validate(
            UploadedFile file,
            AmundiDateFormat dateFormat,
            String userEmail,
            String clientIp) {
        return business.validate(file, dateFormat, userEmail, clientIp);
    }

    @Override
    public AmundiImportResult importFile(
            UploadedFile file,
            AmundiDateFormat dateFormat,
            AmundiImportMode mode,
            String expectedChecksum,
            String userEmail,
            String clientIp) {
        return business.importFile(file, dateFormat, mode, expectedChecksum, userEmail, clientIp);
    }
}
```

### 12.11 `infra/api/v1/ReferentialController.java`

```java
package com.socgen.sgs.api.quark.backend.api.infra.api.v1;

import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiDateFormat;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportMode;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportTemplateConfiguration;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiImportValidationResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.UploadedFile;
import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.ImportRejectedException;
import com.socgen.sgs.api.quark.backend.api.service.AmundiPerimeterImportSerInterface;
import com.socgen.sgs.api.quark.backend.api.service.IAuthenticationService;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.List;

import static org.springframework.http.MediaType.MULTIPART_FORM_DATA_VALUE;

@RestController
@RequestMapping("/api/v1/referential")
@PreAuthorize("hasAuthority('SCOPE_api.quark.v1')")
@RequiredArgsConstructor
public class ReferentialController {

    private static final String EXTERNAL_API = "external_api";

    private final AmundiPerimeterImportSerInterface importService;
    private final IAuthenticationService authenticationService;

    @GetMapping("/import-templates")
    public ResponseEntity<List<AmundiImportTemplateConfiguration>> importTemplates() {
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(List.of(importService.configuration()));
    }

    @PostMapping(value = "/amundi-perimeter/validate", consumes = MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<AmundiImportValidationResult> validate(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "dateFormat", defaultValue = "DD_MM_YYYY")
            AmundiDateFormat dateFormat,
            HttpServletRequest request) {

        AmundiImportValidationResult result = importService.validate(
                uploadedFile(file), dateFormat, currentHumanEmail(), clientIp(request));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(result);
    }

    @PostMapping(value = "/amundi-perimeter/import", consumes = MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<AmundiImportResult> importFile(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "dateFormat", defaultValue = "DD_MM_YYYY")
            AmundiDateFormat dateFormat,
            @RequestParam(value = "mode", defaultValue = "DELETE_AND_INSERT")
            AmundiImportMode mode,
            @RequestParam("expectedChecksum") String expectedChecksum,
            HttpServletRequest request) {

        AmundiImportResult result = importService.importFile(
                uploadedFile(file), dateFormat, mode, expectedChecksum,
                currentHumanEmail(), clientIp(request));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(result);
    }

    private UploadedFile uploadedFile(MultipartFile file) {
        try {
            return new UploadedFile(file.getOriginalFilename(), file.getBytes());
        } catch (IOException exception) {
            throw new ImportRejectedException("Unable to read the uploaded CSV file", exception);
        }
    }

    private String currentHumanEmail() {
        String email = authenticationService.getCurrentUserEmailId()
                .filter(value -> !value.isBlank())
                .orElseThrow(() -> new AccessDeniedException(
                        "The authenticated SGIAM/SG Connect token has no mail claim"));
        if (EXTERNAL_API.equalsIgnoreCase(email)) {
            throw new AccessDeniedException(
                    "A human SGIAM/SG Connect identity is required for an interactive import");
        }
        return email;
    }

    private String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        String realIp = request.getHeader("X-Real-IP");
        return realIp == null || realIp.isBlank() ? request.getRemoteAddr() : realIp.trim();
    }
}
```

### 12.12 `infra/dao/DocumentDownloadDao.java`

```java
package com.socgen.sgs.api.quark.backend.api.infra.dao;

import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.AmundiFilenameMatch;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.DocumentFormat;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.ReportNamingContext;

import java.util.List;
import java.util.Optional;

public interface DocumentDownloadDao {

    Optional<ReportNamingContext> findNamingContext(long idSuivi);

    List<AmundiFilenameMatch> findAmundiMatches(
            ReportNamingContext context,
            String perimeterReportType);

    Optional<byte[]> findContent(long idSuivi, DocumentFormat format);

    void markVisited(long idSuivi, DocumentFormat format);
}
```

### 12.13 `infra/dao/Impl/SimpleJDBCDocumentDownload.java`

```java
package com.socgen.sgs.api.quark.backend.api.infra.dao.Impl;

import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.FeatureConfigurationException;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.AmundiFilenameMatch;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.DocumentFormat;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.ReportNamingContext;
import com.socgen.sgs.api.quark.backend.api.infra.dao.DocumentDownloadDao;
import oracle.jdbc.internal.OracleTypes;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.SqlOutParameter;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.Date;
import java.sql.Types;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Repository
public class SimpleJDBCDocumentDownload implements DocumentDownloadDao {

    private static final String NAMING_CONTEXT_SQL = """
            SELECT DISTINCT
                s.ID_SUIVI,
                s.ID_FND_CODE,
                s.ID_UNIT_CODE,
                s.ID_TYPE_RAPPORT,
                s.ID_STATUT_SUIVI,
                NVL(TO_DATE(sp.VALEUR, 'MM/DD/YYYY HH24:MI:SS'), s.DATE_ECHEANCE) AS REPORT_DATE,
                NVL(rf.FND_LNG_DESCRIPTION, NVL(qs.NOM, s.ID_FND_CODE)) AS FUND_NAME,
                rf.FND_CURRENCY,
                UPPER(ld.VALEUR_LANGUE) AS REPORT_LANGUAGE,
                CASE WHEN rf.ID_FND_CODE IS NULL THEN 0 ELSE 1 END AS FUND_BASED_SUIVI
            FROM QXP_SUIVI s
            LEFT JOIN OWB_DWH.REF_FUND rf
              ON rf.ID_FND_CODE = s.ID_FND_CODE
             AND rf.FND_END_VALIDITY = TO_DATE('31/12/2199', 'DD/MM/YYYY')
            LEFT JOIN QXP_STRUCTURE qs
              ON qs.ID_STRUCTURE = s.ID_FND_CODE
            LEFT JOIN QXP_REF_LANGUE_DOCUMENT ld
              ON ld.ID_LANGUE_DOCUMENT = s.ID_LANGUE
            LEFT JOIN QXP_ASSO_SUIVI_PARAMETRES sp
              ON sp.ID_SUIVI = s.ID_SUIVI
             AND sp.ID_PARAMETRE = 2
            WHERE s.ID_SUIVI = ?
            """;

    private static final String AMUNDI_MATCH_SQL = """
            SELECT ap.REPORT_DATE, ap.REPORT_LANGUAGE, ap.CODE_PARAPLUIE
            FROM QXP_AMUNDI_PERIMETER ap
            WHERE ap.FUND_NAME = :fundCode
              AND ap.REPORT_TYPE = :reportType
              AND ap.REPORT_DATE >= :monthStart
              AND ap.REPORT_DATE < :nextMonth
              AND UPPER(TRIM(ap.REPORT_LANGUAGE)) = :language
            """;

    private final JdbcTemplate jdbcTemplate;
    private final NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    private final SimpleJdbcCall getContentCall;
    private final SimpleJdbcCall updateVisitedCall;

    public SimpleJDBCDocumentDownload(DataSource dataSource) {
        this.jdbcTemplate = new JdbcTemplate(dataSource);
        this.namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(dataSource);
        this.getContentCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_SUIVI")
                .withFunctionName("GetContenuDocument")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlOutParameter(
                                "RETURN_VALUE",
                                OracleTypes.CURSOR,
                                (resultSet, rowNumber) -> resultSet.getBytes("CONTENU")),
                        new SqlParameter("p_idSuivi", Types.NUMERIC),
                        new SqlParameter("p_idTypeDocument", Types.NUMERIC));
        this.updateVisitedCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_SUIVI")
                .withProcedureName("UpdateStatutDocument")
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlParameter("p_idSuivi", Types.NUMERIC),
                        new SqlParameter("p_idTypeDocument", Types.NUMERIC));
    }

    @Override
    public Optional<ReportNamingContext> findNamingContext(long idSuivi) {
        List<ReportNamingContext> rows = jdbcTemplate.query(
                NAMING_CONTEXT_SQL,
                (resultSet, rowNumber) -> new ReportNamingContext(
                        resultSet.getLong("ID_SUIVI"),
                        resultSet.getString("ID_FND_CODE"),
                        resultSet.getString("ID_UNIT_CODE"),
                        resultSet.getInt("ID_TYPE_RAPPORT"),
                        resultSet.getInt("ID_STATUT_SUIVI"),
                        toLocalDate(resultSet.getDate("REPORT_DATE")),
                        resultSet.getString("FUND_NAME"),
                        resultSet.getString("FND_CURRENCY"),
                        resultSet.getString("REPORT_LANGUAGE"),
                        resultSet.getInt("FUND_BASED_SUIVI") == 1),
                idSuivi);

        if (rows.size() > 1) {
            throw new FeatureConfigurationException(
                    "More than one naming context was returned for idSuivi=" + idSuivi);
        }
        return rows.stream().findFirst();
    }

    @Override
    public List<AmundiFilenameMatch> findAmundiMatches(
            ReportNamingContext context,
            String perimeterReportType) {

        LocalDate monthStart = context.reportDate().withDayOfMonth(1);
        MapSqlParameterSource parameters = new MapSqlParameterSource()
                .addValue("fundCode", context.fundCode())
                .addValue("reportType", perimeterReportType)
                .addValue("monthStart", Date.valueOf(monthStart))
                .addValue("nextMonth", Date.valueOf(monthStart.plusMonths(1)))
                .addValue("language", context.language());

        return namedParameterJdbcTemplate.query(
                AMUNDI_MATCH_SQL,
                parameters,
                (resultSet, rowNumber) -> new AmundiFilenameMatch(
                        toLocalDate(resultSet.getDate("REPORT_DATE")),
                        resultSet.getString("REPORT_LANGUAGE"),
                        resultSet.getString("CODE_PARAPLUIE")));
    }

    @Override
    @SuppressWarnings("unchecked")
    public Optional<byte[]> findContent(long idSuivi, DocumentFormat format) {
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("p_idSuivi", idSuivi);
        parameters.put("p_idTypeDocument", format.oracleValue());

        Map<String, Object> result = getContentCall.execute(parameters);
        List<byte[]> rows = (List<byte[]>) result.get("RETURN_VALUE");
        if (rows == null || rows.isEmpty() || rows.getFirst() == null) {
            return Optional.empty();
        }
        return Optional.of(rows.getFirst());
    }

    @Override
    public void markVisited(long idSuivi, DocumentFormat format) {
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("p_idSuivi", idSuivi);
        parameters.put("p_idTypeDocument", format.oracleValue());
        updateVisitedCall.execute(parameters);
    }

    private LocalDate toLocalDate(java.sql.Date value) {
        return value == null ? null : value.toLocalDate();
    }
}
```

### 12.14 `Business/ReportFilenameBusiness.java`

```java
package com.socgen.sgs.api.quark.backend.api.Business;

import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.FeatureConfigurationException;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.AmundiFilenameMatch;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.DocumentFormat;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.ReportNamingContext;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;

@Slf4j
@Component
public class ReportFilenameBusiness {

    private static final int ANNUAL_REPORT = 1;
    private static final int PLAQUETTE = 2;
    private static final int PROSPECTUS = 3;
    private static final int COMPARTMENT_REPORT = 4;
    private static final int DICI = 5;
    private static final int CERTIFIED_CAC_STATUS = 10;

    private static final DateTimeFormatter LEGACY_DATE = DateTimeFormatter.ofPattern("dd-MM-uuuu");
    private static final DateTimeFormatter AMUNDI_DATE = DateTimeFormatter.BASIC_ISO_DATE;

    private final boolean amundiNamingEnabled;

    public ReportFilenameBusiness(
            @Value("${quark.features.amundi-report-filename.enabled:true}")
            boolean amundiNamingEnabled) {
        this.amundiNamingEnabled = amundiNamingEnabled;
    }

    public boolean isAmundiCandidate(ReportNamingContext context) {
        return amundiNamingEnabled
                && context.fundBasedSuivi()
                && context.reportDate() != null
                && context.language() != null
                && (context.reportTypeId() == ANNUAL_REPORT
                    || context.reportTypeId() == PLAQUETTE);
    }

    public String perimeterReportType(ReportNamingContext context) {
        return switch (context.reportTypeId()) {
            case ANNUAL_REPORT -> "RA";
            case PLAQUETTE -> "IS";
            default -> throw new IllegalArgumentException("Report is not an AMUNDI filename candidate");
        };
    }

    public String buildFilename(
            ReportNamingContext context,
            List<AmundiFilenameMatch> matches,
            DocumentFormat format) {

        if (isAmundiCandidate(context)) {
            if (matches.size() == 1 && isUsableAmundiMatch(context, matches.getFirst())) {
                return buildAmundiFilename(context, matches.getFirst(), format);
            }
            if (matches.size() > 1) {
                log.warn("AMUNDI filename fallback: duplicate matches for idSuivi={}", context.idSuivi());
            } else if (matches.size() == 1) {
                log.warn("AMUNDI filename fallback: unusable match for idSuivi={}", context.idSuivi());
            }
        }
        return buildLegacyFilename(context, format);
    }

    private boolean isUsableAmundiMatch(
            ReportNamingContext context,
            AmundiFilenameMatch match) {
        return match.reportDate() != null
                && isTwoLetterLanguage(match.reportLanguage())
                && hasText(context.fundName())
                && hasText(context.currency());
    }

    private String buildAmundiFilename(
            ReportNamingContext context,
            AmundiFilenameMatch match,
            DocumentFormat format) {

        String reportName = context.reportTypeId() == ANNUAL_REPORT
                ? "AnnualReport"
                : "PeriodicReport";
        String codeParapluie = match.codeParapluie() == null
                ? ""
                : sanitizeAmundiSegment(match.codeParapluie());

        if (codeParapluie.isEmpty()) {
            log.warn("AMUNDI filename contains an empty Code-Parapluie for idSuivi={}", context.idSuivi());
        }

        return reportName
                + "_" + sanitizeAmundiSegment(context.fundName())
                + "_" + codeParapluie
                + "_" + AMUNDI_DATE.format(match.reportDate())
                + "_FRA_" + match.reportLanguage().trim().toUpperCase(Locale.ROOT)
                + "_" + sanitizeAmundiSegment(context.currency().toUpperCase(Locale.ROOT))
                + "." + format.extension();
    }

    private String buildLegacyFilename(ReportNamingContext context, DocumentFormat format) {
        if (!hasText(context.fundCode()) || !hasText(context.fundName()) || context.reportDate() == null) {
            throw new FeatureConfigurationException(
                    "Required normal filename data is missing for idSuivi=" + context.idSuivi());
        }

        String separator = " - ";
        StringBuilder filename = new StringBuilder(sanitizeLegacyText(context.fundCode()));
        if (hasText(context.unitCode())) {
            filename.append(separator).append(sanitizeLegacyText(context.unitCode()));
        }
        filename.append(separator)
                .append(sanitizeLegacyText(context.fundName()))
                .append(separator)
                .append(LEGACY_DATE.format(context.reportDate()))
                .append(separator)
                .append(legacyReportCode(context.reportTypeId()));

        if (usesLanguage(context.reportTypeId())) {
            if (!hasText(context.language())) {
                throw new FeatureConfigurationException(
                        "Report language is missing for idSuivi=" + context.idSuivi());
            }
            filename.append(separator).append(sanitizeLegacyText(context.language()));
        }
        if (context.statusId() == CERTIFIED_CAC_STATUS) {
            filename.append(separator).append("C");
        }
        filename.append('.').append(format.extension());
        return filename.toString();
    }

    private String legacyReportCode(int reportTypeId) {
        return switch (reportTypeId) {
            case ANNUAL_REPORT -> "RA";
            case PLAQUETTE -> "IP";
            case PROSPECTUS -> "PB";
            case COMPARTMENT_REPORT -> "RC";
            case DICI -> "DICI";
            default -> throw new FeatureConfigurationException(
                    "Unsupported report type id=" + reportTypeId);
        };
    }

    private boolean usesLanguage(int reportTypeId) {
        return reportTypeId == ANNUAL_REPORT
                || reportTypeId == PLAQUETTE
                || reportTypeId == DICI;
    }

    private boolean isTwoLetterLanguage(String value) {
        return value != null && value.trim().toUpperCase(Locale.ROOT).matches("[A-Z]{2}");
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    private String sanitizeLegacyText(String value) {
        return value.trim()
                .replace('/', '-')
                .replace('\\', '-')
                .replace('\r', ' ')
                .replace('\n', ' ');
    }

    private String sanitizeAmundiSegment(String value) {
        return value.trim()
                .replaceAll("[\\p{Cntrl}\\\\/:*?\"<>|]", "-")
                .replaceAll("[\\p{Z}\\s]+", "-")
                .replaceAll("-+", "-")
                .replaceAll("^-|-$", "");
    }
}
```

### 12.15 `Business/DocumentDownloadBusiness.java`

```java
package com.socgen.sgs.api.quark.backend.api.Business;

import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.ResourceNotFoundException;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.AmundiFilenameMatch;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.DocumentFormat;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.ReportDownload;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.ReportNamingContext;
import com.socgen.sgs.api.quark.backend.api.infra.dao.DocumentDownloadDao;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Component
@RequiredArgsConstructor
public class DocumentDownloadBusiness {

    private final DocumentDownloadDao documentDownloadDao;
    private final ReportFilenameBusiness reportFilenameBusiness;

    @Transactional
    public ReportDownload download(long idSuivi, String requestedFormat) {
        DocumentFormat format = DocumentFormat.fromPath(requestedFormat);
        ReportNamingContext context = documentDownloadDao.findNamingContext(idSuivi)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "No suivi exists for idSuivi=" + idSuivi));

        List<AmundiFilenameMatch> matches = List.of();
        if (reportFilenameBusiness.isAmundiCandidate(context)) {
            matches = documentDownloadDao.findAmundiMatches(
                    context, reportFilenameBusiness.perimeterReportType(context));
        }

        byte[] content = documentDownloadDao.findContent(idSuivi, format)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "No " + format.extension() + " document exists for idSuivi=" + idSuivi));
        String filename = reportFilenameBusiness.buildFilename(context, matches, format);

        documentDownloadDao.markVisited(idSuivi, format);
        return new ReportDownload(content, filename, format.mediaType());
    }
}
```

### 12.16 Download service interface and implementation

`service/DocumentDownloadSerInterface.java`

```java
package com.socgen.sgs.api.quark.backend.api.service;

import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.ReportDownload;

public interface DocumentDownloadSerInterface {
    ReportDownload download(long idSuivi, String requestedFormat);
}
```

`service/Impl/DocumentDownloadService.java`

```java
package com.socgen.sgs.api.quark.backend.api.service.Impl;

import com.socgen.sgs.api.quark.backend.api.Business.DocumentDownloadBusiness;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.ReportDownload;
import com.socgen.sgs.api.quark.backend.api.service.DocumentDownloadSerInterface;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class DocumentDownloadService implements DocumentDownloadSerInterface {

    private final DocumentDownloadBusiness business;

    @Override
    public ReportDownload download(long idSuivi, String requestedFormat) {
        return business.download(idSuivi, requestedFormat);
    }
}
```

### 12.17 Download controller and scoped exception handler

`infra/api/v1/TableauDeBordDocumentController.java`

```java
package com.socgen.sgs.api.quark.backend.api.infra.api.v1;

import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.ReportDownload;
import com.socgen.sgs.api.quark.backend.api.service.DocumentDownloadSerInterface;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;

@RestController
@RequestMapping("/api/v1/tableau-de-bord")
@PreAuthorize("hasAuthority('SCOPE_api.quark.v1')")
@RequiredArgsConstructor
public class TableauDeBordDocumentController {

    private final DocumentDownloadSerInterface downloadService;

    @GetMapping("/suivis/{idSuivi}/documents/{format}")
    public ResponseEntity<byte[]> download(
            @PathVariable long idSuivi,
            @PathVariable String format) {

        ReportDownload document = downloadService.download(idSuivi, format);
        HttpHeaders headers = new HttpHeaders();
        headers.setContentDisposition(ContentDisposition.attachment()
                .filename(document.filename(), StandardCharsets.UTF_8)
                .build());
        headers.setCacheControl(CacheControl.noStore().mustRevalidate());
        headers.setContentType(MediaType.parseMediaType(document.mediaType()));
        headers.setContentLength(document.content().length);
        headers.set("X-Content-Type-Options", "nosniff");

        return ResponseEntity.ok().headers(headers).body(document.content());
    }
}
```

`infra/api/exception/AmundiFeatureExceptionHandler.java`

```java
package com.socgen.sgs.api.quark.backend.api.infra.api.exception;

import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.FeatureConfigurationException;
import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.ImportRejectedException;
import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.ResourceNotFoundException;
import com.socgen.sgs.api.quark.backend.api.infra.api.v1.ReferentialController;
import com.socgen.sgs.api.quark.backend.api.infra.api.v1.TableauDeBordDocumentController;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@Order(Ordered.HIGHEST_PRECEDENCE)
@RestControllerAdvice(assignableTypes = {
        ReferentialController.class,
        TableauDeBordDocumentController.class
})
public class AmundiFeatureExceptionHandler {

    @ExceptionHandler(ImportRejectedException.class)
    public ResponseEntity<ProblemDetail> importRejected(ImportRejectedException exception) {
        return problem(HttpStatus.UNPROCESSABLE_ENTITY, "AMUNDI import rejected", exception.getMessage());
    }

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ProblemDetail> notFound(ResourceNotFoundException exception) {
        return problem(HttpStatus.NOT_FOUND, "Resource not found", exception.getMessage());
    }

    @ExceptionHandler(FeatureConfigurationException.class)
    public ResponseEntity<ProblemDetail> configuration(FeatureConfigurationException exception) {
        return problem(HttpStatus.SERVICE_UNAVAILABLE, "Feature configuration error", exception.getMessage());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ProblemDetail> badRequest(IllegalArgumentException exception) {
        return problem(HttpStatus.BAD_REQUEST, "Invalid request", exception.getMessage());
    }

    private ResponseEntity<ProblemDetail> problem(HttpStatus status, String title, String detail) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail == null ? title : detail);
        problem.setTitle(title);
        return ResponseEntity.status(status).body(problem);
    }
}
```

### 12.18 Focused unit tests

Create these two test files. They cover the highest-risk behavior without needing Oracle.

`src/test/java/com/socgen/sgs/api/quark/backend/api/Business/AmundiCsvParserTest.java`

```java
package com.socgen.sgs.api.quark.backend.api.Business;

import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.AmundiDateFormat;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.CsvParseResult;
import com.socgen.sgs.api.quark.backend.api.domain.AmundiImportModels.UploadedFile;
import com.socgen.sgs.api.quark.backend.api.domain.FeatureExceptions.ImportRejectedException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AmundiCsvParserTest {

    private static final String HEADER = "\"Nom \"\"Fonds\"\"\",Code BWR,"
            + "\"Code \"\"Decalog\"\"\",Code Comptable,Type de rapport,Date de clotûre,"
            + "Langues,Type de fonds,Normes Européennes,Méthode calcul d'engagement,Code Parapluie";

    private AmundiCsvParser parser;

    @BeforeEach
    void setUp() {
        parser = new AmundiCsvParser(10 * 1024 * 1024L);
    }

    @Test
    void parsesUtf8BomQuotedCsvAndTheEleventhColumn() {
        String csv = "\uFEFF" + HEADER + "\r\n"
                + "\"SG ACTIONS, ETATS UNIS\",2987,S110010,310127,IS,31/03/2025,"
                + "FR,FCPE,FIA,\"Méthode de l'engagement\",UM11182\r\n";

        CsvParseResult result = parser.parse(
                upload(csv), AmundiDateFormat.DD_MM_YYYY, liveLengths());

        assertEquals(1, result.totalRows());
        assertEquals(1, result.validRows().size());
        assertTrue(result.errors().isEmpty());
        assertEquals("SG ACTIONS, ETATS UNIS", result.validRows().getFirst().value().fundLabel());
        assertEquals("UM11182", result.validRows().getFirst().value().codeParapluie());
    }

    @Test
    void acceptsAnEmptyCodeParapluie() {
        String csv = HEADER + "\n"
                + "ARCANCIA,2987,S110191,310127,RA,31/12/2024,FR,FCPE,FIA,,\n";

        CsvParseResult result = parser.parse(
                upload(csv), AmundiDateFormat.DD_MM_YYYY, liveLengths());

        assertEquals(1, result.validRows().size());
        assertNull(result.validRows().getFirst().value().codeParapluie());
        assertNull(result.validRows().getFirst().value().engagementMethod());
    }

    @Test
    void rejectsTheSecondOccurrenceOfTheLegacyBusinessKey() {
        String row = "ARCANCIA,2987,S110191,310127,RA,31/12/2024,FR,FCPE,FIA,,UM14174\n";
        CsvParseResult result = parser.parse(
                upload(HEADER + "\n" + row + row),
                AmundiDateFormat.DD_MM_YYYY,
                liveLengths());

        assertEquals(2, result.totalRows());
        assertEquals(1, result.validRows().size());
        assertEquals(1, result.duplicateRows());
        assertEquals(1, result.errors().size());
    }

    @Test
    void requiresCodeParapluieAsTheEleventhHeader() {
        String csv = HEADER.replace(",Code Parapluie", "") + "\n";
        assertThrows(ImportRejectedException.class, () -> parser.parse(
                upload(csv), AmundiDateFormat.DD_MM_YYYY, liveLengths()));
    }

    private UploadedFile upload(String csv) {
        return new UploadedFile("amundi.csv", csv.getBytes(StandardCharsets.UTF_8));
    }

    private Map<String, Integer> liveLengths() {
        Map<String, Integer> lengths = new HashMap<>();
        lengths.put("FUND_LABEL", 100);
        lengths.put("ID_FUND_BWR", 50);
        lengths.put("DECALOG", 50);
        lengths.put("FUND_NAME", 50);
        lengths.put("REPORT_TYPE", 2);
        lengths.put("REPORT_DATE", null);
        lengths.put("REPORT_LANGUAGE", 2);
        lengths.put("LEGAL_FORM", 50);
        lengths.put("EUROPEAN_NORM", 50);
        lengths.put("ENGAGEMENT_METHOD", 50);
        lengths.put("CODE_PARAPLUIE", 50);
        return lengths;
    }
}
```

`src/test/java/com/socgen/sgs/api/quark/backend/api/Business/ReportFilenameBusinessTest.java`

```java
package com.socgen.sgs.api.quark.backend.api.Business;

import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.AmundiFilenameMatch;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.DocumentFormat;
import com.socgen.sgs.api.quark.backend.api.domain.ReportDownloadModels.ReportNamingContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ReportFilenameBusinessTest {

    private ReportFilenameBusiness business;

    @BeforeEach
    void setUp() {
        business = new ReportFilenameBusiness(true);
    }

    @Test
    void createsAnnualReportAmundiFilename() {
        ReportNamingContext context = context(1, 2, "SG ACTIONS ETATS UNIS", "EUR", "FR");
        AmundiFilenameMatch match = new AmundiFilenameMatch(
                LocalDate.of(2025, 3, 31), "FR", "UM11182");

        assertEquals(
                "AnnualReport_SG-ACTIONS-ETATS-UNIS_UM11182_20250331_FRA_FR_EUR.pdf",
                business.buildFilename(context, List.of(match), DocumentFormat.PDF));
    }

    @Test
    void createsPeriodicReportForPlaquetteAndKeepsRequestedExtension() {
        ReportNamingContext context = context(2, 2, "SG ACTIONS ETATS UNIS", "EUR", "FR");
        AmundiFilenameMatch match = new AmundiFilenameMatch(
                LocalDate.of(2025, 3, 31), "FR", "UM11182");

        assertEquals(
                "PeriodicReport_SG-ACTIONS-ETATS-UNIS_UM11182_20250331_FRA_FR_EUR.qxp",
                business.buildFilename(context, List.of(match), DocumentFormat.QXP));
    }

    @Test
    void keepsTheEmptySegmentWhenCodeParapluieIsNull() {
        ReportNamingContext context = context(1, 2, "ARCANCIA", "EUR", "FR");
        AmundiFilenameMatch match = new AmundiFilenameMatch(
                LocalDate.of(2024, 12, 31), "FR", null);

        assertEquals(
                "AnnualReport_ARCANCIA__20241231_FRA_FR_EUR.doc",
                business.buildFilename(context, List.of(match), DocumentFormat.DOC));
    }

    @Test
    void usesTheCommonNameWhenNoPerimeterRowMatches() {
        ReportNamingContext context = new ReportNamingContext(
                99L, "74078", null, 1, 2,
                LocalDate.of(2024, 12, 31),
                "PATRIMOINE REACTIF", "EUR", "FR", true);

        assertEquals(
                "74078 - PATRIMOINE REACTIF - 31-12-2024 - RA - FR.pdf",
                business.buildFilename(context, List.of(), DocumentFormat.PDF));
    }

    @Test
    void duplicateMatchFallsBackToTheCommonCertifiedName() {
        ReportNamingContext context = new ReportNamingContext(
                99L, "74078", null, 1, 10,
                LocalDate.of(2024, 12, 31),
                "PATRIMOINE REACTIF", "EUR", "FR", true);
        AmundiFilenameMatch match = new AmundiFilenameMatch(
                LocalDate.of(2024, 12, 31), "FR", "UM14174");

        assertEquals(
                "74078 - PATRIMOINE REACTIF - 31-12-2024 - RA - FR - C.pdf",
                business.buildFilename(context, List.of(match, match), DocumentFormat.PDF));
    }

    @Test
    void prospectusAlwaysUsesTheCommonRule() {
        ReportNamingContext context = context(3, 2, "ARCANCIA", "EUR", "FR");
        AmundiFilenameMatch match = new AmundiFilenameMatch(
                LocalDate.of(2024, 12, 31), "FR", "UM14174");

        assertEquals(
                "310127 - ARCANCIA - 31-03-2025 - PB.pdf",
                business.buildFilename(context, List.of(match), DocumentFormat.PDF));
    }

    private ReportNamingContext context(
            int reportType,
            int status,
            String fundName,
            String currency,
            String language) {
        return new ReportNamingContext(
                99L,
                "310127",
                null,
                reportType,
                status,
                LocalDate.of(2025, 3, 31),
                fundName,
                currency,
                language,
                true);
    }
}
```

## 13. Oracle deployment and verification

### 13.1 Pre-check and one-time change

Run the pre-check first in each environment:

```sql
SELECT column_name, data_type, char_length, nullable
FROM user_tab_columns
WHERE table_name = 'QXP_AMUNDI_PERIMETER'
  AND column_name = 'CODE_PARAPLUIE';
```

If the pre-check returns no row, run once:

```sql
ALTER TABLE QXP_AMUNDI_PERIMETER
ADD CODE_PARAPLUIE VARCHAR2(50 CHAR);
```

Verify the resulting table contract and unchanged primary key:

```sql
SELECT column_id, column_name, data_type, char_length, nullable
FROM user_tab_columns
WHERE table_name = 'QXP_AMUNDI_PERIMETER'
ORDER BY column_id;

SELECT cc.position, cc.column_name
FROM user_constraints c
JOIN user_cons_columns cc
  ON cc.owner = c.owner
 AND cc.constraint_name = c.constraint_name
WHERE c.table_name = 'QXP_AMUNDI_PERIMETER'
  AND c.constraint_type = 'P'
ORDER BY cc.position;
```

Expected primary-key columns remain exactly:

```text
FUND_NAME, REPORT_DATE, REPORT_LANGUAGE
```

Do not add `REPORT_TYPE` and do not make `CODE_PARAPLUIE` mandatory while .NET is running.

### 13.2 Rollback rule

Oracle commits DDL automatically. Before any real `CODE_PARAPLUIE` data exists, the technical rollback is:

```sql
ALTER TABLE QXP_AMUNDI_PERIMETER DROP COLUMN CODE_PARAPLUIE;
```

After any real data exists, do not drop the column. Disable the Java feature with:

```text
quark.features.amundi-report-filename.enabled=false
```

and roll back the Java deployment. The nullable column is harmless to .NET and preserves imported data.

### 13.3 Endpoint verification order

1. Start Java after the column exists.
2. Call `GET /api/v1/referential/import-templates`; confirm it returns only `IT_AMUNDI_PERIMETER`.
3. Add `Code Parapluie` as the eleventh header in a copy of the supplied CSV.
4. Call the validation endpoint and retain its `checksumSha256`.
5. Call the import endpoint with that exact file and checksum, initially in a development database.
6. Query representative rows:

```sql
SELECT fund_name,
       report_type,
       report_date,
       report_language,
       code_parapluie
FROM qxp_amundi_perimeter
WHERE fund_name IN ('310127')
ORDER BY report_date, report_language;
```

7. Download PDF, QXP, and DOC for one matching RA and one matching IS suivi.
8. Repeat with `CODE_PARAPLUIE = NULL`; confirm the deliberate double underscore.
9. Repeat with no match; confirm the common filename.
10. Run an old .NET import/download smoke test before UAT sign-off.

Example HTTP contracts:

```text
POST /api/v1/referential/amundi-perimeter/validate
Content-Type: multipart/form-data
parts: file=<csv>, dateFormat=DD_MM_YYYY

POST /api/v1/referential/amundi-perimeter/import
Content-Type: multipart/form-data
parts: file=<same csv>, dateFormat=DD_MM_YYYY,
       mode=DELETE_AND_INSERT, expectedChecksum=<validation checksum>

GET /api/v1/tableau-de-bord/suivis/{idSuivi}/documents/pdf
GET /api/v1/tableau-de-bord/suivis/{idSuivi}/documents/qxp
GET /api/v1/tableau-de-bord/suivis/{idSuivi}/documents/doc
```

## 14. Final implementation validation

This bundle is ready to implement with these boundaries:

- it is additive: all Java application files are new and `pom.xml` is unchanged;
- the only database structure change is the nullable eleventh column;
- .NET continues inserting its explicit ten columns and ignores the new column;
- the Java import is fixed to `IT_AMUNDI_PERIMETER` and cannot accept a request-provided table or column name;
- validation uses the live Oracle column widths, avoiding the stale checked-in `FUND_NAME` width;
- a replacement import is transactional, so an insert failure rolls back its preceding delete;
- SGIAM/SG Connect `mail` is used directly and `external_api` is rejected for this interactive audited action;
- the old document procedures and visited flags are reused without changing their signatures;
- AMUNDI naming is limited to RA and IS, applies equally to PDF/QXP/DOC, and never changes PB/RC/DICI;
- null Code-Parapluie deliberately produces an empty segment; a later Java import corrects the next download;
- absent, duplicate, or unusable AMUNDI matches produce the common filename, as confirmed;
- the feature flag provides a safe Java rollback while leaving the compatible nullable column in Oracle.

Local verification performed on this bundle: all 18 new production files and both test files were extracted from this Markdown and compiled with Java 21 against the locally cached project libraries. All 10 focused parser and filename tests passed. A Maven build and Oracle integration test could not be run on this machine because the repository has no Maven wrapper, `mvn` is not installed, and no database connection is available; run those two checks on the work laptop before merging.
