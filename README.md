# UpTown — Marketplace de Roupas · Etapa 6 (versão final)

Aplicação web em **Java + JDBC + MySQL** para o minimundo da marca de roupas UpTown. Reúne tudo o que foi
construído nas etapas anteriores: CRUD, consultas e views (Etapas 3 e 4), funções, procedimentos e triggers
(Etapa 5) e um **dashboard estatístico interativo**. Toda comunicação com o banco usa **SQL explícito**
(`PreparedStatement`), sem ORM/JPA: os comandos estão como texto em `src/main/java/uptown/dao/*.java`.

## Mapa dos requisitos da Etapa 6

| Requisito | Onde está |
|---|---|
| CRUD em ao menos 4 tabelas | **Clientes**, **Fornecedores**, **Categorias** (grava também em `Pertence`), **Pedidos** (grava também em `ItemPedido`) |
| Funções da Etapa 5 | `fn_total_itens_pedido`: coluna "Soma dos itens (fn)" e detalhe de **Pedidos**; `fn_unidades_vendidas_ativas`: coluna "Unid. vendidas (fn)" no **Catálogo**. As duas também podem ser executadas à mão em **Funções e procedimentos** |
| Procedimentos da Etapa 5 | `sp_atualizar_status_pedido`: é o que muda o status em **Pedidos** (erros da procedure aparecem na tela). `sp_planejar_caixas`: tela **Funções e procedimentos** |
| Triggers da Etapa 5 | `trg_pedido_log_status`: cada mudança de status aparece em **Auditoria**. `trg_item_impede_pedido_cancelado`: em **Pedidos → Itens**, incluir item num pedido Entregue/Cancelado é recusado e a mensagem do banco aparece |
| Consultas e views (Etapas 3 e 4) | Aba **Consultas e visões**: 8 consultas da Etapa 3, 4 consultas e 2 views da Etapa 4, com parâmetros/filtros, indicadores, gráfico, tabela e o SQL |
| Dashboard: indicadores | 14 indicadores (total de pedidos, faturamento, média, mediana, moda, variância, desvio-padrão, mín/máx, % de cancelados, variação mensal, tendência, correlação…) |
| Dashboard: ao menos 6 gráficos | 9 gráficos: pizza, linha com tendência, 3 de barras, barras empilhadas, histograma, rosca, radar e dispersão |
| Dashboard: interatividade | Filtros de **data inicial/final**, **categoria** (inclui subcategorias) e **status**; tudo é recalculado por SQL |
| Dados vindos do banco | Todos os números e gráficos saem de SQL agregado (`GROUP BY`, `VAR_POP`, `STDDEV_POP`, funções de janela, CTEs) |

## Dashboard

Os filtros montam uma tabela temporária (`tmp_dash`, uma linha por item de pedido que atende ao filtro) e todos os
indicadores/gráficos são consultas agregadas sobre ela (`DashboardDao.java`). Detalhes:

- Pedidos **cancelados ficam fora das estatísticas** (faturamento, média, mediana…), exceto quando se filtra
  explicitamente por status. O gráfico de status mostra todos os pedidos do filtro.
- Variância e desvio-padrão são **populacionais**. A moda do valor do pedido só existe quando algum valor se repete
  (senão aparece "sem moda"); o cartão também mostra a quantidade mais comum por item.
- **Tendência**: inclinação da regressão linear do faturamento mensal. **Correlação**: r de Pearson entre o preço médio
  e as unidades vendidas por roupa (calculados no navegador a partir dos dados do banco).
- Se o último mês tem poucos dias de dados, a "variação mensal" compara um mês parcial com um completo.

## Como rodar

**Requisitos:** JDK 17+ e MySQL 8.0+ (usa CHECK, CTE recursiva, funções de janela, triggers e procedures).

1. **Criar o banco** — no MySQL Workbench (ou `mysql -u root -p`), execute **uma única vez** o arquivo
   `sql/00_uptown_completo.sql`. Ele reúne, na ordem certa, tabelas, dados de teste, índices/views (Etapa 4) e
   funções, procedures e triggers (Etapa 5). No terminal: `mysql -u root -p < sql/00_uptown_completo.sql`.

   Os scripts separados (`01_schema.sql`, `02_dados.sql`, `04_etapa04.sql`, `05_etapa05.sql`) continuam na pasta
   caso prefiram rodá-los um a um, nessa ordem. `03_consultas.sql` é opcional: só contém as consultas da Etapa 3
   para rodar à mão (o app já as executa).

   > ⚠️ O script começa com `DROP DATABASE IF EXISTS Uptown;` — se já existe um banco `Uptown` com dados que
   > você quer manter, faça backup antes.
2. **Configurar a conexão** — edite `src/main/resources/config.properties` (usuário e senha do MySQL). Para o jar
   já compilado, dá para sobrescrever sem recompilar:
   ```
   java -Ddb.user=root -Ddb.password=SUA_SENHA -jar dist/uptown-app.jar
   ```
3. **Abrir** http://localhost:7070

Para recompilar: `mvn package` (gera `target/uptown-app.jar`) e depois `java -jar target/uptown-app.jar`.

## Estrutura

```
sql/00_uptown_completo.sql  tudo em um arquivo só (01 + 02 + 04 + 05)
sql/01_schema.sql        tabelas (Entrega 2 + ajustes)
sql/02_dados.sql         dados de teste
sql/03_consultas.sql     8 consultas da Etapa 3
sql/04_etapa04.sql       Etapa 4: 2 índices, 4 consultas e 2 views
sql/05_etapa05.sql       Etapa 5: LogStatusPedido, 2 funções, 2 procedures, 2 triggers
src/main/java/uptown/    Main (rotas REST), Db (JDBC), AppException
src/main/java/uptown/dao ClienteDao, FornecedorDao, CategoriaDao, PedidoDao, RoupaDao,
                         ConsultaDao (14 consultas/views), DashboardDao (filtros + estatísticas), RotinaDao (Etapa 5)
src/main/resources/public  interface (index.html, app.js, style.css, Chart.js local)
dist/uptown-app.jar      aplicação compilada
```

## Mudanças em relação à Entrega 3

1. **Status do pedido**: deixou de ser `UPDATE` direto e passou a chamar `sp_atualizar_status_pedido`. Ao **criar**
   um pedido já Entregue/Cancelado, ele é gravado como "Em separação" e depois movido pela procedure, porque o trigger
   `trg_item_impede_pedido_cancelado` proíbe inserir itens em pedido nesses status. Esse caminho também gera linha no log.
2. **Itens de pedido existente**: novo botão "Incluir item" em Pedidos → Itens (demonstra o trigger e recalcula o total
   com `fn_total_itens_pedido`).
3. **Dashboard** passou a aceitar filtros e ganhou novos indicadores e gráficos; os valores agora são calculados a partir
   dos itens (`quantidade × preço`), que é como `Pedido.valor_total` é mantido.
4. **Consultas**: de 8 para 14 (4 consultas + 2 views da Etapa 4), cada uma com indicadores e gráfico.

## Observações sobre os dados

- `Pertence` tem a linha (1, 11): "Camisetas Básicas" tem dois pais. A consulta 1 e o filtro de categoria do dashboard
  tratam isso com `UNION` na CTE recursiva.
- `roupaCor` e `Fornece` só cobrem as roupas 1–30; as demais aparecem como "sem cor / sem fornecedor".
- Só 30 roupas têm venda; as outras aparecem na consulta 6.
- O nome de várias roupas traz uma cor e a cor cadastrada em `roupaCor` é outra. Nas 30 roupas que têm cor cadastrada,
  5 divergem do nome (ex.: "Camisa Polo Branca", roupa 11, está cadastrada como Azul; "Camiseta Basica Branca", roupa 7, como
  Cinza). É assim nos dados de teste originais e foi mantido de propósito: a consulta 2 mostra os dois valores lado a lado,
  e os dados não foram alterados.

## Fora do escopo

Autenticação; CRUD de Roupa com subtipos (Camisa/Calça/Casaco) e de Cor (o catálogo é somente leitura).

## Uso de IA e validação

A evolução da Etapa 6 (rotas, interface, dashboard e este README) foi feita com apoio do Claude Code. Para validar,
os scripts SQL foram executados num MySQL real e a aplicação foi testada ponta a ponta: os totais do dashboard foram
conferidos contra consultas SQL diretas (faturamento e contagem de pedidos, com e sem filtro de categoria), as
14 consultas/views foram abertas na interface e os erros da procedure e do trigger foram provocados e vistos na tela.
