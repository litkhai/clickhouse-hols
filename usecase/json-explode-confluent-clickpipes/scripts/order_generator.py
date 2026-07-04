"""주문 이벤트 생성 로직 (Path A/B 공용).

instruction 3.1 의 스키마를 그대로 따릅니다. 의도적으로 섞는 것:
  - customer_id placeholder ((not set)/undefined/""/null) → NULL 치환 시연
  - 가격 콤마 포함 ("129,000")                            → replaceAll 시연
  - cancelled/returned 상태                              → 상태 필터 + 빈 배열 처리
  - 빈 order_lines 배열                                  → explode_outer 시연
"""
import random
import uuid
from datetime import datetime, timezone

from config import CFG

CATALOG = [
    ("SKU-1001", "Wireless Earbuds Pro", "electronics", "129,000"),
    ("SKU-1002", "Mechanical Keyboard",  "electronics", "89,000"),
    ("SKU-2001", "Running Shoes X",      "sports",      "119,000"),
    ("SKU-2002", "Yoga Mat Premium",     "sports",      "35,000"),
    ("SKU-3001", "Cold Brew Set",        "grocery",     "24,500"),
    ("SKU-3002", "Protein Bar 12-pack",  "grocery",     "18,900"),
    ("SKU-4001", "Desk Lamp Minimal",    "home",        "45,000"),
    ("SKU-4002", "Aroma Diffuser",       "home",        "52,000"),
]
STATUSES = ["completed"] * 5 + ["processing"] * 2 + ["shipped", "delivered"] + ["cancelled"]
PLACEHOLDERS = ["(not set)", "undefined", "", "null"]
TIERS = ["bronze", "silver", "gold", "vip"]


def make_order() -> dict:
    status = random.choice(STATUSES)
    n_lines = 0 if random.random() < CFG.empty_lines_rate else random.randint(1, 4)
    lines = []
    for _ in range(n_lines):
        sku, name, cat, price = random.choice(CATALOG)
        lines.append({"sku": sku, "name": name, "category": cat,
                      "unit_price": price, "qty": str(random.randint(1, 3))})
    cust = (random.choice(PLACEHOLDERS)
            if random.random() < CFG.placeholder_rate
            else f"CUST-{random.randint(1000, 9999)}")
    return {
        "order_id": str(uuid.uuid4()),
        "order_status": status,
        "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3],
        "customer_id": cust,
        "customer_tier": random.choice(TIERS),
        "session_id": f"sess-{uuid.uuid4().hex[:12]}",
        "order_lines": lines,
    }
