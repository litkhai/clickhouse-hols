-- ============================================================
-- ClickPipes CDC Demo - 초기화 스크립트
-- ============================================================

USE cdc_demo;

-- -------------------------------------------------------
-- 1. ClickPipes CDC 전용 복제 유저 생성
-- -------------------------------------------------------
CREATE USER IF NOT EXISTS 'clickpipes_repl'@'%' IDENTIFIED WITH mysql_native_password BY 'ClickPipes2024!';

-- CDC에 필요한 최소 권한 부여
GRANT REPLICATION SLAVE ON *.* TO 'clickpipes_repl'@'%';
GRANT REPLICATION CLIENT ON *.* TO 'clickpipes_repl'@'%';
GRANT SELECT ON cdc_demo.* TO 'clickpipes_repl'@'%';

FLUSH PRIVILEGES;

-- -------------------------------------------------------
-- 2. 데모 테이블 생성
-- -------------------------------------------------------

-- 고객 테이블
CREATE TABLE IF NOT EXISTS customers (
    id         INT          NOT NULL AUTO_INCREMENT,
    name       VARCHAR(100) NOT NULL,
    email      VARCHAR(150) NOT NULL UNIQUE,
    country    VARCHAR(50)  NOT NULL DEFAULT 'KR',
    tier       ENUM('bronze','silver','gold','platinum') NOT NULL DEFAULT 'bronze',
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 상품 테이블
CREATE TABLE IF NOT EXISTS products (
    id          INT            NOT NULL AUTO_INCREMENT,
    sku         VARCHAR(50)    NOT NULL UNIQUE,
    name        VARCHAR(200)   NOT NULL,
    category    VARCHAR(100)   NOT NULL,
    price       DECIMAL(10, 2) NOT NULL,
    stock       INT            NOT NULL DEFAULT 0,
    is_active   TINYINT(1)     NOT NULL DEFAULT 1,
    created_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 주문 테이블
CREATE TABLE IF NOT EXISTS orders (
    id          INT            NOT NULL AUTO_INCREMENT,
    customer_id INT            NOT NULL,
    status      ENUM('pending','processing','shipped','delivered','cancelled') NOT NULL DEFAULT 'pending',
    total_amount DECIMAL(12, 2) NOT NULL,
    items_count INT            NOT NULL DEFAULT 1,
    note        TEXT,
    ordered_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_customer_id (customer_id),
    KEY idx_status (status),
    KEY idx_ordered_at (ordered_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 주문 항목 테이블
CREATE TABLE IF NOT EXISTS order_items (
    id         INT            NOT NULL AUTO_INCREMENT,
    order_id   INT            NOT NULL,
    product_id INT            NOT NULL,
    quantity   INT            NOT NULL DEFAULT 1,
    unit_price DECIMAL(10, 2) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_order_id (order_id),
    KEY idx_product_id (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -------------------------------------------------------
-- 3. 초기 시드 데이터 삽입
-- -------------------------------------------------------

INSERT INTO customers (name, email, country, tier) VALUES
    ('Kim Minjun',    'minjun.kim@example.com',    'KR', 'gold'),
    ('Lee Soyeon',    'soyeon.lee@example.com',    'KR', 'silver'),
    ('Park Jihoon',   'jihoon.park@example.com',   'KR', 'platinum'),
    ('Choi Yuna',     'yuna.choi@example.com',     'KR', 'bronze'),
    ('Jung Taewoo',   'taewoo.jung@example.com',   'KR', 'silver'),
    ('Han Minji',     'minji.han@example.com',     'KR', 'gold'),
    ('Yoon Seojun',   'seojun.yoon@example.com',   'KR', 'bronze'),
    ('Lim Dahye',     'dahye.lim@example.com',     'KR', 'silver'),
    ('Kwon Hyunwoo',  'hyunwoo.kwon@example.com',  'KR', 'gold'),
    ('Shin Eunji',    'eunji.shin@example.com',    'KR', 'platinum');

INSERT INTO products (sku, name, category, price, stock) VALUES
    ('ELEC-001', 'Wireless Earbuds Pro',      'Electronics',  89900.00, 500),
    ('ELEC-002', 'USB-C Hub 7-in-1',          'Electronics',  45000.00, 300),
    ('ELEC-003', 'Mechanical Keyboard TKL',   'Electronics', 129000.00, 150),
    ('FOOD-001', 'Premium Coffee Beans 1kg',  'Food',         35000.00, 1000),
    ('FOOD-002', 'Green Tea Set',             'Food',         28000.00, 800),
    ('CLOTH-001','Tech Hoodie Grey',          'Clothing',     65000.00, 200),
    ('CLOTH-002','Running Shorts',            'Clothing',     32000.00, 400),
    ('BOOK-001', 'Database Internals (KO)',   'Books',        42000.00, 250),
    ('BOOK-002', 'Designing Data-Intensive',  'Books',        48000.00, 200),
    ('ACC-001',  'Laptop Stand Aluminum',     'Accessories',  55000.00, 350);

-- 초기 주문 10건
INSERT INTO orders (customer_id, status, total_amount, items_count) VALUES
    (1, 'delivered',   89900.00, 1),
    (2, 'shipped',    129000.00, 1),
    (3, 'processing',  80000.00, 2),
    (4, 'pending',     35000.00, 1),
    (5, 'delivered',  113000.00, 2),
    (6, 'cancelled',   45000.00, 1),
    (7, 'shipped',     97900.00, 2),
    (8, 'processing',  42000.00, 1),
    (9, 'pending',    184000.00, 3),
    (10,'delivered',   65000.00, 1);

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
    (1,  1, 1, 89900.00),
    (2,  3, 1, 129000.00),
    (3,  6, 1, 65000.00),
    (3,  7, 1, 32000.00) ,
    (4,  4, 1, 35000.00),
    (5,  1, 1, 89900.00),
    (5,  5, 1, 28000.00) ,
    (6,  2, 1, 45000.00),
    (7,  1, 1, 89900.00),
    (7,  7, 1, 32000.00) ,
    (8,  8, 1, 42000.00),
    (9,  3, 1, 129000.00),
    (9,  2, 1, 45000.00),
    (9,  8, 1, 42000.00) ,
    (10, 6, 1, 65000.00);

SELECT 'ClickPipes CDC Demo DB initialized successfully!' AS message;
SELECT 'Replication user: clickpipes_repl / ClickPipes2024!' AS credentials;
