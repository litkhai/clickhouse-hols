"""데모 데이터 초기화 — raw/staging/fact 를 TRUNCATE (스키마·ClickPipe 는 유지).

데모를 여러 번 반복할 때, 이 스크립트로 테이블만 비우고 다시 producer 를 돌리면
숫자가 0 부터 다시 올라가는 깔끔한 시연이 됩니다.

  python scripts/clean.py

옵션:
  --error   ClickPipes 가 만든 *_clickpipes_error 테이블도 함께 비움
"""
import sys

from config import CFG


def main():
    also_error = "--error" in sys.argv
    client = CFG.ch_client()

    targets = [CFG.tbl_raw, CFG.tbl_staging, CFG.tbl_fact]
    if also_error:
        targets.append(f"{CFG.tbl_raw}_clickpipes_error")

    print(f"[clean] DB '{CFG.database}' 데이터 초기화")
    for name in targets:
        # 존재 확인 후 before-count → truncate
        exists = client.query(
            "SELECT count() FROM system.tables "
            f"WHERE database='{CFG.database}' AND name='{name}'"
        ).result_rows[0][0]
        if not exists:
            print(f"    - {name:<32} (없음, 건너뜀)")
            continue
        before = client.query(f"SELECT count() FROM {CFG.database}.{name}").result_rows[0][0]
        client.command(f"TRUNCATE TABLE {CFG.database}.{name}")
        print(f"    - {name:<32} {before:>8,} → 0")

    print("[clean] 완료. producer 를 다시 실행하면 0 부터 시작합니다.")


if __name__ == "__main__":
    main()
