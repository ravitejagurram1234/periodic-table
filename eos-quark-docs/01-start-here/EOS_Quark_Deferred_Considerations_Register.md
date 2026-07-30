# EOS Quark — Deferred Considerations Register

Consolidated list of every item **intentionally deferred** across the remediation batches (B1–B13),
plus live-only validation gates. This is the single place to track "known, not-yet-done" parity work.

> This is a `.md` (not code), so .NET source pointers are kept here for traceability. The Java code
> itself stays .NET-free going forward; this register holds the mapping.

## Status legend
🔴 high impact · 🟠 medium · 🟡 low / nuance · ✅ decided (no action) · 🔬 live-validation gate

---

## Deferred findings

| # | Batch | Title | Sev | Why deferred | Lands in (Java) | .NET source |
|---|---|---|---|---|---|---|
| #10 | B9 | Double-page (`PAGINATION_DOUBLE`) prepare sub-step | 🔴 | Off-by-one risk in the prepare-offset math; cannot test against real double-page docs; you asked for no guesswork | `RunTaskStep.updateBlocPagination` | `Run_Task_Step.cs` ~340–470 (PA `createNextDummyPage` + PR pages + `prepare_offsetTotal`) |
| #86 | B11 | Store-data cleanup (delete-on-empty) | 🟠 | Binding an **empty** assoc-array to a delete proc via `setPlsqlIndexTable` is driver-sensitive — needs live Oracle | `EndRunBusiness.insertDataStorage` + new `InsertDataStorageDao` delete path | `Proxy_Store` delete-then-insert |
| #88 | B11 | Audit message exact format | 🟡 | Needs a golden-file capture of real audit `p_message` to lock the layout | `EndRunBusiness.buildAuditMessage` | `Audit.Message` composition |
| #67 | B8 | `getProject` degrade-on-DOM-failure | 🟡 | Java bridge is stateless (doc-name only); no per-document `modeDegrade` field (degrade is on `RunProperties`). Functional outcome preserved (EMPTY → empty-child error) | `QxpsmSoapClient.getProject` / `GetDocumentProjectBusiness` | `QXPSM_Helper.Get_Project` degrade branch |
| #60 | B13 | Stale-XML parity nuance | 🟡 | Subtle ordering of when cached gabarit XML is considered stale vs refreshed; behaviour equivalent, nuance unverified | `QxpXml` refresh flow / `CheckServiceImpl.refreshGabaritXml` | gabarit `XML` lazy-refresh |
| #61 | B13 | Overflow Todo sweep flow | 🟡 | The exact set/reset of `todo` flags during overflow reprocessing has a nuance not fully pinned | `CheckServiceImpl.checkOverflow` | `Run_Base.Check` overflow loop |
| #70 | B13 | Date patterns configurable (feature) | 🟡 | A *feature* (externalise date formats), not parity — current hardcoded defaults already match. Only do if requested | date helpers / `DataTypeHelper` | n/a (defaults correct) |
| #72 | B13 | `RunProperties` raw `id_type_rapport` | 🟡 | Carrying the raw report-type id alongside the enum — cosmetic/nuance | `RunProperties` / `RunPropertiesMapper` | `Run_Properties.ID_Type_Rapport` |

## Live-validation gates (not deferred *code* — require the real environment)

| Ref | Title | Sev | What to verify |
|---|---|---|---|
| F4 | Combined-URL `encode()` backslash | 🔬🔴 | `UriComponentsBuilder.encode()` must not break the literal `path=D:\Documents\R_…\` that the Quark host expects — confirm against live QXPS |
| #4/#20 | PL/SQL index-table bind | 🔬🔴 | `setPlsqlIndexTable` for `Insert_Run_Errors` / `Insert_Data` against live Oracle (no `ORA-00902`/`PLS-00306`) |
| QXPSM | SOAP round-trip | 🔬🟠 | `executeStep` value updates + `getXPressDOM` against live QXPSM |
| L5 | fr-FR grouping char | 🔬🟡 | U+202F (JDK/CLDR) vs U+00A0 — verify rendered numbers vs golden output |
| L9 | Golden-file regression | 🔬🔴 | Byte-diff PDF/QXP/JPG vs .NET reference run for core report types |

## Decided (no action — recorded so they aren't re-raised)

| # | Decision |
|---|---|
| #17 | Per-task Mode_Degrade override **removed** — the shipped .NET never overrides `Task_Base.Mode_Degrade=false`, so Java matches by keeping it false (✅). |
| POURCENTAGE | Single ` %`, no ×100 — **approved deviation** from the buggy .NET engine path (matches the correct `QXP_Format_Helper`). |
| #3, #85 | **Withdrawn** in Phase-0 reconciliation (Java already matched .NET). |

---

## How these get closed
- **#10** — dedicated session with real double-page test docs.
- **#86 / #4 / #20 / F4 / QXPSM** — live Oracle + live Quark host (the go-live validation pass, see Doc 3 §7).
- **#88 / L5 / L9** — golden-file capture from a .NET reference run.
- **#60 / #61 / #70 / #72 / #67** — low-priority; revisit only if a concrete defect surfaces or a feature is requested.
