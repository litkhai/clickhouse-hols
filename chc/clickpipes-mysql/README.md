# ClickPipes CDC Demo - MySQL Source

MySQL → ClickPipes CDC 파이프라인 데모용 Docker 환경입니다.

---

## 빠른 시작

### 1. MySQL 컨테이너 실행

```bash
cd clickpipes-mysql
docker compose up -d
```

컨테이너가 완전히 뜰 때까지 헬스체크 확인:

```bash
docker compose ps
# STATUS: healthy 확인
```

### 2. 연결 확인

```bash
mysql -h 127.0.0.1 -P 3306 -u cdc_user -pClickPipes2024! cdc_demo
```

### 3. DML 데모 스크립트 실행

```bash
# 기본 (3초 간격)
./scripts/dml-demo.sh

# 간격 조정 (1초)
INTERVAL=1 ./scripts/dml-demo.sh
```

---

## MySQL 접속 정보

| 항목 | 값 |
|------|----|
| Host | `localhost` (또는 머신 IP) |
| Port | `3306` |
| Database | `cdc_demo` |
| Root Password | `ClickPipes2024!` |
| App User | `cdc_user` / `ClickPipes2024!` |

---

## ClickPipes CDC 전용 계정

ClickPipes에 입력할 **복제 전용** 계정:

| 항목 | 값 |
|------|----|
| Username | `clickpipes_repl` |
| Password | `ClickPipes2024!` |
| 권한 | `REPLICATION SLAVE`, `REPLICATION CLIENT`, `SELECT` |

---

## CDC 활성화 설정 확인

```sql
-- binlog 설정 확인
SHOW VARIABLES LIKE 'log_bin';
SHOW VARIABLES LIKE 'binlog_format';
SHOW VARIABLES LIKE 'binlog_row_image';
SHOW VARIABLES LIKE 'gtid_mode';

-- 현재 binlog 위치 확인
SHOW MASTER STATUS;
```

기대값:
- `log_bin` = `ON`
- `binlog_format` = `ROW`
- `binlog_row_image` = `FULL`
- `gtid_mode` = `ON`

---

## 데모 테이블 구조

| 테이블 | 설명 |
|--------|------|
| `customers` | 고객 정보 (tier 업그레이드로 UPDATE 시연) |
| `products` | 상품 및 재고 (stock 차감으로 UPDATE 시연) |
| `orders` | 주문 (status 변경으로 UPDATE, 오래된 주문 DELETE 시연) |
| `order_items` | 주문 항목 (주문 삭제 시 CASCADE DELETE 시연) |

---

## ClickPipes 설정 가이드

### Step 1: ClickPipes 소스 설정

ClickHouse Cloud 콘솔 → **Data Sources** → **ClickPipes** → **MySQL CDC**

| 필드 | 값 |
|------|----|
| Host | 머신의 외부 IP (Docker 내부 127.0.0.1 불가) |
| Port | `3306` |
| Database | `cdc_demo` |
| Username | `clickpipes_repl` |
| Password | `ClickPipes2024!` |

> **로컬 환경에서 ClickHouse Cloud 연결 시:**  
> ngrok 또는 SSH 터널을 사용하여 MySQL 포트를 외부에 노출해야 합니다.  
> ```bash
> # ngrok 사용 예시
> ngrok tcp 3306
> # → Forwarding: tcp://0.tcp.ngrok.io:XXXXX → localhost:3306
> ```

### Step 2: 복제할 테이블 선택

```
cdc_demo.customers
cdc_demo.products
cdc_demo.orders
cdc_demo.order_items
```

### Step 3: ClickHouse 대상 테이블 설정

ClickPipes가 자동으로 스키마를 감지하여 ReplacingMergeTree 테이블을 생성합니다.

### Step 4: 파이프라인 시작 후 DML 스크립트 실행

```bash
./scripts/dml-demo.sh
```

ClickHouse Cloud에서 실시간 데이터 수신 확인:

```sql
-- ClickHouse에서 실행
SELECT count(), max(_peerdb_synced_at)
FROM cdc_demo.orders
GROUP BY ()
```

---

## 컨테이너 정리

```bash
docker compose down -v  # 볼륨까지 삭제
```
