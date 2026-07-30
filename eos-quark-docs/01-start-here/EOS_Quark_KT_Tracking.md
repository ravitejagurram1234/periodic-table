# EOS Quark — KT Session Tracking

**Purpose:** running tracker for the intern KT sessions. Holds (A) the list of code corrections/divergences
that need action, (B) the list of pending actions/deliverables, (C) a log of factual corrections made
during the KT so the final documentation reflects the *corrected* facts, and (D) KT progress.

**Ground rules for this KT (agreed):**
- **.NET is the source of truth.** Java is the rewrite; when they disagree, .NET is correct unless the
  difference is an intentional Kube/tech adaptation.
- **ORA.TXT is the source of truth for every Oracle package body.** Whenever a DB call is encountered,
  read the FULL procedure/function body in `ora.txt` (params, IN/OUT, types, order, cursor columns) before
  explaining or judging it.
- Correctness over speed. Verify before stating.

---

## (A) LIST OF CORRECTIONS — divergences needing action
*(Remind the user of this whole list, with brief descriptions, once the KT is complete.)*

Legend: ✅ fix needed · ❌ not needed · ❓ unclear, re-verify before deciding

| ID | Status | Divergence (brief) | Java location | .NET location |
|----|--------|--------------------|---------------|---------------|
| **J1** | ✅ fix needed | **PDF render failure not recorded as an error.** .NET adds a *Critique* RunError ("Rendu Impossible du document pdf") on a QXPS PDF-render exception; Java only logs it, so a blank/failed PDF leaves the run with a clean error stream. | `QxpsCallerBusiness.java:233-237` | `QXPS_Caller.cs:256-260` |
| **J2** | ✅ fix needed | **QXPSM timeout code-default is 30 s** (and one property drives both socket + request timeout). .NET default = 1 h request / infinite socket. Masked today by yaml (2 h) but the hardcoded fallback is unsafe. | `QxpsmProperties.java:18` | `QXPSM_Call.cs:82-91` |
| **J3** | ✅ fix needed | **Response buffer capped at 500 MB** (WebClient requires a cap); .NET streams into an unbounded buffer. A >500 MB response .NET would accept is rejected in Java. Make sure cap is high enough / per-env tunable. | `QxpsHttpClient.java` + `application.yaml` max-in-memory-size-bytes | `QXPS_Helper.cs:50-71` |
| **J4** | ✅ fix needed | **HTTP protocol version:** Java sends HTTP/1.1 + `Connection: close` (Reactor Netty can't pin 1.0); .NET sends HTTP/1.0. Confirm QXPS behaves identically or address. | `QxpsHttpClient.java:56` | `QXPS_Call.cs:78` |
| **J5** | ❌ NOT needed | QXPS request timeout 2 h (Java) vs 1 h (.NET) — deliberately more generous. *User decision: no change.* | `application.yaml` qxps.server.timeout | `QXPS_Call.cs:77` |
| **J6** | ❓ re-verify | Content-type text/binary match is case-insensitive in Java, case-sensitive in .NET. Believed harmless (QXPS emits lowercase). | `QxpsHttpClient.java:176-182` | `QXPS_Call.cs:90-103` |
| **J7** | ❓ re-verify | Step-split "disable" sentinel: Java `<=0`, .NET `==int.MinValue`. Believed identical for normal config. | `RunTask.java:146` | `Run_Task.cs:163` |
| **J8** | ❓ re-verify | `maxRetries` guard: Java `>0` vs .NET `!=0 && !=int.MinValue`. Both default off. | `QxpsmSoapClient.java:106` | `QXPSM_Call.cs:79-80` |
| **J9** | ❓ re-verify | Sort stability of the combined-URL message sort (Java stable, .NET unstable introsort). Believed no effect at small message counts. | `QxpsRequestBuilder.java:44-46` | `QXPS_Request_Message.cs:68` |
| **J10** | ❓ re-verify | .NET `QXPSM_Request_Modifier` ctor eagerly double-sends the modifier; Java sends once. Believed a dead path in both. | `QxpsmSoapClient.java` | `QXPSM_Request_Modifier.cs:41` |
| **J11** | ✅ fix needed | **Typed-DOM vs XML read for QXP_Previous.** .NET reads box values via the SOAP typed `Project` DOM (`getXPressDOM`); Java reads via HTTP `/xml` `QxpXml`. Needs a golden-output diff to confirm identical box values (representations differ). | `QxpPreviousTaskProcessStrategy.java:92,144,171` | `Process_QXP_Previous.cs` → `Document.QXPProject` (`Document.cs:395`) |
| **J12** | ✅ fix needed | **Temp debug logging left in config:** `org.apache.axis.transport.http: DEBUG` (from the SOAP-migration diagnosis, marked "REMOVE"). Remove it. | `application.yaml:71-73` | n/a (housekeeping) |

---

## (B) LIST OF PENDING ACTIONS / DELIVERABLES

1. **Create the comprehensive new-joiner documentation** — a single, clear, in-depth document that lets a
   brand-new joiner understand this application *from scratch*: functional + technical + deep code + config,
   every claim .NET-verified (and ora.txt-verified for DB calls). Covers everything we go through in the KT.
   *(To be produced as we progress / consolidated at the end.)*
1b. **Build an HTML decision-flow diagram of the WHOLE run** — clear, every decision branch, self-contained
   HTML. To accompany the new-joiner documentation. .NET + ora.txt verified.
2. **Apply the (A) corrections** confirmed as fix-needed (J1, J2, J3, J4, J11, J12), each as its own reviewed change.
3. **Re-verify the ❓ items** (J6–J10) and get a clear yes/no on each before closing them.
4. At the end of the KT, **remind the user of the full (A) corrections list** with brief descriptions.

---

## (C) FACTUAL CORRECTIONS MADE DURING KT
*(The final documentation must use these corrected facts, not the initial mistakes.)*

- **Report types:** initially stated 3 (Plaquette, DICI/KIID, Annual). CORRECT = **5**:
  Rapport_Annuel(1), Plaquette(2), Prospectus(3, spelled "Propectus" in .NET), Rapport_Compartiment(4), DICI(5).
  DICI == KIID (same doc). Source: `Type_Rapport.cs` == `TypeRapportEnum.java`.
- **`prepare()` "resolves box names":** WRONG/vague. `Task_Base.Prepare()` is abstract; box-name resolution is
  in Process, NOT Prepare. Correct: Prepare is per-task-type and near-empty for most types (System/DID/
  Compartiment = nothing; SQL = tags sub-type; Dynamique = upload template; Document/QXP_Previous = fetch external
  reference doc from DB + upload to pool, PDF split per page). In Java the fetch+upload is split out to Step 3b
  (LoadTaskDocumentsBusiness, handles TaskDocument + TaskQxpPrevious). Verified: .NET Task_*.Prepare.
- **QXPS vs QXPSM roles:** initially framed as "printer vs fancy editor" — WRONG. CORRECT = two transports to the
  same QuarkXPress engine, chosen **per step** by `Direct_Call` (default true → QXPS HTTP; only the field-value
  UPDATE step is forced false → QXPSM SOAP). All final rendering (PDF/JPEG/QXP) is QXPS HTTP. QXPSM's unique
  capability is the typed `Project` DOM via `getXPressDOM`. Verified: `QXPS_Caller.cs` / `QxpsCallerBusiness.java`.

---

## (D) KT PROGRESS LOG

- Part 1 — Functional big picture: DONE.
- Part 2 — Cast of characters / architecture: DONE, but QXPS/QXPSM section CORRECTED (see C).
- Interop deep-dive (QXPS vs QXPSM, verified via 4-agent audit + ora/.NET reads): DONE → produced (A) list.
- Part 3 — 8-step pipeline: DONE. Verified Java runProcessor ≡ .NET Run_Base.Launch; read FULL ora.txt bodies
  Start_Run(9276)/Update_Status_Run(9302)/End_Run(9350)/Insert_Run_Errors(9447); confirmed EndRunBusiness
  ≡ Proxy_Run.End_Run (error→Update_Status_Run; success→insert docs 6/7/8 + End_Run [deletes previous run] +
  errors + audit + data-storage) and @Transactional parity (only txn in codebase).
- NEXT: Part 4 — Task types (SYSTEM/SQL/DOCUMENT/DYNAMIQUE/COMPARTIMENT/DID/QXP_PREVIOUS) + the 3-pass Process loop.
