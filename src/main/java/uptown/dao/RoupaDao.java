package uptown.dao;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import uptown.Db;

/** Catalogo de roupas (somente leitura nesta versao). O subtipo vem das tabelas Camisa/Calca/Casaco. */
public final class RoupaDao {

    private static final String SQL_LISTAR = """
            SELECT r.codigo_roupa, r.nome, r.tamanho, r.sexo, c.nome AS categoria,
                   CASE WHEN ca.codigo_camisa IS NOT NULL THEN 'Camisa'
                        WHEN cl.codigo_calca  IS NOT NULL THEN 'Calça'
                        WHEN co.codigo_casaco IS NOT NULL THEN 'Casaco'
                        ELSE '-' END AS tipo,
                   (SELECT i.preco_unitario
                      FROM ItemPedido i
                     WHERE i.codigo_roupa = r.codigo_roupa
                     ORDER BY i.codigo_item DESC
                     LIMIT 1) AS ultimo_preco,
                   fn_unidades_vendidas_ativas(r.codigo_roupa) AS unidades_vendidas
            FROM Roupa r
            JOIN Categoria c ON c.codigo_categoria = r.categoria_codigo_roupa
            LEFT JOIN Camisa ca ON ca.codigo_camisa = r.codigo_roupa
            LEFT JOIN Calca  cl ON cl.codigo_calca  = r.codigo_roupa
            LEFT JOIN Casaco co ON co.codigo_casaco = r.codigo_roupa
            ORDER BY r.codigo_roupa
            """;

    public List<Map<String, Object>> listar() throws SQLException {
        return Db.query(SQL_LISTAR);
    }
}
