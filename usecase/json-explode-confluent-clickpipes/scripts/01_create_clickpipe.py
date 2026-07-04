"""② ClickPipes 생성 (Confluent Kafka → analytics.orders_raw).

ClickHouse Cloud OpenAPI 로 파이프를 자동 생성하고, 파이프 id 를
.clickpipe_state.json 에 저장합니다(teardown 용).

  python scripts/01_create_clickpipe.py

같은 이름의 파이프가 이미 있으면 재사용합니다(중복 생성 방지).
"""
import json

import clickpipe_api as api
from config import CFG


def save_state(pipe: dict):
    CFG.state_file.write_text(json.dumps({
        "id": pipe.get("id"),
        "name": pipe.get("name"),
        "state": pipe.get("state"),
    }, indent=2), encoding="utf-8")
    print(f"[clickpipe] 상태 저장 → {CFG.state_file.name}")


def main():
    existing = api.find_by_name(CFG.clickpipe_name)
    if existing:
        print(f"[clickpipe] 이미 존재: '{CFG.clickpipe_name}' "
              f"(id={existing.get('id')}, state={existing.get('state')}) — 재사용")
        save_state(existing)
        return

    payload = api.build_create_payload()
    print(f"[clickpipe] 생성 요청: '{CFG.clickpipe_name}'")
    print(f"    source : Confluent {CFG.kafka_bootstrap} topic={CFG.kafka_topic} "
          f"auth={CFG.kafka_sasl_mechanism} offset={CFG.clickpipe_offset}")
    print(f"    dest   : {CFG.database}.{CFG.tbl_raw} (managedTable=false)")
    pipe = api.create_clickpipe(payload)
    print(f"[clickpipe] 생성됨: id={pipe.get('id')} state={pipe.get('state')}")
    save_state(pipe)
    print("[clickpipe] Cloud 콘솔 → Data sources → ClickPipes 에서 상태 확인 가능")


if __name__ == "__main__":
    main()
