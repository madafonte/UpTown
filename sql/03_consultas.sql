-- =====================================================================
-- UpTown - Marketplace de Roupas | Entrega 3
-- Script 03: consultas da aplicacao (8 consultas)
--
-- Sao exatamente os mesmos comandos SQL que a aplicacao Java executa via
-- JDBC (uptown/dao/ConsultaDao.java). Aqui os parametros "?" da aplicacao
-- aparecem como variaveis de sessao (@nome) definidas com SET logo acima de
-- cada consulta, para que o script possa ser rodado direto no MySQL.
--
-- Cada consulta responde a uma das "Perguntas/Relatorios Importantes" da
-- Entrega 1 (a referencia RFxx e o requisito funcional correspondente).
-- Requer MySQL 8.0+ (CTE recursiva e funcoes de janela).
-- =====================================================================
USE Uptown;
SET NAMES utf8mb4;


-- ---------------------------------------------------------------------
-- CONSULTA 1 - Roupas de uma categoria, incluindo suas subcategorias (RF08)
-- Perguntas 1 e 2 do minimundo.
-- Tecnica: CTE RECURSIVA percorrendo o auto-relacionamento Pertence
--          (categoria pai -> filha) + JOIN de 3 tabelas.
--          UNION (e nao UNION ALL) elimina duplicatas, pois a categoria 11
--          aparece como filha de 2 pais na base de dados.
-- Parametro: @categoria (1 = "Roupas" traz tudo; 2 = "Camisetas"; 5 = "Casacos")
-- ---------------------------------------------------------------------
SET @categoria = 2;

WITH RECURSIVE arvore (codigo_categoria) AS (
    SELECT codigo_categoria
    FROM Categoria
    WHERE codigo_categoria = @categoria
    UNION
    SELECT p.codigo_categoria_filha
    FROM Pertence p
    JOIN arvore a ON p.codigo_categoria_pai = a.codigo_categoria
)
SELECT r.codigo_roupa, r.nome AS roupa, r.tamanho, r.sexo, c.nome AS categoria
FROM Roupa r
JOIN Categoria c ON c.codigo_categoria = r.categoria_codigo_roupa
JOIN arvore a    ON a.codigo_categoria = c.codigo_categoria
ORDER BY c.nome, r.nome;


-- ---------------------------------------------------------------------
-- CONSULTA 2 - Cores e fornecedores de cada roupa (RF09, RF10)
-- Perguntas 3 e 4 do minimundo.
-- Tecnica: subconsultas correlacionadas com JOIN + GROUP_CONCAT (uma linha
--          por roupa, sem produto cartesiano cor x fornecedor) e COALESCE
--          para roupas sem cor ou sem fornecedor cadastrado.
-- Parametro: @nome (parte do nome da roupa; '' = todas)
-- ---------------------------------------------------------------------
SET @nome = 'Polo';

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
WHERE r.nome LIKE CONCAT('%', @nome, '%')
ORDER BY r.codigo_roupa;


-- ---------------------------------------------------------------------
-- CONSULTA 3 - Historico de pedidos de um cliente (RF11)
-- Pergunta 5 do minimundo.
-- Tecnica: JOIN de 3 tabelas (Cliente, Pedido, ItemPedido) + GROUP BY +
--          SUM(quantidade * preco_unitario). LEFT JOIN em ItemPedido para
--          nao esconder um pedido que (por algum motivo) esteja sem itens.
-- Parametro: @cliente (codigo do cliente)
-- ---------------------------------------------------------------------
SET @cliente = 5;

SELECT c.nome AS cliente, p.codigo_pedido, p.data_pedido, p.status,
       COUNT(i.codigo_item) AS itens,
       COALESCE(SUM(i.quantidade), 0) AS unidades,
       COALESCE(SUM(i.quantidade * i.preco_unitario), 0) AS valor_total
FROM Cliente c
JOIN Pedido p          ON p.codigo_cliente = c.codigo_cliente
LEFT JOIN ItemPedido i ON i.codigo_pedido  = p.codigo_pedido
WHERE c.codigo_cliente = @cliente
GROUP BY c.nome, p.codigo_pedido, p.data_pedido, p.status
ORDER BY p.data_pedido DESC, p.codigo_pedido DESC;


-- ---------------------------------------------------------------------
-- CONSULTA 4 - Unidades vendidas por roupa, com ranking (RF12)
-- Pergunta 6 do minimundo.
-- Tecnica: LEFT JOIN (mantem roupas sem venda) + GROUP BY + HAVING +
--          funcao de janela RANK() (empates recebem a mesma posicao).
-- Parametro: @minimo (minimo de unidades vendidas; 0 = lista todas as roupas)
-- ---------------------------------------------------------------------
SET @minimo = 1;

SELECT r.codigo_roupa, r.nome AS roupa,
       COALESCE(SUM(i.quantidade), 0) AS unidades_vendidas,
       RANK() OVER (ORDER BY COALESCE(SUM(i.quantidade), 0) DESC) AS ranking
FROM Roupa r
LEFT JOIN ItemPedido i ON i.codigo_roupa = r.codigo_roupa
GROUP BY r.codigo_roupa, r.nome
HAVING unidades_vendidas >= @minimo
ORDER BY ranking, r.nome;


-- ---------------------------------------------------------------------
-- CONSULTA 5 - Faturamento por status e periodo (RF13)
-- Pergunta 7 do minimundo.
-- Tecnica: JOIN + GROUP BY ... WITH ROLLUP (gera a linha de TOTAL GERAL) +
--          GROUPING() para identificar essa linha + filtros opcionais
--          (NULL = sem filtro) por status e por intervalo de datas.
-- Parametros: @status ('Entregue', 'A caminho', 'Em separação', 'Cancelado' ou NULL),
--             @inicio e @fim (formato 'AAAA-MM-DD' ou NULL)
-- ---------------------------------------------------------------------
SET @status = NULL;
SET @inicio = '2026-02-01';
SET @fim    = '2026-04-30';

SELECT IF(GROUPING(p.status), 'TOTAL GERAL', p.status) AS status,
       COUNT(DISTINCT p.codigo_pedido) AS pedidos,
       SUM(i.quantidade) AS unidades,
       SUM(i.quantidade * i.preco_unitario) AS faturamento,
       ROUND(SUM(i.quantidade * i.preco_unitario) / COUNT(DISTINCT p.codigo_pedido), 2) AS ticket_medio
FROM Pedido p
JOIN ItemPedido i ON i.codigo_pedido = p.codigo_pedido
WHERE (@status IS NULL OR p.status = @status)
  AND p.data_pedido >= COALESCE(CAST(@inicio AS DATE), '1000-01-01')
  AND p.data_pedido <= COALESCE(CAST(@fim AS DATE), '9999-12-31')
GROUP BY p.status WITH ROLLUP
ORDER BY GROUPING(p.status), faturamento DESC;


-- ---------------------------------------------------------------------
-- CONSULTA 6 - Roupas que nunca foram vendidas
-- Pergunta 8 do minimundo.
-- Tecnica: anti-join com NOT EXISTS (subconsulta correlacionada) + JOIN.
-- ---------------------------------------------------------------------
SELECT r.codigo_roupa, r.nome AS roupa, r.tamanho, r.sexo, c.nome AS categoria
FROM Roupa r
JOIN Categoria c ON c.codigo_categoria = r.categoria_codigo_roupa
WHERE NOT EXISTS (SELECT 1
                    FROM ItemPedido i
                   WHERE i.codigo_roupa = r.codigo_roupa)
ORDER BY c.nome, r.nome;


-- ---------------------------------------------------------------------
-- CONSULTA 7 - Clientes que gastam acima da media (pedidos cancelados ignorados)
-- Consulta analitica de maior dificuldade.
-- Tecnica: CTE (gasto por cliente) reutilizada 3 vezes + subconsulta escalar
--          (AVG) no SELECT e no WHERE + DENSE_RANK() OVER (posicao sem "buracos").
-- ---------------------------------------------------------------------
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
ORDER BY posicao, g.nome;


-- ---------------------------------------------------------------------
-- CONSULTA 8 - Vendas por tipo de roupa (especializacao Camisa / Calca / Casaco)
-- Tecnica: UNION ALL de 3 JOINs (Roupa x cada subtipo) formando uma tabela
--          derivada, depois JOIN com ItemPedido + GROUP BY.
-- ---------------------------------------------------------------------
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
ORDER BY faturamento DESC;
