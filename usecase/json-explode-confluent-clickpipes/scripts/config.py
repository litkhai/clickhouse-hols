"""중앙 설정 로더. .env 를 읽어 모든 스크립트가 공유하는 값을 노출합니다.

  from config import CFG
  CFG.ch_client()          # clickhouse-connect 클라이언트
  CFG.render_sql(path)     # ${...} 플레이스홀더를 .env 값으로 치환
"""
import os
import string
import sys
from pathlib import Path

from dotenv import load_dotenv

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
ENV_PATH = ROOT / ".env"

if not ENV_PATH.exists():
    sys.exit(
        f"[config] {ENV_PATH} 가 없습니다. `cp .env.example .env` 후 값을 채우세요."
    )
load_dotenv(ENV_PATH)


def _req(key: str) -> str:
    """필수 값. 비어 있으면 즉시 중단."""
    val = os.getenv(key, "").strip()
    if not val:
        sys.exit(f"[config] .env 의 {key} 가 비어 있습니다. 값을 채워주세요.")
    return val


def _get(key: str, default: str = "") -> str:
    return os.getenv(key, default).strip()


class Config:
    # --- 오브젝트 이름 / 스키마 ---
    database = _get("CH_DATABASE", "analytics")
    tbl_raw = _get("TBL_RAW", "orders_raw")
    tbl_staging = _get("TBL_STAGING", "orders_staging")
    tbl_fact = _get("TBL_FACT", "order_lines_fact")
    mv_transform = _get("MV_TRANSFORM", "orders_transform_mv")
    mv_explode = _get("MV_EXPLODE", "order_lines_mv")

    # --- 데모 파라미터 ---
    local_tz = _get("LOCAL_TZ", "Asia/Seoul")
    valid_statuses = [s.strip() for s in _get(
        "VALID_STATUSES", "completed,processing,shipped,delivered").split(",") if s.strip()]
    staging_ttl_days = int(_get("STAGING_TTL_DAYS", "7"))

    # --- ClickPipes ---
    clickpipe_name = _get("CLICKPIPE_NAME", "order-events-explode-demo")
    clickpipe_offset = _get("CLICKPIPE_OFFSET", "from_latest")
    clickpipe_replicas = int(_get("CLICKPIPE_REPLICAS", "1"))

    # --- Producer ---
    produce_rate = float(_get("PRODUCE_RATE", "20"))
    produce_max = int(_get("PRODUCE_MAX", "0"))
    placeholder_rate = float(_get("PLACEHOLDER_RATE", "0.15"))
    empty_lines_rate = float(_get("EMPTY_LINES_RATE", "0.05"))

    # --- Kafka ---
    kafka_bootstrap = _get("KAFKA_BOOTSTRAP")
    kafka_topic = _get("KAFKA_TOPIC", "order-events")
    kafka_sasl_mechanism = _get("KAFKA_SASL_MECHANISM", "PLAIN")

    # --- 상태 파일 (생성된 ClickPipe id 저장) ---
    state_file = ROOT / ".clickpipe_state.json"
    sql_dir = ROOT / "sql"

    # ---- 필수 값 getter (사용 시점에 검증) ----
    @property
    def ch_host(self):
        return _req("CH_HOST")

    @property
    def ch_port(self):
        return int(_get("CH_PORT", "8443"))

    @property
    def ch_user(self):
        return _get("CH_USER", "default")

    @property
    def ch_password(self):
        return _req("CH_PASSWORD")

    @property
    def ch_secure(self):
        return _get("CH_SECURE", "true").lower() in ("1", "true", "yes")

    @property
    def ch_api_url(self):
        return _get("CH_API_URL", "https://api.clickhouse.cloud/v1").rstrip("/")

    @property
    def ch_api_key_id(self):
        return _req("CH_API_KEY_ID")

    @property
    def ch_api_key_secret(self):
        return _req("CH_API_KEY_SECRET")

    @property
    def ch_org_id(self):
        return _req("CH_ORG_ID")

    @property
    def ch_service_id(self):
        return _req("CH_SERVICE_ID")

    @property
    def kafka_api_key(self):
        return _req("KAFKA_API_KEY")

    @property
    def kafka_api_secret(self):
        return _req("KAFKA_API_SECRET")

    # ---- 헬퍼 ----
    def valid_statuses_sql(self) -> str:
        """SQL IN 절용: completed → 'completed','processing',..."""
        return ", ".join(f"'{s}'" for s in self.valid_statuses)

    def sql_vars(self) -> dict:
        return {
            "DATABASE": self.database,
            "TBL_RAW": self.tbl_raw,
            "TBL_STAGING": self.tbl_staging,
            "TBL_FACT": self.tbl_fact,
            "MV_TRANSFORM": self.mv_transform,
            "MV_EXPLODE": self.mv_explode,
            "LOCAL_TZ": self.local_tz,
            "STAGING_TTL_DAYS": str(self.staging_ttl_days),
            "VALID_STATUSES_SQL": self.valid_statuses_sql(),
        }

    def render_sql(self, path: Path) -> str:
        """${VAR} 플레이스홀더를 .env 값으로 치환한 SQL 문자열 반환."""
        tmpl = string.Template(Path(path).read_text(encoding="utf-8"))
        return tmpl.safe_substitute(self.sql_vars())

    def split_statements(self, sql: str):
        """세미콜론 기준 분해 (주석/빈 문 제거). 단순 DDL 용도로 충분."""
        out = []
        for chunk in sql.split(";"):
            lines = [ln for ln in chunk.splitlines()
                     if not ln.strip().startswith("--")]
            stmt = "\n".join(lines).strip()
            if stmt:
                out.append(stmt)
        return out

    def ch_client(self):
        import clickhouse_connect
        return clickhouse_connect.get_client(
            host=self.ch_host,
            port=self.ch_port,
            username=self.ch_user,
            password=self.ch_password,
            secure=self.ch_secure,
        )


CFG = Config()
