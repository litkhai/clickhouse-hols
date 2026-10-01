# 배경: Cloud 백업 복원 대신 PeerDB와 데이터 복사를 쓰는 이유

운영 런북([`clickhouse-cloud-to-self-managed-security-runbook.md`](./clickhouse-cloud-to-self-managed-security-runbook.md))이
다루지 않는 질문 두 가지를 정리한다.

1. ClickHouse Cloud 백업을 OSS로 그냥 복원하면 되지 않나?
2. ClickPipes가 하던 CDC를 OSS 쪽에서는 무엇이 대신하나?

모든 주장에는 근거를 붙였다. 근거는 세 종류다. 공식 문서(2026-10-01에 읽음), PeerDB 소스
(`PeerDB-io/peerdb` main `942fb96`, 2026-10-01), 로컬 컨테이너에서 직접 실행한 결과
(ClickHouse 26.9.1.1629). Cloud 서비스에서는 아무것도 실행하지 않았다.

## 1. Cloud 백업을 OSS로 복원할 수 있나

### 1.1 기본(관리형) 백업: 쓸 수 없다

[백업 문서](https://clickhouse.com/docs/cloud/manage/backups/overview)에 따르면 백업은
**새 ClickHouse Cloud 서비스로** 복원된다. 같은 문서에 "외부 버킷으로의 백업은 ClickHouse
버킷으로의 백업보다 느릴 수 있다"는 문장이 있다. 기본 백업이 ClickHouse 쪽 버킷에 있다는
뜻이다. 백업 파일을 내려받거나 self-managed로 복원하는 방법은 문서에 없다.

### 1.2 외부 백업(`BACKUP ... TO S3(...)`): 파일은 손에 들어온다

[외부 백업 문서](https://clickhouse.com/docs/cloud/manage/backups/export-backups-to-own-cloud-account)에
따르면 다음과 같다.

- S3, GCS, Azure Blob Storage의 본인 계정으로 백업을 내보낼 수 있다.
- `BACKUP` 권한은 기본 role에 없다. Support에 요청해야 한다.
- 문서는 Cloud 안에서 하는 `RESTORE`만 설명하고, OSS로 복원하는 경우는 언급하지 않는다.
  공식 가이드는 반대 방향(OSS → Cloud)만 있다. 그 경우 Cloud가 `Replicated*MergeTree`를
  `SharedMergeTree`로 바꿔 준다.

Cloud 테이블은 `SharedMergeTree` 계열인데, OSS에는 이 엔진이 없다.

```text
-- ClickHouse 26.9.1.1629 (clickhouse/clickhouse-server:26.9)
CREATE TABLE t_smt (x UInt8) ENGINE = SharedMergeTree ORDER BY x;
Code: 56. DB::Exception: Unknown table engine SharedMergeTree. (UNKNOWN_STORAGE)
```

### 1.3 로컬 재현: 엔진 이름은 넘을 수 있다

실제 Cloud 백업 없이 OSS 26.9.1.1629에서 흉내 냈다. 먼저 `MergeTree` 테이블 하나(1,000행)를
`File()` 백업으로 만들었다. 그다음 백업 안 metadata `.sql`의 엔진을 `SharedMergeTree`로
고쳤다. 그 상태에서 복원을 세 가지 방법으로 시도했다.

| 시도 | 결과 |
|---|---|
| 그냥 `RESTORE ... AS t_a` | `Code: 56 Unknown table engine SharedMergeTree: While creating table` |
| `MergeTree` target을 미리 만들고 `RESTORE ... AS t_b` | `Code: 608 CANNOT_RESTORE_TABLE` (백업의 정의와 다름) |
| 미리 만들고 `SETTINGS allow_different_table_def = 1` | `RESTORED`. 1,000행, `sum(id)` 원본과 일치, 엔진 `MergeTree` |

```sql
CREATE TABLE default.t_b (id UInt32, v String) ENGINE = MergeTree ORDER BY id;

RESTORE TABLE default.t AS default.t_b
FROM File('/var/lib/clickhouse/backups/b1/')
SETTINGS allow_different_table_def = 1;
```

`allow_different_table_def`는 [백업 문서](https://clickhouse.com/docs/operations/backup/overview)에
나오는 설정이다. 문서 예시는 `MaterializedPostgreSQL` 정의를 `ReplacingMergeTree`로 복원하는
경우다. 그러니 "엔진 이름 때문에 불가능하다"는 말은 맞지 않는다. 다만 이 경로를 이관에
쓰기 전에 세 가지를 짚어야 한다.

- **실제 Cloud 백업으로는 확인하지 않았다.** 확인 안 된 것은 두 가지다. Cloud의
  `SharedMergeTree` 파트와 백업 레이아웃을 OSS가 읽을 수 있는지, 그리고 Cloud 버전이 OSS
  릴리스보다 앞설 때 파트 포맷이 맞는지. 쓰려면 Cloud 외부 백업 한 테이블로 먼저 시험한다.
- **공식 지원 경로로 문서화되어 있지 않다.**
- **백업은 한 시점의 스냅샷이다.** CDC 테이블은 백업 이후의 변경을 PeerDB가 이어받아야
  한다. 따라서 백업 복원은 런북 9장 `remoteSecure` 백필의 대안이 될 수는 있지만, PeerDB
  단계를 없애지는 못한다.

### 1.4 그래서 기본 경로는 데이터 복사다

테이블마다 어느 방식으로 옮길지는 런북 5장을 따르고, 백필은 9장 `remoteSecure`를 쓴다.
데이터가 커서 OSS가 Cloud에서 직접 당겨 오기 어렵다면 아래 두 방법을 대안으로 쓸 수 있다.
둘 다 이 저장소에서 실행하지 않았다.

```sql
-- Cloud에서 본인 S3로 export하고, OSS에서 같은 경로를 s3()로 읽어 INSERT
-- 자격 증명은 쿼리에 직접 쓰지 말고 런북 9.2처럼 named collection으로 넘긴다
INSERT INTO FUNCTION s3('https://<bucket>.s3.amazonaws.com/export/orders/{_partition_id}.parquet', 'Parquet')
PARTITION BY toYYYYMM(created_at)
SELECT * FROM analytics.orders;
```

```bash
clickhouse client --host <cloud-host> --secure --query "SELECT * FROM analytics.orders FORMAT Native" | clickhouse client --host <oss-host> --secure --query "INSERT INTO analytics.orders FORMAT Native"
```

어느 방법을 쓰든 파티션이나 날짜 범위로 나눠 재시도할 수 있게 하고, 검증은 런북 10.1을
따른다.

## 2. ClickPipes가 하던 CDC를 무엇이 대신하나

### 2.1 PeerDB OSS가 OSS를 destination으로 지원한다

ClickPipes는 ClickHouse Cloud로만 데이터를 보낸다. PeerDB README의 connector status 표를
보면 이 런북에 필요한 세 경로가 모두 **Actively maintained**다. MySQL과 MongoDB는 source로,
self-managed ClickHouse는 destination으로. 같은 README에는 PeerDB가 ClickHouse Cloud에
기본 기능으로 들어가 있다고도 적혀 있다(Postgres CDC ClickPipe). Kafka, S3, Snowflake 같은
destination은 deprecated지만 이 런북은 쓰지 않는다. 라이선스는 ELv2이니 조건은 PeerDB
저장소의 라이선스 파일에서 확인한다.

### 2.2 DocumentDB를 따로 처리하는 코드가 있다

"MongoDB 호환이니 되겠지" 수준이 아니다. PeerDB 소스에 DocumentDB 전용 분기가 있다
(main `942fb96`).

| 파일 | 내용 |
|---|---|
| `flow/pkg/mongo/validation.go` | `DocumentDBDomain = "docdb.amazonaws.com"`. `MinSupportedVersion = "4.4.0"`. `RequiredRoles`는 `readAnyDatabase`, `clusterMonitor` |
| `flow/pkg/mongo/validation.go` | DocumentDB는 storage engine과 oplog 보존 시간 정보를 주지 않는다. 그래서 `wiredTiger` 검사와 `MinOplogRetentionHours = 24` 검사를 **건너뛴다**. 보존 시간은 사람이 직접 맞춰야 한다(런북 7.1: `change_stream_log_retention_duration` 72시간 이상) |
| `flow/connectors/mongo/mongo.go` | 호스트에 `docdb.amazonaws.com`이 있으면 `DatabaseVariant_AWS_DOCUMENTDB`로 분기한다 |
| `flow/connectors/mongo/cdc.go` | change stream `Close()`를 호출한 쪽의 context와 분리한다. 주석에 이유가 적혀 있다: DocumentDB는 인스턴스당 cursor 수에 상한이 있어서 "too many cursors are already opened" 오류가 난다 |

이 디렉터리의 기능 검증(PeerDB `stable-v0.37.5`)에서는 DocumentDB 4.0이 wire version 7로
거부되었고, 8.0.1은 통과했다([`README.md`](./README.md)).

### 2.3 dual-run에서 주의할 두 가지

ClickPipes와 PeerDB를 동시에 돌리는 구간(런북 Phase 2)에서는 다음 두 가지가 근거다.

- **`_peerdb_version`은 캡처 시각이다.** `flow/connectors/clickhouse/normalize_query.go`는
  `_peerdb_timestamp`를 `_peerdb_version`으로 쓴다. 그래서 CDC-first + 백필(런북 5.2 M2)이
  `ReplacingMergeTree`에서 성립할 수 있다. 다만 런북에 적은 대로 고정한 버전에서 검증해야
  하는 승인 게이트다.
- **MySQL `server_id`는 명시한다.** `flow/connectors/mysql/cdc.go`는 설정이 없으면
  `[1000, MaxUint32)` 범위에서 임의로 고른다. ClickPipes의 값과 겹치면 MySQL이 replication
  연결 하나를 끊는다.

## 근거

- [Review and restore backups](https://clickhouse.com/docs/cloud/manage/backups/overview), [Export backups to your own cloud account](https://clickhouse.com/docs/cloud/manage/backups/export-backups-to-own-cloud-account), [Backup and restore](https://clickhouse.com/docs/operations/backup/overview), [OSS → Cloud backup/restore](https://clickhouse.com/docs/cloud/migration/oss-to-cloud-backup-restore): 2026-10-01에 읽음
- [PeerDB-io/peerdb](https://github.com/PeerDB-io/peerdb) README와 위 표의 소스 파일: main `942fb96` (2026-10-01)
- 로컬 재현: `clickhouse/clickhouse-server:26.9` (26.9.1.1629). `backups.allowed_path`만 추가한 컨테이너
