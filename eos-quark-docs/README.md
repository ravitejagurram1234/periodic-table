# EOS Quark — Documentation

My working notes for the EOS Quark .NET → Java engine port.
**36 documents**, markdown only, no source code.

> **Ground rule:** the original .NET code plus `ora.txt` are the source of truth.
> These notes record analysis and proposed changes — verify against the code before acting.

## Index

### Start here <sub>&nbsp;3 docs</sub>

Current state of the work. `KT_Tracking` is the live session log; `Consolidated_Changes` is the post-stabilization change log; `Deferred_Considerations` is what was knowingly postponed.

| Document | Topic |
|---|---|
| [EOS_Quark_Consolidated_Changes.md](01-start-here/EOS_Quark_Consolidated_Changes.md) | EOS Quark — Consolidated Change Log (post-batch stabilization) |
| [EOS_Quark_Deferred_Considerations_Register.md](01-start-here/EOS_Quark_Deferred_Considerations_Register.md) | EOS Quark — Deferred Considerations Register |
| [EOS_Quark_KT_Tracking.md](01-start-here/EOS_Quark_KT_Tracking.md) | EOS Quark — KT Session Tracking |

### Engine rewrite batches <sub>&nbsp;14 docs</sub>

The .NET&nbsp;&rarr;&nbsp;Java port, batch by batch, as copy-paste change sets. Batches 11&ndash;13 are the REDO pass and supersede earlier numbering where they overlap.

| Document | Topic |
|---|---|
| [EOS_Quark_Batch10_Changes.md](02-engine-batches/EOS_Quark_Batch10_Changes.md) | EOS Quark Engine — Batch 10 Changes |
| [EOS_Quark_Batch11_Changes.md](02-engine-batches/EOS_Quark_Batch11_Changes.md) | EOS Quark — Batch 11 (REDO) Changes |
| [EOS_Quark_Batch12_Changes.md](02-engine-batches/EOS_Quark_Batch12_Changes.md) | EOS Quark — Batch 12 (REDO) Changes |
| [EOS_Quark_Batch13_Changes.md](02-engine-batches/EOS_Quark_Batch13_Changes.md) | EOS Quark — Batch 13 (REDO) Changes |
| [EOS_Quark_Batch1_Changes.md](02-engine-batches/EOS_Quark_Batch1_Changes.md) | EOS Quark Engine — Batch 1 Changes |
| [EOS_Quark_Batch2_Changes.md](02-engine-batches/EOS_Quark_Batch2_Changes.md) | EOS Quark Engine — Batch 2 Changes |
| [EOS_Quark_Batch3_Changes.md](02-engine-batches/EOS_Quark_Batch3_Changes.md) | EOS Quark Engine — Batch 3 Changes |
| [EOS_Quark_Batch4_Changes.md](02-engine-batches/EOS_Quark_Batch4_Changes.md) | EOS Quark Engine — Batch 4 Changes |
| [EOS_Quark_Batch5_Changes.md](02-engine-batches/EOS_Quark_Batch5_Changes.md) | EOS Quark Engine — Batch 5 Changes |
| [EOS_Quark_Batch5b_TestFixes.md](02-engine-batches/EOS_Quark_Batch5b_TestFixes.md) | EOS Quark Engine — Batch 5b (Stale-Test Fixes) |
| [EOS_Quark_Batch6_Changes.md](02-engine-batches/EOS_Quark_Batch6_Changes.md) | EOS Quark Engine — Batch 6 Changes |
| [EOS_Quark_Batch7_Changes.md](02-engine-batches/EOS_Quark_Batch7_Changes.md) | EOS Quark Engine — Batch 7 Changes |
| [EOS_Quark_Batch8_Changes.md](02-engine-batches/EOS_Quark_Batch8_Changes.md) | EOS Quark Engine — Batch 8 Changes |
| [EOS_Quark_Batch9_Changes.md](02-engine-batches/EOS_Quark_Batch9_Changes.md) | EOS Quark Engine — Batch 9 Changes |

### Fixes — QXPS / QXPSM SOAP <sub>&nbsp;6 docs</sub>

The per-step QXPS (HTTP) / QXPSM (SOAP) transport switch and its failure modes. `QXPSM_FINAL` is the single source of truth &mdash; read it before the others.

| Document | Topic |
|---|---|
| [EOS_Quark_QXPSM_Correctness_Verification.md](03-fixes-soap-qxps-qxpsm/EOS_Quark_QXPSM_Correctness_Verification.md) | EOS Quark — QXPSM correctness verification (deep research + probe) |
| [EOS_Quark_QXPSM_FINAL.md](03-fixes-soap-qxps-qxpsm/EOS_Quark_QXPSM_FINAL.md) | EOS Quark — QXPSM SOAP Fix: SINGLE SOURCE OF TRUTH |
| [EOS_Quark_QXPSM_WSDL_Fix.md](03-fixes-soap-qxps-qxpsm/EOS_Quark_QXPSM_WSDL_Fix.md) | EOS Quark — QXPSM SOAP Fix (Wrong WSDL + Endpoint Env Mismatch) |
| [EOS_Quark_QxpsBuffer_Timeout_Fix.md](03-fixes-soap-qxps-qxpsm/EOS_Quark_QxpsBuffer_Timeout_Fix.md) | EOS Quark — Live-Run Fix: QXPS response buffer + timeout |
| [EOS_Quark_QxpsmSoapClient_Update.md](03-fixes-soap-qxps-qxpsm/EOS_Quark_QxpsmSoapClient_Update.md) | EOS Quark — QxpsmSoapClient update (new doc/literal stub) |
| [EOS_Quark_QxpsmSoap_MultiRef_Fix.md](03-fixes-soap-qxps-qxpsm/EOS_Quark_QxpsmSoap_MultiRef_Fix.md) | EOS Quark — QXPSM SOAP fix: disable Axis multi-ref (+ temp wire debug) |

### Fixes — Oracle SQL, binding & dates <sub>&nbsp;5 docs</sub>

Dynamic-SQL date binding (ORA-01843 / ORA-01830), NLS session settings, positional binds, and NULL hardening in the parameter mappers.

| Document | Topic |
|---|---|
| [EOS_Quark_DateBind_DocLog_TracingSpam_Fix.md](04-fixes-oracle-sql-dates/EOS_Quark_DateBind_DocLog_TracingSpam_Fix.md) | EOS Quark — date-bind blocker + document-store logging + tracing-spam silence (copy-paste ready |
| [EOS_Quark_DynamicSQL_Date_Fix.md](04-fixes-oracle-sql-dates/EOS_Quark_DynamicSQL_Date_Fix.md) | EOS Quark — Dynamic-SQL Date Failure (ORA-01843 / ORA-01830) — Root Cause & Fix |
| [EOS_Quark_DynamicSQL_Date_NLS_Fix_14-07.md](04-fixes-oracle-sql-dates/EOS_Quark_DynamicSQL_Date_NLS_Fix_14-07.md) | EOS Quark — Dynamic-SQL Date / NLS Fix for the 14-07 repo (copy-paste ready) |
| [EOS_Quark_InParamMapper_NullHardening.md](04-fixes-oracle-sql-dates/EOS_Quark_InParamMapper_NullHardening.md) | EOS Quark — `InParamMapper` NULL-hardening (`input_data_type` NUMBER(2,0)) — copy-paste ready |
| [EOS_Quark_RowCount_and_PositionalBinding_Fix.md](04-fixes-oracle-sql-dates/EOS_Quark_RowCount_and_PositionalBinding_Fix.md) | EOS Quark — row-count logging + `?` positional-binding fix (copy-paste ready) |

### Fixes — logging & live-run analysis <sub>&nbsp;3 docs</sub>

Fixes driven by analysing specific production runs, plus logging-hygiene work.

| Document | Topic |
|---|---|
| [EOS_Quark_AuditNull_Fix_and_TestRunQuery.md](05-fixes-logging-run-analysis/EOS_Quark_AuditNull_Fix_and_TestRunQuery.md) | EOS Quark — Audit NULL-`id_suivi` fix + corrected test-run query (copy-paste ready) |
| [EOS_Quark_Logging_Fixes_and_Run339403.md](05-fixes-logging-run-analysis/EOS_Quark_Logging_Fixes_and_Run339403.md) | EOS Quark — logging hygiene + run 339403 analysis (copy-paste ready) |
| [EOS_Quark_RunAnalysis_Fixes_488654_505244.md](05-fixes-logging-run-analysis/EOS_Quark_RunAnalysis_Fixes_488654_505244.md) | EOS Quark — Run-Analysis Fix Batch (runs 488654 & 505244) |

### Validation & testing <sub>&nbsp;4 docs</sub>

Divergences between the Java engine and the .NET original. `Validation_Issue_List_Verified` is the ground-truth-reconciled version &mdash; prefer it over the unverified list.

| Document | Topic |
|---|---|
| [EOS_Quark_Engine_Validation_Findings.md](06-validation-and-testing/EOS_Quark_Engine_Validation_Findings.md) | EOS Quark Engine — Validation Findings Report |
| [EOS_Quark_Repo_Verification_27-06.md](06-validation-and-testing/EOS_Quark_Repo_Verification_27-06.md) | EOS Quark — New Repo Verification & Remaining Changes (27-06) |
| [EOS_Quark_Validation_Issue_List.md](06-validation-and-testing/EOS_Quark_Validation_Issue_List.md) | EOS Quark Java Engine — Consolidated Validation Issue List |
| [EOS_Quark_Validation_Issue_List_Verified.md](06-validation-and-testing/EOS_Quark_Validation_Issue_List_Verified.md) | EOS Quark Java Engine — VERIFIED Validation Issue List (Phase 0 ground-truth reconciled) |

### Copilot / AI agent instructions <sub>&nbsp;1 docs</sub>

Copy-paste bundle of the nine `.github/` instruction files that tell Copilot how to work in the engine repo.

| Document | Topic |
|---|---|
| [EOS_Quark_Copilot_Instructions_BUNDLE.md](07-copilot-instructions/EOS_Quark_Copilot_Instructions_BUNDLE.md) | EOS Quark Engine — GitHub Copilot Custom Instructions (copy-paste bundle) |

## Keeping this in sync

These files are **copies**. The originals live in the working tree and are
never touched by this repo. To pull in new or edited notes:

```bash
./sync-md.sh
```

That re-copies every mapped file and regenerates this index. When you write a
new note, add a `put` line for it in `sync-md.sh` — the script prints an
`UNMAPPED` list for any top-level markdown it doesn't know about, so nothing
goes missing quietly.

## Scope

Only the top-level EOS Quark notes are here. The working tree also holds ~106
other markdown files buried inside code folders — legacy .NET QXP
documentation, `.github/instructions/`, execution plans, batch-service docs,
and duplicate copies across four repo snapshots. Those are deliberately left
out to keep this searchable; the Copilot instruction files are covered by the
bundle in `07-copilot-instructions/`.
