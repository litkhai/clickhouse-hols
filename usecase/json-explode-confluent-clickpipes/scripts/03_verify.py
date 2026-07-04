"""④ 데모 쿼리 실행/검증 — sql/demo_queries.sql 의 6개 쿼리를 순서대로 출력.

  python scripts/03_verify.py           # 1회 실행
  python scripts/03_verify.py --watch   # ③ 실시간 집계를 3초 간격으로 반복
"""
import sys
import time

from config import CFG


def load_queries():
    """`-- @@ 제목` 마커로 쿼리 블록 분해."""
    sql = CFG.render_sql(CFG.sql_dir / "demo_queries.sql")
    blocks, title, buf = [], None, []
    for line in sql.splitlines():
        if line.strip().startswith("-- @@"):
            if title:
                blocks.append((title, "\n".join(buf).strip()))
            title = line.split("-- @@", 1)[1].strip()
            buf = []
        elif title:
            buf.append(line)
    if title:
        blocks.append((title, "\n".join(buf).strip()))
    return [(t, q) for t, q in blocks if q]


def run_one(client, title, query):
    print(f"\n\033[1m─── {title}\033[0m")
    res = client.query(query)
    cols = res.column_names
    print("  " + " | ".join(cols))
    for row in res.result_rows:
        print("  " + " | ".join(str(c) for c in row))


def main():
    client = CFG.ch_client()
    queries = load_queries()

    if "--watch" in sys.argv:
        agg = next((q for t, q in queries if t.startswith("③")), None)
        if not agg:
            sys.exit("③ 집계 쿼리를 찾지 못했습니다.")
        print("[verify] ③ 실시간 집계 3초 간격 반복 — Ctrl+C 로 중단")
        try:
            while True:
                run_one(client, "③ 실시간 집계", agg)
                time.sleep(3)
        except KeyboardInterrupt:
            print("\n[verify] 중단")
        return

    for title, query in queries:
        run_one(client, title, query)


if __name__ == "__main__":
    main()
