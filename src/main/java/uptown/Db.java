package uptown;

import java.io.IOException;
import java.io.InputStream;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;

/**
 * Camada de acesso ao MySQL via JDBC puro.
 * Nenhum SQL e gerado aqui: cada DAO escreve o seu comando SQL explicitamente
 * e apenas o entrega a estes metodos, que usam PreparedStatement (parametros
 * "?" protegem contra SQL injection).
 */
public final class Db {

    private static final Properties CFG = new Properties();

    static {
        try (InputStream in = Db.class.getResourceAsStream("/config.properties")) {
            CFG.load(in);
        } catch (IOException | NullPointerException e) {
            throw new IllegalStateException("config.properties nao encontrado", e);
        }
        // Permite sobrescrever por -D (ex.: -Ddb.password=xxx)
        for (String k : new String[]{"db.url", "db.user", "db.password", "server.port"}) {
            String v = System.getProperty(k);
            if (v != null) CFG.setProperty(k, v);
        }
    }

    private Db() {}

    public static String config(String key) {
        return CFG.getProperty(key);
    }

    public static Connection open() throws SQLException {
        return DriverManager.getConnection(CFG.getProperty("db.url"),
                CFG.getProperty("db.user"), CFG.getProperty("db.password", ""));
    }

    private static void bind(PreparedStatement ps, Object... params) throws SQLException {
        for (int i = 0; i < params.length; i++) {
            if (params[i] == null) ps.setNull(i + 1, Types.NULL);
            else ps.setObject(i + 1, params[i]);
        }
    }

    /** SELECT -> lista de linhas (coluna -> valor), na ordem das colunas. */
    public static List<Map<String, Object>> query(String sql, Object... params) throws SQLException {
        try (Connection c = open()) {
            return query(c, sql, params);
        }
    }

    public static List<Map<String, Object>> query(Connection c, String sql, Object... params) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement(sql)) {
            bind(ps, params);
            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData md = rs.getMetaData();
                int n = md.getColumnCount();
                List<Map<String, Object>> rows = new ArrayList<>();
                while (rs.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    for (int i = 1; i <= n; i++) {
                        row.put(md.getColumnLabel(i), normalize(rs.getObject(i)));
                    }
                    rows.add(row);
                }
                return rows;
            }
        }
    }

    /** Resultado de um SELECT com os nomes das colunas (mesmo quando nao ha linhas). */
    public record Table(List<String> columns, List<Map<String, Object>> rows) {}

    public static Table table(String sql, Object... params) throws SQLException {
        try (Connection c = open(); PreparedStatement ps = c.prepareStatement(sql)) {
            bind(ps, params);
            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData md = rs.getMetaData();
                int n = md.getColumnCount();
                List<String> cols = new ArrayList<>();
                for (int i = 1; i <= n; i++) cols.add(md.getColumnLabel(i));
                List<Map<String, Object>> rows = new ArrayList<>();
                while (rs.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    for (int i = 1; i <= n; i++) row.put(cols.get(i - 1), normalize(rs.getObject(i)));
                    rows.add(row);
                }
                return new Table(cols, rows);
            }
        }
    }

    /** SELECT que devolve uma unica linha (ou null). */
    public static Map<String, Object> queryOne(String sql, Object... params) throws SQLException {
        List<Map<String, Object>> rows = query(sql, params);
        return rows.isEmpty() ? null : rows.get(0);
    }

    /** Igual a queryOne, numa conexao ja aberta (necessario para tabelas temporarias). */
    public static Map<String, Object> queryOne(Connection c, String sql, Object... params) throws SQLException {
        List<Map<String, Object>> rows = query(c, sql, params);
        return rows.isEmpty() ? null : rows.get(0);
    }

    /** INSERT / UPDATE / DELETE -> numero de linhas afetadas. */
    public static int update(String sql, Object... params) throws SQLException {
        try (Connection c = open()) {
            return update(c, sql, params);
        }
    }

    public static int update(Connection c, String sql, Object... params) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement(sql)) {
            bind(ps, params);
            return ps.executeUpdate();
        }
    }

    /** INSERT devolvendo a chave AUTO_INCREMENT gerada. */
    public static long insert(Connection c, String sql, Object... params) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            bind(ps, params);
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                keys.next();
                return keys.getLong(1);
            }
        }
    }

    public static long insert(String sql, Object... params) throws SQLException {
        try (Connection c = open()) {
            return insert(c, sql, params);
        }
    }

    /** Datas viram texto ISO (yyyy-MM-dd) para o JSON. */
    private static Object normalize(Object v) {
        if (v instanceof java.sql.Date || v instanceof java.sql.Timestamp || v instanceof java.sql.Time
                || v instanceof java.time.temporal.TemporalAccessor) {
            return v.toString();
        }
        return v;
    }
}
