# Kafka Partitioning ↔ ClickHouse Sort-Key Alignment — a hands-on lab

[English](#english) | [한국어](#한국어)

---

## English

A reproducible, end-to-end lab that proves how a **Kafka partitioning strategy**
turns into the **part-level pruning** behavior of a ClickHouse `MergeTree` — and
how the **ingestion path** (Kafka table engine vs Kafka Connect Sink) changes
whether that locality survives.

Same data. Same `ORDER BY (customer_id, ts)`. Same `index_granularity`. The only
variables are **(1)** how records map to Kafka partitions (range vs hash) and
**(2)** which ingestion path carries them into ClickHouse. Everything is measured
with `EXPLAIN ESTIMATE`, `EXPLAIN indexes = 1`, and `system.query_log`.

### 🎯 What this lab proves

ClickHouse always sorts rows **inside** a part by the table's `ORDER BY`, so
granule skipping within a part works regardless. The difference shows up at the
**part level**: each part stores the min/max of the sort key, and the planner
skips whole parts that can't contain the value. Whether parts are *skippable*
depends on whether each part holds a **narrow, disjoint key range** — and that is
decided upstream, by how Kafka partitions are formed and how the ingestion path
batches them into parts.

Three ingestion paths × two partitioning strategies:

| Path | How it batches partitions → parts | Locality result |
|---|---|---|
| **A. Kafka engine, DEFAULT** | one consumer multiplexes all partitions into each INSERT block | **diluted** — even a range topic yields full-range parts |
| **B. Kafka engine, TUNED** | `kafka_num_consumers = N` + `kafka_thread_per_consumer = 1` → one consumer per partition, parallel flush | **preserved** — part = one partition's range |
| **C. Kafka Connect Sink** | groups records by topic-partition, one batch per partition (by design) | **preserved** with no CH tuning, but many tiny parts → rely on merges |

ClickPipes is intentionally **out of scope** here (managed, batches by size/time;
the same MergeTree benefit applies *if* the batch reflects partition locality, but
that isn't a documented guarantee — verify with per-part min/max if you use it).

### 🧪 The experiment

- **10M events per topic**, `customer_id ∈ [0, 9999]`, **8 partitions**.
- `events_misaligned` — producer uses the **default (hash) partitioner**.
- `events_aligned` — producer assigns **`partition = customer_id // 1250`** (range).
- Both topics get the **identical interleaved time order**; only the partitioner
  differs. (This "all customers active at once" timeline is exactly what exposes
  the engine-default dilution.)
- Background **merges are stopped** so the streaming steady-state (many unmerged
  parts) stays observable — the regime where part-level pruning actually matters.

### 📊 Verified results (ClickHouse 26.6.1, full raw output in [RESULTS.md](RESULTS.md))

Per-part `customer_id` span — **lower = better pruning**:

| target | path · topic | parts | avg key span | reads for `id=4242` |
|---|---|---:|---:|---|
| `engine_aligned` | B engine tuned · range | 38 | **1249** | **5 parts / 40,960 rows** |
| `engine_misaligned` | B engine tuned · hash | 32 | 9992 | 32 parts / 262,144 rows |
| `engine_default_aligned` | A engine default · range | 10 | **9999** ⚠ | 10 parts / 82,418 rows |
| `connect_aligned` | C Connect · range | 1861 | **1249** | 234 parts / 996,619 rows † |
| `connect_misaligned` | C Connect · hash | 1836 | 9989 | 1836 parts / 7,839,808 rows |

`EXPLAIN indexes = 1` (granule-level): `engine_aligned` reads **5/38 parts,
5/1216 granules**; `engine_misaligned` reads **32/32 parts, 32/1220 granules**.

**Three lessons:**
1. **Range partitioning works** — `engine_aligned` keeps each part to one
   1,250-wide bucket, so a point lookup skips 33 of 38 parts.
2. **The engine default is a trap** — `engine_default_aligned` consumes the *same
   range topic* but a single consumer multiplexes partitions into each block, so
   every part spans the full range (span 9999). You **must** set
   `kafka_thread_per_consumer = 1` + `kafka_num_consumers = partitions`.
3. **Connect keeps locality for free, but explodes part count** — `connect_aligned`
   has narrow parts (span 1249) with zero CH tuning, but 1,861 tiny parts. †With
   merges off the lookup still touches 234 of them. Enable merges →
   `OPTIMIZE … FINAL` collapses it to **1 part / 8,192 rows**; merges preserve
   `ORDER BY`, so locality survives. Connect's lever is **healthy merges**, not
   consumer tuning.

### 📁 File structure

```
kafka-partitioning-ingestion/
├── README.md                  # this file
├── RESULTS.md                 # full raw output of the verified run
├── docker-compose.yml         # Kafka (KRaft) + ClickHouse + Kafka Connect
├── connect.Dockerfile         # Connect worker + ClickHouse sink connector
├── .env                       # ports + experiment dimensions (ROWS, partitions…)
├── requirements.txt           # confluent-kafka (producer)
├── _env.sh                    # shared .env loader + `chc` helper
├── 00-explain-estimate.sql    # deterministic SQL-only proof (no Kafka)
├── 01-up.sh                   # build + start the stack, wait for healthy
├── 02-create-topics.sh        # two 8-partition topics
├── 03-clickhouse-setup.sql    # 5 target tables + engine consumers (A/B) + MVs + user
├── 04-register-connectors.sh  # register the two Connect sinks (C)
├── 05-produce.py              # produce 10M events/topic, range vs hash partitioner
├── 06-compare.sql             # the full comparison (rows, span, ESTIMATE, query_log)
├── 07-benchmark.sh            # wall-clock the point lookup across all targets
└── 99-cleanup.sh              # tear down
```

### 🏗️ Architecture

```
                              ┌────────────────────── ClickHouse ──────────────────────┐
events_aligned (range) ──┬──► Kafka engine (tuned, 8 consumers) ─MV─► engine_aligned
   8 partitions          ├──► Kafka engine (DEFAULT, 1 consumer) ─MV─► engine_default_aligned
                         └──► Connect Sink (8 tasks) ───────────────► connect_aligned
events_misaligned(hash)──┬──► Kafka engine (tuned, 8 consumers) ─MV─► engine_misaligned
   8 partitions          └──► Connect Sink (8 tasks) ───────────────► connect_misaligned
                              └─ all targets: MergeTree ORDER BY (customer_id, ts) ─────┘
```

### 🚀 Run it

Prereqs: Docker (with Compose) and Python 3.9+. First `01-up.sh` builds the
Connect image (installs the connector) — a few minutes; later runs are instant.

```bash
cd usecase/kafka-partitioning-ingestion

./01-up.sh                                                            # start Kafka + ClickHouse + Connect
./02-create-topics.sh                                                 # 2 topics × 8 partitions
docker compose exec -T clickhouse clickhouse-client --multiquery < 03-clickhouse-setup.sql
./04-register-connectors.sh                                           # the two Connect sinks

python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python 05-produce.py                                                  # 10M rows → each topic (~1 min)

# wait a few seconds for all consumers to drain, then:
docker compose exec -T clickhouse clickhouse-client --multiquery < 06-compare.sql
./07-benchmark.sh

# deterministic SQL-only proof (no Kafka needed):
docker compose exec -T clickhouse clickhouse-client --multiquery < 00-explain-estimate.sql

./99-cleanup.sh            # or: ./99-cleanup.sh --hard   (also wipes volumes)
```

Tune the experiment in `.env` (`ROWS`, `NUM_CUSTOMERS`, `NUM_PARTITIONS`,
`LOOKUP_CUSTOMER`). If you change `NUM_PARTITIONS`, also update the hard-coded
`kafka_num_consumers` in `03-clickhouse-setup.sql`. Ports default to **8124**
(ClickHouse HTTP), **9001** (native), **9094** (Kafka), **8083** (Connect) to avoid
colliding with the `langfuse` lab.

### ⚠️ When NOT to over-engineer this

Range/custom Kafka partitioning buys part-level pruning for **point/equality
lookups on the partition key**, but it brings real operational cost: hot
partitions, skew, and a partition count that is hard to change later. If your
queries are mostly **time-range scans**, prefer `ORDER BY (time, …)` with ordinary
`hash` partitioning — that already prunes by time, and you avoid the skew risk.
And remember: once parts are **merged**, within-part granule skipping handles
point lookups anyway. The alignment win is specifically about the **unmerged,
high-throughput streaming steady-state**.

### 🧠 Key takeaways

- A Kafka **partition strategy** is implicitly a ClickHouse **part-layout** strategy.
- Plain `hash(key)` keeps per-key *order* but mixes keys into every partition, so
  parts span the full range and can't be pruned. **Range/custom** partitioning is
  what produces narrow, skippable parts.
- The **ingestion path matters as much as the partitioner**: the Kafka engine
  dilutes locality unless you set `kafka_thread_per_consumer = 1` +
  `kafka_num_consumers = partitions`; Connect Sink preserves it by design but
  needs healthy merges to tame part count.
- Always **verify with `EXPLAIN indexes = 1`** (or per-part min/max) — design
  intent is not proof.

### 📝 License

MIT License

### 👤 Author

Ken Lee (ClickHouse Solution Architect) — ken.lee@clickhouse.com
작성일: 2026-06-28

---

## 한국어

**Kafka 파티셔닝 전략**이 어떻게 ClickHouse `MergeTree`의 **part 레벨 pruning**
동작으로 이어지는지, 그리고 **인제스천 경로**(Kafka 테이블 엔진 vs Kafka Connect
Sink)에 따라 그 지역성이 보존되는지 달라지는지를 **실측으로 증명**하는 재현 가능한
end-to-end 실습입니다.

동일한 데이터, 동일한 `ORDER BY (customer_id, ts)`, 동일한 `index_granularity`.
변수는 단 둘 — **(1)** 레코드를 Kafka 파티션에 매핑하는 방식(range vs hash),
**(2)** 어떤 인제스천 경로로 ClickHouse에 넣는가. 모든 것을 `EXPLAIN ESTIMATE`,
`EXPLAIN indexes = 1`, `system.query_log`로 측정합니다.

### 🎯 무엇을 증명하나

ClickHouse는 part **내부**를 항상 `ORDER BY` 순으로 정렬하므로, part 안에서의
granule skipping은 어느 경우든 작동합니다. 차이는 **part 레벨**에서 납니다 — 각
part는 정렬 키의 min/max를 메타로 갖고, 플래너는 값이 들어있을 수 없는 part 전체를
건너뜁니다. part가 *건너뛸 수 있는지*는 각 part가 **좁고 서로 겹치지 않는 키 범위**를
담는지에 달려 있고, 이는 상류에서 — Kafka 파티션이 어떻게 형성되고 인제스천 경로가
그것을 어떻게 part로 배치하는지 — 결정됩니다.

세 가지 인제스천 경로 × 두 가지 파티셔닝 전략:

| 경로 | 파티션 → part 배치 방식 | 지역성 결과 |
|---|---|---|
| **A. Kafka 엔진, 기본값** | 단일 컨슈머가 모든 파티션을 한 INSERT 블록에 멀티플렉싱 | **희석** — range 토픽조차 전 범위 part |
| **B. Kafka 엔진, 튜닝** | `kafka_num_consumers = N` + `kafka_thread_per_consumer = 1` → 파티션당 컨슈머 1개, 병렬 flush | **보존** — part = 한 파티션의 범위 |
| **C. Kafka Connect Sink** | 설계상 topic-partition 단위로 그룹핑, 파티션당 배치 1개 | CH 튜닝 없이 **보존**, 단 작은 part 다수 → 머지에 의존 |

ClickPipes는 의도적으로 **범위 밖**입니다(관리형, 크기·시간 기준 배치. 배치가 파티션
지역성을 반영하는 *한* 동일 이점이 적용되지만 문서화된 보장은 아니므로, 쓴다면 part별
min/max로 검증하세요).

### 🧪 실험

- **토픽당 1,000만 이벤트**, `customer_id ∈ [0, 9999]`, **파티션 8개**.
- `events_misaligned` — 프로듀서가 **기본(hash) 파티셔너** 사용.
- `events_aligned` — 프로듀서가 **`partition = customer_id // 1250`**(range) 할당.
- 두 토픽은 **동일한 교차 시간 순서**로 생성되고, 파티셔너만 다릅니다.("모든 customer가
  동시에 활동하는" 이 타임라인이 바로 엔진 기본값 희석을 드러냅니다.)
- 백그라운드 **머지를 멈춰** 스트리밍 정상상태(머지 안 된 part 다수)를 관찰합니다 —
  part 레벨 pruning이 실제로 중요한 구간입니다.

### 📊 검증 결과 (ClickHouse 26.6.1, 전체 raw 출력은 [RESULTS.md](RESULTS.md))

part별 `customer_id` 폭 — **낮을수록 pruning이 잘 됨**:

| 타겟 | 경로 · 토픽 | parts | 평균 키 폭 | `id=4242` 읽는 양 |
|---|---|---:|---:|---|
| `engine_aligned` | B 엔진 튜닝 · range | 38 | **1249** | **5 parts / 40,960 행** |
| `engine_misaligned` | B 엔진 튜닝 · hash | 32 | 9992 | 32 parts / 262,144 행 |
| `engine_default_aligned` | A 엔진 기본값 · range | 10 | **9999** ⚠ | 10 parts / 82,418 행 |
| `connect_aligned` | C Connect · range | 1861 | **1249** | 234 parts / 996,619 행 † |
| `connect_misaligned` | C Connect · hash | 1836 | 9989 | 1836 parts / 7,839,808 행 |

`EXPLAIN indexes = 1`(granule 레벨): `engine_aligned`는 **5/38 parts, 5/1216
granules**; `engine_misaligned`는 **32/32 parts, 32/1220 granules** 읽음.

**세 가지 교훈:**
1. **range 파티셔닝은 작동한다** — `engine_aligned`는 각 part를 1,250 폭의 버킷
   하나로 유지 → point lookup이 38개 중 33개 part를 건너뜀.
2. **엔진 기본값은 함정** — `engine_default_aligned`는 *같은 range 토픽*을 소비하지만
   단일 컨슈머가 파티션을 한 블록에 멀티플렉싱 → 모든 part가 전 범위(폭 9999).
   반드시 `kafka_thread_per_consumer = 1` + `kafka_num_consumers = 파티션수` 설정.
3. **Connect는 지역성을 공짜로 보존하지만 part 수가 폭증** — `connect_aligned`는
   CH 튜닝 0으로 좁은 part(폭 1249)지만 1,861개의 작은 part. †머지 정지 상태에선
   lookup이 234개를 건드림. 머지 켜고 `OPTIMIZE … FINAL` →
   **1 part / 8,192 행**으로 수렴. 머지는 `ORDER BY`를 보존하므로 지역성 유지.
   Connect의 레버는 컨슈머 튜닝이 아니라 **건강한 머지**.

### 📁 파일 구조

```
kafka-partitioning-ingestion/
├── README.md                  # 이 문서
├── RESULTS.md                 # 검증 실행의 전체 raw 출력
├── docker-compose.yml         # Kafka (KRaft) + ClickHouse + Kafka Connect
├── connect.Dockerfile         # Connect 워커 + ClickHouse 싱크 커넥터
├── .env                       # 포트 + 실험 차원 (ROWS, partitions…)
├── requirements.txt           # confluent-kafka (프로듀서)
├── _env.sh                    # .env 로더 + `chc` 헬퍼
├── 00-explain-estimate.sql    # 결정적 SQL-only 증명 (Kafka 불필요)
├── 01-up.sh                   # 스택 빌드+기동, healthy 대기
├── 02-create-topics.sh        # 8 파티션 토픽 2개
├── 03-clickhouse-setup.sql    # 타겟 5개 + 엔진 컨슈머(A/B) + MV + 유저
├── 04-register-connectors.sh  # Connect 싱크 2개 등록 (C)
├── 05-produce.py              # 토픽당 1천만 이벤트, range vs hash 파티셔너
├── 06-compare.sql             # 전체 비교 (행, 폭, ESTIMATE, query_log)
├── 07-benchmark.sh            # 전 타겟 point lookup 시간 측정
└── 99-cleanup.sh              # 정리
```

### 🚀 실행

사전 준비: Docker(Compose 포함), Python 3.9+. 최초 `01-up.sh`는 Connect 이미지를
빌드(커넥터 설치)하므로 수 분 소요, 이후엔 즉시.

```bash
cd usecase/kafka-partitioning-ingestion

./01-up.sh                                                            # Kafka + ClickHouse + Connect 기동
./02-create-topics.sh                                                 # 토픽 2 × 파티션 8
docker compose exec -T clickhouse clickhouse-client --multiquery < 03-clickhouse-setup.sql
./04-register-connectors.sh                                           # Connect 싱크 2개

python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python 05-produce.py                                                  # 각 토픽에 1천만 행 (~1분)

# 모든 컨슈머가 소비를 끝낼 때까지 수 초 대기 후:
docker compose exec -T clickhouse clickhouse-client --multiquery < 06-compare.sql
./07-benchmark.sh

# 결정적 SQL-only 증명 (Kafka 불필요):
docker compose exec -T clickhouse clickhouse-client --multiquery < 00-explain-estimate.sql

./99-cleanup.sh            # 또는: ./99-cleanup.sh --hard   (볼륨까지 삭제)
```

`.env`에서 실험을 조정하세요(`ROWS`, `NUM_CUSTOMERS`, `NUM_PARTITIONS`,
`LOOKUP_CUSTOMER`). `NUM_PARTITIONS`를 바꾸면 `03-clickhouse-setup.sql`의
하드코딩된 `kafka_num_consumers`도 맞춰 변경하세요. 포트는 `langfuse` 랩과 충돌을
피하려 **8124**(HTTP)·**9001**(native)·**9094**(Kafka)·**8083**(Connect) 기본값.

### ⚠️ 과설계 주의

range/custom Kafka 파티셔닝은 **파티션 키에 대한 point/등치 lookup**에서 part 레벨
pruning을 얻지만, 핫 파티션·스큐·나중에 바꾸기 어려운 파티션 수 같은 실제 운영 비용을
동반합니다. 쿼리가 주로 **시간 범위 스캔**이면 일반 `hash` 파티셔닝 + `ORDER BY (time, …)`을
쓰세요 — 이미 시간으로 pruning되고 스큐 위험도 피합니다. 그리고 **머지가 끝난** part는
within-part granule skipping이 point lookup을 처리합니다. 정렬의 이점은 정확히
**머지 안 된 고처리량 스트리밍 정상상태**에 관한 것입니다.

### 🧠 핵심 요약

- Kafka **파티션 전략**은 곧 ClickHouse **part 배치 전략**입니다.
- 단순 `hash(key)`는 키별 *순서*는 지키지만 키들을 모든 파티션에 섞어 part가 전
  범위를 차지 → pruning 불가. 좁고 건너뛸 수 있는 part를 만드는 건 **range/custom**.
- **인제스천 경로가 파티셔너만큼 중요**합니다: Kafka 엔진은
  `kafka_thread_per_consumer = 1` + `kafka_num_consumers = 파티션수` 없이는 지역성을
  희석하고, Connect Sink는 설계상 보존하지만 part 수 제어를 위해 건강한 머지가 필요합니다.
- 항상 **`EXPLAIN indexes = 1`**(또는 part별 min/max)로 **검증**하세요 — 설계 의도는
  증명이 아닙니다.

### 📝 검증

비어 있는 상태에서 **ClickHouse 26.6.1** + **Apache Kafka 3.9.0 (KRaft)** +
**Kafka Connect 7.8.0 / clickhouse-kafka-connect v1.3.9**(모두 단일 노드 Docker)에
대해 1천만 행/토픽으로 end-to-end 검증됨. 전체 raw 출력은 [RESULTS.md](RESULTS.md).

### 📝 라이선스

MIT License

### 👤 작성자

Ken Lee (ClickHouse Solution Architect) — ken.lee@clickhouse.com
작성일: 2026-06-28

---

**Happy Pruning! ⚡**

질문이나 이슈는 메인 [clickhouse-hols README](../../README.md)를 참조하세요.
