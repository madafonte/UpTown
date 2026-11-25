-- =====================================================================
-- UpTown | Etapa 04 - Consultas Avancadas, Visões e Índices
-- Banco: MySQL 8.0+
--
-- Pré-requisito: banco Uptown criado e populado pelos scripts 01_schema.sql
-- e 02_dados.sql da Entrega 3. Execute este arquivo uma vez depois deles.
-- Este arquivo não apaga nem recria o banco.
-- =====================================================================

USE Uptown;
SET NAMES utf8mb4;


-- =====================================================================
-- 1. ÍNDICES
-- Os índices são compostos para atender padrões de acesso usados abaixo.
-- O otimizador pode preferir uma varredura em tabelas pequenas; em bases
-- maiores, confirme a escolha com EXPLAIN após carregar dados representativos.
-- =====================================================================

-- Consultas de faturamento filtram pedidos por intervalo de data e status.
-- data_pedido é a primeira coluna para a busca por período; status permite
-- filtrar os registros encontrados sem voltar à tabela em vários planos.
CREATE INDEX idx_pedido_data_status
    ON Pedido (data_pedido, status);

-- Consultas e a view de desempenho agrupam itens por roupa e calculam
-- unidades/faturamento; codigo_pedido também atende a associação com Pedido.
-- As colunas finais permitem que os cálculos do item sejam lidos pelo índice.
CREATE INDEX idx_itempedido_roupa_pedido_valores
    ON ItemPedido (codigo_roupa, codigo_pedido, quantidade, preco_unitario);


-- =====================================================================
-- 2. QUATRO CONSULTAS NOVAS
-- =====================================================================

-- ---------------------------------------------------------------------
-- CONSULTA 1 - Clientes sem pedidos em um intervalo (anti-join à esquerda)
-- Pergunta: quais clientes não fizeram pedidos no período informado?
-- O período é semiaberto [início, fim_exclusivo), evitando ambiguidade na
-- fronteira e facilitando a inclusão de meses completos.
-- ---------------------------------------------------------------------
SET @periodo_inicio = '2026-03-01';
SET @periodo_fim_exclusivo = '2026-04-01';

SELECT c.codigo_cliente,
       c.nome AS cliente,
       c.email
FROM Cliente c
LEFT JOIN Pedido p
       ON p.codigo_cliente = c.codigo_cliente
      AND p.data_pedido >= @periodo_inicio
      AND p.data_pedido <  @periodo_fim_exclusivo
WHERE p.codigo_pedido IS NULL
ORDER BY c.nome;


-- ---------------------------------------------------------------------
-- CONSULTA 2 - Conciliação de roupas vendidas e roupas com fornecedor
-- Técnica: FULL OUTER JOIN emulado com LEFT JOIN + segundo LEFT JOIN que
-- retorna apenas as linhas sem correspondência + UNION ALL.
-- MySQL 8.0 não implementa FULL OUTER JOIN nativamente.
-- A venda considera pedidos não cancelados. NULL nas métricas indica que
-- a roupa não pertence àquele conjunto (sem venda ativa ou sem fornecedor).
-- ---------------------------------------------------------------------
WITH vendas_roupa AS (
    SELECT i.codigo_roupa,
           SUM(i.quantidade) AS unidades_vendidas,
           SUM(i.quantidade * i.preco_unitario) AS faturamento_ativo,
           COUNT(DISTINCT p.codigo_pedido) AS pedidos_ativos
    FROM ItemPedido i
    JOIN Pedido p ON p.codigo_pedido = i.codigo_pedido
    WHERE p.status <> 'Cancelado'
    GROUP BY i.codigo_roupa
),
fornecedores_roupa AS (
    SELECT fo.codigo_roupa,
           GROUP_CONCAT(DISTINCT f.nome ORDER BY f.nome SEPARATOR ', ') AS fornecedores
    FROM Fornece fo
    JOIN Fornecedor f ON f.codigo_fornecedor = fo.codigo_fornecedor
    GROUP BY fo.codigo_roupa
),
conciliacao AS (
    -- Lado esquerdo: todas as roupas com venda ativa, correspondidas ou não.
    SELECT v.codigo_roupa,
           v.unidades_vendidas,
           v.faturamento_ativo,
           v.pedidos_ativos,
           f.fornecedores
    FROM vendas_roupa v
    LEFT JOIN fornecedores_roupa f ON f.codigo_roupa = v.codigo_roupa

    UNION ALL

    -- Lado direito exclusivo: roupas com fornecedor e sem venda ativa.
    SELECT f.codigo_roupa,
           v.unidades_vendidas,
           v.faturamento_ativo,
           v.pedidos_ativos,
           f.fornecedores
    FROM fornecedores_roupa f
    LEFT JOIN vendas_roupa v ON v.codigo_roupa = f.codigo_roupa
    WHERE v.codigo_roupa IS NULL
)
SELECT r.codigo_roupa,
       r.nome AS roupa,
       c.unidades_vendidas,
       c.faturamento_ativo,
       c.pedidos_ativos,
       c.fornecedores,
       CASE
           WHEN c.unidades_vendidas IS NULL THEN 'Fornecedor sem venda ativa'
           WHEN c.fornecedores IS NULL THEN 'Venda ativa sem fornecedor'
           ELSE 'Venda ativa e fornecedor'
       END AS situacao
FROM conciliacao c
JOIN Roupa r ON r.codigo_roupa = c.codigo_roupa
ORDER BY r.codigo_roupa;


-- ---------------------------------------------------------------------
-- CONSULTA 3 - Roupas acima da média de unidades vendidas da categoria
-- Técnica: subconsulta escalar correlacionada. A média inclui todas as
-- roupas da mesma categoria, inclusive as que não tiveram venda ativa
-- (zero unidades). Pedidos cancelados não contam como venda.
-- ---------------------------------------------------------------------
WITH vendas_por_roupa AS (
    SELECT r.codigo_roupa,
           r.nome AS roupa,
           r.categoria_codigo_roupa,
           c.nome AS categoria,
           COALESCE(SUM(
               CASE
                   WHEN p.codigo_pedido IS NOT NULL
                    AND p.status <> 'Cancelado' THEN i.quantidade
                   ELSE 0
               END
           ), 0) AS unidades_vendidas
    FROM Roupa r
    JOIN Categoria c ON c.codigo_categoria = r.categoria_codigo_roupa
    LEFT JOIN ItemPedido i ON i.codigo_roupa = r.codigo_roupa
    LEFT JOIN Pedido p ON p.codigo_pedido = i.codigo_pedido
    GROUP BY r.codigo_roupa, r.nome,
             r.categoria_codigo_roupa, c.nome
)
SELECT v.codigo_roupa,
       v.roupa,
       v.categoria,
       v.unidades_vendidas,
       (SELECT AVG(v2.unidades_vendidas)
          FROM vendas_por_roupa v2
         WHERE v2.categoria_codigo_roupa = v.categoria_codigo_roupa
       ) AS media_unidades_da_categoria
FROM vendas_por_roupa v
WHERE v.unidades_vendidas > (
    SELECT AVG(v2.unidades_vendidas)
    FROM vendas_por_roupa v2
    WHERE v2.categoria_codigo_roupa = v.categoria_codigo_roupa
)
ORDER BY v.categoria, v.unidades_vendidas DESC, v.roupa;


-- ---------------------------------------------------------------------
-- CONSULTA 4 - Categorias acima do faturamento médio no período
-- Técnica: subconsultas escalares sobre uma CTE agregada. A comparação é
-- feita somente entre categorias com faturamento ativo no período; pedidos
-- cancelados ficam fora. O intervalo é semiaberto [início, fim_exclusivo).
-- Este filtro usa idx_pedido_data_status.
-- ---------------------------------------------------------------------
SET @faturamento_inicio = '2026-01-01';
SET @faturamento_fim_exclusivo = '2027-01-01';

WITH faturamento_categoria AS (
    SELECT c.codigo_categoria,
           c.nome AS categoria,
           SUM(i.quantidade * i.preco_unitario) AS faturamento_ativo
    FROM Pedido p
    JOIN ItemPedido i ON i.codigo_pedido = p.codigo_pedido
    JOIN Roupa r ON r.codigo_roupa = i.codigo_roupa
    JOIN Categoria c ON c.codigo_categoria = r.categoria_codigo_roupa
    WHERE p.data_pedido >= @faturamento_inicio
      AND p.data_pedido <  @faturamento_fim_exclusivo
      AND p.status <> 'Cancelado'
    GROUP BY c.codigo_categoria, c.nome
)
SELECT fc.codigo_categoria,
       fc.categoria,
       fc.faturamento_ativo,
       (SELECT AVG(fc2.faturamento_ativo)
          FROM faturamento_categoria fc2
       ) AS media_faturamento_categorias
FROM faturamento_categoria fc
WHERE fc.faturamento_ativo > (
    SELECT AVG(fc2.faturamento_ativo)
    FROM faturamento_categoria fc2
)
ORDER BY fc.faturamento_ativo DESC;


-- =====================================================================
-- 3. DUAS VISÕES
-- =====================================================================

-- ---------------------------------------------------------------------
-- VIEW 1 - Detalhe de cada item comprado, com cliente, pedido e categoria
-- Justificativa semântica: no domínio da loja, o histórico de um pedido
-- precisa identificar quem comprou, quando, em que situação e qual roupa
-- foi registrada em cada item. A granularidade é uma linha por ItemPedido;
-- o valor_total do cabeçalho não é repetido para evitar somas duplicadas.
-- Cinco tabelas conectam cliente -> pedido -> item -> roupa -> categoria.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_detalhe_pedido_cliente AS
SELECT c.codigo_cliente,
       c.nome AS cliente,
       p.codigo_pedido,
       p.data_pedido,
       p.status AS status_pedido,
       i.codigo_item,
       r.codigo_roupa,
       r.nome AS roupa,
       cat.nome AS categoria,
       i.quantidade,
       i.preco_unitario,
       CAST(i.quantidade * i.preco_unitario AS DECIMAL(12, 2)) AS subtotal_item
FROM Cliente c
JOIN Pedido p ON p.codigo_cliente = c.codigo_cliente
JOIN ItemPedido i ON i.codigo_pedido = p.codigo_pedido
JOIN Roupa r ON r.codigo_roupa = i.codigo_roupa
JOIN Categoria cat ON cat.codigo_categoria = r.categoria_codigo_roupa;


-- ---------------------------------------------------------------------
-- VIEW 2 - Desempenho de vendas por roupa e categoria
-- Justificativa semântica: permite comparar o catálogo por categoria e
-- roupa, mantendo também itens sem venda. A contagem e os valores excluem
-- pedidos cancelados. A granularidade é uma linha por roupa, com unidades,
-- quantidade de pedidos ativos e faturamento ativo consolidados.
-- Quatro tabelas: Categoria -> Roupa -> ItemPedido -> Pedido.
-- idx_itempedido_roupa_pedido_valores atende o acesso aos itens por roupa.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_desempenho_vendas_roupa AS
SELECT cat.codigo_categoria,
       cat.nome AS categoria,
       r.codigo_roupa,
       r.nome AS roupa,
       r.tamanho,
       r.sexo,
       COUNT(DISTINCT CASE
           WHEN p.codigo_pedido IS NOT NULL AND p.status <> 'Cancelado'
           THEN p.codigo_pedido
       END) AS pedidos_ativos,
       COALESCE(SUM(CASE
           WHEN p.codigo_pedido IS NOT NULL AND p.status <> 'Cancelado'
           THEN i.quantidade
           ELSE 0
       END), 0) AS unidades_vendidas_ativas,
       COALESCE(SUM(CASE
           WHEN p.codigo_pedido IS NOT NULL AND p.status <> 'Cancelado'
           THEN i.quantidade * i.preco_unitario
           ELSE 0
       END), 0.00) AS faturamento_ativo
FROM Categoria cat
JOIN Roupa r ON r.categoria_codigo_roupa = cat.codigo_categoria
LEFT JOIN ItemPedido i ON i.codigo_roupa = r.codigo_roupa
LEFT JOIN Pedido p ON p.codigo_pedido = i.codigo_pedido
GROUP BY cat.codigo_categoria, cat.nome,
         r.codigo_roupa, r.nome, r.tamanho, r.sexo;


-- Exemplos opcionais para consultar as visões:
-- SELECT * FROM vw_detalhe_pedido_cliente ORDER BY data_pedido DESC, codigo_pedido;
-- SELECT * FROM vw_desempenho_vendas_roupa ORDER BY faturamento_ativo DESC, roupa;
