**Change C - package body, repair the current email-aware translation call:** replace only the existing statement
at original body line 289:

```sql
v_id_run := qxp_pk_suivi.InsertRun(v_id_new_suivi, NULL, 4, p_email, 0, 0, p_idSuivi);
```

with this named call:

```sql
v_id_run := qxp_pk_suivi.InsertRun
(
    p_idSuivi           => v_id_new_suivi
  , p_datePlanification => NULL
  , p_gabarit_source    => 4
  , p_idCreateur        => 0
  , p_email             => p_email
  , p_integrerN1        => 0
  , p_modeCompart       => 0
  , p_idSuiviSrc        => p_idSuivi
);
```

This preserves the deployed email-based translation behavior while restoring the intended mapping: automatic
creator `0`, actual email, `INTEGRER_N1=0`, non-compartment mode, and the original suivi as source 4.

**Change D - package body, legacy translation overload:** insert this immediately after the `END;` of the existing
email-aware `InsertSuiviTraduction` implementation and before the comment for `DeleteSuivi`:

```sql
-- Legacy .NET compatibility: convert the old numeric identity and delegate.
FUNCTION InsertSuiviTraduction
(
    p_idSuivi       IN NUMBER
  , p_idLangues     IN qxp_pk_common.NumberArray
  , p_idUtilisateur IN NUMBER
  , p_idTypeRapport IN NUMBER
)
RETURN qxp_pk_common.NumberArray
IS
  v_email QXP_UTILISATEUR.EMAIL%TYPE;
BEGIN
  IF p_idTypeRapport = 5
     AND NVL(p_idUtilisateur, 0) <> 0 THEN
    SELECT utilisateur.email
    INTO v_email
    FROM QXP_UTILISATEUR utilisateur
    WHERE utilisateur.id_utilisateur = p_idUtilisateur;
  END IF;

  RETURN InsertSuiviTraduction
  (
      p_idSuivi       => p_idSuivi
    , p_idLangues     => p_idLangues
    , p_email         => v_email
    , p_idTypeRapport => p_idTypeRapport
  );
END InsertSuiviTraduction;
```

The type-5 condition preserves the historical no-op behavior for report types that do not support translation and
avoids an unnecessary user lookup on that path.

**Change E - package body, legacy run overload:** insert this immediately after the `END;` of the existing
email-aware `InsertRun` implementation at original body line 856 and before the comment for `InsertRunTaches`:

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
