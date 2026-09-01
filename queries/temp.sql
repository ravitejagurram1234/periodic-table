-- Legacy .NET compatibility: convert and delegate to the current implementation.
PROCEDURE InsertRunTaches
(
    p_idRun     IN NUMBER
  , p_idTaches  IN qxp_pk_common.NumberArray
)
IS
  v_idTaches TABLE_NUMBER;
BEGIN
  v_idTaches := qxp_pk_common.ARRAY_TO_TABLE_NUMBER(p_idTaches);

  InsertRunTaches
  (
      p_idRun    => p_idRun
    , p_idTaches => v_idTaches
  );
END InsertRunTaches;
