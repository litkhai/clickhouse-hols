# AI 작업지시서 — ClickHouse Cloud → OSS 전체 사이클 검증

> 이 문서는 AI 작업자가 격리된 AWS 검증 환경을 구축하고, source → ClickPipes → ClickHouse Cloud와 source → PeerDB → ClickHouse OSS의 dual-run, `remoteSecure` backfill, cutover, rollback, 장애 복구 및 자원 정리까지 증적과 함께 수행하기 위한 실행 지시서다.
>
> 기준 런북: [`clickhouse-cloud-to-self-managed-security-runbook.md`](./clickhouse-cloud-to-self-managed-security-runbook.md)

## 1. 최종 목표

합성 데이터만 사용하는 격리된 검증 환경에서 다음 경로를 실제로 확인한다.

```text
Amazon DocumentDB ─┬─ ClickPipes ─→ ClickHouse Cloud ─┐
                   └─ PeerDB ─────→ ClickHouse OSS    ├─ 대조/전환/rollback
RDS MySQL ─────────┬─ ClickPipes ─→ ClickHouse Cloud ─┤
                   └─ PeerDB ─────→ ClickHouse OSS    ┘

ClickHouse Cloud ── remoteSecure ─→ ClickHouse OSS
```

성공의 정의는 단순 설치가 아니다. 초기 적재, CDC INSERT/UPDATE/DELETE, dual-run 일치성, Cloud backfill, cutover, rollback, process/EC2 재시작 후 재개, backup/restore를 모두 통과하고 재현 가능한 로그와 최종 보고서를 남겨야 한다.

## 2. 작업 원칙

AI 작업자는 다음 규칙을 반드시 지킨다.

1. 실제 운영 database, credential, table을 사용하지 않는다.
2. 모든 AWS resource에 `Purpose=cloud-to-oss-validation`, `RunId=<UTC run id>`, `ExpiresAt=<UTC>` tag를 붙인다.
3. public IP를 만들지 않고 `0.0.0.0/0` inbound rule을 만들지 않는다.
4. 전송 구간 TLS, EBS/RDS/DocumentDB/S3 KMS 암호화를 기본으로 한다.
5. secret 값은 Terraform state, Git, 터미널 출력, 로그에 기록하지 않는다.
6. 명령 실행 전후 시각, exit code, resource ID와 검증 결과를 기록한다.
7. 실패를 숨기거나 성공으로 간주하지 않는다. 실패 로그와 재현 조건을 그대로 보존한다.
8. ClickPipes 또는 PeerDB의 고정 버전에서 MySQL/MongoDB connector가 지원되지 않으면 임의의 다른 도구로 바꾸지 말고 blocker로 보고한다.
9. 비용이 발생하는 리소스 생성 전 `terraform plan`과 예상 리소스 목록을 제시한다.
10. `terraform destroy`, RDS/DocumentDB 삭제, snapshot 삭제는 명시적인 사용자 승인 후에만 실행한다.

## 3. 사용자에게 받아야 할 입력

실행 전에 `test-runs/<run-id>/00-inputs-redacted.md`를 만들고 값 자체가 아닌 입력의 존재 여부만 기록한다.

필수 입력:

- AWS account/role과 region
- 기존 VPC, 서로 다른 AZ의 private subnet 최소 2개, route table, private hosted zone
- private subnet의 NAT 또는 승인된 package/container mirror 사용 가능 여부
- ClickHouse Cloud test service host, secure port, database와 migration credential
- ClickHouse Cloud IP access list를 변경할 권한 또는 담당자
- ClickPipes 2개를 생성할 권한 또는 담당자
- 테스트용 private DNS suffix
- TLS certificate 발급 방식과 CA
- 최대 허용 검증 시간과 예상 비용 상한
- 자원 삭제 승인자를 포함한 cleanup 방식

입력이 없으면 다음과 같이 처리한다.

- 기존 network가 없으면 새 VPC/NAT 생성안을 plan까지만 만들고 비용 승인을 요청한다.
- ClickHouse Cloud 또는 ClickPipes 권한이 없으면 AWS/OSS 경로까지만 몰래 진행하지 말고 명확한 user-action gate를 만든다.
- 인증서가 없으면 임시 private CA 발급 절차를 제안하되 개인 키를 Terraform state에 넣지 않는다.
- Amazon DocumentDB 4.0은 PeerDB `stable-v0.37.5` 검증에서 wire version 7로 거부됐다. 8.0.1은 통과했으며, 실제 대상인 5.0은 지원된다고 추정하지 말고 peer 생성 validation과 snapshot/CDC smoke test를 먼저 수행한다.

## 4. Run ID와 증적 디렉터리

Run ID 형식:

```text
YYYYMMDDTHHMMSSZ-<short-random>
```

작업 시작 시 다음 디렉터리를 만든다.

```text
test-runs/<run-id>/
├── 00-inputs-redacted.md
├── 01-preflight/
├── 02-plan/
├── 03-provision/
├── 04-bootstrap/
├── 05-source-fixtures/
├── 06-clickpipes-cloud/
├── 07-peerdb-oss/
├── 08-dual-run/
├── 09-remotesecure/
├── 10-cutover/
├── 11-rollback/
├── 12-failure-recovery/
├── 13-backup-restore/
├── 14-cleanup/
├── artifacts.sha256
└── SUMMARY.md
```

각 단계 디렉터리에는 최소한 다음을 저장한다.

- `commands.log`: secret을 제거한 실행 명령
- `stdout.log`, `stderr.log`: UTC timestamp가 붙은 출력
- `result.json`: 시작/종료 시각, exit code, 판정, 핵심 metric
- `resources.json`: 해당 단계에서 만든/변경한 resource ID
- `NOTES.md`: 가정, 수동 조작, 실패, 재시도와 원인

모든 로그는 UTF-8, UTC 기준으로 기록한다. 화면 캡처가 필요한 ClickHouse Cloud/ClickPipes/PeerDB UI 단계는 민감정보를 가린 PNG와 함께 동일 내용을 텍스트로 기록한다.

## 5. 로깅 표준

### 5.1 명령 wrapper

AI는 공통 wrapper를 만들어 모든 shell 명령을 실행한다. wrapper는 다음 정보를 남겨야 한다.

- `run_id`, `step_id`, hostname, UTC 시작/종료 시각
- 실행한 명령의 redacted form
- exit code와 실행 시간
- stdout/stderr 파일 위치
- 실패 시 마지막 100줄과 다음 조치

다음 값은 출력 전에 `[REDACTED]`로 치환한다.

- password, secret, token, private key
- AWS access key/session token
- ClickHouse Cloud credential
- database connection string의 user info
- DocumentDB/RDS master password
- PeerDB `.env` 내용

로그 파일 자체에 secret이 기록됐을 가능성이 있으면 공유하거나 commit하지 말고 격리한 뒤 새 credential로 rotate한다.

### 5.2 데이터 검증 기록

각 table/collection마다 다음을 JSON Lines로 남긴다.

```json
{"phase":"cdc","source":"mysql","object":"orders","expected_rows":10000,"cloud_rows":10000,"oss_rows":10000,"checksum_match":true,"lag_seconds":4,"checked_at":"<UTC>"}
```

검증 query에는 고유 `query_id=<run-id>-<step>-<sequence>`를 붙이고 ClickHouse `system.query_log`에서 duration, read/write rows, memory와 exception을 수집한다.

### 5.3 변경 원장

`change-ledger.jsonl`에 다음 사건을 순서대로 기록한다.

- source fixture INSERT
- source UPDATE
- source DELETE
- schema change
- ClickPipes/PeerDB pause/resume
- EC2/container restart
- Security Group fault injection과 복구
- cutover/rollback 시각

각 record는 `operation_id`, source transaction identifier/GTID 또는 change stream token, source commit UTC, Cloud 관측 UTC, OSS 관측 UTC를 포함한다.

## 6. 검증용 최소 사양

다음은 성능 시험이 아니라 기능 검증용 시작값이다.

| 역할 | 최소 사양 | 저장소 | 비고 |
|---|---|---|---|
| ClickHouse OSS EC2 | `t3.large`, 2 vCPU / 8 GiB | root gp3 30 GiB + data gp3 80 GiB | query concurrency 1~2로 제한 |
| PeerDB EC2 | `t3.xlarge`, 4 vCPU / 16 GiB | root gp3 30 GiB + state gp3 80 GiB | Temporal/catalog/worker 동시 실행 |
| RDS MySQL | `db.t4g.micro`, Single-AZ | gp3 20 GiB | synthetic fixture 전용 |
| Amazon DocumentDB | `db.t4g.medium`, instance 1개 | standard storage | 지원되는 가장 작은 T4g class |
| S3 stage/backup | private bucket | SSE-KMS | 1~7일 lifecycle |

사양 선택 규칙:

- 생성 전 AWS `describe-orderable-db-instance-options`와 DocumentDB region 지원 목록으로 class/engine 조합을 확인한다.
- `t3` capacity가 없으면 같은 크기의 x86 general-purpose instance로만 변경하고 이유를 기록한다.
- PeerDB OOM 또는 지속적인 CPU credit 고갈이 발생하면 먼저 동시성을 1로 낮추고, 그래도 실패하면 `m7i.xlarge` 4/16으로 변경한다.
- ClickHouse OOM이면 `max_threads=2`, query memory 3 GiB, external group/sort spill을 적용한다. 기능 검증에서 운영 크기인 16/64로 바로 올리지 않는다.
- burstable instance의 CPU credit 상태를 수집하며 이 결과를 운영 성능 근거로 사용하지 않는다.

DocumentDB `db.t4g.medium`은 2 vCPU/4 GiB이며 5.0을 지원한다. RDS MySQL은 리전에서 지원할 때 `db.t4g.micro`를 사용한다. 리전에서 지원하지 않는 조합은 가장 가까운 작은 class로 변경하되 plan과 보고서에 차이를 남긴다.

## 7. 코드 작성 범위

기존 [`terraform/`](./terraform/)은 운영 시작 사양을 위한 기준 코드이므로 기본값을 축소하지 않는다. AI는 다음 validation overlay를 별도로 만든다.

```text
validation/
├── terraform/
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── sources.tf
│   ├── security.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── fixtures/
│   ├── mysql/
│   └── documentdb/
├── scripts/
│   ├── run-logged.sh
│   ├── seed-mysql.sh
│   ├── seed-documentdb.sh
│   ├── mutate-sources.sh
│   ├── validate-counts.sh
│   ├── validate-checksums.sh
│   └── collect-evidence.sh
└── README.md
```

Terraform validation overlay 요구사항:

- 기존 VPC와 서로 다른 AZ의 private subnet 최소 2개 사용을 기본으로 한다. EC2 2대는 한 private subnet에 둘 수 있지만 RDS/DocumentDB subnet group은 2개 AZ를 포함한다.
- source와 EC2는 같은 VPC의 private subnet에 둔다.
- RDS와 DocumentDB subnet group은 최소 2개 AZ subnet 요구사항을 충족한다.
- RDS/DocumentDB inbound는 PeerDB SG와 승인된 fixture runner SG에서만 허용한다.
- ClickHouse 9440 inbound는 PeerDB SG에서만 허용한다.
- SSH 22는 열지 않고 SSM을 사용한다.
- IMDSv2를 필수로 한다. PeerDB container host만 hop limit 2를 사용한다.
- password는 `random_password` output이나 `tfvars`로 노출하지 않는다. 기존 Secrets Manager secret ARN을 입력받는다.
- RDS, DocumentDB, EBS, S3는 KMS 암호화를 사용한다.
- deletion protection은 test에서 false일 수 있으나 `prevent_destroy` 해제와 실제 destroy는 사용자 승인 gate로 분리한다.
- Cloud egress에 고정 NAT EIP가 필요하면 resource ID와 Cloud access-list 변경 내역을 기록한다.

## 8. Phase 0 — Preflight

다음을 실행하고 `01-preflight/`에 저장한다.

1. repository status와 기존 사용자 변경 확인
2. Terraform/CLI/Docker/ClickHouse client 버전 확인
3. `aws sts get-caller-identity`의 account/role만 기록
4. region, AZ, service quota, orderable DB class 확인
5. VPC DNS, private subnet route, NAT/VPC endpoint 확인
6. Secrets Manager ARN 존재와 접근 가능 여부 확인하되 값을 출력하지 않음
7. ClickHouse Cloud `SELECT version()`, timezone, service state 확인
8. ClickPipes/PeerDB 고정 version과 MySQL/MongoDB connector 지원 여부 확인
9. 예상 AWS resource와 시간당 비용을 표로 작성
10. `terraform fmt -check`, `terraform validate`와 lint 실행

Preflight fail 조건:

- 운영 리소스와 tag/name 충돌
- public exposure 필요
- TLS certificate hostname 불일치
- source engine/class가 해당 region에서 미지원
- ClickPipes 또는 PeerDB connector 호환성 미확인
- 비용 상한 또는 cleanup owner 부재

## 9. Phase 1 — AWS 인프라 생성

`terraform plan -out=tfplan`을 만들고 plan JSON을 redaction하여 저장한다. 다음 resource를 확인한 뒤 apply한다.

- RDS MySQL Single-AZ 1개
- DocumentDB 5.0 cluster와 instance 1개
- ClickHouse EC2 1대
- PeerDB EC2 1대
- EBS data/state volume 각 1개
- KMS key, S3 stage/backup bucket
- SG, IAM role/profile, private DNS

Apply 후 다음을 `03-provision/resources.json`에 기록한다.

- ARN/ID, private endpoint, private IP
- instance/engine version과 class
- EBS/S3 encryption key
- SG rule 요약
- 생성 시각과 `ExpiresAt`

AWS Config/CLI 확인으로 public IP 없음, public S3 차단, 암호화와 IMDSv2를 검증한다.

## 10. Phase 2 — Source CDC 준비

### 10.1 RDS MySQL

고정 PeerDB/ClickPipes 릴리스 요구사항을 먼저 확인한 뒤 전용 parameter group을 사용한다. 최소 검증 항목:

```sql
SHOW VARIABLES WHERE Variable_name IN (
  'binlog_format',
  'binlog_row_image',
  'binlog_checksum',
  'binlog_row_metadata',
  'gtid_mode',
  'enforce_gtid_consistency'
);
```

기대값은 connector 문서에 맞추며 일반적으로 ROW binlog, FULL row image와 `binlog_row_metadata=FULL`을 사용한다. PeerDB 검증 전 RDS `binlog retention hours`를 최소 24시간으로 설정하고 실제 값을 확인한다. static parameter 변경이면 reboot와 parameter 적용 시각을 기록한다. PeerDB와 ClickPipes마다 별도 최소 권한 CDC 사용자를 만들고 password는 Secrets Manager에서 주입한다.

fixture schema:

- `customers`: PK, nullable, Unicode, timestamp
- `orders`: PK, decimal, status, updated_at
- `order_items`: composite business key, quantity, amount
- `immutable_history`: `event_id`, `event_time`, payload; `remoteSecure` 전용

초기 데이터는 총 10,000~30,000 rows로 제한한다.

### 10.2 Amazon DocumentDB

- engine 5.0, instance 1개. 단, PeerDB 고정 릴리스의 MongoDB driver와 wire protocol 호환성을 peer validation으로 먼저 확인
- TLS와 AWS CA 검증
- test database/collections에 change stream 활성화
- retention은 검증 시간보다 길게 설정하되 최대 7일 범위
- PeerDB와 ClickPipes 전용 사용자 분리

Change stream 활성화 예시:

```javascript
db.adminCommand({
  modifyChangeStreams: 1,
  database: "validation",
  collection: "",
  enable: true
});
```

fixture collections:

- `profiles`: ObjectId/string key, nested object, array, nullable field
- `events`: append-only document와 event_time
- `mutable_docs`: INSERT/UPDATE/DELETE와 field add/remove 검증

초기 document는 총 5,000~10,000개로 제한한다. MongoDB와 DocumentDB의 동작 차이를 숨기지 말고 connector가 실제 DocumentDB 5.0에서 동작했는지 명시한다.

## 11. Phase 3 — ClickHouse OSS와 PeerDB bootstrap

기준 Terraform의 `user_data`를 validation overlay에서 재사용한다.

ClickHouse 검증:

- 별도 EBS가 `/var/lib/clickhouse`에 UUID mount됨
- 8443/9440 TLS listener만 열림
- 8123/9000/9010 닫힘
- certificate chain과 private DNS hostname 검증 성공
- `peerdb_ingest`가 PeerDB private IP `/32`로 제한됨
- test settings: `max_threads=2`, `max_memory_usage=3 GiB`, spill threshold 1 GiB

PeerDB 검증:

- Docker data root가 별도 EBS에 위치
- catalog, Temporal, Flow API/worker/snapshot worker, server/UI가 실행 중
- Temporal admin bootstrap이 `MirrorName` custom search attribute를 등록했으며 Flow service가 그 완료 이후 시작됨
- image tag 또는 digest가 기록됨
- UI/SQL endpoint가 loopback 또는 승인된 private CIDR에만 bind됨
- instance role로 S3 stage 접근 가능하며 static AWS key가 없음
- ClickHouse 9440 TLS/CA/hostname validation 성공

Bootstrap 로그와 실패 시 `journalctl`, `cloud-init`, `docker compose logs`를 `04-bootstrap/`에 저장한다.

## 12. Phase 4 — ClickPipes → Cloud 기준선

MySQL과 DocumentDB용 ClickPipe를 각각 하나 만든다. 자동화 가능한 공식 API가 없거나 권한이 부족하면 수동 작업 gate를 열고 다음을 기록한다.

- pipe 이름과 source type
- 선택 table/collection
- initial load 시작/종료 UTC
- CDC running 전환 UTC
- checkpoint/상태와 error
- Cloud target table DDL
- row/document count와 canonical checksum

두 pipe가 Running이고 Cloud count/checksum이 source와 일치하기 전에는 PeerDB dual-run으로 넘어가지 않는다.

## 13. Phase 5 — PeerDB → OSS 기준선

PeerDB에 다음 peer를 만든다.

- RDS MySQL source peer
- DocumentDB/MongoDB source peer
- ClickHouse OSS target peer: private DNS, 9440, TLS ON, CA 검증

MySQL과 DocumentDB mirror를 분리해서 만들고 initial snapshot concurrency는 1로 둔다. target database는 Cloud table과 충돌하지 않는 `peerdb_validation`을 사용한다.

PeerDB용 ClickHouse 권한:

```sql
CREATE DATABASE IF NOT EXISTS peerdb_validation;
CREATE ROLE IF NOT EXISTS peerdb_validation_writer;
GRANT INSERT, SELECT, DROP, CREATE TABLE
    ON peerdb_validation.* TO peerdb_validation_writer;
GRANT CREATE TEMPORARY TABLE, S3 ON *.* TO peerdb_validation_writer;
GRANT ALTER ADD COLUMN
    ON peerdb_validation.* TO peerdb_validation_writer;
GRANT peerdb_validation_writer TO peerdb_ingest;
```

고정 릴리스가 요구하지 않는 권한은 제거한다. initial snapshot 완료 후 source/Cloud/OSS count와 checksum을 비교한다.

## 14. Phase 6 — Dual-run CDC

fixture generator는 deterministic seed와 `operation_id`를 사용한다. 각 source에서 다음을 최소 3회 batch로 수행한다.

- INSERT 200건
- UPDATE 50건
- DELETE 20건
- nullable 값 변경
- Unicode/emoji 문자열
- MySQL transaction commit/rollback
- DocumentDB nested field add/remove와 array 변경
- 지원되는 범위에서 schema evolution column/field 추가

각 batch 후 다음을 확인한다.

1. ClickPipes/Cloud와 PeerDB/OSS 양쪽에 예상 변경 도착
2. 최종 business key별 상태 일치
3. delete 처리 방식과 `_peerdb_is_deleted` 의미 일치
4. duplicate logical rows 없음 또는 ReplacingMergeTree FINAL 결과 일치
5. lag가 승인한 test SLO 이내
6. source cursor/GTID 또는 change stream resume 상태 기록

raw row 순서나 내부 ingestion timestamp가 아니라 canonical business columns로 checksum을 계산한다.

## 15. Phase 7 — `remoteSecure` backfill

Cloud credential은 ClickHouse server의 named collection 또는 외부 secret 경로로만 사용한다. query text와 `system.query_log`에 password가 나타나지 않게 한다.

두 방식을 분리해 검증한다.

### 15.1 안전한 기본 방식

- CDC 대상이 아닌 `immutable_history`를 Cloud에서 OSS로 복사
- month/day partition 단위로 `INSERT SELECT FROM remoteSecure(...)`
- partition별 count, min/max time, checksum 기록
- 같은 partition 재실행 시 중복 방지 절차 확인

### 15.2 CDC-first + backfill 방식

다음 gate를 모두 통과한 작은 test table에만 수행한다.

- immutable PK 존재
- Cloud history와 새 CDC의 경계 timestamp/GTID 기록
- target ReplacingMergeTree version 의미 확인
- PeerDB와 backfill의 version/metadata 충돌 없음
- dry-run duplicate query 통과

동일 target에 무조건 겹쳐 쓰지 않는다. gate가 실패하면 staging table로 backfill 후 검증된 merge를 수행하고 이를 결과에 기록한다.

## 16. Phase 8 — Cutover simulation

Cutover는 application write target 변경이 아니라 read endpoint를 Cloud에서 OSS로 전환하는 simulation이다. source DB가 system of record이며 ClickPipes와 PeerDB는 계속 source CDC를 읽는다.

순서:

1. fixture writer 일시 정지
2. 두 pipeline lag 0 또는 승인 threshold 도달 대기
3. final count/checksum과 delete reconciliation
4. read alias/config를 OSS로 전환
5. 대표 SELECT 20개를 실행해 결과/latency/error 비교
6. fixture writer 재개 후 신규 100건 확인
7. 30분 observation 또는 합의한 축소 시간 유지

Cutover timestamp, 승인자, 최종 source cursor, Cloud/OSS count를 `10-cutover/cutover-record.json`에 남긴다.

## 17. Phase 9 — Rollback simulation

기존 ClickPipes를 중지하지 않은 상태에서 다음을 수행한다.

1. read alias/config를 Cloud로 되돌림
2. rollback window 중 발생한 source 변경이 Cloud에도 도착했는지 확인
3. 대표 SELECT와 checksum 재검증
4. OSS PeerDB mirror는 관측을 위해 유지하거나 명시적으로 pause
5. rollback 원인, 시각, 소요 시간, 데이터 손실 여부 기록

Rollback success 기준은 Cloud read path 복구뿐 아니라 RPO/RTO 측정과 양쪽 pipeline의 cursor 연속성 확인까지 포함한다.

## 18. Phase 10 — 장애와 재개 검증

한 번에 하나의 장애만 주입하고 즉시 복구 가능하도록 원상복구 명령을 먼저 준비한다.

필수 시나리오:

1. `flow-worker` container restart
2. PeerDB 전체 Compose restart
3. PeerDB EC2 reboot
4. ClickHouse service restart
5. ClickHouse EC2 reboot
6. PeerDB → ClickHouse 9440 SG rule을 2~3분 차단 후 복구
7. source 연결을 짧게 차단 후 복구

각 시나리오에서 확인한다.

- mirror가 수동 resnapshot 없이 재개되는가
- duplicate/missing event가 없는가
- lag가 정상 범위로 회복되는가
- Temporal/catalog checkpoint가 보존되는가
- ClickHouse EBS mount가 reboot 후 유지되는가
- TLS가 복구 과정에서 우회되지 않는가

source retention을 초과하는 장시간 장애는 별도 destructive/비용 승인 없이는 실행하지 않는다.

## 19. Phase 11 — Backup/restore 검증

ClickHouse:

- S3 backup 생성
- backup manifest와 encryption 확인
- 별도 `restore_validation` database로 restore
- count/checksum과 대표 query 검증

PeerDB:

- catalog PostgreSQL logical backup
- PeerDB state EBS snapshot
- image tag/digest와 Compose config의 redacted copy
- 별도 임시 database/volume에서 catalog restore 검증
- mirror definition과 마지막 checkpoint 조회

RDS/DocumentDB:

- 자동 backup 설정과 retention 확인
- 최종 snapshot 생성 여부는 비용/cleanup 정책에 따라 결정

Backup 파일을 만들었다는 사실만으로 통과시키지 말고 restore 결과까지 기록한다.

## 20. Phase 12 — 결과 판정

모든 항목을 Pass/Fail/Blocked/Not Applicable로 기록한다.

필수 통과 기준:

- 4개 ingestion path의 initial load 성공
- MySQL과 DocumentDB INSERT/UPDATE/DELETE 최종 상태 일치
- TLS negative test 성공
- `remoteSecure` partition backfill count/checksum 일치
- cutover와 rollback이 목표 RPO/RTO 안에서 완료
- PeerDB/ClickHouse restart 후 CDC 자동 재개
- backup restore count/checksum 일치
- public exposure와 plaintext DB port 없음
- unredacted secret이 로그/Git/Terraform state에 없음

하나라도 실패하면 전체 결과를 `PASS WITH EXCEPTIONS`가 아닌 `FAIL` 또는 `BLOCKED`로 분류하고, 운영 전환 조건을 별도로 적는다.

## 21. `SUMMARY.md` 형식

최종 보고서는 다음 순서를 따른다.

1. Executive summary와 최종 판정
2. 검증한 version/region/resource 사양
3. 아키텍처와 실제 resource inventory
4. 단계별 시작/종료/소요 시간
5. count/checksum/lag 비교표
6. cutover RTO와 관측 RPO
7. rollback RTO와 관측 RPO
8. 장애 시나리오별 회복 결과
9. backup/restore 결과
10. 보안 통제 결과
11. 실패, 우회, 수동 작업과 미검증 항목
12. 운영 사양으로 전환할 때 변경할 값
13. 비용 요약
14. cleanup 상태와 남은 resource
15. 증적 파일 링크와 SHA-256 manifest

운영 권장 16/64 ClickHouse, 8/32 PeerDB와 validation 사양 결과를 직접 성능 비교하지 않는다. 검증 환경은 기능과 절차 확인용이라고 명시한다.

## 22. Cleanup gate

테스트가 끝나면 즉시 destroy하지 않는다.

1. 남은 resource와 시간당/일별 비용을 출력한다.
2. 보존할 log, snapshot, backup bucket 목록을 제시한다.
3. `terraform plan -destroy`를 저장하고 삭제 대상을 정확히 보여준다.
4. 사용자에게 명시적 cleanup 승인을 요청한다.
5. 승인 후 ClickPipes/mirror 중지, Cloud test object 정리, AWS destroy 순서로 진행한다.
6. 삭제 API 결과와 잔존 resource scan을 `14-cleanup/`에 저장한다.
7. secret 삭제는 별도 승인과 recovery window를 적용한다.

삭제 후에도 비용이 발생할 수 있는 항목을 별도로 확인한다.

- NAT gateway와 Elastic IP
- RDS/DocumentDB snapshot
- EBS snapshot/volume
- S3 versioned object
- CloudWatch log group
- KMS key
- ClickHouse Cloud service와 ClickPipes

## 23. 중단 및 사용자 확인 조건

다음 상황에서는 추측해서 진행하지 말고 증적을 남긴 뒤 사용자에게 확인한다.

- 운영 resource일 가능성이 있음
- 예상 월/일 비용이 승인 상한을 초과함
- public endpoint 또는 광범위 CIDR이 필요함
- ClickHouse Cloud access-list/ClickPipes 변경 권한이 없음
- source connector가 실제 고정 version에서 미지원 또는 beta 제한에 걸림
- TLS를 꺼야만 진행되는 것으로 보임
- 데이터 삭제, snapshot 삭제, KMS key 삭제가 필요함
- checksum 불일치 원인이 밝혀지지 않음

## 24. 참고 자료

- [Amazon DocumentDB instance classes](https://docs.aws.amazon.com/documentdb/latest/devguide/db-instance-classes.html)
- [Amazon DocumentDB change streams](https://docs.aws.amazon.com/documentdb/latest/devguide/change_streams.html)
- [Amazon RDS 개요와 지원되는 소형 instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html)
- [PeerDB supported connectors](https://docs.peerdb.io/features/supported-connectors)
- [PeerDB ClickHouse target 설정과 권한](https://docs.peerdb.io/connect/clickhouse/clickhouse)
- [PeerDB CDC mirror API](https://docs.peerdb.io/peerdb-api/endpoints/create-mirror)
- [ClickHouse `remoteSecure`](https://clickhouse.com/docs/reference/functions/table-functions/remote)
- [ClickHouse backup/restore](https://clickhouse.com/docs/concepts/features/backup-restore/overview)
