SELECT r.id_run,
       s.id_suivi,
       s.id_gabarit,
       g.nom                              AS gabarit_nom,
       s.id_type_rapport,                 -- 2 = Plaquette, 5 = DICI, ...
       r.id_statut_generation,            -- 1=ToGenerate 2=Generated 3=Error 4=Running
       COUNT(DISTINCT gt.id_tache)                                        AS nb_taches,
       COUNT(DISTINCT rt.id_tache)                                        AS nb_todo,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=1 THEN t.id_tache END)    AS nb_sql,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=0 THEN t.id_tache END)    AS nb_system,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=2 THEN t.id_tache END)    AS nb_document,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=3 THEN t.id_tache END)    AS nb_qxp_prev,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=4 THEN t.id_tache END)    AS nb_dynamique,
       COUNT(DISTINCT CASE WHEN t.id_type_tache=5 THEN t.id_tache END)    AS nb_compartiment
FROM       qxp_suivi               s
JOIN       qxp_asso_fond_gabarit   fg ON s.id_type_rapport = fg.id_type_rapport
                                     AND s.id_fnd_code     = fg.id_fnd_code
                                     AND s.id_langue       = fg.id_langue
                                     AND s.id_gabarit      = fg.id_gabarit
JOIN       qxp_gabarit             g  ON g.id_gabarit = fg.id_gabarit    -- gabarit MUST exist,
                                     AND g.is_actif   = 1                --   be active,
                                     AND g.contenu IS NOT NULL           --   and have QXP content
JOIN       qxp_asso_gabarit_taches gt ON gt.id_gabarit = fg.id_gabarit
JOIN       qxp_run                 r  ON r.id_run = s.id_run_suivant
JOIN       qxp_tache               t  ON t.id_tache = gt.id_tache
                                     AND t.is_actif = 1
LEFT JOIN  qxp_asso_run_taches     rt ON rt.id_run  = r.id_run
                                     AND rt.id_tache = gt.id_tache
GROUP BY r.id_run, s.id_suivi, s.id_gabarit, g.nom, s.id_type_rapport, r.id_statut_generation
HAVING   COUNT(DISTINCT rt.id_tache) > 0
ORDER BY nb_sql DESC, nb_dynamique DESC, nb_taches DESC;
