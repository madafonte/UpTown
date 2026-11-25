package uptown.dao;

import static uptown.AppException.vazio;

import java.sql.Connection;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import uptown.AppException;
import uptown.Db;

/**
 * Dados do dashboard (estatistica descritiva sobre o que esta no banco), com filtros de periodo,
 * categoria (inclui subcategorias) e status.
 *
 * Estrategia: uma tabela temporaria (tmp_dash, uma linha por item de pedido que atende aos filtros)
 * e criada na conexao e todos os indicadores/graficos sao SQL agregado sobre ela.
 * A coluna "conta" indica se a linha entra nas estatisticas: pedidos cancelados ficam de fora,
 * exceto quando o usuario filtra explicitamente por status.
 */
public final class DashboardDao {

    private static final String SQL_ARVORE = """
            WITH RECURSIVE arvore (codigo_categoria) AS (
                SELECT codigo_categoria FROM Categoria WHERE codigo_categoria = ?
                UNION
                SELECT p.codigo_categoria_filha
                FROM Pertence p JOIN arvore a ON p.codigo_categoria_pai = a.codigo_categoria
            )
            SELECT codigo_categoria FROM arvore
            """;

    /** O trecho "%CATEGORIAS%" vira "1 = 1" ou "r.categoria_codigo_roupa IN (?, ?, ...)". */
    private static final String SQL_BASE = """
            CREATE TEMPORARY TABLE tmp_dash AS
            SELECT p.codigo_pedido, p.codigo_cliente, p.data_pedido, p.status,
                   CASE WHEN ? IS NOT NULL OR p.status <> 'Cancelado' THEN 1 ELSE 0 END AS conta,
                   r.codigo_roupa, r.nome AS roupa, c.nome AS categoria, r.sexo, r.tamanho,
                   CASE WHEN ca.codigo_camisa IS NOT NULL THEN 'Camisa'
                        WHEN cl.codigo_calca  IS NOT NULL THEN 'Calça'
                        WHEN co.codigo_casaco IS NOT NULL THEN 'Casaco'
                        ELSE 'Outro' END AS tipo,
                   i.quantidade, i.preco_unitario,
                   CAST(i.quantidade * i.preco_unitario AS DECIMAL(12,2)) AS subtotal
            FROM Pedido p
            JOIN ItemPedido i ON i.codigo_pedido = p.codigo_pedido
            JOIN Roupa r      ON r.codigo_roupa = i.codigo_roupa
            JOIN Categoria c  ON c.codigo_categoria = r.categoria_codigo_roupa
            LEFT JOIN Camisa ca ON ca.codigo_camisa = r.codigo_roupa
            LEFT JOIN Calca  cl ON cl.codigo_calca  = r.codigo_roupa
            LEFT JOIN Casaco co ON co.codigo_casaco = r.codigo_roupa
            WHERE (? IS NULL OR p.data_pedido >= CAST(? AS DATE))
              AND (? IS NULL OR p.data_pedido <= CAST(? AS DATE))
              AND (? IS NULL OR p.status = ?)
              AND %CATEGORIAS%
            """;

    /** Valor de cada pedido (soma dos itens que contam). Reaproveitado como subconsulta. */
    private static final String PEDIDOS =
            "(SELECT codigo_pedido, SUM(subtotal) AS valor FROM tmp_dash WHERE conta = 1 GROUP BY codigo_pedido)";

    private static final String SQL_KPIS = """
            SELECT COUNT(*)                          AS pedidos_validos,
                   COALESCE(SUM(valor), 0)           AS faturamento,
                   COALESCE(AVG(valor), 0)           AS media,
                   COALESCE(VAR_POP(valor), 0)       AS variancia,
                   COALESCE(STDDEV_POP(valor), 0)    AS desvio_padrao,
                   COALESCE(MIN(valor), 0)           AS minimo,
                   COALESCE(MAX(valor), 0)           AS maximo
            FROM\s""" + PEDIDOS + " v";

    /** Mediana: media dos 1 ou 2 valores centrais da lista ordenada. */
    private static final String SQL_MEDIANA = """
            SELECT COALESCE(AVG(valor), 0) AS mediana
            FROM (SELECT valor,
                         ROW_NUMBER() OVER (ORDER BY valor) AS pos,
                         COUNT(*) OVER () AS total
                  FROM\s""" + PEDIDOS + """
             v) t
            WHERE pos IN (FLOOR((total + 1) / 2), CEIL((total + 1) / 2))
            """;

    /** Moda do valor do pedido: so existe se algum valor se repete. */
    private static final String SQL_MODA_VALOR = "SELECT valor AS moda_valor, COUNT(*) AS freq FROM " + PEDIDOS
            + " v GROUP BY valor HAVING COUNT(*) > 1 ORDER BY freq DESC, valor LIMIT 1";

    private static final String SQL_MODA_QTD = """
            SELECT quantidade AS moda_qtd, COUNT(*) AS freq
            FROM tmp_dash
            WHERE conta = 1
            GROUP BY quantidade
            ORDER BY freq DESC, quantidade
            LIMIT 1
            """;

    private static final String SQL_VOLUME = """
            SELECT COUNT(DISTINCT codigo_pedido) AS pedidos,
                   COUNT(DISTINCT CASE WHEN conta = 1 THEN codigo_cliente END) AS clientes_ativos,
                   COALESCE(SUM(CASE WHEN conta = 1 THEN quantidade END), 0) AS unidades,
                   COUNT(DISTINCT CASE WHEN status = 'Cancelado' THEN codigo_pedido END) AS cancelados
            FROM tmp_dash
            """;

    private static final String SQL_TOTAIS = """
            SELECT (SELECT COUNT(*) FROM Pedido)  AS total_pedidos,
                   (SELECT COUNT(*) FROM Cliente) AS clientes,
                   (SELECT COUNT(*) FROM Roupa)   AS roupas,
                   (SELECT COUNT(*) FROM Fornecedor) AS fornecedores,
                   (SELECT MIN(data_pedido) FROM Pedido) AS data_min,
                   (SELECT MAX(data_pedido) FROM Pedido) AS data_max
            """;

    private static final String SQL_POR_STATUS = """
            SELECT status, COUNT(DISTINCT codigo_pedido) AS pedidos
            FROM tmp_dash
            GROUP BY status
            ORDER BY pedidos DESC
            """;

    private static final String SQL_FATURAMENTO_MES = """
            SELECT DATE_FORMAT(data_pedido, '%Y-%m') AS mes,
                   SUM(subtotal) AS faturamento,
                   COUNT(DISTINCT codigo_pedido) AS pedidos
            FROM tmp_dash
            WHERE conta = 1
            GROUP BY DATE_FORMAT(data_pedido, '%Y-%m')
            ORDER BY mes
            """;

    private static final String SQL_TOP_ROUPAS = """
            SELECT roupa, SUM(quantidade) AS unidades
            FROM tmp_dash
            WHERE conta = 1
            GROUP BY codigo_roupa, roupa
            ORDER BY unidades DESC, roupa
            LIMIT 10
            """;

    private static final String SQL_POR_CATEGORIA = """
            SELECT categoria, SUM(quantidade) AS unidades, SUM(subtotal) AS faturamento
            FROM tmp_dash
            WHERE conta = 1
            GROUP BY categoria
            ORDER BY unidades DESC, categoria
            """;

    private static final String SQL_TAMANHO_SEXO = """
            SELECT sexo, tamanho, SUM(quantidade) AS unidades
            FROM tmp_dash
            WHERE conta = 1
            GROUP BY sexo, tamanho
            ORDER BY sexo, tamanho
            """;

    /** Histograma do preco unitario praticado, em faixas de R$ 25. */
    private static final String SQL_HISTOGRAMA = """
            SELECT FLOOR(preco_unitario / 25) * 25 AS faixa_inicio, COUNT(*) AS itens
            FROM tmp_dash
            WHERE conta = 1
            GROUP BY FLOOR(preco_unitario / 25) * 25
            ORDER BY faixa_inicio
            """;

    private static final String SQL_POR_TIPO = """
            SELECT tipo, SUM(quantidade) AS unidades, SUM(subtotal) AS faturamento
            FROM tmp_dash
            WHERE conta = 1
            GROUP BY tipo
            ORDER BY faturamento DESC
            """;

    /** Distribuicao de frequencia dos pedidos por dia da semana (1 = domingo ... 7 = sabado). */
    private static final String SQL_DIA_SEMANA = """
            SELECT DAYOFWEEK(data_pedido) AS dia, COUNT(DISTINCT codigo_pedido) AS pedidos
            FROM tmp_dash
            WHERE conta = 1
            GROUP BY DAYOFWEEK(data_pedido)
            ORDER BY dia
            """;

    /** Um ponto por roupa: preco medio praticado x unidades vendidas (para a correlacao). */
    private static final String SQL_DISPERSAO = """
            SELECT roupa, ROUND(AVG(preco_unitario), 2) AS preco, SUM(quantidade) AS unidades
            FROM tmp_dash
            WHERE conta = 1
            GROUP BY codigo_roupa, roupa
            ORDER BY roupa
            """;

    public Map<String, Object> painel(Map<String, String> filtro) throws SQLException {
        String inicio = data(filtro.get("inicio"), "inicial");
        String fim = data(filtro.get("fim"), "final");
        if (inicio != null && fim != null && inicio.compareTo(fim) > 0) {
            throw AppException.invalido("A data inicial nao pode ser posterior a data final.");
        }
        String status = vazio(filtro.get("status")) ? null : filtro.get("status");
        Integer categoria = null;
        if (!vazio(filtro.get("categoria"))) {
            try {
                categoria = Integer.valueOf(filtro.get("categoria").trim());
            } catch (NumberFormatException e) {
                throw AppException.invalido("Categoria invalida.");
            }
        }

        List<Object> params = new ArrayList<>();
        params.add(status);                       // conta
        params.add(inicio); params.add(inicio);
        params.add(fim); params.add(fim);
        params.add(status); params.add(status);
        String filtroCategoria = "1 = 1";
        if (categoria != null) {
            List<Map<String, Object>> ids = Db.query(SQL_ARVORE, categoria);
            if (ids.isEmpty()) throw AppException.invalido("Categoria nao encontrada.");
            StringBuilder in = new StringBuilder("r.categoria_codigo_roupa IN (");
            for (int i = 0; i < ids.size(); i++) {
                in.append(i == 0 ? "?" : ", ?");
                params.add(ids.get(i).get("codigo_categoria"));
            }
            filtroCategoria = in.append(")").toString();
        }

        try (Connection c = Db.open()) {
            Db.update(c, SQL_BASE.replace("%CATEGORIAS%", filtroCategoria), params.toArray());

            Map<String, Object> kpis = new LinkedHashMap<>(Db.queryOne(c, SQL_KPIS));
            kpis.putAll(Db.queryOne(c, SQL_MEDIANA));
            Map<String, Object> moda = Db.queryOne(c, SQL_MODA_VALOR);
            kpis.put("moda_valor", moda == null ? null : moda.get("moda_valor"));
            Map<String, Object> modaQtd = Db.queryOne(c, SQL_MODA_QTD);
            kpis.put("moda_qtd", modaQtd == null ? null : modaQtd.get("moda_qtd"));
            kpis.putAll(Db.queryOne(c, SQL_VOLUME));
            kpis.putAll(Db.queryOne(c, SQL_TOTAIS));

            Map<String, Object> out = new LinkedHashMap<>();
            out.put("kpis", kpis);
            out.put("porStatus", Db.query(c, SQL_POR_STATUS));
            out.put("faturamentoMes", Db.query(c, SQL_FATURAMENTO_MES));
            out.put("topRoupas", Db.query(c, SQL_TOP_ROUPAS));
            out.put("porCategoria", Db.query(c, SQL_POR_CATEGORIA));
            out.put("tamanhoSexo", Db.query(c, SQL_TAMANHO_SEXO));
            out.put("histograma", Db.query(c, SQL_HISTOGRAMA));
            out.put("porTipo", Db.query(c, SQL_POR_TIPO));
            out.put("diaSemana", Db.query(c, SQL_DIA_SEMANA));
            out.put("dispersao", Db.query(c, SQL_DISPERSAO));
            return out;
        }
    }

    private static String data(String s, String nome) {
        if (vazio(s)) return null;
        try {
            return LocalDate.parse(s.trim()).toString();
        } catch (DateTimeParseException e) {
            throw AppException.invalido("Data " + nome + " invalida (use AAAA-MM-DD).");
        }
    }
}
