# Full-Text Search Lab with ClickHouse — Bilingual (ko/en) Support Ticket Search

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory that builds a **bilingual (Korean + English) full-text search** over **1,000,000 customer-support tickets** and rigorously compares the three indexing strategies ClickHouse offers — `tokenbf_v1`, `ngrambf_v1`, and the GA `text` inverted index — side by side.

The lab is designed to be driven from **Claude Code through the [mcp-clickhouse](https://github.com/ClickHouse/mcp-clickhouse) MCP server** against ClickHouse Cloud, so each SQL block can be executed and reasoned about interactively.

### Why this lab exists

Most full-text search demos use English-only Wikipedia dumps and the GA `text` index "just works". Korean is a different story: there is no built-in morphological analyzer, particles (조사) attach to nouns, spacing is inconsistent, and customers freely mix English error codes into Korean prose. The lab quantifies **exactly where the index helps, where it silently misses matches, and what to do about it**.

### What you will measure

| Question | Answered in |
|---|---|
| How fast is a brute-force scan on 1M rows? | `03-baseline-search.sql` |
| How much does each index type cost on disk? | `04-index-comparison.sql` §4.0 |
| Which index wins on English exact-token queries? | `04-index-comparison.sql` §4.1 |
| Which index actually finds Korean 2-character terms like "결제"? | `04-index-comparison.sql` §4.2 + `05-korean-limits.sql` §5.1 |
| How much recall do you lose to particles, spacing, and stems? | `05-korean-limits.sql` §5.1–5.3 |
| Production scenarios: live agent search, trending issues, similar tickets, MTTR | `06-real-scenarios.sql` |
| How to drop / rebuild / monitor indexes in production | `07-management.sql` |

### Dataset

- **1,000,000** tickets, partitioned by month over the last 180 days
- **~2,000,000** ticket messages (multi-turn conversations)
- **10** knowledge-base articles (FAQ matching target)
- Language mix: **70% Korean, 20% mixed ko/en, 10% English**
- Realistic content: actual Korean support-ticket phrasings (조사 변형 포함), product names, error codes
- **4 identical copies** of the tickets table with different index strategies, so every comparison is apples-to-apples

### File structure

```
fulltext-search/
├── README.md                   # this file
├── 01-schema.sql               # 4 ticket tables × 3 index strategies + articles + messages
├── 02-load.sql                 # generate 1M bilingual tickets + 2M messages
├── 03-baseline-search.sql      # LIKE / position / multiSearchAny / hasToken (no index)
├── 04-index-comparison.sql     # tokenbf vs ngrambf vs text(asciiCJK) vs text(ngrams)
├── 05-korean-limits.sql        # 조사 / 띄어쓰기 / 어간 / 복합명사 / 혼용 한계
├── 06-real-scenarios.sql       # live search, trending detection, similar tickets, MTTR, MV
└── 07-management.sql           # drop/add/materialize indexes, monitoring, cleanup
```

### Prerequisites

- **ClickHouse 26.2+** (text index GA). Earlier 25.x clusters work but the `text(...)` index falls back to scan; the comparison still produces useful numbers.
- A ClickHouse Cloud service (any size — even Development tier handles 1M rows fine).
- Local Python 3.10+ if you want to drive the lab via MCP from Claude Code.

### Connect Claude Code → ClickHouse Cloud via MCP

#### 1. Grab your service connection details

In ClickHouse Cloud → your service → **Connect** → **HTTPS**. Copy:
- `host` (e.g. `abc123.us-east-1.aws.clickhouse.cloud`)
- `username` (default: `default`)
- the password you set when creating the service

#### 2. Add the MCP server

For **Claude Code CLI**:

```bash
claude mcp add clickhouse-cloud \
  --scope project \
  --env CLICKHOUSE_HOST=YOUR_HOST.clickhouse.cloud \
  --env CLICKHOUSE_USER=default \
  --env CLICKHOUSE_PASSWORD='YOUR_PASSWORD' \
  --env CLICKHOUSE_SECURE=true \
  --env CLICKHOUSE_PORT=8443 \
  --env CLICKHOUSE_DATABASE=support_search \
  -- uv run --with mcp-clickhouse --python 3.10 mcp-clickhouse
```

For **Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS):

```json
{
  "mcpServers": {
    "clickhouse-cloud": {
      "command": "uv",
      "args": ["run", "--with", "mcp-clickhouse", "--python", "3.10", "mcp-clickhouse"],
      "env": {
        "CLICKHOUSE_HOST": "YOUR_HOST.clickhouse.cloud",
        "CLICKHOUSE_USER": "default",
        "CLICKHOUSE_PASSWORD": "YOUR_PASSWORD",
        "CLICKHOUSE_SECURE": "true",
        "CLICKHOUSE_PORT": "8443",
        "CLICKHOUSE_DATABASE": "support_search",
        "CLICKHOUSE_CONNECT_TIMEOUT": "30",
        "CLICKHOUSE_SEND_RECEIVE_TIMEOUT": "60"
      }
    }
  }
}
```

Restart Claude Code / Claude Desktop. You should now have `mcp__clickhouse-cloud__run_select_query` and friends available as tools.

#### 3. Verify

In a Claude Code session ask: *"connect to clickhouse-cloud and run `SELECT version()`"* — expect ClickHouse 26.x.

### Running the lab

Once MCP is wired up you can ask Claude Code to execute each script in turn — it will call `run_select_query` / `run_command` for every statement and stream the output back. Or run from your shell:

```bash
cd usecase/fulltext-search

# Replace with your Cloud creds, or rely on a ~/.clickhouse-client/config.xml
export CH_OPTS="--host YOUR_HOST.clickhouse.cloud --port 9440 --secure \
                --user default --password 'YOUR_PASSWORD'"

for f in 01-schema.sql 02-load.sql 03-baseline-search.sql \
         04-index-comparison.sql 05-korean-limits.sql \
         06-real-scenarios.sql 07-management.sql; do
    echo "▶ $f"
    clickhouse-client $CH_OPTS --queries-file "$f"
done
```

**Estimated total runtime** on a ClickHouse Cloud development service:

| Step | Time |
|---|---|
| 01 schema | <1 s |
| 02 load (1M tickets + 2M messages) | 3–6 min |
| 03 baseline | ~30 s |
| 04 index comparison | ~30 s |
| 05 korean limits | ~20 s |
| 06 real scenarios | ~30 s (plus MV backfill) |
| 07 management | ~10 s |

### What you will conclude (preview of the punchline)

After running the lab, the expected findings:

1. **English exact-token queries** (`PAYMENT_DECLINED`): `tokenbf_v1` and `text(asciiCJK)` are roughly tied at ~10× faster than full scan. `ngrambf_v1` does fine but isn't required.
2. **Korean 2-char queries** (`결제`): `tokenbf_v1` returns **near-zero hits** because particles fragment the token space. `text(asciiCJK)` returns correct hits with full index pruning. `ngrambf_v1`+`LIKE` is correct but slower.
3. **Korean phrase queries** (`결제 실패`): `hasPhrase()` on `text(asciiCJK)` is both fastest and most accurate. Bloom filters can only fall back to `LIKE` which means full scans behind the index probe.
4. **Particle/spacing variants** (`로그인이 안 됩니다` vs `로그인안됨`): no tokenizer recovers all of these on its own — you **must** normalize the query side-side (OR-expand the variants) regardless of which index you choose.
5. **On-disk cost**: `text(ngrams=2)` is by far the largest (often 30–60% of base table); `text(asciiCJK)` is moderate (10–20%); `tokenbf_v1` is smallest (~5%). Pick `asciiCJK` as the default and only add `ngrams` if short-substring search drives revenue.

### Author

Ken (ClickHouse Solution Architect) · 2026-06-07

---

## 한국어

ClickHouse로 **한국어+영어 혼용 풀텍스트 검색**을 100만 건의 고객지원 티켓 위에 구축하고, ClickHouse가 제공하는 세 가지 인덱스 전략 — `tokenbf_v1`, `ngrambf_v1`, GA된 `text` 역인덱스 — 을 동일 데이터에서 정량적으로 비교하는 실습입니다.

[mcp-clickhouse](https://github.com/ClickHouse/mcp-clickhouse) MCP 서버를 통해 **Claude Code에서 ClickHouse Cloud로 직접 붙어** 인터랙티브하게 실행하도록 설계되었습니다.

### 왜 이 실습이 필요한가

대부분의 풀텍스트 검색 데모는 영어 전용 데이터 (위키피디아 등)로 진행되어 `text` 인덱스가 “그냥 잘 됩니다”라고 끝납니다. 하지만 한국어는 다릅니다:

- ClickHouse에 한국어 형태소 분석기가 내장되어 있지 않음
- 명사에 조사가 직접 붙음 (`결제 + 가 = 결제가`)
- 띄어쓰기가 비일관적 (`안 됩니다` vs `안됩니다` vs `안됨`)
- 고객이 자유롭게 영어 에러 코드를 섞어 씀 (`PAYMENT_DECLINED 발생`)

이 실습은 **어디서 인덱스가 효과를 내는지, 어디서 조용히 매치를 놓치는지, 그리고 무엇을 해야 하는지**를 수치로 정량화합니다.

### 측정하는 것

| 질문 | 답이 나오는 파일 |
|---|---|
| 100만 행 풀스캔은 얼마나 걸리는가 | `03-baseline-search.sql` |
| 각 인덱스의 디스크 비용은? | `04-index-comparison.sql` §4.0 |
| 영어 정확 토큰 검색에서 누가 이기나 | `04-index-comparison.sql` §4.1 |
| 한국어 2글자 검색 ("결제")에서 누가 실제로 매치하나 | `04-index-comparison.sql` §4.2 + `05-korean-limits.sql` §5.1 |
| 조사·띄어쓰기·어간 변형으로 인한 recall 손실은 얼마? | `05-korean-limits.sql` §5.1–5.3 |
| 실전 시나리오: 상담사 라이브 검색, 급증 이슈, 유사 티켓, MTTR | `06-real-scenarios.sql` |
| 운영: 인덱스 삭제·재구축·모니터링 | `07-management.sql` |

### 데이터셋

- 티켓 **100만 건** — 최근 180일을 월별 파티션
- 티켓 메시지 **약 200만 건** — 멀티턴 대화
- 지식베이스 문서 **10건** — FAQ 매칭 대상
- 언어 비율: **한국어 70% / 한+영 혼용 20% / 영어 10%**
- 실제적인 문구: 조사 변형 포함 한국어 표현, 제품명, 에러 코드를 모두 포함
- **티켓 테이블 4벌** — 인덱스 전략만 다르고 데이터는 동일 (사과 대 사과 비교)

### 파일 구성

```
fulltext-search/
├── README.md                   # 이 파일
├── 01-schema.sql               # 4개 티켓 테이블 × 3개 인덱스 전략 + 문서/메시지
├── 02-load.sql                 # 한/영 혼용 티켓 100만 + 메시지 200만 생성
├── 03-baseline-search.sql      # LIKE / position / multiSearchAny / hasToken (인덱스 없음)
├── 04-index-comparison.sql     # tokenbf vs ngrambf vs text(asciiCJK) vs text(ngrams)
├── 05-korean-limits.sql        # 조사·띄어쓰기·어간·복합명사·혼용의 한계
├── 06-real-scenarios.sql       # 라이브 검색, 급증 탐지, 유사 티켓, MTTR, MV
└── 07-management.sql           # 인덱스 삭제/추가/머티리얼라이즈, 모니터링, 정리
```

### 사전 요구사항

- **ClickHouse 26.2+** (text 인덱스 GA). 25.x에서는 `text(...)`가 풀스캔으로 fallback되지만 다른 비교는 여전히 유효함.
- ClickHouse Cloud 서비스 (Development 티어로도 100만 행은 충분).
- Claude Code에서 MCP로 구동하려면 로컬에 Python 3.10+ 필요.

### Claude Code ↔ ClickHouse Cloud MCP 연결

#### 1. 접속 정보 확보

ClickHouse Cloud → 서비스 → **Connect** → **HTTPS** 탭에서 다음을 복사:
- `host` (예: `abc123.us-east-1.aws.clickhouse.cloud`)
- `username` (기본값: `default`)
- 서비스 생성 시 설정한 비밀번호

#### 2. MCP 서버 등록

**Claude Code CLI** 사용 시:

```bash
claude mcp add clickhouse-cloud \
  --scope project \
  --env CLICKHOUSE_HOST=YOUR_HOST.clickhouse.cloud \
  --env CLICKHOUSE_USER=default \
  --env CLICKHOUSE_PASSWORD='YOUR_PASSWORD' \
  --env CLICKHOUSE_SECURE=true \
  --env CLICKHOUSE_PORT=8443 \
  --env CLICKHOUSE_DATABASE=support_search \
  -- uv run --with mcp-clickhouse --python 3.10 mcp-clickhouse
```

**Claude Desktop** 사용 시 (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "clickhouse-cloud": {
      "command": "uv",
      "args": ["run", "--with", "mcp-clickhouse", "--python", "3.10", "mcp-clickhouse"],
      "env": {
        "CLICKHOUSE_HOST": "YOUR_HOST.clickhouse.cloud",
        "CLICKHOUSE_USER": "default",
        "CLICKHOUSE_PASSWORD": "YOUR_PASSWORD",
        "CLICKHOUSE_SECURE": "true",
        "CLICKHOUSE_PORT": "8443",
        "CLICKHOUSE_DATABASE": "support_search",
        "CLICKHOUSE_CONNECT_TIMEOUT": "30",
        "CLICKHOUSE_SEND_RECEIVE_TIMEOUT": "60"
      }
    }
  }
}
```

재시작 후 `mcp__clickhouse-cloud__run_select_query` 등의 도구가 활성화되어 있어야 합니다.

#### 3. 동작 확인

Claude Code 세션에서: *"clickhouse-cloud에 붙어서 `SELECT version()` 실행해줘"* — ClickHouse 26.x 버전이 떠야 합니다.

### 실습 실행

MCP 연결 후에는 Claude Code에 각 파일을 순서대로 실행해달라고 하면 됩니다. 또는 셸에서 직접:

```bash
cd usecase/fulltext-search

export CH_OPTS="--host YOUR_HOST.clickhouse.cloud --port 9440 --secure \
                --user default --password 'YOUR_PASSWORD'"

for f in 01-schema.sql 02-load.sql 03-baseline-search.sql \
         04-index-comparison.sql 05-korean-limits.sql \
         06-real-scenarios.sql 07-management.sql; do
    echo "▶ $f"
    clickhouse-client $CH_OPTS --queries-file "$f"
done
```

**예상 소요 시간** (Cloud Development 서비스 기준):

| 단계 | 시간 |
|---|---|
| 01 스키마 | <1초 |
| 02 데이터 적재 (티켓 100만 + 메시지 200만) | 3–6분 |
| 03 베이스라인 | ~30초 |
| 04 인덱스 비교 | ~30초 |
| 05 한국어 한계 | ~20초 |
| 06 실전 시나리오 | ~30초 (MV 백필 포함) |
| 07 관리 | ~10초 |

### 실습 후 확인할 수 있는 결론 (미리보기)

1. **영어 정확 토큰** (`PAYMENT_DECLINED`): `tokenbf_v1`과 `text(asciiCJK)`가 풀스캔 대비 약 10배 빠름. `ngrambf_v1`도 동작하지만 굳이 필요 없음.
2. **한국어 2글자** (`결제`): `tokenbf_v1`은 조사가 토큰을 쪼개기 때문에 **거의 0건**을 반환. `text(asciiCJK)`는 정상 매치 + 인덱스 prune. `ngrambf_v1`+`LIKE`도 정답을 내지만 느림.
3. **한국어 구문** (`결제 실패`): `text(asciiCJK)`의 `hasPhrase()`가 가장 빠르고 정확. 블룸 필터는 `LIKE` fallback이라 결국 인덱스 뒤에서 스캔.
4. **조사·띄어쓰기 변형** (`로그인이 안 됩니다` vs `로그인안됨`): 어떤 토크나이저도 단독으로는 모두 잡지 못함. 인덱스와 무관하게 **클라이언트에서 쿼리 정규화 (OR 확장)** 가 반드시 필요.
5. **디스크 비용**: `text(ngrams=2)`가 가장 큼 (기본 테이블의 30–60% 추가). `text(asciiCJK)`는 중간 (10–20%). `tokenbf_v1`이 가장 작음 (~5%). 기본은 `asciiCJK`로 가고, 짧은 substring 검색이 매출과 직결될 때만 `ngrams`를 추가.

### 핵심 권장사항 한 줄

> **`text(tokenizer = 'asciiCJK')` + 클라이언트 쿼리 정규화** 의 조합이 한국어 풀텍스트 검색에서 가장 균형 잡힌 기본값입니다. 형태소 분석이 필요한 경우 ClickHouse 외부 NLP (예: KoNLPy, mecab-ko) 에서 토큰화된 컬럼을 별도로 두고 그 위에 `text(tokenizer = 'array')` 또는 `splitByString` 토크나이저를 사용하세요.

### 라이선스

MIT License

### 작성자

Ken (ClickHouse Solution Architect) · 2026-06-07
