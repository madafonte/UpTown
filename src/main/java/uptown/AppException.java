package uptown;

/** Erro de negocio/validacao com o codigo HTTP que deve ser devolvido a interface. */
public class AppException extends RuntimeException {

    private final int status;

    public AppException(int status, String message) {
        super(message);
        this.status = status;
    }

    public int status() {
        return status;
    }

    public static AppException invalido(String msg) {
        return new AppException(400, msg);
    }

    public static AppException conflito(String msg) {
        return new AppException(409, msg);
    }

    public static AppException naoEncontrado(String msg) {
        return new AppException(404, msg);
    }

    /** Lanca 400 se a condicao for falsa. */
    public static void exigir(boolean condicao, String msg) {
        if (!condicao) throw invalido(msg);
    }

    public static boolean vazio(String s) {
        return s == null || s.isBlank();
    }
}
