package com.socgen.sgs.api.quark.engine.infra.dao.impl;

import com.socgen.sgs.api.quark.engine.domain.DocumentDomain;
import com.socgen.sgs.api.quark.engine.infra.dao.InsertDocumentDao;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.SqlOutParameter;
import org.springframework.jdbc.core.SqlParameter;
import org.springframework.jdbc.core.SqlTypeValue;
import org.springframework.jdbc.core.simple.SimpleJdbcCall;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.io.ByteArrayInputStream;
import java.sql.Types;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.Map;

/**
 * Oracle implementation: QXP_PK_RUN.Insert_Document
 */
@Repository
@RequiredArgsConstructor
@Slf4j
public class InsertDocumentDaoImpl implements InsertDocumentDao {

    private final DataSource dataSource;

    @Override
    public int insertDocument(DocumentDomain document, int idSousCategorie,
                              String idFndCode, String idUnitCode,
                              LocalDate dateEcheance, int idRun) {
        if (document == null || document.getData() == null) {
            return Integer.MIN_VALUE;
        }

        SimpleJdbcCall jdbcCall = new SimpleJdbcCall(dataSource)
                .withCatalogName("QXP_PK_RUN")
                .withFunctionName("Insert_Document")
                // Bind solely from the explicit declareParameters list (no JDBC metadata lookup),
                // matching AuditDao and the rest of the DAO layer — deterministic RETURN/param
                // resolution across drivers. Declared order matches the proc in ora.txt. Findings #47/#90.
                .withoutProcedureColumnMetaDataAccess()
                .declareParameters(
                        new SqlOutParameter("RETURN", Types.NUMERIC),
                        new SqlParameter("p_code_port", Types.VARCHAR),
                        new SqlParameter("p_id_unit_code", Types.VARCHAR),
                        new SqlParameter("p_id_sous_categorie", Types.NUMERIC),
                        new SqlParameter("p_format", Types.VARCHAR),
                        new SqlParameter("p_id_langue", Types.NUMERIC),
                        new SqlParameter("p_date_document", Types.DATE),
                        new SqlParameter("p_nom_document", Types.VARCHAR),
                        new SqlParameter("p_id_utilisateur", Types.NUMERIC),
                        new SqlParameter("p_contenu", Types.BLOB),
                        new SqlParameter("p_taille_document", Types.NUMERIC),
                        new SqlParameter("p_is_actif", Types.NUMERIC),
                        new SqlParameter("p_id_run", Types.NUMERIC)
                );

        Map<String, Object> params = new HashMap<>();
        params.put("p_code_port", idFndCode);
        params.put("p_id_unit_code", idUnitCode);
        params.put("p_id_sous_categorie", idSousCategorie);
        params.put("p_format", document.getFormat());
        params.put("p_id_langue", document.getIdLangue() != null ? document.getIdLangue() : 1);
        // Null-safe (p_date_document is Types.DATE); mirrors GetDocumentDaoImpl's guard. Finding #89.
        params.put("p_date_document", dateEcheance != null ? java.sql.Date.valueOf(dateEcheance) : null);
        params.put("p_nom_document", document.getFileName());
        params.put("p_id_utilisateur", 0);
        // Oracle rejects a byte[] bound to a BLOB IN-param via setObject (SQLException 17004
        // "Invalid column type"). Stream the bytes through a SqlTypeValue (setBinaryStream),
        // which bypasses setObject and handles large (100 MB+) QXP/PDF payloads.
        final byte[] contenu = document.getData();
        params.put("p_contenu", (SqlTypeValue) (ps, paramIndex, sqlType, typeName) ->
                ps.setBinaryStream(paramIndex, new ByteArrayInputStream(contenu), contenu.length));
        params.put("p_taille_document", contenu.length);
        params.put("p_is_actif", 1);
        params.put("p_id_run", idRun);

        Map<String, Object> result = jdbcCall.execute(params);
        Number idDoc = (Number) result.get("RETURN");

        log.debug("Inserted document [{}] with id [{}] for run [{}]",
                document.getFileName(), idDoc, idRun);

        return idDoc != null ? idDoc.intValue() : Integer.MIN_VALUE;
    }













package com.socgen.sgs.api.quark.engine.domain.dynamic.report;

import lombok.Getter;

import java.util.ArrayList;
import java.util.List;

/** A single break rule defining which row-levels trigger a page/column break and which levels to bring along. */
@Getter
public class DBreakRule {

    public static final DBreakRule DEFAULT = new DBreakRule(Integer.MIN_VALUE);

    private final List<Integer> levels = new ArrayList<>();
    private final List<Integer> bringLevels = new ArrayList<>();

    public DBreakRule(int... levels) {
        for (int level : levels) {
            this.levels.add(level);
        }
    }

    public DBreakRule(String rule) {
        analyseRule(rule);
    }

    public DBreakRule(int level, List<Integer> bringLevels) {
        this.levels.add(level);
        this.bringLevels.addAll(bringLevels);
    }

    /**
     * Parses a rule string in the format "X:Y" where X = levels triggering break, Y = levels to bring.
     * X and Y can be comma-separated values, ranges (e.g. 1-3), or LZ notation (bring Z lines).
     */
    private void analyseRule(String rule) {
        String[] ruleInfos = rule.split(":");
        if (ruleInfos.length == 2) {
            levels.addAll(parseRuleValues(ruleInfos[0]));
            bringLevels.addAll(parseRuleValues(ruleInfos[1]));
        }
    }

    private List<Integer> parseRuleValues(String input) {
        List<Integer> values = new ArrayList<>();
        String[] parts = input.split(",");

        for (String part : parts) {
            String[] rangeParts = part.split("-");

            if (rangeParts.length == 2 && !part.startsWith("L")) {
                int start = Integer.parseInt(rangeParts[0].trim());
                int end = Integer.parseInt(rangeParts[1].trim());
                for (int i = start; i <= end; i++) {
                    values.add(i);
                }
            } else {
                String level = rangeParts[0].trim();
                if (level.startsWith("L")) {
                    // LZ notation: negative value means "bring Z lines above regardless of row_level"
                    int nbLigne = Integer.parseInt(level.substring(1));
                    values.add(-nbLigne);
                } else {
                    values.add(Integer.parseInt(level));
                }
            }
        }
        return values;
    }
}

