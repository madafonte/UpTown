-- =====================================================================
-- UpTown - Etapa 6 | Script unico: executa tudo de uma vez
-- (01_schema + 02_dados + 04_etapa04 + 05_etapa05, nessa ordem)
-- ATENCAO: comeca com DROP DATABASE IF EXISTS Uptown.
-- =====================================================================
SET NAMES utf8mb4;


-- ################ 01_schema.sql ################

-- =====================================================================
-- UpTown - Marketplace de Roupas | Entrega 3
-- Script 01: esquema (tabelas)
--
-- Base: script da Entrega 2. Ajustes feitos para a Entrega 3:
--   1) DROP DATABASE IF EXISTS  -> permite reexecutar o script do zero.
--   2) AUTO_INCREMENT nos codigos numericos (Categoria, Roupa, Cliente,
--      Pedido, ItemPedido, Fornecedor) -> a interface insere sem precisar
--      informar o codigo. Os dados da Entrega 2 continuam com seus ids.
--   3) Pedido.codigo_cliente agora NOT NULL + ON DELETE RESTRICT.
--      A propria Entrega 2 alertava que "on delete set null" contradiz o
--      minimo mundo: todo pedido e gerado por exatamente 1 cliente.
--   4) Charset utf8mb4 (acentos: 'Em separação', 'Lilás', ...).
-- Requer MySQL 8.0+ (CHECK constraints, CTE recursiva e funcoes de janela).
-- =====================================================================

DROP DATABASE IF EXISTS Uptown;
CREATE DATABASE Uptown CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE Uptown;

CREATE TABLE Categoria (
    codigo_categoria INT AUTO_INCREMENT PRIMARY KEY,
    nome             VARCHAR(50) NOT NULL UNIQUE,
    descricao        VARCHAR(100)
);

CREATE TABLE Roupa (
    categoria_codigo_roupa INT NOT NULL,
    codigo_roupa           INT AUTO_INCREMENT PRIMARY KEY,
    nome                   VARCHAR(30) NOT NULL,
    tamanho                VARCHAR(3)  NOT NULL,   -- Entrega 2: INT -> VARCHAR (P, M, G)
    sexo                   VARCHAR(10) NOT NULL,

    FOREIGN KEY (categoria_codigo_roupa)
        REFERENCES Categoria(codigo_categoria)
        ON UPDATE CASCADE,

    CHECK (tamanho IN ('P', 'M', 'G')),
    CHECK (sexo IN ('Masculino', 'Feminino', 'Unissex'))
);

-- Especializacao total e exclusiva de Roupa
CREATE TABLE Camisa (
    codigo_camisa INT PRIMARY KEY,                 -- PK e FK
    corte         VARCHAR(20) NOT NULL,
    gola          VARCHAR(20) NOT NULL,
    FOREIGN KEY (codigo_camisa) REFERENCES Roupa(codigo_roupa)
);

CREATE TABLE Calca (
    codigo_calca INT PRIMARY KEY,                  -- PK e FK
    modelo       VARCHAR(30) NOT NULL,
    cintura      VARCHAR(10) NOT NULL,
    FOREIGN KEY (codigo_calca) REFERENCES Roupa(codigo_roupa)
);

CREATE TABLE Casaco (
    codigo_casaco INT PRIMARY KEY,                 -- PK e FK
    encapuzado    BOOLEAN NOT NULL DEFAULT TRUE,   -- Entrega 2: VARCHAR -> BOOLEAN
    bolso         BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (codigo_casaco) REFERENCES Roupa(codigo_roupa)
);

CREATE TABLE Cor (
    codigo_cor VARCHAR(20) PRIMARY KEY,
    cor        VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE Cliente (
    codigo_cliente INT AUTO_INCREMENT PRIMARY KEY,
    nome           VARCHAR(100) NOT NULL,
    email          VARCHAR(100) NOT NULL UNIQUE,
    rua            VARCHAR(100) NOT NULL,          -- endereco composto:
    bairro         VARCHAR(100) NOT NULL,          -- rua, numero, bairro
    numero         INT NOT NULL
);

CREATE TABLE Pedido (
    codigo_pedido  INT AUTO_INCREMENT PRIMARY KEY,
    codigo_cliente INT NOT NULL,                   -- Entrega 3: NOT NULL
    data_pedido    DATE NOT NULL,
    status         VARCHAR(30) NOT NULL DEFAULT 'Em separação',
    valor_total    DECIMAL(10, 2) NOT NULL,

    CHECK (valor_total >= 0.00),
    CHECK (status IN ('A caminho', 'Em separação', 'Entregue', 'Cancelado')),

    FOREIGN KEY (codigo_cliente)
        REFERENCES Cliente(codigo_cliente)
        ON DELETE RESTRICT                         -- Entrega 3: era SET NULL
);

-- Entidade fraca/associativa: so existe dentro de um Pedido
CREATE TABLE ItemPedido (
    codigo_item    INT AUTO_INCREMENT PRIMARY KEY,
    codigo_roupa   INT NOT NULL,
    codigo_pedido  INT NOT NULL,
    quantidade     INT NOT NULL,
    preco_unitario DECIMAL(10, 2) NOT NULL,

    CHECK (quantidade > 0),
    CHECK (preco_unitario >= 0.00),

    FOREIGN KEY (codigo_pedido) REFERENCES Pedido(codigo_pedido),
    FOREIGN KEY (codigo_roupa)  REFERENCES Roupa(codigo_roupa)
);

CREATE TABLE Fornecedor (
    codigo_fornecedor INT AUTO_INCREMENT PRIMARY KEY,
    nome              VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE Fornece (
    codigo_fornecedor INT,
    codigo_roupa      INT,
    PRIMARY KEY (codigo_fornecedor, codigo_roupa),
    FOREIGN KEY (codigo_roupa)      REFERENCES Roupa(codigo_roupa),
    FOREIGN KEY (codigo_fornecedor) REFERENCES Fornecedor(codigo_fornecedor)
);

-- Auto-relacionamento de Categoria (categoria pai / subcategoria)
CREATE TABLE Pertence (
    codigo_categoria_pai   INT,
    codigo_categoria_filha INT,
    PRIMARY KEY (codigo_categoria_pai, codigo_categoria_filha),
    FOREIGN KEY (codigo_categoria_pai)   REFERENCES Categoria(codigo_categoria),
    FOREIGN KEY (codigo_categoria_filha) REFERENCES Categoria(codigo_categoria),
    CHECK (codigo_categoria_pai <> codigo_categoria_filha)
);

-- Atributo multivalorado Cor de Roupa
CREATE TABLE roupaCor (
    codigo_roupa INT,
    cor          VARCHAR(20),
    PRIMARY KEY (codigo_roupa, cor),
    FOREIGN KEY (codigo_roupa) REFERENCES Roupa(codigo_roupa),
    FOREIGN KEY (cor)          REFERENCES Cor(cor)
);


-- ################ 02_dados.sql ################

-- =====================================================================
-- UpTown - Marketplace de Roupas | Entrega 3
-- Script 02: dados de teste (mesmos dados da Entrega 2)
--
-- Ajuste unico: o UPDATE final recalcula Pedido.valor_total como a soma de
-- quantidade * preco_unitario dos itens. Na Entrega 2 o valor_total nao
-- batia com os itens (ex.: pedido 1 = 149,90, mas o item vale 1 x 79,90).
-- =====================================================================
USE Uptown;
SET NAMES utf8mb4;

INSERT INTO Categoria (codigo_categoria, nome, descricao)
VALUES
    (1, 'Roupas', 'Categoria principal de roupas'),
    (2, 'Camisetas', 'Camisetas casuais e básicas'),
    (3, 'Camisas', 'Camisas sociais e casuais'),
    (4, 'Calcas', 'Calcas de diferentes modelos'),
    (5, 'Casacos', 'Casacos e peças para frio'),
    (6, 'Bermudas', 'Bermudas masculinas e femininas'),
    (7, 'Vestidos', 'Vestidos de diferentes estilos'),
    (8, 'Saias', 'Saias femininas'),
    (9, 'Blusas', 'Blusas femininas'),
    (10, 'Jaquetas', 'Jaquetas de diferentes modelos'),
    (11, 'Camisetas Basicas', 'Camisetas para uso cotidiano'),
    (12, 'Camisetas Estampadas', 'Camisetas com estampas'),
    (13, 'Camisetas Oversized', 'Camisetas de modelagem ampla'),
    (14, 'Camisas Sociais', 'Camisas para ocasioes formais'),
    (15, 'Camisas Polo', 'Camisas polo casuais'),
    (16, 'Camisas Flanela', 'Camisas de flanela'),
    (17, 'Calcas Jeans', 'Calcas confeccionadas em jeans'),
    (18, 'Calcas Cargo', 'Calcas com bolsos laterais'),
    (19, 'Calcas Jogger', 'Calcas de modelagem jogger'),
    (20, 'Casacos Moletom', 'Casacos confeccionados em moletom'),
    (21, 'Casacos Inverno', 'Casacos para temperaturas baixas'),
    (22, 'Casacos Esportivos', 'Casacos para atividades esportivas'),
    (23, 'Bermudas Jeans', 'Bermudas confeccionadas em jeans'),
    (24, 'Bermudas Esportivas', 'Bermudas para atividades esportivas'),
    (25, 'Vestidos Casuais', 'Vestidos para uso cotidiano'),
    (26, 'Vestidos Sociais', 'Vestidos para ocasioes formais'),
    (27, 'Saias Curtas', 'Saias de comprimento curto'),
    (28, 'Saias Longas', 'Saias de comprimento longo'),
    (29, 'Blusas Casuais', 'Blusas para uso cotidiano'),
    (30, 'Blusas Sociais', 'Blusas para ocasioes formais');

INSERT INTO Cor (codigo_cor, cor)
VALUES
    ('COR01', 'Preto'),
    ('COR02', 'Branco'),
    ('COR03', 'Azul'),
    ('COR04', 'Vermelho'),
    ('COR05', 'Verde'),
    ('COR06', 'Amarelo'),
    ('COR07', 'Cinza'),
    ('COR08', 'Marrom'),
    ('COR09', 'Bege'),
    ('COR10', 'Rosa'),
    ('COR11', 'Roxo'),
    ('COR12', 'Laranja'),
    ('COR13', 'Vinho'),
    ('COR14', 'Azul Marinho'),
    ('COR15', 'Azul Claro'),
    ('COR16', 'Verde Militar'),
    ('COR17', 'Verde Claro'),
    ('COR18', 'Cinza Chumbo'),
    ('COR19', 'Cinza Claro'),
    ('COR20', 'Off White'),
    ('COR21', 'Caramelo'),
    ('COR22', 'Creme'),
    ('COR23', 'Lilás'),
    ('COR24', 'Pink'),
    ('COR25', 'Turquesa'),
    ('COR26', 'Mostarda'),
    ('COR27', 'Terracota'),
    ('COR28', 'Grafite'),
    ('COR29', 'Prata'),
    ('COR30', 'Dourado');

INSERT INTO Cliente (codigo_cliente, nome, email, rua, bairro, numero)
VALUES
    (1, 'Arthur Moury', 'arthur.moury@email.com', 'Rua das Flores', 'Boa Viagem', 101),
    (2, 'Bruno Leite', 'bruno.leite@email.com', 'Rua do Sol', 'Pina', 202),
    (3, 'Diego Magnata', 'diego.magnata@email.com', 'Rua Aurora', 'Recife', 303),
    (4, 'Gustavo Castro', 'gustavo.castro@email.com', 'Rua Central', 'Casa Forte', 404),
    (5, 'Luiza Almeida', 'luiza.almeida@email.com', 'Rua do Comercio', 'Santo Amaro', 505),
    (6, 'Maria Hatem', 'maria.hatem@email.com', 'Rua Recife', 'Madalena', 606),
    (7, 'Joao Silva', 'joao.silva@email.com', 'Rua Brasil', 'Imbiribeira', 707),
    (8, 'Ana Santos', 'ana.santos@email.com', 'Rua Pernambuco', 'Torre', 808),
    (9, 'Pedro Oliveira', 'pedro.oliveira@email.com', 'Rua Principal', 'Derby', 909),
    (10, 'Julia Costa', 'julia.costa@email.com', 'Rua Nova', 'Espinheiro', 100),
    (11, 'Lucas Souza', 'lucas.souza@email.com', 'Rua Verde', 'Encruzilhada', 111),
    (12, 'Mariana Lima', 'mariana.lima@email.com', 'Rua Azul', 'Aflitos', 122),
    (13, 'Rafael Alves', 'rafael.alves@email.com', 'Rua Recife Antigo', 'Sao Jose', 133),
    (14, 'Camila Rocha', 'camila.rocha@email.com', 'Rua da Paz', 'Ilha do Leite', 144),
    (15, 'Felipe Martins', 'felipe.martins@email.com', 'Rua das Palmeiras', 'Vasco da Gama', 155),
    (16, 'Beatriz Ferreira', 'beatriz.ferreira@email.com', 'Rua do Porto', 'Areias', 166),
    (17, 'Gabriel Pereira', 'gabriel.pereira@email.com', 'Rua do Mar', 'Jordao', 177),
    (18, 'Larissa Gomes', 'larissa.gomes@email.com', 'Rua Boa Vista', 'Boa Vista', 188),
    (19, 'Matheus Ribeiro', 'matheus.ribeiro@email.com', 'Rua das Acacias', 'Iputinga', 199),
    (20, 'Isabela Carvalho', 'isabela.carvalho@email.com', 'Rua dos Pinheiros', 'Várzea', 210),
    (21, 'Henrique Nunes', 'henrique.nunes@email.com', 'Rua do Campo', 'Curado', 221),
    (22, 'Sofia Barbosa', 'sofia.barbosa@email.com', 'Rua da Lagoa', 'Cordeiro', 232),
    (23, 'Guilherme Melo', 'guilherme.melo@email.com', 'Rua da Praia', 'Brasilia Teimosa', 243),
    (24, 'Clara Mendes', 'clara.mendes@email.com', 'Rua do Parque', 'Jaqueira', 254),
    (25, 'Vinicius Cardoso', 'vinicius.cardoso@email.com', 'Rua do Norte', 'Macaxeira', 265),
    (26, 'Manuela Dias', 'manuela.dias@email.com', 'Rua do Sul', 'Ibura', 276),
    (27, 'Eduardo Teixeira', 'eduardo.teixeira@email.com', 'Rua do Mercado', 'Afogados', 287),
    (28, 'Helena Monteiro', 'helena.monteiro@email.com', 'Rua da Estacao', 'Coelhos', 298),
    (29, 'Thiago Moreira', 'thiago.moreira@email.com', 'Rua do Jardim', 'Tamarineira', 309),
    (30, 'Valentina Freitas', 'valentina.freitas@email.com', 'Rua das Palmeiras', 'Poco da Panela', 320);

INSERT INTO Fornecedor (codigo_fornecedor, nome)
VALUES
    (1, 'Fashion Textil'),
    (2, 'Brasil Tecidos'),
    (3, 'Premium Fabrics'),
    (4, 'Recife Textil'),
    (5, 'Nordeste Confeccoes'),
    (6, 'Style Supply'),
    (7, 'Urban Fabrics'),
    (8, 'Moda Brasil'),
    (9, 'Alpha Textil'),
    (10, 'Beta Confeccoes'),
    (11, 'Gamma Tecidos'),
    (12, 'Delta Fashion'),
    (13, 'Litoral Textil'),
    (14, 'Centro Moda'),
    (15, 'Master Fabrics'),
    (16, 'Nova Textil'),
    (17, 'Original Confeccoes'),
    (18, 'Top Fashion'),
    (19, 'Prime Tecidos'),
    (20, 'Real Textil'),
    (21, 'Elite Confeccoes'),
    (22, 'Max Fabrics'),
    (23, 'Trend Supply'),
    (24, 'Urban Supply'),
    (25, 'Classic Textil'),
    (26, 'Modern Fabrics'),
    (27, 'Style Brasil'),
    (28, 'Fashion Nordeste'),
    (29, 'Quality Textil'),
    (30, 'Uptown Supply');

INSERT INTO Roupa (categoria_codigo_roupa, codigo_roupa, nome, tamanho, sexo)
VALUES
    (11, 1, 'Camiseta Basica Preta', 'P', 'Unissex'),
    (12, 2, 'Camiseta Street', 'M', 'Masculino'),
    (13, 3, 'Camiseta Oversized', 'G', 'Unissex'),
    (14, 4, 'Camisa Social Branca', 'M', 'Masculino'),
    (15, 5, 'Camisa Polo Azul', 'G', 'Masculino'),
    (16, 6, 'Camisa Flanela', 'P', 'Unissex'),
    (11, 7, 'Camiseta Basica Branca', 'M', 'Feminino'),
    (12, 8, 'Camiseta Estampada Azul', 'G', 'Unissex'),
    (13, 9, 'Camiseta Wide Preta', 'M', 'Masculino'),
    (14, 10, 'Camisa Social Preta', 'G', 'Masculino'),
    (15, 11, 'Camisa Polo Branca', 'M', 'Unissex'),
    (16, 12, 'Camisa Flanela Verde', 'P', 'Unissex'),
    (11, 13, 'Camiseta Basica Cinza', 'G', 'Masculino'),
    (12, 14, 'Camiseta Estampada Vermelha', 'M', 'Feminino'),
    (13, 15, 'Camiseta Oversized Branca', 'G', 'Unissex'),
    (14, 16, 'Camisa Social Azul', 'M', 'Masculino'),
    (15, 17, 'Camisa Polo Preta', 'P', 'Masculino'),
    (16, 18, 'Camisa Flanela Marrom', 'G', 'Unissex'),
    (11, 19, 'Camiseta Basica Verde', 'M', 'Feminino'),
    (12, 20, 'Camiseta Estampada Amarela', 'P', 'Unissex'),
    (13, 21, 'Camiseta Oversized Cinza', 'G', 'Masculino'),
    (14, 22, 'Camisa Social Branca', 'M', 'Feminino'),
    (15, 23, 'Camisa Polo Azul', 'G', 'Unissex'),
    (16, 24, 'Camisa Flanela Azul', 'P', 'Masculino'),
    (11, 25, 'Camiseta Basica Rosa', 'M', 'Feminino'),
    (12, 26, 'Camiseta Estampada Verde', 'G', 'Unissex'),
    (13, 27, 'Camiseta Oversized Preta', 'M', 'Masculino'),
    (14, 28, 'Camisa Social Cinza', 'P', 'Feminino'),
    (15, 29, 'Camisa Polo Verde', 'G', 'Unissex'),
    (16, 30, 'Camisa Flanela Bege', 'M', 'Masculino'),
    (17, 31, 'Calca Jeans Slim', 'M', 'Masculino'),
    (18, 32, 'Calca Cargo Bege', 'G', 'Masculino'),
    (19, 33, 'Calca Jogger Preta', 'M', 'Unissex'),
    (17, 34, 'Calca Jeans Reta', 'G', 'Feminino'),
    (18, 35, 'Calca Cargo Verde', 'M', 'Masculino'),
    (19, 36, 'Calca Jogger Cinza', 'P', 'Unissex'),
    (17, 37, 'Calca Jeans Skinny', 'M', 'Feminino'),
    (18, 38, 'Calca Cargo Preta', 'G', 'Masculino'),
    (19, 39, 'Calca Jogger Azul', 'M', 'Unissex'),
    (17, 40, 'Calca Jeans Clara', 'P', 'Feminino'),
    (18, 41, 'Calca Cargo Bege', 'M', 'Masculino'),
    (19, 42, 'Calca Jogger Verde', 'G', 'Unissex'),
    (17, 43, 'Calca Jeans Escura', 'M', 'Masculino'),
    (18, 44, 'Calca Cargo Cinza', 'P', 'Feminino'),
    (19, 45, 'Calca Jogger Preta', 'G', 'Unissex'),
    (17, 46, 'Calca Jeans Slim Azul', 'M', 'Masculino'),
    (18, 47, 'Calca Cargo Marrom', 'G', 'Feminino'),
    (19, 48, 'Calca Jogger Cinza', 'P', 'Unissex'),
    (17, 49, 'Calca Jeans Reta Azul', 'M', 'Masculino'),
    (18, 50, 'Calca Cargo Verde Militar', 'G', 'Feminino'),
    (19, 51, 'Calca Jogger Bege', 'M', 'Unissex'),
    (17, 52, 'Calca Jeans Skinny Preta', 'P', 'Feminino'),
    (18, 53, 'Calca Cargo Azul', 'M', 'Masculino'),
    (19, 54, 'Calca Jogger Marrom', 'G', 'Unissex'),
    (17, 55, 'Calca Jeans Tradicional', 'M', 'Masculino'),
    (18, 56, 'Calca Cargo Cinza', 'P', 'Feminino'),
    (19, 57, 'Calca Jogger Verde', 'G', 'Unissex'),
    (17, 58, 'Calca Jeans Slim Preta', 'M', 'Masculino'),
    (18, 59, 'Calca Cargo Bege', 'G', 'Feminino'),
    (19, 60, 'Calca Jogger Azul', 'P', 'Unissex'),
    (20, 61, 'Moletom Basico Preto', 'G', 'Unissex'),
    (21, 62, 'Casaco Inverno Marrom', 'M', 'Feminino'),
    (22, 63, 'Casaco Esportivo Azul', 'P', 'Unissex'),
    (20, 64, 'Moletom Cinza', 'M', 'Masculino'),
    (21, 65, 'Casaco Inverno Preto', 'G', 'Feminino'),
    (22, 66, 'Casaco Esportivo Verde', 'M', 'Unissex'),
    (20, 67, 'Moletom Oversized', 'G', 'Masculino'),
    (21, 68, 'Casaco Inverno Bege', 'M', 'Feminino'),
    (22, 69, 'Casaco Esportivo Preto', 'P', 'Unissex'),
    (20, 70, 'Moletom Branco', 'M', 'Masculino'),
    (21, 71, 'Casaco Inverno Cinza', 'G', 'Feminino'),
    (22, 72, 'Casaco Esportivo Azul', 'M', 'Unissex'),
    (20, 73, 'Moletom Verde', 'P', 'Masculino'),
    (21, 74, 'Casaco Inverno Marrom', 'M', 'Feminino'),
    (22, 75, 'Casaco Esportivo Vermelho', 'G', 'Unissex'),
    (20, 76, 'Moletom Preto', 'M', 'Masculino'),
    (21, 77, 'Casaco Inverno Azul', 'P', 'Feminino'),
    (22, 78, 'Casaco Esportivo Cinza', 'G', 'Unissex'),
    (20, 79, 'Moletom Bege', 'M', 'Masculino'),
    (21, 80, 'Casaco Inverno Verde', 'G', 'Feminino'),
    (22, 81, 'Casaco Esportivo Preto', 'P', 'Unissex'),
    (20, 82, 'Moletom Azul', 'M', 'Masculino'),
    (21, 83, 'Casaco Inverno Bege', 'G', 'Feminino'),
    (22, 84, 'Casaco Esportivo Verde', 'M', 'Unissex'),
    (20, 85, 'Moletom Cinza Chumbo', 'P', 'Masculino'),
    (21, 86, 'Casaco Inverno Preto', 'M', 'Feminino'),
    (22, 87, 'Casaco Esportivo Azul', 'G', 'Unissex'),
    (20, 88, 'Moletom Verde Militar', 'M', 'Masculino'),
    (21, 89, 'Casaco Inverno Cinza', 'P', 'Feminino'),
    (22, 90, 'Casaco Esportivo Marrom', 'G', 'Unissex');

INSERT INTO Camisa (codigo_camisa, corte, gola)
VALUES
    (1, 'Regular', 'Redonda'),
    (2, 'Oversized', 'Redonda'),
    (3, 'Oversized', 'Redonda'),
    (4, 'Slim', 'Social'),
    (5, 'Regular', 'Polo'),
    (6, 'Regular', 'Padre'),
    (7, 'Regular', 'Redonda'),
    (8, 'Oversized', 'Redonda'),
    (9, 'Oversized', 'Redonda'),
    (10, 'Slim', 'Social'),
    (11, 'Regular', 'Polo'),
    (12, 'Regular', 'Padre'),
    (13, 'Regular', 'Redonda'),
    (14, 'Regular', 'Redonda'),
    (15, 'Oversized', 'Redonda'),
    (16, 'Slim', 'Social'),
    (17, 'Regular', 'Polo'),
    (18, 'Regular', 'Padre'),
    (19, 'Regular', 'Redonda'),
    (20, 'Regular', 'Redonda'),
    (21, 'Oversized', 'Redonda'),
    (22, 'Slim', 'Social'),
    (23, 'Regular', 'Polo'),
    (24, 'Regular', 'Padre'),
    (25, 'Regular', 'Redonda'),
    (26, 'Regular', 'Redonda'),
    (27, 'Oversized', 'Redonda'),
    (28, 'Slim', 'Social'),
    (29, 'Regular', 'Polo'),
    (30, 'Regular', 'Padre');

INSERT INTO Calca (codigo_calca, modelo, cintura)
VALUES
    (31, 'Slim', 'Media'),
    (32, 'Cargo', 'Alta'),
    (33, 'Jogger', 'Media'),
    (34, 'Reta', 'Alta'),
    (35, 'Cargo', 'Media'),
    (36, 'Jogger', 'Alta'),
    (37, 'Skinny', 'Media'),
    (38, 'Cargo', 'Alta'),
    (39, 'Jogger', 'Media'),
    (40, 'Reta', 'Alta'),
    (41, 'Cargo', 'Media'),
    (42, 'Jogger', 'Alta'),
    (43, 'Slim', 'Media'),
    (44, 'Cargo', 'Alta'),
    (45, 'Jogger', 'Media'),
    (46, 'Slim', 'Alta'),
    (47, 'Cargo', 'Media'),
    (48, 'Jogger', 'Alta'),
    (49, 'Reta', 'Media'),
    (50, 'Cargo', 'Alta'),
    (51, 'Jogger', 'Media'),
    (52, 'Skinny', 'Alta'),
    (53, 'Cargo', 'Media'),
    (54, 'Jogger', 'Alta'),
    (55, 'Slim', 'Media'),
    (56, 'Cargo', 'Alta'),
    (57, 'Jogger', 'Media'),
    (58, 'Slim', 'Alta'),
    (59, 'Cargo', 'Media'),
    (60, 'Jogger', 'Alta');

INSERT INTO Casaco (codigo_casaco, encapuzado, bolso)
VALUES
    (61, TRUE, TRUE),
    (62, TRUE, TRUE),
    (63, FALSE, TRUE),
    (64, TRUE, TRUE),
    (65, TRUE, FALSE),
    (66, TRUE, TRUE),
    (67, TRUE, TRUE),
    (68, FALSE, TRUE),
    (69, TRUE, TRUE),
    (70, TRUE, TRUE),
    (71, TRUE, FALSE),
    (72, TRUE, TRUE),
    (73, FALSE, TRUE),
    (74, TRUE, TRUE),
    (75, FALSE, TRUE),
    (76, TRUE, TRUE),
    (77, TRUE, FALSE),
    (78, TRUE, TRUE),
    (79, FALSE, TRUE),
    (80, TRUE, TRUE),
    (81, TRUE, TRUE),
    (82, FALSE, TRUE),
    (83, TRUE, TRUE),
    (84, TRUE, FALSE),
    (85, TRUE, TRUE),
    (86, FALSE, TRUE),
    (87, TRUE, TRUE),
    (88, TRUE, FALSE),
    (89, TRUE, TRUE),
    (90, FALSE, TRUE);

INSERT INTO Pedido (codigo_pedido, codigo_cliente, data_pedido, status, valor_total)
VALUES
    (1, 1, '2026-01-05', 'Entregue', 149.90),
    (2, 2, '2026-01-08', 'Entregue', 219.90),
    (3, 3, '2026-01-12', 'A caminho', 99.90),
    (4, 4, '2026-01-15', 'Em separação', 179.90),
    (5, 5, '2026-01-19', 'Entregue', 259.90),
    (6, 6, '2026-01-23', 'Cancelado', 129.90),
    (7, 7, '2026-02-02', 'Entregue', 189.90),
    (8, 8, '2026-02-06', 'A caminho', 299.90),
    (9, 9, '2026-02-10', 'Em separação', 159.90),
    (10, 10, '2026-02-14', 'Entregue', 349.90),
    (11, 11, '2026-02-18', 'Entregue', 119.90),
    (12, 12, '2026-02-21', 'A caminho', 199.90),
    (13, 13, '2026-02-25', 'Em separação', 229.90),
    (14, 14, '2026-03-01', 'Entregue', 279.90),
    (15, 15, '2026-03-05', 'Cancelado', 139.90),
    (16, 16, '2026-03-09', 'Entregue', 189.90),
    (17, 17, '2026-03-13', 'A caminho', 249.90),
    (18, 18, '2026-03-17', 'Em separação', 159.90),
    (19, 19, '2026-03-21', 'Entregue', 319.90),
    (20, 20, '2026-03-25', 'Entregue', 199.90),
    (21, 21, '2026-04-01', 'A caminho', 129.90),
    (22, 22, '2026-04-05', 'Em separação', 289.90),
    (23, 23, '2026-04-09', 'Entregue', 169.90),
    (24, 24, '2026-04-13', 'Cancelado', 99.90),
    (25, 25, '2026-04-17', 'Entregue', 239.90),
    (26, 26, '2026-04-21', 'A caminho', 199.90),
    (27, 27, '2026-04-25', 'Em separação', 309.90),
    (28, 28, '2026-05-01', 'Entregue', 179.90),
    (29, 29, '2026-05-05', 'A caminho', 269.90),
    (30, 30, '2026-05-09', 'Entregue', 219.90);

INSERT INTO ItemPedido (codigo_item, codigo_roupa, codigo_pedido, quantidade, preco_unitario)
VALUES
    (1, 1, 1, 1, 79.90),
    (2, 2, 2, 2, 89.90),
    (3, 3, 3, 1, 99.90),
    (4, 4, 4, 1, 179.90),
    (5, 5, 5, 2, 129.90),
    (6, 6, 6, 1, 119.90),
    (7, 31, 7, 1, 159.90),
    (8, 32, 8, 2, 149.90),
    (9, 33, 9, 1, 139.90),
    (10, 61, 10, 1, 159.90),
    (11, 62, 11, 1, 199.90),
    (12, 63, 12, 1, 189.90),
    (13, 34, 13, 1, 99.90),
    (14, 35, 14, 2, 89.90),
    (15, 64, 15, 1, 179.90),
    (16, 65, 16, 1, 219.90),
    (17, 36, 17, 1, 119.90),
    (18, 37, 18, 1, 149.90),
    (19, 66, 19, 2, 109.90),
    (20, 67, 20, 1, 129.90),
    (21, 21, 21, 1, 79.90),
    (22, 22, 22, 1, 89.90),
    (23, 23, 23, 1, 99.90),
    (24, 24, 24, 1, 179.90),
    (25, 25, 25, 2, 129.90),
    (26, 26, 26, 1, 119.90),
    (27, 27, 27, 1, 159.90),
    (28, 68, 28, 1, 149.90),
    (29, 69, 29, 1, 139.90),
    (30, 70, 30, 1, 159.90);

INSERT INTO Fornece (codigo_fornecedor, codigo_roupa)
VALUES
    (1, 1),
    (2, 2),
    (3, 3),
    (4, 4),
    (5, 5),
    (6, 6),
    (7, 7),
    (8, 8),
    (9, 9),
    (10, 10),
    (11, 11),
    (12, 12),
    (13, 13),
    (14, 14),
    (15, 15),
    (16, 16),
    (17, 17),
    (18, 18),
    (19, 19),
    (20, 20),
    (21, 21),
    (22, 22),
    (23, 23),
    (24, 24),
    (25, 25),
    (26, 26),
    (27, 27),
    (28, 28),
    (29, 29),
    (30, 30);

INSERT INTO Pertence (codigo_categoria_pai, codigo_categoria_filha)
VALUES
    (1, 2),
    (1, 3),
    (1, 4),
    (1, 5),
    (1, 6),
    (1, 7),
    (1, 8),
    (1, 9),
    (1, 10),
    (2, 11),
    (2, 12),
    (2, 13),
    (3, 14),
    (3, 15),
    (3, 16),
    (4, 17),
    (4, 18),
    (4, 19),
    (5, 20),
    (5, 21),
    (5, 22),
    (6, 23),
    (6, 24),
    (7, 25),
    (7, 26),
    (8, 27),
    (8, 28),
    (9, 29),
    (9, 30),
    (1, 11);

INSERT INTO roupaCor (codigo_roupa, cor)
VALUES
    (1, 'Preto'),
    (2, 'Branco'),
    (3, 'Azul'),
    (4, 'Branco'),
    (5, 'Azul'),
    (6, 'Verde'),
    (7, 'Cinza'),
    (8, 'Vermelho'),
    (9, 'Preto'),
    (10, 'Branco'),
    (11, 'Azul'),
    (12, 'Verde'),
    (13, 'Cinza'),
    (14, 'Vermelho'),
    (15, 'Branco'),
    (16, 'Azul Marinho'),
    (17, 'Preto'),
    (18, 'Marrom'),
    (19, 'Verde'),
    (20, 'Amarelo'),
    (21, 'Cinza'),
    (22, 'Branco'),
    (23, 'Azul'),
    (24, 'Verde Militar'),
    (25, 'Rosa'),
    (26, 'Verde Claro'),
    (27, 'Preto'),
    (28, 'Cinza Chumbo'),
    (29, 'Verde'),
    (30, 'Bege');

-- Coerencia: valor_total do pedido = soma dos seus itens
UPDATE Pedido p
SET p.valor_total = (
    SELECT SUM(i.quantidade * i.preco_unitario)
    FROM ItemPedido i
    WHERE i.codigo_pedido = p.codigo_pedido
);

-- ################ 04_etapa04.sql ################

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


-- ################ 05_etapa05.sql ################

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
