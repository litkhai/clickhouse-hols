# ClickHouse 26.8 LTS

[English](#english) | [한국어](#한국어)

---

## English

**Released 2026-08-30 · LTS · verified here against 26.8.2.7**

26.8 is an LTS release and a large one — the changelog runs to 21 backward
incompatible changes, 46 new features and 89 performance improvements. This lab
takes three of them that you can see working in a single container, and that
change how you write queries rather than how fast they run, and adds AI functions
that also need an Anthropic API key (not run by `tools/hol`).

| Lab | Feature | Why it is here |
|-----|---------|----------------|
| [01](01-pipe-operators.sql) | Pipe operators `\|>` | The biggest syntax change in years. Queries read in the order data flows |
| [02](02-groups-window-frame.sql) | `GROUPS` window frame mode | The third frame mode SQL defines, and the one ClickHouse was missing |
| [03](03-cjk-tokenizers.sql) | `japanese`, `chinese`, `icu` tokenizers | The difference between a working Korean text index and a useless one |
| [AI](ai-functions.sql) | `aiFilter`, `aiRedact` (Beta) | An LLM call inside a `WHERE` — what it returns, what it costs, and the per-query limit that stops it. Needs an Anthropic key |

### Quick start

```bash
./00-setup.sh              # brings up ClickHouse 26.8 via local/oss-docker
./01-pipe-operators.sh
./02-groups-window-frame.sh
./03-cjk-tokenizers.sh
./ai-functions.sh         # needs ./.env with ANTHROPIC_API_KEY; not run by tools/hol or smoke
```

Each `NN-*.sh` pipes the matching `.sql` into `clickhouse-client`. Read the SQL
— the comments are the lab.

---

### 01 · Pipe operators

```sql
FROM trips
|> WHERE n > 2
|> AGGREGATE sum(n) AS total GROUP BY city
|> ORDER BY total DESC
```

SQL reads in an order nobody writes in. You start at `SELECT`, jump back to
`FROM`, then to `WHERE`, then return to the select list once you know what you
are grouping by. Pipe syntax lets the text run in the order the data flows.

**The operators.** The parser will list them if you give it something it does
not recognise:

```text
WHERE, SELECT, EXTEND, SET, DROP, AS, AGGREGATE, DISTINCT,
ORDER BY, LIMIT, OFFSET, UNION, INTERSECT, EXCEPT, and the JOIN family
```

Three of those have no classic equivalent and are worth knowing:

| | |
|---|---|
| `EXTEND expr AS name` | add a column, keep everything else — no need to re-list the columns |
| `SET col = expr` | overwrite a column in place |
| `DROP col` | remove a column |

**The practical argument is not elegance, it is append-only editing.** Every
prefix of a pipe chain is a complete query:

```sql
FROM trips;
FROM trips |> WHERE n >= 5;
FROM trips |> WHERE n >= 5 |> AGGREGATE sum(n) AS total GROUP BY city;
FROM trips |> WHERE n >= 5 |> AGGREGATE sum(n) AS total GROUP BY city |> ORDER BY total DESC;
```

Each line is the previous one plus a step. Nothing above ever has to be edited.
Building a query stops being a cycle of jumping back to the top.

**It is sugar, with nesting.** `EXPLAIN SYNTAX` rewrites a pipe chain as nested subqueries, one per step:

```text
SELECT city, sum(n) AS total FROM (SELECT * FROM (SELECT * FROM trips)
WHERE greater(n, 2)) GROUP BY city
```

The planner flattens the nesting. On an 18M-span `otel_traces` table (Cloud
26.8.1.608, 2026-11-04), a six-step chain and its classic form had the same
plan steps and the same index use (27 of 213 granules), and read the same
101,335 rows. Planning the nesting costs a little: across ten interleaved runs
the median was 16 ms against 11 ms, with analysis and plan build taking about
5.1 ms against 2.7 ms. That is noise on a heavy query and visible on a tiny
one. On a single-table lookup the classic form is also still shorter, which is
worth saying out loud before someone rewrites a codebase.

!!! note
    `EXPLAIN SYNTAX` itself changed in 26.8: it now returns **one `String`
    record** with embedded newlines instead of one record per line. If you had
    something parsing its output, that is a breaking change.

---

### 02 · `GROUPS` window frame mode

SQL defines three ways to size a window frame. ClickHouse had two.

| Mode | Counts |
|------|--------|
| `ROWS` | physical rows |
| `RANGE` | rows whose **value** is within the given distance |
| `GROUPS` | **peer groups** — sets of rows sharing the same `ORDER BY` value |

The difference only shows up when there are ties, gaps, or both. Values
`1, 5, 5, 100` with `BETWEEN 1 PRECEDING AND 1 FOLLOWING`:

| n | `ROWS` | `RANGE` | `GROUPS` |
|---|---|---|---|
| 1 | 2 | 1 | 3 |
| 5 | 3 | 2 | 4 |
| 5 | 3 | 2 | 4 |
| 100 | 2 | 1 | 3 |

`RANGE` collapses at the gap — nothing is within ±1 of 100, so the frame is the
row itself. `GROUPS` does not care how far away 100 is, only that it is the
next distinct value.

**Where it is the correct answer.** Ranked results with ties. "Compare each
score against the ranks either side of it" is a `GROUPS` question — you mean
the neighbouring rank, not a score one point away and not a fixed row count:

```text
player  score  GROUPS neighbours      ROWS neighbours
a       100    [a,b,c,d]              [a,b]
b       100    [a,b,c,d]              [a,b,c]
c       100    [a,b,c,d]              [b,c,d]
d        80    [a,b,c,d,e,f]          [c,d,e]
```

`GROUPS` returns the same complete answer for all three tied players. `ROWS`
slices arbitrarily through the tie and gives each of them a different one.

**The detail that surprises people.** Under `GROUPS` and `RANGE`,
`CURRENT ROW` is not one row — it is every row tied with it:

```sql
-- three rows all equal to 7
count() OVER (ORDER BY n GROUPS BETWEEN CURRENT ROW AND CURRENT ROW)  -- 3
count() OVER (ORDER BY n ROWS   BETWEEN CURRENT ROW AND CURRENT ROW)  -- 1
```

**On evenly spaced data `RANGE` and `GROUPS` are the same function**, which is
why the distinction is easy to miss until it produces a wrong number.

---

### 03 · `japanese`, `chinese` and `icu` tokenizers

For anyone indexing Korean, Japanese or Chinese, this is the release that makes
text indexes usable.

**What used to happen to Korean:**

```text
unicodeWord  ['클','릭','하','우','스','벡','터','검','색','은','빠','르','다']
asciiCJK     ['클','릭','하','우','스','벡','터','검','색','은','빠','르','다']
chinese      ['클릭하우스','벡터','검색은','빠르다']
icu(ko)      ['클릭하우스','벡터','검색은','빠르다']
```

Thirteen tokens for four words. An index built on per-syllable tokens matches
almost everything and prunes almost nothing — the worst of both. Korean does
put spaces between words, which is why this is easy to get wrong: it looks like
a space-splitting tokenizer should have been fine.

**Building the index.** The tokenizer argument is a function call:

```sql
INDEX idx body TYPE text(tokenizer = icu('ko')) GRANULARITY 1   -- correct
INDEX idx body TYPE text(tokenizer = 'icu', locale = 'ko')      -- rejected
```

**Two things about `icu` worth knowing before you tune it.**

The locale is mandatory — `tokens(s, 'icu')` errors with *"requires a mandatory
locale argument"*. And it must be a **constant**; passing a column gives
*"Expected: const String, got: String"*.

And then it does not change the Korean result. `ko`, `ko_KR`, `en`, `ja` and
`zh` all return identical tokens, because ICU's Korean word-break comes from a
built-in dictionary rather than from the locale tag.

#### The limitation to plan around

```sql
SELECT count() FROM docs WHERE hasToken(body, '검색');   -- 0
SELECT id    FROM docs WHERE hasToken(body, '검색은');   -- 1
```

Korean particles (조사) stay glued to the noun. `검색은`, `검색을` and `검색이`
are three different tokens and none of them is `검색`.

**This is word segmentation, not morphological analysis.** ICU finds word
boundaries; it does not know that 은/을/이 are grammar rather than spelling.
Options, in the order most people should consider them:

1. Search with the particle, if users type whole phrases.
2. Pre-process a second column with a Korean morphological analyser
   (mecab-ko, nori, kiwi) outside ClickHouse and index that with
   `splitByString`. You keep control and pay an ingest step.
3. Use `ngrams` for recall-first search and accept the index size.

What you should not do is assume `icu('ko')` behaves like a Korean analyser. It
is a large improvement over per-syllable splitting, and it is not that.

#### The other two

For Chinese the dedicated tokenizer is better than ICU:

```text
chinese  ['点击','之家','向量','搜索','很快']
icu(zh)  ['点','击','之家','向量','搜索','很快']
```

ICU splits 点击 into two characters. For Korean the two were identical. Test on
your own corpus rather than picking by name.

`japanese` is listed in `system.tokenizers` but needs a dictionary supplied in
the server configuration:

```text
Code: 139. The Japanese tokenizer requires a dictionary configured under
<tokenizer><japanese> in the server configuration
```

so it does not work out of the box in this container. `icu` handles Japanese
without extra configuration, which is the pragmatic choice for a mixed corpus.

---

### AI functions: `aiFilter` and `aiRedact` (outside `tools/hol`)

```sql
SELECT id, body FROM tickets
WHERE aiFilter(body, 'the customer asks for a refund or for their money back',
               map('temperature', '1'))
```

A function that sends the row to an LLM. They are **Beta** in 26.8 — every
`ai_function_*` setting reports tier `Beta` in `system.settings` — their output
is non-deterministic, and the text you pass goes to the provider. The docs carry a
prompt-injection warning: input text can steer the model, so treat the output as
untrusted before it builds SQL, shell commands or access decisions.

**Setup.** Provider `anthropic`, model `claude-haiku-5-5`, run on local OSS
26.8.36.3 with the author's own key. The key is never in the repository:
`ai-functions.sh` reads it from `./.env` (gitignored; one line,
`ANTHROPIC_API_KEY=...`, mode 600), builds the `CREATE NAMED COLLECTION`
statement and pipes it to `clickhouse-client` on stdin (no `--echo`), and drops
the collection when it ends. `ai_function_text_default_credentials` points the
text functions at it. In `system.named_collections` and `query_log` the secret
shows as `[HIDDEN]`. After the runs, a search of `system.query_log`,
`system.text_log` and the server log file for the key's first 20 characters
found nothing from the lab (the only hits were the search queries themselves).

**What came back** (20 made-up tickets, Korean and English mixed, with fake names,
`010-0000-xxxx` numbers and `@example.com` emails):

| | Result |
|---|---|
| `aiFilter` "asks for a refund" | 7 of 20 rows: ids 1, 4, 6, 9, 12, 15, 18 — Korean and English both. Two runs gave the same 7 |
| `aiRedact` name, email, phone number | `...My name is [REDACTED], phone [REDACTED].` and `연락처 [REDACTED], 이름은 [REDACTED]입니다.` The surrounding text was kept |

Row 9 shows the docs' warning in action: `Jisoo Han, 010-0000-0009.` became
`[REDACTED], [REDACTED].` — fine here, but the model decides what to keep, and the
docs say not to rely on it as anonymisation.

**One thing to know before you copy this.** `aiFilter` and `aiRedact` send
`temperature = 0.0` by default, and `claude-haiku-5-5` rejects it:
`HTTP 400 [invalid_request_error] temperature is deprecated for this model`. The
lab passes `map('temperature', '1')` on every call, which the API accepts (an
empty string is refused by ClickHouse: "must be a number"). The answers are then
sampled rather than greedy, so another run can differ from the table above.

**The limit.** `ai_function_max_api_calls_per_query` is an exact cap. On the
first 8 tickets (8 calls):

| Setting | Outcome |
|---|---|
| `max_api_calls_per_query = 10` | returns `3`, 8 calls |
| `= 3`, `throw_on_quota_exceeded = 1` (default) | `Code: 290 ... AI API call limit reached: 3 calls made, maximum: 3 (LIMIT_EXCEEDED)` |
| `= 3`, `throw_on_quota_exceeded = 0` | returns `1`, no error: 3 calls, 5 rows skipped (`AIRowsSkipped`) |

The last row is the dangerous one — the query succeeds with a count that is wrong,
and only `AIRowsSkipped` says so.

**What it cost.** Per query, from `ProfileEvents` in `system.query_log` (the lab
tags each query with `log_comment`):

| Query | `AIAPICalls` | `AIInputTokens` | `AIOutputTokens` |
|---|---|---|---|
| `aiFilter` over 20 rows | 20 | 2182 | 60 |
| `aiRedact` over 4 rows | 4 | 1105 | 168 |
| limit 10, 8 rows | 8 | 875 | 24 |
| limit 3, error | 3 | 318 | 9 |
| limit 3, no throw | 3 | 318 | 9 |
| **one run** | **38** | **4798** | **270** |

One call per row. At Haiku 5.5 list price ($0.10 / $0.50 per million input /
output tokens) one run is about $0.0006.

**Why `aiSimilarity` is not run.** It needs an embeddings endpoint, and in the
docs' "Supported providers" table (`ai-functions.mdx`, ClickHouse repository
master) Anthropic is listed for chat functions only. An OpenAI key would be
needed; the lab does not use one.

**Provider hosts.** The docs suggest `remote_url_allow_hosts` to limit which
hosts the functions may call; this container does not set it.

---

### Also in 26.8, not covered by these labs

Worth knowing about, in rough order of how likely they are to affect you:

| | |
|---|---|
| **`max_insert_threads` default `1` → `auto`** | `INSERT SELECT` is now parallel by default. Backward incompatible, and the one most likely to change your ingest behaviour without you asking |
| Lightweight `UPDATE` patch parts, v2 format | Peak memory bounded by the largest equal-sort-key run instead of the whole patch |
| `Date32` range widened | `[1900-01-01, 2299-12-31]` → `[0000-01-01, 9999-12-31]` |
| `PostgreSQL` / `MaterializedPostgreSQL` engines respect `remote_url_allow_hosts` | `CREATE DATABASE` now rejects disallowed hosts |
| `IEJoin` | Join algorithm for inequality comparisons |
| `gini` | Aggregate function for the Gini coefficient |
| `notHas`, array-of-integers subscript, `MultiPoint` | Small conveniences, all present and working |
| `bigquery` table function and `BigQuery` engine | |
| `aiSimilarity` | Embedding similarity of two texts; needs an embeddings provider, see the AI functions section for why it is not run. `aiFilter` and `aiRedact` are that section |
| `CREATE HANDLER` | Custom HTTP handlers as DDL |
| `parseQueryToJSON` / `formatQueryFromJSON` | AST to JSON and back |

### Verified

Every query in the three `.sql` files was run against **26.8.2.7** in the
container this lab sets up, and the outputs quoted above are from those runs.
Two of them needed fixing along the way, and both are noted in the SQL:
`UNION ALL` does not expose its column aliases to a trailing `ORDER BY`, and
`tokens()` will not take a locale from a column.

The AI functions section was run separately, on **26.8.36.3** (the image `26.8` resolved to on
2026-11-04), with the Anthropic API; labs 01–03 were not re-run on that build,
so the version at the top of this page is unchanged.

---

## 한국어

**2026-08-30 릴리스 · LTS · 여기서는 26.8.2.7로 검증**

26.8은 LTS이고 규모가 큽니다 — changelog에 하위 호환성 변경 21개, 신기능 46개,
성능 개선 89개가 있습니다. 이 랩은 그중 **컨테이너 하나에서 눈으로 확인할 수
있고**, 속도가 아니라 쿼리를 쓰는 방식을 바꾸는 세 가지를 다루고, Anthropic API 키가
필요한 AI 함수를 따로 더합니다(`tools/hol`은 실행하지 않음).

| 랩 | 기능 | 선정 이유 |
|----|------|-----------|
| [01](01-pipe-operators.sql) | 파이프 연산자 `\|>` | 수년 만의 가장 큰 문법 변화. 쿼리가 데이터 흐름 순서로 읽힘 |
| [02](02-groups-window-frame.sql) | `GROUPS` 윈도우 프레임 | SQL이 정의한 세 번째 프레임 모드, ClickHouse에 없던 것 |
| [03](03-cjk-tokenizers.sql) | `japanese`·`chinese`·`icu` 토크나이저 | 쓸모 있는 한국어 텍스트 인덱스와 무용지물의 차이 |
| [AI](ai-functions.sql) | `aiFilter`·`aiRedact` (Beta) | `WHERE` 안의 LLM 호출 — 무엇을 돌려주고, 얼마가 들고, 무엇이 막는지. Anthropic 키 필요 |

### 빠른 시작

```bash
./00-setup.sh              # local/oss-docker으로 26.8 기동
./01-pipe-operators.sh
./02-groups-window-frame.sh
./03-cjk-tokenizers.sh
./ai-functions.sh         # ./.env에 ANTHROPIC_API_KEY 필요, tools/hol·smoke는 실행하지 않음
```

각 `NN-*.sh`는 같은 이름의 `.sql`을 `clickhouse-client`에 넘깁니다. SQL을
읽으세요 — 주석이 곧 랩입니다.

---

### 01 · 파이프 연산자

```sql
FROM trips
|> WHERE n > 2
|> AGGREGATE sum(n) AS total GROUP BY city
|> ORDER BY total DESC
```

SQL은 아무도 쓰지 않는 순서로 읽힙니다. `SELECT`에서 시작해 `FROM`으로
돌아갔다가 `WHERE`로 갔다가, 무엇으로 그룹핑할지 정해진 뒤에야 다시 select
목록으로 옵니다. 파이프 문법은 텍스트가 데이터 흐름 순서로 흐르게 합니다.

**연산자 목록.** 파서에 모르는 것을 주면 알려줍니다.

```text
WHERE, SELECT, EXTEND, SET, DROP, AS, AGGREGATE, DISTINCT,
ORDER BY, LIMIT, OFFSET, UNION, INTERSECT, EXCEPT, 그리고 JOIN 계열
```

이 중 셋은 고전 문법에 대응물이 없어 알아둘 만합니다.

| | |
|---|---|
| `EXTEND expr AS name` | 컬럼 추가, 나머지는 유지 — 컬럼을 다시 나열할 필요 없음 |
| `SET col = expr` | 컬럼을 제자리에서 덮어씀 |
| `DROP col` | 컬럼 제거 |

**실용적 논거는 우아함이 아니라 "덧붙이기만 하는 편집"입니다.** 파이프 체인의
모든 접두사가 완결된 쿼리입니다.

```sql
FROM trips;
FROM trips |> WHERE n >= 5;
FROM trips |> WHERE n >= 5 |> AGGREGATE sum(n) AS total GROUP BY city;
FROM trips |> WHERE n >= 5 |> AGGREGATE sum(n) AS total GROUP BY city |> ORDER BY total DESC;
```

각 줄은 이전 줄에 한 단계를 더한 것입니다. 위쪽은 절대 고칠 일이 없습니다.
쿼리 작성이 맨 위로 되돌아가는 반복에서 벗어납니다.

**문법 설탕이되, 중첩됩니다.** `EXPLAIN SYNTAX`는 파이프 체인을 단계마다 하나씩 중첩된 서브쿼리로 바꿉니다.

```text
SELECT city, sum(n) AS total FROM (SELECT * FROM (SELECT * FROM trips)
WHERE greater(n, 2)) GROUP BY city
```

중첩은 플래너가 펼칩니다. 스팬 1,800만 행의 `otel_traces`(Cloud 26.8.1.608,
2026-11-04)에서 여섯 단계 체인과 같은 뜻의 고전 쿼리는 계획 단계와 인덱스 사용
(그래뉼 213개 중 27개)이 같았고, 읽은 행도 101,335행으로 같았습니다. 중첩을
계획하는 비용은 조금 있습니다. 번갈아 10번씩 돌린 중앙값이 16 ms 대 11 ms였고,
분석·계획 생성에 약 5.1 ms 대 2.7 ms가 들었습니다. 무거운 쿼리에서는 묻히고,
아주 가벼운 쿼리에서는 보이는 정도입니다. 단일 테이블 조회는 고전 문법이 여전히
더 짧습니다 — 누군가 코드베이스를 갈아엎기 전에 말해둘 필요가 있습니다.

!!! note
    `EXPLAIN SYNTAX` 자체가 26.8에서 바뀌었습니다. 줄마다 레코드 하나가 아니라
    개행이 포함된 **`String` 레코드 하나**를 반환합니다. 출력을 파싱하던 게
    있다면 깨지는 변경입니다.

---

### 02 · `GROUPS` 윈도우 프레임 모드

SQL은 윈도우 프레임 크기를 정하는 방법을 셋 정의합니다. ClickHouse엔 둘이
있었습니다.

| 모드 | 세는 대상 |
|------|-----------|
| `ROWS` | 물리적 행 |
| `RANGE` | **값**이 주어진 거리 안에 있는 행 |
| `GROUPS` | **피어 그룹** — `ORDER BY` 값이 같은 행들의 묶음 |

차이는 동점이나 간격이 있을 때만 드러납니다. 값 `1, 5, 5, 100`에
`BETWEEN 1 PRECEDING AND 1 FOLLOWING`:

| n | `ROWS` | `RANGE` | `GROUPS` |
|---|---|---|---|
| 1 | 2 | 1 | 3 |
| 5 | 3 | 2 | 4 |
| 5 | 3 | 2 | 4 |
| 100 | 2 | 1 | 3 |

`RANGE`는 간격에서 무너집니다 — 100의 ±1 안에 아무것도 없어 프레임이 자기 행
하나입니다. `GROUPS`는 100이 얼마나 먼지 신경 쓰지 않고, 다음 구별되는 값이라는
것만 봅니다.

**이게 정답인 경우.** 동점이 있는 순위표입니다. "각 점수를 양옆 순위와 비교"는
`GROUPS` 질문입니다 — 1점 차이 나는 점수도, 고정된 행 수도 아니고 이웃한
*순위*를 뜻하니까요.

```text
player  score  GROUPS 이웃            ROWS 이웃
a       100    [a,b,c,d]              [a,b]
b       100    [a,b,c,d]              [a,b,c]
c       100    [a,b,c,d]              [b,c,d]
d        80    [a,b,c,d,e,f]          [c,d,e]
```

`GROUPS`는 동점인 세 명 모두에게 같은 완전한 답을 줍니다. `ROWS`는 동점을
임의로 잘라 각자에게 다른 답을 줍니다.

**사람들이 놀라는 지점.** `GROUPS`와 `RANGE`에서 `CURRENT ROW`는 한 행이 아니라
**동점인 모든 행**입니다.

```sql
-- 값이 전부 7인 세 행
count() OVER (ORDER BY n GROUPS BETWEEN CURRENT ROW AND CURRENT ROW)  -- 3
count() OVER (ORDER BY n ROWS   BETWEEN CURRENT ROW AND CURRENT ROW)  -- 1
```

**값이 고르게 분포하면 `RANGE`와 `GROUPS`는 같은 함수입니다.** 그래서 이 구분은
틀린 숫자가 나오기 전까지 놓치기 쉽습니다.

---

### 03 · `japanese`·`chinese`·`icu` 토크나이저

한국어·일본어·중국어를 색인하는 사람에게 이 릴리스는 텍스트 인덱스를 쓸 수 있게
만든 릴리스입니다.

**기존에 한국어에 벌어지던 일:**

```text
unicodeWord  ['클','릭','하','우','스','벡','터','검','색','은','빠','르','다']
asciiCJK     ['클','릭','하','우','스','벡','터','검','색','은','빠','르','다']
chinese      ['클릭하우스','벡터','검색은','빠르다']
icu(ko)      ['클릭하우스','벡터','검색은','빠르다']
```

네 단어에 토큰 13개입니다. 음절 단위 토큰으로 만든 인덱스는 거의 모든 것에
매칭되고 거의 아무것도 걸러내지 못합니다 — 양쪽의 최악입니다. 한국어는 단어
사이에 띄어쓰기를 하기 때문에 이게 틀리기 쉽습니다. 공백 분할 토크나이저로
충분해 보이거든요.

**인덱스 만들기.** 토크나이저 인자는 함수 호출입니다.

```sql
INDEX idx body TYPE text(tokenizer = icu('ko')) GRANULARITY 1   -- 맞음
INDEX idx body TYPE text(tokenizer = 'icu', locale = 'ko')      -- 거부됨
```

**`icu`에 대해 튜닝 전에 알아둘 두 가지.**

로케일은 **필수**입니다 — `tokens(s, 'icu')`는 <em>"requires a mandatory locale
argument"</em>로 실패합니다. 그리고 **상수**여야 합니다. 컬럼을 넘기면
<em>"Expected: const String, got: String"</em>이 납니다.

그런데 한국어 결과는 로케일에 따라 바뀌지 않습니다. `ko`, `ko_KR`, `en`, `ja`,
`zh` 전부 동일한 토큰을 냅니다. ICU의 한국어 단어 분리가 로케일 태그가 아니라
내장 사전에서 오기 때문입니다.

#### 반드시 감안해야 할 한계

```sql
SELECT count() FROM docs WHERE hasToken(body, '검색');   -- 0
SELECT id    FROM docs WHERE hasToken(body, '검색은');   -- 1
```

조사가 명사에 붙어 있습니다. `검색은`, `검색을`, `검색이`는 서로 다른 세 토큰
이고 그중 어느 것도 `검색`이 아닙니다.

**이건 단어 분리이지 형태소 분석이 아닙니다.** ICU는 단어 경계를 찾을 뿐,
은/을/이가 철자가 아니라 문법이라는 것은 모릅니다. 고려할 선택지를 순서대로:

1. 사용자가 구 단위로 입력한다면 조사를 포함해 검색.
2. ClickHouse 밖에서 한국어 형태소 분석기(mecab-ko, nori, kiwi)로 전처리한
   컬럼을 하나 더 두고 `splitByString`으로 색인. 통제권을 갖는 대신 적재 단계를
   지불합니다.
3. 재현율 우선이면 `ngrams`를 쓰고 인덱스 크기를 감수.

하지 말아야 할 것은 `icu('ko')`가 한국어 분석기처럼 동작하리라 가정하는
것입니다. 음절 분할보다 크게 나아진 것이지, 그것은 아닙니다.

#### 나머지 둘

중국어에서는 전용 토크나이저가 ICU보다 낫습니다.

```text
chinese  ['点击','之家','向量','搜索','很快']
icu(zh)  ['点','击','之家','向量','搜索','很快']
```

ICU는 点击을 두 글자로 쪼갭니다. 한국어에서는 둘이 동일했습니다. 이름으로
고르지 말고 자기 코퍼스에서 시험하세요.

`japanese`는 `system.tokenizers`에 있지만 서버 설정에 사전이 필요합니다.

```text
Code: 139. The Japanese tokenizer requires a dictionary configured under
<tokenizer><japanese> in the server configuration
```

그래서 이 컨테이너에서는 바로 안 됩니다. `icu`는 추가 설정 없이 일본어를
처리하므로, 혼합 코퍼스에는 그쪽이 현실적입니다.

---

### AI 함수: `aiFilter`와 `aiRedact` (`tools/hol` 밖)

```sql
SELECT id, body FROM tickets
WHERE aiFilter(body, 'the customer asks for a refund or for their money back',
               map('temperature', '1'))
```

행을 LLM으로 보내는 함수입니다. 26.8에서는 **Beta**입니다 — `system.settings`에서
모든 `ai_function_*` 설정의 tier가 `Beta`입니다. 출력은 비결정적이고, 넘긴 텍스트는
제공자에게 갑니다. 문서에는 프롬프트 인젝션 경고가 있습니다. 입력 텍스트가 모델을
유도할 수 있으므로, 출력으로 SQL·셸 명령·접근 결정을 만들기 전에 신뢰하지 않는
값으로 다루세요.

**준비.** 제공자 `anthropic`, 모델 `claude-haiku-5-5`, 로컬 OSS 26.8.36.3에서
작성자 본인의 키로 실행했습니다. 키는 저장소에 없습니다. `ai-functions.sh`가
`./.env`(gitignore, `ANTHROPIC_API_KEY=...` 한 줄, 권한 600)에서 읽어
`CREATE NAMED COLLECTION` 문을 만들고 stdin으로 `clickhouse-client`에 넘기며
(`--echo` 없음), 끝나면 컬렉션을 지웁니다. `ai_function_text_default_credentials`가
텍스트 함수를 이 컬렉션으로 향하게 합니다. `system.named_collections`와
`query_log`에서 비밀 값은 `[HIDDEN]`으로 보입니다. 실행 뒤 `system.query_log`,
`system.text_log`, 서버 로그 파일에서 키 앞 20자를 검색했을 때 랩이 남긴 흔적은
없었습니다(검색 쿼리 자체만 걸렸습니다).

**결과** (한·영 섞인 가짜 티켓 20건. 가짜 이름, `010-0000-xxxx`, `@example.com`):

| | 결과 |
|---|---|
| `aiFilter` "환불 요청" | 20행 중 7행: id 1, 4, 6, 9, 12, 15, 18 — 한국어와 영어 모두. 두 번 돌려 같은 7행 |
| `aiRedact` 이름·이메일·전화번호 | `...My name is [REDACTED], phone [REDACTED].`, `연락처 [REDACTED], 이름은 [REDACTED]입니다.` 주변 텍스트는 유지 |

9번 행이 문서의 경고를 보여 줍니다. `Jisoo Han, 010-0000-0009.`가
`[REDACTED], [REDACTED].`가 됐습니다. 여기서는 무난하지만 무엇을 남길지는 모델이
정하고, 문서도 익명화 수단으로 믿지 말라고 합니다.

**복사해 가기 전에 알아둘 것.** `aiFilter`와 `aiRedact`는 기본으로
`temperature = 0.0`을 보내는데 `claude-haiku-5-5`는 이를 거부합니다.
`HTTP 400 [invalid_request_error] temperature is deprecated for this model`.
이 랩은 모든 호출에 `map('temperature', '1')`을 넘기고 API가 받아들입니다(빈
문자열은 ClickHouse가 "must be a number"로 거부). 그래서 답이 탐욕적이 아니라
샘플링이므로 다시 돌리면 위 표와 다를 수 있습니다.

**제한.** `ai_function_max_api_calls_per_query`는 정확한 상한입니다. 앞 8개 티켓
(호출 8회) 기준:

| 설정 | 결과 |
|---|---|
| `max_api_calls_per_query = 10` | `3` 반환, 호출 8회 |
| `= 3`, `throw_on_quota_exceeded = 1`(기본) | `Code: 290 ... AI API call limit reached: 3 calls made, maximum: 3 (LIMIT_EXCEEDED)` |
| `= 3`, `throw_on_quota_exceeded = 0` | 오류 없이 `1` 반환: 호출 3회, 5행 건너뜀(`AIRowsSkipped`) |

마지막 줄이 위험합니다. 쿼리는 성공하는데 카운트가 틀리고, `AIRowsSkipped`만이
이를 알려 줍니다.

**비용.** `system.query_log`의 `ProfileEvents`로 쿼리별 값입니다(랩이 쿼리마다
`log_comment`를 붙임):

| 쿼리 | `AIAPICalls` | `AIInputTokens` | `AIOutputTokens` |
|---|---|---|---|
| `aiFilter` 20행 | 20 | 2182 | 60 |
| `aiRedact` 4행 | 4 | 1105 | 168 |
| 한도 10, 8행 | 8 | 875 | 24 |
| 한도 3, 오류 | 3 | 318 | 9 |
| 한도 3, throw 끔 | 3 | 318 | 9 |
| **1회 실행** | **38** | **4798** | **270** |

행마다 호출 1회입니다. Haiku 5.5 정가(입력 100만 토큰 $0.10 / 출력 $0.50) 기준
1회 실행은 약 $0.0006입니다.

**`aiSimilarity`를 실행하지 않는 이유.** 임베딩 엔드포인트가 필요한데, 문서의
"Supported providers" 표(ClickHouse 저장소 master의 `ai-functions.mdx`)에서
Anthropic은 채팅 함수만 지원합니다. OpenAI 키가 있어야 하며 이 랩은 쓰지 않았습니다.

**제공자 호스트.** 문서는 함수가 호출할 호스트를 `remote_url_allow_hosts`로
제한하라고 합니다. 이 컨테이너는 설정하지 않았습니다.

---

### 26.8의 다른 변화 (이 랩에서 다루지 않음)

영향을 받을 가능성이 큰 순서로:

| | |
|---|---|
| **`max_insert_threads` 기본값 `1` → `auto`** | `INSERT SELECT`가 기본 병렬화. 하위 호환성 변경이고, 요청하지 않았는데 적재 동작이 바뀔 가능성이 가장 큼 |
| 경량 `UPDATE` patch part v2 포맷 | 피크 메모리가 전체 patch가 아니라 최대 동일-정렬키 구간으로 제한 |
| `Date32` 범위 확대 | `[1900-01-01, 2299-12-31]` → `[0000-01-01, 9999-12-31]` |
| `PostgreSQL`/`MaterializedPostgreSQL` 엔진이 `remote_url_allow_hosts` 존중 | `CREATE DATABASE`가 허용되지 않은 호스트를 거부 |
| `IEJoin` | 부등호 비교 조인 알고리즘 |
| `gini` | 지니 계수 집계 함수 |
| `notHas`, 정수 배열 첨자, `MultiPoint` | 소소한 편의 기능, 모두 동작 확인 |
| `bigquery` 테이블 함수와 `BigQuery` 엔진 | |
| `aiSimilarity` | 두 텍스트의 임베딩 유사도. 임베딩 제공자가 필요해 실행하지 않음(이유는 AI 함수 절). `aiFilter`·`aiRedact`는 그 절 |
| `CREATE HANDLER` | 커스텀 HTTP 핸들러를 DDL로 |
| `parseQueryToJSON` / `formatQueryFromJSON` | AST ↔ JSON |

### 검증

세 `.sql` 파일의 모든 쿼리를 이 랩이 띄우는 컨테이너의 **26.8.2.7**에서
실행했고, 위에 인용한 출력은 그 실행 결과입니다. 그 과정에서 두 가지를 고쳐야
했고 둘 다 SQL에 적어뒀습니다. `UNION ALL`은 컬럼 별칭을 뒤따르는 `ORDER BY`에
노출하지 않으며, `tokens()`는 로케일을 컬럼에서 받지 않습니다.

AI 함수 절은 따로 **26.8.36.3**(2026-11-04에 `26.8` 이미지가 가리킨 빌드)에서 Anthropic
API로 실행했습니다. 01–03은 그 빌드에서 다시 돌리지 않았으므로 맨 위의 버전
표기는 그대로입니다.
