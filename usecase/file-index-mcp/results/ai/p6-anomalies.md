## p6-anomalies (rules)

> 확장자가 없는 파일, 크기가 0인 파일, 임시 파일(~$, .tmp, .part)이 얼마나 되는지 정리해줘.

model `claude-sonnet-5` · Claude Code 2.1.220 · 5 turns · 25.5 s · $0.1459 · success

### call 1: `ToolSearch` (Claude Code, not MCP)

`{"query": "fileidx query files", "max_results": 10}`

### call 2: `run_query` → ok

```sql
SELECT
  count() AS total_files,
  countIf(ext = '') AS no_ext_cnt,
  sumIf(size, ext = '') AS no_ext_size,
  countIf(size = 0) AS zero_size_cnt,
  countIf(positionCaseInsensitive(name, '~$') > 0 OR ext = 'tmp' OR ext = 'part') AS temp_cnt,
  sumIf(size, positionCaseInsensitive(name, '~$') > 0 OR ext = 'tmp' OR ext = 'part') AS temp_size
FROM fileidx.files
```

```text
{"result":"{\"columns\": [\"total_files\", \"no_ext_cnt\", \"no_ext_size\", \"zero_size_cnt\", \"temp_cnt\", \"temp_size\"], \"rows\": [[21028, 25, 2500, 60, 45, 1240089850]]}"}
```

### call 3: `run_query` → ok

```sql
SELECT
  countIf(positionCaseInsensitive(name, '~$') > 0) AS tilde_cnt,
  sumIf(size, positionCaseInsensitive(name, '~$') > 0) AS tilde_size,
  countIf(ext = 'tmp') AS tmp_cnt,
  sumIf(size, ext = 'tmp') AS tmp_size,
  countIf(ext = 'part') AS part_cnt,
  sumIf(size, ext = 'part') AS part_size
FROM fileidx.files
```

```text
{"result":"{\"columns\": [\"tilde_cnt\", \"tilde_size\", \"tmp_cnt\", \"tmp_size\", \"part_cnt\", \"part_size\"], \"rows\": [[15, 404591911, 15, 388854090, 15, 446643849]]}"}
```

### call 4: `run_query` → ok

```sql
SELECT
  root,
  countIf(ext = '') AS no_ext_cnt,
  countIf(size = 0) AS zero_size_cnt,
  countIf(positionCaseInsensitive(name, '~$') > 0 OR ext IN ('tmp','part')) AS temp_cnt
FROM fileidx.files
GROUP BY root
HAVING no_ext_cnt > 0 OR zero_size_cnt > 0 OR temp_cnt > 0
ORDER BY (no_ext_cnt + zero_size_cnt + temp_cnt) DESC
LIMIT 50
```

```text
{"result":"{\"columns\": [\"root\", \"no_ext_cnt\", \"zero_size_cnt\", \"temp_cnt\"], \"rows\": [[\"docs\", 0, 60, 45], [\"archive\", 25, 0, 0]]}"}
```

### answer

## 이상 파일 점검 결과 (`fileidx.files` 기준)

| 구분 | 조건 | 건수 | 총 용량 |
|---|---|---|---|
| 확장자 없음 | `ext = ''` | 25건 | 약 2.4 KB |
| 크기 0 | `size = 0` | 60건 | 0 B |
| 임시 파일 (`~$`) | `name`에 `~$` 포함 | 15건 | 약 385.9 MB |
| 임시 파일 (`.tmp`) | `ext = 'tmp'` | 15건 | 약 370.9 MB |
| 임시 파일 (`.part`) | `ext = 'part'` | 15건 | 약 425.9 MB |
| **임시 파일 합계** | 위 세 패턴 합 | **45건** | **약 1.15 GB** |

전체 색인 파일 수: 21,028건 (`SELECT count() FROM fileidx.files`)

**root별 분포** (0건 초과만):
- `archive`: 확장자 없는 파일 25건 전부 — 평균 100바이트 수준, 용량 낭비는 미미
- `docs`: 크기 0 파일 60건 + 임시 파일 45건 전부 — 임시 파일이 약 1.15GB를 차지해 `docs` root가 정리 우선순위

**근거 쿼리**
1. `countIf/sumIf(ext='', size=0, name LIKE '~$%' OR ext IN ('tmp','part'))` 집계 쿼리 (전체)
2. `~$`, `tmp`, `part` 패턴별 개별 countIf/sumIf
3. root별 GROUP BY로 분포 확인

**참고**: `content_hash`가 빈 문자열인 8MiB 초과 파일은 이번 집계에 영향 없음(크기·확장자·파일명 조건만 사용했으므로). 크기 0인 60건과 임시파일 45건이 모두 `docs` root에 몰려 있어, 정리 시 `docs`부터 보는 게 효율적입니다.

