package uptown.dao;

import static uptown.AppException.exigir;
import static uptown.AppException.vazio;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import uptown.AppException;
import uptown.Db;

/** CRUD da tabela Fornecedor (RF04). Todo SQL e explicito. */
public final class FornecedorDao {

    public record Dados(String nome) {}

    private static final String SQL_LISTAR = """
            SELECT f.codigo_fornecedor, f.nome,
                   (SELECT COUNT(*) FROM Fornece fo WHERE fo.codigo_fornecedor = f.codigo_fornecedor) AS qtd_roupas
            FROM Fornecedor f
            ORDER BY f.nome
            """;

    private static final String SQL_INSERIR = "INSERT INTO Fornecedor (nome) VALUES (?)";

    private static final String SQL_ATUALIZAR = "UPDATE Fornecedor SET nome = ? WHERE codigo_fornecedor = ?";

    private static final String SQL_DELETAR = "DELETE FROM Fornecedor WHERE codigo_fornecedor = ?";

    public List<Map<String, Object>> listar() throws SQLException {
        return Db.query(SQL_LISTAR);
    }

    public long criar(Dados d) throws SQLException {
        validar(d);
        return Db.insert(SQL_INSERIR, d.nome().trim());
    }

    public void atualizar(int id, Dados d) throws SQLException {
        validar(d);
        int n = Db.update(SQL_ATUALIZAR, d.nome().trim(), id);
        if (n == 0) throw AppException.naoEncontrado("Fornecedor " + id + " nao encontrado.");
    }

    public void deletar(int id) throws SQLException {
        try {
            int n = Db.update(SQL_DELETAR, id);
            if (n == 0) throw AppException.naoEncontrado("Fornecedor " + id + " nao encontrado.");
        } catch (SQLException e) {
            if (e.getErrorCode() == 1451) {
                throw AppException.conflito("Nao e possivel excluir: o fornecedor abastece roupas do catalogo.");
            }
            throw e;
        }
    }

    private void validar(Dados d) {
        exigir(d != null && !vazio(d.nome()), "Informe o nome do fornecedor.");
    }
}
