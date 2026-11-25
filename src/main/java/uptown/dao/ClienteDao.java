package uptown.dao;

import static uptown.AppException.exigir;
import static uptown.AppException.vazio;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import uptown.AppException;
import uptown.Db;

/** CRUD da tabela Cliente (RF05). Todo SQL e explicito. */
public final class ClienteDao {

    public record Dados(String nome, String email, String rua, Integer numero, String bairro) {}

    private static final String SQL_LISTAR = """
            SELECT codigo_cliente, nome, email, rua, numero, bairro
            FROM Cliente
            ORDER BY nome
            """;

    private static final String SQL_INSERIR = """
            INSERT INTO Cliente (nome, email, rua, numero, bairro)
            VALUES (?, ?, ?, ?, ?)
            """;

    private static final String SQL_ATUALIZAR = """
            UPDATE Cliente
            SET nome = ?, email = ?, rua = ?, numero = ?, bairro = ?
            WHERE codigo_cliente = ?
            """;

    private static final String SQL_DELETAR = "DELETE FROM Cliente WHERE codigo_cliente = ?";

    public List<Map<String, Object>> listar() throws SQLException {
        return Db.query(SQL_LISTAR);
    }

    public long criar(Dados d) throws SQLException {
        validar(d);
        return Db.insert(SQL_INSERIR, d.nome().trim(), d.email().trim(), d.rua().trim(), d.numero(), d.bairro().trim());
    }

    public void atualizar(int id, Dados d) throws SQLException {
        validar(d);
        int n = Db.update(SQL_ATUALIZAR, d.nome().trim(), d.email().trim(), d.rua().trim(), d.numero(), d.bairro().trim(), id);
        if (n == 0) throw AppException.naoEncontrado("Cliente " + id + " nao encontrado.");
    }

    public void deletar(int id) throws SQLException {
        try {
            int n = Db.update(SQL_DELETAR, id);
            if (n == 0) throw AppException.naoEncontrado("Cliente " + id + " nao encontrado.");
        } catch (SQLException e) {
            if (e.getErrorCode() == 1451) {
                throw AppException.conflito("Nao e possivel excluir: o cliente possui pedidos registrados.");
            }
            throw e;
        }
    }

    private void validar(Dados d) {
        exigir(d != null, "Dados do cliente nao informados.");
        exigir(!vazio(d.nome()), "Informe o nome.");
        exigir(!vazio(d.email()) && d.email().contains("@"), "Informe um e-mail valido.");
        exigir(!vazio(d.rua()), "Informe a rua.");
        exigir(d.numero() != null && d.numero() > 0, "Informe o numero do endereco.");
        exigir(!vazio(d.bairro()), "Informe o bairro.");
    }
}
