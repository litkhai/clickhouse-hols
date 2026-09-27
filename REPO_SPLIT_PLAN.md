# clickhouse-hols 분산 계획 (Repo Split Plan)

> 상태: **롤아웃 완료 (2026-09-27)** — 코어 PR #2 머지(`e9cf21b`), 새 레포 4개 public. 남은 것은 §8 트랙
> 키트(`~/Documents/GitHub/repo-split-kit`)와 로컬 잔여 파일은 롤아웃 후 삭제함 (2026-09-27). 다시 분리할 때는 §5의 절차로 키트를 새로 만듭니다.
> 작성 기준: `origin/main` @ `fe0f26e` (2026-09-27)
> v2 변경: Postgres 레포 이름을 `clickhouse-managed-postgres-hols`로 변경하고
> `local/pg-analytics`는 코어에 남김. `clickstack-hyperdx-hols` 신설 — 코어의
> `observability/` 영역 안을 폐기하고 ClickStack 계열을 새 레포로 옮김.
> v3 변경: §1을 기본값으로 확정. 단 D2는 archive하지 않고 유지하며, AWS 실습
> README마다 마지막 검증 시점 배너를 추가 (§5.1-D, §5.5, §8 트랙 K).
> 이 문서 안의 경로는 일부러 링크가 아닌 code span으로 적었습니다. 커밋해도
> `links` job이 깨지지 않게 하기 위해서입니다.

---

## 0. 원칙

1. **롤아웃 = 기계적 이동만.** 실행 동작을 바꾸는 코드 수정(러너, 크로스플랫폼,
   CHC 자동화)은 롤아웃에 넣지 않는다. 동작이 바뀌면 재검증이 필요하고
   (AGENTS.md "Verification claims"), 그러면 "한 번에"가 불가능해진다.
   문서 링크 수정만 허용.
2. **코드로 엮인 실습은 함께 움직이거나 함께 남는다.** (§4)
3. **기존 문서는 계속 접근 가능해야 한다.** 세 겹으로 보장:
   - 사이트: 옮긴 실습의 `docs/labs/<old>/`에 redirect 페이지
   - GitHub `/tree/main/<old>/`: 옛 경로에 pointer README(stub)
   - 영구 스냅샷: `pre-split-2026-10` 태그 → 옛 deep link는 `/tree/pre-split-2026-10/<old>`
4. **상대 링크 깊이 유지.** 새 레포에서도 디렉터리 깊이를 원본과 같게 두어
   `../../LICENSE`, `../../README.md` 같은 링크를 다시 쓰지 않아도 되게 한다.
   (예외: `ch2otel` 한 곳, §3.1)
5. **새 레포는 비공개로 만들어 검사한 뒤 공개한다.** gitleaks와 링크 검사를 통과하고 코어 PR이 머지된 뒤에만 public으로 바꾼다.
6. **히스토리는 `origin`에서 새로 clone해서 자른다.** 로컬 clone에는
   `backup-local-main-20260907`(재작성 전 히스토리, 실제 CHC 자격증명 포함)이 있으므로
   절대 로컬 clone을 원본으로 쓰지 않는다.

---

## 1. 결정사항 (확정 2026-09-27)

D2를 제외한 모든 항목은 기본값으로 확정했습니다. D2만 대안 쪽으로 바꿨습니다.

| # | 결정 | 확정 | 채택하지 않은 안 |
|---|------|--------------|------|
| D1 | 새 레포 이름 | `clickhouse-managed-postgres-hols`, `clickstack-hyperdx-hols`, `langfuse-hols`, `clickhouse-cloud-aws-hols` | — |
| D2 | Terraform/AWS 실습 레포 상태 | **archive하지 않고 일반 레포로 유지.** 대신 실습 README 7개 맨 위에 **마지막 검증 시점 배너**를 넣어, 언제 실제로 돌려 봤고 그 뒤로 무엇이 재실행 없이 바뀌었는지 밝힘 (§5.1-D) | 생성 후 GitHub Archive(읽기 전용) — 2026-08 이후 손대지 않았고 대부분 단일 언어이며 provider가 낡았다는 이유 |
| D3 | `tpcds/` | **pointer만 두고 원본은 태그로 보존.** diff 결과 내용은 다르지만(§5.0 D3 결과), 라이선스가 달라 import하지 않음 | `tpcds-scripts`에 `legacy/`로 스냅샷 import |
| D4 | LibreChat 실습 2개 (`local/llm-*`) | **이번엔 코어에 둔다** — `llm-mac`이 `../mcp-server-clickhouse`(docker build context)와 `../oss-mac-setup`에 코드로 묶여 있음 | vendoring 수정 + 재검증 후 `llmops-in-a-box/examples/`로 |
| D5 | 워크숍 3개 | **`o11y-vector-ai`, `observability-waf` → `clickstack-hyperdx-hols/workshops/`**, **`device-360` → 코어 `usecase/device-360`**, 코어의 `workshop/` 영역 폐지 | `device-360`도 밖으로 |
| D6 | 옛 경로 stub README | **실습마다 생성, 2027-03-31에 제거** (그 뒤로는 사이트 redirect와 태그만 남음) | 영역당 1개만 / 생성 안 함 |
| D7 | 새 레포 문서 사이트 | **롤아웃 때는 없음** (GitHub README로 충분). 다만 `clickstack-hyperdx-hols`는 실습이 늘어날 예정이므로 트랙 F에서 가장 먼저 켠다 | 롤아웃 때 함께 |
| D8 | 코어 히스토리의 `tfplan` (§6.3) | **이번엔 재작성하지 않음**, 대신 노출된 AWS 리소스와 role을 점검·교체 | 코어 히스토리 재작성 + GitHub 캐시 purge 요청 |
| D9 | `chc/tool/costkeeper*` | **코어 유지** (CHC 안에서 도는 SQL/RMV라 ClickHouse가 주연) | 도구 레포로 분리 |
| D10 | `local/pg-analytics` | **코어 유지** — pg_lake, pg_duckdb, Polaris를 쓰는 자체 호스팅 벤치마크라 Managed Postgres 제품과 맞지 않음. 2026-09-25에 커밋한 블로그 글의 경로(`local/pg-analytics`)도 그대로 유효 | Managed Postgres 레포의 `extensions/`로 |
| D11 | `local/pg-clickhouse-lab` | **Managed Postgres 레포의 `extensions/`로** — `pg_clickhouse`는 Managed Postgres의 ClickHouse 연동 확장이고, 이 실습은 Managed Postgres README가 권하는 "로컬 Docker 개발" 경로 그 자체 | 코어 유지 |
| D12 | `chc/tool/ch2otel` | **`clickstack-hyperdx-hols/labs/ch2otel`로** — ClickHouse 시스템 메트릭을 OTel 스키마로 바꿔 HyperDX에서 보는 도구 | 코어 유지 |

---

## 2. 목표 구조

```
litkhai/clickhouse-hols                 (코어 — URL, Pages, star 유지)
├── local/          oss-mac-setup, releases/(21), datalake-minio-catalog,
│                   kafka-mysql-table-engines, pg-analytics,              ← D10
│                   mcp-server-clickhouse,
│                   llm-mac-librechat-with-clickhouse, llm-linux-librechat-sole   ← D4
├── chc/            api/chc-api-test, clickpipes-mysql, clickpipes-s3,
│                   cloud-to-oss-peerdb, mysql-interface,
│                   tool/costkeeper, tool/costkeeper-multi                    ← D9
├── usecase/        (langfuse 2개 빠짐, device-360 들어옴) 12개
├── workload/       11개 (변경 없음)
├── MOVED.md        옛 경로 → 새 위치 (build_site가 redirect 생성에 사용)
└── (stub만)        managed-postgres/*, local/pg-clickhouse-lab, usecase/langfuse-*,
                    chc/{kafka,lake,s3}/*, chc/tool/ch2otel, tpcds, workshop/*

litkhai/clickhouse-managed-postgres-hols   (신규, 히스토리 포함)
├── managed-postgres/  provisioning, postgis-fdw-bike, vector-search,
│                      ny-citi-bike-workshop(pointer)                        ← 깊이 2 유지
└── extensions/        pg-clickhouse-lab                                     ← D11, 깊이 2 유지

litkhai/clickstack-hyperdx-hols            (신규, 히스토리 포함 — 앞으로 가장 많이 늘어날 레포)
├── _base/             (트랙 F) ClickStack all-in-one compose / Cloud 연결
├── labs/              ch2otel                                              ← D12, 이후 실습 추가
└── workshops/         o11y-vector-ai, observability-waf                    ← 깊이 2 유지

litkhai/langfuse-hols                      (신규, 히스토리 포함)
└── labs/              langfuse-ee, langfuse-eval                           ← 깊이 2 유지

litkhai/clickhouse-cloud-aws-hols          (신규, 히스토리 포함, tfplan 제외, D2: 유지 + 검증 시점 배너)
└── labs/{kafka,lake,s3}/...                                                ← 깊이 3 유지

litkhai/tpcds-scripts                      (기존, D3)
```

**숫자 (롤아웃 후):**

| | 롤아웃 전 | 롤아웃 후 코어 |
|---|---:|---:|
| 영역 표 실습 | 56 | **38** |
| release 실습 | 21 | 21 |
| 단일 언어 실습 | 28 | **18** |
| 사이트 redirect 페이지 | 0 | 19 |

레포 밖으로 나가는 18개의 내역: Managed Postgres 5, ClickStack 3, Langfuse 2, AWS 7, tpcds 1. 레포 안에서 옮기는 것은 `device-360` 1개입니다.

단일 언어 실습 중 10개가 밖으로 나갑니다: AWS 7, tpcds, `o11y-vector-ai`, `observability-waf`.

---

## 3. 실습별 이동표

### 3.1 레포 밖으로 (18개)

| 옛 경로 | 새 위치 | 방식 | filter-repo에 함께 넣을 과거 경로 |
|---|---|---|---|
| `managed-postgres/` (README + 4개) | `clickhouse-managed-postgres-hols/managed-postgres/` | 히스토리 | — |
| `local/pg-clickhouse-lab` | `clickhouse-managed-postgres-hols/extensions/pg-clickhouse-lab` | 히스토리 | — |
| `chc/tool/ch2otel` | `clickstack-hyperdx-hols/labs/ch2otel` | 히스토리 | `chc/tool/db2otel/` (`archive_sql_v0`의 원래 위치). **깊이 3→2: `../../../LICENSE` → `../../LICENSE` 수정** |
| `workshop/o11y-vector-ai` | `clickstack-hyperdx-hols/workshops/o11y-vector-ai` | 히스토리 | **`workshop/o11y-vector-ai.backup-20251220-203405/`는 제외** (과거 백업 사본) |
| `workshop/observability-waf` | `clickstack-hyperdx-hols/workshops/observability-waf` | 히스토리 | — |
| `usecase/langfuse-ee` | `langfuse-hols/labs/langfuse-ee` | 히스토리 | `usecase/langfuse/` |
| `usecase/langfuse-eval` | `langfuse-hols/labs/langfuse-eval` | 히스토리 | — |
| `chc/kafka/terraform-confluent-aws` | `clickhouse-cloud-aws-hols/labs/kafka/…` | 히스토리 | `terraform-confluent-aws/` |
| `chc/kafka/terraform-confluent-aws-nlb-ssl` | 〃 | 히스토리 | `terraform-confluent-aws-nlb-ssl/` |
| `chc/kafka/terraform-confluent-aws-connect-sink` | 〃 | 히스토리 | `terraform-confluent-aws-connect-sink/` |
| `chc/lake/terraform-minio-on-aws` | `…/labs/lake/…` | 히스토리 | `terraform-minio-on-aws/` |
| `chc/lake/terraform-glue-s3-chc-integration` | 〃 | 히스토리 | `terraform-glue-s3-chc-integration/` |
| `chc/s3/terraform-chc-secures3-aws` | `…/labs/s3/…` | 히스토리 (**tfplan, backup-metadata 제외**) | `terraform-chc-secures3-aws/` |
| `chc/s3/terraform-chc-secures3-aws-direct-attach` | 〃 | 〃 | `terraform-chc-secures3-aws-direct-attach/` |
| `tpcds` | stub → 태그 원본 + `tpcds-scripts` (D3) | pointer | — |

### 3.2 레포 안에서 이동 (1개)

| 옛 경로 | 새 경로 | 링크 수정 |
|---|---|---|
| `workshop/device-360` | `usecase/device-360` | 없음 (깊이 동일) |

### 3.3 그대로 (코어 유지)

`local/*`(`pg-clickhouse-lab` 제외, `pg-analytics` 포함), `local/releases/*`, `chc/api`,
`chc/clickpipes-*`, `chc/cloud-to-oss-peerdb`, `chc/mysql-interface`,
`chc/tool/costkeeper*`, `usecase/*`(langfuse 2개 제외), `workload/*`.

---

## 4. 경계를 넘는 의존성과 조치

전체 레포에서 실습 간 링크와 코드 참조를 스캔한 결과, 경계를 넘는 것만 추렸습니다.

| 출발 | 도착 | 종류 | 조치 |
|---|---|---|---|
| `usecase/langfuse-eval` | `usecase/langfuse-ee` | **코드** (`01-seed-traces.py`가 ee의 생성기를 import, compose 공유) | 함께 이동 → 형제 관계 유지 ✅ |
| `chc/kafka/*-nlb-ssl`, `*-connect-sink` | `chc/kafka/terraform-confluent-aws` | 문서 | 함께 이동 ✅ |
| `chc/s3/*-direct-attach` | `chc/s3/terraform-chc-secures3-aws` | 문서 | 함께 이동 ✅ |
| `managed-postgres/vector-search` | `usecase/fulltext-search` | 문서 | 새 레포에서 http 링크로 교체 |
| `managed-postgres/ny-citi-bike-workshop` | `managed-postgres/postgis-fdw-bike` | 문서 | 함께 이동 ✅ |
| `local/pg-clickhouse-lab` | 루트 `README.md` | 문서 | 새 레포 루트 README를 가리키게 됨. 문구만 확인 |
| `workshop/observability-waf` | 내부 `etc/` | 코드 | 레포 내부 참조라 함께 이동 ✅ |
| `local/llm-mac-librechat-with-clickhouse` | `local/mcp-server-clickhouse`, `local/oss-mac-setup` | **코드** | D4: 코어 유지 |
| `local/releases/*`, `usecase/timeseries-promql-oss`, `workload/replacingmergetree` | `local/oss-mac-setup` | 코드·문서 | 모두 코어 유지 ✅ (이름 변경은 트랙 B) |
| `local/releases/25.8` | `local/datalake-minio-catalog` | 코드 | 모두 코어 유지 ✅ |
| 루트 `README.md` 학습 경로 | tpcds, `chc/s3/…`, `chc/lake/…`, `chc/kafka/…`, `managed-postgres/…` | 문서 | §5.4에서 http로 교체하거나 코어 실습으로 대체 |
| `.gitleaks.toml` allowlist | `usecase/langfuse-ee/08-generate-pii-traces.py` | 설정 | `langfuse-hols`로 옮기고(`labs/…`), 코어에서는 제거 |
| `.gitignore` | `workshop/observability-waf/artifact.md` | 설정 | `clickstack-hyperdx-hols`의 `.gitignore`로 옮기고(`workshops/…`), 코어에서는 제거 |

**공개 히스토리 gitleaks 결과를 경로별로 나누면** (`--log-opts=origin/main`, 19건):

| 경로 | 건수 | 이번 계획에서 |
|---|---:|---|
| `local/llm-mac-librechat` | 10 | 코어에 남음 (D4) |
| `terraform-glue-s3-chc-integration` | 3 | `clickhouse-cloud-aws-hols`로 → `.gitleaksignore` |
| `usecase/bug-bounty` | 4 | 코어에 남음 (현재는 없는 경로) |
| `tpcds` | 2 | 코어 히스토리에 그대로 남음 (D3: pointer만, 옮기지 않음) |
| **ClickStack·Managed Postgres·Langfuse 경로** | **0** | 깨끗함 |

---

## 5. 롤아웃 절차

### 5.0 사전 준비 (D-1)

```bash
brew install git-filter-repo gitleaks gh
gh auth status                      # repo 권한 확인
```

- [x] §1 결정사항 확정 (2026-09-27, D2는 유지 + 배너)
- [x] ~~코어 `main` 동결 공지~~ → 혼자 쓰는 레포라 공지는 필요 없음. 대신 **D-day까지 `main`에 push하지 않기.** 이유: 태그, 리허설, `.gitleaksignore` 지문이 모두 `fe0f26e`를 기준으로 함. D-day 첫 단계에서 `git rev-parse origin/main pre-split-2026-10^{}`로 둘이 같은지 확인하고, 다르면 `rehearse.sh`를 다시 실행
- [x] 태그 생성·푸시 (2026-09-27, annotated, `pre-split-2026-10` → `fe0f26e`):
  ```bash
  git fetch origin
  git tag pre-split-2026-10 origin/main
  git push origin pre-split-2026-10
  ```
- [x] 도구 확인 (2026-09-27): git-filter-repo, gitleaks 8.30.1, gh 2.96.0(`litkhai`, `repo` scope), jq. 새 레포 이름 4개 모두 비어 있음
- [x] D3: `tpcds/`와 `tpcds-scripts/engines/`의 ClickHouse 부분 비교 (2026-09-27) → **이미 들어 있지 않음.** 아래 D3 결과 참고
- [x] 새 레포 공통 키트 준비 (`KIT=~/Documents/GitHub/repo-split-kit`, 어느 레포에도 속하지 않음):
  - `common/` (4개 레포 공통), `overlays/<repo>/` (레포별), `gen_overlays.py`가 overlays를 생성
  - `assemble.sh <repo> <dir>` — common + overlay 복사 (v2의 `cp -R "$KIT"/. .`을 대신함)
  - `fix_docs.sh <repo>` — filter-repo 뒤의 문서 경로 수정 (아래 "문서 수정" 주석을 대신함)
  - `rehearse.sh <dir>` — §5.1 A–D를 origin에서 새로 clone해 로컬에서만 재현 (push 없음)
  - 구성:
  - `LICENSE` (MIT, 코어와 동일)
  - `.gitignore` (코어 것에서 해당 부분만)
  - `.gitleaks.toml` (코어 규칙 복사 + 레포별 allowlist)
  - `.githooks/pre-commit`
  - `.github/scripts/check_links.py`, `.github/scripts/check_syntax.sh` (코어 것 그대로)
  - `.github/workflows/checks.yml` (`links`, `syntax`, `secrets`, `hygiene`; `site` job 제외 — D7)
  - `AGENTS.md` (짧게: 코어 AGENTS.md 링크 + 레포별 규칙)
  - `README.md` (이중 언어, 실습 표, "원래 clickhouse-hols에 있었음 → `pre-split-2026-10`" 한 줄)
  - `.gitleaksignore` (`clickhouse-cloud-aws-hols`만, 지문 3개. 지문에 재작성된 커밋 SHA가 들어가므로 **동결 뒤 `origin/main`이 움직였다면 `rehearse.sh`로 다시 생성**)
- [x] 리허설 (2026-09-27, `origin/main` @ `fe0f26e`) — 결과는 아래 "D-1 리허설 결과"

**D3 결과.** 두 쪽은 출처가 다릅니다.
- 코어 `tpcds/queries/` 99개: `Altinity/tpc-ds`에서 가져와 수정한 **GPL-3.0** 파일. 44개에 수작업 최적화 표시(`Filtering joins rewritten to where join key IN` 38개, 불필요한 join 제거 23개 등)
- `tpcds-scripts/engines/clickhouse/queries/`: ClickHouse 공식 벤치마크를 그대로 가져온 **Apache-2.0** 파일 (`query14_1/_2`처럼 분할)
- 정규화 후 동일한 쿼리 0개, 유사도 중앙값 0.42. DDL도 타입 선택이 다름
- 따라서 기본값의 전제("이미 들어 있으면 pointer만")가 성립하지 않음. 대안(`tpcds-scripts`에 `legacy/`로 import)은 Apache-2.0 레포에 GPL-3.0 파일을 넣는 것이라 `tpcds-scripts` NOTICE의 방침과 충돌함
- **확정 (2026-09-27): pointer + 태그 보존.** `tpcds/` stub이 `pre-split-2026-10` 태그의 원본(Altinity 변형, GPL-3.0)과 `tpcds-scripts`(유지보수 중인 후속, 쿼리 출처 다름)를 **둘 다** 안내하고, 차이를 한 줄로 적음. `tpcds-scripts`에서는 할 일 없음

**D-1 리허설 결과** (`rehearse.sh` → `fix_docs.sh`, push 없음):

| 레포 | 커밋 | 파일 | links | syntax | gitleaks | hygiene |
|---|---:|---:|---|---|---|---|
| clickhouse-managed-postgres-hols | 22 | 72 | `fix_docs` 전 2건 → 후 0건 | OK | 0 | OK |
| clickstack-hyperdx-hols | 21 | 78 | 2건 → 0건 | OK | 0 | OK |
| langfuse-hols | 10 | 49 | 0건 | OK | 0 | OK |
| clickhouse-cloud-aws-hols | 67 | 101 | 0건 | OK | 3건 → `.gitleaksignore` 뒤 0건 | OK |

- 히스토리에 남은 AWS state 경로 0개, `o11y-vector-ai.backup` 0개, 현재 트리에 `_history-db2otel` 0개 — §6.1 기대와 같음
- **계획에 없던 것:** `cd <옛 경로>` 명령이 langfuse만이 아니라 세 레포에 남아 있었음 (`local/pg-clickhouse-lab` 2곳, `workshop/o11y-vector-ai` 6곳, `usecase/langfuse-*` 15곳). `fix_docs.sh`가 수정함. 캡처된 실행 기록 `lab-output.md`는 원문 그대로 둠 (검증 기록이므로)

### 5.1 새 레포 만들기 (D-day)

작업 디렉터리는 스크래치 공간 (`W=$(mktemp -d)`)에 둡니다. **항상 origin에서 새로 clone합니다.**

#### A. `clickhouse-managed-postgres-hols`

```bash
cd "$W"
git clone --single-branch --no-tags https://github.com/litkhai/clickhouse-hols.git clickhouse-managed-postgres-hols
cd clickhouse-managed-postgres-hols
git filter-repo \
  --path managed-postgres/ \
  --path local/pg-clickhouse-lab/ \
  --path LICENSE \
  --path-rename local/pg-clickhouse-lab/:extensions/pg-clickhouse-lab/
"$KIT"/assemble.sh clickhouse-managed-postgres-hols . && "$KIT"/fix_docs.sh clickhouse-managed-postgres-hols
# 문서 수정 (fix_docs.sh가 처리)
#  - managed-postgres/vector-search/README.md: ../../usecase/fulltext-search
#      → https://github.com/litkhai/clickhouse-hols/tree/main/usecase/fulltext-search
#  - managed-postgres/README.md: "../README.md"가 새 루트 README를 가리킴 — 문구 확인
#  - 루트 README: 관련 실습으로 코어의 local/pg-analytics를 http로 안내
python3 .github/scripts/check_links.py && ./.github/scripts/check_syntax.sh
git add -A && git commit -m "Split from litkhai/clickhouse-hols@pre-split-2026-10"
```

#### B. `clickstack-hyperdx-hols`

```bash
cd "$W"
git clone --single-branch --no-tags https://github.com/litkhai/clickhouse-hols.git clickstack-hyperdx-hols
cd clickstack-hyperdx-hols
git filter-repo \
  --path chc/tool/ch2otel/ \
  --path chc/tool/db2otel/ \
  --path workshop/o11y-vector-ai/ \
  --path workshop/observability-waf/ \
  --path LICENSE \
  --path-rename chc/tool/ch2otel/:labs/ch2otel/ \
  --path-rename chc/tool/db2otel/:labs/ch2otel/_history-db2otel/ \
  --path-rename workshop/:workshops/
# 주의: `--path workshop/o11y-vector-ai/`는 끝의 `/` 때문에
#       `workshop/o11y-vector-ai.backup-20251220-203405/`와 매칭되지 않음 → 자동 제외.
git log --all --name-only --format= | grep -c 'o11y-vector-ai.backup' # 0이어야 함
"$KIT"/assemble.sh clickstack-hyperdx-hols . && "$KIT"/fix_docs.sh clickstack-hyperdx-hols
# 문서·설정 수정 (fix_docs.sh와 overlay가 처리)
#  - labs/ch2otel/README.md: ../../../LICENSE → ../../LICENSE (깊이 3→2)
#  - .gitignore: workshops/observability-waf/artifact.md
#  - 루트 README: 영역 표(labs / workshops) + 로드맵 표(§8 트랙 F의 빈 슬롯)
python3 .github/scripts/check_links.py && ./.github/scripts/check_syntax.sh
git add -A && git commit -m "Split from litkhai/clickhouse-hols@pre-split-2026-10"
```

> `db2otel` → `_history-db2otel` 이름 변경: 과거 커밋의 파일은 `archive_sql_v0`로
> 한 번 더 이름이 바뀌어 현재 트리에 들어 있습니다. 따라서 현재 트리에서는
> `_history-db2otel`가 비어 있고, 과거 커밋에만 존재합니다. 현재 트리에 남아 있으면
> 그 커밋에서 삭제합니다.

#### C. `langfuse-hols`

```bash
cd "$W"
git clone --single-branch --no-tags https://github.com/litkhai/clickhouse-hols.git langfuse-hols
cd langfuse-hols
git filter-repo \
  --path usecase/langfuse/ \
  --path usecase/langfuse-ee/ \
  --path usecase/langfuse-eval/ \
  --path LICENSE \
  --path-rename usecase/langfuse/:labs/langfuse-ee/ \
  --path-rename usecase/:labs/
"$KIT"/assemble.sh langfuse-hols . && "$KIT"/fix_docs.sh langfuse-hols
# (overlay와 fix_docs.sh가 처리) .gitleaks.toml allowlist: '''labs/langfuse-ee/08-generate-pii-traces\.py$'''
# 본문의 `usecase/langfuse-ee` 경로 문구 → `labs/langfuse-ee`
python3 .github/scripts/check_links.py && ./.github/scripts/check_syntax.sh
git add -A && git commit -m "Split from litkhai/clickhouse-hols@pre-split-2026-10"
```

> 검증 문구("Langfuse v3.197.1 / SDK 3.7.0 / CH 25.11, 2026-07-26")는 **그대로 둡니다.**
> 경로만 바뀌었고 스크립트는 바뀌지 않았으므로 기존 검증이 유효합니다.

#### D. `clickhouse-cloud-aws-hols`

```bash
cd "$W"
git clone --single-branch --no-tags https://github.com/litkhai/clickhouse-hols.git clickhouse-cloud-aws-hols
cd clickhouse-cloud-aws-hols
# 1차: 포함
git filter-repo \
  --path chc/kafka/ --path chc/lake/ --path chc/s3/ --path LICENSE \
  --path terraform-confluent-aws/ \
  --path terraform-confluent-aws-nlb-ssl/ \
  --path terraform-confluent-aws-connect-sink/ \
  --path terraform-minio-on-aws/ \
  --path terraform-glue-s3-chc-integration/ \
  --path terraform-chc-secures3-aws/ \
  --path terraform-chc-secures3-aws-direct-attach/ \
  --path-rename chc/:labs/
# 2차: 실제 AWS state가 담긴 파일을 히스토리에서 제거
git filter-repo --force --invert-paths \
  --path-glob '*tfplan' --path-glob '*.tfplan' \
  --path-glob '*.tfstate' --path-glob '*.tfstate.*' \
  --path-glob '*backup-metadata-*'
git log --all --name-only --format= | grep -E 'tfplan|tfstate|backup-metadata' && echo "!!! 남아 있음" || echo "clean"
"$KIT"/assemble.sh clickhouse-cloud-aws-hols . && "$KIT"/fix_docs.sh clickhouse-cloud-aws-hols
python3 .github/scripts/check_links.py && ./.github/scripts/check_syntax.sh
git add -A && git commit -m "Split from litkhai/clickhouse-hols@pre-split-2026-10"
# D2: 실습 README 7개 맨 위(제목 바로 아래)에 마지막 검증 시점 배너 추가 — 아래 표
git add -A && git commit -m "Add last-verified banners to the AWS labs"   # D2, 분리 커밋과 따로
```

**마지막 검증 시점 배너 (D2).** 원칙 0.1의 "문서 수정만 허용"에 해당합니다. 스크립트는
건드리지 않고, AGENTS.md "Verification claims"에 따라 **실제로 돌린 날짜만** 적습니다.
실행 로그가 따로 없으므로 날짜는 git에서 구한 **마지막 기능 커밋**(실행하면서 고친 흔적)이며,
그 뒤의 정리 커밋은 "재실행 없이 바뀐 것"으로 따로 적습니다.

| 실습 | 마지막 실행 (git 기준) | 그 뒤 재실행 없이 바뀐 것 | 비고 |
|---|---|---|---|
| `kafka/terraform-confluent-aws` | 2025-11-20 (`9c262ec`) | 2026-07-28 자격증명 제거(`6aeebc8`), 2026-08-10 `allowed_cidr_blocks` 필수화(`58c93c4`) | |
| `kafka/terraform-confluent-aws-nlb-ssl` | 2025-11-20 (`a2459bd`) | 〃 | |
| `kafka/terraform-confluent-aws-connect-sink` | 2025-11-24 (`7daf4ee`) | 〃 | |
| `lake/terraform-minio-on-aws` | 2025-11-16 (`5fc2444`) | 2026-08-10 `allowed_cidr_blocks` 필수화(`58c93c4`) | |
| `lake/terraform-glue-s3-chc-integration` | 2025-11-17 (`1e97dfe`) | — | |
| `s3/terraform-chc-secures3-aws` | 2025-11-30 (`cbe0cf8`) | — | |
| `s3/terraform-chc-secures3-aws-direct-attach` | 2025-12-05 (`e0042aa`) | — | **마지막 실행이 ClickHouse Cloud에서 실패** (커밋 메시지 "(fail)", README 상단 경고와 일치). 배너에도 그대로 적음 |

공통: AWS provider `~> 5.0`. `58c93c4`는 terraform 1.15.8에서 `plan`과 `deploy.sh`의
CIDR 입력 경로까지만 확인했고 `apply`는 하지 않았습니다 — 배너에 이 구분을 적습니다.
롤아웃 전날 위 표를 `git log origin/main -- <lab>/*.tf <lab>/*.sh <옛 루트 경로>`로 한 번 더 확인합니다.

배너 템플릿 (EN 먼저, 한 블록):

```markdown
> **Last verified: 2025-11-20** (end-to-end `deploy.sh` → `destroy.sh`, AWS provider `~> 5.0`).
> Changed since without a full re-run: credential cleanup (2026-07-28);
> `allowed_cidr_blocks` is now required (2026-08-10, checked with `terraform plan` only).
> Provider and AMI versions may have drifted — expect to adjust before applying.
>
> **마지막 검증: 2025-11-20** (`deploy.sh` → `destroy.sh` 전 과정, AWS provider `~> 5.0`).
> 그 뒤 전체 재실행 없이 바뀐 것: 자격증명 정리(2026-07-28),
> `allowed_cidr_blocks` 필수화(2026-08-10, `terraform plan`까지만 확인).
> provider와 AMI 버전이 달라졌을 수 있으니 apply 전에 조정이 필요할 수 있습니다.
```

실습을 다시 돌리면 배너 날짜와 "바뀐 것" 줄을 갱신합니다 (§8 트랙 K). 이 규칙은 새 레포 `AGENTS.md`에 적습니다.

> 옛 루트 경로(`terraform-*/`)는 이름을 바꾸지 않고 과거 커밋에 그대로 둡니다.
> 그때 파일이 그 위치에 있었다는 것이 사실이므로 히스토리로서 맞습니다.

#### E. `tpcds-scripts` (D3)

- 확정: pointer만 둠. 할 일 없음 (코어 stub에서 태그와 `tpcds-scripts`를 둘 다 안내).
- (채택 안 함) import할 경우: `tpcds-scripts`에서 브랜치를 만들어 `tpcds/`를 스냅샷 복사하고, 커밋 메시지에 `from litkhai/clickhouse-hols@<sha>:tpcds`를 적은 뒤 PR을 엽니다. `tpcds/sql/*.sql` 3개의 CRLF는 이때 LF로 정규화합니다.

> **진행 (2026-09-27):** A–D 로컬 생성 완료 (`~/Documents/GitHub/repo-split-kit/work/`, push 전).
> HEAD — managed-postgres `15e5f04`, clickstack `d0e45e7`, langfuse `859b8c1`, cloud-aws `0bcfbfc` (분리 커밋 + 배너 커밋).
> 배너 표현: 날짜는 "실습을 실행하며 남긴 마지막 커밋"이라고 밝히고, `direct-attach`는 "Last run — not verified"로 적음.
> 2026-07-28 SASL 자격증명 필수화도 재실행하지 않은 변경이라 kafka 3개 배너에 함께 적음.

### 5.2 새 레포 검사

```bash
NEW="clickhouse-managed-postgres-hols clickstack-hyperdx-hols langfuse-hols clickhouse-cloud-aws-hols"
for r in $NEW; do
  (cd "$W/$r" && echo "== $r" \
    && gitleaks detect --config .gitleaks.toml --no-banner --redact \
         --report-format json --report-path "$W/$r.gitleaks.json"; \
       jq length "$W/$r.gitleaks.json")
done
```

예상 결과:

| 레포 | 예상 발견 | 판단 |
|---|---|---|
| clickhouse-cloud-aws-hols | `terraform-glue-s3-chc-integration/CREDENTIAL_SOLUTIONS.md`의 STS 임시 자격증명(잘린 샘플) 3건 | STATUS.md 기존 평가와 같이 무해. 지문을 `.gitleaksignore`에 추가 |
| langfuse-hols | 0건 (합성 PII는 allowlist로 처리) | — |
| clickstack-hyperdx-hols | 0건 | 한 건이라도 나오면 중단하고 확인 |
| clickhouse-managed-postgres-hols | 0건 | 〃 |

> `.gitleaksignore`가 필요한 이유: 새 레포의 첫 push에서는 gitleaks-action이 히스토리 전체를 스캔합니다. 무해한 과거 발견 때문에 CI가 첫날부터 red가 되지 않게 미리 막아 둡니다.

### 5.3 새 레포 생성과 push (비공개)

```bash
for r in $NEW; do
  (cd "$W/$r" && gh repo create "litkhai/$r" --private --source . --push \
     --description "…(README 첫 줄)…")
done
```

- [x] 4개 레포 생성·push 완료 (2026-09-27, private)
- [x] 각 레포 Actions green 확인. `langfuse-hols`의 첫 push `secret scan`만 실패했는데 유출이 아니라 gitleaks-action의 알려진 문제: push 이벤트 커밋이 20개 미만이면 root 커밋이 포함되어 `root^..HEAD` 범위를 만들 수 없음. 네 레포 모두 `workflow_dispatch`로 전체 히스토리 스캔을 다시 돌려 green, leak 0 확인
- [ ] ~~Settings에서 secret scanning과 push protection을 켬~~ → 개인 계정의 private 레포에서는 불가("Secret scanning is not available"). **§5.5에서 public으로 바꾼 직후 켬**

### 5.4 코어 PR (브랜치 `repo-split`)

> **진행 (2026-09-27):** 1–11 완료. 계획과 다르게 한 점:
> - 삭제 후 각 실습의 `.gitignore`가 사라지면서 숨겨져 있던 로컬 파일이 untracked로 드러남 (`nlb-private-key.pem`, tfstate, `.env`, sample data 등). 커밋되지 않도록 전부 `~/Documents/GitHub/repo-split-kit/core-leftovers/`로 경로 그대로 **이동** (삭제 아님)
> - `MOVED.md`는 20행 (영역 폴더 `managed-postgres` 포함). 영역 폴더는 다른 행의 prefix이면 redirect를 만들지 않는 규칙으로 처리 → redirect 19개
> - `tpcds`의 MOVED 대상은 태그 원본. stub은 태그와 `tpcds-scripts`를 둘 다 안내 (D3)
> - 학습 경로: Advanced의 두 번째 항목은 Beginner와 겹치지 않게 `workload/projection`으로. Observability 경로는 `clickstack-hyperdx-hols` → `usecase/timeseries-promql-oss`
> - `usecase/ch-geo-analytics` README의 `local/pg-clickhouse-lab` 언급과 `device-360` 내부 문서의 `cd workshop/device-360`도 수정
> - STATUS.md에 §6.3 tfplan 항목 추가

```bash
cd ~/Documents/GitHub/clickhouse-hols
git switch -c repo-split origin/main
```

1. **삭제** — 옮겨 나가는 경로 전부:
   ```bash
   git rm -r -q managed-postgres local/pg-clickhouse-lab \
     chc/tool/ch2otel workshop/o11y-vector-ai workshop/observability-waf \
     usecase/langfuse-ee usecase/langfuse-eval \
     chc/kafka chc/lake chc/s3 tpcds
   ```
2. **레포 안 이동:**
   ```bash
   git mv workshop/device-360 usecase/device-360
   ```
   `.gitignore`에서 `workshop/observability-waf/artifact.md` 행을 삭제합니다.
3. **`MOVED.md`** (루트, 신규):
   ```markdown
   | Old path | New location |
   |---|---|
   | `managed-postgres` | https://github.com/litkhai/clickhouse-managed-postgres-hols |
   | `managed-postgres/provisioning` | https://github.com/litkhai/clickhouse-managed-postgres-hols/tree/main/managed-postgres/provisioning |
   | `local/pg-clickhouse-lab` | https://github.com/litkhai/clickhouse-managed-postgres-hols/tree/main/extensions/pg-clickhouse-lab |
   | `chc/tool/ch2otel` | https://github.com/litkhai/clickstack-hyperdx-hols/tree/main/labs/ch2otel |
   | `workshop/o11y-vector-ai` | https://github.com/litkhai/clickstack-hyperdx-hols/tree/main/workshops/o11y-vector-ai |
   | … (§3.1 전부) |
   | `workshop/device-360` | `usecase/device-360` |
   ```
   새 위치가 http이면 레포 밖, 상대 경로이면 레포 안 이동입니다.
4. **stub 생성** — `MOVED.md`를 읽어서 옛 경로마다 `README.md`를 만듭니다 (D6). 템플릿:
   ```markdown
   # <lab> — moved

   [English](#english) | [한국어](#한국어)

   ## English
   This lab now lives at **<new location>**.
   The last version in this repository: https://github.com/litkhai/clickhouse-hols/tree/pre-split-2026-10/<old>
   This pointer will be removed after 2027-03-31.

   ---
   ## 한국어
   이 실습은 **<new location>**으로 옮겼습니다.
   이 저장소의 마지막 버전: https://github.com/litkhai/clickhouse-hols/tree/pre-split-2026-10/<old>
   이 안내는 2027-03-31 이후 삭제됩니다.
   ```
   레포 안 이동의 경우 `<new location>`을 상대 링크로 씁니다. `links` job이 이 링크를 검증합니다.
5. **`build_site.py` 수정:**
   - `parse_moved(root / "MOVED.md")` → `[(old, target)]`
   - 각 항목마다 `files["labs/<old>/index.html"] = redirect_page(target)`를 만듭니다.
     - 레포 밖: target URL 그대로
     - 레포 안: `SITE + "/labs/<new>/"`
     - `<meta http-equiv="refresh" content="0; url=…">`, `<link rel="canonical">`,
       `<meta name="robots" content="noindex">`, 그리고 이중 언어로 된 눈에 보이는 링크를 넣습니다.
   - `sitemap()`에서는 제외합니다.
   - `assert old not in has_page`: stub 경로가 실제 페이지와 겹치면 빌드를 실패시킵니다.
   - 기존에 페이지가 없던 영역 폴더(`managed-postgres` 등)는 redirect를 생략합니다.
6. **루트 `README.md` (EN, KO 둘 다):**
   - 구조 트리: `managed-postgres/`, `tpcds/`, `workshop/` 제거
   - 영역 표:
     - 🐘 Managed Postgres, 📊 Benchmark, 🎓 Workshops 섹션 삭제
     - ☁️ 표에서 kafka/lake/s3 7행과 ch2otel 행 삭제
     - 🏠 표에서 `pg-clickhouse-lab` 행 삭제 (`pg-analytics`는 유지)
     - 🧪 표에서 langfuse 2행 삭제, `device-360` 추가
   - **🔗 Related repositories / 관련 저장소** 섹션 추가 (6행: 새 레포 4개, `tpcds-scripts`, `lightweight-workshop-*`). http 행만 넣으므로 `is_catalogue`에 걸려 사이트 파서가 건너뜁니다. EN과 KO 양쪽에 모두 넣어야 섹션 수 assert가 맞습니다.
   - 학습 경로:
     - Beginner의 `tpcds` → `workload/replacingmergetree` 등 코어 실습
     - Cloud → `chc/api/chc-api-test` → `chc/clickpipes-s3` → `chc/mysql-interface`
     - Advanced의 `chc/kafka/…` → `workload/kafka-partitioning-ingestion`
     - Postgres → `local/pg-analytics` + 관련 저장소 링크
     - **Observability** 경로 신설 → `clickstack-hyperdx-hols` 링크
   - 전제조건 표: "Cloud labs: Terraform, AWS CLI" 행 → `clickpipes-s3`만 해당한다고 명시하고, 나머지는 관련 저장소로 안내
7. **`.gitleaks.toml`**: langfuse allowlist 제거. `clickhouse-managed-postgres-host` 규칙은 유지(여전히 유용).
8. **`.gitattributes`** (신규, 동작 영향 없음 — CRLF 파일 5개 중 3개는 나가는 `tpcds/sql/*`이고, 남는 `local/pg-analytics/results/sf10/*.csv` 2개는 제외 규칙 추가):
   ```
   * text=auto
   *.sh text eol=lf
   *.py text eol=lf
   *.sql text eol=lf
   local/pg-analytics/results/** -text
   ```
   추가 후 `git add --renormalize . && git status`로 변경이 0건인지 확인합니다.
9. **`AGENTS.md`**: "Moving a lab out" 절 추가 (`MOVED.md` 행, stub, redirect, 영문·한글 표). 관련 저장소 지도.
10. **`STATUS.md`**: 인벤토리 표, 단일 언어 수(18), 레포 지도, §6.3 tfplan 항목.
11. **사이트 재생성과 검사:**
    ```bash
    python3 .github/scripts/build_site.py
    python3 .github/scripts/check_links.py
    ./.github/scripts/check_syntax.sh
    python3 .github/scripts/build_site.py --check
    gitleaks detect --config .gitleaks.toml --log-opts="origin/main..HEAD" --no-banner --redact
    ```
12. PR 열기 → CI green → **머지** (squash보다 merge commit 권장: 되돌리기가 한 번에 됨)

### 5.5 전환 (머지 직후)

- [x] 새 레포 4개를 public으로 전환: `gh repo edit litkhai/<r> --visibility public --accept-visibility-change-consequences`
- [x] 전환 직후 secret scanning + push protection 켜기 (4개 모두 enabled 확인): `gh api -X PATCH repos/litkhai/<r>` 에 `security_and_analysis.secret_scanning(_push_protection).status=enabled`
- [x] D2: `clickhouse-cloud-aws-hols`는 archive하지 않음. 실습 README 7개 맨 위에 검증 시점 배너가 보이는지 확인
- [x] 코어 레포 description 갱신 (현재 "19 per-release labs (25.1 → 26.7)"로 낡아 있음)
- [x] 레포 topics 설정 (코어의 기존 관례 `hands-on-lab`, `korean`에 맞춤) (`clickhouse`, `hands-on-labs`, `managed-postgres`, `clickstack`, `hyperdx`, `opentelemetry`, `langfuse` …)
- [x] `lightweight-workshop-ny-citi-bike`의 `managed-postgres/postgis-fdw-bike` 링크 → 새 레포 (`workshop/08-wrap-up.md`, `64dc86d`)
- [x] `llmops-in-a-box` README에 Related repositories 추가 (`b185d43`). `lightweight-workshop-llmops-in-a-box`의 `usecase/langfuse-eval` 언급도 새 레포 링크로 (`440827c`)
- [x] Claude memory 갱신 (langfuse 경로)
- [x] ~~동결 해제 공지~~ (혼자 쓰는 레포라 해당 없음)

---

## 6. 검증 체크리스트

### 6.1 자동

| 대상 | 명령 | 기대 |
|---|---|---|
| 코어 | `check_links.py`, `check_syntax.sh`, `build_site.py --check`, gitleaks | 전부 OK |
| 코어 사이트 | `find docs/labs -name index.html \| wc -l` | 38 + 21 + 19 = 78 (영역 폴더 redirect를 생략하면 그만큼 적음) |
| 새 레포 4개 | Actions `checks` | green |
| `clickhouse-cloud-aws-hols` | `git log --all --name-only \| grep -E 'tfplan\|tfstate'` | 0건 |
| `clickstack-hyperdx-hols` | `git log --all --name-only \| grep 'o11y-vector-ai.backup'` | 0건 |

### 6.2 수동 (머지 후)

- [x] `https://litkhai.github.io/clickhouse-hols/labs/usecase/langfuse-ee/` → 새 레포로 이동됨
- [x] `https://litkhai.github.io/clickhouse-hols/labs/workshop/o11y-vector-ai/` → `clickstack-hyperdx-hols`로 이동됨
- [x] `https://litkhai.github.io/clickhouse-hols/labs/workshop/device-360/` → `labs/usecase/device-360/`로 이동됨
- [x] `https://github.com/litkhai/clickhouse-hols/tree/main/managed-postgres/postgis-fdw-bike` → stub이 보임
- [x] `https://github.com/litkhai/clickhouse-hols/tree/pre-split-2026-10/managed-postgres/postgis-fdw-bike` → 원본이 보임
- [ ] 새 레포 README 표의 모든 실습 링크 클릭 확인

### 6.3 따로 결정할 보안 항목 (D8)

`origin/main` 공개 히스토리에 **실제 AWS state가 담긴 `tfplan`이 남아 있습니다.**
- 추가: `e0042aa`
- 이동: `5f95b01`
- 추적 해제: `a9ebaf1`

추적만 해제했을 뿐 히스토리에서는 지우지 않았습니다. `STATUS.md`의 "19 findings, none exploitable"은 gitleaks 기준이라, 계정 ID나 role ARN은 잡히지 않은 것으로 보입니다.

- 이번 분리에서는 새 레포로 **옮기지 않습니다** (§5.1-D 2차 filter).
- 코어 히스토리 재작성은 별도로 결정합니다 (D8). 최소한 다음은 합니다.
  1. `git show e0042aa --stat`으로 내용을 확인합니다.
  2. 노출된 버킷, role, 계정이 아직 쓰이는지 확인합니다.
  3. 쓰이고 있으면 교체합니다.
  4. 결과를 `STATUS.md`에 기록합니다.

---

## 7. 롤백

| 시점 | 방법 |
|---|---|
| 5.3 이전 | 스크래치 디렉터리 삭제. 영향 없음 |
| 5.4 머지 전 | PR 닫기. 새 레포는 비공개 상태이므로 삭제하거나 보류 |
| 5.4 머지 후 | `git revert -m 1 <merge-sha>` 한 번으로 코어 복원(사이트 포함). 새 레포는 비공개로 되돌림 |
| 공개 후 | 코어 revert. 새 레포는 archive하고 README 첫 줄에 "clickhouse-hols로 돌아감" 표시 |

`pre-split-2026-10` 태그는 어떤 경우에도 지우지 않습니다.

---

## 8. 롤아웃 이후 트랙 (재검증이 필요하므로 롤아웃과 분리)

각 트랙은 독립 PR로 진행하고, 실제로 실행해 본 것만 검증 문구로 남깁니다.

| 트랙 | 레포 | 내용 | 선행 조건 |
|---|---|---|---|
| **B. 크로스플랫폼 OSS** | 코어 | `local/oss-mac-setup` → `local/oss-docker`로 이름 변경 (release 21개와 `timeseries-promql-oss`, `replacingmergetree`, `llm-mac`의 참조 갱신). `brew`, `sed -i ''` 6곳 제거. Windows(Docker Desktop, WSL 없이)와 Linux에서 실행 확인 | 없음 |
| **C. `lab.yaml`과 공통 러너** | 코어 → 이후 전 레포 | 대상(oss/cloud), tier(T0–T3), 최소 버전, 필요 서비스, `verified_on`. HTTP 인터페이스 기반 러너 `hol up/run/down`. `build_site.py`가 README 표 대신 manifest를 읽게 전환 검토 | B |
| **D. CI 스모크 테스트** | 코어 | T0 실습을 ClickHouse 컨테이너에서 작은 규모로 매일 실행. release 실습은 해당 버전 이미지로 | C |
| **E. CHC 자동 프로비저닝** | 코어 | costkeeper와 clickpipes-s3의 API 호출 코드를 공통 모듈로 추출. 서비스 생성 → IP 허용 → `.env` → 실행 → 삭제. TTL 태그, 최소 권한 키 | C |
| **F. ClickStack 기반 다지기** | `clickstack-hyperdx-hols` | 아래 §8.1 | B (러너 패턴 공유) |
| **G. Langfuse on ClickHouse** | 코어 `usecase/` | `langfuse-hols`의 ee 01–04 SQL과 eval 07을 **복사해 오고**, Langfuse 스키마의 Parquet 스냅샷을 추가해서 Langfuse 없이 도는 T0로 만듦. `clickstack-hyperdx-hols`와 서로 링크 | 없음 |
| **H. LibreChat 이동 (D4)** | 코어 → `llmops-in-a-box` | `mcp-server-clickhouse` vendoring, ClickHouse를 공식 이미지로 교체 → 재실행 → `examples/` | B |
| **I. 번역 backlog** | 각 레포 | 코어 단일 언어 18개를 의도적으로 번역(AGENTS.md). `clickstack-hyperdx-hols`의 워크숍 2개도 포함 | 없음 |
| **J. stub 제거** | 코어 | 2027-03-31에 stub 디렉터리 삭제, `MOVED.md`와 redirect는 유지 | 날짜 |
| **K. AWS 실습 재검증 (D2)** | `clickhouse-cloud-aws-hols` | 실습을 실제로 `apply`→`destroy`까지 돌릴 때마다 배너 날짜와 "바뀐 것" 줄 갱신. provider `~> 5.0` → 현행 메이저 올리기는 이 트랙에서, 재실행과 함께만. `direct-attach`는 CHC에서 실패가 알려져 있으므로 OSS/동일 계정 경로로만 재검증하거나 배너에 실패를 유지 | 없음 |

### 8.1 `clickstack-hyperdx-hols` 로드맵 (트랙 F)

롤아웃 직후 이 레포에는 `labs/ch2otel`과 `workshops/` 2개만 있습니다. 순서는 **공통 환경 → 기초 → 심화 → 워크숍 축약**을 권합니다. 아래 슬롯은 제안이므로 README 로드맵 표에 "planned"로 두고 채워 나가면 됩니다.

| 순서 | 경로 | 내용 | 대상 |
|---|---|---|---|
| F0 | `_base/` | ClickStack all-in-one compose(Win/Mac/Linux), Cloud 연결 `.env.example`, 수집 확인 SQL | oss / cloud |
| F1 | `labs/otel-schema` | `otel_logs`, `otel_traces`, `otel_metrics_*` 구조, 정렬 키, 속성 Map/JSON | oss / cloud |
| F2 | `labs/ingestion` | OTel Collector ClickHouse exporter, 배치·async insert, 샘플링 | oss / cloud |
| F3 | `labs/hyperdx-sources` | Log/Trace/Metric source 설정, SpanKind 등 필수 매핑 (지금 `o11y-vector-ai`의 `HYPERDX_UI_SETUP.md`에서 수작업인 부분). API나 기본 구성으로 자동화할 수 있는지 확인 필요 | oss |
| F4 | `labs/schema-tuning` | 코덱, TTL, skip index, 속성 materialize, 비용·용량 | oss / cloud |
| F5 | `labs/dashboards-alerts` | 대시보드, 알림, 검색 문법 | oss / cloud |
| F6 | `labs/ch2otel` | (기존) ClickHouse 자체 관측 — ClickHouse가 ClickHouse를 봄 | cloud |
| F7 | `labs/clickstack-cloud` | ClickHouse Cloud의 관리형 ClickStack/HyperDX | cloud |
| F8 | `workshops/*` | 기존 2개를 `_base` 위에서 도는 시나리오로 축약. 원본은 태그로 보존 | oss / cloud |

**이 레포의 규칙 제안** (새 `AGENTS.md`에 적을 것):
- 버전 기록은 ClickHouse 버전과 ClickStack/HyperDX 버전을 둘 다 적습니다.
- CI 검증은 UI가 아니라 SQL로 합니다. 예: `otel_traces`의 행 수, 서비스별 span 수.
- 실습이 약 10개로 늘어나기 전에 Pages 사이트를 켭니다(D7). `build_site.py`를 일반화해서 재사용하는 방법이 있습니다.
