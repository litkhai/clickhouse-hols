"""ClickHouse Cloud OpenAPI — ClickPipes 헬퍼.

  엔드포인트:  {CH_API_URL}/organizations/{org}/services/{svc}/clickpipes
  인증:        HTTP Basic (username=Key ID, password=Key Secret)

필드명은 ClickHouse Cloud REST API (camelCase) 를 그대로 따릅니다.
Terraform provider(ClickHouse/terraform-provider-clickhouse) 의
pkg/internal/api/clickpipe_models.go 스키마 기준.
"""
import requests
from requests.auth import HTTPBasicAuth

from config import CFG


def _base():
    return (f"{CFG.ch_api_url}/organizations/{CFG.ch_org_id}"
            f"/services/{CFG.ch_service_id}/clickpipes")


def _auth():
    return HTTPBasicAuth(CFG.ch_api_key_id, CFG.ch_api_key_secret)


def _unwrap(resp: requests.Response):
    resp.raise_for_status()
    if not resp.content:
        return None
    body = resp.json()
    # Cloud API 는 보통 {"result": {...}} 로 감쌉니다.
    return body.get("result", body) if isinstance(body, dict) else body


def build_create_payload() -> dict:
    """Kafka(Confluent) → 기존 raw 테이블(managedTable=false) 로 적재하는 ClickPipe.

    변환은 ClickHouse MV 가 담당하므로 fieldMappings 는 1:1 이름 매핑만 합니다.
    """
    raw_fields = [
        "order_id", "order_status", "created_at",
        "customer_id", "customer_tier", "session_id", "order_lines",
    ]
    return {
        "name": CFG.clickpipe_name,
        "scaling": {"replicas": CFG.clickpipe_replicas},
        "source": {
            "kafka": {
                "type": "confluent",
                "format": "JSONEachRow",
                "brokers": CFG.kafka_bootstrap,
                "topics": CFG.kafka_topic,
                "authentication": CFG.kafka_sasl_mechanism,   # PLAIN / SCRAM-SHA-*
                "credentials": {
                    "username": CFG.kafka_api_key,
                    "password": CFG.kafka_api_secret,
                },
                "offset": {"strategy": CFG.clickpipe_offset},  # from_latest / from_beginning
            },
            "validateSamples": True,
        },
        "destination": {
            "database": CFG.database,
            "table": CFG.tbl_raw,
            "managedTable": False,          # 우리가 이미 만든 raw 테이블에 적재
        },
        "fieldMappings": [
            {"sourceField": f, "destinationField": f} for f in raw_fields
        ],
    }


def create_clickpipe(payload: dict) -> dict:
    return _unwrap(requests.post(_base(), json=payload, auth=_auth(), timeout=60))


def list_clickpipes() -> list:
    result = _unwrap(requests.get(_base(), auth=_auth(), timeout=60))
    return result or []


def find_by_name(name: str):
    for cp in list_clickpipes():
        if cp.get("name") == name:
            return cp
    return None


def get_clickpipe(pipe_id: str) -> dict:
    return _unwrap(requests.get(f"{_base()}/{pipe_id}", auth=_auth(), timeout=60))


def delete_clickpipe(pipe_id: str):
    resp = requests.delete(f"{_base()}/{pipe_id}", auth=_auth(), timeout=60)
    if resp.status_code not in (200, 202, 204, 404):
        resp.raise_for_status()
    return resp.status_code
