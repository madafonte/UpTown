package uptown.dao;

import static uptown.AppException.exigir;
import static uptown.AppException.vazio;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.Map;
import java.util.Set;
import uptown.AppException;
import uptown.Db;

/**
 * Pedidos e itens de pedido (RF06, RF07). Criar/excluir um pedido mexe em
 * duas tabelas (Pedido + ItemPedido), portanto usa transacao.
 */
public final class PedidoDao {

    public record Item(Integer codigoRoupa, Integer quantidade, BigDecimal precoUnitario) {}

    public record Dados(Integer codigoCliente, String dataPedido, String status, List<Item> itens) {}

    public static final Set<String> STATUS = Set.of("Em separação", "A caminho", "Entregue", "Cancelado");

    private static final String SQL_LISTAR = """
            SELECT p.codigo_pedido, p.codigo_cliente, c.nome AS cliente, p.data_pedido, p.status, p.valor_total,
                   (SELECT COUNT(*) FROM ItemPedido i WHERE i.codigo_pedido = p.codigo_pedido) AS itens,
                   fn_total_itens_pedido(p.codigo_pedido) AS total_itens_fn
            FROM Pedido p
            JOIN Cliente c ON c.codigo_cliente = p.codigo_cliente
            ORDER BY p.data_pedido DESC, p.codigo_pedido DESC
            """;

    private static final String SQL_ITENS = """
            SELECT i.codigo_item, i.codigo_roupa, r.nome AS roupa, i.quantidade, i.preco_unitario,
                   i.quantidade * i.preco_unitario AS subtotal
            FROM ItemPedido i
            JOIN Roupa r ON r.codigo_roupa = i.codigo_roupa
            WHERE i.codigo_pedido = ?
            ORDER BY i.codigo_item
            """;

    private static final String SQL_INSERIR_PEDIDO = """
            INSERT INTO Pedido (codigo_cliente, data_pedido, status, valor_total)
            VALUES (?, ?, ?, ?)
            """;

    private static final String SQL_INSERIR_ITEM = """
            INSERT INTO ItemPedido (codigo_pedido, codigo_roupa, quantidade, preco_unitario)
            VALUES (?, ?, ?, ?)
            """;

    /** A regra de transicao de status esta na procedure (Etapa 5); o trigger trg_pedido_log_status grava o log. */
    private static final String SQL_STATUS = "CALL sp_atualizar_status_pedido(?, ?)";

    /** Recalcula o total do cabecalho com a funcao fn_total_itens_pedido. */
    private static final String SQL_RECALCULAR_TOTAL =
            "UPDATE Pedido SET valor_total = fn_total_itens_pedido(codigo_pedido) WHERE codigo_pedido = ?";

    private static final String SQL_DELETAR_ITENS = "DELETE FROM ItemPedido WHERE codigo_pedido = ?";

    private static final String SQL_DELETAR = "DELETE FROM Pedido WHERE codigo_pedido = ?";

    public List<Map<String, Object>> listar() throws SQLException {
        return Db.query(SQL_LISTAR);
    }

    public List<Map<String, Object>> itens(int codigoPedido) throws SQLException {
        return Db.query(SQL_ITENS, codigoPedido);
    }

    public long criar(Dados d) throws SQLException {
        exigir(d != null, "Dados do pedido nao informados.");
        exigir(d.codigoCliente() != null, "Selecione o cliente.");
        exigir(d.itens() != null && !d.itens().isEmpty(), "O pedido precisa de ao menos um item.");
        String status = vazio(d.status()) ? "Em separação" : d.status();
        exigir(STATUS.contains(status), "Status invalido.");
        LocalDate data;
        try {
            data = vazio(d.dataPedido()) ? LocalDate.now() : LocalDate.parse(d.dataPedido());
        } catch (DateTimeParseException e) {
            throw AppException.invalido("Data invalida (use AAAA-MM-DD).");
        }

        BigDecimal total = BigDecimal.ZERO;
        for (Item it : d.itens()) {
            exigir(it.codigoRoupa() != null, "Selecione a roupa de cada item.");
            exigir(it.quantidade() != null && it.quantidade() > 0, "A quantidade de cada item deve ser maior que zero.");
            exigir(it.precoUnitario() != null && it.precoUnitario().signum() >= 0, "Informe o preco unitario de cada item.");
            total = total.add(it.precoUnitario().multiply(BigDecimal.valueOf(it.quantidade())));
        }

        try (Connection c = Db.open()) {
            c.setAutoCommit(false);
            try {
                // O trigger trg_item_impede_pedido_cancelado proibe itens em pedido Entregue/Cancelado,
                // entao o pedido nasce "Em separação" e so depois recebe o status pedido (via procedure).
                long id = Db.insert(c, SQL_INSERIR_PEDIDO, d.codigoCliente(), data, "Em separação", total);
                for (Item it : d.itens()) {
                    Db.insert(c, SQL_INSERIR_ITEM, id, it.codigoRoupa(), it.quantidade(), it.precoUnitario());
                }
                if (!"Em separação".equals(status)) Db.update(c, SQL_STATUS, id, status);
                c.commit();
                return id;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }

    /** Chama sp_atualizar_status_pedido; erros da procedure (SQLSTATE 45000) voltam como mensagem ao usuario. */
    public void atualizarStatus(int id, String status) throws SQLException {
        Db.update(SQL_STATUS, id, status);
    }

    /**
     * Inclui um item num pedido ja existente. Se o pedido estiver Entregue/Cancelado o trigger
     * trg_item_impede_pedido_cancelado recusa o INSERT (erro 1644) e nada e gravado.
     */
    public void adicionarItem(int pedido, Item it) throws SQLException {
        exigir(it != null && it.codigoRoupa() != null, "Selecione a roupa.");
        exigir(it.quantidade() != null && it.quantidade() > 0, "A quantidade deve ser maior que zero.");
        exigir(it.precoUnitario() != null && it.precoUnitario().signum() >= 0, "Informe o preco unitario.");
        try (Connection c = Db.open()) {
            c.setAutoCommit(false);
            try {
                Db.insert(c, SQL_INSERIR_ITEM, pedido, it.codigoRoupa(), it.quantidade(), it.precoUnitario());
                Db.update(c, SQL_RECALCULAR_TOTAL, pedido);
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
                Db.update(c, SQL_DELETAR_ITENS, id);
                int n = Db.update(c, SQL_DELETAR, id);
                if (n == 0) throw AppException.naoEncontrado("Pedido " + id + " nao encontrado.");
                c.commit();
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            }
        }
    }
}
