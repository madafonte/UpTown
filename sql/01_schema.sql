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
