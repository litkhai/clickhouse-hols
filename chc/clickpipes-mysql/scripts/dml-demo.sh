#!/usr/bin/env bash
# ============================================================
# ClickPipes CDC Demo - DML 자동 실행 스크립트
# 지속적으로 INSERT / UPDATE / DELETE 를 수행하여
# ClickPipes CDC 파이프라인 동작을 시연합니다.
# ============================================================

set -euo pipefail

# -------------------------------------------------------
# 설정
# -------------------------------------------------------
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-cdc_user}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-ClickPipes2024!}"
MYSQL_DATABASE="${MYSQL_DATABASE:-cdc_demo}"

# 반복 간격 (초) - 기본 3초
INTERVAL="${INTERVAL:-3}"

# 색상 출력 헬퍼
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_insert() { echo -e "${GREEN}[INSERT]${NC} $*"; }
log_update() { echo -e "${YELLOW}[UPDATE]${NC} $*"; }
log_delete() { echo -e "${RED}[DELETE]${NC} $*"; }
log_info()   { echo -e "${BLUE}[INFO  ]${NC} $*"; }

# MySQL 실행 래퍼
mysql_exec() {
    mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
          --database="$MYSQL_DATABASE" --silent --skip-column-names -e "$1" 2>/dev/null
}

# -------------------------------------------------------
# 연결 확인
# -------------------------------------------------------
echo ""
echo "============================================================"
echo " ClickPipes CDC Demo - DML 스트림 시작"
echo "============================================================"
echo " Host     : $MYSQL_HOST:$MYSQL_PORT"
echo " Database : $MYSQL_DATABASE"
echo " User     : $MYSQL_USER"
echo " Interval : ${INTERVAL}s"
echo "============================================================"
echo ""

log_info "MySQL 연결 확인 중..."
until mysql_exec "SELECT 1" > /dev/null 2>&1; do
    echo "  대기 중... (MySQL이 아직 준비되지 않았습니다)"
    sleep 3
done
log_info "MySQL 연결 성공!"
echo ""

# -------------------------------------------------------
# DML 루프
# -------------------------------------------------------
CYCLE=0

while true; do
    CYCLE=$((CYCLE + 1))
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "────────────────────────────────── Cycle #${CYCLE} [${TIMESTAMP}]"

    # ── INSERT: 신규 고객 ──────────────────────────────────────
    RAND_SUFFIX="$(date +%s)${CYCLE}$((RANDOM % 999))"
    TIERS=("bronze" "silver" "gold" "platinum")
    TIER="${TIERS[$((RANDOM % 4))]}"
    NEW_CUSTOMER_ID=$(mysql_exec "
        INSERT INTO customers (name, email, country, tier)
        VALUES ('Demo User ${RAND_SUFFIX}', 'user${RAND_SUFFIX}@demo.com', 'KR', '${TIER}');
        SELECT LAST_INSERT_ID();
    ")
    log_insert "customers  → id=${NEW_CUSTOMER_ID}, email=user${RAND_SUFFIX}@demo.com, tier=${TIER}"

    # ── INSERT: 신규 주문 ──────────────────────────────────────
    # 기존 고객 중 랜덤 선택
    CUST_ID=$(mysql_exec "SELECT id FROM customers ORDER BY RAND() LIMIT 1;")
    PROD_ID=$(mysql_exec "SELECT id FROM products WHERE is_active=1 ORDER BY RAND() LIMIT 1;")
    UNIT_PRICE=$(mysql_exec "SELECT price FROM products WHERE id=${PROD_ID};")
    QTY=$((RANDOM % 3 + 1))
    TOTAL=$(echo "$UNIT_PRICE * $QTY" | bc)

    NEW_ORDER_ID=$(mysql_exec "
        INSERT INTO orders (customer_id, status, total_amount, items_count)
        VALUES (${CUST_ID}, 'pending', ${TOTAL}, ${QTY});
        SELECT LAST_INSERT_ID();
    ")
    mysql_exec "
        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        VALUES (${NEW_ORDER_ID}, ${PROD_ID}, ${QTY}, ${UNIT_PRICE});
    "
    log_insert "orders     → id=${NEW_ORDER_ID}, customer_id=${CUST_ID}, total=${TOTAL}, qty=${QTY}"

    # ── UPDATE: 주문 상태 진행 ─────────────────────────────────
    STATUSES=("processing" "shipped" "delivered")
    NEXT_STATUS="${STATUSES[$((RANDOM % 3))]}"
    PENDING_ORDER=$(mysql_exec "SELECT id FROM orders WHERE status='pending' ORDER BY RAND() LIMIT 1;" 2>/dev/null || echo "")
    if [[ -n "$PENDING_ORDER" ]]; then
        mysql_exec "UPDATE orders SET status='${NEXT_STATUS}' WHERE id=${PENDING_ORDER};"
        log_update "orders     → id=${PENDING_ORDER}, status=pending → ${NEXT_STATUS}"
    fi

    # ── UPDATE: 재고 차감 ──────────────────────────────────────
    PROD_UPDATE=$(mysql_exec "SELECT id FROM products WHERE stock > 10 ORDER BY RAND() LIMIT 1;")
    if [[ -n "$PROD_UPDATE" ]]; then
        DEC=$((RANDOM % 5 + 1))
        mysql_exec "UPDATE products SET stock = stock - ${DEC} WHERE id=${PROD_UPDATE};"
        NEW_STOCK=$(mysql_exec "SELECT stock FROM products WHERE id=${PROD_UPDATE};")
        log_update "products   → id=${PROD_UPDATE}, stock -${DEC} → ${NEW_STOCK}"
    fi

    # ── UPDATE: 고객 tier 업그레이드 (10% 확률) ───────────────
    if [[ $((RANDOM % 10)) -eq 0 ]]; then
        UPGRADABLE=$(mysql_exec "SELECT id FROM customers WHERE tier != 'platinum' ORDER BY RAND() LIMIT 1;")
        if [[ -n "$UPGRADABLE" ]]; then
            mysql_exec "
                UPDATE customers
                SET tier = CASE tier
                    WHEN 'bronze'  THEN 'silver'
                    WHEN 'silver'  THEN 'gold'
                    WHEN 'gold'    THEN 'platinum'
                    ELSE tier
                END
                WHERE id = ${UPGRADABLE};
            "
            NEW_TIER=$(mysql_exec "SELECT tier FROM customers WHERE id=${UPGRADABLE};")
            log_update "customers  → id=${UPGRADABLE}, tier upgraded to ${NEW_TIER}"
        fi
    fi

    # ── DELETE: cancelled 주문 정리 (5% 확률) ─────────────────
    if [[ $((RANDOM % 20)) -eq 0 ]]; then
        # 오래된 pending 주문 하나를 cancel 후 삭제
        OLD_ORDER=$(mysql_exec "
            SELECT id FROM orders
            WHERE status = 'pending'
              AND ordered_at < NOW() - INTERVAL 1 MINUTE
            ORDER BY RAND() LIMIT 1;
        " 2>/dev/null || echo "")
        if [[ -n "$OLD_ORDER" ]]; then
            mysql_exec "DELETE FROM order_items WHERE order_id = ${OLD_ORDER};"
            mysql_exec "DELETE FROM orders WHERE id = ${OLD_ORDER};"
            log_delete "orders     → id=${OLD_ORDER} (old pending order purged)"
        fi
    fi

    # ── 현재 통계 출력 ────────────────────────────────────────
    TOTAL_CUSTOMERS=$(mysql_exec "SELECT COUNT(*) FROM customers;")
    TOTAL_ORDERS=$(mysql_exec "SELECT COUNT(*) FROM orders;")
    PENDING_ORDERS=$(mysql_exec "SELECT COUNT(*) FROM orders WHERE status='pending';")
    log_info "Stats: customers=${TOTAL_CUSTOMERS}, orders=${TOTAL_ORDERS} (pending=${PENDING_ORDERS})"

    sleep "$INTERVAL"
done
