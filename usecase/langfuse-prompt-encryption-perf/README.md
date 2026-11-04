# What encrypting Langfuse prompts in ClickHouse costs (UDF, KMS, codec)

[English](#english) | [한국어](#한국어)

---

## English

**Verified end to end on 2026-11-04** against ClickHouse 26.8.22.13 (OSS, plus Python 3.10.12 and `cryptography` 3.4.8 for the executable UDFs), OpenBao 2.7.2 as the KMS, and Langfuse 4.56.0 with an Enterprise licence from the [langfuse-hols](https://github.com/litkhai/langfuse-hols) v4 stack (for the end-to-end run). Host: Apple M4 Pro, 12 CPU, macOS 26.7.2; Docker 29.9.2 (16 GiB VM), Compose 5.6.1. The bench ClickHouse had 8 CPU and 10 GiB, OpenBao 2 CPU. `01` passed 8 checks, `06` 7, `08` 3. Every number below is from one run on a laptop; read them as ratios between methods, not as capacity.

A regulated team asked: if prompts and outputs must be encrypted with the organisation's key (Azure Key Vault in their case), and the encryption is done in ClickHouse with UDFs, how much slower does Langfuse get? This lab measures that with Langfuse's own `events_full` schema, Langfuse-shaped writes and reads, and a real Langfuse in front.

### First: ClickHouse cannot encrypt Langfuse's column in place

Langfuse writes `input`/`output` into `events_full` and reads the same columns back (the UI, the public API, evaluations), and a materialized view copies `leftUTF8(input, 200)` into `events_core` for list pages. For ClickHouse to encrypt on write and decrypt on read, the same column name would have to accept plaintext on INSERT and return plaintext on SELECT while storing ciphertext. [08-in-place-probe.sh](08-in-place-probe.sh) shows that neither column kind does it: an `ALIAS` column cannot be inserted into, and an `EPHEMERAL` column cannot be selected (both `Code: 16`). A materialized view can encrypt, but only into another table, which Langfuse does not read. So the methods that can be wired into Langfuse are:

- **Encrypt before ClickHouse**: the SDK masking hook ([an earlier lab](https://github.com/litkhai/langfuse-hols/tree/main/labs/v4/langfuse-ee), step 14) or Langfuse EE's ingestion callback (measured here, `cb_*`). Langfuse then stores and shows ciphertext; decryption happens outside Langfuse (see [usecase/langfuse-decryption-audit](../langfuse-decryption-audit/)). A ClickHouse UDF can decrypt for people who query ClickHouse directly.
- **Encrypt below the column**: the `AES_256_GCM_SIV` column codec, or disk/storage encryption. Transparent to Langfuse, but anyone with `SELECT` sees plaintext.

The ClickHouse-side UDF numbers below (`sql`, `local`, `kms_*`) are the cost of that encrypt/decrypt work on Langfuse-shaped data, written through a Null table + materialized view and read with the decrypt function in the query.

### Methods

| Label | What runs | Key handling |
|---|---|---|
| `plain` | Langfuse's schema as is (`input`/`output` `ZSTD(3)`, text indexes on `lower(input)`/`lower(output)`) | — |
| `plain_nofts` | same without the two text indexes (the fair baseline for ciphertext, which cannot use them) | — |
| `codec` | `CODEC(ZSTD(3), AES_256_GCM_SIV)` on `input`/`output` | key in server config (`from_env`) |
| `sql` | SQL UDF over built-in `encrypt()`/`decrypt()`, AES-256-GCM | key written into the function definition |
| `local` | executable UDF (Python), AES-256-GCM in process | **envelope**: data key unwrapped once from the KMS at process start |
| `kms_batch` | executable UDF, the KMS encrypts: one Transit call per ≤256 values / 4 MiB | key never leaves the KMS |
| `kms_row` | one KMS call per value | key never leaves the KMS |
| `…5` / `cb_kms_row5` | the same + 5 ms sleep per KMS call, standing in for a network round trip | simulation |
| `cb_local`, `cb_kms_batch`, `cb_kms_row5` | Langfuse EE ingestion callback ([bench/enc_callback.py](bench/enc_callback.py)) encrypts `langfuse.observation.input/output` before Langfuse writes them; `FAIL_CLOSED=true`, timeout 500 ms | as above |

Data ([02-load.sh](02-load.sh)): 400,000 observations (100,000 traces × 4) over 7 days in Langfuse 4.56.0's `events_full` DDL; prompts are chat-style JSON, 512 / 2,000 / 8,000 / 32,000 characters at 30 / 40 / 22 / 8 %, Korean and English words drawn skewed. 3.43 GiB of input, 0.59 GiB of output, average input 9,192 bytes; `ZSTD(3)` compresses it 4.0×, about like real prompt text.

### Results

**W1 — bulk write** ([03-write-bulk.sh](03-write-bulk.sh), all 400,000 rows except `kms_row` 20,000 and `kms_row5` 4,000). CPU is the ClickHouse container's cgroup (UDF child processes included) plus OpenBao, for the insert and the merges that follow.

| Method | CPU µs per row | vs `plain_nofts` | `input`+`output` on disk | Skip indexes |
|---|---|---|---|---|
| plain_nofts | 160 | 1.00 | 1,026 MiB | 2 MiB |
| plain (Langfuse as is) | 262 | 1.63 | 1,026 MiB | 17 MiB |
| codec | 244 | 1.52 (≈ plain) | 1,026 MiB | 17 MiB |
| sql | 206 | 1.28 | 4,135 MiB | 2 MiB |
| local | 459 | 2.86 | 4,135 MiB | 2 MiB |
| kms_batch | 454 (144 in the KMS) | 2.83 | 4,138 MiB | 2 MiB |
| kms_batch5 | 591 | 3.68 | 4,138 MiB | 2 MiB |
| kms_row | 800 (395 in the KMS) | 4.98 | — | — |
| kms_row5 | 2,475; 155 rows/s | 15.4 | — | — |
| sql with Langfuse's text indexes kept | 1,219 | 7.6 | 4,135 MiB | **5,718 MiB** |

- Ciphertext does not compress: **4.0× the disk** for the prompt columns (2.6 KB → 10.6 KB per observation).
- Keeping Langfuse's text indexes over ciphertext builds an index of random base64 tokens larger than the data, and costs 7.6× the CPU. Drop `idx_fts_input_low`/`idx_fts_output_low` if values are encrypted; they find nothing anyway. The first run of this lab, with the default 8-minute `old_parts_lifetime`, filled the host disk (the bench volume reached 79 GB).
- Memory: the `sql` and `local` inserts peaked at 3.3–3.5 GiB against 1.5–1.8 GiB for plaintext, merges at 1.5 GiB against 1.3 GiB, and 2.7 GiB with the text indexes over ciphertext. With `max_block_size` 8192 the `sql` insert went past an 8 GiB container; the bench uses 2048 and 10 GiB.

**W2 — Langfuse-sized inserts** ([04-write-small.sh](04-write-small.sh)): one INSERT = one trace = 4 observations, open loop, 30 s; encryption through a Null table + materialized view.

| Method | 67 traces/s (≈ 4,000/min): p50 / p95 ms | 267 traces/s: achieved, p50 ms |
|---|---|---|
| plain | 126 / 222 | 266 /s, 146 (repeat: 264 /s, 165) |
| codec | 127 / 223 | 266 /s, 146 |
| sql | 130 / 225 | 234 /s, 223 (repeat: 263 /s, 214) |
| local | 135 / 228 | 265 /s, 148 (repeat: 266 /s, 147) |
| kms_batch | 139 / 234 | 235 /s, 241 (repeat: 213 /s, 299) — falls behind |
| kms_batch5 | 153 / 249 | 265 /s, 184 |
| kms_row | 168 / 266 | **151 /s**, 413 — falls behind |
| kms_row5 | **776** / 882 | **19 /s**, 3,514 — collapses |

**R — reads** ([05-read.sh](05-read.sh)), clickhouse-benchmark, 20 s per cell, queries drawn from 100 variants. p50 in ms (errors in brackets). `detail` = one trace with full input/output; `list` = newest 50 of a day with 200-character previews (plain and codec read the preview table as Langfuse does; ciphertext previews are useless, so encrypted methods decrypt `events_full`); `search` = Langfuse's own match predicate over one day; `export` = all of a day decrypted; `agg` = cost/latency by model, no prompt column.

| Method | detail c=4 | list c=4 | search c=1 | search c=4 | export c=1 | export c=4 | agg c=4 |
|---|---|---|---|---|---|---|---|
| plain | 33 | 5 | 400 | 418 | 486 | 485 | 18 |
| plain without index (search) | — | — | 574 | 527 | — | — | — |
| codec | 37 | 7 | 582 | 560 | 694 | 668 | 17 |
| sql | 46 | 35 | 2,138 | 13,842 (2) | 1,330 | 1,811 | 14 |
| local | 27 | 44 | 9,361 | 22,542 (2) | 5,038 | 6,519 | 16 |
| kms_batch | 40 | 68 | 10,661 | 31,313 (1) | 10,791 | 15,471 | 14 |
| kms_batch5 | 56 | 78 | 14,532 | **OOM-kill** | 15,309 | — | 15 |
| kms_row | 45 | 93 | — | — | — | — | — |
| kms_row5 | 89 | 638 | — | — | — | — | — |

- One trace: encryption hardly shows. A list page: 7–9× slower with a local key, 14–19× through the KMS, ~130× with a KMS call per value and a 5 ms round trip. Whole-day work (search, export, evaluation): 3–36× slower at concurrency 1 and up to 75× at 4, and full-text search loses its index.
- **Memory.** At concurrency 16, whole-day search failed on query memory for plaintext too (7 of 285), and for `sql` nearly all (85 of 86). The executable-UDF methods are worse: **their Python processes' memory is outside ClickHouse's memory limit, so the container was OOM-killed** (`local` search at 16, `kms_batch5` search at 4) and the server restarted, instead of one query failing.

**E1 — through a real Langfuse** ([07-langfuse-e2e.sh](07-langfuse-e2e.sh)): OTLP/HTTP into Langfuse 4.56.0 EE, one request = one trace of 4 spans with the same prompts; lag = `events_full.created_at` − span start.

| Variant | 67 traces/s, 120 s: arrived, lag p95 | 200 traces/s, 60 s: arrived, lag p95 |
|---|---|---|
| plain | 32,160 / 32,160, 0.15 s | 48,000 / 48,000, 0.67 s |
| codec | 32,160 / 32,160, 0.10 s | — |
| cb_local | 32,160 / 32,160 (all encrypted), 0.29 s | 48,000 / 48,000, **26 s** backlog |
| cb_kms_batch | 32,160 / 32,160, 0.38 s | 48,000 / 48,000, **30 s** |
| cb_kms_row5 | 32,160 / 32,160, 0.44 s | 48,000 / 48,000, **107 s** |

No event was lost and none was stored in clear in any callback run. At about 4,000 traces a minute the encrypting callback adds a fraction of a second; at 3× that, one worker on this laptop falls behind. Langfuse's ClickHouse used 2–3× the CPU with ciphertext (84–124 s against 41 s at 67/s), mostly for the text indexes over random tokens.

### KMS calls against Azure Key Vault's limits

Azure Key Vault allows 4,000 "all other" key transactions per 10 seconds per vault and region for software RSA-2048 and EC keys, 2,000 for HSM keys ([service limits](https://learn.microsoft.com/en-us/azure/key-vault/general/service-limits), read 2026-11-04), and answers HTTP 429 beyond. Its Encrypt operation handles a single block, intended for wrapping keys ([Encrypt](https://learn.microsoft.com/en-us/rest/api/keyvault/keys/encrypt/encrypt)), and has no batch form — so the `kms_batch` pattern exists for Vault-style KMSs, not for Key Vault.

- At 4,000 traces per minute with 4 observations and 2 fields each, a call per value is 533 encrypt calls per second: above the 400/s (software) and 200/s (HSM) per vault, before any read.
- Reads add to that: a trace page 8 decrypts, a list page 100, one day's export at that rate (5.76 M traces) about 46 M — 32 hours at 400/s.
- With envelope encryption (`local`, `cb_local`) the KMS is called when a process starts or the data key rotates: a handful of calls a day.

### Where plaintext still is ([06-codec-leak.sh](06-codec-leak.sh))

- With `AES_256_GCM_SIV`, `input.bin` cannot be decompressed without the key, but **the text index dictionary holds the prompt words in clear** (front-coded: `rx77refund` is stored as `r` + `x77refund`), byte-identical to the plaintext table's. ClickHouse's docs say indexes are written without the column codec. Drop the text indexes if this matters.
- A search value appears in `system.query_log` in clear.
- The UDF ciphertext table without text indexes holds the marker in no file.

### Run

```bash
cd usecase/langfuse-prompt-encryption-perf
./01-up.sh            # .env and .secrets, OpenBao Transit key + wrapped data key, ClickHouse with UDFs; round trips
./02-load.sh          # 400k synthetic observations in Langfuse's events_full schema (TRACES=100000)
./03-write-bulk.sh    # W1, ~15 min; results/w1-bulk.tsv, results/w1-storage.tsv
./06-codec-leak.sh    # plaintext on disk and in query_log
./05-read.sh          # R, ~60 min; results/r-read.tsv (CONC="1 4 16", TIME=20)
./04-write-small.sh   # W2, ~10 min; results/w2-small.tsv
./07-langfuse-e2e.sh  # E1, ~20 min; needs the langfuse-hols v4 stack with an EE licence; restores it at the end
./08-in-place-probe.sh
./99-down.sh [--purge]
```

Disk: about 25 GB in the bench volume at peak; keep 40 GB free. `07` changes the Langfuse stack (EE overlay, codec on `events_full`/`events_core`, the callback) and puts it back: OSS mode, original codecs, rows tagged `bench_run` deleted; `07-langfuse-e2e.sh --restore-only` does that again after an interrupted run.

### Not covered

- A real Azure Key Vault (no spending): its latency is modelled as 5 ms per call; its limits come from the docs.
- Production sizing: one laptop, one worker, one ClickHouse; numbers are ratios.
- Langfuse's UI and evaluations with ciphertext: covered in the regulated-controls article (search finds nothing, LLM judges score 0).
- Decrypting inside Langfuse's own queries: not possible without changing Langfuse.

### Files

| File | What |
|---|---|
| [docker-compose.yml](docker-compose.yml) | bench ClickHouse (built from [docker/Dockerfile](docker/Dockerfile)) and OpenBao |
| [clickhouse/user_scripts/prompt_crypto.py](clickhouse/user_scripts/prompt_crypto.py) | executable UDF body: `local`, `kms_batch`, `kms_row`, optional round-trip delay |
| [clickhouse/udf/prompt_crypto.xml](clickhouse/udf/prompt_crypto.xml) | the 10 executable UDFs (`executable_pool`, `send_chunk_header`) |
| [clickhouse/config.d/prompt-enc.xml](clickhouse/config.d/prompt-enc.xml) | codec key from the environment, UDF config path, `old_parts_lifetime` 10 s |
| [sql/events_full.langfuse-4.56.0.sql](sql/events_full.langfuse-4.56.0.sql) | Langfuse's DDL, taken from a running 4.56.0 |
| [sql/generate.sql](sql/generate.sql) | the synthetic observations |
| [bench/small_insert.py](bench/small_insert.py), [bench/otlp_load.py](bench/otlp_load.py) | open-loop load generators (ClickHouse HTTP, Langfuse OTLP) |
| [bench/enc_callback.py](bench/enc_callback.py) | the encrypting ingestion callback |
| [docker-compose.langfuse.yml](docker-compose.langfuse.yml), [docker-compose.langfuse-callback.yml](docker-compose.langfuse-callback.yml) | overlays for the langfuse-hols stack |
| `results/*.tsv` | the measurements of 2026-11-04 (raw logs are not committed) |

---

## 한국어

**2026-11-04에 처음부터 끝까지 검증**했습니다. ClickHouse 26.8.22.13(OSS, executable UDF용으로 Python 3.10.12와 `cryptography` 3.4.8 추가), KMS 역할의 OpenBao 2.7.2, 끝에서 끝 실행에는 [langfuse-hols](https://github.com/litkhai/langfuse-hols) v4 스택의 Langfuse 4.56.0(Enterprise 라이선스) 기준입니다. 호스트는 Apple M4 Pro, 12 CPU, macOS 26.7.2이고 Docker 29.9.2(VM 16 GiB), Compose 5.6.1입니다. 측정용 ClickHouse는 8 CPU / 10 GiB, OpenBao는 2 CPU입니다. `01`은 확인 8개, `06`은 7개, `08`은 3개를 통과했습니다. 아래 숫자는 모두 노트북 한 대에서 한 번 잰 값입니다. 용량이 아니라 방식 사이의 비율로 읽어 주세요.

규제를 받는 팀이 물었습니다. prompt와 출력을 조직의 키(이 경우 Azure Key Vault)로 암호화해야 하고, 그 암호화를 ClickHouse UDF로 한다면 Langfuse가 얼마나 느려지는가. 이 실습은 Langfuse의 `events_full` 스키마 그대로, Langfuse와 같은 모양의 쓰기와 읽기로, 그리고 실제 Langfuse를 앞에 두고 그것을 잽니다.

### 먼저: ClickHouse는 Langfuse의 컬럼을 그 자리에서 암호화할 수 없다

Langfuse는 `events_full`의 `input`/`output`에 쓰고 같은 컬럼을 다시 읽습니다(화면, public API, 평가). 목록 화면용으로는 materialized view가 `leftUTF8(input, 200)`을 `events_core`에 복사합니다. ClickHouse가 쓸 때 암호화하고 읽을 때 복호화하려면, 같은 이름의 컬럼이 INSERT에서는 평문을 받고 SELECT에서는 평문을 돌려주면서 저장은 암호문으로 해야 합니다. [08-in-place-probe.sh](08-in-place-probe.sh)에서 보듯 어떤 컬럼 종류도 그렇게 하지 못합니다. `ALIAS` 컬럼에는 INSERT할 수 없고, `EPHEMERAL` 컬럼은 SELECT할 수 없습니다(둘 다 `Code: 16`). materialized view는 암호화할 수 있지만 다른 테이블로만 쓰고, Langfuse는 그 테이블을 읽지 않습니다. 그래서 Langfuse에 연결할 수 있는 방식은 둘입니다.

- **ClickHouse 앞에서 암호화**: SDK masking hook([이전 실습](https://github.com/litkhai/langfuse-hols/tree/main/labs/v4/langfuse-ee) 14단계) 또는 Langfuse EE의 수집 callback(여기서 `cb_*`로 측정). Langfuse는 암호문을 저장하고 보여 줍니다. 복호화는 Langfuse 밖에서 합니다([usecase/langfuse-decryption-audit](../langfuse-decryption-audit/) 참고). ClickHouse에 직접 쿼리하는 사람에게는 ClickHouse UDF로 복호화할 수 있습니다.
- **컬럼 아래에서 암호화**: `AES_256_GCM_SIV` 컬럼 코덱이나 디스크·저장소 암호화. Langfuse에는 투명하지만 `SELECT` 권한이 있으면 평문이 보입니다.

아래 ClickHouse 쪽 UDF 숫자(`sql`, `local`, `kms_*`)는 Langfuse 모양의 데이터에서 그 암호화·복호화가 드는 비용입니다. 쓰기는 Null 테이블 + materialized view로, 읽기는 쿼리에 복호화 함수를 넣어 쟀습니다.

### 방식

| 이름 | 하는 일 | 키 |
|---|---|---|
| `plain` | Langfuse 스키마 그대로(`input`/`output` `ZSTD(3)`, `lower(input)`/`lower(output)` 텍스트 인덱스) | — |
| `plain_nofts` | 텍스트 인덱스 둘을 뺀 것(인덱스를 쓸 수 없는 암호문과 공정하게 비교하는 기준) | — |
| `codec` | `input`/`output`에 `CODEC(ZSTD(3), AES_256_GCM_SIV)` | 서버 설정의 키(`from_env`) |
| `sql` | 내장 `encrypt()`/`decrypt()`를 쓰는 SQL UDF, AES-256-GCM | 함수 정의 안에 키 |
| `local` | executable UDF(Python), 프로세스 안에서 AES-256-GCM | **envelope**: 프로세스 시작 때 KMS로 데이터 키를 한 번 풂 |
| `kms_batch` | executable UDF, KMS가 암호화: 값 256개 / 4 MiB마다 Transit 호출 1번 | 키가 KMS 밖으로 나오지 않음 |
| `kms_row` | 값마다 KMS 호출 1번 | 키가 KMS 밖으로 나오지 않음 |
| `…5` / `cb_kms_row5` | 위와 같고 KMS 호출마다 5 ms 대기(네트워크 왕복을 흉내) | 시뮬레이션 |
| `cb_local`, `cb_kms_batch`, `cb_kms_row5` | Langfuse EE 수집 callback([bench/enc_callback.py](bench/enc_callback.py))이 Langfuse가 쓰기 전에 `langfuse.observation.input/output`을 암호화. `FAIL_CLOSED=true`, timeout 500 ms | 위와 같음 |

데이터([02-load.sh](02-load.sh)): Langfuse 4.56.0의 `events_full` DDL에 7일 동안의 observation 40만 개(trace 10만 × 4). prompt는 채팅 형식 JSON이고 길이는 512 / 2,000 / 8,000 / 32,000자가 30 / 40 / 22 / 8 %입니다. 한국어와 영어 단어를 치우치게 뽑았습니다. input 3.43 GiB, output 0.59 GiB, input 평균 9,192바이트이고 `ZSTD(3)`로 4.0배 압축됩니다. 실제 prompt 텍스트와 비슷한 수준입니다.

### 결과

**W1 — 대량 쓰기** ([03-write-bulk.sh](03-write-bulk.sh), `kms_row` 2만 행과 `kms_row5` 4천 행을 빼면 40만 행 전부). CPU는 ClickHouse 컨테이너 cgroup(UDF 자식 프로세스 포함)과 OpenBao의 합이고, insert와 이어지는 merge를 함께 셌습니다.

| 방식 | 행당 CPU µs | `plain_nofts` 대비 | `input`+`output` 디스크 | 스킵 인덱스 |
|---|---|---|---|---|
| plain_nofts | 160 | 1.00 | 1,026 MiB | 2 MiB |
| plain(Langfuse 그대로) | 262 | 1.63 | 1,026 MiB | 17 MiB |
| codec | 244 | 1.52(≈ plain) | 1,026 MiB | 17 MiB |
| sql | 206 | 1.28 | 4,135 MiB | 2 MiB |
| local | 459 | 2.86 | 4,135 MiB | 2 MiB |
| kms_batch | 454(KMS에서 144) | 2.83 | 4,138 MiB | 2 MiB |
| kms_batch5 | 591 | 3.68 | 4,138 MiB | 2 MiB |
| kms_row | 800(KMS에서 395) | 4.98 | — | — |
| kms_row5 | 2,475, 초당 155행 | 15.4 | — | — |
| Langfuse 텍스트 인덱스를 둔 sql | 1,219 | 7.6 | 4,135 MiB | **5,718 MiB** |

- 암호문은 압축되지 않습니다. prompt 컬럼 **디스크가 4.0배**입니다(observation당 2.6 KB → 10.6 KB).
- Langfuse 텍스트 인덱스를 암호문 위에 그대로 두면 무작위 base64 토큰의 인덱스가 데이터보다 커지고 CPU는 7.6배가 됩니다. 값을 암호화한다면 `idx_fts_input_low`/`idx_fts_output_low`를 지웁니다. 어차피 아무것도 찾지 못합니다. 이 실습의 첫 실행은 기본 `old_parts_lifetime` 8분으로 돌다가 호스트 디스크를 채웠습니다(측정 볼륨 79 GB).
- 메모리: `sql`과 `local` insert는 최대 3.3–3.5 GiB(평문 1.5–1.8 GiB), merge는 1.5 GiB(평문 1.3 GiB), 암호문 위에 텍스트 인덱스를 두면 2.7 GiB였습니다. `max_block_size` 8192에서는 `sql` insert가 8 GiB 컨테이너를 넘어서, 2048과 10 GiB로 돌렸습니다.

**W2 — Langfuse 크기의 insert** ([04-write-small.sh](04-write-small.sh)): INSERT 하나 = trace 하나 = observation 4개, open loop, 30초. 암호화는 Null 테이블 + materialized view.

| 방식 | 초당 67 trace(분당 약 4,000): p50 / p95 ms | 초당 267 trace: 달성, p50 ms |
|---|---|---|
| plain | 126 / 222 | 266/s, 146(재실행 264/s, 165) |
| codec | 127 / 223 | 266/s, 146 |
| sql | 130 / 225 | 234/s, 223(재실행 263/s, 214) |
| local | 135 / 228 | 265/s, 148(재실행 266/s, 147) |
| kms_batch | 139 / 234 | 235/s, 241(재실행 213/s, 299) — 뒤처짐 |
| kms_batch5 | 153 / 249 | 265/s, 184 |
| kms_row | 168 / 266 | **151/s**, 413 — 뒤처짐 |
| kms_row5 | **776** / 882 | **19/s**, 3,514 — 무너짐 |

**R — 읽기** ([05-read.sh](05-read.sh)): clickhouse-benchmark, 칸마다 20초, 쿼리는 100가지 변형에서 무작위. p50 ms(괄호는 오류 수). `detail` = trace 하나의 전체 input/output, `list` = 하루 중 최신 50행과 200자 미리보기(plain과 codec은 Langfuse처럼 미리보기 테이블을 읽음, 암호문의 미리보기는 쓸 수 없어 암호화 방식은 `events_full`을 복호화), `search` = Langfuse의 match 조건으로 하루 검색, `export` = 하루치 전부 복호화, `agg` = 모델별 비용·지연, prompt 컬럼 없음.

| 방식 | detail c=4 | list c=4 | search c=1 | search c=4 | export c=1 | export c=4 | agg c=4 |
|---|---|---|---|---|---|---|---|
| plain | 33 | 5 | 400 | 418 | 486 | 485 | 18 |
| 인덱스 없는 plain(search) | — | — | 574 | 527 | — | — | — |
| codec | 37 | 7 | 582 | 560 | 694 | 668 | 17 |
| sql | 46 | 35 | 2,138 | 13,842(2) | 1,330 | 1,811 | 14 |
| local | 27 | 44 | 9,361 | 22,542(2) | 5,038 | 6,519 | 16 |
| kms_batch | 40 | 68 | 10,661 | 31,313(1) | 10,791 | 15,471 | 14 |
| kms_batch5 | 56 | 78 | 14,532 | **OOM-kill** | 15,309 | — | 15 |
| kms_row | 45 | 93 | — | — | — | — | — |
| kms_row5 | 89 | 638 | — | — | — | — | — |

- trace 하나는 암호화 차이가 거의 없습니다. 목록 화면은 로컬 키로 7–9배, KMS를 거치면 14–19배, 값마다 KMS를 부르고 왕복이 5 ms면 약 130배 느립니다. 하루 단위 작업(검색, export, 평가)은 동시 1에서 3–36배, 동시 4에서 최대 75배 느리고, 전문 검색은 인덱스를 잃습니다.
- **메모리.** 동시 16에서는 하루 검색이 평문도 쿼리 메모리로 실패했고(285개 중 7개), `sql`은 거의 전부(86개 중 85개)였습니다. executable UDF 방식은 더 나쁩니다. **Python 프로세스의 메모리는 ClickHouse 메모리 한도 밖이라, 쿼리 하나가 실패하는 대신 컨테이너가 OOM-kill되어 서버가 재시작됐습니다**(`local` search 동시 16, `kms_batch5` search 동시 4).

**E1 — 실제 Langfuse를 거쳐서** ([07-langfuse-e2e.sh](07-langfuse-e2e.sh)): Langfuse 4.56.0 EE에 OTLP/HTTP, 요청 하나 = span 4개짜리 trace 하나, prompt는 같은 데이터. 지연 = `events_full.created_at` − span 시작.

| 방식 | 초당 67 trace, 120초: 도착, 지연 p95 | 초당 200 trace, 60초: 도착, 지연 p95 |
|---|---|---|
| plain | 32,160 / 32,160, 0.15초 | 48,000 / 48,000, 0.67초 |
| codec | 32,160 / 32,160, 0.10초 | — |
| cb_local | 32,160 / 32,160(전부 암호문), 0.29초 | 48,000 / 48,000, **26초** 밀림 |
| cb_kms_batch | 32,160 / 32,160, 0.38초 | 48,000 / 48,000, **30초** |
| cb_kms_row5 | 32,160 / 32,160, 0.44초 | 48,000 / 48,000, **107초** |

callback 실행 어디에서도 유실된 이벤트나 평문으로 저장된 이벤트는 없었습니다. 분당 약 4,000 trace에서 암호화 callback이 더하는 것은 1초 미만이고, 그 3배에서는 이 노트북의 worker 하나가 뒤처집니다. Langfuse의 ClickHouse는 암호문일 때 CPU를 2–3배 썼고(초당 67에서 41초 대비 84–124초), 대부분 무작위 토큰을 색인하는 텍스트 인덱스 때문입니다.

### KMS 호출 수와 Azure Key Vault 한도

Azure Key Vault는 소프트웨어 RSA-2048·EC 키 기준 vault·리전당 10초에 "그 밖의" 키 트랜잭션 4,000건, HSM 키는 2,000건까지 받고([service limits](https://learn.microsoft.com/en-us/azure/key-vault/general/service-limits), 2026-11-04 확인), 넘으면 HTTP 429로 답합니다. Encrypt 작업은 블록 하나만 처리하고 키 감싸기용이며([Encrypt](https://learn.microsoft.com/en-us/rest/api/keyvault/keys/encrypt/encrypt)) 일괄 처리가 없습니다. 그래서 `kms_batch`는 Vault 계열 KMS의 방식이고 Key Vault에는 해당하지 않습니다.

- 분당 4,000 trace에 observation 4개, 필드 2개면 값마다 호출할 때 초당 533번 암호화합니다. 읽기를 빼고도 vault당 초당 400번(소프트웨어), 200번(HSM)을 넘습니다.
- 읽기가 더해집니다. trace 화면 하나에 복호화 8번, 목록 화면 하나에 100번, 그 속도로 하루치 export(trace 576만 개)는 약 4,600만 번, 초당 400번이면 32시간입니다.
- envelope 암호화(`local`, `cb_local`)에서는 프로세스가 시작하거나 데이터 키를 교체할 때만 KMS를 부릅니다. 하루에 몇 번입니다.

### 평문이 남는 곳 ([06-codec-leak.sh](06-codec-leak.sh))

- `AES_256_GCM_SIV`에서 `input.bin`은 키 없이 압축을 풀 수 없지만, **텍스트 인덱스 사전에는 prompt 단어가 평문으로 있습니다**(front coding: `rx77refund`는 `r` + `x77refund`로 저장). 평문 테이블의 사전과 바이트까지 같습니다. ClickHouse 문서도 인덱스에는 컬럼 코덱이 적용되지 않는다고 적고 있습니다. 문제가 된다면 텍스트 인덱스를 지웁니다.
- 검색어는 `system.query_log`에 평문으로 남습니다.
- 텍스트 인덱스가 없는 UDF 암호문 테이블에는 표시 단어가 어느 파일에도 없습니다.

### 실행

```bash
cd usecase/langfuse-prompt-encryption-perf
./01-up.sh            # .env와 .secrets, OpenBao Transit 키 + 감싼 데이터 키, UDF가 있는 ClickHouse, 왕복 확인
./02-load.sh          # Langfuse events_full 스키마에 합성 observation 40만 개(TRACES=100000)
./03-write-bulk.sh    # W1, 약 15분. results/w1-bulk.tsv, results/w1-storage.tsv
./06-codec-leak.sh    # 디스크와 query_log의 평문
./05-read.sh          # R, 약 60분. results/r-read.tsv (CONC="1 4 16", TIME=20)
./04-write-small.sh   # W2, 약 10분. results/w2-small.tsv
./07-langfuse-e2e.sh  # E1, 약 20분. EE 라이선스가 있는 langfuse-hols v4 스택 필요, 끝나면 원래대로 되돌림
./08-in-place-probe.sh
./99-down.sh [--purge]
```

디스크: 측정 볼륨이 최대 약 25 GB입니다. 40 GB는 비워 두세요. `07`은 Langfuse 스택을 바꿨다가(EE overlay, `events_full`/`events_core` 코덱, callback) 되돌립니다. OSS 모드, 원래 코덱, `bench_run` 표시가 붙은 행 삭제까지입니다. 중간에 멈췄다면 `07-langfuse-e2e.sh --restore-only`로 다시 되돌립니다.

### 다루지 않은 것

- 실제 Azure Key Vault(비용 없음): 지연은 호출당 5 ms로 흉내 냈고, 한도는 문서 기준입니다.
- 운영 사이징: 노트북 한 대, worker 하나, ClickHouse 하나입니다. 숫자는 비율로 읽습니다.
- 암호문일 때 Langfuse 화면과 평가: 규제 통제 글에서 다룹니다(검색 0건, LLM 평가 0점).
- Langfuse 자체 쿼리 안에서 복호화: Langfuse를 고치지 않고는 할 수 없습니다.

### 파일

| 파일 | 내용 |
|---|---|
| [docker-compose.yml](docker-compose.yml) | 측정용 ClickHouse([docker/Dockerfile](docker/Dockerfile)로 빌드)와 OpenBao |
| [clickhouse/user_scripts/prompt_crypto.py](clickhouse/user_scripts/prompt_crypto.py) | executable UDF 본체: `local`, `kms_batch`, `kms_row`, 왕복 지연 옵션 |
| [clickhouse/udf/prompt_crypto.xml](clickhouse/udf/prompt_crypto.xml) | executable UDF 10개(`executable_pool`, `send_chunk_header`) |
| [clickhouse/config.d/prompt-enc.xml](clickhouse/config.d/prompt-enc.xml) | 환경 변수의 코덱 키, UDF 설정 경로, `old_parts_lifetime` 10초 |
| [sql/events_full.langfuse-4.56.0.sql](sql/events_full.langfuse-4.56.0.sql) | 실행 중인 4.56.0에서 가져온 Langfuse DDL |
| [sql/generate.sql](sql/generate.sql) | 합성 observation |
| [bench/small_insert.py](bench/small_insert.py), [bench/otlp_load.py](bench/otlp_load.py) | open loop 부하 생성기(ClickHouse HTTP, Langfuse OTLP) |
| [bench/enc_callback.py](bench/enc_callback.py) | 암호화하는 수집 callback |
| [docker-compose.langfuse.yml](docker-compose.langfuse.yml), [docker-compose.langfuse-callback.yml](docker-compose.langfuse-callback.yml) | langfuse-hols 스택용 overlay |
| `results/*.tsv` | 2026-11-04 측정값(원본 로그는 커밋하지 않음) |
