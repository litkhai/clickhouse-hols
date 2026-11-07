# File index in ClickHouse, queried read-only by an AI through mcp-clickhouse

[English](#english) | [한국어](#한국어)

---

## English

A batch job walks a file tree and writes one row per file (name, size, type, mtime, hash, optional
text) into ClickHouse. An AI assistant answers questions about that tree through
[mcp-clickhouse](https://github.com/ClickHouse/mcp-clickhouse), signed in as a user that can only read
one view. The design follows a common how-to for this pattern: a `ReplacingMergeTree` keyed on
`(root, path)`, a view with `FINAL` that hides deleted rows, delete detection after a full scan, a
`readonly` user granted the view only, and a project prompt with query rules. This lab runs each piece of it and
records where it holds and where it does not.

**Verified on ClickHouse 26.10.3.7** (`clickhouse/clickhouse-server:26.10.3.7`), 2026-11-07, `run.sh`
steps 00–08, with mcp-clickhouse 0.7.0 over stdio, clickhouse-connect 1.12.0, the `mcp` Python SDK 2.3.0
as a client, and `ai_prompts.sh` with Claude Code 2.1.220 in print mode (model alias `sonnet`).
Machine: Docker Desktop on macOS, 12 CPUs, 8 GB; the container was capped at 3 GB, and other labs'
containers were running at the same time, so timings are indicative only.
The file tree is synthetic (`gen_tree.py`, seed 42): 21,033 files, 892.6 GB logical size in
sparse files, 360 MB on disk. No real files were indexed.

### Results

| What was checked | Result (26.10.3.7, mcp-clickhouse 0.7.0) |
|---|---|
| The view as usually written (`CREATE VIEW … AS SELECT … FINAL`) + `GRANT SELECT ON fileidx.files` only | **`ACCESS_DENIED`** for the reader: `default_normal_view_sql_security = INVOKER`, so the reader also needs `SELECT` on the base table |
| Same view with `DEFINER = fileidx_view_owner SQL SECURITY DEFINER` (owner: `HOST NONE`, `SELECT` on the base table only) | Reader reads the view; reading the base table directly is still `ACCESS_DENIED` |
| Cost of the DEFINER view | A primary-key lookup read **25,691 rows** through the view, 4,650 on the base table with `FINAL`. `EXPLAIN` shows `ReadFromSealedView` with the filter above it: the predicate is not pushed into the view |
| No-view alternative: `ReplacingMergeTree(indexed_at, is_deleted)`, column grants, user setting `final = 1` | Same 21,028 visible rows, **4,651 rows** read for the lookup; `SETTINGS final = 0` refused (`READONLY`), an ungranted column refused |
| Same full scan run twice | Base table 42,066 rows, view 21,033. The usual "duplicates in the base table should be 0" check returns **21,033** before merges; the same check through the view returns 0 |
| Incremental scan (`mtime > last scan`) after 5 deletes, 1 rename, 1 edit | Picks up the edit only (1 row). `mv` keeps the mtime, so the renamed file is missing until a full scan |
| Delete-detection SQL after that incremental scan | Would mark **21,032 of 21,033** live files deleted; `indexer.py` refuses `DETECT_DELETES=1` unless `MODE=full` |
| Full scan + delete detection | 6 rows marked (5 deletes + the old path of the rename); view = files on disk = 21,028 |
| Read-only user, `clickhouse-client` | `SELECT` on the view OK; `INSERT`, `DROP TABLE`, `DROP VIEW`, `CREATE TABLE` → `ACCESS_DENIED` (497); `SET max_result_rows = 0` → `READONLY` (164); `SELECT` of every path → `TOO_MANY_ROWS_OR_BYTES` (396) at 20,000; control: the same `INSERT` as `indexer` succeeds |
| Same through mcp-clickhouse | Same errors (12 of 12 probe checks pass). `list_tables fileidx` shows only `files` |
| `readonly = 1` and query `SETTINGS` | Any `SETTINGS` clause is refused, even `log_comment`; `SETTINGS readonly = 1` (the user's own value, which mcp-clickhouse sends) is accepted — checked by hand, `results/05b-settings-clause.txt` |
| The built-in `/play` UI as `ai_reader` | Refused before the query runs: `Cannot modify 'add_http_cors_header' setting in readonly mode` ([images/05-play-readonly-user.png](images/05-play-readonly-user.png)) |
| MCP timeout (`CLICKHOUSE_MCP_QUERY_TIMEOUT=3`, a ~12 s query) | Error after 3.1 s, and the server-side query **was cancelled** (`QUERY_WAS_CANCELLED` after 2,994 ms in `query_log`, via the server's `KILL QUERY`). Control: the same query completes in 11.6 s under the default 30 s |
| Three calls at once on one MCP session | 2.8 s for one, 2.8 s for three: **not serial** (`CLICKHOUSE_MCP_MAX_WORKERS` defaults to 10) |
| Skip indexes (`EXPLAIN indexes = 1`) | `ngrambf_v1` on `name`: used by `LIKE '%contract%'`, **not** by `positionCaseInsensitive` or `multiSearchAnyCaseInsensitive`. `tokenbf_v1` and `text` on `text_excerpt`: used by `hasToken` and `LIKE`, not by `positionCaseInsensitive` |

The AI runs (`ai_prompts.sh`) are in [results/ai/](results/ai/), one markdown transcript per prompt with
every SQL the assistant sent and what came back. See [AI.md](AI.md) for the summary: six prompts with
the rules were answered from aggregates and checked correct except one GiB conversion the model did itself
(559.35 for 559.32); without the rules, one run generalised from a 200-row sample to a wrong statement, and
one sent a `SELECT` with no `LIMIT` that `max_result_rows` stopped.

`images/` holds the `/play` screens taken after the run (admin user except 05): the two `ACCESS_DENIED`
rows of step 01, rows read in step 07, the step 08 timeout and concurrency in `query_log`, the AI's
queries around the refused `SELECT`, and `/play` refusing `ai_reader`.

### Run it

```bash
./run.sh            # container, schema, users, tree, scans, controls, MCP probe → results/00..08
./ai_prompts.sh     # optional: 8 prompts through Claude Code + mcp-clickhouse → results/ai/
./run.sh down       # remove the container and work/
```

`run.sh` needs Docker, Python 3 and [uv](https://docs.astral.sh/uv/). Passwords are random per run and
stay in `work/.lab.env` (gitignored). `ai_prompts.sh` uses your own Claude Code login; each prompt is
capped with `--max-budget-usd` (default 0.50).

### Files

| File | What it does |
|---|---|
| `gen_tree.py` | Synthetic tree: office files, contracts, sparse media/ISO/ZIP, duplicate groups, empty and temp files, a folder with 17,000 photos, a deep path, mtimes 2019–2026 with a spike in 2025-03 |
| `indexer.py` | Full or incremental scan, batched `INSERT`, optional BLAKE2b hash (`HASH_MAX_MB=8`) and text excerpt (`TEXT_MAX_KB=4`, `.txt`/`.md` only), delete detection after a full scan |
| `sql/01-schema.sql` | Database and `ReplacingMergeTree(indexed_at)` table |
| `sql/02-view-invoker.sql` | The view as usually written (fails for a view-only reader on 26.10) |
| `sql/03-users.sql` | `indexer` (`SELECT`, `INSERT` on the table) and `ai_reader` (`readonly = 1`, limits, view only) |
| `sql/04-view-definer.sql` | The fix: a `DEFINER` view owned by a user that cannot log in |
| `sql/05-skip-indexes.sql` | `tokenbf_v1`, `ngrambf_v1` (deprecated in the current docs) and a `text` index |
| `sql/06-no-view.sql` | The no-view alternative |
| `sql/07-ground-truth.sql` | Admin checks of the numbers in the AI answers |
| `mcp_probe.py` | mcp-clickhouse over stdio without an AI: tools, grants, limits, timeout, concurrency |
| `project-prompt.md` | Context and query rules given to the assistant (Korean) |
| `prompts.tsv`, `ai_prompts.sh`, `render_transcript.py` | The prompts, the Claude Code runs, the transcripts |

### Not covered

- ClickHouse Cloud, TLS, and any MCP client other than Claude Code in print mode.
- Real storage (NAS, SMB, cloud mounts), permissions errors while walking, or text extraction from PDF/Office files.
- Directories as rows (`is_dir` is always 0 here, as in the skeleton this lab follows).
- Scale: 21,033 rows fit in three granules, so the skip-index results show which predicates *can* use an index, not how much they save.
- `claude mcp add` was not run (it writes to the user's Claude Code config); the runs pass the same server through `--mcp-config`.

---

## 한국어

배치 작업이 파일 트리를 돌며 파일마다 한 행(이름, 크기, 유형, 수정 시각, 해시, 선택적으로 본문)을
ClickHouse에 씁니다. AI 도우미는 [mcp-clickhouse](https://github.com/ClickHouse/mcp-clickhouse)로
뷰 하나만 읽을 수 있는 사용자로 접속해 그 트리에 대한 질문에 답합니다. 설계는 이 패턴의 흔한
안내를 따릅니다: `(root, path)` 키의 `ReplacingMergeTree`, `FINAL`로 읽고 삭제 행을 숨기는 뷰, 전체
스캔 뒤 삭제 감지, 뷰만 받은 `readonly` 사용자, 질의 규칙을 담은 프로젝트 프롬프트. 이 실습은
그 각각을 실행해 맞는 곳과 맞지 않는 곳을 기록합니다.

**ClickHouse 26.10.3.7**(`clickhouse/clickhouse-server:26.10.3.7`)에서 2026-11-07 `run.sh` 00–08단계로
검증했습니다. mcp-clickhouse 0.7.0(stdio), clickhouse-connect 1.12.0, 클라이언트로 `mcp` Python SDK
2.3.0, `ai_prompts.sh`는 Claude Code 2.1.220 print 모드(모델 별칭 `sonnet`). 장비: macOS Docker Desktop,
CPU 12개, 8 GB. 컨테이너는 3 GB로 제한했고 다른 실습의 컨테이너가 함께 돌고 있어 시간은 참고용입니다.
파일 트리는 합성입니다(`gen_tree.py`, seed 42): 파일 21,033개, sparse 파일로 논리 크기 892.6 GB,
디스크 사용 360 MB. 실제 파일은 색인하지 않았습니다.

### 결과

| 확인한 것 | 결과 (26.10.3.7, mcp-clickhouse 0.7.0) |
|---|---|
| 흔히 쓰는 뷰(`CREATE VIEW … AS SELECT … FINAL`) + `GRANT SELECT ON fileidx.files`만 | 읽는 사용자에게 **`ACCESS_DENIED`**: `default_normal_view_sql_security = INVOKER`라 원본 테이블 `SELECT`도 필요 |
| 같은 뷰를 `DEFINER = fileidx_view_owner SQL SECURITY DEFINER`로(소유자: `HOST NONE`, 원본 `SELECT`만) | 뷰는 읽힘. 원본 테이블 직접 조회는 여전히 `ACCESS_DENIED` |
| DEFINER 뷰의 비용 | 기본 키 조회가 뷰로 **25,691행**, 원본 `FINAL`로 4,650행을 읽음. `EXPLAIN`은 필터가 `ReadFromSealedView` 위에 있음 — 조건이 뷰 안으로 내려가지 않음 |
| 뷰 없는 대안: `ReplacingMergeTree(indexed_at, is_deleted)`, 컬럼 권한, 사용자 설정 `final = 1` | 보이는 행 21,028개로 같음, 조회에 **4,651행**. `SETTINGS final = 0`은 거부(`READONLY`), 권한 없는 컬럼도 거부 |
| 같은 전체 스캔 두 번 | 원본 42,066행, 뷰 21,033행. 흔한 "원본 테이블 중복 0이어야 정상" 검사는 병합 전 **21,033**, 뷰로 같은 검사는 0 |
| 삭제 5 · 이름 변경 1 · 수정 1 뒤 증분 스캔(`mtime > 지난 스캔`) | 수정 1건만 들어옴. `mv`는 mtime을 유지해 바뀐 이름은 전체 스캔 전까지 없음 |
| 그 증분 스캔 뒤의 삭제 감지 SQL | 살아 있는 파일 **21,033개 중 21,032개**를 삭제로 표시했을 것. `indexer.py`는 `MODE=full`이 아니면 `DETECT_DELETES=1`을 거부 |
| 전체 스캔 + 삭제 감지 | 6행 표시(삭제 5 + 이름 바뀐 파일의 옛 경로). 뷰 = 디스크 = 21,028 |
| 읽기 전용 사용자, `clickhouse-client` | 뷰 `SELECT` 성공. `INSERT`, `DROP TABLE`, `DROP VIEW`, `CREATE TABLE` → `ACCESS_DENIED`(497). `SET max_result_rows = 0` → `READONLY`(164). 전체 경로 `SELECT` → 2만 행에서 `TOO_MANY_ROWS_OR_BYTES`(396). 대조: 같은 `INSERT`를 `indexer`로는 성공 |
| mcp-clickhouse로 같은 것 | 같은 오류(프로브 12개 모두 통과). `list_tables fileidx`에는 `files`만 보임 |
| `readonly = 1`과 쿼리 `SETTINGS` | `SETTINGS` 절은 `log_comment`까지 모두 거부. `SETTINGS readonly = 1`(사용자 자신의 값, mcp-clickhouse가 보내는 것)은 받아들여짐 — 손으로 확인, `results/05b-settings-clause.txt` |
| 내장 `/play` UI를 `ai_reader`로 | 쿼리 전에 거부: `Cannot modify 'add_http_cors_header' setting in readonly mode`([images/05-play-readonly-user.png](images/05-play-readonly-user.png)) |
| MCP 시간 제한(`CLICKHOUSE_MCP_QUERY_TIMEOUT=3`, 약 12초 쿼리) | 3.1초에 오류, 서버 쪽 쿼리는 **취소됨**(`query_log`에 2,994 ms 뒤 `QUERY_WAS_CANCELLED`, 서버의 `KILL QUERY`). 대조: 기본 30초에서는 같은 쿼리가 11.6초에 끝남 |
| MCP 세션 하나에 호출 세 개 동시 | 하나 2.8초, 셋 2.8초 — **직렬이 아님**(`CLICKHOUSE_MCP_MAX_WORKERS` 기본 10) |
| skip index(`EXPLAIN indexes = 1`) | `name`의 `ngrambf_v1`: `LIKE '%contract%'`는 사용, `positionCaseInsensitive`·`multiSearchAnyCaseInsensitive`는 **사용 안 함**. `text_excerpt`의 `tokenbf_v1`·`text`: `hasToken`·`LIKE`는 사용, `positionCaseInsensitive`는 사용 안 함 |

AI 실행(`ai_prompts.sh`) 결과는 [results/ai/](results/ai/)에 프롬프트마다 마크다운 기록으로 있습니다.
도우미가 보낸 SQL과 돌아온 결과가 모두 들어 있고, 요약은 [AI.md](AI.md)에 있습니다: 규칙을 준 프롬프트 여섯 개는
집계로 답했고, 모델이 직접 한 GiB 환산 하나(559.32를 559.35로)를 빼면 맞았습니다. 규칙이 없을 때는 한 번은
200행 표본에서 틀린 일반화를 했고, 한 번은 `LIMIT` 없는 `SELECT`를 보냈다가 `max_result_rows`에 막혔습니다.

`images/`에는 실행 뒤 찍은 `/play` 화면이 있습니다(05 말고는 관리자): 01단계의 `ACCESS_DENIED` 두 행,
07단계의 읽은 행 수, 08단계 시간 제한·동시 실행의 `query_log`, 거부된 `SELECT` 앞뒤의 AI 쿼리,
`ai_reader`를 거부하는 `/play`.

### 실행

```bash
./run.sh            # 컨테이너, 스키마, 사용자, 트리, 스캔, 대조, MCP 프로브 → results/00..08
./ai_prompts.sh     # 선택: Claude Code + mcp-clickhouse로 프롬프트 8개 → results/ai/
./run.sh down       # 컨테이너와 work/ 삭제
```

`run.sh`에는 Docker, Python 3, [uv](https://docs.astral.sh/uv/)가 필요합니다. 비밀번호는 실행마다 무작위로
만들어 `work/.lab.env`(gitignore)에만 둡니다. `ai_prompts.sh`는 각자의 Claude Code 로그인을 쓰고, 프롬프트마다
`--max-budget-usd`(기본 0.50)로 상한을 둡니다.

### 파일

| 파일 | 하는 일 |
|---|---|
| `gen_tree.py` | 합성 트리: 사무 문서, 계약서, sparse 미디어·ISO·ZIP, 중복 묶음, 빈 파일·임시 파일, 사진 17,000장 폴더, 깊은 경로, 2019–2026 수정 시각과 2025-03의 급증 |
| `indexer.py` | 전체·증분 스캔, 묶음 `INSERT`, 선택적 BLAKE2b 해시(`HASH_MAX_MB=8`)와 본문 앞부분(`TEXT_MAX_KB=4`, `.txt`/`.md`만), 전체 스캔 뒤 삭제 감지 |
| `sql/01-schema.sql` | 데이터베이스와 `ReplacingMergeTree(indexed_at)` 테이블 |
| `sql/02-view-invoker.sql` | 흔히 쓰는 뷰(26.10에서 뷰만 받은 사용자는 못 읽음) |
| `sql/03-users.sql` | `indexer`(테이블 `SELECT`·`INSERT`)와 `ai_reader`(`readonly = 1`, 상한, 뷰만) |
| `sql/04-view-definer.sql` | 고친 것: 로그인할 수 없는 사용자가 소유한 `DEFINER` 뷰 |
| `sql/05-skip-indexes.sql` | `tokenbf_v1`, `ngrambf_v1`(현재 문서에서 deprecated)과 `text` 인덱스 |
| `sql/06-no-view.sql` | 뷰 없는 대안 |
| `sql/07-ground-truth.sql` | AI 답의 수치를 관리자로 확인 |
| `mcp_probe.py` | AI 없이 stdio로 mcp-clickhouse 확인: 도구, 권한, 상한, 시간 제한, 동시 실행 |
| `project-prompt.md` | 도우미에게 주는 맥락과 질의 규칙(한국어) |
| `prompts.tsv`, `ai_prompts.sh`, `render_transcript.py` | 프롬프트, Claude Code 실행, 기록 |

### 다루지 않은 것

- ClickHouse Cloud, TLS, Claude Code print 모드 외의 MCP 클라이언트.
- 실제 스토리지(NAS, SMB, 클라우드 마운트), 순회 중 권한 오류, PDF·Office 본문 추출.
- 디렉터리 행(`is_dir`는 이 실습이 따르는 골격처럼 항상 0).
- 규모: 21,033행은 granule 세 개라 skip index 결과는 어떤 조건이 인덱스를 *쓸 수 있는지*만 보여 주고 얼마나 줄이는지는 아님.
- `claude mcp add`는 실행하지 않음(사용자의 Claude Code 설정에 씀). 실행은 같은 서버를 `--mcp-config`로 넘김.
