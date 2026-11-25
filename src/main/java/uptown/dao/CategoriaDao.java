package uptown.dao;

import static uptown.AppException.exigir;
import static uptown.AppException.vazio;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import uptown.AppException;
import uptown.Db;

/**
 * CRUD da tabela Categoria (RF01) incluindo o auto-relacionamento
 * (tabela Pertence: categoria pai -> subcategoria). Categoria e Pertence sao
 * alteradas na mesma transacao.
 */
public final class CategoriaDao {

    /** alterarPai = true indica que o campo codigoPai deve ser regravado (null = sem categoria pai). */
    public record Dados(String nome, String descricao, Integer codigoPai, Boolean alterarPai) {}

    private static final String SQL_LISTAR = """
            SELECT c.codigo_categoria, c.nome, c.descricao,
                   (SELECT GROUP_CONCAT(pai.nome ORDER BY pai.nome SEPARATOR ', ')
                      FROM Pertence p
                      JOIN Categoria pai ON pai.codigo_categoria = p.codigo_categoria_pai
                     WHERE p.codigo_categoria_filha = c.codigo_categoria) AS categoria_pai,
                   (SELECT MIN(p.codigo_categoria_pai)
                      FROM Pertence p
                     WHERE p.codigo_categoria_filha = c.codigo_categoria) AS codigo_pai,
                   (SELECT COUNT(*) FROM Pertence p
                     WHERE p.codigo_categoria_filha = c.codigo_categoria) AS qtd_pais,
                   (SELECT COUNT(*) FROM Roupa r
                     WHERE r.categoria_codigo_roupa = c.codigo_categoria) AS qtd_roupas
            FROM Categoria c
            ORDER BY c.codigo_categoria
            """;

    private static final String SQL_INSERIR = "INSERT INTO Categoria (nome, descricao) VALUES (?, ?)";

    private static final String SQL_ATUALIZAR = "UPDATE Categoria SET nome = ?, descricao = ? WHERE codigo_categoria = ?";

    private static final String SQL_INSERIR_PERTENCE =
            "INSERT INTO Pertence (codigo_categoria_pai, codigo_categoria_filha) VALUES (?, ?)";

    private static final String SQL_LIMPAR_PAIS = "DELETE FROM Pertence WHERE codigo_categoria_filha = ?";

    private static final String SQL_DELETAR = "DELETE FROM Categoria WHERE codigo_categoria = ?";

    /** A nova categoria pai nao pode ser a propria categoria nem uma das suas descendentes (evita ciclo). */
    private static final String SQL_CICLO = """
            WITH RECURSIVE descendentes (codigo) AS (
                SELECT ?
                UNION
                SELECT p.codigo_categoria_filha
                FROM Pertence p
                JOIN descendentes d ON p.codigo_categoria_pai = d.codigo
            )
            SELECT COUNT(*) AS qtd FROM descendentes WHERE codigo = ?
            """;

    public List<Map<String, Object>> listar() throws SQLException {
        return Db.query(SQL_LISTAR);
    }

    public long criar(Dados d) throws SQLException {
        validar(d);
        try (Connection c = Db.open()) {
            c.setAutoCommit(false);
            try {
                long id = Db.insert(c, SQL_INSERIR, d.nome().trim(), vazio(d.descricao()) ? null : d.descricao().trim());
                if (d.codigoPai() != null) {
                    Db.update(c, SQL_INSERIR_PERTENCE, d.codigoPai(), id);
                }
                c.commit();
                return id;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    public void atualizar(int id, Dados d) throws SQLException {
        validar(d);
        try (Connection c = Db.open()) {
            c.setAutoCommit(false);
            try {
                int n = Db.update(c, SQL_ATUALIZAR, d.nome().trim(), vazio(d.descricao()) ? null : d.descricao().trim(), id);
                if (n == 0) throw AppException.naoEncontrado("Categoria " + id + " nao encontrada.");
                if (Boolean.TRUE.equals(d.alterarPai())) {
                    Db.update(c, SQL_LIMPAR_PAIS, id);
                    if (d.codigoPai() != null) {
                        Map<String, Object> r = Db.query(c, SQL_CICLO, id, d.codigoPai()).get(0);
                        exigir(((Number) r.get("qtd")).intValue() == 0,
                                "Categoria pai invalida: ela nao pode ser a propria categoria nem uma de suas subcategorias.");
                        Db.update(c, SQL_INSERIR_PERTENCE, d.codigoPai(), id);
                    }
                }
                c.commit();
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    public void deletar(int id) throws SQLException {
        try (Connection c = Db.open()) {
            c.setAutoCommit(false);
            try {
                Db.update(c, SQL_LIMPAR_PAIS, id); // desfaz o vinculo com o(s) pai(s)
                int n = Db.update(c, SQL_DELETAR, id);
                if (n == 0) throw AppException.naoEncontrado("Categoria " + id + " nao encontrada.");
                c.commit();
            } catch (SQLException e) {
                c.rollback();
                if (e.getErrorCode() == 1451) {
                    throw AppException.conflito("Nao e possivel excluir: a categoria possui subcategorias ou roupas vinculadas.");
                }
                throw e;
            } catch (RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    private void validar(Dados d) {
        exigir(d != null && !vazio(d.nome()), "Informe o nome da categoria.");
    }
}
