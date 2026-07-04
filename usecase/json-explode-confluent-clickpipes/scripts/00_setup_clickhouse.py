"""① ClickHouse Cloud 스키마 생성: DB + raw/staging/fact 테이블 + 2개 MV.

  python scripts/00_setup_clickhouse.py
"""
from config import CFG


def main():
    client = CFG.ch_client()
    print(f"[setup] {CFG.ch_host} 접속 — DB '{CFG.database}' 준비")
    client.command(f"CREATE DATABASE IF NOT EXISTS {CFG.database}")

    sql = CFG.render_sql(CFG.sql_dir / "schema.sql")
    stmts = CFG.split_statements(sql)
    print(f"[setup] {len(stmts)}개 DDL 실행")
    for i, stmt in enumerate(stmts, 1):
        head = stmt.splitlines()[0][:70]
        print(f"  [{i}/{len(stmts)}] {head} ...")
        client.command(stmt)

    print("[setup] 완료. 생성된 오브젝트:")
    rows = client.query(
        "SELECT name, engine FROM system.tables "
        f"WHERE database = '{CFG.database}' ORDER BY name"
    ).result_rows
    for name, engine in rows:
        print(f"    - {name}  ({engine})")


if __name__ == "__main__":
    main()
