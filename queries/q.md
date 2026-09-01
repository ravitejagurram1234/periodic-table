#### 6.2.2 DEV change ORA-INSERTRUN-COMPAT-01

`QOFF-01I` proved the exact deployed anchors. This change touches only `QXP_PK_SUIVI`; do not edit
`QXP_PK_RUN`. Keep existing specification lines 106-117 and body lines 799-856 unchanged.

**Package specification:** insert the following declaration immediately after current line 117 (`RETURN NUMBER;`)
and before current blank line 118:

```sql
-- Legacy .NET compatibility: the old caller does not supply p_email.
FUNCTION InsertRun
(
    p_idSuivi             IN NUMBER
  , p_datePlanification   IN DATE
  , p_gabarit_source      IN NUMBER
  , p_idCreateur          IN NUMBER
  , p_integrerN1          IN NUMBER
  , p_modeCompart         IN NUMBER
  , p_idSuiviSrc          IN NUMBER := NULL
)
RETURN NUMBER;
```

**Package body:** insert the following complete overload immediately after current line 856 (`END;`) and before
the comment beginning at current line 859 (`Nom : InsertRunTaches`):

```sql
-- Legacy .NET compatibility: resolve email, then use the current implementation.
FUNCTION InsertRun
(
    p_idSuivi             IN NUMBER
  , p_datePlanification   IN DATE
  , p_gabarit_source      IN NUMBER
  , p_idCreateur          IN NUMBER
  , p_integrerN1          IN NUMBER
  , p_modeCompart         IN NUMBER
  , p_idSuiviSrc          IN NUMBER := NULL
)
RETURN NUMBER
IS
  v_email QXP_UTILISATEUR.EMAIL%TYPE;
BEGIN
  IF NVL(p_idCreateur, 0) = 0 THEN
    v_email := NULL;
  ELSE
    SELECT utilisateur.email
    INTO v_email
    FROM QXP_UTILISATEUR utilisateur
    WHERE utilisateur.id_utilisateur = p_idCreateur;
  END IF;

  RETURN InsertRun
  (
      p_idSuivi           => p_idSuivi
    , p_datePlanification => p_datePlanification
    , p_gabarit_source    => p_gabarit_source
    , p_idCreateur        => p_idCreateur
    , p_email             => v_email
    , p_integrerN1        => p_integrerN1
    , p_modeCompart       => p_modeCompart
    , p_idSuiviSrc        => p_idSuiviSrc
  );
END InsertRun;
```

Why this is safe:

- the old six-input named call resolves only to the new legacy overload;
- a seven- or eight-input email-aware call resolves to the existing implementation by `P_EMAIL` name/type;
- a seven-input legacy positional call has `NUMBER` at position 5 and resolves to the legacy overload;
- the named `p_email` delegation resolves explicitly to the current implementation;
- the current email-aware declaration/body and all `QXP_PK_RUN` routines remain unchanged;
- creator `0`, used by automatic compartment runs, stores null email as seen in existing data;
- a missing nonzero `QXP_UTILISATEUR` row raises an error instead of creating an unattributed run.

Apply and validate:

1. Keep the old UI, Batch, .NET Engine and Java Engine stopped.
2. Save a private rollback export of the deployed package specification/body; do not paste it into chat.
3. Insert only the two fragments above using the SQL Developer package editors.
4. Compile the package specification and then immediately compile the package body.
5. Run `QOFF-01J`; continue only when it returns exactly two `OBJECT` rows and both are `VALID`, with no `ERROR`
   rows.
6. Rerun `QOFF-01H`. It must show two InsertRun signatures: one containing required `P_EMAIL`, and one without
   `P_EMAIL`; both retain optional `P_IDSUIVISRC`.
7. Stop and share the complete `QOFF-01J` and `QOFF-01H` results. Do not start the UI until both are reviewed.
8. After review, start only the old UI components needed for creation. Keep Batch and both engines stopped.
9. Make one Programmed/Planned normal source-1 creation attempt, then run `QOFF-01C` and stop for review.
10. After the normal path passes, separately test one real compartment creation before declaring coexistence
   compatibility complete.

Rollback: if either package object is invalid, an unexpected signature appears, or old-UI creation still reports
`PLS-00306`, keep all callers stopped, restore both private pre-change package objects, compile both, and rerun
`QOFF-01J` plus `QOFF-01H`. Do not modify `QXP_RUN`, `QXP_SUIVI` or `QXP_PK_RUN` to compensate.

For simultaneous engine operation, route each queued run to either .NET or Java. Never let both engines process the
same run ID. Use separate queues/routing keys or an equivalent dispatcher decision, retain the atomic run-claim
guard, and record the selected engine in operational evidence.

For the current first diagnostic, route 1 is recommended pending operator confirmation. Path B is blocked in this
DEV deployment until route 2 is implemented; retain the remaining Path B steps for the restored compatible flow.

1. Stop/disable the **batch**, the **old .NET engine**, and the **Java engine** before clicking Generate in the UI.
   Keep only the UI/backend components needed to call `QXP_PK_SUIVI.InsertRun` available. Confirm all three consumers
   are stopped; stopping them after creation is too late because the batch can race the operator.
2. In the old UI, select the real fund/unit, report, date, language, gabarit/source mode, compartment mode and active
   tasks needed for the case. Select tasks normally in the UI; never add rows directly to `QXP_ASSO_RUN_TACHES`.
3. Submit/plan the run through the normal UI flow. `InsertRun` creates or refreshes the current `QXP_RUN` with status
   `1`, sets `QXP_SUIVI.ID_RUN_SUIVANT`, sets `QXP_SUIVI.ID_STATUT_GENERATION=1`, and `InsertRunTaches` records the
   selected tasks.
4. Run `QOFF-01C` and save `04_ui_created_status1_candidates.csv`. Choose `UI_CREATED_RUN_ID` for the intended
   scenario/report/mode. Prefer `CONFIGURED_CHANGE_SHAPE=UPDATE_AND_MODIFY_CONFIGURED` and
   `BASELINE_HAS_NONZERO_STEP_CHANGE=1` when available.
5. Set `RUN_ID` in the evidence SQL file. Run `QOFF-02A` and save `00_pre_reservation_validation.csv`. Continue only
   when `PRE_RESERVATION_RESULT=PASS`.
6. Before changing status, run `QOFF-03` through `QOFF-09`, including `QOFF-05A`. This catches a wrong report, empty
   dynamic template, missing task document or bad compartment child while rollback is still simple.
7. In SQL Developer/SQLcl, turn **autocommit off**. In the same Oracle session, open
   `EOS_Quark_NonProd_Swagger_Run_Reservation.sql`, set both `RUN_ID` and `CONFIRM_RUN_ID`, execute it once, and save
   DBMS output/result as `00_reservation_console.txt`.
8. The script must print `RESERVATION_UPDATED_ROWS=1`, `QXP_RUN_STATUS=5`, and `TRANSACTION IS UNCOMMITTED`. Its
   post-check must be `PASS`.
9. Before committing, run `QOFF-02B` in that same session. If it is not `PASS`, execute `ROLLBACK`; do not repair any
   other row. If it is `PASS`, execute `COMMIT` manually.
10. Run `QOFF-02B` again after commit and save the final result as `00_selected_run_validation.csv`.
11. Start Java with `engine.input.rabbit.enabled=false`. Keep the batch and old .NET engine stopped until all
   pre/post evidence for that run is complete.
