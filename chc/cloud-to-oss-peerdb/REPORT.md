# ClickHouse Cloud → Self-managed OSS 마이그레이션: PeerDB 기능 검증 보고서

| 항목 | 내용 |
|---|---|
| 검증일 | 2026-09-07 (UTC) |
| 대상 | Amazon RDS for MySQL, Amazon DocumentDB → PeerDB → ClickHouse OSS |
| 리전 | ap-northeast-2 (Seoul) |
| 최종 판정 | **PASS (기능 검증 통과)** |

> 이 문서는 사내/샌드박스 AWS 계정에서 수행한 1회성 기능 검증 기록입니다. 계정 ID, IAM
> 자격증명, 인스턴스 엔드포인트, IP 주소, 그 외 계정을 특정하거나 무관한 다른 프로젝트를
> 노출할 수 있는 정보는 모두 제거했습니다. 검증에 사용한 모든 AWS 리소스는 검증 종료 후
> 전량 삭제했습니다.

---

## 1. 목적과 범위

### 1.1 배경

`cloud-to-oss` 런북(`AI-VALIDATION-WORK-INSTRUCTIONS.md`,
`clickhouse-cloud-to-self-managed-security-runbook.md`)은 원래 ClickHouse Cloud에서
self-managed ClickHouse OSS로 전환하는 전체 절차 — source → ClickPipes → ClickHouse Cloud와
source → PeerDB → ClickHouse OSS의 dual-run 대조, `remoteSecure` backfill, cutover, rollback,
장애 복구, 자원 정리까지 — 를 다룬다. 이번 검증은 그 런북 중 **PeerDB를 이용한 데이터 이관
경로만을 격리된 환경에서 기능적으로 검증**하는 것을 목표로 진행했다.

### 1.2 범위 결정 (진행 중 두 차례 축소)

**1차 축소 — 보안 기능 제외:** 성능/보안 하드닝 검증이 아니라 기능 동작 여부 확인이
목적이므로, **TLS/mTLS, KMS를 포함한 저장/전송 구간 암호화, PrivateLink, private subnet
격리 등 모든 보안 통제 항목을 이번 검증에서 완전히 제외**하기로 결정했다. ClickHouse OSS는
평문 포트(8123/9000)로, PeerDB↔ClickHouse 간 통신도 TLS 없이, 컴퓨트 자원은 인터넷 게이트웨이가
연결된 public subnet에 배치했으며 접근 제한은 Security Group 룰로만 걸었다. DocumentDB의 TLS도
명시적으로 비활성화했다.

> **이 검증 결과는 보안이 검증되었다는 의미가 아니라, 보안 검증을 아예 시도하지 않았다는
> 의미다.** 운영 전환 전에는 원 런북의 SEC-2(Production Secure) 이상 프로파일 기준으로 반드시
> 별도 재검증이 필요하다.

**2차 축소 — PeerDB 경로만 남기고 나머지 제외:** ClickPipes 생성/구성, ClickHouse Cloud와
OSS 경로의 dual-run 대조, `remoteSecure` 를 통한 기존 Cloud 데이터 backfill, cutover/rollback
시뮬레이션, 장애 주입 시나리오, backup/restore 드릴은 모두 범위에서 제외했다. 최종 목표는
**"PeerDB로 RDS MySQL과 DocumentDB의 데이터를 ClickHouse OSS로 옮기고, 초기 적재와
CDC(INSERT/UPDATE/DELETE)가 기능적으로 정상 동작하는지 확인"** 으로 좁혔다.

---

## 2. 검증 환경

| 구성 요소 | 버전/사양 | 비고 |
|---|---|---|
| ClickHouse OSS | 26.8.2.7 (`lts` apt 채널) | 단일 노드, 평문 8123/9000 |
| PeerDB | `stable-v0.37.5` | flow-api/flow-worker/flow-snapshot-worker/peerdb-server/peerdb-ui 전체 동일 태그 |
| RDS MySQL | 8.0.42 | `db.t4g.micro`, gp3 20 GiB, Single-AZ |
| Amazon DocumentDB | 8.0.1 | `db.t4g.medium`, 인스턴스 1개 (최초 4.0.0으로 생성했다가 재생성 — 3.2절 참조) |
| ClickHouse OSS 컴퓨트 | 2 vCPU / 8 GiB | gp3 50 GiB 단일 root 볼륨 (별도 데이터 볼륨 생략) |
| PeerDB 컴퓨트 | 4 vCPU / 16 GiB | gp3 60 GiB root, Docker Compose 스택 |
| Staging(S3 호환) | Self-hosted MinIO | ClickHouse 타깃 미러는 반드시 S3 호환 스테이징을 거침 (3.2절) |
| 네트워크 | 기본 VPC, public subnet | private subnet/NAT 없음, 접근 제어는 Security Group으로만 |

모든 리소스는 검증 전용 태그로 표시해 다른 목적의 기존 리소스와 분리했으며, 검증 종료 후
전량 삭제했다 (§6).

---

## 3. 수행 내역 상세

### 3.1 사전 점검 및 인프라 구성

- 원본 런북의 Terraform(TLS·KMS·Secrets Manager·private subnet 전제)은 보안 검토 제외
  방침과 맞지 않아 재사용하지 않고, 최소 구성을 별도로 조립했다.
- 기본 VPC에 NAT/private subnet이 없어(전부 public subnet) 컴퓨트 자원을 public subnet에
  두고 Security Group으로만 접근을 제한했다.
- Security Group 4개(RDS/DocumentDB/ClickHouse/PeerDB) 생성, 필요한 트래픽만 상호 참조
  방식으로 허용.
- RDS MySQL: 전용 파라미터 그룹에 `binlog_format=ROW`, `binlog_row_image=FULL` 설정.
  (GTID는 단계적 전환 절차가 필요해 시간 절약을 위해 생략 — CDC 자체에는 필수가 아님.)
- DocumentDB: 전용 클러스터 파라미터 그룹에 `tls=disabled` 설정(보안 검토 제외 방침에 따름).
- IAM 인스턴스 role/profile 생성 시도 중, 해당 계정의 조직 SCP가 `iam:CreateUser`/
  `iam:CreateAccessKey`를 명시적으로 차단하고 있음을 확인했다(공유 샌드박스 계정의
  가드레일). 이 때문에 애초 계획했던 "실제 S3 버킷 + 정적 액세스 키" 방식의 PeerDB 스테이징을
  포기하고 self-hosted MinIO로 전환했다(3.2절).

### 3.2 부트스트랩 중 발생한 문제와 해결 (핵심 트러블슈팅 기록)

아래는 이번 검증에서 실제로 시간이 가장 많이 소요된 부분이며, 향후 동일 작업을 반복할 때
참고할 가치가 크다.

**(1) ClickHouse `default` 사용자 인증 충돌** — users.d 오버라이드에서 `replace="1"`을
빠뜨려 패키지 기본 `default` 사용자 정의와 병합되면서 "Cannot specify multiple authentication
methods" 오류로 서비스가 크래시 루프에 빠짐. `<default replace="1">`로 수정.

**(2) XML로 정의한 사용자에 대한 SQL GRANT 불가** — `peerdb_ingest` 사용자를 users.xml로
정의했더니 `ACCESS_STORAGE_READONLY` 오류로 SQL `GRANT`가 불가능. XML 정의를 제거하고 SQL
기반 사용자(`CREATE USER ... IDENTIFIED WITH sha256_hash`)로 재생성.

**(3) `CREATE TEMPORARY TABLE` 권한 스코프 오류** — DB 레벨(`ON db.*`)로 부여 시도 시 오류.
전역(`ON *.*`)으로만 부여 가능.

**(4) PeerDB 이미지 태그 오류** — 최초 `v0.37.5` 태그로 `flow-snapshot-worker` pull
실패("not found"). PeerDB 공식 `docker-compose.yml`(GitHub)을 대조해 정확한 태그 형식이
`stable-v0.37.5`임을 확인 후 수정.

**(5) ClickHouse 타깃 미러의 S3 스테이징 필수 요구 사항 — 가장 오래 걸린 이슈** — PeerDB에서
ClickHouse를 타깃으로 하는 미러는 **예외 없이 S3 호환 스테이징 버킷을 거쳐야 한다**
(ClickHouse의 `s3()` 테이블 함수로 다시 읽어들이는 구조). 처음 만든 Compose 파일에는 PeerDB
공식 예제에 있는 `minio` 서비스가 빠져 있었다. 이후 다음 문제가 연쇄적으로 발생했다.

  - MinIO 컨테이너에 PeerDB가 사용할 자격 증명 환경변수만 설정하고 MinIO 자신의 루트
    계정 환경변수를 빠뜨려, MinIO가 기본값(`minioadmin`)으로 기동됨. 이 상태에서 PeerDB가
    우리가 설정한 자격 증명으로 접근을 시도하니 "InvalidAccessKeyId" 오류가 발생했는데, 이
    오류 메시지의 형식이 실제 AWS S3 오류와 거의 동일해 처음에는 "실제 AWS S3로 잘못 나가고
    있다"고 오판했다 — 실제로는 **MinIO 자신이 반환한 오류**였다.
  - 스테이징 엔드포인트를 Docker 내부 네트워크 이름으로 설정했는데, ClickHouse OSS는
    **다른 호스트**에서 실행 중이라 이 이름을 resolve할 수 없음. MinIO 포트를 호스트에
    게시하고 실제 도달 가능한 사설 IP로 endpoint를 변경, 해당 포트를 ClickHouse 쪽 Security
    Group에서 허용하도록 수정.
  - PeerDB의 SQL `CREATE PEER ... FROM CLICKHOUSE` 문법은 (공개 GitHub 소스로 직접 확인한
    결과) 항상 중첩 S3 설정 필드를 비워둔다 — 대신 평면(flat) 형태의
    `s3_path`/`access_key_id`/`secret_access_key`/`region`/`endpoint` WITH-옵션이 실제로
    사용됨을 소스 코드에서 확인하고 그 방식으로 전환했다.

**(6) MySQL peer `flavor` 미지정 오류** — 공식 문서 예제에는 없지만 `flavor='mysql'`을
명시하지 않으면 "flavor is set to unknown"으로 검증 실패.

**(7) MySQL CDC 검증 추가 요구 사항** —
- `binlog retention hours`가 최소 24시간 이상이어야 함 → RDS 설정 프로시저로 조정.
- `binlog_row_metadata=FULL`이어야 함(원 런북 체크리스트에는 `binlog_format`/
  `binlog_row_image`만 언급되고 이 항목은 없었음) → 파라미터 그룹 수정 후 **재부팅 두 번**
  필요(첫 재부팅 시점에 파라미터 그룹 변경이 아직 propagate되지 않아 반영 안 됨).

**(8) Mongo peer 자격 증명/옵션 파싱** —
- 연결 URI에 자격 증명을 포함해도 사용자명/비밀번호를 별도 WITH-옵션으로 또 지정해야 함.
- `read_preference`는 열거형 이름이 아니라 **숫자값**으로 지정해야 함 — SQL 파서가 정수
  파싱만 시도함을 소스에서 확인.
- 필요한 DocumentDB 권한: 일반적인 읽기 권한만으로는 부족하고 **`clusterMonitor`** 역할이
  추가로 필요("missing required role: clusterMonitor").

**(9) DocumentDB 엔진 버전 비호환 — 재생성 필요 (가장 근본적인 발견)** — 최초 생성한
DocumentDB 4.0.0에 대해 Mongo peer 생성 시도 시 다음과 같은 오류로 완전히 막혔다.

```
server ... reports wire version 7, but this version of the Go driver requires
at least 8 (MongoDB 4.2)
```

PeerDB의 MongoDB 커넥터(Go 드라이버)는 MongoDB 4.2 이상 호환 wire protocol(버전 8+)을
요구하는데, DocumentDB 4.0은 wire version 7까지만 지원한다. 인스턴스 클래스를 지정하지 않고
전체 조회한 결과 같은 인스턴스 클래스로도 엔진 8.0.1을 만들 수 있음을 확인, 클러스터를
삭제 후 8.0.1로 재생성했다.

> **향후 실제 마이그레이션 계획 시 가장 먼저 확인해야 할 항목:** 소스 DocumentDB의 엔진
> 버전이 PeerDB Mongo 커넥터의 wire protocol 요구사항(버전 8 이상)을 충족하는지 사전에
> 반드시 검증할 것.

**(10) Temporal 커스텀 검색 속성(Search Attribute) 미등록** — 미러 생성 시 "Namespace
default has no mapping defined for search attribute MirrorName" 오류. 이 요구사항은 PeerDB의
미러 생성 문서 어디에도 명시되어 있지 않고, PeerDB 공식 `docker-compose.yml`의
`temporal-admin-tools` 서비스(초기 구성에는 없었음)가 기동 시 자동 등록해주는 것이었다.
Temporal 관리 CLI로 해당 검색 속성을 1회 등록해 해결했다.

**(11) 위 (9)(10) 해결 전에 시도했던 미러 생성이 catalog에 고아 레코드로 남는 문제** —
Temporal 오류로 워크플로우가 시작되지 못한 상태에서 미러 삭제를 시도하면 "workflow not
found"로 실패하고, 재생성 시도는 "mirror already exists"로 막히는 교착 상태가 발생했다.
PeerDB catalog(내부 Postgres)에 직접 접속해 관련 레코드를 수동 삭제해 복구했다.

### 3.3 소스 데이터(Fixture) 구성

**RDS MySQL**

| 테이블 | 초기 행 수 | 비고 |
|---|---:|---|
| `customers` | 200 | nullable 필드, 유니코드/이모지 포함 |
| `orders` | 500 | decimal 금액, status enum |
| `order_items` | 1,000 | 복합 PK(`order_id, line_no`) |

**Amazon DocumentDB**

| 컬렉션 | 초기 문서 수 | 비고 |
|---|---:|---|
| `profiles` | 150 | nullable 필드, nested object, array, 유니코드/이모지 |
| `events` | 300 | append-only 패턴 |
| `mutable_docs` | 100 | UPDATE/DELETE 검증 대상 |

DocumentDB 시딩 시에도 엔진 버전 이슈가 재발했다: 최초 4.0.0에서는 최신 `mongosh`(wire
version 8+ 요구)가 호환되지 않아 레거시 `mongo` 셸(4.0)로 시딩해야 했고, 8.0.1로 재생성한
뒤에는 최신 `mongosh`를 사용했다.

### 3.4 PeerDB Peer/Mirror 구성

- ClickHouse 타깃 peer: 3.2절 (5)의 해결책대로 평면 S3 옵션으로 MinIO 스테이징을 명시.
- MySQL 소스 peer → 미러: `customers`, `orders`, `order_items` 매핑, 초기 스냅샷 포함.
- Mongo 소스 peer → 미러: `profiles`, `events`, `mutable_docs` 매핑, 초기 스냅샷 포함.

### 3.5 검증 결과

**초기 스냅샷 (전수 일치)**

| 테이블/컬렉션 | 소스 | ClickHouse OSS (`FINAL`) | 결과 |
|---|---:|---:|---|
| customers | 200 | 200 | 일치 |
| orders | 500 | 500 | 일치 |
| order_items | 1,000 | 1,000 | 일치 |
| profiles | 150 | 150 | 일치 |
| events | 300 | 300 | 일치 |
| mutable_docs | 100 | 100 | 일치 |

**CDC 배치 검증 (INSERT/UPDATE/DELETE)**

| 소스 | 연산 | 내용 | ClickHouse OSS 결과 |
|---|---|---|---|
| MySQL | INSERT | `customers` 20건 추가 (200→220) | `count() FINAL` = 220 — 일치 |
| MySQL | UPDATE | `orders` 10건 status 변경 | 10/10 반영 확인 |
| MySQL | DELETE | `order_items` 5건 삭제 | `sum(_peerdb_is_deleted)` = 5 — 전부 정상 tombstone 처리 |
| DocumentDB | INSERT | `profiles` 20건 추가 (150→170) | `count() FINAL WHERE NOT _peerdb_is_deleted` = 170 — 일치 |
| DocumentDB | UPDATE | `mutable_docs` 10건 상태 변경 | 10/10 반영 확인 |
| DocumentDB | DELETE | `events` 5건 삭제 | `sum(_peerdb_is_deleted)` = 5 — 전부 정상 tombstone 처리 |

CDC 반영 지연은 이 데이터 규모에서 사실상 즉시(첫 폴링인 약 15초 이내)였다.

**스키마 관련 참고 사항:** PeerDB의 MongoDB→ClickHouse 미러는 문서를 필드별로 펼치지 않고
`_id`, `doc`(JSON 텍스트 String), `_peerdb_synced_at`, `_peerdb_is_deleted`,
`_peerdb_version` 형태로 저장한다. 중첩 필드 조회 시 `JSONExtractString(doc, '<field>')`가
필요하며, `_id`는 String 타입으로 저장되므로 숫자 비교 시 명시적 캐스팅이 필요하다.

---

## 4. 최종 판정

**PASS** — PeerDB는 RDS MySQL과 Amazon DocumentDB 양쪽 모두에서 ClickHouse OSS로의 초기
적재와 CDC(삽입/수정/삭제)를 기능적으로 정상 수행했다. 단, 이 판정은 다음을 전제로 한다.

- 성능/부하 검증이 아님 (최소 사양, 소규모 데이터셋)
- **보안 통제(TLS/mTLS/암호화/네트워크 격리)는 검증 대상에서 완전히 제외됨** — 운영 전환 전
  별도 재검증 필수
- ClickPipes 대조, `remoteSecure` backfill, cutover/rollback, 장애 주입, backup/restore는
  수행하지 않음

---

## 5. 향후 실제 마이그레이션 시 반영해야 할 사항

1. **DocumentDB 엔진 버전을 계획 최초 단계에서 확정할 것.** PeerDB Mongo 커넥터는 wire
   protocol 8 이상을 요구하므로, 최소 엔진 8.0 계열을 사용해야 한다.
2. PeerDB 자체 문서(docs.peerdb.io)는 MySQL/Mongo 커넥터에 대해 곳곳이 오래됐거나
   불완전하다. 실제 동작 확인이 필요하면 공개 GitHub 저장소의 해당 릴리스 태그에 대응하는
   proto 정의, SQL 파서 소스, 공식 `docker-compose.yml`을 직접 대조하는 편이 빠르다.
3. ClickHouse를 타깃으로 하는 PeerDB 미러는 반드시 S3 호환 스테이징이 필요하며, 스테이징
   엔드포인트는 **ClickHouse 서버 자신도 도달 가능해야 한다**(PeerDB 컨테이너뿐 아니라).
4. Temporal의 `MirrorName` 커스텀 검색 속성 등록은 PeerDB 최초 기동 시 반드시 수행해야 하는
   숨은 전제 조건이다.
5. RDS MySQL CDC에는 `binlog_format=ROW`/`binlog_row_image=FULL` 외에
   `binlog_row_metadata=FULL`과 `binlog retention hours ≥ 24`가 추가로 필요하다.
6. 이번에는 시간 관계상 GTID 설정을 생략했다 — 운영 환경에서는 원 런북대로 GTID 활성화를
   재검토할 것.
7. 보안 통제 재검증 시 원 런북(`clickhouse-cloud-to-self-managed-security-runbook.md`)의
   SEC-2 프로파일 체크리스트를 그대로 적용할 것.

---

## 6. 자원 정리

검증에 사용한 모든 AWS 리소스(EC2 2대, RDS MySQL, DocumentDB 클러스터/인스턴스, S3 스테이징
버킷, Security Group, IAM role/instance profile, 파라미터/서브넷 그룹)는 검증 완료 후
전량 삭제했다.
