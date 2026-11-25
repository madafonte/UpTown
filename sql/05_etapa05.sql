USE Uptown;
SET NAMES utf8mb4;

CREATE TABLE LogStatusPedido (
    codigo_log BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    codigo_pedido INT NOT NULL,
    status_anterior VARCHAR(30) NOT NULL,
    status_novo VARCHAR(30) NOT NULL,
    data_alteracao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_banco VARCHAR(288) NOT NULL
);

DELIMITER $$

CREATE FUNCTION fn_total_itens_pedido(p_pedido INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_total DECIMAL(12,2) DEFAULT 0;
    SELECT COUNT(*) INTO v_existe FROM Pedido WHERE codigo_pedido = p_pedido;
    IF v_existe = 0 THEN
        RETURN NULL;
    END IF;
    SELECT COALESCE(SUM(quantidade * preco_unitario), 0)
      INTO v_total FROM ItemPedido WHERE codigo_pedido = p_pedido;
    RETURN v_total;
END$$

CREATE FUNCTION fn_unidades_vendidas_ativas(p_roupa INT)
RETURNS BIGINT
READS SQL DATA
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_unidades BIGINT DEFAULT 0;
    SELECT COUNT(*) INTO v_existe FROM Roupa WHERE codigo_roupa = p_roupa;
    IF v_existe = 0 THEN RETURN NULL; END IF;
    SELECT COALESCE(SUM(i.quantidade), 0) INTO v_unidades
      FROM ItemPedido i JOIN Pedido p ON p.codigo_pedido = i.codigo_pedido
     WHERE i.codigo_roupa = p_roupa AND p.status <> 'Cancelado';
    RETURN v_unidades;
END$$

CREATE PROCEDURE sp_atualizar_status_pedido(IN p_pedido INT, IN p_status VARCHAR(30))
BEGIN
    IF p_status IS NULL OR p_status NOT IN ('Em separação', 'A caminho', 'Entregue', 'Cancelado') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status de pedido inválido';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Pedido WHERE codigo_pedido = p_pedido) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido não encontrado';
    END IF;
    IF EXISTS (SELECT 1 FROM Pedido
                WHERE codigo_pedido = p_pedido
                  AND status IN ('Entregue', 'Cancelado')
                  AND status <> p_status) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido entregue ou cancelado não pode mudar de status';
    END IF;
    UPDATE Pedido SET status = p_status WHERE codigo_pedido = p_pedido;
END$$

CREATE PROCEDURE sp_planejar_caixas(IN p_pedido INT, IN p_capacidade INT)
BEGIN
    DECLARE v_fim BOOLEAN DEFAULT FALSE;
    DECLARE v_item INT;
    DECLARE v_roupa INT;
    DECLARE v_quantidade INT;
    DECLARE v_restante INT;
    DECLARE v_caixa INT DEFAULT 1;
    DECLARE v_livre INT;
    DECLARE v_alocada INT;
    DECLARE cur_itens CURSOR FOR
        SELECT codigo_item, codigo_roupa, quantidade FROM ItemPedido
         WHERE codigo_pedido = p_pedido ORDER BY codigo_item;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fim = TRUE;

    IF p_capacidade IS NULL OR p_capacidade <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Capacidade deve ser positiva';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Pedido WHERE codigo_pedido = p_pedido) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido não encontrado';
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_plano_caixas;
    CREATE TEMPORARY TABLE tmp_plano_caixas (
        numero_caixa INT NOT NULL,
        codigo_item INT NOT NULL,
        codigo_roupa INT NOT NULL,
        quantidade INT NOT NULL
    );
    SET v_livre = p_capacidade;
    OPEN cur_itens;
    loop_itens: LOOP
        FETCH cur_itens INTO v_item, v_roupa, v_quantidade;
        IF v_fim THEN LEAVE loop_itens; END IF;
        SET v_restante = v_quantidade;
        WHILE v_restante > 0 DO
            IF v_livre = 0 THEN
                SET v_caixa = v_caixa + 1;
                SET v_livre = p_capacidade;
            END IF;
            SET v_alocada = LEAST(v_restante, v_livre);
            INSERT INTO tmp_plano_caixas VALUES (v_caixa, v_item, v_roupa, v_alocada);
            SET v_restante = v_restante - v_alocada;
            SET v_livre = v_livre - v_alocada;
        END WHILE;
    END LOOP;
    CLOSE cur_itens;
    SELECT numero_caixa, codigo_item, codigo_roupa, quantidade
      FROM tmp_plano_caixas ORDER BY numero_caixa, codigo_item;
END$$

CREATE TRIGGER trg_pedido_log_status
AFTER UPDATE ON Pedido FOR EACH ROW
BEGIN
    IF NOT (OLD.status <=> NEW.status) THEN
        INSERT INTO LogStatusPedido (codigo_pedido, status_anterior, status_novo, usuario_banco)
        VALUES (NEW.codigo_pedido, OLD.status, NEW.status, USER());
    END IF;
END$$

CREATE TRIGGER trg_item_impede_pedido_cancelado
BEFORE INSERT ON ItemPedido FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM Pedido WHERE codigo_pedido = NEW.codigo_pedido AND status IN ('Entregue', 'Cancelado')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Não é permitido incluir itens em pedido entregue ou cancelado';
    END IF;
END$$
DELIMITER ;
