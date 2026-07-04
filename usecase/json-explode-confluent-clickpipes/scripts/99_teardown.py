"""⑨ 정리: ClickPipe 삭제 + (선택) 테이블/DB 삭제.

  python scripts/99_teardown.py             # ClickPipe 삭제 + 테이블 TRUNCATE (기본, 안전)
  python scripts/99_teardown.py --drop      # ClickPipe 삭제 + 테이블/MV DROP
  python scripts/99_teardown.py --drop-db   # 위 + 데이터베이스까지 DROP
  python scripts/99_teardown.py --keep-pipe # ClickPipe 는 남기고 테이블만 처리

데모 재시작 시엔 인자 없이 실행하면 TRUNCATE 만 해서 다시 producer 만 돌리면 됩니다.
"""
import json
import sys

import clickpipe_api as api
from config import CFG


def teardown_pipe():
    pipe_id = None
    if CFG.state_file.exists():
        pipe_id = json.loads(CFG.state_file.read_text()).get("id")
    if not pipe_id:
        found = api.find_by_name(CFG.clickpipe_name)
        pipe_id = found.get("id") if found else None
    if not pipe_id:
        print("[teardown] 삭제할 ClickPipe 를 찾지 못함 (이미 없음)")
        return
    print(f"[teardown] ClickPipe 삭제: id={pipe_id}")
    code = api.delete_clickpipe(pipe_id)
    print(f"[teardown] 삭제 응답 {code}")
    CFG.state_file.unlink(missing_ok=True)


def main():
    args = set(sys.argv[1:])
    client = CFG.ch_client()

    if "--keep-pipe" not in args:
        teardown_pipe()

    db = CFG.database
    objs_drop_order = [  # MV 먼저, 그다음 테이블
        ("MATERIALIZED VIEW", CFG.mv_explode),
        ("MATERIALIZED VIEW", CFG.mv_transform),
        ("TABLE", CFG.tbl_fact),
        ("TABLE", CFG.tbl_staging),
        ("TABLE", CFG.tbl_raw),
    ]

    if "--drop" in args or "--drop-db" in args:
        for kind, name in objs_drop_order:
            print(f"[teardown] DROP {kind} {db}.{name}")
            client.command(f"DROP {kind} IF EXISTS {db}.{name}")
        if "--drop-db" in args:
            print(f"[teardown] DROP DATABASE {db}")
            client.command(f"DROP DATABASE IF EXISTS {db}")
    else:
        for name in (CFG.tbl_raw, CFG.tbl_staging, CFG.tbl_fact):
            print(f"[teardown] TRUNCATE {db}.{name}")
            client.command(f"TRUNCATE TABLE IF EXISTS {db}.{name}")

    print("[teardown] 완료")


if __name__ == "__main__":
    main()
