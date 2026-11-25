package uptown;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import io.javalin.Javalin;
import io.javalin.http.Context;
import io.javalin.http.staticfiles.Location;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.Map;
import uptown.dao.CategoriaDao;
import uptown.dao.ClienteDao;
import uptown.dao.ConsultaDao;
import uptown.dao.DashboardDao;
import uptown.dao.FornecedorDao;
import uptown.dao.PedidoDao;
import uptown.dao.RotinaDao;
import uptown.dao.RoupaDao;

/** Servidor web: API REST (JSON) sobre os DAOs + arquivos estaticos da interface (resources/public). */
public final class Main {

    private static final Gson GSON = new GsonBuilder().serializeNulls().create();

    private static final ClienteDao clientes = new ClienteDao();
    private static final FornecedorDao fornecedores = new FornecedorDao();
    private static final CategoriaDao categorias = new CategoriaDao();
    private static final PedidoDao pedidos = new PedidoDao();
    private static final RoupaDao roupas = new RoupaDao();
    private static final ConsultaDao consultas = new ConsultaDao();
    private static final DashboardDao dashboard = new DashboardDao();
    private static final RotinaDao rotinas = new RotinaDao();

    public static void main(String[] args) {
        int porta = Integer.parseInt(Db.config("server.port"));

        Javalin app = Javalin.create(cfg -> {
            cfg.staticFiles.add("/public", Location.CLASSPATH);
            cfg.showJavalinBanner = false;
        });

        // ---- Dashboard ----
        app.get("/api/dashboard", ctx -> json(ctx, dashboard.painel(parametros(ctx))));

        // ---- Clientes ----
        app.get("/api/clientes", ctx -> json(ctx, clientes.listar()));
        app.post("/api/clientes", ctx -> criado(ctx, clientes.criar(corpo(ctx, ClienteDao.Dados.class))));
        app.put("/api/clientes/{id}", ctx -> {
            clientes.atualizar(id(ctx), corpo(ctx, ClienteDao.Dados.class));
            ok(ctx);
        });
        app.delete("/api/clientes/{id}", ctx -> {
            clientes.deletar(id(ctx));
            ok(ctx);
        });

        // ---- Fornecedores ----
        app.get("/api/fornecedores", ctx -> json(ctx, fornecedores.listar()));
        app.post("/api/fornecedores", ctx -> criado(ctx, fornecedores.criar(corpo(ctx, FornecedorDao.Dados.class))));
        app.put("/api/fornecedores/{id}", ctx -> {
            fornecedores.atualizar(id(ctx), corpo(ctx, FornecedorDao.Dados.class));
            ok(ctx);
        });
        app.delete("/api/fornecedores/{id}", ctx -> {
            fornecedores.deletar(id(ctx));
            ok(ctx);
        });

        // ---- Categorias ----
        app.get("/api/categorias", ctx -> json(ctx, categorias.listar()));
        app.post("/api/categorias", ctx -> criado(ctx, categorias.criar(corpo(ctx, CategoriaDao.Dados.class))));
        app.put("/api/categorias/{id}", ctx -> {
            categorias.atualizar(id(ctx), corpo(ctx, CategoriaDao.Dados.class));
            ok(ctx);
        });
        app.delete("/api/categorias/{id}", ctx -> {
            categorias.deletar(id(ctx));
            ok(ctx);
        });

        // ---- Roupas (catalogo, leitura) ----
        app.get("/api/roupas", ctx -> json(ctx, roupas.listar()));

        // ---- Pedidos ----
        app.get("/api/pedidos", ctx -> json(ctx, pedidos.listar()));
        app.get("/api/pedidos/{id}/itens", ctx -> json(ctx, pedidos.itens(id(ctx))));
        app.post("/api/pedidos", ctx -> criado(ctx, pedidos.criar(corpo(ctx, PedidoDao.Dados.class))));
        app.patch("/api/pedidos/{id}/status", ctx -> {
            Map<?, ?> b = corpo(ctx, Map.class);
            pedidos.atualizarStatus(id(ctx), b == null ? null : (String) b.get("status"));
            ok(ctx);
        });
        app.post("/api/pedidos/{id}/itens", ctx -> {
            pedidos.adicionarItem(id(ctx), corpo(ctx, PedidoDao.Item.class));
            ctx.status(201);
            ok(ctx);
        });
        app.delete("/api/pedidos/{id}", ctx -> {
            pedidos.deletar(id(ctx));
            ok(ctx);
        });

        // ---- Rotinas da Etapa 5 (funcoes, procedures, trigger/log) ----
        app.get("/api/rotinas/total-pedido/{id}", ctx -> json(ctx, rotinas.totalPedido(id(ctx))));
        app.get("/api/rotinas/unidades-roupa/{id}", ctx -> json(ctx, rotinas.unidadesRoupa(id(ctx))));
        app.get("/api/rotinas/caixas", ctx -> json(ctx, rotinas.planejarCaixas(
                inteiro(ctx.queryParam("pedido"), "Informe o pedido."),
                inteiro(ctx.queryParam("capacidade"), "Informe a capacidade da caixa."))));
        app.get("/api/auditoria", ctx -> json(ctx, rotinas.auditoria()));

        // ---- Consultas ----
        app.get("/api/consultas", ctx -> json(ctx, consultas.listar()));
        app.get("/api/consultas/{id}", ctx -> {
            Map<String, String> valores = new LinkedHashMap<>();
            ctx.queryParamMap().forEach((k, v) -> valores.put(k, v.isEmpty() ? "" : v.get(0)));
            json(ctx, consultas.executar(id(ctx), valores));
        });

        // ---- Erros -> JSON {"erro": "..."} ----
        app.exception(AppException.class, (e, ctx) -> erro(ctx, e.status(), e.getMessage()));
        app.exception(SQLException.class, (e, ctx) -> {
            int cod = e.getErrorCode();
            if (cod == 1062) erro(ctx, 409, "Ja existe um registro com este valor unico (e-mail ou nome repetido).");
            else if (cod == 1452) erro(ctx, 409, "Referencia invalida: o registro relacionado (cliente, roupa ou categoria) nao existe.");
            else if (cod == 3819) erro(ctx, 400, "Valor recusado por uma regra do banco (CHECK): confira os campos.");
            else if (cod == 1644) erro(ctx, 409, e.getMessage()); // SIGNAL das procedures/triggers da Etapa 5
            else if (cod == 1451) erro(ctx, 409, "O registro e usado por outros dados e nao pode ser removido.");
            else erro(ctx, 500, "Erro de banco de dados: " + e.getMessage());
        });
        app.exception(Exception.class, (e, ctx) -> {
            e.printStackTrace();
            erro(ctx, 500, "Erro inesperado: " + e.getMessage());
        });

        app.start(porta);
        System.out.println("UpTown rodando em http://localhost:" + porta);
    }

    // -------- utilitarios --------

    private static Map<String, String> parametros(Context ctx) {
        Map<String, String> valores = new LinkedHashMap<>();
        ctx.queryParamMap().forEach((k, v) -> valores.put(k, v.isEmpty() ? "" : v.get(0)));
        return valores;
    }

    private static int inteiro(String s, String msg) {
        try {
            return Integer.parseInt(s == null ? "" : s.trim());
        } catch (NumberFormatException e) {
            throw AppException.invalido(msg);
        }
    }

    private static int id(Context ctx) {
        try {
            return Integer.parseInt(ctx.pathParam("id"));
        } catch (NumberFormatException e) {
            throw AppException.invalido("Identificador invalido.");
        }
    }

    private static <T> T corpo(Context ctx, Class<T> tipo) {
        try {
            return GSON.fromJson(ctx.body(), tipo);
        } catch (RuntimeException e) {
            throw AppException.invalido("Corpo da requisicao invalido.");
        }
    }

    private static void json(Context ctx, Object o) {
        ctx.contentType("application/json; charset=utf-8").result(GSON.toJson(o));
    }

    private static void criado(Context ctx, long id) {
        ctx.status(201);
        json(ctx, Map.of("codigo", id));
    }

    private static void ok(Context ctx) {
        json(ctx, Map.of("ok", true));
    }

    private static void erro(Context ctx, int status, String msg) {
        ctx.status(status);
        json(ctx, Map.of("erro", msg));
    }
}
