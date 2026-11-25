package uptown.dao;

import static uptown.AppException.exigir;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import uptown.AppException;
import uptown.Db;

/**
 * Integracao com as funcoes, procedimentos e triggers da Etapa 5 (sql/05_etapa05.sql).
 * Toda a regra mora no banco: aqui so ha CALL / SELECT das rotinas e a leitura do log.
 */
public final class RotinaDao {

    private static final String SQL_FN_TOTAL = "SELECT fn_total_itens_pedido(?) AS total";
    private static final String SQL_FN_UNIDADES = "SELECT fn_unidades_vendidas_ativas(?) AS unidades";

    private static final String SQL_CAIXAS = "CALL sp_planejar_caixas(?, ?)";

    /** Le a tabela temporaria criada pela procedure (mesma conexao) e acrescenta o nome da roupa. */
    private static final String SQL_CAIXAS_DETALHE = """
            SELECT t.numero_caixa, t.codigo_item, t.codigo_roupa, r.nome AS roupa, t.quantidade
            FROM tmp_plano_caixas t
            JOIN Roupa r ON r.codigo_roupa = t.codigo_roupa
            ORDER BY t.numero_caixa, t.codigo_item
            """;

    private static final String SQL_AUDITORIA = """
            SELECT l.codigo_log, l.codigo_pedido, c.nome AS cliente, l.status_anterior, l.status_novo,
                   l.data_alteracao, l.usuario_banco
            FROM LogStatusPedido l
            LEFT JOIN Pedido p  ON p.codigo_pedido = l.codigo_pedido
            LEFT JOIN Cliente c ON c.codigo_cliente = p.codigo_cliente
            ORDER BY l.codigo_log DESC
            LIMIT 300
            """;

    /** fn_total_itens_pedido: soma dos itens do pedido (NULL se o pedido nao existe). */
    public Map<String, Object> totalPedido(int pedido) throws SQLException {
        Object total = Db.queryOne(SQL_FN_TOTAL, pedido).get("total");
        if (total == null) throw AppException.naoEncontrado("Pedido " + pedido + " nao encontrado (a funcao retornou NULL).");
        return resultado("fn_total_itens_pedido(" + pedido + ")", total);
    }

    /** fn_unidades_vendidas_ativas: unidades vendidas em pedidos nao cancelados (NULL se a roupa nao existe). */
    public Map<String, Object> unidadesRoupa(int roupa) throws SQLException {
        Object un = Db.queryOne(SQL_FN_UNIDADES, roupa).get("unidades");
        if (un == null) throw AppException.naoEncontrado("Roupa " + roupa + " nao encontrada (a funcao retornou NULL).");
        return resultado("fn_unidades_vendidas_ativas(" + roupa + ")", un);
    }

    private static Map<String, Object> resultado(String chamada, Object valor) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("chamada", chamada);
        m.put("valor", valor);
        return m;
    }

    /** CALL sp_planejar_caixas: distribui os itens do pedido em caixas de uma capacidade (em unidades). */
    public Map<String, Object> planejarCaixas(int pedido, int capacidade) throws SQLException {
        exigir(capacidade > 0, "A capacidade da caixa deve ser positiva.");
        try (Connection c = Db.open()) {
            Db.query(c, SQL_CAIXAS, pedido, capacidade); // a procedure devolve o plano e cria tmp_plano_caixas
            List<Map<String, Object>> linhas = Db.query(c, SQL_CAIXAS_DETALHE);
            int caixas = 0;
            long unidades = 0;
            for (Map<String, Object> l : linhas) {
                caixas = Math.max(caixas, ((Number) l.get("numero_caixa")).intValue());
                unidades += ((Number) l.get("quantidade")).longValue();
            }
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("chamada", "CALL sp_planejar_caixas(" + pedido + ", " + capacidade + ")");
            out.put("caixas", caixas);
            out.put("unidades", unidades);
            out.put("linhas", linhas);
            return out;
        }
    }

    /** Linhas gravadas pelo trigger trg_pedido_log_status. */
    public List<Map<String, Object>> auditoria() throws SQLException {
        return Db.query(SQL_AUDITORIA);
    }
}
