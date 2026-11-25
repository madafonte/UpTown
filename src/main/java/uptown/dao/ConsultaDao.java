package uptown.dao;

import static uptown.AppException.vazio;

import java.sql.SQLException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import uptown.AppException;
import uptown.Db;

/**
 * As 8 consultas da Entrega 3 (sql/03_consultas.sql) e as 4 consultas + 2 views da Etapa 4 (sql/04_etapa04.sql).
 * O mesmo texto SQL esta nesses arquivos (la com variaveis @ em vez de "?").
 */
public final class ConsultaDao {

    /** Parametro que a interface deve pedir. tipo: categoria | cliente | texto | numero | data | status */
    public record Param(String nome, String rotulo, String tipo, String padrao) {}

    private static final class Def {
        final int id;
        final String titulo;
        final String pergunta;
        final String tecnica;
        final String sql;
        final List<Param> params;
        final Function<Map<String, String>, Object[]> binder;

        Def(int id, String titulo, String pergunta, String tecnica, String sql,
            List<Param> params, Function<Map<String, String>, Object[]> binder) {
            this.id = id;
            this.titulo = titulo;
            this.pergunta = pergunta;
            this.tecnica = tecnica;
            this.sql = sql.strip();
            this.params = params;
            this.binder = binder;
        }

        Map<String, Object> meta() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", id);
            m.put("titulo", titulo);
            m.put("pergunta", pergunta);
            m.put("tecnica", tecnica);
            m.put("sql", sql);
            m.put("params", params);
            return m;
        }
    }

    private static final List<Def> CONSULTAS = List.of(

        // 1 ---------------------------------------------------------------------------------
        new Def(1, "Roupas de uma categoria (com subcategorias)",
            "Quais roupas pertencem a uma determinada categoria ou subcategoria? (RF08)",
            "CTE recursiva sobre Pertence + JOIN de 3 tabelas",
            """
            WITH RECURSIVE arvore (codigo_categoria) AS (
                SELECT codigo_categoria
                FROM Categoria
                WHERE codigo_categoria = ?
                UNION
                SELECT p.codigo_categoria_filha
                FROM Pertence p
                JOIN arvore a ON p.codigo_categoria_pai = a.codigo_categoria
            )
            SELECT r.codigo_roupa, r.nome AS roupa, r.tamanho, r.sexo, c.nome AS categoria
            FROM Roupa r
            JOIN Categoria c ON c.codigo_categoria = r.categoria_codigo_roupa
            JOIN arvore a    ON a.codigo_categoria = c.codigo_categoria
            ORDER BY c.nome, r.nome
            """,
            List.of(new Param("categoria", "Categoria", "categoria", null)),
            v -> new Object[]{inteiro(v, "categoria", "Selecione a categoria.")}),

        // 2 ---------------------------------------------------------------------------------
        new Def(2, "Cores e fornecedores de cada roupa",
            "Em quais cores uma roupa esta disponivel e quais fornecedores a fornecem? (RF09, RF10)",
            "JOIN com subconsultas correlacionadas + GROUP_CONCAT + COALESCE",
            """
            SELECT r.codigo_roupa, r.nome AS roupa,
                   COALESCE((SELECT GROUP_CONCAT(rc.cor ORDER BY rc.cor SEPARATOR ', ')
                               FROM roupaCor rc
                              WHERE rc.codigo_roupa = r.codigo_roupa),
                            '(sem cor cadastrada)') AS cores,
                   COALESCE((SELECT GROUP_CONCAT(f.nome ORDER BY f.nome SEPARATOR ', ')
                               FROM Fornece fo
                               JOIN Fornecedor f ON f.codigo_fornecedor = fo.codigo_fornecedor
                              WHERE fo.codigo_roupa = r.codigo_roupa),
                            '(sem fornecedor)') AS fornecedores
            FROM Roupa r
            WHERE r.nome LIKE CONCAT('%', ?, '%')
            ORDER BY r.codigo_roupa
            """,
            List.of(new Param("nome", "Nome da roupa contem (vazio = todas)", "texto", "")),
            v -> new Object[]{texto(v, "nome")}),

        // 3 ---------------------------------------------------------------------------------
        new Def(3, "Historico de pedidos de um cliente",
            "Qual o historico de pedidos de um cliente, com valor total e status de cada um? (RF11)",
            "JOIN de 3 tabelas + GROUP BY + SUM",
            """
            SELECT c.nome AS cliente, p.codigo_pedido, p.data_pedido, p.status,
                   COUNT(i.codigo_item) AS itens,
                   COALESCE(SUM(i.quantidade), 0) AS unidades,
                   COALESCE(SUM(i.quantidade * i.preco_unitario), 0) AS valor_total
            FROM Cliente c
            JOIN Pedido p          ON p.codigo_cliente = c.codigo_cliente
            LEFT JOIN ItemPedido i ON i.codigo_pedido  = p.codigo_pedido
            WHERE c.codigo_cliente = ?
            GROUP BY c.nome, p.codigo_pedido, p.data_pedido, p.status
            ORDER BY p.data_pedido DESC, p.codigo_pedido DESC
            """,
            List.of(new Param("cliente", "Cliente", "cliente", null)),
            v -> new Object[]{inteiro(v, "cliente", "Selecione o cliente.")}),

        // 4 ---------------------------------------------------------------------------------
        new Def(4, "Unidades vendidas por roupa (ranking)",
            "Quantas unidades de cada roupa ja foram vendidas (soma da quantidade nos itens de pedido)? (RF12)",
            "LEFT JOIN + GROUP BY + HAVING + funcao de janela RANK()",
            """
            SELECT r.codigo_roupa, r.nome AS roupa,
                   COALESCE(SUM(i.quantidade), 0) AS unidades_vendidas,
                   RANK() OVER (ORDER BY COALESCE(SUM(i.quantidade), 0) DESC) AS ranking
            FROM Roupa r
            LEFT JOIN ItemPedido i ON i.codigo_roupa = r.codigo_roupa
            GROUP BY r.codigo_roupa, r.nome
            HAVING unidades_vendidas >= ?
            ORDER BY ranking, r.nome
            """,
            List.of(new Param("minimo", "Minimo de unidades vendidas (0 = todas as roupas)", "numero", "1")),
            v -> new Object[]{inteiro(v, "minimo", "Informe o minimo de unidades.")}),

        // 5 ---------------------------------------------------------------------------------
        new Def(5, "Faturamento por status e periodo",
            "Qual o faturamento total dos pedidos num determinado status ou periodo? (RF13)",
            "JOIN + GROUP BY ... WITH ROLLUP + GROUPING() + filtros opcionais",
            """
            SELECT IF(GROUPING(p.status), 'TOTAL GERAL', p.status) AS status,
                   COUNT(DISTINCT p.codigo_pedido) AS pedidos,
                   SUM(i.quantidade) AS unidades,
                   SUM(i.quantidade * i.preco_unitario) AS faturamento,
                   ROUND(SUM(i.quantidade * i.preco_unitario) / COUNT(DISTINCT p.codigo_pedido), 2) AS ticket_medio
            FROM Pedido p
            JOIN ItemPedido i ON i.codigo_pedido = p.codigo_pedido
            WHERE (? IS NULL OR p.status = ?)
              AND p.data_pedido >= COALESCE(CAST(? AS DATE), '1000-01-01')
              AND p.data_pedido <= COALESCE(CAST(? AS DATE), '9999-12-31')
            GROUP BY p.status WITH ROLLUP
            ORDER BY GROUPING(p.status), faturamento DESC
            """,
            List.of(new Param("status", "Status (vazio = todos)", "status", ""),
                    new Param("inicio", "Data inicial", "data", ""),
                    new Param("fim", "Data final", "data", "")),
            v -> {
                String st = vazio(v.get("status")) ? null : v.get("status");
                String ini = vazio(v.get("inicio")) ? null : v.get("inicio");
                String fim = vazio(v.get("fim")) ? null : v.get("fim");
                return new Object[]{st, st, ini, fim};
            }),

        // 6 ---------------------------------------------------------------------------------
        new Def(6, "Roupas que nunca foram vendidas",
            "Quais roupas do catalogo ainda nao aparecem em nenhum pedido?",
            "Anti-join com NOT EXISTS + JOIN",
            """
            SELECT r.codigo_roupa, r.nome AS roupa, r.tamanho, r.sexo, c.nome AS categoria
            FROM Roupa r
            JOIN Categoria c ON c.codigo_categoria = r.categoria_codigo_roupa
            WHERE NOT EXISTS (SELECT 1
                                FROM ItemPedido i
                               WHERE i.codigo_roupa = r.codigo_roupa)
            ORDER BY c.nome, r.nome
            """,
            List.of(),
            v -> new Object[]{}),

        // 7 ---------------------------------------------------------------------------------
        new Def(7, "Clientes que gastam acima da media",
            "Quais clientes gastaram mais que o gasto medio por cliente (ignorando pedidos cancelados)?",
            "CTE + subconsulta escalar + DENSE_RANK() OVER",
            """
            WITH gasto AS (
                SELECT c.codigo_cliente, c.nome,
                       COUNT(DISTINCT p.codigo_pedido) AS pedidos,
                       SUM(i.quantidade * i.preco_unitario) AS total_gasto
                FROM Cliente c
                JOIN Pedido p     ON p.codigo_cliente = c.codigo_cliente
                JOIN ItemPedido i ON i.codigo_pedido  = p.codigo_pedido
                WHERE p.status <> 'Cancelado'
                GROUP BY c.codigo_cliente, c.nome
            )
            SELECT g.codigo_cliente, g.nome AS cliente, g.pedidos, g.total_gasto,
                   ROUND((SELECT AVG(total_gasto) FROM gasto), 2) AS media_geral,
                   ROUND(g.total_gasto - (SELECT AVG(total_gasto) FROM gasto), 2) AS acima_da_media,
                   DENSE_RANK() OVER (ORDER BY g.total_gasto DESC) AS posicao
            FROM gasto g
            WHERE g.total_gasto > (SELECT AVG(total_gasto) FROM gasto)
            ORDER BY posicao, g.nome
            """,
            List.of(),
            v -> new Object[]{}),

        // 8 ---------------------------------------------------------------------------------
        new Def(8, "Vendas por tipo de roupa",
            "Quanto cada especializacao de Roupa (camisa, calca, casaco) vendeu?",
            "UNION ALL de 3 JOINs (especializacao) + JOIN com ItemPedido + GROUP BY",
            """
            SELECT t.tipo,
                   COUNT(DISTINCT t.codigo_roupa) AS roupas_vendidas,
                   SUM(i.quantidade) AS unidades,
                   SUM(i.quantidade * i.preco_unitario) AS faturamento
            FROM (
                SELECT 'Camisa' AS tipo, r.codigo_roupa
                FROM Roupa r JOIN Camisa x ON x.codigo_camisa = r.codigo_roupa
                UNION ALL
                SELECT 'Calça', r.codigo_roupa
                FROM Roupa r JOIN Calca x ON x.codigo_calca = r.codigo_roupa
                UNION ALL
                SELECT 'Casaco', r.codigo_roupa
                FROM Roupa r JOIN Casaco x ON x.codigo_casaco = r.codigo_roupa
            ) t
            JOIN ItemPedido i ON i.codigo_roupa = t.codigo_roupa
            GROUP BY t.tipo
            ORDER BY faturamento DESC
            """,
            List.of(),
            v -> new Object[]{}),

        // ===== Etapa 04 (sql/04_etapa04.sql) =====

        // 9 ---------------------------------------------------------------------------------
        new Def(9, "Clientes sem pedidos no periodo",
            "Quais clientes nao fizeram nenhum pedido no periodo informado? (Etapa 4)",
            "Anti-join com LEFT JOIN ... IS NULL, periodo semiaberto [inicio, fim)",
            """
            SELECT c.codigo_cliente,
                   c.nome AS cliente,
                   c.email
            FROM Cliente c
            LEFT JOIN Pedido p
                   ON p.codigo_cliente = c.codigo_cliente
                  AND p.data_pedido >= ?
                  AND p.data_pedido <  ?
            WHERE p.codigo_pedido IS NULL
            ORDER BY c.nome
            """,
            List.of(new Param("inicio", "Inicio do periodo", "data", "2026-03-01"),
                    new Param("fim", "Fim do periodo (exclusivo)", "data", "2026-04-01")),
            v -> new Object[]{data(v, "inicio"), data(v, "fim")}),

        // 10 --------------------------------------------------------------------------------
        new Def(10, "Conciliacao: roupas vendidas x roupas com fornecedor",
            "Que roupas tem venda ativa, fornecedor, ou so um dos dois? (Etapa 4)",
            "FULL OUTER JOIN emulado (LEFT JOIN + UNION ALL) sobre duas CTEs",
            """
            WITH vendas_roupa AS (
                SELECT i.codigo_roupa,
                       SUM(i.quantidade) AS unidades_vendidas,
                       SUM(i.quantidade * i.preco_unitario) AS faturamento_ativo,
                       COUNT(DISTINCT p.codigo_pedido) AS pedidos_ativos
                FROM ItemPedido i
                JOIN Pedido p ON p.codigo_pedido = i.codigo_pedido
                WHERE p.status <> 'Cancelado'
                GROUP BY i.codigo_roupa
            ),
            fornecedores_roupa AS (
                SELECT fo.codigo_roupa,
                       GROUP_CONCAT(DISTINCT f.nome ORDER BY f.nome SEPARATOR ', ') AS fornecedores
                FROM Fornece fo
                JOIN Fornecedor f ON f.codigo_fornecedor = fo.codigo_fornecedor
                GROUP BY fo.codigo_roupa
            ),
            conciliacao AS (
                SELECT v.codigo_roupa, v.unidades_vendidas, v.faturamento_ativo, v.pedidos_ativos, f.fornecedores
                FROM vendas_roupa v
                LEFT JOIN fornecedores_roupa f ON f.codigo_roupa = v.codigo_roupa
                UNION ALL
                SELECT f.codigo_roupa, v.unidades_vendidas, v.faturamento_ativo, v.pedidos_ativos, f.fornecedores
                FROM fornecedores_roupa f
                LEFT JOIN vendas_roupa v ON v.codigo_roupa = f.codigo_roupa
                WHERE v.codigo_roupa IS NULL
            )
            SELECT r.codigo_roupa,
                   r.nome AS roupa,
                   c.unidades_vendidas,
                   c.faturamento_ativo,
                   c.pedidos_ativos,
                   c.fornecedores,
                   CASE
                       WHEN c.unidades_vendidas IS NULL THEN 'Fornecedor sem venda ativa'
                       WHEN c.fornecedores IS NULL THEN 'Venda ativa sem fornecedor'
                       ELSE 'Venda ativa e fornecedor'
                   END AS situacao
            FROM conciliacao c
            JOIN Roupa r ON r.codigo_roupa = c.codigo_roupa
            ORDER BY r.codigo_roupa
            """,
            List.of(),
            v -> new Object[]{}),

        // 11 --------------------------------------------------------------------------------
        new Def(11, "Roupas acima da media de vendas da categoria",
            "Que roupas venderam mais unidades que a media da propria categoria? (Etapa 4)",
            "CTE + subconsulta escalar correlacionada (AVG por categoria)",
            """
            WITH vendas_por_roupa AS (
                SELECT r.codigo_roupa,
                       r.nome AS roupa,
                       r.categoria_codigo_roupa,
                       c.nome AS categoria,
                       COALESCE(SUM(
                           CASE
                               WHEN p.codigo_pedido IS NOT NULL
                                AND p.status <> 'Cancelado' THEN i.quantidade
                               ELSE 0
                           END
                       ), 0) AS unidades_vendidas
                FROM Roupa r
                JOIN Categoria c ON c.codigo_categoria = r.categoria_codigo_roupa
                LEFT JOIN ItemPedido i ON i.codigo_roupa = r.codigo_roupa
                LEFT JOIN Pedido p ON p.codigo_pedido = i.codigo_pedido
                GROUP BY r.codigo_roupa, r.nome, r.categoria_codigo_roupa, c.nome
            )
            SELECT v.codigo_roupa,
                   v.roupa,
                   v.categoria,
                   v.unidades_vendidas,
                   (SELECT AVG(v2.unidades_vendidas)
                      FROM vendas_por_roupa v2
                     WHERE v2.categoria_codigo_roupa = v.categoria_codigo_roupa
                   ) AS media_unidades_da_categoria
            FROM vendas_por_roupa v
            WHERE v.unidades_vendidas > (
                SELECT AVG(v2.unidades_vendidas)
                FROM vendas_por_roupa v2
                WHERE v2.categoria_codigo_roupa = v.categoria_codigo_roupa
            )
            ORDER BY v.categoria, v.unidades_vendidas DESC, v.roupa
            """,
            List.of(),
            v -> new Object[]{}),

        // 12 --------------------------------------------------------------------------------
        new Def(12, "Categorias acima do faturamento medio no periodo",
            "Que categorias faturaram mais que a media das categorias no periodo? (Etapa 4)",
            "CTE agregada + subconsultas escalares; usa o indice idx_pedido_data_status",
            """
            WITH faturamento_categoria AS (
                SELECT c.codigo_categoria,
                       c.nome AS categoria,
                       SUM(i.quantidade * i.preco_unitario) AS faturamento_ativo
                FROM Pedido p
                JOIN ItemPedido i ON i.codigo_pedido = p.codigo_pedido
                JOIN Roupa r ON r.codigo_roupa = i.codigo_roupa
                JOIN Categoria c ON c.codigo_categoria = r.categoria_codigo_roupa
                WHERE p.data_pedido >= ?
                  AND p.data_pedido <  ?
                  AND p.status <> 'Cancelado'
                GROUP BY c.codigo_categoria, c.nome
            )
            SELECT fc.codigo_categoria,
                   fc.categoria,
                   fc.faturamento_ativo,
                   (SELECT AVG(fc2.faturamento_ativo)
                      FROM faturamento_categoria fc2
                   ) AS media_faturamento_categorias
            FROM faturamento_categoria fc
            WHERE fc.faturamento_ativo > (
                SELECT AVG(fc2.faturamento_ativo)
                FROM faturamento_categoria fc2
            )
            ORDER BY fc.faturamento_ativo DESC
            """,
            List.of(new Param("inicio", "Inicio do periodo", "data", "2026-01-01"),
                    new Param("fim", "Fim do periodo (exclusivo)", "data", "2027-01-01")),
            v -> new Object[]{data(v, "inicio"), data(v, "fim")}),

        // 13 --------------------------------------------------------------------------------
        new Def(13, "Visao: detalhe de cada item comprado (vw_detalhe_pedido_cliente)",
            "Quem comprou, quando, em que situacao e qual roupa/categoria em cada item de pedido? (view da Etapa 4)",
            "VIEW de 5 tabelas (Cliente, Pedido, ItemPedido, Roupa, Categoria) com filtros opcionais",
            """
            SELECT *
            FROM vw_detalhe_pedido_cliente
            WHERE (? IS NULL OR codigo_cliente = ?)
              AND (? IS NULL OR status_pedido = ?)
            ORDER BY data_pedido DESC, codigo_pedido DESC, codigo_item
            """,
            List.of(new Param("cliente", "Cliente (vazio = todos)", "cliente_opc", ""),
                    new Param("status", "Status (vazio = todos)", "status", "")),
            v -> {
                Integer cli = vazio(v.get("cliente")) ? null : inteiro(v, "cliente", "Cliente invalido.");
                String st = vazio(v.get("status")) ? null : v.get("status");
                return new Object[]{cli, cli, st, st};
            }),

        // 14 --------------------------------------------------------------------------------
        new Def(14, "Visao: desempenho de vendas por roupa (vw_desempenho_vendas_roupa)",
            "Quanto cada roupa vendeu (sem pedidos cancelados), por categoria? (view da Etapa 4)",
            "VIEW de 4 tabelas com LEFT JOIN, agregacao condicional e filtros opcionais",
            """
            WITH RECURSIVE arvore (codigo_categoria) AS (
                SELECT codigo_categoria FROM Categoria WHERE codigo_categoria = ?
                UNION
                SELECT p.codigo_categoria_filha
                FROM Pertence p JOIN arvore a ON p.codigo_categoria_pai = a.codigo_categoria
            )
            SELECT v.*
            FROM vw_desempenho_vendas_roupa v
            WHERE (? IS NULL OR v.codigo_categoria IN (SELECT codigo_categoria FROM arvore))
              AND v.unidades_vendidas_ativas >= ?
            ORDER BY v.faturamento_ativo DESC, v.roupa
            """,
            List.of(new Param("categoria", "Categoria (inclui subcategorias; vazio = todas)", "categoria_opc", ""),
                    new Param("minimo", "Minimo de unidades vendidas", "numero", "0")),
            v -> {
                Integer cat = vazio(v.get("categoria")) ? null : inteiro(v, "categoria", "Categoria invalida.");
                return new Object[]{cat, cat, inteiro(v, "minimo", "Informe o minimo de unidades.")};
            })
    );

    public List<Map<String, Object>> listar() {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Def d : CONSULTAS) out.add(d.meta());
        return out;
    }

    public Map<String, Object> executar(int id, Map<String, String> valores) throws SQLException {
        Def d = CONSULTAS.stream().filter(c -> c.id == id).findFirst()
                .orElseThrow(() -> AppException.naoEncontrado("Consulta " + id + " nao existe."));
        Db.Table t = Db.table(d.sql, d.binder.apply(valores));
        Map<String, Object> out = d.meta();
        out.put("colunas", t.columns());
        out.put("linhas", t.rows());
        return out;
    }

    private static Integer inteiro(Map<String, String> v, String nome, String msgErro) {
        try {
            return Integer.valueOf(v.getOrDefault(nome, "").trim());
        } catch (NumberFormatException e) {
            throw AppException.invalido(msgErro);
        }
    }

    /** Data AAAA-MM-DD obrigatoria (o texto vai para o MySQL e e comparado com DATE). */
    private static String data(Map<String, String> v, String nome) {
        String s = v.getOrDefault(nome, "").trim();
        try {
            return java.time.LocalDate.parse(s).toString();
        } catch (java.time.format.DateTimeParseException e) {
            throw AppException.invalido("Informe as datas do periodo (AAAA-MM-DD).");
        }
    }

    private static String texto(Map<String, String> v, String nome) {
        return v.getOrDefault(nome, "").trim();
    }
}
