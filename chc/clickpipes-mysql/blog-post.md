# MySQL CDC → ClickHouse Cloud 실시간 파이프라인 구축하기 (ClickPipes 활용)

> Docker로 MySQL을 띄우고, ClickPipes CDC를 통해 변경 데이터를 ClickHouse Cloud로 실시간 스트리밍하는 전체 과정을 다룹니다.

---

## 목차

1. [CDC란 무엇인가](#1-cdc란-무엇인가)
2. [아키텍처 개요](#2-아키텍처-개요)
3. [MySQL Docker 환경 구성](#3-mysql-docker-환경-구성)
4. [CDC 필수 설정](#4-cdc-필수-설정)
5. [초기 스키마 및 복제 유저 설정](#5-초기-스키마-및-복제-유저-설정)
6. [ngrok으로 로컬 MySQL 외부 노출](#6-ngrok으로-로컬-mysql-외부-노출)
7. [ClickPipes CDC 파이프라인 설정](#7-clickpipes-cdc-파이프라인-설정)
8. [DML 자동화 스크립트로 CDC 시연](#8-dml-자동화-스크립트로-cdc-시연)
9. [트러블슈팅](#9-트러블슈팅)
10. [마무리](#10-마무리)

---

## 1. CDC란 무엇인가

**CDC(Change Data Capture)** 는 데이터베이스에서 발생하는 INSERT / UPDATE / DELETE 이벤트를 실시간으로 감지하여 다른 시스템으로 전파하는 기술입니다.

MySQL의 경우 **Binary Log(binlog)** 를 통해 모든 변경 이벤트가 기록되며, CDC 도구는 이 binlog를 구독하는 방식으로 동작합니다. 즉, 애플리케이션 코드를 수정하지 않고도 모든 데이터 변경을 캡처할 수 있습니다.

### CDC가 필요한 상황

- OLTP 데이터베이스(MySQL)의 데이터를 분석용 데이터베이스(ClickHouse)로 실시간 동기화
- 마이크로서비스 간 이벤트 기반 데이터 전파
- 실시간 데이터 레이크 구축

---

## 2. 아키텍처 개요

```
┌─────────────────────────────────┐
│         로컬 머신                │
│                                 │
│  ┌─────────────────────────┐   │
│  │   MySQL 8.0 (Docker)    │   │
│  │   binlog: ROW format    │   │
│  │   port: 3306            │   │
│  └───────────┬─────────────┘   │
│              │                  │
│  ┌───────────▼─────────────┐   │
│  │   ngrok TCP Tunnel      │   │
│  │   0.tcp.jp.ngrok.io     │   │
│  └───────────┬─────────────┘   │
└──────────────┼──────────────────┘
               │ Internet
┌──────────────▼──────────────────┐
│      ClickHouse Cloud           │
│                                 │
│  ┌──────────────────────────┐  │
│  │  ClickPipes CDC          │  │
│  │  (MySQL Source)          │  │
│  └───────────┬──────────────┘  │
│              │                  │
│  ┌───────────▼──────────────┐  │
│  │  ClickHouse Tables       │  │
│  │  (ReplacingMergeTree)    │  │
│  └──────────────────────────┘  │
└─────────────────────────────────┘
```

ClickPipes는 ClickHouse Cloud의 완전 관리형 데이터 수집 서비스로, MySQL binlog를 직접 구독하여 ClickHouse 테이블로 변경 이벤트를 스트리밍합니다.

---

## 3. MySQL Docker 환경 구성

### 디렉토리 구조

```
clickpipes-mysql/
├── docker-compose.yml
├── .env
├── mysql/
│   ├── conf/my.cnf       # CDC 설정
│   └── init/01-init.sql  # 스키마 + 복제 유저
└── scripts/
    └── dml-demo.sh       # DML 자동 실행 스크립트
```

### docker-compose.yml

```yaml
version: "3.8"

services:
  mysql:
    image: mysql:8.0
    container_name: clickpipes-mysql-cdc
    restart: unless-stopped
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:-ClickPipes2024!}
      MYSQL_DATABASE: ${MYSQL_DATABASE:-cdc_demo}
      MYSQL_USER: ${MYSQL_USER:-cdc_user}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD:-ClickPipes2024!}
    volumes:
      - ./mysql/conf/my.cnf:/etc/mysql/conf.d/clickpipes.cnf:ro
      - ./mysql/init:/docker-entrypoint-initdb.d:ro
      - mysql_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  mysql_data:
```

컨테이너 실행:

```bash
docker compose up -d

# 헬스체크 확인
docker compose ps
# STATUS: healthy 가 될 때까지 대기
```

---

## 4. CDC 필수 설정

MySQL을 CDC 소스로 사용하려면 binlog 관련 설정이 반드시 필요합니다. `mysql/conf/my.cnf`:

```ini
[mysqld]
# 서버 고유 ID
server-id = 1

# Binary Log 활성화
log_bin = mysql-bin

# ROW 기반 바이너리 로깅 (CDC 필수)
binlog_format = ROW

# before/after 모든 컬럼 값 기록
binlog_row_image = FULL

# 컬럼명 등 메타정보 기록 (ClickPipes 요구사항)
binlog_row_metadata = FULL

# GTID 모드 활성화 (안정적인 CDC 지원)
gtid_mode = ON
enforce_gtid_consistency = ON

# 바이너리 로그 보존 기간 (7일)
binlog_expire_logs_seconds = 604800

# 타임존
default_time_zone = '+00:00'
```

### 설정값 의미

| 설정 | 값 | 이유 |
|------|-----|------|
| `binlog_format` | `ROW` | 실제 변경된 행 데이터를 기록. STATEMENT 방식은 함수 호출 등에서 비결정적일 수 있음 |
| `binlog_row_image` | `FULL` | UPDATE 시 변경 전/후 모든 컬럼 값을 기록. ClickHouse에서 정확한 상태 추적 가능 |
| `binlog_row_metadata` | `FULL` | 컬럼명, 타입 등 메타정보 포함. 스키마 없이도 컬럼 매핑 가능 |
| `gtid_mode` | `ON` | 글로벌 트랜잭션 ID로 복제 위치 추적. 재연결 시 정확한 지점부터 재개 |

### 설정 확인

```sql
SHOW VARIABLES LIKE 'log_bin';           -- ON
SHOW VARIABLES LIKE 'binlog_format';     -- ROW
SHOW VARIABLES LIKE 'binlog_row_image';  -- FULL
SHOW VARIABLES LIKE 'binlog_row_metadata'; -- FULL
SHOW VARIABLES LIKE 'gtid_mode';         -- ON

-- 현재 binlog 위치
SHOW MASTER STATUS;
```

---

## 5. 초기 스키마 및 복제 유저 설정

`mysql/init/01-init.sql`은 컨테이너 최초 실행 시 자동으로 적용됩니다.

### 복제 전용 유저 생성

```sql
CREATE USER 'clickpipes_repl'@'%'
  IDENTIFIED WITH mysql_native_password BY 'ClickPipes2024!';

GRANT REPLICATION SLAVE   ON *.*         TO 'clickpipes_repl'@'%';
GRANT REPLICATION CLIENT  ON *.*         TO 'clickpipes_repl'@'%';
GRANT SELECT              ON cdc_demo.*  TO 'clickpipes_repl'@'%';

FLUSH PRIVILEGES;
```

ClickPipes는 이 계정으로 binlog를 구독합니다. 최소 권한 원칙에 따라 `REPLICATION SLAVE`, `REPLICATION CLIENT`, `SELECT` 세 가지만 부여합니다.

### 데모 테이블 구조

```sql
-- 고객
CREATE TABLE customers (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    email      VARCHAR(150) NOT NULL UNIQUE,
    country    VARCHAR(50)  NOT NULL DEFAULT 'KR',
    tier       ENUM('bronze','silver','gold','platinum') DEFAULT 'bronze',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 상품
CREATE TABLE products (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    sku        VARCHAR(50) NOT NULL UNIQUE,
    name       VARCHAR(200) NOT NULL,
    category   VARCHAR(100) NOT NULL,
    price      DECIMAL(10,2) NOT NULL,
    stock      INT NOT NULL DEFAULT 0,
    is_active  TINYINT(1) DEFAULT 1,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 주문
CREATE TABLE orders (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    customer_id  INT NOT NULL,
    status       ENUM('pending','processing','shipped','delivered','cancelled') DEFAULT 'pending',
    total_amount DECIMAL(12,2) NOT NULL,
    items_count  INT DEFAULT 1,
    ordered_at   DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_status (status)
) ENGINE=InnoDB;

-- 주문 항목
CREATE TABLE order_items (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    order_id   INT NOT NULL,
    product_id INT NOT NULL,
    quantity   INT DEFAULT 1,
    unit_price DECIMAL(10,2) NOT NULL
) ENGINE=InnoDB;
```

---

## 6. ngrok으로 로컬 MySQL 외부 노출

ClickHouse Cloud는 인터넷을 통해 MySQL에 접근합니다. 로컬에서 테스트할 때는 **ngrok** TCP 터널을 사용합니다.

```bash
# 설치 (macOS)
brew install ngrok

# MySQL 포트 터널링
ngrok tcp 3306
```

실행 결과:

```
Session Status    online
Account           user@example.com (Plan: Free)
Region            Japan (jp)
Forwarding        tcp://0.tcp.jp.ngrok.io:14290 -> localhost:3306
```

`0.tcp.jp.ngrok.io:14290` 가 ClickPipes에서 사용할 외부 주소입니다.

> **주의**: ngrok 무료 플랜은 세션이 종료되면 포트가 바뀝니다. 데모 중에는 터널을 유지해야 합니다.

---

## 7. ClickPipes CDC 파이프라인 설정

ClickHouse Cloud 콘솔에서 다음 경로로 이동합니다:

**Integrations → ClickPipes → + New Pipe → MySQL CDC**

### 연결 정보 입력

| 항목 | 값 |
|------|----|
| Host | `0.tcp.jp.ngrok.io` |
| Port | `14290` (ngrok 할당 포트) |
| Username | `clickpipes_repl` |
| Password | `ClickPipes2024!` |
| Database | `cdc_demo` |

### 복제 테이블 선택

```
cdc_demo.customers
cdc_demo.products
cdc_demo.orders
cdc_demo.order_items
```

### ClickHouse 대상 테이블

ClickPipes가 MySQL 스키마를 자동 감지하여 ClickHouse에 **ReplacingMergeTree** 테이블을 생성합니다. Primary Key 기반으로 Upsert가 처리됩니다.

---

## 8. DML 자동화 스크립트로 CDC 시연

파이프라인이 설정되면 `scripts/dml-demo.sh`를 실행하여 실시간 데이터 변경을 발생시킵니다.

```bash
./scripts/dml-demo.sh
```

스크립트는 3초 간격으로 다음 DML을 반복 수행합니다:

```
────────────────── Cycle #5 [2026-04-05 16:13:25]
[INSERT] customers  → id=289, email=user17753732055530@demo.com, tier=platinum
[INSERT] orders     → id=286, customer_id=246, total=89900.00, qty=1
[UPDATE] orders     → id=273, status=pending → processing
[UPDATE] products   → id=7, stock -1 → 312
[INFO  ] Stats: customers=287, orders=286 (pending=2)
```

### DML 패턴

| 연산 | 대상 | 내용 |
|------|------|------|
| INSERT | customers | 매 사이클 신규 고객 생성 |
| INSERT | orders / order_items | 랜덤 고객의 신규 주문 생성 |
| UPDATE | orders | pending → processing/shipped/delivered 상태 전이 |
| UPDATE | products | 주문 수량만큼 재고(stock) 차감 |
| UPDATE | customers | 10% 확률로 tier 업그레이드 (bronze→silver→gold→platinum) |
| DELETE | orders | 5% 확률로 오래된 pending 주문 정리 |

약 10분 실행 후 데이터 규모:

| 테이블 | 행 수 |
|--------|------:|
| customers | ~765 |
| orders | ~764 |
| order_items | ~780 |
| products | 10 (고정) |

### ClickHouse에서 실시간 확인

```sql
-- 동기화된 행 수 및 최신 수신 시각 확인
SELECT
    count()                         AS total_rows,
    max(_peerdb_synced_at)          AS last_synced
FROM cdc_demo.orders;

-- 주문 상태 분포 실시간 모니터링
SELECT status, count() AS cnt
FROM cdc_demo.orders
GROUP BY status
ORDER BY cnt DESC;

-- 최근 변경된 고객 확인
SELECT id, name, tier, updated_at
FROM cdc_demo.customers
ORDER BY updated_at DESC
LIMIT 10;
```

---

## 9. 트러블슈팅

### `binlog_row_metadata must be set to 'FULL'`

ClickPipes 연결 테스트 시 아래 오류가 발생할 수 있습니다:

```
binlog_row_metadata must be set to 'FULL', currently MINIMAL
```

`my.cnf`에 설정을 추가하고 컨테이너를 재시작합니다:

```ini
binlog_row_metadata = FULL
```

```bash
docker compose restart
```

MySQL 8.0의 기본값은 `MINIMAL`이므로, ClickPipes처럼 컬럼명 기반 매핑이 필요한 도구는 반드시 `FULL`로 설정해야 합니다.

---

### `connection refused` (ClickPipes → MySQL)

로컬 IP(`192.168.x.x`) 또는 `localhost`를 직접 입력하면 연결이 거부됩니다. ClickHouse Cloud는 인터넷을 통해 접근하므로 **ngrok 도메인**을 사용해야 합니다.

```
# 잘못된 예
Host: 192.168.0.75   ← 로컬 네트워크, 외부 접근 불가
Host: localhost       ← ClickHouse Cloud 서버의 localhost를 의미함

# 올바른 예
Host: 0.tcp.jp.ngrok.io   ← ngrok 터널 도메인
Port: 14290               ← ngrok이 할당한 포트
```

---

### DML 스크립트 중단 (Duplicate entry)

이메일 컬럼에 UNIQUE 제약이 있어 랜덤 suffix 충돌 시 스크립트가 종료될 수 있습니다. epoch 타임스탬프 + cycle 카운터 + 난수 조합으로 고유성을 보장합니다:

```bash
RAND_SUFFIX="$(date +%s)${CYCLE}$((RANDOM % 999))"
```

---

## 10. 마무리

이번 실습에서 구성한 파이프라인 요약:

```
MySQL 8.0 (Docker)
  └─ binlog_format=ROW, binlog_row_image=FULL, binlog_row_metadata=FULL, gtid_mode=ON
  └─ 복제 유저: clickpipes_repl (REPLICATION SLAVE + CLIENT + SELECT)
     │
     │  ngrok TCP Tunnel
     ▼
ClickPipes (ClickHouse Cloud)
  └─ MySQL CDC 커넥터
  └─ 자동 스키마 감지 → ReplacingMergeTree 생성
     │
     ▼
ClickHouse Cloud 테이블
  └─ customers / products / orders / order_items
  └─ 실시간 INSERT / UPDATE / DELETE 반영
```

ClickPipes를 활용하면 Debezium, Kafka 등 별도 미들웨어 없이 MySQL binlog를 ClickHouse로 직접 스트리밍할 수 있습니다. 인프라 복잡도를 낮추면서도 실시간 분석 환경을 빠르게 구축할 수 있다는 점이 핵심 장점입니다.

---

## 참고

- [ClickPipes MySQL CDC 공식 문서](https://clickhouse.com/docs/integrations/clickpipes/mysql)
- [MySQL Binary Log 설정 가이드](https://dev.mysql.com/doc/refman/8.0/en/binary-log.html)
- [ngrok TCP 터널](https://ngrok.com/docs/tcp/)
