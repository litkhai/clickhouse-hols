# Korean keyword search for RAG — tokenizers, a morpheme column, hybrid retrieval

[English](#english) | [한국어](#한국어)

---

## English

In a RAG stack on ClickHouse the vector half does not care about the language: Korean quality
comes from the embedding model. The keyword half does care, and ClickHouse has no Korean analyser
(nothing like nori or mecab-ko). This lab measures what each text-index tokenizer gets right and
wrong when Korean questions are asked over Korean document chunks. It then measures what a
morpheme column produced outside ClickHouse adds, and what hybrid retrieval adds on top.

Two labs cover the ground before this one:
- [local/releases/26.8](../../local/releases/26.8/) shows `tokens()` for `asciiCJK`, `chinese` and `icu` on one sentence.
- [usecase/fulltext-search](../fulltext-search/) measures recall lost to particles and spacing over 1M support tickets on Cloud.

This lab adds:
- questions with labelled relevant chunks
- a Kiwi morpheme column
- `splitByRegexp` and `sparseGrams`
- keyword ranking without BM25
- vector search and fusion
- a Cloud check

**Verified on ClickHouse 26.9.11.2** (`clickhouse/clickhouse-server:26.9`), 2026-10-06, steps 00–05 through
`tools/hol run` and step 06 by hand. Kiwi: kiwipiepy 0.24.0, model 0.24.0. Step 06: Ollama 0.35.0,
`bge-m3` (digest `7907646426…`), 1024 dimensions. Machine: Docker Desktop on macOS, 12 CPUs, 8 GB.

### Results

40 questions, 300 chunks, ranked by matched query tokens ÷ query tokens (step 04). Index size is on the
300-chunk table (step 05). The body column itself is 27.6 KB compressed.

| Keyword setup | recall@5 | recall@10 | MRR@10 | unranked recall@10 | index size | × body | scan without index (30k rows) |
|---|---:|---:|---:|---:|---:|---:|---:|
| `kiwi` — morphemes, `tokenizer = array` | **0.925** | **0.962** | **0.919** | 0.575 | **16.4 KB** | **0.60** | 6 ms |
| `splitByRegexp` — particle-stripping regexp | 0.667 | 0.846 | 0.686 | 0.588 | 22.6 KB | 0.82 | 794 ms |
| `ngrams(2)` | 0.692 | 0.817 | 0.745 | 0.025 | 57.9 KB | 2.10 | 15 ms |
| `ngrams(3)` | 0.704 | 0.767 | 0.707 | 0.375 | 85.1 KB | 3.09 | 16 ms |
| `asciiCJK` | 0.562 | 0.700 | 0.613 | 0.025 | 29.1 KB | 1.06 | 12 ms |
| `sparseGrams` | 0.371 | 0.462 | 0.303 | 0.417 | 227.4 KB | 8.24 | 52 ms |
| `icu('ko')` | 0.346 | 0.450 | 0.359 | 0.338 | 26.4 KB | 0.96 | 70 ms |
| `splitByNonAlpha` | 0.296 | 0.396 | 0.306 | 0.308 | 26.4 KB | 0.96 | 4 ms |

Ranked recall@10 by failure case (8 questions each):

| Keyword setup | particle 조사 | spacing 띄어쓰기 | ending 어미 | mixed 한영 | short 1음절 |
|---|---:|---:|---:|---:|---:|
| `kiwi` | 1.000 | 1.000 | 0.812 | 1.000 | 1.000 |
| `splitByRegexp` | 1.000 | 0.500 | 0.854 | 0.875 | 1.000 |
| `ngrams(2)` | 0.812 | 0.875 | 0.750 | 0.896 | 0.750 |
| `ngrams(3)` | 0.812 | 0.750 | 0.500 | 0.958 | 0.812 |
| `asciiCJK` | 0.688 | 0.875 | 0.771 | 0.542 | 0.625 |
| `sparseGrams` | 0.750 | 0.375 | 0.104 | 0.521 | 0.562 |
| `icu('ko')` | 0.062 | 0.375 | 0.250 | 0.938 | 0.625 |
| `splitByNonAlpha` | 0.062 | 0.250 | 0.250 | 0.792 | 0.625 |

With the index, every tokenizer answers `hasAllTokens(col, '법인카드 분실')` at 30,000 rows in 2–3 ms and
reads 800 rows; the scans in the first table read all 30,000. A plain `LIKE` scan took 3 ms at that size,
so wall time does not separate the setups at this scale; rows read do. The 30k-row table repeats the
300 chunks 100 times, so dictionaries do not grow; it measures posting-list reads, not vocabulary.
Three runs on the same day differed by under 10%.

Vector and hybrid (step 06, reciprocal rank fusion with k = 60 of the top 20 of each list):

| Method | recall@5 | recall@10 | MRR@10 |
|---|---:|---:|---:|
| vector only (`bge-m3`) | **0.979** | **1.000** | **0.975** |
| hybrid vector + `kiwi` | 0.962 | 1.000 | 0.966 |
| hybrid vector + `ngrams(2)` | 0.892 | 1.000 | 0.870 |
| keyword `kiwi` | 0.925 | 0.962 | 0.919 |
| keyword `ngrams(2)` | 0.692 | 0.817 | 0.745 |

### Which keyword setup to use for Korean RAG, and why

1. **A morpheme column indexed with `tokenizer = array`.** Run a Korean analyser (here Kiwi) at ingest,
   store `morphemes Array(String)`, search with the question's morphemes and rank by overlap.
   - It is best on every failure case but verb endings. It has the highest recall@5 (0.925) and the smallest index (0.6 × body).
   - The analyser runs outside ClickHouse, and nothing inside the server changes.
   - `array` is accepted on the Cloud service checked below.
   - It needs the same analyser, version and rule on the query side. `lab_meta` records them.
2. **No analyser available: `ngrams(2)`, ranked.**
   - Recall@10 is 0.817 for 2.1 × the body on disk.
   - Never use it as a filter. `hasAnyTokens` returns 250 of 300 chunks for a question, so unranked recall@10 is 0.025.
   - The particle-stripping `splitByRegexp` gets 0.846 at recall@10 but only 0.5 on spacing.
   - That regexp also over-strips: `사이` becomes `사`.
   - It costs the most to tokenize: 794 ms to scan 30k rows without the index.
   - It is not on the Cloud build checked below.
3. **Avoid for question search:**
   - `icu('ko')` and `splitByNonAlpha` keep the particle on the word: particle recall@10 is 0.062.
   - `asciiCJK` matches 296 of 300 chunks per question: no pruning, 38 of 38 granules.
   - `sparseGrams`: see the next section.
4. **Always rank.** Unranked filtering stays at 0.025–0.588 recall@10.
5. **`hasAllTokens` on a question is not usable as is.**
   - The question's endings (`하나요`, `어떻게`) are not in the chunks, so every raw tokenizer returns nothing.
   - `kiwi` reaches 0.308 recall, because its rule drops those words.
6. **On this corpus, hybrid did not beat vector search.**
   - `bge-m3` alone reaches recall@10 = 1.0. Hybrid with `kiwi` ties at @10 and is 0.017 lower at @5.
   - The two transliteration questions (`아웃룩`/`Outlook`, `팀즈`/`Teams`) were found by keywords too, because the rest of the question carries them.
   - So this lab shows that the keyword setup decides how much a hybrid loses (vector + `ngrams(2)`: 0.892 at @5).
   - It does not show what hybrid gains.
   - *Hypothesis, unmeasured:* the keyword half earns its place on corpora with many near-duplicate chunks, or exact identifiers the embedding model has not seen.

### Things that surprised us (26.9.11.2)

- **`sparseGrams` treats a String needle as a phrase.**
  - A String needle goes through `compactTokens()` (`src/Functions/hasAnyAllTokens.cpp:64` at `v26.9.11.2-stable`).
  - For `sparseGrams` that drops every gram contained in a longer one (`src/Interpreters/ITokenizer.cpp:677`).
  - This is right for `hasAllTokens`. But `hasAnyTokens(col, '<question>')` then searches only the longest grams, so it behaves like a phrase search.
  - For question 1, `tokens()` shares a gram with 97 chunks. The index returned 1 chunk, which matched only `나요?`.
  - Step 03 applies the same compaction, and its positive control (48 rows, all 8 tokenizers) fails the step without it.
  - `sparseGrams` also has a minimum length of 3, so `tokens('결재', 'sparseGrams')` is `[]`.
- **One text index per column.** A second one fails with Code 36, `Column b must not have more than one text index`. Step 02 indexes `MATERIALIZED` copies of the body instead.
- **The needle must be a constant.**
  - A column from a join is rejected with Code 44.
  - A scalar subquery `(SELECT question FROM queries WHERE qid = 1)` is accepted, and the index is used.
  - Steps 03–04 therefore compare token arrays, and step 03 checks them against the index.
- **The 26.8 findings hold on 26.9.** `asciiCJK` gives single syllables, and `icu` keeps particles. The locale (`ko`, `ko_KR`, `en`, `ja`) does not change the result.

### Data

All of it is in the lab, so the T0 run needs neither Python nor network.

- `data/chunks.jsonl`: 300 chunks from 27 documents of a fictional company.
  - Internal policy: remote work, leave, travel, corporate card, purchasing, approvals, security.
  - IT helpdesk: VPN, Outlook, SSO, Teams, ERP error codes, devices.
- `data/queries.jsonl`: 40 questions phrased as an employee would ask a helpdesk bot.
  - 8 per failure case, each with 2–3 relevant chunks (qrels) and a `note` naming its trap.
  - **particle**: `결재선을` in the question, `결재선은` / `결재선이` in the chunks.
  - **spacing**: `구매 요청서` against `구매요청서`, and the other way round.
  - **ending**: `잠겼어요` against `계정 잠금` / `잠긴 계정`.
  - **mixed**: lowercase codes, English glued to a particle (`VPN이`), error codes (`ERP-4012`, `0x80070005`), and transliterations (`아웃룩` against `Outlook`).
  - **short**: one-syllable terms (`키`, `망`, `폰`, `앱`, `차`, `층`, `팀`, `표`).
  - Every question also has hard negatives: chunks that share its key term and answer something else.
- The text is synthetic, drafted for this lab with an AI model.
  - The qrels are by construction: the relevant chunks were written for the question.
  - Script checks: the trap holds in every relevant chunk, ids are contiguous, and there are 8 questions per case.
  - A sample was read by hand.
- `gen_data.py` runs Kiwi once and writes `00-data.sql`, which is committed.
  - Rule: keep tags `NNG NNP NR SL SN SH XR VV VA` (the part before `-`), lowercase them, and drop `하 되 있 어떻`.
  - It is deliberately simple: `그렇` and `없` survive, for example.
  - To regenerate: `uv run usecase/korean-rag-tokenizers/gen_data.py`. Re-running it with unchanged inputs writes a byte-identical file.

### Steps

| File | Tier | What it does |
|---|---|---|
| `00-data.sql` | T0 | generated: `chunks_src`, `queries`, `phrases`, `lab_meta` |
| `01-tokens.sql` | T0 | `tokens()` of 8 tokenizers on 11 failure-case phrases; the 26.8 re-check; `sparseGrams` minimum; constant needles |
| `02-schema.sql` | T0 | `chunks`: the body, 7 `MATERIALIZED` copies each with its own text index (`preprocessor = lower(...)`), `morphemes` with `tokenizer = array`; `index_granularity = 8` so pruning shows on 300 rows |
| `03-recall.sql` | T0 | `hasAny` / `hasAll` filtering: recall, precision and chunks returned, by tokenizer and failure case; positive control against the index (48 rows, fails the step on any mismatch) |
| `04-ranking.sql` | T0 | ranking by matched ÷ query tokens: recall@5/@10, MRR@10, unranked baseline, by failure case; `keyword_ranked` for step 06 |
| `05-index-cost.sql` | T0 | index bytes, distinct tokens, granules read (`EXPLAIN indexes = 1`), latency and rows read at 30k rows with and without the index |
| `t1/06-hybrid.sh` + `t1/06-hybrid.sql` | T1 | `aiEmbed` through a local Ollama, a `vector_similarity` HNSW index, exact top 20, RRF with the `kiwi` and `ngrams(2)` lists |
| `cloud/tokenizer-check.sql` | by hand | which tokenizers a ClickHouse Cloud service accepts, as `tokens()` and as a text index; drops what it creates |

`t1/` and `cloud/` sit outside the top-level `NN-*.sql` that `tools/hol` runs, so steps 00–05 stay T0.

### Run it

```bash
python3 tools/hol run usecase/korean-rag-tokenizers
```

To read each step's output, keep the container and pipe the step in again:

```bash
python3 tools/hol run usecase/korean-rag-tokenizers --keep
docker exec -i hol-usecase-korean-rag-tokenizers clickhouse-client --multiline --multiquery < usecase/korean-rag-tokenizers/04-ranking.sql
```

Step 06 needs Ollama on the host, with the model pulled:

```bash
ollama pull bge-m3
```

Then run it against the kept container:

```bash
usecase/korean-rag-tokenizers/t1/06-hybrid.sh
```

What the script does:
- It checks the container, the step-04 tables, Ollama and the model, and prints the Ollama version and model digest.
- It gives the container's `default` user `named_collection_control` through a users.d file. The hol container has no right to `CREATE NAMED COLLECTION` without it.
- It then runs `06-hybrid.sql`.
- The SQL reaches Ollama as `host.docker.internal:11434`. Docker Desktop provides that name; on Linux add `--add-host=host.docker.internal:host-gateway` (not tested).

```bash
python3 tools/hol down usecase/korean-rag-tokenizers
```

### Two framework defaults that break Korean

Reproduced on 26.9.11.2 on 2026-10-06 in a scratch environment, with mock embeddings.

**LlamaIndex** — `llama-index-vector-stores-clickhouse` 0.8.0 (llama-index-core 0.14.25, clickhouse-connect 1.9.0).

How it searches keywords:
- HYBRID and TEXT_SEARCH match keywords with regexes built in `_build_text_search_statement` / `_build_hybrid_search_statement`.
- `base.py:351` builds `\b(?i)<token>\b` for `multiMatchAllIndices`.
- `\b` is an ASCII word boundary, so a Hangul keyword never matches: `match('클릭하우스 테스트', '\\b(?i)클릭하우스\\b')` = 0 on 26.9.11.2, while the English equivalent is 1.
- No text index is created; the keyword path is a regex scan.

What goes wrong:
- **TEXT_SEARCH crashes.** With no matching row, `base.py:516` raises `ValueError: tuple.index(x): x not in tuple`.
- **HYBRID silently ignores the Korean keyword.**
- **The second term is broken even for English.** `base.py:360` writes a single `\b` into a SQL literal, which ClickHouse reads as a backspace (`hex('\b')` = `08`), so `countMatches` is always 0.

There is no constructor option. Override the two builders in a subclass:

```python
from llama_index.vector_stores.clickhouse import ClickHouseVectorStore
from llama_index.vector_stores.clickhouse.base import _default_tokenizer, escape_str

class KoreanClickHouseVectorStore(ClickHouseVectorStore):
    def _terms(self, query_str):
        arr = "[" + ",".join("'" + escape_str(t) + "'" for t in _default_tokenizer(query_str)) + "]"
        hits = f"arraySum(arrayMap(p -> p > 0, multiSearchAllPositionsCaseInsensitiveUTF8(text, {arr})))"
        tf = f"log(1 + arraySum(arrayMap(t -> countSubstringsCaseInsensitiveUTF8(text, t), {arr})))"
        return hits, tf

    def _build_text_search_statement(self, query_str, similarity_top_k):
        hits, tf = self._terms(query_str)
        cols = ",".join(k for k in self._column_config if k != "vector")
        return (f"SELECT {cols}, score FROM {self._config.database}.{self._config.table} "
                f"WHERE score > 0 ORDER BY {hits} AS score DESC, {tf} AS d2 DESC LIMIT {similarity_top_k}")

    def _build_hybrid_search_statement(self, stage_one_sql, query_str, similarity_top_k):
        hits, tf = self._terms(query_str)
        cols = ",".join(k for k in self._column_config if k != "vector")
        return (f"SELECT {cols}, score FROM ({stage_one_sql}) tempt "
                f"ORDER BY {hits} AS d1 DESC, {tf} AS d2 DESC, score ASC LIMIT {similarity_top_k}")
```

How the override behaves:
- Substring matching finds `클릭하우스` in `클릭하우스는 빠르다`.
- A query with no match still raises the `ValueError` above, so catch it around `query()`.
- To use a text index instead, add `WHERE hasAnyTokens(text, '<query>')` on a column indexed as in this lab.

**LangChain** — `langchain-community` 0.4.2 (`langchain_community/vectorstores/clickhouse.py`).

The default index:
- `ClickhouseSettings.index_type` defaults to `"annoy"` (line 78), with `index_param = ["'L2Distance'", 100]` (line 80).
- ClickHouse removed `annoy` in 25.5, so on 26.9 the constructor fails with:
  `Code: 80. DB::Exception: Unknown Index type 'annoy'. Available index types: hypothesis, text, vector_similarity, …`

Override both settings:

```python
from langchain_community.vectorstores import Clickhouse, ClickhouseSettings

# no ANN index (exact scan)
ClickhouseSettings(index_type=None, ...)
# or HNSW; the dimension goes inside index_param, and the metric must stay L2Distance
ClickhouseSettings(index_type="vector_similarity", index_param=["'hnsw'", "'L2Distance'", DIM], ...)
```

Pitfalls:
- **The metric must be L2Distance.** The store's search is hard-coded to `L2Distance` (line 582); an index built on `cosineDistance` is not used.
- **Changing only `index_type` fails**, with `Vector similarity index must have three or six arguments`.
- **`index_query_params` is broken.** It emits `SETTING` instead of `SETTINGS` (line 576). The resulting syntax error is swallowed, and the search returns `[]`.
- **`langchain-community` warns that it is being sunset.** The `langchain-clickhouse` 0.1.0 on PyPI is a third-party package with no index options, not its successor.

### ClickHouse Cloud

Checked read-only on 2026-10-06 against a Cloud service on **26.6.1.2292**, through `mcp-clickhouse`.

Tokenizers:
- `system.tokenizers` lists `ngrams`, `splitByNonAlpha`, `sparseGrams`, `array`, `splitByString`, `asciiCJK`, `unicodeWord` (and the bloom-filter names). It does not list `icu`, `chinese`, `japanese` or `splitByRegexp`.
- `tokens()` works for the five listed in this lab. `tokens(…, 'icu', 'ko')` and `tokens(…, 'splitByRegexp', …)` fail with Code 42 on that build.
- That service already holds text indexes with `splitByNonAlpha`, `array` and `ngrams(2)`.
- So the two setups recommended above, `kiwi` and `ngrams(2)`, are available on it.

Embeddings:
- `aiEmbed` appears in `system.functions` there, but `allow_experimental_ai_functions` is 0.
- The docs say AI functions are not available in Cloud services at the moment ([AI functions](https://clickhouse.com/docs/reference/functions/regular-functions/ai-functions), read 2026-10-06).
- On Cloud the application produces the embeddings and inserts them as `Array(Float32)`. The `vector_similarity` part of step 06 is unchanged.

Other notes:
- The docs mark the `japanese` tokenizer's dictionary configuration as not supported on Cloud ([text index](https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/textindexes), read 2026-10-06).
- **Not run yet:** creating each text index on Cloud. The connection was read-only. [`cloud/tokenizer-check.sql`](cloud/tokenizer-check.sql) does it on a service you own, statement by statement, and drops what it creates. Ask the service owner before running it.

### Not covered

- BM25. It is not in a release: [ClickHouse/ClickHouse#117519](https://github.com/ClickHouse/ClickHouse/pull/117519), a pull request, was open on 2026-10-06.
- A Korean analyser inside ClickHouse.
- Scale. 300 chunks are enough to separate tokenizers by recall, but not to measure latency or hybrid gains. Both are open questions for a larger corpus.

### Author

Ken (ClickHouse Solution Architect) · 2026-10-06

---

## 한국어

ClickHouse 위의 RAG에서 벡터 쪽은 언어를 가리지 않습니다. 한국어 품질은 임베딩 모델이 결정합니다. 언어를
타는 쪽은 키워드 쪽입니다. 그런데 ClickHouse에는 nori나 mecab-ko 같은 한국어 분석기가 없습니다. 이 실습은
한국어 문서 청크에 한국어 질문을 던졌을 때 text index 토크나이저마다 무엇을 맞히고 무엇을 놓치는지 잽니다.
이어서 ClickHouse 밖에서 만든 형태소 컬럼이 얼마나 보태는지, 그 위에 하이브리드 검색이 무엇을 더하는지 잽니다.

앞선 실습 두 개가 일부를 다룹니다.
- [local/releases/26.8](../../local/releases/26.8/)은 문장 하나에서 `asciiCJK`·`chinese`·`icu`의 `tokens()` 결과를 보여 줍니다.
- [usecase/fulltext-search](../fulltext-search/)는 Cloud의 지원 티켓 100만 건에서 조사·띄어쓰기로 잃는 재현율을 잽니다.

이 실습이 더하는 것:
- 정답 청크가 붙은 질문
- Kiwi 형태소 컬럼
- `splitByRegexp`와 `sparseGrams`
- BM25 없는 키워드 순위
- 벡터 검색과 결합(fusion)
- Cloud 확인

**ClickHouse 26.9.11.2에서 검증** (`clickhouse/clickhouse-server:26.9`, 2026-10-06). 00–05단계는
`tools/hol run`으로, 06단계는 손으로 실행했습니다. Kiwi는 kiwipiepy 0.24.0, 모델 0.24.0입니다. 06단계는 Ollama 0.35.0,
`bge-m3`(digest `7907646426…`), 1024차원입니다. 머신은 macOS의 Docker Desktop, CPU 12개, 8 GB입니다.

### 결과

질문 40개, 청크 300개입니다. 순위는 "맞은 질문 토큰 수 ÷ 질문 토큰 수"로 매겼습니다(04단계). 인덱스 크기는 청크 300개
테이블 기준입니다(05단계). body 컬럼 자체는 압축 27.6 KB입니다.

| 키워드 설정 | recall@5 | recall@10 | MRR@10 | 순위 없는 recall@10 | 인덱스 크기 | body 대비 | 인덱스 없이 스캔 (3만 행) |
|---|---:|---:|---:|---:|---:|---:|---:|
| `kiwi` — 형태소, `tokenizer = array` | **0.925** | **0.962** | **0.919** | 0.575 | **16.4 KB** | **0.60** | 6 ms |
| `splitByRegexp` — 조사 제거 정규식 | 0.667 | 0.846 | 0.686 | 0.588 | 22.6 KB | 0.82 | 794 ms |
| `ngrams(2)` | 0.692 | 0.817 | 0.745 | 0.025 | 57.9 KB | 2.10 | 15 ms |
| `ngrams(3)` | 0.704 | 0.767 | 0.707 | 0.375 | 85.1 KB | 3.09 | 16 ms |
| `asciiCJK` | 0.562 | 0.700 | 0.613 | 0.025 | 29.1 KB | 1.06 | 12 ms |
| `sparseGrams` | 0.371 | 0.462 | 0.303 | 0.417 | 227.4 KB | 8.24 | 52 ms |
| `icu('ko')` | 0.346 | 0.450 | 0.359 | 0.338 | 26.4 KB | 0.96 | 70 ms |
| `splitByNonAlpha` | 0.296 | 0.396 | 0.306 | 0.308 | 26.4 KB | 0.96 | 4 ms |

실패 유형별 순위 recall@10 (유형마다 질문 8개):

| 키워드 설정 | 조사 | 띄어쓰기 | 어미 | 한영 혼용 | 1음절 |
|---|---:|---:|---:|---:|---:|
| `kiwi` | 1.000 | 1.000 | 0.812 | 1.000 | 1.000 |
| `splitByRegexp` | 1.000 | 0.500 | 0.854 | 0.875 | 1.000 |
| `ngrams(2)` | 0.812 | 0.875 | 0.750 | 0.896 | 0.750 |
| `ngrams(3)` | 0.812 | 0.750 | 0.500 | 0.958 | 0.812 |
| `asciiCJK` | 0.688 | 0.875 | 0.771 | 0.542 | 0.625 |
| `sparseGrams` | 0.750 | 0.375 | 0.104 | 0.521 | 0.562 |
| `icu('ko')` | 0.062 | 0.375 | 0.250 | 0.938 | 0.625 |
| `splitByNonAlpha` | 0.062 | 0.250 | 0.250 | 0.792 | 0.625 |

인덱스를 쓰면 모든 토크나이저가 3만 행에서 `hasAllTokens(col, '법인카드 분실')`을 2–3 ms에 답하고 800행만 읽습니다.
첫 표의 스캔은 3만 행을 전부 읽습니다. 같은 크기에서 단순 `LIKE` 스캔은 3 ms였습니다. 그래서 이 규모에서는
시간으로는 설정이 갈리지 않고, 읽은 행 수로 갈립니다. 3만 행 테이블은 청크 300개를 100번 반복한 것이라
사전(dictionary)이 커지지 않습니다. 즉 어휘량이 아니라 posting list 읽기를 잰 것입니다. 같은 날 세 번 돌린
결과의 차이는 10% 미만이었습니다.

벡터와 하이브리드 (06단계, 각 목록의 상위 20개를 k = 60인 reciprocal rank fusion으로 결합):

| 방법 | recall@5 | recall@10 | MRR@10 |
|---|---:|---:|---:|
| 벡터만 (`bge-m3`) | **0.979** | **1.000** | **0.975** |
| 하이브리드 벡터 + `kiwi` | 0.962 | 1.000 | 0.966 |
| 하이브리드 벡터 + `ngrams(2)` | 0.892 | 1.000 | 0.870 |
| 키워드 `kiwi` | 0.925 | 0.962 | 0.919 |
| 키워드 `ngrams(2)` | 0.692 | 0.817 | 0.745 |

### 한국어 RAG의 키워드 설정은 무엇으로, 왜

1. **형태소 컬럼을 `tokenizer = array`로 인덱싱합니다.** 적재할 때 한국어 분석기(여기서는 Kiwi)를 돌려
   `morphemes Array(String)`에 저장합니다. 질문의 형태소로 검색하고 겹치는 비율로 순위를 매깁니다.
   - 어미를 뺀 모든 실패 유형에서 가장 좋습니다. recall@5가 가장 높고(0.925) 인덱스는 가장 작습니다(body의 0.6배).
   - 분석기는 ClickHouse 밖에서 돌고, 서버 안은 아무것도 바꾸지 않습니다.
   - `array`는 아래에서 확인한 Cloud 서비스에도 있습니다.
   - 질문 쪽에도 같은 분석기·버전·규칙을 써야 합니다. 그 값은 `lab_meta`에 기록합니다.
2. **분석기를 쓸 수 없으면 `ngrams(2)`에 순위를 매겨 씁니다.**
   - 디스크를 body의 2.1배 쓰고 recall@10은 0.817입니다.
   - 필터로만 쓰면 안 됩니다. 질문 하나에 `hasAnyTokens`가 청크 300개 중 250개를 돌려주므로 순위 없는 recall@10이 0.025입니다.
   - 조사 제거 `splitByRegexp`는 recall@10이 0.846이지만 띄어쓰기에서는 0.5입니다.
   - 이 정규식은 과하게 깎기도 합니다(`사이` → `사`).
   - 토큰화 비용이 가장 큽니다. 인덱스 없이 3만 행을 스캔하는 데 794 ms가 걸립니다.
   - 아래에서 확인한 Cloud 빌드에는 없습니다.
3. **질문 검색에 쓰지 말 것:**
   - `icu('ko')`와 `splitByNonAlpha`는 조사를 단어에 붙인 채 둡니다. 조사 유형의 recall@10이 0.062입니다.
   - `asciiCJK`는 질문마다 300개 중 296개 청크와 맞습니다. 가지치기가 없어서 granule을 38개 중 38개 다 읽습니다.
   - `sparseGrams`는 다음 절을 보세요.
4. **항상 순위를 매깁니다.** 순위 없는 필터링은 recall@10이 0.025–0.588에 머뭅니다.
5. **질문에 `hasAllTokens`를 그대로 쓸 수 없습니다.**
   - 질문의 어미(`하나요`, `어떻게`)가 청크에 없어서, 원문 토크나이저는 모두 아무것도 돌려주지 않습니다.
   - `kiwi`만 0.308이 나옵니다. 규칙이 그런 단어를 버리기 때문입니다.
6. **이 코퍼스에서는 하이브리드가 벡터 검색을 이기지 못했습니다.**
   - `bge-m3` 단독이 이미 recall@10 1.0입니다. `kiwi`와의 하이브리드는 @10에서 같고, @5에서 0.017 낮습니다.
   - 음차 질문 두 개(`아웃룩`/`Outlook`, `팀즈`/`Teams`)도 질문의 나머지 단어 덕분에 키워드로 찾았습니다.
   - 그래서 이 실습이 보여 주는 것은, 키워드 설정에 따라 하이브리드가 얼마나 손해를 보는지입니다(벡터 + `ngrams(2)`는 @5에서 0.892).
   - 하이브리드가 얼마나 얻는지는 보여 주지 못합니다.
   - *가설, 측정 안 함:* 거의 같은 청크가 많은 코퍼스나, 임베딩 모델이 본 적 없는 정확한 식별자가 있는 코퍼스에서 키워드 쪽이 제 몫을 할 것입니다.

### 26.9.11.2에서 의외였던 것

- **`sparseGrams`는 문자열 needle을 구(phrase)처럼 다룹니다.**
  - 문자열 needle은 `compactTokens()`를 거칩니다(`v26.9.11.2-stable`의 `src/Functions/hasAnyAllTokens.cpp:64`).
  - `sparseGrams`는 이 단계에서 더 긴 gram에 들어 있는 gram을 모두 버립니다(`src/Interpreters/ITokenizer.cpp:677`).
  - `hasAllTokens`에는 맞는 처리입니다. 하지만 `hasAnyTokens(col, '<질문>')`은 가장 긴 gram만 찾게 되어 구 검색처럼 동작합니다.
  - 질문 1은 `tokens()` 기준으로 청크 97개와 gram을 공유합니다. 그런데 인덱스는 `나요?` 하나만 맞은 청크 1개를 돌려줬습니다.
  - 03단계도 같은 압축을 적용합니다. 압축을 빼면 positive control(48행, 토크나이저 8종 전부)이 단계를 실패시킵니다.
  - `sparseGrams`는 최소 길이가 3이라 `tokens('결재', 'sparseGrams')`는 `[]`입니다.
- **컬럼 하나에 text index는 하나만 됩니다.** 두 번째는 Code 36(`Column b must not have more than one text index`)으로 실패합니다. 그래서 02단계는 body의 `MATERIALIZED` 사본마다 인덱스를 만듭니다.
- **needle은 상수여야 합니다.**
  - join으로 들어온 컬럼은 Code 44로 거부됩니다.
  - scalar subquery `(SELECT question FROM queries WHERE qid = 1)`는 받아들여지고 인덱스도 탑니다.
  - 그래서 03–04단계는 토큰 배열을 비교하고, 03단계가 그 결과를 인덱스와 대조합니다.
- **26.8의 관찰은 26.9에서도 그대로입니다.** `asciiCJK`는 한 음절씩 쪼개고, `icu`는 조사를 붙여 둡니다. 로캘(`ko`, `ko_KR`, `en`, `ja`)은 결과를 바꾸지 않습니다.

### 데이터

데이터는 모두 실습 안에 있어서, T0 실행에는 Python도 네트워크도 필요 없습니다.

- `data/chunks.jsonl`: 가상 회사의 문서 27개에서 나온 청크 300개.
  - 사내 규정: 재택근무, 휴가, 출장, 법인카드, 구매, 결재, 보안.
  - IT 헬프데스크: VPN, Outlook, SSO, Teams, ERP 오류 코드, 기기.
- `data/queries.jsonl`: 직원이 헬프데스크 봇에 묻듯 쓴 질문 40개.
  - 실패 유형마다 8개이고, 질문마다 정답 청크(qrels) 2–3개와 함정을 적은 `note`가 있습니다.
  - **조사**: 질문은 `결재선을`, 청크는 `결재선은` / `결재선이`.
  - **띄어쓰기**: `구매 요청서` 대 `구매요청서`, 그리고 그 반대.
  - **어미**: `잠겼어요` 대 `계정 잠금` / `잠긴 계정`.
  - **한영 혼용**: 소문자 코드, 조사가 붙은 영어(`VPN이`), 오류 코드(`ERP-4012`, `0x80070005`), 음차(`아웃룩` 대 `Outlook`).
  - **1음절**: `키`, `망`, `폰`, `앱`, `차`, `층`, `팀`, `표`.
  - 질문마다 hard negative도 있습니다. 핵심어는 같지만 다른 것을 답하는 청크입니다.
- 텍스트는 이 실습을 위해 AI 모델로 초안을 쓴 합성 데이터입니다.
  - 정답 청크를 질문에 맞춰 썼으므로 qrels는 구성상 정해집니다.
  - 스크립트로 확인한 것: 모든 정답 청크에서 함정이 성립하는지, id가 연속인지, 유형마다 질문이 8개인지.
  - 일부는 사람이 직접 읽었습니다.
- `gen_data.py`가 Kiwi를 한 번 돌려 `00-data.sql`을 쓰고, 이 파일을 커밋합니다.
  - 규칙: 태그 `NNG NNP NR SL SN SH XR VV VA`(`-` 앞부분)만 남기고 소문자로 바꾼 뒤 `하 되 있 어떻`을 버립니다.
  - 일부러 단순하게 두었습니다. 예를 들어 `그렇`, `없`은 남습니다.
  - 다시 만들려면 `uv run usecase/korean-rag-tokenizers/gen_data.py`를 실행합니다. 입력이 같으면 바이트까지 같은 파일이 나옵니다.

### 단계

| 파일 | Tier | 내용 |
|---|---|---|
| `00-data.sql` | T0 | 생성 파일: `chunks_src`, `queries`, `phrases`, `lab_meta` |
| `01-tokens.sql` | T0 | 실패 유형 문구 11개에 토크나이저 8종의 `tokens()`; 26.8 재확인; `sparseGrams` 최소 길이; 상수 needle |
| `02-schema.sql` | T0 | `chunks`: body, 각자 text index(`preprocessor = lower(...)`)를 가진 `MATERIALIZED` 사본 7개, `tokenizer = array`인 `morphemes`; 300행에서도 가지치기가 보이도록 `index_granularity = 8` |
| `03-recall.sql` | T0 | `hasAny` / `hasAll` 필터링: 토크나이저·실패 유형별 재현율, 정밀도, 돌려준 청크 수; 인덱스 대조 positive control(48행, 하나라도 다르면 단계 실패) |
| `04-ranking.sql` | T0 | 맞은 토큰 ÷ 질문 토큰 순위: recall@5/@10, MRR@10, 순위 없는 기준선, 실패 유형별; 06단계용 `keyword_ranked` |
| `05-index-cost.sql` | T0 | 인덱스 바이트, 고유 토큰 수, 읽은 granule(`EXPLAIN indexes = 1`), 3만 행에서 인덱스 유무별 지연과 읽은 행 |
| `t1/06-hybrid.sh` + `t1/06-hybrid.sql` | T1 | 로컬 Ollama로 `aiEmbed`, `vector_similarity` HNSW 인덱스, 정확한 상위 20개, `kiwi`·`ngrams(2)` 목록과의 RRF |
| `cloud/tokenizer-check.sql` | 수동 | ClickHouse Cloud 서비스가 `tokens()`와 text index로 받는 토크나이저; 만든 것은 지움 |

`t1/`과 `cloud/`는 `tools/hol`이 실행하는 최상위 `NN-*.sql` 밖에 있어서, 00–05단계는 T0로 남습니다.

### 실행

```bash
python3 tools/hol run usecase/korean-rag-tokenizers
```

단계별 출력을 보려면 컨테이너를 남기고 단계를 다시 넣습니다.

```bash
python3 tools/hol run usecase/korean-rag-tokenizers --keep
docker exec -i hol-usecase-korean-rag-tokenizers clickhouse-client --multiline --multiquery < usecase/korean-rag-tokenizers/04-ranking.sql
```

06단계에는 호스트의 Ollama와 받아 둔 모델이 필요합니다.

```bash
ollama pull bge-m3
```

그다음 남겨 둔 컨테이너에 대해 실행합니다.

```bash
usecase/korean-rag-tokenizers/t1/06-hybrid.sh
```

스크립트가 하는 일:
- 컨테이너, 04단계 테이블, Ollama, 모델을 확인하고 Ollama 버전과 모델 digest를 출력합니다.
- users.d 파일로 컨테이너의 `default` 사용자에게 `named_collection_control`을 줍니다. 이게 없으면 hol 컨테이너에는 `CREATE NAMED COLLECTION` 권한이 없습니다.
- 그다음 `06-hybrid.sql`을 실행합니다.
- SQL은 Ollama에 `host.docker.internal:11434`로 접속합니다. Docker Desktop이 이 이름을 제공합니다. Linux에서는 `--add-host=host.docker.internal:host-gateway`를 더해야 합니다(테스트 안 함).

```bash
python3 tools/hol down usecase/korean-rag-tokenizers
```

### 한국어를 깨뜨리는 프레임워크 기본값 두 가지

2026-10-06에 26.9.11.2에서 별도 환경과 mock 임베딩으로 재현했습니다.

**LlamaIndex** — `llama-index-vector-stores-clickhouse` 0.8.0 (llama-index-core 0.14.25, clickhouse-connect 1.9.0).

키워드를 찾는 방식:
- HYBRID와 TEXT_SEARCH는 `_build_text_search_statement` / `_build_hybrid_search_statement`에서 만든 정규식으로 키워드를 찾습니다.
- `base.py:351`이 `multiMatchAllIndices`용으로 `\b(?i)<token>\b`를 만듭니다.
- `\b`는 ASCII 단어 경계라서 한글 키워드는 절대 맞지 않습니다. 26.9.11.2에서 `match('클릭하우스 테스트', '\\b(?i)클릭하우스\\b')`는 0이고, 영어로 같은 식을 쓰면 1입니다.
- text index는 만들지 않습니다. 키워드 경로는 정규식 스캔입니다.

어떻게 깨지는가:
- **TEXT_SEARCH는 죽습니다.** 맞는 행이 없으면 `base.py:516`이 `ValueError: tuple.index(x): x not in tuple`을 던집니다.
- **HYBRID는 한글 키워드를 조용히 무시합니다.**
- **두 번째 항은 영어에서도 깨져 있습니다.** `base.py:360`은 SQL 리터럴에 `\b`를 하나만 쓰는데, ClickHouse는 이를 백스페이스로 읽습니다(`hex('\b')` = `08`). 그래서 `countMatches`는 항상 0입니다.

생성자 옵션은 없습니다. 하위 클래스에서 두 빌더를 덮어씁니다. 코드는 위 English 절과 같습니다.

덮어쓴 뒤의 동작:
- 부분 문자열 일치로 `클릭하우스는 빠르다`에서 `클릭하우스`를 찾습니다.
- 맞는 것이 없는 질의는 여전히 위의 `ValueError`를 던지므로, `query()`를 감싸서 잡습니다.
- text index를 쓰려면 이 실습처럼 인덱싱한 컬럼에 `WHERE hasAnyTokens(text, '<질의>')`를 더합니다.

**LangChain** — `langchain-community` 0.4.2 (`langchain_community/vectorstores/clickhouse.py`).

기본 인덱스:
- `ClickhouseSettings.index_type`의 기본값은 `"annoy"`(78행)이고, `index_param = ["'L2Distance'", 100]`(80행)입니다.
- ClickHouse는 25.5에서 `annoy`를 없앴습니다. 그래서 26.9에서는 생성자가 다음 오류로 실패합니다.
  `Code: 80. DB::Exception: Unknown Index type 'annoy'. Available index types: hypothesis, text, vector_similarity, …`

두 설정을 함께 바꿉니다. `index_type=None`(ANN 인덱스 없이 정확한 스캔)으로 두거나,
`index_type="vector_similarity", index_param=["'hnsw'", "'L2Distance'", DIM]`으로 둡니다. 차원은 `index_param` 안에 넣습니다.

주의할 점:
- **거리 함수는 L2Distance여야 합니다.** 스토어의 검색이 `L2Distance`로 고정되어 있어서(582행), `cosineDistance`로 만든 인덱스는 쓰이지 않습니다.
- **`index_type`만 바꾸면 실패합니다.** `Vector similarity index must have three or six arguments` 오류가 납니다.
- **`index_query_params`는 깨져 있습니다.** `SETTINGS` 대신 `SETTING`을 내보냅니다(576행). 그 문법 오류는 삼켜지고 검색은 `[]`를 돌려줍니다.
- **`langchain-community`는 지원 종료 예정이라고 경고합니다.** PyPI의 `langchain-clickhouse` 0.1.0은 인덱스 옵션이 없는 서드파티 패키지이고, 후속 패키지가 아닙니다.

### ClickHouse Cloud

2026-10-06에 **26.6.1.2292** Cloud 서비스에서 `mcp-clickhouse`로 읽기 전용 확인을 했습니다.

토크나이저:
- `system.tokenizers`에는 `ngrams`, `splitByNonAlpha`, `sparseGrams`, `array`, `splitByString`, `asciiCJK`, `unicodeWord`(와 bloom filter 이름)가 있습니다. `icu`, `chinese`, `japanese`, `splitByRegexp`는 없습니다.
- 이 실습의 토크나이저 중 목록에 있는 다섯 가지는 `tokens()`가 동작합니다. 그 빌드에서 `tokens(…, 'icu', 'ko')`와 `tokens(…, 'splitByRegexp', …)`는 Code 42로 실패합니다.
- 그 서비스에는 `splitByNonAlpha`, `array`, `ngrams(2)` text index가 이미 있습니다.
- 그래서 위에서 권장한 두 설정 `kiwi`와 `ngrams(2)`는 그 서비스에서 쓸 수 있습니다.

임베딩:
- `aiEmbed`는 그 서비스의 `system.functions`에 있지만 `allow_experimental_ai_functions`가 0입니다.
- 문서는 AI 함수를 지금은 Cloud 서비스에서 쓸 수 없다고 적고 있습니다([AI functions](https://clickhouse.com/docs/reference/functions/regular-functions/ai-functions), 2026-10-06 확인).
- Cloud에서는 애플리케이션이 임베딩을 만들어 `Array(Float32)`로 넣습니다. 06단계의 `vector_similarity` 부분은 그대로입니다.

그 밖에:
- 문서는 `japanese` 토크나이저의 사전 설정을 Cloud 미지원으로 표시합니다([text index](https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/textindexes), 2026-10-06 확인).
- **아직 실행 안 한 것:** Cloud에서 text index를 토크나이저마다 만들어 보기. 연결이 읽기 전용이었습니다. [`cloud/tokenizer-check.sql`](cloud/tokenizer-check.sql)이 본인 서비스에서 문장별로 이 확인을 하고 만든 것을 지웁니다. 실행 전에 서비스 소유자에게 묻습니다.

### 다루지 않는 것

- BM25. 릴리스에 없습니다. 풀 리퀘스트 [ClickHouse/ClickHouse#117519](https://github.com/ClickHouse/ClickHouse/pull/117519)는 2026-10-06에 열려 있었습니다.
- ClickHouse 안의 한국어 분석기.
- 규모. 청크 300개로 재현율 기준의 토크나이저 차이는 갈리지만, 지연이나 하이브리드의 이득은 잴 수 없습니다. 둘 다 더 큰 코퍼스에서 열린 질문입니다.

### 작성자

Ken (ClickHouse Solution Architect) · 2026-10-06
