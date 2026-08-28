# EOS Quark — Report File Naming

## Purpose

This document explains the report names used when a document is downloaded from page 2 of the **Tableau de bord**.

The enhancement changes the file name only for AMUNDI Annual reports and Plaquettes. All other reports keep the current standard name.

The same naming rule applies to every available download format, including PDF, QXP and DOC.

## 1. Standard reports — no change

For a fund-level report, the current name remains:

```text
Fund code - Fund name - DD-MM-YYYY - Report code [ - Language ] [ - C].extension
```

Example:

```text
74078 - PATRIMOINE REACTIF - 31-12-2024 - RA - FR.pdf
```

For a share/part-level report, the share/part code is also included after the fund code.

The report codes remain:

| Report type | Code in the standard file name | Language included? |
|---|---:|---:|
| Annual report | RA | Yes |
| Plaquette | IP | Yes |
| Prospectus | PB | No |
| Compartiment report | RC | No |
| DICI | DICI | Yes |

`C` is added at the end when a standard report is marked as certified by the statutory auditor.

## 2. AMUNDI reports — previous behavior

Previously, the special AMUNDI name was:

```text
Report code_Fund name_YYYYMM_Language name_Currency_BWR code_xxx_Language ID_xxx.extension
```

For a Plaquette, the report code changed from the standard `IP` to `IS`.

The old file name used:

| Value | Previous source |
|---|---|
| Report code | Type of report selected in the Tableau de bord |
| Fund name | Main fund referential |
| Year and month | Date of the report in the Tableau de bord |
| Language name and language ID | Language of the report |
| Currency | Main fund referential |
| BWR code | AMUNDI perimeter file imported through **Référentiel > Importer un fichier en base** |
| Extension | Download selected by the user, such as PDF, QXP or DOC |

The imported fund label, Decalog code and perimeter language were not used in the previous AMUNDI file name.

## 3. AMUNDI reports — new behavior

The new special name applies only to:

- Annual report (`RA`), displayed as `AnnualReport`;
- Plaquette (`IS` in the AMUNDI perimeter), displayed as `PeriodicReport`.

The new name is:

```text
Report type_Fund name_Code Parapluie_YYYYMMDD_FRA_Language_Currency.extension
```

Examples:

```text
AnnualReport_ARCANCIA_UM14174_20241231_FRA_FR_EUR.pdf
PeriodicReport_SG-ACTIONS-ETATS-UNIS_UM11182_20250331_FRA_FR_EUR.pdf
```

Spaces in the fund name are changed to hyphens so that the name is safe to download and share.

### Where the new values come from

| Part of the file name | New source |
|---|---|
| `AnnualReport` or `PeriodicReport` | Type of report being downloaded |
| Fund name | Main fund referential; this is the same fund name source used previously |
| Code Parapluie | New **Code Parapluie** column in the AMUNDI perimeter CSV file |
| `YYYYMMDD` | **Date de clôture** in the matching AMUNDI perimeter row |
| Country | Always `FRA` for this enhancement |
| Language | **Langues** in the matching AMUNDI perimeter row, using a two-letter code such as `FR` |
| Currency | Main fund referential; this is the same currency source used previously |
| Extension | Download selected by the user, such as PDF, QXP or DOC |

The CSV field **Code Comptable** is used to find the correct fund. It is not displayed in the new AMUNDI file name. The CSV fund label and Decalog code are also not displayed in the new name.

## 4. How EOS Quark decides that the AMUNDI name must be used

EOS Quark does not check whether the fund name contains “AMUNDI” and does not check the management-company name.

The system checks the information imported with the template **IT_AMUNDI_PERIMETER**. The new AMUNDI name is used only when all the following conditions are met:

1. The document is an Annual report or a Plaquette.
2. The report's fund code matches **Code Comptable** in the imported AMUNDI perimeter.
3. The report type matches: `RA` for an Annual report or `IS` for a Plaquette.
4. The month and year of the report match the month and year of **Date de clôture** in the imported perimeter.
5. The report language matches **Langues** in the imported perimeter.
6. Exactly one imported perimeter row matches the report.

### Difference from the previous check

| Previous check | New check |
|---|---|
| Used a matching AMUNDI perimeter row with a BWR code as the AMUNDI indicator | Requires exactly one usable matching AMUNDI perimeter row; Code Parapluie may still be blank |
| Compared fund code, report type, and report month/year | Also compares the report language |
| Could identify the other legacy report types in the perimeter | Special naming is limited to Annual reports and Plaquettes |

## 5. What happens when no AMUNDI match is found

The document is still downloaded. EOS Quark uses the unchanged standard file name when:

- the report is not an Annual report or Plaquette;
- no AMUNDI perimeter row matches;
- more than one row matches;
- the matched information cannot be used to create the special name.

If exactly one row matches but **Code Parapluie** is empty, the AMUNDI format is still used with an empty section:

```text
AnnualReport_ARCANCIA__20241231_FRA_FR_EUR.pdf
```

The user can then import a corrected CSV containing **Code Parapluie** and download the document again. The next download uses the corrected value.

## 6. Import file used for this enhancement

Only the template **IT_AMUNDI_PERIMETER** is included in this enhancement.

Production users upload a comma-separated CSV file through:

```text
Référentiel > Importer un fichier en base
```

The CSV contains its column headings, and **Code Parapluie** is the eleventh column. The import accepts only Annual (`RA`) and Plaquette (`IS`) perimeter rows for this enhancement.

Adding the new Code Parapluie information does not stop the existing application from operating during the transition to the new application.

## 7. Summary for production users

- Standard report names do not change.
- Only matching AMUNDI Annual reports and Plaquettes receive the new name.
- AMUNDI identification comes from the imported perimeter, not from the fund or management-company name.
- A missing or unclear AMUNDI match falls back to the standard name and does not prevent download.
- A blank Code Parapluie produces an AMUNDI name with an empty section until a corrected CSV is imported.
- PDF, QXP and DOC downloads follow the same naming decision.
