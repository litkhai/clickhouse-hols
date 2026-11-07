# AI runs — summary

[English](#english) | [한국어](#한국어)

## English

`ai_prompts.sh`, 2026-11-07: Claude Code 2.1.220 in print mode (`--model sonnet`; the session reported
`claude-sonnet-5`), mcp-clickhouse 0.7.0 over stdio as `ai_reader`, ClickHouse 26.10.3.7. "rules" =
system prompt plus [project-prompt.md](project-prompt.md); "bare" = one line saying it is a data
assistant connected to `fileidx`. Built-in tools were denied by name, so the only tools were the three MCP ones
(plus Claude Code's own `ToolSearch`, which loads their schemas). Every number below was checked
against an admin query on the same view ([sql/07-ground-truth.sql](sql/07-ground-truth.sql) →
`results/09-ground-truth.txt`). These ten runs cost $1.54 (the sum of `total_cost_usd` Claude Code reports, list-price equivalent); two earlier attempts that answered before the MCP server connected and two connection tests are not counted.

| Run | Context | MCP calls | Answer vs ground truth |
|---|---|---:|---|
| `p1-capacity` | rules | 2 | Correct: the top 20 are all `archive/images/*.iso`, 142,807,662,592 bytes |
| `p2-duplicates` | rules | 2 | Correct: 63 groups, 574 files, 214,320,666 bytes wasted; `content_hash != ''` applied |
| `p3-types` | rules | 2 | Counts correct (15 extensions, so "top 30" has 15). **mp4 shown as 559.35 GiB; it is 559.32 GiB**: the model converted `sum(size)` to GiB itself instead of using `formatReadableSize()` (rule 3) |
| `p4-contracts` | rules | 1 | Correct: 30 newest of the 60 matching pdf/docx/hwp files; `service_agreement_*` correctly left out |
| `p5-trend` | rules | 2 | Correct: 2025-03 has 194 files, 153 of them mp4, 217.85 GiB |
| `p6-anomalies` | rules | 3 | Correct: 25 without extension, 60 empty, 45 temp files |
| `c1-list-all` | bare | 6 | **Wrong conclusion.** It sampled `ORDER BY path LIMIT 200`, saw only `backup/*.zip`, and wrote that the archive root is "almost entirely `backup_NNN.zip`, `backup_000.zip` … `backup_17724.zip`". The archive root has 200 zip files out of 17,725 |
| `r1-list-all` | rules | 1 | Same request with the rules: one `GROUP BY root` aggregate, said why it would not list 21,028 rows |
| `c2-duplicates` | bare | 4 | Correct without the rules: it filtered `content_hash != ''` and `size > 0` by itself (62 groups; the empty-file group is the 63rd). Paths were shown without `root` |
| `c3-no-limit` | bare | 2 | **Wrong SQL, caught by the server**: `SELECT root, path FROM fileidx.files` with no `LIMIT` → `TOO_MANY_ROWS_OR_BYTES` (396) from the user's `max_result_rows = 20000`. It then counted the rows (21,028), read "21.03 thousand" in the error as 21,030 and called the gap a timing difference, and offered to fetch everything in two pages with `LIMIT`/`OFFSET` |

What catches what:

- **Grants and user settings** stopped the unbounded `SELECT` (c3). They do not stop paging around the
  limit with `OFFSET`: `max_result_rows` is per query.
- **The rules** turned "list everything" into one aggregate (r1 vs c1). Without them the model sampled
  and generalised from the sample. Nothing on the server can catch a wrong sentence built on correct rows.
- **`content_hash = ''`** is the anti-pattern the rules warn about. Grouping the empty hashes as one
  group would report 33.62 GiB wasted instead of 204 MiB (`results/09-ground-truth.txt`). The model avoided
  it here with and without the rules, so this run does not show the rule changing the result.
- **The audit query** (`system.query_log`, `user = 'ai_reader'`) holds every SQL the model sent, but also
  the clients' own queries (`SELECT version(), timezone()`, `system.settings`, `SELECT 1 AS check`, metadata)
  — `results/10-audit.txt`. Filter on `query LIKE '%fileidx.files%'` or similar to see the model's queries.

## 한국어

`ai_prompts.sh`, 2026-11-07: Claude Code 2.1.220 print 모드(`--model sonnet`, 세션이 보고한 모델
`claude-sonnet-5`), mcp-clickhouse 0.7.0(stdio, `ai_reader`), ClickHouse 26.10.3.7. "rules" = 시스템
프롬프트 + [project-prompt.md](project-prompt.md), "bare" = `fileidx`에 연결된 데이터 도우미라는 한 줄.
내장 도구는 이름으로 막아 도구는 MCP 세 개뿐이었습니다(그 스키마를 불러오는 Claude Code 자체 `ToolSearch` 제외).
아래 수치는 모두 같은 뷰에 대한 관리자 쿼리로 확인했습니다([sql/07-ground-truth.sql](sql/07-ground-truth.sql) →
`results/09-ground-truth.txt`). 이 10회 실행 비용은 $1.54(Claude Code가 보고한 `total_cost_usd` 합계, 정가 환산)이고, MCP 서버가 붙기 전에 답한 앞선 시도 두 번과 연결 시험 두 번은 넣지 않았습니다.

| 실행 | 맥락 | MCP 호출 | 답과 실제 |
|---|---|---:|---|
| `p1-capacity` | rules | 2 | 맞음: 상위 20개 모두 `archive/images/*.iso`, 142,807,662,592바이트 |
| `p2-duplicates` | rules | 2 | 맞음: 63묶음, 574파일, 낭비 214,320,666바이트. `content_hash != ''` 적용 |
| `p3-types` | rules | 2 | 개수는 맞음(확장자가 15종이라 "상위 30"은 15개). **mp4를 559.35 GiB로 적었으나 실제 559.32 GiB**: `formatReadableSize()`(규칙 3) 대신 `sum(size)`를 모델이 직접 GiB로 바꿈 |
| `p4-contracts` | rules | 1 | 맞음: 조건에 맞는 pdf/docx/hwp 60개 중 최신 30개. `service_agreement_*`는 제대로 뺌 |
| `p5-trend` | rules | 2 | 맞음: 2025-03은 194개, 그중 mp4 153개, 217.85 GiB |
| `p6-anomalies` | rules | 3 | 맞음: 확장자 없음 25, 빈 파일 60, 임시 파일 45 |
| `c1-list-all` | bare | 6 | **틀린 결론.** `ORDER BY path LIMIT 200`으로 표본을 뽑아 `backup/*.zip`만 보고 archive 루트가 "거의 전부 `backup_NNN.zip`, `backup_000.zip` … `backup_17724.zip`"라고 씀. 실제 archive 루트 17,725개 중 zip은 200개 |
| `r1-list-all` | rules | 1 | 같은 요청에 규칙을 주면: `GROUP BY root` 집계 하나, 21,028행을 나열하지 않는 이유를 밝힘 |
| `c2-duplicates` | bare | 4 | 규칙 없이도 맞음: `content_hash != ''`와 `size > 0`을 스스로 걸었음(62묶음, 빈 파일 묶음이 63번째). 경로에 `root`를 붙이지 않음 |
| `c3-no-limit` | bare | 2 | **틀린 SQL을 서버가 막음**: `LIMIT` 없는 `SELECT root, path FROM fileidx.files` → 사용자 `max_result_rows = 20000`의 `TOO_MANY_ROWS_OR_BYTES`(396). 그 뒤 행 수(21,028)를 세고, 오류의 "21.03 thousand"를 21,030으로 읽어 차이를 조회 시점 탓으로 돌렸고, `LIMIT`/`OFFSET` 두 번으로 전부 가져오겠다고 제안함 |

무엇이 무엇을 막았나:

- **권한과 사용자 설정**이 상한 없는 `SELECT`를 막았습니다(c3). `OFFSET`으로 나눠 가져오는 것은 막지
  않습니다: `max_result_rows`는 쿼리 하나 단위입니다.
- **규칙**이 "전부 뽑아줘"를 집계 하나로 바꿨습니다(r1 대 c1). 규칙이 없으면 모델은 표본을 뽑아 일반화했습니다.
  맞는 행 위에 쓴 틀린 문장은 서버가 잡을 수 없습니다.
- **`content_hash = ''`**는 규칙이 경고하는 안티패턴입니다. 빈 해시를 한 묶음으로 세면 낭비가 204 MiB가 아니라
  33.62 GiB로 나옵니다(`results/09-ground-truth.txt`). 이번 실행에서는 모델이 규칙이 있든 없든 피했으므로,
  규칙이 결과를 바꾼 사례는 아닙니다.
- **감사 쿼리**(`system.query_log`, `user = 'ai_reader'`)에는 모델이 보낸 SQL이 모두 있지만, 클라이언트 자신의
  쿼리(`SELECT version(), timezone()`, `system.settings`, `SELECT 1 AS check`, 메타데이터)도 섞입니다 —
  `results/10-audit.txt`. 모델의 쿼리만 보려면 `query LIKE '%fileidx.files%'` 같은 조건을 더합니다.
