# Iceberg format versions — v1, v2 and v3 side by side

[English](#english) | [한국어](#한국어)

---

## English

One Iceberg table per format version (v1, v2, v3), the same changes on each, and the files each
version leaves behind, opened without Spark. ClickHouse comes in only at the end, reading the same
tables. The lab backs a notes article on understanding Iceberg v1/v2/v3.

Verified on Spark 4.1.4 + Iceberg 1.11.0 (writer) and ClickHouse 26.10.3.7 (reader), 2026-11-08.
The ClickHouse step was also run on the `head` image of that day (26.11.1.1642).

### What it does

```bash
./run.sh          # stack up -> Spark writes the tables -> files opened -> ClickHouse reads them
./run.sh read     # ClickHouse step only (CH_VERSION=<tag> to try another server)
python3 capture.py  # results/*.txt excerpts -> images/*.png (needs Google Chrome)
./run.sh down     # remove the stack and its volumes
```

| Step (`spark/steps.py`) | v1 table | v2 table | v3 table |
|---|---|---|---|
| 1 create, partitioned by `days(ts)` | copy-on-write | merge-on-read | merge-on-read |
| 2 two inserts | | | |
| 3 add a column, rename a column | | | |
| 4 add `bucket(4, id)` to the partition spec, insert | | | |
| 5 `DELETE` id 2 and 7 | | | |
| 6 `UPDATE` id 3 | | | |
| 7 add a `VARIANT` column | refused (control) | refused (control) | added, one row inserted |

Two more tables: `t_v3_variant` (a `VARIANT` column from `CREATE`, the control for step 7) and
`t_v2_to_v3` (a v2 table with a position delete, upgraded to v3, then written to). After each step
the script records the snapshots, the live data and delete files, and on v3 the row lineage, from
Iceberg's own metadata tables (`results/spark-steps.txt`).

`inspect/inspect.py` then opens every table's files directly — the current `metadata.json`, the
manifest list and manifests (Avro), position delete files (Parquet), deletion vectors (Puffin,
decoded to row positions, CRC checked) and the Parquet schema with Iceberg field ids
(`results/inspect-<table>.txt`). `clickhouse/read.py` reads the same tables with `icebergS3` and
through the REST catalog (`DataLakeCatalog`) and compares each answer with Spark's
(`results/clickhouse-<version>.txt`).

### What each version wrote (2026-11-08 run)

| | v1 | v2 | v3 |
|---|---|---|---|
| `DELETE` with merge-on-read | refused: `Deletes are supported in V2 and above` | position delete files: Parquet rows of (data file, row position) | one deletion vector per data file: a roaring bitmap blob in a Puffin file |
| `DELETE` id 2 and 7 | data files rewritten (`overwrite`: 2 files out, 3 in) | 2 position delete files, data files untouched | 1 Puffin file with 2 blobs, one per data file |
| `UPDATE` id 3 on a file that already had a delete | rewritten | a new delete file holding both positions replaces the old one for that file | the deletion vector for that file is rewritten with both positions (cardinality 2) |
| sequence numbers | none in snapshots | per snapshot; delete files apply to data with a lower sequence number | as v2 |
| row lineage | — | — | `first-row-id` per snapshot, `next-row-id` in metadata; `_row_id` kept across `UPDATE`, `_last_updated_sequence_number` moves to the update's sequence number |
| `VARIANT` | refused: `variant is not supported until v3` | refused | stored in Parquet as `struct<metadata: binary, value: binary>` |

Upgrade (`t_v2_to_v3`): after `format-version` 2 → 3, `_row_id` is NULL for every existing row until
the next write assigns `first_row_id` to the old data file. The first `DELETE` after the upgrade
removed the old position delete file and wrote deletion vectors that include its position
(`removed-position-delete-files: 1`, `added-dvs: 2`). Setting `format-version` back to 2 is refused
(`Cannot downgrade v3 table to v2`).

Row ids are unique but not dense: on `t_v3`, `next-row-id` is 21 after 12 rows were written. The
step-4 commit inserted one row but reports `added-rows=10`: it also wrote a manifest of the 5 existing
data files (9 rows) and a new id range was reserved for that manifest, while those rows kept the ids
already recorded on their data files (`_row_id` did not change).

Captures of these results are in [images/](images/) (`01`–`07`; the ClickHouse run is `08`).

### ClickHouse reading the tables

| Check (`clickhouse/read.py`) | 26.10.3.7 | 26.11.1.1642 (head) |
|---|---|---|
| v1, v2: rows after delete and update | match | match |
| v1, v2: time travel (`iceberg_snapshot_id`) to the second insert | match | match |
| v2, v3: the data files still hold the deleted rows; the table does not | match | match |
| v3 before the `VARIANT` column: rows (deletion vectors applied) and `_row_id` / `_last_updated_sequence_number` | match | match |
| v3 current snapshot (a `VARIANT` column added by `ALTER TABLE ... ADD COLUMN`) | **error** | **error** |
| v3, same table, only the file written after the column was added (`WHERE id = 11`) | match | match |
| `t_v3_variant` (`VARIANT` from `CREATE`): rows, type `Dynamic` | match | match |
| `t_v2_to_v3`: rows and row lineage | match | match |
| REST catalog: `SHOW TABLES`, rows of `fv.t_v2` | match | match |

15 match and 1 error on both servers. The error:

```text
Cannot add a column with id 6 with required values to the table during schema evolution.
This is forbidden by Iceberg format specification. (ICEBERG_SPECIFICATION_VIOLATION)
```

The column is optional in the table metadata (`"required": false`), and the same data reads when
the column exists from `CREATE`. Reading only data files written after the column was added also
works, so the failure is in filling the new column for older files. A possible cause, not
verified: ClickHouse maps `variant` to `Dynamic`, which cannot be `Nullable`, so the new column
looks required. No upstream issue was found for this message (searched 2026-11-08).

`DataLakeCatalog` with a REST catalog needs `allow_database_iceberg = 1` on 26.10 (beta;
`SUPPORT_IS_DISABLED` without it).

### Not covered

- Equality deletes: Spark writes position deletes only; equality deletes come from streaming writers
  (for example Flink). The inspector prints them if a table has them.
- Other v3 changes: `initial-default` / `write-default`, nanosecond timestamps, geometry and
  geography types, multi-argument transforms, table encryption keys.
- ORC and Avro data files (all data here is Parquet), writes from ClickHouse, ClickHouse Cloud.

### Pinned versions (checked 2026-11-08)

| Component | Pin | Checked against |
|---|---|---|
| Spark | `apache/spark:4.1.4-python3` (by digest) | Docker Hub |
| Iceberg | `iceberg-spark-runtime-4.1_2.13` and `iceberg-aws-bundle` 1.11.0 | Maven Central (released 2026-05-15) |
| REST catalog | `apache/iceberg-rest-fixture:1.10.1` (by digest) | Docker Hub; env vars from the 1.10.1 Dockerfile |
| MinIO | Chainguard image by digest (same as `local/datalake-minio-catalog`) | — |
| ClickHouse | `clickhouse/clickhouse-server:26.10.3.7` (`CH_VERSION` to override) | Docker Hub |
| Inspector | `python:3.13-slim` (by digest), `fastavro` 1.13.1, `pyarrow` 26.0.1 | PyPI |

A full run from a clean stack took 38 s (2026-11-08, Docker Desktop 29.9.2, 12 CPUs, 16 GB,
images already pulled). No host ports are published; everything runs in the compose network.

---

## 한국어

Iceberg 포맷 버전(v1, v2, v3)마다 테이블을 하나씩 만들고, 같은 변경을 똑같이 적용한 뒤, 버전마다 남는
파일을 Spark 없이 직접 열어 봅니다. ClickHouse는 마지막에 같은 테이블을 읽는 단계에서만 나옵니다.
notes의 Iceberg v1/v2/v3 이해 글을 뒷받침하는 실습입니다.

Spark 4.1.4 + Iceberg 1.11.0(쓰기)과 ClickHouse 26.10.3.7(읽기)로 2026-11-08에 검증했습니다.
ClickHouse 단계는 같은 날의 `head` 이미지(26.11.1.1642)에서도 실행했습니다.

### 하는 일

```bash
./run.sh          # 스택 기동 -> Spark가 테이블 작성 -> 파일 열기 -> ClickHouse가 읽기
./run.sh read     # ClickHouse 단계만 (CH_VERSION=<태그>로 다른 서버)
python3 capture.py  # results/*.txt 발췌 -> images/*.png (Google Chrome 필요)
./run.sh down     # 스택과 볼륨 삭제
```

| 단계 (`spark/steps.py`) | v1 테이블 | v2 테이블 | v3 테이블 |
|---|---|---|---|
| 1 생성, `days(ts)` 파티션 | copy-on-write | merge-on-read | merge-on-read |
| 2 INSERT 두 번 | | | |
| 3 컬럼 추가, 컬럼 이름 변경 | | | |
| 4 파티션 스펙에 `bucket(4, id)` 추가 후 INSERT | | | |
| 5 id 2, 7 `DELETE` | | | |
| 6 id 3 `UPDATE` | | | |
| 7 `VARIANT` 컬럼 추가 | 거부(대조군) | 거부(대조군) | 추가, 한 행 INSERT |

테이블이 두 개 더 있습니다. `t_v3_variant`는 `CREATE` 때부터 `VARIANT` 컬럼이 있는 테이블로 7단계의
대조군이고, `t_v2_to_v3`는 position delete가 있는 v2 테이블을 v3로 올린 뒤 다시 쓴 테이블입니다.
각 단계 뒤에 스냅샷, 살아 있는 데이터·삭제 파일, v3에서는 row lineage를 Iceberg 메타데이터 테이블에서
기록합니다(`results/spark-steps.txt`).

이어서 `inspect/inspect.py`가 테이블마다 파일을 직접 엽니다. 현재 `metadata.json`, manifest list와
manifest(Avro), position delete 파일(Parquet), 삭제 벡터(Puffin, 행 위치로 디코딩하고 CRC 확인),
Iceberg field id가 붙은 Parquet 스키마입니다(`results/inspect-<테이블>.txt`). `clickhouse/read.py`는 같은
테이블을 `icebergS3`와 REST 카탈로그(`DataLakeCatalog`)로 읽고, 답을 Spark 결과와 비교합니다
(`results/clickhouse-<버전>.txt`).

### 버전마다 쓴 것 (2026-11-08 실행)

| | v1 | v2 | v3 |
|---|---|---|---|
| merge-on-read `DELETE` | 거부: `Deletes are supported in V2 and above` | position delete 파일: (데이터 파일, 행 위치) Parquet 행 | 데이터 파일마다 삭제 벡터 하나: Puffin 파일 안의 roaring bitmap blob |
| id 2, 7 `DELETE` | 데이터 파일 재작성(`overwrite`: 2개 제거, 3개 추가) | position delete 파일 2개, 데이터 파일은 그대로 | Puffin 파일 1개에 blob 2개(데이터 파일마다 하나) |
| 이미 삭제가 있던 파일의 id 3 `UPDATE` | 재작성 | 두 위치를 담은 새 delete 파일이 그 파일의 기존 delete 파일을 대체 | 그 파일의 삭제 벡터를 두 위치로 다시 씀(cardinality 2) |
| sequence number | 스냅샷에 없음 | 스냅샷마다 있음, delete 파일은 더 낮은 번호의 데이터에 적용 | v2와 같음 |
| row lineage | — | — | 스냅샷마다 `first-row-id`, 메타데이터에 `next-row-id`. `UPDATE` 후에도 `_row_id`는 유지되고 `_last_updated_sequence_number`는 UPDATE의 번호로 바뀜 |
| `VARIANT` | 거부: `variant is not supported until v3` | 거부 | Parquet에 `struct<metadata: binary, value: binary>`로 저장 |

업그레이드(`t_v2_to_v3`): `format-version`을 2 → 3으로 바꾸면, 다음 쓰기가 기존 데이터 파일에
`first_row_id`를 줄 때까지 기존 행의 `_row_id`는 모두 NULL입니다. 업그레이드 후 첫 `DELETE`는 기존
position delete 파일을 지우고, 그 위치까지 포함한 삭제 벡터를 썼습니다(`removed-position-delete-files: 1`,
`added-dvs: 2`). `format-version`을 2로 되돌리는 것은 거부됩니다(`Cannot downgrade v3 table to v2`).

row id는 유일하지만 연속적이지 않습니다. `t_v3`는 12행을 쓴 뒤 `next-row-id`가 21입니다. 4단계 커밋은
한 행을 넣었는데 `added-rows=10`으로 기록됩니다. 기존 데이터 파일 5개(9행)의 manifest도 새로 쓰면서 그
manifest에 새 id 범위를 예약했기 때문입니다. 그 행들은 데이터 파일에 기록된 id를 그대로 유지합니다
(`_row_id`는 바뀌지 않음).

결과 캡처는 [images/](images/)에 있습니다(`01`–`07`, ClickHouse 실행은 `08`).

### ClickHouse로 읽기

| 확인 항목 (`clickhouse/read.py`) | 26.10.3.7 | 26.11.1.1642 (head) |
|---|---|---|
| v1, v2: DELETE·UPDATE 후의 행 | 일치 | 일치 |
| v1, v2: 두 번째 INSERT 시점으로 시간 여행(`iceberg_snapshot_id`) | 일치 | 일치 |
| v2, v3: 데이터 파일에는 삭제된 행이 남아 있고 테이블에는 없음 | 일치 | 일치 |
| `VARIANT` 컬럼 추가 전의 v3: 행(삭제 벡터 반영)과 `_row_id` / `_last_updated_sequence_number` | 일치 | 일치 |
| v3 현재 스냅샷(`ALTER TABLE ... ADD COLUMN`으로 `VARIANT` 추가) | **에러** | **에러** |
| 같은 v3 테이블에서 컬럼 추가 후에 쓴 파일만 읽기(`WHERE id = 11`) | 일치 | 일치 |
| `t_v3_variant`(`CREATE`부터 `VARIANT`): 행, 타입 `Dynamic` | 일치 | 일치 |
| `t_v2_to_v3`: 행과 row lineage | 일치 | 일치 |
| REST 카탈로그: `SHOW TABLES`, `fv.t_v2`의 행 | 일치 | 일치 |

두 서버 모두 일치 15, 에러 1입니다. 에러 내용:

```text
Cannot add a column with id 6 with required values to the table during schema evolution.
This is forbidden by Iceberg format specification. (ICEBERG_SPECIFICATION_VIOLATION)
```

테이블 메타데이터에서 이 컬럼은 optional(`"required": false`)이고, `CREATE`부터 컬럼이 있는 같은 데이터는
읽힙니다. 컬럼 추가 후에 쓴 데이터 파일만 읽어도 성공하므로, 실패 지점은 예전 파일에 새 컬럼을 채우는
부분입니다. 원인 추정(검증하지 않음): ClickHouse가 `variant`를 `Dynamic`으로 매핑하는데 `Dynamic`은
`Nullable`이 될 수 없어서 새 컬럼이 required로 보이는 것일 수 있습니다. 이 메시지로 등록된 upstream 이슈는
찾지 못했습니다(2026-11-08 검색).

REST 카탈로그용 `DataLakeCatalog`는 26.10에서 `allow_database_iceberg = 1`이 필요합니다(beta, 없으면
`SUPPORT_IS_DISABLED`).

### 다루지 않은 것

- equality delete: Spark는 position delete만 씁니다. equality delete는 스트리밍 writer(예: Flink)가 씁니다.
  테이블에 있으면 inspector가 출력합니다.
- 그 밖의 v3 변경: `initial-default` / `write-default`, 나노초 timestamp, geometry·geography 타입, 다중 인자
  transform, 테이블 암호화 키.
- ORC·Avro 데이터 파일(여기 데이터는 모두 Parquet), ClickHouse에서의 쓰기, ClickHouse Cloud.

### 고정한 버전 (2026-11-08 확인)

| 구성 요소 | 고정 값 | 확인한 곳 |
|---|---|---|
| Spark | `apache/spark:4.1.4-python3` (digest 고정) | Docker Hub |
| Iceberg | `iceberg-spark-runtime-4.1_2.13`, `iceberg-aws-bundle` 1.11.0 | Maven Central (2026-05-15 배포) |
| REST 카탈로그 | `apache/iceberg-rest-fixture:1.10.1` (digest 고정) | Docker Hub, 환경 변수는 1.10.1 Dockerfile |
| MinIO | Chainguard 이미지 digest (`local/datalake-minio-catalog`와 같음) | — |
| ClickHouse | `clickhouse/clickhouse-server:26.10.3.7` (`CH_VERSION`으로 변경) | Docker Hub |
| Inspector | `python:3.13-slim` (digest 고정), `fastavro` 1.13.1, `pyarrow` 26.0.1 | PyPI |

깨끗한 스택에서 전체 실행에 38초 걸렸습니다(2026-11-08, Docker Desktop 29.9.2, CPU 12개, 16 GB, 이미지는
미리 받아 둔 상태). 호스트 포트는 열지 않고, 모두 compose 네트워크 안에서 실행합니다.
