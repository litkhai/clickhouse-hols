# ClickHouse Cloud MySQL Interface 호환성 검증 계획서

## 문서 정보

- **작성일**: 2025-12-13
- **작성자**: Ken (Solution Architect, ClickHouse Inc.)
- **목적**: ClickHouse Cloud의 MySQL Wire Protocol 호환성 체계적 검증
- **대상**: 기술 평가팀, 고객 POC, 마이그레이션 프로젝트

---

## 목차

1. [개요](#1-개요)
2. [테스트 환경 구성](#2-테스트-환경-구성)
3. [호환성 테스트 매트릭스](#3-호환성-테스트-매트릭스)
4. [기능별 호환성 검증](#4-기능별-호환성-검증)
5. [TPC-DS 벤치마크 테스트](#5-tpc-ds-벤치마크-테스트)
6. [성능 및 부하 테스트](#6-성능-및-부하-테스트)
7. [호환성 이슈 검증](#7-호환성-이슈-검증)
8. [통합 테스트 스위트](#8-통합-테스트-스위트)
9. [결과 분석 및 보고](#9-결과-분석-및-보고)

---

## 1. 개요

### 1.1 목적

ClickHouse Cloud의 MySQL interface connector가 다양한 MySQL 클라이언트 및 드라이버와 얼마나 호환되는지 검증하고, 실제 워크로드(TPC-DS)를 통해 프로덕션 환경에서의 사용 가능성을 평가합니다.

### 1.2 검증 범위

- **클라이언트 도구**: MySQL CLI, MySQL Workbench, DBeaver 등
- **프로그래밍 언어 드라이버**: Python, Java, Node.js, Go, PHP
- **SQL 구문 호환성**: DDL, DML, 함수, 데이터 타입
- **표준 벤치마크**: TPC-DS 스키마 및 쿼리
- **성능 특성**: 연결 풀링, 배치 처리, 대용량 데이터

### 1.3 성공 기준

- 주요 MySQL 클라이언트 도구 80% 이상 연결 성공
- 언어별 MySQL 드라이버 90% 이상 기본 CRUD 작동
- TPC-DS 쿼리 70% 이상 정상 실행
- 성능: MySQL 대비 analytical 쿼리 3배 이상 향상

---

## 2. 테스트 환경 구성

### 2.1 ClickHouse Cloud 설정

#### MySQL Interface 활성화 확인

```sql
-- ClickHouse 설정 확인
SELECT * FROM system.settings WHERE name LIKE '%mysql%';

-- MySQL port 확인 (기본 9004)
SHOW SETTINGS LIKE 'mysql_port';
```

#### 연결 정보

- **Hostname**: `<chc-instance>.clickhouse.cloud`
- **Port**: 9004 (MySQL wire protocol)
- **User**: `default` (또는 커스텀 사용자)
- **SSL/TLS**: Required
- **Authentication**: Native ClickHouse 또는 MySQL-compatible

### 2.2 테스트 클라이언트 환경

#### 기본 연결 테스트

```bash
# MySQL CLI 8.0+ 사용
mysql --host=<chc-hostname> \
      --port=9004 \
      --user=default \
      --password=<password> \
      --ssl-mode=REQUIRED

# 연결 후 기본 검증
SHOW DATABASES;
USE default;
SHOW TABLES;
SELECT version();
```

### 2.3 네트워크 구성

- **Public Endpoint**: 인터넷을 통한 직접 연결
- **Private Link** (선택): VPC peering을 통한 프라이빗 연결
- **방화벽 규칙**: MySQL port (9004) 허용 확인

---

## 3. 호환성 테스트 매트릭스

### 3.1 클라이언트 도구별 테스트

| 도구 | 버전 | 연결 | 쿼리 실행 | DDL | DML | 특이사항 |
|------|------|------|----------|-----|-----|---------|
| MySQL CLI | 8.0+ | ✓ | ✓ | ✓ | ✓ | 기본 지원 |
| MySQL Workbench | 8.0+ | ? | ? | ? | ? | GUI 테스트 |
| DBeaver | Latest | ? | ? | ? | ? | 범용 도구 |
| phpMyAdmin | Latest | ? | ? | ? | ? | 웹 기반 |
| HeidiSQL | Latest | ? | ? | ? | ? | Windows |

### 3.2 언어별 드라이버 호환성

| 언어 | 드라이버 | 버전 | 검증 항목 | 상태 |
|------|---------|------|----------|------|
| Python | mysql-connector-python | 8.0+ | 기본 CRUD, Prepared statements, Transaction | 필수 |
| Python | PyMySQL | Latest | Connection pooling, SSL 연결 | 필수 |
| Java | MySQL Connector/J | 8.0+ | JDBC 표준 API, Batch operations | 필수 |
| Node.js | mysql2 | Latest | Promise/Callback, Connection pool | 필수 |
| PHP | mysqli, PDO | 7.4+ | Prepared statements, Multi-query | 권장 |
| Go | go-sql-driver/mysql | Latest | Context support, Connection lifecycle | 권장 |
| .NET | MySqlConnector | Latest | Async/await, Entity Framework | 선택 |

### 3.3 Python 연결 예제

```python
import mysql.connector
from mysql.connector import Error

def test_chc_mysql_interface():
    """ClickHouse Cloud MySQL Interface 기본 테스트"""
    try:
        # 연결 생성
        connection = mysql.connector.connect(
            host='<chc-hostname>',
            port=9004,
            user='default',
            password='<password>',
            database='default',
            ssl_disabled=False
        )
        
        cursor = connection.cursor()
        
        # Test 1: 버전 확인
        cursor.execute("SELECT version()")
        version = cursor.fetchone()
        print(f"✓ ClickHouse version: {version[0]}")
        
        # Test 2: 테이블 생성
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS test_mysql_compat (
                id UInt32,
                name String,
                created DateTime
            ) ENGINE = MergeTree()
            ORDER BY id
        """)
        print("✓ Table created successfully")
        
        # Test 3: 데이터 삽입
        cursor.execute("""
            INSERT INTO test_mysql_compat VALUES 
            (1, 'test1', now()),
            (2, 'test2', now())
        """)
        print("✓ Data inserted successfully")
        
        # Test 4: 조회
        cursor.execute("SELECT * FROM test_mysql_compat WHERE id = 1")
        result = cursor.fetchall()
        print(f"✓ Query result: {result}")
        
        # Test 5: Prepared Statement
        query = "SELECT * FROM test_mysql_compat WHERE id = %s"
        cursor.execute(query, (2,))
        result = cursor.fetchall()
        print(f"✓ Prepared statement result: {result}")
        
        # Clean up
        cursor.execute("DROP TABLE IF EXISTS test_mysql_compat")
        print("✓ Cleanup completed")
        
        cursor.close()
        connection.close()
        
        return True
        
    except Error as e:
        print(f"✗ Error: {e}")
        return False

if __name__ == "__main__":
    success = test_chc_mysql_interface()
    exit(0 if success else 1)
```

---

## 4. 기능별 호환성 검증

### 4.1 SQL 구문 호환성

#### DDL 명령어 테스트

```sql
-- 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS mysql_test_db;

-- MySQL 스타일 테이블 생성
CREATE TABLE mysql_test_db.users (
    id INT PRIMARY KEY,
    username VARCHAR(50),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 테이블 수정
ALTER TABLE mysql_test_db.users ADD COLUMN last_login DATETIME;

-- 테이블 삭제
DROP TABLE IF EXISTS mysql_test_db.users;
```

#### DML 명령어 테스트

```sql
-- INSERT (단일/다중)
INSERT INTO users VALUES (1, 'john', 'john@example.com', now());
INSERT INTO users (id, username, email) VALUES 
    (2, 'jane', 'jane@example.com'),
    (3, 'bob', 'bob@example.com');

-- UPDATE
UPDATE users SET last_login = now() WHERE id = 1;

-- DELETE
DELETE FROM users WHERE id = 3;

-- SELECT with JOIN
SELECT u.id, u.username, o.order_id
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.created_at > '2025-01-01';
```

### 4.2 MySQL 함수 호환성

#### 날짜/시간 함수

```sql
SELECT 
    NOW(),
    CURDATE(),
    CURTIME(),
    DATE_FORMAT(created_at, '%Y-%m-%d') as formatted_date,
    UNIX_TIMESTAMP(created_at),
    FROM_UNIXTIME(1234567890),
    DATE_ADD(created_at, INTERVAL 7 DAY) as next_week,
    DATEDIFF(NOW(), created_at) as days_since,
    YEAR(created_at) as year,
    MONTH(created_at) as month,
    DAY(created_at) as day,
    QUARTER(created_at) as quarter,
    WEEK(created_at) as week_number
FROM users;
```

#### 문자열 함수

```sql
SELECT 
    CONCAT(username, '@', email) as contact,
    SUBSTRING(email, 1, 5) as email_prefix,
    LENGTH(username) as name_length,
    UPPER(username) as uppercase,
    LOWER(email) as lowercase,
    REPLACE(email, '@example.com', '@newdomain.com') as new_email,
    TRIM(username) as trimmed,
    LOCATE('@', email) as at_position
FROM users;
```

#### 집계 함수

```sql
SELECT 
    COUNT(*) as total_count,
    COUNT(DISTINCT username) as unique_users,
    SUM(id) as sum_ids,
    AVG(id) as avg_id,
    MIN(created_at) as first_created,
    MAX(created_at) as last_created,
    GROUP_CONCAT(username) as all_usernames
FROM users;
```

### 4.3 데이터 타입 호환성

```sql
CREATE TABLE type_compatibility_test (
    -- 숫자형
    tiny_int TINYINT,
    small_int SMALLINT,
    medium_int MEDIUMINT,
    int_col INT,
    big_int BIGINT,
    float_col FLOAT,
    double_col DOUBLE,
    decimal_col DECIMAL(10,2),
    
    -- 문자열
    char_col CHAR(10),
    varchar_col VARCHAR(255),
    text_col TEXT,
    
    -- 날짜/시간
    date_col DATE,
    datetime_col DATETIME,
    timestamp_col TIMESTAMP,
    
    -- 기타
    enum_col ENUM('a', 'b', 'c'),
    json_col JSON
) ENGINE = MergeTree() ORDER BY int_col;

-- 데이터 삽입 및 검증
INSERT INTO type_compatibility_test VALUES (
    127, 32767, 8388607, 2147483647, 9223372036854775807,
    3.14, 3.14159265359, 123.45,
    'test', 'varchar test', 'text content',
    '2025-01-01', '2025-01-01 12:00:00', '2025-01-01 12:00:00',
    'a', '{"key": "value"}'
);

-- 타입 검증
SELECT 
    typeof(tiny_int), typeof(decimal_col), 
    typeof(varchar_col), typeof(json_col)
FROM type_compatibility_test;
```

### 4.4 트랜잭션 및 고급 기능

```sql
-- Transaction (제한적 지원)
START TRANSACTION;
INSERT INTO users VALUES (4, 'test', 'test@example.com', now());
COMMIT;

-- Prepared Statements (드라이버 레벨에서 테스트)
-- 아래는 MySQL 프로토콜을 통한 예시
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @id = 1;
EXECUTE stmt USING @id;
DEALLOCATE PREPARE stmt;
```

### 4.5 Character Set / Collation

```sql
-- Character set 지원 확인
SHOW CHARACTER SET;
SHOW COLLATION;

-- UTF-8 데이터 처리
CREATE TABLE utf8_test (
    id INT,
    korean VARCHAR(100),
    emoji VARCHAR(100),
    mixed TEXT
) CHARACTER SET utf8mb4;

INSERT INTO utf8_test VALUES 
    (1, '한글 테스트', '😀 emoji test', '混合 مرحبا Hello');

SELECT * FROM utf8_test;
```

---

## 5. TPC-DS 벤치마크 테스트

### 5.1 데이터베이스 생성

```sql
-- MySQL Interface를 통해 전용 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS mysql_interface;
USE mysql_interface;

-- 데이터베이스 확인
SHOW DATABASES;
SELECT currentDatabase();
```

### 5.2 TPC-DS 스키마 생성

#### 5.2.1 Fact Table: store_sales

```sql
CREATE TABLE mysql_interface.store_sales (
    ss_sold_date_sk INT,
    ss_sold_time_sk INT,
    ss_item_sk INT,
    ss_customer_sk INT,
    ss_cdemo_sk INT,
    ss_hdemo_sk INT,
    ss_addr_sk INT,
    ss_store_sk INT,
    ss_promo_sk INT,
    ss_ticket_number BIGINT,
    ss_quantity INT,
    ss_wholesale_cost DECIMAL(7,2),
    ss_list_price DECIMAL(7,2),
    ss_sales_price DECIMAL(7,2),
    ss_ext_discount_amt DECIMAL(7,2),
    ss_ext_sales_price DECIMAL(7,2),
    ss_ext_wholesale_cost DECIMAL(7,2),
    ss_ext_list_price DECIMAL(7,2),
    ss_ext_tax DECIMAL(7,2),
    ss_coupon_amt DECIMAL(7,2),
    ss_net_paid DECIMAL(7,2),
    ss_net_paid_inc_tax DECIMAL(7,2),
    ss_net_profit DECIMAL(7,2)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(toDate(ss_sold_date_sk))
ORDER BY (ss_sold_date_sk, ss_item_sk, ss_customer_sk);
```

#### 5.2.2 Dimension Tables

```sql
-- customer (고객 정보)
CREATE TABLE mysql_interface.customer (
    c_customer_sk INT,
    c_customer_id VARCHAR(16),
    c_current_cdemo_sk INT,
    c_current_hdemo_sk INT,
    c_current_addr_sk INT,
    c_first_shipto_date_sk INT,
    c_first_sales_date_sk INT,
    c_salutation VARCHAR(10),
    c_first_name VARCHAR(20),
    c_last_name VARCHAR(30),
    c_preferred_cust_flag VARCHAR(1),
    c_birth_day INT,
    c_birth_month INT,
    c_birth_year INT,
    c_birth_country VARCHAR(20),
    c_login VARCHAR(13),
    c_email_address VARCHAR(50),
    c_last_review_date VARCHAR(10)
) ENGINE = MergeTree()
ORDER BY c_customer_sk;

-- date_dim (날짜 차원)
CREATE TABLE mysql_interface.date_dim (
    d_date_sk INT,
    d_date_id VARCHAR(16),
    d_date DATE,
    d_month_seq INT,
    d_week_seq INT,
    d_quarter_seq INT,
    d_year INT,
    d_dow INT,
    d_moy INT,
    d_dom INT,
    d_qoy INT,
    d_fy_year INT,
    d_fy_quarter_seq INT,
    d_fy_week_seq INT,
    d_day_name VARCHAR(9),
    d_quarter_name VARCHAR(6),
    d_holiday VARCHAR(1),
    d_weekend VARCHAR(1),
    d_following_holiday VARCHAR(1),
    d_first_dom INT,
    d_last_dom INT,
    d_same_day_ly INT,
    d_same_day_lq INT,
    d_current_day VARCHAR(1),
    d_current_week VARCHAR(1),
    d_current_month VARCHAR(1),
    d_current_quarter VARCHAR(1),
    d_current_year VARCHAR(1)
) ENGINE = MergeTree()
ORDER BY d_date_sk;

-- item (상품 정보)
CREATE TABLE mysql_interface.item (
    i_item_sk INT,
    i_item_id VARCHAR(16),
    i_rec_start_date DATE,
    i_rec_end_date DATE,
    i_item_desc VARCHAR(200),
    i_current_price DECIMAL(7,2),
    i_wholesale_cost DECIMAL(7,2),
    i_brand_id INT,
    i_brand VARCHAR(50),
    i_class_id INT,
    i_class VARCHAR(50),
    i_category_id INT,
    i_category VARCHAR(50),
    i_manufact_id INT,
    i_manufact VARCHAR(50),
    i_size VARCHAR(20),
    i_formulation VARCHAR(20),
    i_color VARCHAR(20),
    i_units VARCHAR(10),
    i_container VARCHAR(10),
    i_manager_id INT,
    i_product_name VARCHAR(50)
) ENGINE = MergeTree()
ORDER BY i_item_sk;

-- store (매장 정보)
CREATE TABLE mysql_interface.store (
    s_store_sk INT,
    s_store_id VARCHAR(16),
    s_rec_start_date DATE,
    s_rec_end_date DATE,
    s_closed_date_sk INT,
    s_store_name VARCHAR(50),
    s_number_employees INT,
    s_floor_space INT,
    s_hours VARCHAR(20),
    s_manager VARCHAR(40),
    s_market_id INT,
    s_geography_class VARCHAR(100),
    s_market_desc VARCHAR(100),
    s_market_manager VARCHAR(40),
    s_division_id INT,
    s_division_name VARCHAR(50),
    s_company_id INT,
    s_company_name VARCHAR(50),
    s_street_number VARCHAR(10),
    s_street_name VARCHAR(60),
    s_street_type VARCHAR(15),
    s_suite_number VARCHAR(10),
    s_city VARCHAR(60),
    s_county VARCHAR(30),
    s_state VARCHAR(2),
    s_zip VARCHAR(10),
    s_country VARCHAR(20),
    s_gmt_offset DECIMAL(5,2),
    s_tax_precentage DECIMAL(5,2)
) ENGINE = MergeTree()
ORDER BY s_store_sk;

-- customer_demographics (고객 인구통계)
CREATE TABLE mysql_interface.customer_demographics (
    cd_demo_sk INT,
    cd_gender VARCHAR(1),
    cd_marital_status VARCHAR(1),
    cd_education_status VARCHAR(20),
    cd_purchase_estimate INT,
    cd_credit_rating VARCHAR(10),
    cd_dep_count INT,
    cd_dep_employed_count INT,
    cd_dep_college_count INT
) ENGINE = MergeTree()
ORDER BY cd_demo_sk;

-- household_demographics (가구 인구통계)
CREATE TABLE mysql_interface.household_demographics (
    hd_demo_sk INT,
    hd_income_band_sk INT,
    hd_buy_potential VARCHAR(15),
    hd_dep_count INT,
    hd_vehicle_count INT
) ENGINE = MergeTree()
ORDER BY hd_demo_sk;

-- customer_address (고객 주소)
CREATE TABLE mysql_interface.customer_address (
    ca_address_sk INT,
    ca_address_id VARCHAR(16),
    ca_street_number VARCHAR(10),
    ca_street_name VARCHAR(60),
    ca_street_type VARCHAR(15),
    ca_suite_number VARCHAR(10),
    ca_city VARCHAR(60),
    ca_county VARCHAR(30),
    ca_state VARCHAR(2),
    ca_zip VARCHAR(10),
    ca_country VARCHAR(20),
    ca_gmt_offset DECIMAL(5,2),
    ca_location_type VARCHAR(20)
) ENGINE = MergeTree()
ORDER BY ca_address_sk;

-- promotion (프로모션 정보)
CREATE TABLE mysql_interface.promotion (
    p_promo_sk INT,
    p_promo_id VARCHAR(16),
    p_start_date_sk INT,
    p_end_date_sk INT,
    p_item_sk INT,
    p_cost DECIMAL(15,2),
    p_response_target INT,
    p_promo_name VARCHAR(50),
    p_channel_dmail VARCHAR(1),
    p_channel_email VARCHAR(1),
    p_channel_catalog VARCHAR(1),
    p_channel_tv VARCHAR(1),
    p_channel_radio VARCHAR(1),
    p_channel_press VARCHAR(1),
    p_channel_event VARCHAR(1),
    p_channel_demo VARCHAR(1),
    p_channel_details VARCHAR(100),
    p_purpose VARCHAR(15),
    p_discount_active VARCHAR(1)
) ENGINE = MergeTree()
ORDER BY p_promo_sk;

-- time_dim (시간 차원)
CREATE TABLE mysql_interface.time_dim (
    t_time_sk INT,
    t_time_id VARCHAR(16),
    t_time INT,
    t_hour INT,
    t_minute INT,
    t_second INT,
    t_am_pm VARCHAR(2),
    t_shift VARCHAR(20),
    t_sub_shift VARCHAR(20),
    t_meal_time VARCHAR(20)
) ENGINE = MergeTree()
ORDER BY t_time_sk;
```

#### 5.2.3 스키마 검증

```sql
-- 생성된 테이블 목록 확인
SHOW TABLES FROM mysql_interface;

-- 각 테이블의 구조 확인
DESCRIBE mysql_interface.store_sales;
DESCRIBE mysql_interface.customer;

-- 시스템 테이블에서 확인
SELECT 
    database,
    name as table_name,
    engine,
    total_rows,
    total_bytes,
    formatReadableSize(total_bytes) as size
FROM system.tables
WHERE database = 'mysql_interface'
ORDER BY total_bytes DESC;
```

### 5.3 샘플 데이터 생성 (Python)

```python
import mysql.connector
from datetime import datetime, timedelta
import random
from decimal import Decimal

def connect_via_mysql_interface():
    """MySQL interface로 ClickHouse 연결"""
    return mysql.connector.connect(
        host='<chc-hostname>',
        port=9004,
        user='default',
        password='<password>',
        database='mysql_interface',
        ssl_disabled=False
    )

def generate_date_dim_data(start_date, days=365):
    """날짜 차원 데이터 생성"""
    data = []
    for i in range(days):
        date = start_date + timedelta(days=i)
        data.append((
            i + 1,  # d_date_sk
            f'DATE{i+1:08d}',  # d_date_id
            date,  # d_date
            date.year * 12 + date.month,  # d_month_seq
            i // 7 + 1,  # d_week_seq
            (date.year * 4) + ((date.month - 1) // 3),  # d_quarter_seq
            date.year,  # d_year
            date.weekday(),  # d_dow
            date.month,  # d_moy
            date.day,  # d_dom
            ((date.month - 1) // 3) + 1,  # d_qoy
            date.year,  # d_fy_year
            None, None,  # d_fy_quarter_seq, d_fy_week_seq
            date.strftime('%A'),  # d_day_name
            f'Q{((date.month-1)//3)+1}',  # d_quarter_name
            'N',  # d_holiday
            'Y' if date.weekday() >= 5 else 'N',  # d_weekend
            'N', date.day, date.day,
            None, None,
            'N', 'N', 'N', 'N', 'N'
        ))
    return data

def generate_customer_data(num_customers=10000):
    """고객 데이터 생성"""
    first_names = ['John', 'Jane', 'Michael', 'Sarah', 'David', 'Emily', 'James', 'Jessica']
    last_names = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis']
    
    data = []
    for i in range(1, num_customers + 1):
        data.append((
            i,  # c_customer_sk
            f'CUST{i:010d}',
            random.randint(1, 10000),
            random.randint(1, 1000),
            random.randint(1, 50000),
            random.randint(1, 365),
            random.randint(1, 365),
            random.choice(['Mr.', 'Mrs.', 'Ms.', 'Dr.']),
            random.choice(first_names),
            random.choice(last_names),
            random.choice(['Y', 'N']),
            random.randint(1, 28),
            random.randint(1, 12),
            random.randint(1950, 2000),
            'United States',
            None,
            f'customer{i}@example.com',
            None
        ))
    return data

def generate_item_data(num_items=5000):
    """상품 데이터 생성"""
    brands = ['BrandA', 'BrandB', 'BrandC', 'BrandD']
    categories = ['Electronics', 'Clothing', 'Home', 'Sports']
    colors = ['Red', 'Blue', 'Green', 'Black', 'White']
    
    data = []
    for i in range(1, num_items + 1):
        data.append((
            i,
            f'ITEM{i:010d}',
            datetime(2020, 1, 1).date(),
            None,
            f'Product description for item {i}',
            Decimal(random.uniform(10, 1000)).quantize(Decimal('0.01')),
            Decimal(random.uniform(5, 500)).quantize(Decimal('0.01')),
            random.randint(1, 100),
            random.choice(brands),
            random.randint(1, 50),
            f'Class{random.randint(1, 50)}',
            random.randint(1, 10),
            random.choice(categories),
            random.randint(1, 1000),
            f'Manufacturer{random.randint(1, 100)}',
            random.choice(['Small', 'Medium', 'Large']),
            f'Formula{random.randint(1, 10)}',
            random.choice(colors),
            'Each',
            'Box',
            random.randint(1, 100),
            f'Product {i}'
        ))
    return data

def generate_store_sales_data(num_sales=100000):
    """매출 데이터 생성"""
    data = []
    for i in range(num_sales):
        quantity = random.randint(1, 10)
        list_price = Decimal(random.uniform(10, 500)).quantize(Decimal('0.01'))
        discount_pct = Decimal(random.uniform(0, 0.3))
        sales_price = (list_price * (1 - discount_pct)).quantize(Decimal('0.01'))
        wholesale_cost = (list_price * Decimal('0.6')).quantize(Decimal('0.01'))
        
        ext_list_price = (list_price * quantity).quantize(Decimal('0.01'))
        ext_sales_price = (sales_price * quantity).quantize(Decimal('0.01'))
        ext_wholesale_cost = (wholesale_cost * quantity).quantize(Decimal('0.01'))
        ext_discount_amt = (ext_list_price - ext_sales_price).quantize(Decimal('0.01'))
        ext_tax = (ext_sales_price * Decimal('0.08')).quantize(Decimal('0.01'))
        net_paid = ext_sales_price
        net_paid_inc_tax = (ext_sales_price + ext_tax).quantize(Decimal('0.01'))
        net_profit = (ext_sales_price - ext_wholesale_cost).quantize(Decimal('0.01'))
        
        data.append((
            random.randint(1, 365),
            random.randint(1, 86400),
            random.randint(1, 5000),
            random.randint(1, 10000),
            random.randint(1, 10000),
            random.randint(1, 1000),
            random.randint(1, 50000),
            random.randint(1, 100),
            random.randint(1, 500),
            i + 1,
            quantity,
            wholesale_cost,
            list_price,
            sales_price,
            ext_discount_amt,
            ext_sales_price,
            ext_wholesale_cost,
            ext_list_price,
            ext_tax,
            Decimal('0.00'),
            net_paid,
            net_paid_inc_tax,
            net_profit
        ))
    return data

def bulk_insert_data(connection, table_name, columns, data, batch_size=1000):
    """대용량 데이터 배치 삽입"""
    cursor = connection.cursor()
    placeholders = ', '.join(['%s'] * len(columns))
    query = f"INSERT INTO {table_name} ({', '.join(columns)}) VALUES ({placeholders})"
    
    total_inserted = 0
    for i in range(0, len(data), batch_size):
        batch = data[i:i + batch_size]
        cursor.executemany(query, batch)
        total_inserted += len(batch)
        if total_inserted % 10000 == 0:
            print(f"  Progress: {total_inserted} rows")
    
    cursor.close()
    print(f"  ✓ Total: {total_inserted} rows")

# 메인 실행
if __name__ == "__main__":
    print("=" * 60)
    print("TPC-DS Data Loading via MySQL Interface")
    print("=" * 60)
    
    conn = connect_via_mysql_interface()
    
    print("\n[1/4] Loading date_dim...")
    date_data = generate_date_dim_data(datetime(2024, 1, 1), days=730)
    date_columns = ['d_date_sk', 'd_date_id', 'd_date', 'd_month_seq', 'd_week_seq', 
                    'd_quarter_seq', 'd_year', 'd_dow', 'd_moy', 'd_dom', 'd_qoy', 
                    'd_fy_year', 'd_fy_quarter_seq', 'd_fy_week_seq', 'd_day_name', 
                    'd_quarter_name', 'd_holiday', 'd_weekend', 'd_following_holiday', 
                    'd_first_dom', 'd_last_dom', 'd_same_day_ly', 'd_same_day_lq', 
                    'd_current_day', 'd_current_week', 'd_current_month', 'd_current_quarter', 
                    'd_current_year']
    bulk_insert_data(conn, 'mysql_interface.date_dim', date_columns, date_data)
    
    print("\n[2/4] Loading customer...")
    customer_data = generate_customer_data(10000)
    customer_columns = ['c_customer_sk', 'c_customer_id', 'c_current_cdemo_sk', 'c_current_hdemo_sk',
                        'c_current_addr_sk', 'c_first_shipto_date_sk', 'c_first_sales_date_sk',
                        'c_salutation', 'c_first_name', 'c_last_name', 'c_preferred_cust_flag',
                        'c_birth_day', 'c_birth_month', 'c_birth_year', 'c_birth_country',
                        'c_login', 'c_email_address', 'c_last_review_date']
    bulk_insert_data(conn, 'mysql_interface.customer', customer_columns, customer_data)
    
    print("\n[3/4] Loading item...")
    item_data = generate_item_data(5000)
    item_columns = ['i_item_sk', 'i_item_id', 'i_rec_start_date', 'i_rec_end_date', 'i_item_desc',
                    'i_current_price', 'i_wholesale_cost', 'i_brand_id', 'i_brand', 'i_class_id',
                    'i_class', 'i_category_id', 'i_category', 'i_manufact_id', 'i_manufact',
                    'i_size', 'i_formulation', 'i_color', 'i_units', 'i_container',
                    'i_manager_id', 'i_product_name']
    bulk_insert_data(conn, 'mysql_interface.item', item_columns, item_data)
    
    print("\n[4/4] Loading store_sales...")
    sales_data = generate_store_sales_data(100000)
    sales_columns = ['ss_sold_date_sk', 'ss_sold_time_sk', 'ss_item_sk', 'ss_customer_sk',
                     'ss_cdemo_sk', 'ss_hdemo_sk', 'ss_addr_sk', 'ss_store_sk', 'ss_promo_sk',
                     'ss_ticket_number', 'ss_quantity', 'ss_wholesale_cost', 'ss_list_price',
                     'ss_sales_price', 'ss_ext_discount_amt', 'ss_ext_sales_price',
                     'ss_ext_wholesale_cost', 'ss_ext_list_price', 'ss_ext_tax', 'ss_coupon_amt',
                     'ss_net_paid', 'ss_net_paid_inc_tax', 'ss_net_profit']
    bulk_insert_data(conn, 'mysql_interface.store_sales', sales_columns, sales_data)
    
    conn.close()
    print("\n" + "=" * 60)
    print("✓ Data Loading Completed Successfully!")
    print("=" * 60)
```

### 5.4 TPC-DS 쿼리 호환성 테스트

#### Q1: 일별 매출 집계

```sql
SELECT 
    d.d_year,
    d.d_moy as month,
    COUNT(DISTINCT ss.ss_customer_sk) as customer_count,
    SUM(ss.ss_quantity) as total_quantity,
    SUM(ss.ss_sales_price) as total_sales,
    AVG(ss.ss_sales_price) as avg_sale_price
FROM mysql_interface.store_sales ss
JOIN mysql_interface.date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
WHERE d.d_year = 2024
GROUP BY d.d_year, d.d_moy
ORDER BY d.d_year, d.d_moy;
```

#### Q2: 고객별 구매 패턴 분석

```sql
SELECT 
    c.c_customer_id,
    c.c_first_name,
    c.c_last_name,
    c.c_email_address,
    COUNT(DISTINCT ss.ss_ticket_number) as num_purchases,
    SUM(ss.ss_quantity) as total_items,
    SUM(ss.ss_net_paid) as total_spent,
    AVG(ss.ss_net_paid) as avg_purchase_value,
    MAX(d.d_date) as last_purchase_date
FROM mysql_interface.customer c
JOIN mysql_interface.store_sales ss ON c.c_customer_sk = ss.ss_customer_sk
JOIN mysql_interface.date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
WHERE d.d_year = 2024
GROUP BY c.c_customer_id, c.c_first_name, c.c_last_name, c.c_email_address
HAVING SUM(ss.ss_net_paid) > 1000
ORDER BY total_spent DESC
LIMIT 100;
```

#### Q3: 상품 카테고리별 매출 순위 (윈도우 함수)

```sql
SELECT 
    i.i_category,
    i.i_brand,
    SUM(ss.ss_net_paid) as category_sales,
    RANK() OVER (
        PARTITION BY i.i_category 
        ORDER BY SUM(ss.ss_net_paid) DESC
    ) as sales_rank
FROM mysql_interface.store_sales ss
JOIN mysql_interface.item i ON ss.ss_item_sk = i.i_item_sk
JOIN mysql_interface.date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
WHERE d.d_year = 2024
GROUP BY i.i_category, i.i_brand
ORDER BY i.i_category, sales_rank
LIMIT 50;
```

#### Q4: 시계열 분석 (이동 평균)

```sql
SELECT 
    d.d_date,
    SUM(ss.ss_net_paid) as daily_sales,
    AVG(SUM(ss.ss_net_paid)) OVER (
        ORDER BY d.d_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as moving_avg_7days,
    SUM(SUM(ss.ss_net_paid)) OVER (
        PARTITION BY d.d_year, d.d_moy 
        ORDER BY d.d_date
    ) as month_to_date_sales
FROM mysql_interface.store_sales ss
JOIN mysql_interface.date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
WHERE d.d_year = 2024 AND d.d_moy = 1
GROUP BY d.d_date, d.d_year, d.d_moy
ORDER BY d.d_date;
```

#### Q5: 고가치 상품 분석

```sql
SELECT 
    i.i_category,
    i.i_class,
    COUNT(DISTINCT i.i_item_sk) as item_count,
    AVG(i.i_current_price) as avg_price,
    SUM(ss.ss_quantity) as total_sold,
    SUM(ss.ss_net_profit) as total_profit,
    SUM(ss.ss_net_profit) / NULLIF(SUM(ss.ss_net_paid), 0) * 100 as profit_margin_pct
FROM mysql_interface.item i
JOIN mysql_interface.store_sales ss ON i.i_item_sk = ss.ss_item_sk
GROUP BY i.i_category, i.i_class
HAVING SUM(ss.ss_quantity) > 100
    AND SUM(ss.ss_net_profit) > 0
ORDER BY profit_margin_pct DESC
LIMIT 20;
```

#### Q6: 고객 세그먼트 분석 (CASE WHEN)

```sql
SELECT 
    CASE 
        WHEN customer_total BETWEEN 0 AND 500 THEN 'Low Value'
        WHEN customer_total BETWEEN 501 AND 2000 THEN 'Medium Value'
        WHEN customer_total > 2000 THEN 'High Value'
    END as customer_segment,
    COUNT(*) as customer_count,
    AVG(customer_total) as avg_spend,
    SUM(customer_total) as segment_revenue
FROM (
    SELECT 
        c.c_customer_sk,
        SUM(ss.ss_net_paid) as customer_total
    FROM mysql_interface.customer c
    JOIN mysql_interface.store_sales ss ON c.c_customer_sk = ss.ss_customer_sk
    GROUP BY c.c_customer_sk
) customer_totals
GROUP BY customer_segment
ORDER BY segment_revenue DESC;
```

#### Q7: 날짜 함수 종합 테스트

```sql
SELECT 
    d.d_date,
    YEAR(d.d_date) as year,
    MONTH(d.d_date) as month,
    DAY(d.d_date) as day,
    DAYOFWEEK(d.d_date) as day_of_week,
    QUARTER(d.d_date) as quarter,
    WEEK(d.d_date) as week_number,
    DATE_FORMAT(d.d_date, '%Y-%m-%d') as formatted_date,
    DATE_ADD(d.d_date, INTERVAL 7 DAY) as next_week,
    DATEDIFF(CURDATE(), d.d_date) as days_ago,
    COUNT(*) as num_sales,
    SUM(ss.ss_net_paid) as daily_revenue
FROM mysql_interface.date_dim d
LEFT JOIN mysql_interface.store_sales ss ON d.d_date_sk = ss.ss_sold_date_sk
WHERE d.d_year = 2024 AND d.d_moy = 1
GROUP BY d.d_date
ORDER BY d.d_date
LIMIT 31;
```

#### Q8: 문자열 함수 종합 테스트

```sql
SELECT 
    c.c_customer_id,
    CONCAT(c.c_first_name, ' ', c.c_last_name) as full_name,
    UPPER(c.c_email_address) as email_upper,
    LOWER(c.c_email_address) as email_lower,
    SUBSTRING(c.c_email_address, 1, LOCATE('@', c.c_email_address) - 1) as email_prefix,
    LENGTH(c.c_last_name) as lastname_length,
    REPLACE(c.c_email_address, '@example.com', '@newdomain.com') as new_email
FROM mysql_interface.customer c
LIMIT 20;
```

#### Q9: 서브쿼리 및 EXISTS

```sql
SELECT 
    i.i_item_id,
    i.i_product_name,
    i.i_current_price,
    i.i_category
FROM mysql_interface.item i
WHERE EXISTS (
    SELECT 1
    FROM mysql_interface.store_sales ss
    WHERE ss.ss_item_sk = i.i_item_sk
        AND ss.ss_net_profit > 100
)
AND i.i_current_price > (
    SELECT AVG(i2.i_current_price)
    FROM mysql_interface.item i2
    WHERE i2.i_category = i.i_category
)
ORDER BY i.i_current_price DESC
LIMIT 50;
```

#### Q10: CTE (Common Table Expression)

```sql
WITH monthly_sales AS (
    SELECT 
        d.d_year,
        d.d_moy,
        SUM(ss.ss_net_paid) as monthly_revenue,
        COUNT(DISTINCT ss.ss_customer_sk) as unique_customers
    FROM mysql_interface.store_sales ss
    JOIN mysql_interface.date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
    WHERE d.d_year = 2024
    GROUP BY d.d_year, d.d_moy
),
avg_metrics AS (
    SELECT 
        AVG(monthly_revenue) as avg_monthly_revenue,
        AVG(unique_customers) as avg_monthly_customers
    FROM monthly_sales
)
SELECT 
    ms.d_year,
    ms.d_moy,
    ms.monthly_revenue,
    ms.unique_customers,
    am.avg_monthly_revenue,
    ms.monthly_revenue - am.avg_monthly_revenue as revenue_vs_avg,
    (ms.monthly_revenue / am.avg_monthly_revenue - 1) * 100 as revenue_pct_diff
FROM monthly_sales ms
CROSS JOIN avg_metrics am
ORDER BY ms.d_year, ms.d_moy;
```

---

## 6. 성능 및 부하 테스트

### 6.1 연결 풀 테스트

```python
from mysql.connector import pooling
import concurrent.futures
import time

def test_connection_pool():
    """Connection pool 성능 테스트"""
    
    # Connection pool 생성
    pool = pooling.MySQLConnectionPool(
        pool_name="chc_pool",
        pool_size=10,
        host='<chc-hostname>',
        port=9004,
        user='default',
        password='<password>',
        database='mysql_interface'
    )
    
    def execute_query(pool, query_id):
        """단일 쿼리 실행"""
        connection = pool.get_connection()
        cursor = connection.cursor()
        
        start_time = time.time()
        cursor.execute("SELECT count(*) FROM system.tables")
        result = cursor.fetchone()
        execution_time = time.time() - start_time
        
        cursor.close()
        connection.close()
        
        return (query_id, execution_time, result)
    
    # 동시 연결 테스트
    num_queries = 100
    print(f"Testing {num_queries} concurrent queries...")
    
    start_total = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        futures = [executor.submit(execute_query, pool, i) for i in range(num_queries)]
        results = [f.result() for f in concurrent.futures.as_completed(futures)]
    end_total = time.time()
    
    # 결과 분석
    execution_times = [r[1] for r in results]
    avg_time = sum(execution_times) / len(execution_times)
    
    print(f"\n✓ Completed {len(results)} queries")
    print(f"  Total time: {end_total - start_total:.2f}s")
    print(f"  Average query time: {avg_time:.3f}s")
    print(f"  Throughput: {num_queries / (end_total - start_total):.1f} queries/sec")

if __name__ == "__main__":
    test_connection_pool()
```

### 6.2 대용량 데이터 처리 벤치마크

```python
import mysql.connector
import time
from decimal import Decimal
import random

def benchmark_batch_insert(connection, batch_sizes=[100, 1000, 10000]):
    """배치 insert 성능 테스트"""
    
    cursor = connection.cursor()
    
    # 테스트 테이블 생성
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS mysql_interface.perf_test (
            id INT,
            value DECIMAL(10,2),
            text VARCHAR(100),
            created DATETIME
        ) ENGINE = MergeTree()
        ORDER BY id
    """)
    
    results = []
    
    for batch_size in batch_sizes:
        # 테이블 초기화
        cursor.execute("TRUNCATE TABLE mysql_interface.perf_test")
        
        # 테스트 데이터 생성
        values = [
            (i, Decimal(random.uniform(1, 1000)).quantize(Decimal('0.01')), 
             f'text_{i}', '2025-01-01 00:00:00')
            for i in range(batch_size)
        ]
        
        # 삽입 성능 측정
        start_time = time.time()
        cursor.executemany(
            "INSERT INTO mysql_interface.perf_test VALUES (%s, %s, %s, %s)",
            values
        )
        end_time = time.time()
        
        execution_time = end_time - start_time
        throughput = batch_size / execution_time
        
        results.append({
            'batch_size': batch_size,
            'time': execution_time,
            'throughput': throughput
        })
        
        print(f"Batch size {batch_size:>6}: {execution_time:.3f}s ({throughput:.0f} rows/sec)")
    
    # 정리
    cursor.execute("DROP TABLE IF EXISTS mysql_interface.perf_test")
    cursor.close()
    
    return results

if __name__ == "__main__":
    conn = mysql.connector.connect(
        host='<chc-hostname>',
        port=9004,
        user='default',
        password='<password>',
        database='mysql_interface'
    )
    
    print("\n" + "=" * 60)
    print("Batch Insert Performance Test")
    print("=" * 60 + "\n")
    
    results = benchmark_batch_insert(conn)
    
    conn.close()
```

### 6.3 쿼리 성능 벤치마크

```python
import mysql.connector
import time

def benchmark_query(connection, query_name, query, iterations=3):
    """쿼리 성능 측정"""
    cursor = connection.cursor()
    execution_times = []
    
    print(f"\n{'='*60}")
    print(f"Query: {query_name}")
    print(f"{'='*60}")
    
    for i in range(iterations):
        start_time = time.time()
        cursor.execute(query)
        results = cursor.fetchall()
        end_time = time.time()
        
        execution_time = end_time - start_time
        execution_times.append(execution_time)
        
        print(f"  Run {i+1}: {execution_time:.3f}s (Rows: {len(results)})")
    
    cursor.close()
    
    avg_time = sum(execution_times) / len(execution_times)
    min_time = min(execution_times)
    max_time = max(execution_times)
    
    print(f"\n  Statistics:")
    print(f"    Average: {avg_time:.3f}s")
    print(f"    Min:     {min_time:.3f}s")
    print(f"    Max:     {max_time:.3f}s")
    
    return {
        'query_name': query_name,
        'avg_time': avg_time,
        'min_time': min_time,
        'max_time': max_time,
        'row_count': len(results) if results else 0
    }

# TPC-DS 쿼리 벤치마크
tpcds_benchmark_queries = {
    "Q1_Simple_Aggregation": """
        SELECT d.d_year, d.d_moy, 
               COUNT(DISTINCT ss.ss_customer_sk) as customers,
               SUM(ss.ss_net_paid) as revenue
        FROM mysql_interface.store_sales ss
        JOIN mysql_interface.date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
        WHERE d.d_year = 2024
        GROUP BY d.d_year, d.d_moy
    """,
    
    "Q2_Complex_Join": """
        SELECT i.i_category, 
               COUNT(DISTINCT c.c_customer_sk) as unique_customers,
               SUM(ss.ss_net_profit) as profit
        FROM mysql_interface.store_sales ss
        JOIN mysql_interface.item i ON ss.ss_item_sk = i.i_item_sk
        JOIN mysql_interface.customer c ON ss.ss_customer_sk = c.c_customer_sk
        JOIN mysql_interface.date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
        WHERE d.d_year = 2024
        GROUP BY i.i_category
        ORDER BY profit DESC
    """,
    
    "Q3_Window_Function": """
        SELECT i.i_category, i.i_brand, 
               SUM(ss.ss_net_paid) as sales,
               RANK() OVER (PARTITION BY i.i_category ORDER BY SUM(ss.ss_net_paid) DESC) as rank
        FROM mysql_interface.store_sales ss
        JOIN mysql_interface.item i ON ss.ss_item_sk = i.i_item_sk
        GROUP BY i.i_category, i.i_brand
        LIMIT 100
    """,
    
    "Q4_Subquery": """
        SELECT c.c_customer_id, 
               COUNT(*) as purchases,
               SUM(ss.ss_net_paid) as total_spent
        FROM mysql_interface.customer c
        JOIN mysql_interface.store_sales ss ON c.c_customer_sk = ss.ss_customer_sk
        GROUP BY c.c_customer_id
        HAVING SUM(ss.ss_net_paid) > (
            SELECT AVG(total) FROM (
                SELECT SUM(ss2.ss_net_paid) as total
                FROM mysql_interface.store_sales ss2
                GROUP BY ss2.ss_customer_sk
            ) avg_calc
        )
        LIMIT 100
    """
}

# 벤치마크 실행
if __name__ == "__main__":
    conn = mysql.connector.connect(
        host='<chc-hostname>',
        port=9004,
        user='default',
        password='<password>',
        database='mysql_interface'
    )
    
    print("\n" + "=" * 60)
    print("TPC-DS Query Performance Benchmark")
    print("=" * 60)
    
    results = []
    for query_name, query in tpcds_benchmark_queries.items():
        result = benchmark_query(conn, query_name, query, iterations=3)
        results.append(result)
    
    # 결과 요약
    print("\n" + "=" * 60)
    print("BENCHMARK SUMMARY")
    print("=" * 60)
    print(f"{'Query':<30} {'Avg Time':<12} {'Rows':<10}")
    print("-" * 60)
    for r in results:
        print(f"{r['query_name']:<30} {r['avg_time']:.3f}s{'':<6} {r['row_count']:<10}")
    
    conn.close()
```

---

## 7. 호환성 이슈 검증

### 7.1 알려진 제한사항 테스트

#### AUTO_INCREMENT 지원 여부

```sql
-- AUTO_INCREMENT 테스트
CREATE TABLE mysql_interface.auto_inc_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50)
) ENGINE = MergeTree() ORDER BY id;

-- 데이터 삽입 테스트
INSERT INTO mysql_interface.auto_inc_test (name) VALUES ('test1');
INSERT INTO mysql_interface.auto_inc_test (name) VALUES ('test2');

-- 결과 확인
SELECT * FROM mysql_interface.auto_inc_test;

-- 예상: AUTO_INCREMENT는 제한적 지원
-- 대안: generateUUIDv4(), now64() 등 사용
```

#### FOREIGN KEY 제약조건

```sql
-- FOREIGN KEY 테스트
CREATE TABLE mysql_interface.fk_parent (
    id INT PRIMARY KEY,
    name VARCHAR(50)
) ENGINE = MergeTree() ORDER BY id;

CREATE TABLE mysql_interface.fk_child (
    id INT PRIMARY KEY,
    parent_id INT,
    value VARCHAR(50),
    FOREIGN KEY (parent_id) REFERENCES fk_parent(id)
) ENGINE = MergeTree() ORDER BY id;

-- 데이터 삽입으로 제약조건 검증
INSERT INTO mysql_interface.fk_parent VALUES (1, 'parent1');
INSERT INTO mysql_interface.fk_child VALUES (1, 1, 'valid');
INSERT INTO mysql_interface.fk_child VALUES (2, 999, 'invalid');  -- 제약조건 위반?

-- 예상: 구문은 허용되나 실제 제약조건 미적용
```

#### TRIGGER 지원

```sql
-- TRIGGER 테스트 (예상: 미지원)
CREATE TRIGGER before_insert_users
BEFORE INSERT ON mysql_interface.customer
FOR EACH ROW
SET NEW.c_customer_id = CONCAT('CUST_', NEW.c_customer_sk);

-- 예상 결과: 에러 또는 무시
```

#### VIEW 호환성

```sql
-- VIEW 생성 테스트
CREATE VIEW mysql_interface.active_customers AS
SELECT c.*
FROM mysql_interface.customer c
JOIN mysql_interface.store_sales ss ON c.c_customer_sk = ss.ss_customer_sk
WHERE ss.ss_sold_date_sk > (SELECT MAX(d_date_sk) - 90 FROM mysql_interface.date_dim);

-- VIEW 조회
SELECT * FROM mysql_interface.active_customers LIMIT 10;

-- VIEW 삭제
DROP VIEW IF EXISTS mysql_interface.active_customers;
```

### 7.2 트랜잭션 지원 검증

```sql
-- Transaction 테스트
START TRANSACTION;

INSERT INTO mysql_interface.customer VALUES 
    (99999, 'TEST99999', 1, 1, 1, 1, 1, 'Mr.', 'Test', 'User', 'N', 1, 1, 2000, 'Test Country', NULL, 'test@test.com', NULL);

-- 중간 상태 확인
SELECT * FROM mysql_interface.customer WHERE c_customer_sk = 99999;

ROLLBACK;
-- 또는 COMMIT;

-- 롤백 후 확인
SELECT * FROM mysql_interface.customer WHERE c_customer_sk = 99999;

-- 예상: ClickHouse는 제한적 트랜잭션 지원
```

### 7.3 제한사항 체크리스트

| 기능 | MySQL | ClickHouse | 호환성 | 비고 |
|------|-------|-----------|--------|------|
| AUTO_INCREMENT | ✓ | 제한적 | ⚠️ | 대안 필요 |
| FOREIGN KEY | ✓ | 문법만 | ⚠️ | 제약조건 미적용 |
| TRIGGER | ✓ | ✗ | ✗ | 미지원 |
| STORED PROCEDURE | ✓ | ✗ | ✗ | 미지원 |
| VIEW | ✓ | ✓ | ✓ | 지원 |
| TRANSACTION | ✓ | 제한적 | ⚠️ | INSERT만 부분 지원 |
| UNION | ✓ | ✓ | ✓ | 지원 |
| CTE (WITH) | ✓ | ✓ | ✓ | 지원 |
| Window Functions | ✓ | ✓ | ✓ | 지원 |

---

## 8. 통합 테스트 스위트

### 8.1 자동화된 테스트 프레임워크

```python
import unittest
import mysql.connector
from decimal import Decimal

class ClickHouseMySQLCompatibilityTest(unittest.TestCase):
    """ClickHouse MySQL Interface 호환성 통합 테스트"""
    
    @classmethod
    def setUpClass(cls):
        """테스트 환경 설정"""
        cls.connection = mysql.connector.connect(
            host='<chc-hostname>',
            port=9004,
            user='default',
            password='<password>',
            database='mysql_interface'
        )
        cls.cursor = cls.connection.cursor()
    
    @classmethod
    def tearDownClass(cls):
        """테스트 환경 정리"""
        cls.cursor.close()
        cls.connection.close()
    
    def test_01_connection(self):
        """기본 연결 테스트"""
        self.cursor.execute("SELECT 1")
        result = self.cursor.fetchone()
        self.assertEqual(result[0], 1, "Basic connection test failed")
    
    def test_02_database_operations(self):
        """데이터베이스 기본 작업 테스트"""
        # Database 생성
        self.cursor.execute("CREATE DATABASE IF NOT EXISTS test_db")
        
        # Database 조회
        self.cursor.execute("SHOW DATABASES LIKE 'test_db'")
        result = self.cursor.fetchone()
        self.assertIsNotNone(result, "Database creation failed")
        
        # Database 삭제
        self.cursor.execute("DROP DATABASE IF EXISTS test_db")
    
    def test_03_table_operations(self):
        """테이블 작업 테스트"""
        # 테이블 생성
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS mysql_interface.test_table (
                id INT,
                name VARCHAR(50),
                value DECIMAL(10,2)
            ) ENGINE = MergeTree() ORDER BY id
        """)
        
        # 테이블 존재 확인
        self.cursor.execute("SHOW TABLES FROM mysql_interface LIKE 'test_table'")
        result = self.cursor.fetchone()
        self.assertIsNotNone(result, "Table creation failed")
        
        # 정리
        self.cursor.execute("DROP TABLE IF EXISTS mysql_interface.test_table")
    
    def test_04_insert_select(self):
        """INSERT/SELECT 테스트"""
        # 테이블 생성
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS mysql_interface.crud_test (
                id INT,
                name VARCHAR(50)
            ) ENGINE = MergeTree() ORDER BY id
        """)
        
        # INSERT
        self.cursor.execute("INSERT INTO mysql_interface.crud_test VALUES (1, 'test')")
        
        # SELECT
        self.cursor.execute("SELECT * FROM mysql_interface.crud_test WHERE id = 1")
        result = self.cursor.fetchone()
        self.assertEqual(result[0], 1, "INSERT/SELECT failed")
        self.assertEqual(result[1], 'test', "INSERT/SELECT failed")
        
        # 정리
        self.cursor.execute("DROP TABLE IF EXISTS mysql_interface.crud_test")
    
    def test_05_data_types(self):
        """데이터 타입 테스트"""
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS mysql_interface.type_test (
                int_col INT,
                varchar_col VARCHAR(100),
                decimal_col DECIMAL(10,2),
                date_col DATE,
                datetime_col DATETIME
            ) ENGINE = MergeTree() ORDER BY int_col
        """)
        
        # 데이터 삽입
        self.cursor.execute("""
            INSERT INTO mysql_interface.type_test VALUES 
            (1, 'test', 123.45, '2025-01-01', '2025-01-01 12:00:00')
        """)
        
        # 조회 및 검증
        self.cursor.execute("SELECT * FROM mysql_interface.type_test WHERE int_col = 1")
        result = self.cursor.fetchone()
        
        self.assertEqual(result[0], 1)
        self.assertEqual(result[1], 'test')
        self.assertAlmostEqual(float(result[2]), 123.45, places=2)
        
        # 정리
        self.cursor.execute("DROP TABLE IF EXISTS mysql_interface.type_test")
    
    def test_06_aggregate_functions(self):
        """집계 함수 테스트"""
        # 기존 테이블 사용
        self.cursor.execute("""
            SELECT 
                COUNT(*) as cnt,
                SUM(ss_quantity) as total_qty,
                AVG(ss_sales_price) as avg_price,
                MIN(ss_sold_date_sk) as min_date,
                MAX(ss_sold_date_sk) as max_date
            FROM mysql_interface.store_sales
            LIMIT 1
        """)
        result = self.cursor.fetchone()
        
        self.assertIsNotNone(result[0], "COUNT failed")
        self.assertIsNotNone(result[1], "SUM failed")
        self.assertIsNotNone(result[2], "AVG failed")
    
    def test_07_join_operations(self):
        """JOIN 작업 테스트"""
        self.cursor.execute("""
            SELECT 
                ss.ss_item_sk,
                i.i_product_name,
                SUM(ss.ss_quantity) as total_qty
            FROM mysql_interface.store_sales ss
            JOIN mysql_interface.item i ON ss.ss_item_sk = i.i_item_sk
            GROUP BY ss.ss_item_sk, i.i_product_name
            LIMIT 10
        """)
        results = self.cursor.fetchall()
        self.assertGreater(len(results), 0, "JOIN operation failed")
    
    def test_08_string_functions(self):
        """문자열 함수 테스트"""
        self.cursor.execute("""
            SELECT 
                CONCAT('Hello', ' ', 'World') as concat_result,
                UPPER('test') as upper_result,
                LOWER('TEST') as lower_result,
                LENGTH('test') as length_result,
                SUBSTRING('Hello World', 1, 5) as substring_result
        """)
        result = self.cursor.fetchone()
        
        self.assertEqual(result[0], 'Hello World')
        self.assertEqual(result[1], 'TEST')
        self.assertEqual(result[2], 'test')
        self.assertEqual(result[3], 4)
        self.assertEqual(result[4], 'Hello')
    
    def test_09_date_functions(self):
        """날짜 함수 테스트"""
        self.cursor.execute("""
            SELECT 
                NOW() as now_result,
                CURDATE() as curdate_result,
                YEAR(NOW()) as year_result,
                MONTH(NOW()) as month_result,
                DAY(NOW()) as day_result
        """)
        result = self.cursor.fetchone()
        
        self.assertIsNotNone(result[0], "NOW() failed")
        self.assertIsNotNone(result[1], "CURDATE() failed")
        self.assertIsInstance(result[2], int, "YEAR() failed")
    
    def test_10_prepared_statements(self):
        """Prepared Statement 테스트"""
        query = "SELECT * FROM mysql_interface.customer WHERE c_customer_sk = %s"
        self.cursor.execute(query, (1,))
        result = self.cursor.fetchone()
        
        if result:
            self.assertEqual(result[0], 1, "Prepared statement failed")

if __name__ == '__main__':
    # 테스트 실행
    unittest.main(verbosity=2)
```

### 8.2 테스트 실행 스크립트

```bash
#!/bin/bash
# run_tests.sh - MySQL Interface 호환성 테스트 실행

echo "=========================================="
echo "ClickHouse MySQL Interface Test Suite"
echo "=========================================="
echo ""

# Python 환경 확인
python3 --version
echo ""

# 필요한 패키지 설치
echo "Installing required packages..."
pip3 install mysql-connector-python > /dev/null 2>&1
echo "✓ Packages installed"
echo ""

# 테스트 실행
echo "Running compatibility tests..."
python3 test_mysql_compatibility.py

# 결과 확인
if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✓ All tests passed successfully!"
    echo "=========================================="
    exit 0
else
    echo ""
    echo "=========================================="
    echo "✗ Some tests failed"
    echo "=========================================="
    exit 1
fi
```

---

## 9. 결과 분석 및 보고

### 9.1 테스트 결과 수집

```sql
-- MySQL Interface를 통한 종합 검증
USE mysql_interface;

-- 1. 테이블 생성 확인
SELECT COUNT(*) as table_count 
FROM system.tables 
WHERE database = 'mysql_interface';

-- 2. 데이터 적재 확인
SELECT 
    name as table_name,
    total_rows,
    formatReadableSize(total_bytes) as size
FROM system.tables
WHERE database = 'mysql_interface' AND total_rows > 0
ORDER BY total_rows DESC;

-- 3. 파티션 확인 (store_sales)
SELECT 
    partition,
    rows,
    formatReadableSize(bytes_on_disk) as size
FROM system.parts
WHERE database = 'mysql_interface' AND table = 'store_sales'
ORDER BY partition;

-- 4. 쿼리 실행 통계
SELECT 
    query_kind,
    COUNT(*) as count,
    AVG(query_duration_ms) as avg_duration_ms,
    MAX(query_duration_ms) as max_duration_ms
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE '%mysql_interface%'
  AND event_date >= today() - 1
GROUP BY query_kind
ORDER BY count DESC;
```

### 9.2 호환성 점수 계산

```python
def calculate_compatibility_score(test_results):
    """호환성 점수 계산"""
    
    categories = {
        'connection': {'weight': 0.15, 'tests': []},
        'ddl': {'weight': 0.15, 'tests': []},
        'dml': {'weight': 0.20, 'tests': []},
        'functions': {'weight': 0.20, 'tests': []},
        'datatypes': {'weight': 0.15, 'tests': []},
        'performance': {'weight': 0.15, 'tests': []}
    }
    
    # 카테고리별 점수 계산
    total_score = 0.0
    
    for category, data in categories.items():
        if len(data['tests']) > 0:
            passed = sum(1 for t in data['tests'] if t['passed'])
            category_score = (passed / len(data['tests'])) * data['weight']
            total_score += category_score
            
            print(f"{category.upper()}: {passed}/{len(data['tests'])} passed "
                  f"({category_score/data['weight']*100:.1f}%)")
    
    print(f"\nTotal Compatibility Score: {total_score*100:.1f}%")
    
    # 등급 판정
    if total_score >= 0.9:
        grade = "A (Excellent)"
    elif total_score >= 0.8:
        grade = "B (Good)"
    elif total_score >= 0.7:
        grade = "C (Acceptable)"
    elif total_score >= 0.6:
        grade = "D (Limited)"
    else:
        grade = "F (Poor)"
    
    print(f"Compatibility Grade: {grade}")
    
    return total_score, grade
```

### 9.3 보고서 템플릿

```markdown
# ClickHouse Cloud MySQL Interface 호환성 평가 보고서

## 요약

- **테스트 일자**: 2025-01-XX
- **ClickHouse 버전**: 24.X.X
- **테스트 환경**: ClickHouse Cloud
- **전체 호환성 점수**: XX.X%

## 테스트 결과

### 1. 연결 테스트
- MySQL CLI: ✓ 성공
- MySQL Workbench: ✓ 성공
- Python mysql-connector: ✓ 성공
- Java JDBC: ✓ 성공
- Node.js mysql2: ✓ 성공

### 2. SQL 구문 호환성
- DDL 명령: 90% (18/20 passed)
- DML 명령: 95% (19/20 passed)
- 집계 함수: 100% (15/15 passed)
- 문자열 함수: 90% (18/20 passed)
- 날짜 함수: 85% (17/20 passed)

### 3. TPC-DS 쿼리
- 실행 성공률: 80% (8/10 queries)
- 평균 실행 시간: X.XX초
- 성능 비교: MySQL 대비 3.5배 향상

### 4. 알려진 제한사항
- AUTO_INCREMENT: 제한적 지원
- FOREIGN KEY: 구문만 허용, 제약조건 미적용
- TRIGGER: 미지원
- STORED PROCEDURE: 미지원
- TRANSACTION: INSERT만 부분 지원

## 권장사항

1. **프로덕션 사용 가능**: 분석 워크로드에 적합
2. **주의 필요 영역**: 
   - 트랜잭션 의존 애플리케이션
   - AUTO_INCREMENT 필수 스키마
3. **마이그레이션 전략**:
   - 스키마 변환 필요
   - 애플리케이션 로직 조정 권장

## 결론

ClickHouse Cloud의 MySQL interface는 대부분의 분석 쿼리에서 높은 호환성을 보이며, 
특히 대용량 데이터 처리 성능이 우수합니다. OLTP 기능의 일부 제한이 있으나, 
OLAP 워크로드에는 충분히 프로덕션 수준의 호환성을 제공합니다.
```

---

## 10. 부록

### 10.1 참고 자료

- ClickHouse MySQL Interface 공식 문서
- TPC-DS 벤치마크 스펙
- MySQL 8.0 호환성 가이드

### 10.2 트러블슈팅 가이드

#### 연결 문제

```bash
# SSL 인증서 오류
mysql --ssl-mode=REQUIRED --ssl-ca=/path/to/ca-cert.pem ...

# 연결 타임아웃
mysql --connect-timeout=60 ...

# 포트 확인
telnet <chc-hostname> 9004
```

#### 쿼리 오류

```sql
-- 쿼리 로그 확인
SELECT 
    query,
    exception,
    stack_trace
FROM system.query_log
WHERE type = 'ExceptionWhileProcessing'
  AND event_time > now() - INTERVAL 1 HOUR
ORDER BY event_time DESC
LIMIT 10;
```

### 10.3 연락처

- **Technical Support**: support@clickhouse.com
- **Documentation**: https://clickhouse.com/docs
- **Community**: https://clickhouse.com/slack

---

**문서 버전**: 1.0  
**마지막 업데이트**: 2025-12-13