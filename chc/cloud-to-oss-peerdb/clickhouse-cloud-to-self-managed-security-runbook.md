# ClickHouse Cloud → Self-managed ClickHouse 마이그레이션 런북

> 고객 검토용 초안
>
> 대상: Amazon DocumentDB 5.0, AWS RDS MySQL, ClickPipes, self-hosted PeerDB, ClickHouse OSS
>
> 배포 기준: PeerDB 스택 1 EC2 + ClickHouse 단일 노드 1 EC2, 일반 EBS(gp3)
>
> 목적: ClickPipes를 PeerDB로 전환하고, ClickHouse Cloud의 기존 데이터를 `remoteSecure`로 이관하면서 보안 수준과 EC2 사이징을 명시적으로 선택한다.

## 1. 문서 사용 방법

이 문서는 하나의 고정된 구성을 강제하지 않는다. 먼저 2절에서 보안 프로파일을 선택하고, 3절의 의사결정표에 선택 결과와 예외를 기록한 다음 해당 프로파일에 맞춰 구축·이관·검증한다.

격리된 AWS 환경에서 전체 절차를 실행하는 AI 작업자는 [`AI-VALIDATION-WORK-INSTRUCTIONS.md`](./AI-VALIDATION-WORK-INSTRUCTIONS.md)를 함께 사용한다. 해당 지시서는 최소 사양의 DocumentDB, RDS MySQL, ClickHouse EC2와 PeerDB EC2를 이용한 initial load, CDC dual-run, `remoteSecure`, cutover, rollback, 장애 복구, backup/restore와 증적 수집 범위를 정의한다.

운영 환경의 기본 권고는 **SEC-2(Production Secure)** 이다. 보안 기능을 끄는 선택은 개발·격리 환경 또는 기한이 정해진 호환성 예외에만 허용한다.

다음 원칙은 모든 프로파일에 공통이다.

- ClickHouse Cloud의 관리형 인증서와 개인 키는 self-managed 환경으로 복사하지 않는다. 고객 소유 DNS와 PKI로 새 인증서를 발급한다.
- Cloud의 보안 설정을 파일 단위로 복제하는 것이 아니라 암호화, 접근 통제, 감사, 백업이라는 **통제 목표**를 재구현한다.
- `remoteSecure`는 일회성/구간별 이관 수단이지 CDC가 아니다.
- ClickPipes의 체크포인트가 PeerDB로 승계된다고 가정하지 않는다.
- 같은 대상 테이블에 PeerDB와 `remoteSecure`를 겹쳐 쓰는 방식은 5.2절의 호환성 게이트를 통과한 경우에만 사용한다.
- 모든 예외에는 사유, 소유자, 만료일, 제거 조건을 기록한다.

## 2. 보안 프로파일 선택

### 2.1 프로파일 정의

| 항목 | SEC-0 Lab Only | SEC-1 Transitional | SEC-2 Production Secure | SEC-3 High Assurance |
|---|---:|---:|---:|---:|
| 사용 범위 | 폐쇄형 단기 실험 | 제한된 PoC/전환 | 일반 운영 권고 | 규제·고민감 데이터 |
| Client TLS 8443/9440 | 선택 | 필수 | 필수 | 필수 |
| 평문 8123/9000 | 격리망에서 선택 | 기본 차단 | 차단 | 차단 |
| Interserver TLS 9010 | 선택 | 권고 | 필수 | 필수 |
| Keeper client/Raft TLS | Keeper 사용 시 선택 | Keeper 사용 시 권고 | Keeper 사용 시 필수 | 필수 |
| PeerDB → ClickHouse mTLS | 선택 | 선택 | 권고 | 필수 |
| DocumentDB/MySQL TLS 검증 | 권고 | 필수 | 필수 | 필수 |
| Private subnet | 필수 | 필수 | 필수 | 필수 |
| PrivateLink/VPN | 선택 | 권고 | 권고 | 필수 |
| KMS 저장 암호화 | 권고 | 필수 | 필수 | 필수 |
| 외부 감사 로그 보관 | 선택 | 권고 | 필수 | 필수·변경 불가 보관 |
| S3 백업 | 선택 | 필수 | 필수 | 필수·Object Lock |
| 운영 적합 여부 | 아니오 | 조건부 | 예 | 예 |

### 2.2 선택 기록

고객 검토 시 아래 블록을 채운다.

```yaml
security_profile: SEC-2

client_tls: true
interserver_enabled: false         # 현재 ClickHouse 단일 노드 범위
interserver_tls: null              # 복제/분산 노드 간 통신이 없으므로 N/A
keeper_enabled: false              # 현재 ClickHouse 단일 노드 범위
keeper_tls: null                   # Keeper 미사용 시 N/A
peerdb_clickhouse_mtls: false   # 초기에는 TLS+비밀번호, 검증 후 true 전환 가능
source_tls_verification: true
private_connectivity: true
at_rest_kms: true
audit_export: true
immutable_backup: false

exception_owner: ""
exception_reason: ""
exception_expiry: ""
```

### 2.3 권고안

- 운영 전환은 SEC-2를 최소 기준으로 한다.
- PeerDB mTLS는 고정할 PeerDB 릴리스에서 인증서 필드를 검증한 뒤 켠다.
- mTLS 준비가 늦어져도 TLS 자체를 끄지 않는다. 그 기간에는 `9440 + CA 검증 + 전용 비밀번호 + Security Group + HOST IP`를 사용한다.
- SEC-0의 평문 포트는 인터넷, VPC 피어링, 사내 공용망과 연결되지 않은 폐쇄형 실험 환경에서만 허용한다.

## 3. 보안 기능별 ON/OFF 의사결정

| 통제 | ON일 때 | OFF일 때 영향 | OFF 허용 조건 | 운영 권고 |
|---|---|---|---|---|
| Client TLS | 8443/9440 사용, 인증서 검증 | 자격증명과 데이터가 평문 노출 가능 | 폐쇄형 단기 실험만 | ON |
| Interserver TLS | replica fetch와 내부 전송 암호화 | 노드 간 데이터 평문 | 단일 노드에서는 N/A | 복제/분산 구성 시 ON |
| Keeper TLS | Keeper client와 Raft 암호화 | 메타데이터·조정 트래픽 평문 | Keeper를 사용하지 않는 단일 노드는 N/A | Keeper 사용 시 ON |
| PeerDB mTLS | 비밀번호 없이 인증서 기반 서비스 인증 가능 | 비밀번호/시크릿 운영 필요 | TLS와 네트워크 제한이 켜진 경우 | SEC-2 권고, SEC-3 필수 |
| Source 인증서 검증 | DocumentDB/RDS 서버 신원 검증 | MITM 방어 약화 | 허용하지 않음 | ON |
| 저장 KMS 암호화 | EBS/RDS/S3 암호화 및 키 감사 | 스냅샷·디스크 노출 위험 증가 | 비민감 임시 데이터 | ON |
| Private connectivity | public exposure 최소화 | 인터넷 경계 통제 필요 | 고정 IP allowlist와 보안 승인 | ON |
| 외부 감사 로그 | DB 장애/침해 후에도 기록 보존 | DB와 함께 로그 유실 가능 | 비운영 환경 | ON |
| Immutable backup | 랜섬웨어·오삭제 방어 강화 | 관리자 탈취 시 백업도 삭제 가능 | 일반 SEC-2에서 위험 승인 | SEC-3 필수 |

`remoteSecure` 경로의 TLS는 선택 대상이 아니다. ClickHouse Cloud에서 데이터를 읽는 운영 마이그레이션은 `remoteSecure`와 secure native port `9440`을 사용한다. 평문 `remote`로 변경하지 않는다.

## 4. 목표 아키텍처

```text
                                 기존 경로(롤백 창 동안 유지)
Amazon DocumentDB 5.0 ────────── ClickPipes ─────────→ ClickHouse Cloud
        │ change stream                                  ▲
        │                                                │ remoteSecure
        ▼                                                │
┌─────────────────────────────┐     TLS/mTLS 9440    ┌────┴─────────────────────┐
│ EC2 #1: PeerDB stack        │ ───────────────────→ │ EC2 #2: ClickHouse OSS   │
│                             │                      │ single node              │
│ - Flow worker/API           │                      │                          │
│ - UI/server                 │                      │ - MergeTree family       │
│ - Temporal                  │                      │ - HTTPS 8443             │
│ - catalog PostgreSQL        │                      │ - Native TLS 9440        │
└──────────────▲──────────────┘                      └──────────────────────────┘
               │
AWS RDS MySQL ─┘ ROW binlog / GTID

두 EC2 모두 private subnet, public IP 없음
PeerDB SG → ClickHouse SG의 9440만 허용
외부 접속: internal NLB + VPN/PrivateLink
Cloud egress: 고정 NAT EIP → ClickHouse Cloud IP access list
```

현재 범위의 배포 단위는 다음과 같다.

- EC2 #1: PeerDB Flow worker/API/UI, Temporal, catalog PostgreSQL
- EC2 #2: ClickHouse 단일 노드
- PeerDB stage: 외부 private S3 권고. 로컬 MinIO를 쓰면 PeerDB EC2의 EBS를 분리한다.
- ClickHouse data: KMS 암호화 gp3 EBS
- ClickHouse 단일 노드에서는 Keeper를 사용하지 않고 `MergeTree`/`ReplacingMergeTree` 계열을 사용한다.
- S3 stage: private VPC endpoint, SSE-KMS, lifecycle 기반 자동 삭제
- ClickHouse/PeerDB 노드: public IP 없음
- 운영 접속: SSH 대신 SSM Session Manager 또는 승인된 bastion

이 구성은 컴포넌트 간 자원 경합을 줄이고, PeerDB 장애가 ClickHouse 조회 프로세스까지 같이 종료시키는 상황을 방지한다. 다만 ClickHouse 자체는 여전히 single point of failure다.

HA가 필요해지면 ClickHouse replica를 2개 이상으로 확장하고 3-node Keeper를 별도 배치한다. 이 가능성이 가까운 시점에 있다면 현재부터 `ReplicatedMergeTree`와 Keeper를 도입할지 별도 의사결정한다.

## 5. 데이터 이관 방식 선택

테이블마다 이관 owner를 하나 지정한다.

| 분류 | 예시 | 기본 이관 방식 | 주의점 |
|---|---|---|---|
| DocumentDB/MySQL CDC 테이블 | orders, users | PeerDB initial snapshot + CDC | 가장 보수적인 기본안 |
| 대용량 CDC 테이블 | source full scan 부담이 큰 테이블 | PeerDB CDC-first + Cloud backfill | 5.2 호환성 게이트 필수 |
| 변경 없는 과거 데이터 | archive, reference | `remoteSecure` 1회 복사 | partition별 재시도 가능하게 구성 |
| Append-only 활성 테이블 | events, logs | 초기 backfill + watermark delta | 경계 컬럼과 중복 제거 키 필요 |
| UPDATE/DELETE 활성 비-CDC 테이블 | 수동 갱신 테이블 | writer dual-write 또는 쓰기 중단 후 final sync | `remoteSecure`만으로 지속 동기화 불가 |
| DDL/메타데이터 | MV, dictionary, role, quota | 별도 스크립트로 재생성 | 데이터 복사와 분리 |

### 5.1 권고 기본안 M1: PeerDB initial snapshot + CDC

신규 빈 target 테이블에 PeerDB가 initial snapshot을 수행하고 이어서 CDC를 적용한다. 이 테이블에는 Cloud backfill을 넣지 않는다.

장점:

- 서로 다른 ClickPipes/PeerDB 버전 컬럼 의미에 의존하지 않는다.
- 데이터 owner가 하나라서 중복·역전 분석이 단순하다.
- 장애 시 PeerDB mirror 단위로 resync하기 쉽다.

단점:

- DocumentDB와 MySQL에 두 번째 full scan 부하가 발생한다.
- snapshot 시간이 change stream/binlog 보존 기간 안에 들어와야 한다.

### 5.2 최적화안 M2: PeerDB CDC-first + Cloud backfill

PeerDB를 initial snapshot 없이 먼저 시작하고, 시작 지점 이후 변경을 target에 쌓은 다음 ClickHouse Cloud의 과거 데이터를 `remoteSecure`로 같은 target에 backfill한다.

이 방식은 source full scan을 피할 수 있지만 다음을 **모두 검증한 경우에만** 승인한다.

- [ ] 고정한 ClickPipes와 PeerDB 버전에서 `_peerdb_version`의 단위와 의미가 비교 가능하다.
- [ ] Cloud와 target의 PK, `ORDER BY`, nullable/type mapping이 같다.
- [ ] target 엔진이 의도한 `ReplacingMergeTree(version[, is_deleted])` 계열이다.
- [ ] `_peerdb_version`, `_peerdb_is_deleted`, `_peerdb_source_schema` 등 필요한 메타 컬럼을 그대로 backfill한다.
- [ ] 동일 PK에 대해 backfill 중 UPDATE와 DELETE가 발생하는 경쟁 조건을 재현해 통과했다.
- [ ] 동일 version 값이 충돌하는 경우의 결과를 검증했다.
- [ ] 검증 쿼리는 `FINAL` 또는 명시적 최신행 뷰를 사용한다.
- [ ] merge 전 중복 행이 사용자 쿼리에 노출되는지 확인했다.

PeerDB 현재 main 소스는 normalize 단계에서 `_peerdb_timestamp`를 `_peerdb_version`으로 사용한다. 그러나 이 사실만으로 운영 중인 ClickPipes와 신규 PeerDB의 모든 버전이 전역 비교 가능하다고 보장할 수는 없다. 따라서 이 특성은 설계 가정이 아니라 릴리스 고정 후 검증해야 하는 승인 게이트다.

## 6. 전환 단계

### Phase 0 — 조사와 의사결정

- [ ] ClickHouse Cloud의 `SELECT version()` 기록
- [ ] PeerDB 이미지 tag/digest 고정
- [ ] 데이터베이스·테이블·MV·dictionary 목록 수집
- [ ] `SHOW CREATE TABLE` 전체 수집
- [ ] 사용자, role, grant, row policy, settings profile, quota 수집
- [ ] IP access list, PrivateLink, 인증서 정책, KMS 사용 여부 기록
- [ ] 테이블별 M1/M2/one-shot/delta 방식 지정
- [ ] 예상 데이터량, snapshot 시간, 허용 source 부하 측정
- [ ] RPO/RTO와 rollback 기간 승인

완료 기준: 테이블별 owner와 이관 방식이 문서화되고 보안 프로파일이 승인됨.

### Phase 1 — Self-managed 기반 구축

- [ ] Private subnet에 ClickHouse 단일 노드 EC2 배포
- [ ] 별도 private subnet에 PeerDB용 EC2, EBS, Security Group 준비
- [ ] 향후 HA 계획이 확정된 경우에만 Keeper 배포 여부 결정
- [ ] SEC 프로파일에 맞는 TLS 포트 구성
- [ ] EBS/RDS/S3 KMS 암호화
- [ ] RBAC, 계정별 CIDR, quota 설정
- [ ] 로그 외부 수집과 백업 구성
- [ ] 장애·복구 테스트

완료 기준: 운영 데이터를 넣기 전에 선택한 보안 프로파일의 검증 항목을 통과함.

### Phase 2 — PeerDB 배포와 dual-run

- [ ] PeerDB, catalog PostgreSQL, Temporal을 private subnet에 배포
- [ ] DocumentDB/RDS CA를 설치하고 hostname 검증 활성화
- [ ] PeerDB → ClickHouse는 TLS 또는 mTLS 사용
- [ ] 기존 ClickPipes는 유지
- [ ] M1은 initial snapshot + CDC 시작
- [ ] M2는 CDC-only를 먼저 시작한 뒤 checkpoint/GTID를 기록
- [ ] source cursor, CPU, IOPS, replica lag, network egress 모니터링

완료 기준: PeerDB mirror가 정상 상태이고 CDC lag가 승인 범위에서 유지됨.

### Phase 3 — `remoteSecure` backfill

- [ ] Cloud에 만료 가능한 read-only migration 계정 생성
- [ ] target NAT EIP만 Cloud IP access list에 추가
- [ ] target DDL을 먼저 생성하고 engine 변환 검토
- [ ] 작은 partition으로 예행 연습
- [ ] 재실행 가능한 manifest를 기준으로 partition backfill
- [ ] M1이 소유하는 테이블은 backfill 대상에서 제외
- [ ] M2는 모든 PeerDB 메타 컬럼을 포함

완료 기준: manifest의 모든 partition이 성공하고 checksum 검증을 통과함.

### Phase 4 — 검증

- [ ] 행 수, checksum, business aggregate 비교
- [ ] INSERT/UPDATE/DELETE와 schema evolution 테스트
- [ ] MV, dictionary, row policy, quota 동작 확인
- [ ] 주요 쿼리 결과와 성능 비교
- [ ] TLS와 닫힌 포트 검증
- [ ] ClickHouse/PeerDB 프로세스 및 EC2 장애 시 복구 테스트
- [ ] Keeper를 선택한 경우 Keeper 쿼럼 장애 테스트
- [ ] 실제 S3 backup으로 격리된 환경에 restore

완료 기준: 10절의 승인 기준을 모두 통과함.

### Phase 5 — Cutover와 rollback 창

- [ ] DDL 변경 동결
- [ ] 마지막 delta와 CDC lag 확인
- [ ] BI/애플리케이션 endpoint를 self-managed로 전환
- [ ] ClickPipes와 Cloud를 1~2주 유지
- [ ] rollback 기간 동안 양쪽 결과와 target 신규 쓰기 확인
- [ ] 종료 승인 후 ClickPipes와 migration 계정 제거
- [ ] Cloud IP access list의 NAT EIP 제거
- [ ] Cloud 서비스 종료 전 최종 백업과 승인 기록

## 7. 소스별 dual-run 준비

### 7.1 Amazon DocumentDB 5.0

DocumentDB change stream은 기본 보존 시간이 짧으므로 snapshot 또는 장애 복구 시간을 덮도록 늘린다. 최대 보존 범위와 비용은 해당 리전/엔진 문서를 기준으로 확인한다.

권장 사항:

- 대상 database/collection의 change stream을 명시적으로 활성화한다.
- `change_stream_log_retention_duration`을 최소 72시간, 가능하면 예상 snapshot 시간 + 장애 여유보다 길게 설정한다.
- PeerDB 전용 read-only 사용자를 사용한다.
- `root_ca`에 AWS DocumentDB CA bundle을 제공한다.
- `disable_tls=false`, `skip_cert_verification=false`로 설정한다.
- DocumentDB 5.0에서는 검증 후 secondary read preference를 고려한다.
- PeerDB `stable-v0.37.5` 실측에서는 DocumentDB 4.0이 wire version 7로 거부되고 8.0.1이 통과했다. 5.0은 MongoDB 5.0 호환이지만 동일 실행에서 검증되지 않았으므로, 운영 전 고정 릴리스로 peer validation과 snapshot/CDC smoke test를 수행한다.
- PeerDB 사용자는 대상 database의 read 권한 외에 connector validation이 요구하는 `clusterMonitor` 권한을 최소 범위로 확인한다.
- SQL 방식으로 Mongo peer를 만들면 고정 릴리스에서 URI 외 별도 username/password와 숫자형 `read_preference`가 필요한지 확인한다.
- ClickPipes와 PeerDB 동시 실행 중 cursor 수, read IOPS, CPU, replica lag를 감시한다.
- 16 MB를 넘는 change event, 대량 `updateMany`/`deleteMany`, full-document lookup을 별도 테스트한다.

```javascript
// 예: 특정 database의 모든 collection에 change stream 활성화
db.adminCommand({
  modifyChangeStreams: 1,
  database: "app",
  collection: "",
  enable: true
});
```

### 7.2 AWS RDS MySQL

권장 사항:

- `binlog_format=ROW`
- `binlog_row_image=FULL`
- PeerDB `stable-v0.37.5`에서는 `binlog_row_metadata=FULL`
- GTID 사용 권고
- backfill과 장애 시간을 덮는 binlog 보존 기간. 실측 connector validation 최소값은 24시간
- ClickPipes와 PeerDB의 replication `server_id`가 겹치지 않도록 PeerDB에 명시
- SQL 방식으로 MySQL peer를 만들면 `flavor='mysql'`을 명시
- dual-run 기간의 network egress, IOPS, replica lag 관찰

예시:

```sql
CALL mysql.rds_set_configuration('binlog retention hours', 168);
```

실제 적용 가능 값과 재시작 필요 여부는 RDS 엔진 버전과 parameter group에서 확인한다.

## 8. ClickHouse 보안 구성

설정은 기본 `config.xml`을 직접 수정하지 않고 `/etc/clickhouse-server/config.d/`에 목적별 파일로 나눈다. 아래 예시는 배포 버전에서 `clickhouse-server --config-file ... --test-config` 또는 별도 staging node로 검증한 뒤 적용한다.

### 8.1 SEC-2/SEC-3: 평문 포트 제거

`config.d/10-network-secure.xml`

```xml
<clickhouse>
    <!-- 노드별 private IP 또는 private interface에 맞게 변경 -->
    <listen_host>10.0.12.31</listen_host>

    <http_port remove="1"/>
    <tcp_port remove="1"/>
    <interserver_http_port remove="1"/>
    <mysql_port remove="1"/>
    <postgresql_port remove="1"/>

    <https_port>8443</https_port>
    <tcp_port_secure>9440</tcp_port_secure>
</clickhouse>
```

현재 단일 노드는 replica fetch가 없으므로 interserver listener를 열지 않는다. 향후 replica를 추가할 때만 `interserver_https_port=9010`, interserver credential과 인증서 검증을 함께 구성하고 Security Group도 replica 간에만 연다.

`listen_host=0.0.0.0`이 필요한 컨테이너 환경에서는 이를 보안 결함으로 단정하지 않는다. 대신 public IP 없음, load balancer scheme, Security Group, NetworkPolicy를 함께 검증한다.

### 8.2 SEC-2/SEC-3: TLS 설정

`config.d/11-tls.xml`

```xml
<clickhouse>
    <openSSL>
        <server>
            <certificateFile>/etc/clickhouse-server/tls/server.crt</certificateFile>
            <privateKeyFile>/etc/clickhouse-server/tls/server.key</privateKeyFile>
            <caConfig>/etc/clickhouse-server/tls/internal-ca.crt</caConfig>
            <verificationMode>relaxed</verificationMode>
            <loadDefaultCAFile>false</loadDefaultCAFile>
            <cacheSessions>true</cacheSessions>
            <disableProtocols>sslv2,sslv3,tlsv1,tlsv1_1</disableProtocols>
            <preferServerCiphers>true</preferServerCiphers>
            <invalidCertificateHandler>
                <name>RejectCertificateHandler</name>
            </invalidCertificateHandler>
        </server>

        <client>
            <!-- remoteSecure의 Cloud 공개 인증서 체인도 검증 -->
            <loadDefaultCAFile>true</loadDefaultCAFile>
            <verificationMode>strict</verificationMode>
            <cacheSessions>true</cacheSessions>
            <disableProtocols>sslv2,sslv3,tlsv1,tlsv1_1</disableProtocols>
            <invalidCertificateHandler>
                <name>RejectCertificateHandler</name>
            </invalidCertificateHandler>
        </client>
    </openSSL>
</clickhouse>
```

선택 기준:

- server `relaxed`: 비밀번호 사용자와 인증서 사용자를 같은 TLS listener에서 혼용할 때 사용한다.
- server `strict`: 모든 client가 인증서를 제시할 수 있는 SEC-3 환경에서만 사용한다.
- client `strict`: ClickHouse가 Cloud, Keeper 등으로 연결할 때 인증서 오류를 거부하기 위해 유지한다.
- `cipherList`를 고정하면 client 호환성이나 TLS 1.3 정책에 영향을 줄 수 있다. 보안팀의 cipher 정책이 있을 때만 staging 검증 후 추가한다.

### 8.3 SEC-0: 평문 호환 모드

이 구성은 운영에 사용하지 않는다. secure 설정 파일과 동시에 배포하지 않는다.

`config.d/10-network-lab-only.xml`

```xml
<clickhouse>
    <listen_host>10.0.12.31</listen_host>
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>

    <https_port remove="1"/>
    <tcp_port_secure remove="1"/>
</clickhouse>
```

필수 보완 통제:

- internet gateway와 public IP 없음
- 실험 전용 Security Group과 VPC
- 운영 자격증명·운영 데이터 사용 금지
- 종료일 지정
- SEC-2 전환 전 데이터 재생성 권고

### 8.4 Keeper TLS — 향후 HA 또는 scale-ready 구성에서만

현재 2-EC2 구성의 ClickHouse 단일 노드는 Keeper를 사용하지 않는다. 향후 replica를 추가하거나 처음부터 `ReplicatedMergeTree`를 선택할 경우에만 Keeper를 배포하며, 이때 Keeper client 포트와 Keeper 노드 사이의 Raft 연결을 모두 암호화한다.

```xml
<keeper_server>
    <tcp_port_secure>9281</tcp_port_secure>
    <server_id>1</server_id>

    <raft_configuration>
        <secure>true</secure>
        <server>
            <id>1</id>
            <hostname>keeper-1.internal</hostname>
            <port>9444</port>
        </server>
        <server>
            <id>2</id>
            <hostname>keeper-2.internal</hostname>
            <port>9444</port>
        </server>
        <server>
            <id>3</id>
            <hostname>keeper-3.internal</hostname>
            <port>9444</port>
        </server>
    </raft_configuration>
</keeper_server>
```

ClickHouse server 쪽:

```xml
<zookeeper>
    <node index="1">
        <host>keeper-1.internal</host>
        <port>9281</port>
        <secure>1</secure>
    </node>
    <node index="2">
        <host>keeper-2.internal</host>
        <port>9281</port>
        <secure>1</secure>
    </node>
    <node index="3">
        <host>keeper-3.internal</host>
        <port>9281</port>
        <secure>1</secure>
    </node>
</zookeeper>
```

Standalone Keeper는 ClickHouse server의 OpenSSL 설정을 자동 상속하지 않으므로 Keeper 설정에도 인증서와 CA를 별도로 구성한다.

### 8.5 약한 인증 차단

`config.d/12-auth.xml`

```xml
<clickhouse>
    <allow_no_password>0</allow_no_password>
    <allow_implicit_no_password>0</allow_implicit_no_password>
    <allow_plaintext_password>0</allow_plaintext_password>

    <!-- 고정 버전이 bcrypt 기본값을 지원하는지 먼저 검증 -->
    <default_password_type>bcrypt_password</default_password_type>
    <bcrypt_workfactor>12</bcrypt_workfactor>

    <password_complexity>
        <rule>
            <pattern>.{16,}</pattern>
            <message>be at least 16 characters long</message>
        </rule>
        <rule>
            <pattern>\p{N}</pattern>
            <message>contain at least one number</message>
        </rule>
        <rule>
            <pattern>\p{Ll}</pattern>
            <message>contain at least one lowercase character</message>
        </rule>
        <rule>
            <pattern>\p{Lu}</pattern>
            <message>contain at least one uppercase character</message>
        </rule>
        <rule>
            <pattern>[^\p{L}\p{N}]</pattern>
            <message>contain at least one special character</message>
        </rule>
    </password_complexity>
</clickhouse>
```

구버전 호환성이 필요하면 `default_password_type=sha256_password`를 사용하되, 중요 계정은 `CREATE USER ... IDENTIFIED WITH bcrypt_password`로 명시한다.

### 8.6 계정과 역할

PeerDB 기본 TLS+비밀번호 예시:

```sql
CREATE ROLE peerdb_role;

GRANT SELECT, INSERT, CREATE TABLE ON analytics.* TO peerdb_role;
GRANT ALTER ADD COLUMN ON analytics.* TO peerdb_role;
GRANT CREATE TEMPORARY TABLE, S3 ON *.* TO peerdb_role;

-- DROP MIRROR를 실제로 사용할 때만 일시 부여 권고
-- GRANT DROP TABLE ON analytics.* TO peerdb_role;

CREATE USER peerdb_writer
    IDENTIFIED WITH bcrypt_password BY '<secret>'
    HOST IP '10.0.12.0/24';

GRANT peerdb_role TO peerdb_writer;
```

PeerDB mTLS 선택 시:

```sql
CREATE USER peerdb_writer
    IDENTIFIED WITH ssl_certificate CN 'peerdb-writer'
    HOST IP '10.0.12.0/24';

GRANT peerdb_role TO peerdb_writer;
```

현재 PeerDB source schema에는 ClickHouse peer용 `certificate`, `private_key`, `root_ca`, `tls_host`, `tls_certificate_directory` 필드가 있다. 단, 반드시 고정한 배포 릴리스에서 실제 연결을 검증한다.

읽기 사용자 예시:

```sql
CREATE SETTINGS PROFILE bi_readonly SETTINGS
    readonly = 1,
    allow_ddl = 0,
    max_execution_time = 120,
    max_result_rows = 2000000;

CREATE ROLE bi_reader_role;
GRANT SELECT ON analytics.* TO bi_reader_role;

CREATE USER bi_reader
    IDENTIFIED WITH bcrypt_password BY '<secret>'
    HOST IP '10.0.20.0/24'
    SETTINGS PROFILE bi_readonly;

GRANT bi_reader_role TO bi_reader;
```

`default` 사용자를 정리하기 전에 별도 관리자 계정으로 로그인과 권한 복구 절차를 검증한다. 관리 계정을 만들지 않은 상태에서 `default`를 제거하면 클러스터 접근을 잃을 수 있다.

### 8.7 저장 암호화와 시크릿

| 대상 | SEC-2 권고 | SEC-3 추가 |
|---|---|---|
| ClickHouse data EBS | 고객 CMK, encrypted snapshot | 키 관리자와 DB 관리자 분리 |
| Keeper EBS(선택 시) | 고객 CMK | 별도 CMK 고려 |
| PeerDB catalog RDS | KMS + TLS + Multi-AZ | 별도 계정/CMK, 강화된 감사 |
| PeerDB stage S3 | SSE-KMS, private endpoint, lifecycle | Object Lock 필요성 검토 |
| ClickHouse backup S3 | SSE-KMS, versioning | Object Lock, cross-region/account copy |
| 인증서 개인 키 | Secrets Manager/Vault/Secret volume | 짧은 수명과 자동 rotation |

시크릿 원칙:

- SQL에 비밀번호를 직접 넣지 않는다.
- AWS에서는 정적 access key보다 instance profile, IRSA 또는 assume-role을 우선한다.
- `from_env`, secret file, Vault agent 등 배포 방식에 맞는 주입 방법을 사용한다.
- ClickHouse preprocessed config 파일의 권한과 secret 노출 여부를 점검한다.
- PeerDB catalog에는 connection 정보가 저장되므로 DB 암호화, 접근 통제, 백업을 포함한다.

### 8.8 감사 로그

최소 수집 대상:

- `system.query_log`
- `system.session_log`
- `system.part_log`
- `system.backup_log`
- ClickHouse server/error log
- PeerDB/Temporal/catalog 로그
- AWS CloudTrail, KMS, VPC Flow Logs, load balancer 로그

감사 로그는 운영 ClickHouse 안에만 보관하지 않는다. S3 또는 별도 감사 플랫폼으로 전송하고, SEC-3에서는 변경 불가능 보관을 사용한다.

`remoteSecure` 자격증명은 named collection으로 분리한다. 추가 `query_masking_rules`는 RE2 표현식이 정상 쿼리까지 과도하게 마스킹할 수 있으므로 staging에서 로그 결과를 확인한 뒤 적용한다.

## 9. `remoteSecure` backfill

### 9.1 방향과 네트워크

Self-managed ClickHouse에서 ClickHouse Cloud를 읽는 pull 방식으로 실행한다.

```text
Self-managed ClickHouse ── outbound TLS 9440 ──→ ClickHouse Cloud
```

필요한 네트워크 변경:

1. Self-managed NAT Gateway의 EIP를 고정한다.
2. 해당 EIP만 ClickHouse Cloud IP access list에 임시 추가한다.
3. Cloud에 read-only `migration_reader`를 만든다.
4. 완료 후 계정과 allowlist를 제거한다.

### 9.2 Named collection

`config.d/20-named-collections.xml`

```xml
<clickhouse>
    <named_collections>
        <ch_cloud_src>
            <host>service-id.ap-northeast-2.aws.clickhouse.cloud</host>
            <port>9440</port>
            <database>analytics</database>
            <user>migration_reader</user>
            <password from_env="CLOUD_MIGRATION_PASSWORD"/>
            <secure>1</secure>
        </ch_cloud_src>
    </named_collections>
</clickhouse>
```

Target의 migration role에는 이관 대상 `INSERT`, `REMOTE`, named collection 사용 권한만 부여한다.

```sql
GRANT INSERT, SELECT ON analytics.* TO migration_role;
GRANT REMOTE ON *.* TO migration_role;
GRANT NAMED COLLECTION ON ch_cloud_src TO migration_role;
```

### 9.3 DDL 변환

Cloud의 `SharedMergeTree` 계열은 현재 단일 노드에서 대응되는 비복제 `MergeTree` 계열로 변환한다. 향후 ClickHouse replica와 Keeper를 도입할 때만 `Replicated*MergeTree` 계열을 사용한다.

| Cloud | 현재 단일 노드 | 향후 HA 구성 |
|---|---|---|
| `SharedMergeTree` | `MergeTree` | `ReplicatedMergeTree` |
| `SharedReplacingMergeTree` | `ReplacingMergeTree` | `ReplicatedReplacingMergeTree` |
| `SharedAggregatingMergeTree` | `AggregatingMergeTree` | `ReplicatedAggregatingMergeTree` |

다음은 데이터 복사 전에 별도로 확인한다.

- `ORDER BY`, `PRIMARY KEY`, `PARTITION BY`
- TTL, projection, skipping index
- version/deleted engine 인자
- codec와 column default/materialized/alias
- `Distributed` cluster 이름과 sharding key
- materialized view 생성 순서와 backfill 중 중복 집계 여부

### 9.4 Partition backfill

```sql
INSERT INTO analytics.orders
SELECT *
FROM remoteSecure(
    ch_cloud_src,
    database = 'analytics',
    table = 'orders'
)
WHERE created_at >= '2026-01-01'
  AND created_at <  '2026-02-01'
SETTINGS
    max_insert_threads = 8,
    max_execution_time = 0;
```

운영 원칙:

- partition별 manifest에 `pending/running/succeeded/failed`, 행 수, checksum, 시작·종료 시각을 기록한다.
- 동시에 실행할 stream 수는 source Cloud와 target merge 부하를 보며 조절한다.
- 실패한 partition만 재실행할 수 있도록 범위를 고정한다.
- 단순 `INSERT SELECT`의 재실행은 중복을 만들 수 있으므로 성공 여부가 불명확하면 먼저 검증한다.
- M2에서는 `_peerdb_*` 컬럼을 누락하지 않는다.
- MV가 target insert를 다시 집계하는 구조인지 확인하고 생성 시점을 조정한다.

## 10. 검증과 승인 기준

### 10.1 데이터 검증

```sql
SELECT
    count() AS rows,
    sum(cityHash64(id, status, amount)) AS checksum
FROM analytics.orders FINAL
WHERE created_at >= '2026-01-01'
  AND created_at <  '2026-02-01';
```

Cloud 쪽도 동일한 column 목록과 filter로 비교한다. `SELECT *` 기반 hash보다 명시적 business column을 사용한다.

- [ ] partition별 `count()` 일치
- [ ] 중요 business column checksum 일치
- [ ] 금액·상태·일자별 business aggregate 일치
- [ ] null 비율과 cardinality 비교
- [ ] UPDATE/DELETE 최신 상태 비교
- [ ] schema evolution 결과 비교
- [ ] timezone, Decimal, ObjectId, JSON/nested mapping 비교

### 10.2 보안 검증

```bash
# 성공해야 함
openssl s_client -connect ch.internal.example.com:9440 \
  -servername ch.internal.example.com -tls1_2

# 거부되어야 함
openssl s_client -connect ch.internal.example.com:9440 \
  -servername ch.internal.example.com -tls1_1

# 리스너 확인
ss -tlnp
```

- [ ] SEC-2/3에서 `8123`, `9000`, `9009` listener 없음
- [ ] 인증서 chain, SAN, 만료일 정상
- [ ] 잘못된 CA와 hostname으로 연결 실패
- [ ] `no_password`, `plaintext_password` 계정 없음
- [ ] 사용자별 `HOST IP`/CIDR 제한 적용
- [ ] PeerDB가 `disable_tls=false`로 연결
- [ ] SEC-3에서 PeerDB client certificate 없이 연결 실패
- [ ] query log에 실제 자격증명 없음
- [ ] S3/RDS/EBS KMS key와 정책 확인
- [ ] public IP와 public load balancer 없음
- [ ] backup restore 실제 성공

### 10.3 운영 승인 기준 예시

| 지표 | 승인 기준 예시 | 실제 승인값 |
|---|---:|---:|
| PeerDB CDC lag | 60초 미만 | TBD |
| 데이터 checksum | 100% 일치 | TBD |
| 주요 쿼리 결과 | 100% 일치 | TBD |
| P95 query latency | Cloud 대비 허용 범위 내 | TBD |
| 연속 안정화 관찰 | 72시간 이상 | TBD |
| RPO | 고객 정의 | TBD |
| RTO | 고객 정의 | TBD |
| Backup restore | 격리 환경에서 성공 | TBD |

## 11. Cutover와 rollback

### 11.1 Cutover

1. DDL과 schema 변경을 동결한다.
2. PeerDB mirror 상태와 lag를 확인한다.
3. non-CDC 테이블의 마지막 delta를 반영한다.
4. Cloud와 target checksum을 다시 비교한다.
5. DNS, connection string 또는 feature flag로 읽기를 target으로 전환한다.
6. target에만 직접 쓰는 producer가 있는지 감시한다.
7. 최소 1~2주간 ClickPipes와 Cloud를 유지한다.

### 11.2 Rollback

rollback trigger 예시:

- 데이터 불일치가 승인 임계치를 초과
- CDC lag가 지속적으로 증가
- 주요 쿼리 오류 또는 성능 저하
- ClickHouse node 장애 또는 Keeper를 사용한 경우 Keeper 안정성 문제
- 인증서/PrivateLink 문제로 client 연결 실패

절차:

1. 읽기 endpoint를 Cloud로 되돌린다.
2. source 기반 ClickPipes가 정상인지 확인한다.
3. target-only writer를 중지하거나 별도 보존한다.
4. 불일치가 시작된 checkpoint/GTID/time range를 기록한다.
5. 원인을 수정한 뒤 해당 범위를 재검증한다.

주의: cutover 후 self-managed ClickHouse에만 직접 기록된 데이터는 Cloud로 자동 복제되지 않는다. rollback 가능성을 유지하려면 해당 producer도 dual-write하거나 rollback 창 동안 write source를 DocumentDB/MySQL 등 원천 시스템으로 한정한다.

## 12. ClickHouse Cloud 대비 책임과 격차

| 영역 | ClickHouse Cloud | Self-managed 책임 | 동일 수준 가능성 |
|---|---|---|---|
| TLS·암호화 | 관리형 | 인증서, CA, rotation, KMS 운영 | 통제로 대응 가능 |
| Private networking | 관리형 옵션 | VPC, NLB, PrivateLink 설계 | 대응 가능 |
| SQL RBAC | 지원 | role/grant/policy 운영 | 대응 가능 |
| Console SSO/MFA | Cloud control plane | VPN, IdP, bastion, BI 계층 | DB 단독으로 동일하지 않음 |
| 패치/CVE | 자동 운영 | 버전 감시와 정기 upgrade | 고객 운영 역량 필요 |
| HA/복구 | 관리형 | replica, Keeper, backup, restore drill | 고객 운영 역량 필요 |
| 감사·컴플라이언스 | 서비스 증빙 | 자체 통제와 증빙 | 자동 승계되지 않음 |
| 자동 확장/SLA | 서비스 기능 | 용량 계획·온콜·장애 대응 | 별도 설계 필요 |

고객 커뮤니케이션 권고 문구:

> 본 구성은 ClickHouse Cloud의 설정 파일이나 인증서를 복제하는 방식이 아니라, 전송 암호화·저장 암호화·네트워크 격리·접근 통제·감사·백업이라는 보안 통제 목표를 self-managed 환경에 재구현하는 방식입니다. 관리형 패치, 제어면 SSO/MFA, 서비스 SLA와 컴플라이언스 증빙은 자동 승계되지 않으며 고객 또는 운영 사업자의 책임으로 전환됩니다.

## 13. 고객 승인 항목

- [ ] 배포 단위: PeerDB EC2 1대 + ClickHouse EC2 1대
- [ ] ClickHouse 시작 사양: `m7i.4xlarge` 16 vCPU / 64 GiB
- [ ] PeerDB 시작 사양: `m7i.2xlarge` 8 vCPU / 32 GiB
- [ ] ClickHouse gp3: 300 GiB, 이관 시 6,000 IOPS / 250 MiB/s
- [ ] PeerDB gp3: 100~150 GiB, 기본 3,000 IOPS / 125 MiB/s
- [ ] PeerDB stage: private S3 권고 / 로컬 MinIO 예외
- [ ] 보안 프로파일: SEC-0 / SEC-1 / SEC-2 / SEC-3
- [ ] PeerDB → ClickHouse 인증: TLS+password / mTLS
- [ ] 접속 방식: VPN / PrivateLink / 제한된 public endpoint
- [ ] CDC 테이블 이관: M1 initial snapshot / M2 CDC-first+backfill
- [ ] DocumentDB change stream 보존 시간
- [ ] MySQL binlog 보존 시간과 GTID 사용
- [ ] rollback 유지 기간
- [ ] RPO/RTO
- [ ] audit log 보존 기간
- [ ] backup 주기, 보존 기간, Object Lock 여부
- [ ] Cloud 종료 조건과 최종 승인자

## 14. EC2 사이징 권장

### 14.1 실측 요약

ClickHouse workload:

- user table 데이터: 최대 약 10.7 GB
- replica당 지속 메모리: 평균 5 GB, P95 16.8 GB
- 관측 peak 메모리: 294 GB. 12-replica 시점의 일회성 이상치로 상시 용량 기준에서는 제외하되 원인 쿼리를 추적한다.
- SELECT 비율: 99% 이상
- 안정화 후 월 SELECT: 약 300만 건, 월평균으로 환산하면 약 1.2 QPS

PeerDB/ClickPipes workload, 2026-04-21~2026-09-07:

| 소스 | Pipe 수 | Initial load | 이벤트 수 |
|---|---:|---:|---:|
| MySQL | 8 | 4.30 GB | 370,635 |
| MongoDB/DocumentDB | 2 | 0.27 GB | 178,620 |
| 합계 | 10 | 약 4.57 GB | 549,255 |

- 월 이벤트는 최근 약 10만~12만 건으로 평균 event rate는 매우 낮다.
- 월 initial load는 대부분 0.3~0.7 GB이며, 2026-06의 2.65 GB는 신규 pipe 또는 resnapshot 성격으로 판단된다.
- `fetched_bytes_total`이 CDC byte를 충분히 반영하지 않으므로 바이트 수만으로 사이징하지 않는다.
- peak 초당 이벤트, 최대 row/document 크기, snapshot 동시성 자료가 없으므로 PeerDB에는 보수적 여유를 둔다.

### 14.2 최종 권장안: EC2 2대

| 역할 | 권장 EC2 예시 | vCPU | RAM | EBS | 판단 |
|---|---|---:|---:|---|---|
| ClickHouse OSS | `m7i.4xlarge` | 16 | 64 GiB | data gp3 300 GiB | 안정 운영 권장 |
| PeerDB 전체 스택 | `m7i.2xlarge` | 8 | 32 GiB | state gp3 100~150 GiB | 10 mirrors에 충분한 여유 |

ClickHouse는 사용자가 제안한 **16 vCPU가 적절한 시작점**이다. P95 메모리 16.8 GB는 64 GiB의 약 26%이므로 OS page cache, background merge, 동시 SELECT와 external spill을 위한 여유가 남는다. 데이터가 작아 32 core보다 16 core의 비용 대비 균형이 좋다.

PeerDB는 처리 데이터가 작지만 Flow worker 외에 API/UI, Temporal, Temporal admin bootstrap, catalog PostgreSQL을 같은 EC2에 넣으므로 8 vCPU/32 GiB를 권장한다. CDC만 보면 4/16도 가능하지만, resnapshot·schema change·10개 mirror 재시작이 겹칠 때의 운영 여유를 포함해 8/32로 시작한다.

두 구성 모두 단일 노드이므로 각각 SPOF다. ClickHouse 데이터 백업뿐 아니라 PeerDB catalog PostgreSQL과 Temporal 상태도 정기 스냅샷·복구 시험 대상에 포함한다. 이 권장안은 장애 격리와 자원 경합 완화를 위한 2대 분리이며 HA 구성을 의미하지 않는다.

### 14.3 대안 비교

| 안 | ClickHouse | PeerDB | 적용 조건 |
|---|---|---|---|
| 최소/비운영 | 8 vCPU / 32 GiB | 4 vCPU / 16 GiB | 개발·성능 검증, 운영 비권고 |
| 비용 절감 운영 | 16 vCPU / 64 GiB | 4 vCPU / 16 GiB | PeerDB snapshot 직렬화, 외부 S3 stage, 엄격한 lag 모니터링 |
| **안정 운영 권장** | **16 vCPU / 64 GiB** | **8 vCPU / 32 GiB** | 현재 실측 규모와 10개 mirror 기준 |
| 메모리 안전형 | 16 vCPU / 128 GiB (`r7i.4xlarge`) | 8 vCPU / 32 GiB | ClickHouse memory spike가 반복될 때 |
| 성장 대비 | 32 vCPU / 128 GiB | 16 vCPU / 64 GiB | 동시 쿼리·데이터·mirror 처리량이 수배 증가할 때 |

`m7i-flex`는 vCPU당 baseline 성능 모델이 있으므로 지속적인 ClickHouse 쿼리 부하에는 표준 `m7i`를 우선한다. Graviton 계열은 ClickHouse와 PeerDB의 고정 이미지가 arm64를 지원하는지 확인한 뒤 비용 최적화 대안으로 검토한다.

### 14.4 일반 EBS(gp3) 구성

로컬 NVMe는 이번 권장안에서 제외한다. EC2 instance store의 데이터는 stop/terminate 또는 일부 host 장애 시 유실될 수 있으므로 single-node ClickHouse의 유일한 저장소로 적합하지 않다.

권장 volume 구성:

| EC2 | Mount/용도 | gp3 용량 | 시작 성능 | 비고 |
|---|---|---:|---:|---|
| ClickHouse | root/config/log | 50 GiB | 기본 3,000 IOPS / 125 MiB/s | data와 분리 |
| ClickHouse | `/var/lib/clickhouse` | 300 GiB | 6,000 IOPS / 250 MiB/s | backfill 종료 후 지표로 하향 가능 |
| PeerDB | root/container | 50 GiB | 기본 3,000 IOPS / 125 MiB/s | image/log 포함 |
| PeerDB | catalog/Temporal state | 100~150 GiB | 기본 3,000 IOPS / 125 MiB/s | snapshot·복구 단위 분리 |

현재 ClickHouse 데이터만 보면 data volume 200 GiB도 충분하다. 다만 Cloud backfill, PeerDB raw/normalized 중복, merge 임시 공간, mutation과 로그를 고려해 300 GiB를 권장한다. gp3는 용량과 IOPS/throughput을 독립적으로 조정할 수 있으므로 최초 이관 기간에만 6,000 IOPS/250 MiB/s를 쓰고 안정화 후 낮출 수 있다.

PeerDB stage는 로컬 MinIO보다 private S3 bucket을 권장한다. 로컬 MinIO를 사용하면 PeerDB state volume과 분리된 gp3 200 GiB 이상을 추가하고, EC2 장애 시 stage 재생성 절차를 마련한다.

### 14.5 같은 VPC의 두 EC2 간 보안

- PeerDB SG에서 ClickHouse SG의 `9440`만 접근 허용한다.
- PeerDB → ClickHouse는 SEC-2에서 TLS+CA 검증을 기본으로 한다.
- mTLS는 고정 PeerDB 릴리스 검증 후 선택한다.
- `9000` 평문 native port는 운영에서 열지 않는다.
- 두 EC2 모두 public IP를 두지 않는다.
- S3, Secrets Manager, CloudWatch 접근에는 VPC endpoint를 우선한다.
- `remoteSecure`용 Cloud outbound만 고정 NAT EIP로 제한한다.

### 14.6 시작 리소스 가드레일

ClickHouse 16/64 시작값 예시:

```sql
CREATE SETTINGS PROFILE analytics_guardrail SETTINGS
    max_threads = 8,
    max_memory_usage = 12000000000,
    max_bytes_before_external_group_by = 4000000000,
    max_bytes_before_external_sort = 4000000000,
    max_execution_time = 300;
```

이는 초기 안전값이며 실제 query profile을 보고 사용자군별로 나눈다. 294 GB 이상치가 진짜 단일 쿼리 요구량이라면 64 GiB 노드가 이를 메모리에서 처리할 수 없으므로, 해당 쿼리를 최적화·분할하거나 external aggregation/sort를 사용해야 한다. 이상치 하나만으로 384 GiB급 EC2를 상시 배치하지 않는다.

PeerDB 시작값:

- initial snapshot 동시 table 수: 1~2
- table당 snapshot worker: 2~4
- mirror 10개를 한 번에 resync하지 않고 순차/소그룹 실행
- M2 CDC-first 전략이면 snapshot 자원이 줄지만 5.2절 호환성 게이트 필수
- ClickHouse backfill과 PeerDB resnapshot을 동시에 최대로 실행하지 않음

### 14.7 Scale-up 조건

| 컴포넌트 | 증설 또는 튜닝 조건 |
|---|---|
| ClickHouse CPU | CPU P95 70% 이상 지속, query queue 또는 SLA 초과 |
| ClickHouse RAM | memory P95 70% 이상, 반복 OOM, spill로 SLA 초과 |
| ClickHouse EBS | queue length/latency 증가, merge backlog, 사용량 60% 초과 |
| PeerDB CPU/RAM | worker 재시작, GC/메모리 압박, snapshot 시간이 retention 창에 접근 |
| PeerDB 처리량 | CDC lag가 승인 SLO를 15분 이상 초과하거나 계속 증가 |
| PeerDB EBS | catalog/Temporal latency 증가, volume 사용량 60% 초과 |

Cutover 후 72시간과 2주 시점에 각각 재평가한다. PeerDB가 CPU P95 30%, memory P95 50% 미만이고 lag가 안정적이면 4/16으로 축소할 수 있다. ClickHouse는 workload 특성상 16/64를 기본 유지하고, 반복되는 memory spike가 확인되면 CPU를 늘리기 전에 `r7i.4xlarge` 16/128을 우선 검토한다.

## 15. EC2 설치 및 Terraform 배포

### 15.1 배포 범위와 전제

제공하는 Terraform은 기존 VPC와 private subnet 안에 다음 리소스를 만든다.

- ClickHouse EC2 1대와 별도 gp3 data volume
- PeerDB EC2 1대와 별도 gp3 state volume
- KMS key와 암호화된 private S3 stage bucket
- ClickHouse/PeerDB별 IAM role과 SSM 권한
- TLS 9440만 허용하는 Security Group 연결
- ClickHouse 인증서 SAN과 일치하는 Route 53 private A record
- 선택적인 S3 gateway VPC endpoint
- ClickHouse 패키지와 PeerDB Docker Compose 자동 설치 `user_data`

다음 항목은 환경별 기존 리소스를 입력받는다.

- VPC, private subnet, private route table
- Route 53 private hosted zone
- TLS 인증서와 비밀번호가 저장된 Secrets Manager secret
- NAT gateway 또는 승인된 package/container registry mirror

private subnet에서 Ubuntu, ClickHouse package repository, Docker repository와 GHCR에 나갈 수 있어야 최초 설치가 성공한다. NAT가 없는 환경은 S3, SSM, `ssmmessages`, Secrets Manager, KMS, CloudWatch용 VPC endpoint와 내부 package/container mirror를 별도로 준비한다.

### 15.2 제공 파일

```text
chc/cloud-to-oss-peerdb/terraform/
├── README.md
├── versions.tf
├── variables.tf
├── main.tf
├── outputs.tf
├── terraform.tfvars.example
└── templates/
    ├── clickhouse-user-data.sh.tftpl
    └── peerdb-user-data.sh.tftpl
```

- [`terraform/README.md`](./terraform/README.md): 실행 전제, secret 형식, 배포·점검 방법
- [`terraform/main.tf`](./terraform/main.tf): EC2, EBS, KMS, S3, IAM, SG, private DNS
- [`terraform/terraform.tfvars.example`](./terraform/terraform.tfvars.example): 16/64 ClickHouse와 8/32 PeerDB 예시
- [`terraform/templates/clickhouse-user-data.sh.tftpl`](./terraform/templates/clickhouse-user-data.sh.tftpl): EBS mount, 패키지 설치, TLS, admin/PeerDB 계정 생성
- [`terraform/templates/peerdb-user-data.sh.tftpl`](./terraform/templates/peerdb-user-data.sh.tftpl): EBS mount, Docker 설치, PeerDB/Temporal/catalog Compose 배포

운영 환경은 Terraform backend를 S3와 state locking으로 별도 구성한다. 예제에는 특정 계정의 backend를 하드코딩하지 않았다.

### 15.3 Secret 준비

Terraform variable에는 secret 값이 아니라 기존 Secrets Manager ARN만 넣는다. 다음 5개 secret을 먼저 만든다.

| Secret | `SecretString` 형식 | 접근 주체 |
|---|---|---|
| ClickHouse TLS | JSON: `server_crt`, `server_key`, `ca_crt` | ClickHouse EC2만 |
| ClickHouse CA | CA PEM 원문 | PeerDB EC2만 |
| ClickHouse admin password | 비밀번호 원문 | ClickHouse EC2만 |
| PeerDB용 ClickHouse password | 비밀번호 원문 | 두 EC2 |
| PeerDB environment | dotenv 3개 항목 | PeerDB EC2만 |

PeerDB environment secret 예시:

```dotenv
CATALOG_PASSWORD=long_random_alphanumeric_value
PEERDB_PASSWORD=long_random_alphanumeric_value
NEXTAUTH_SECRET=at_least_32_random_alphanumeric_characters
```

dotenv 해석이 달라지는 공백, 줄바꿈, `#`, 따옴표를 피하고 충분히 긴 URL-safe 또는 영숫자 값을 사용한다. customer-managed KMS key로 secret을 암호화했다면 key ARN을 `bootstrap_secret_kms_key_arns`에 추가한다. Terraform state, Git, shell history에 실제 비밀번호나 개인 키를 넣지 않는다.

TLS 인증서의 SAN은 `clickhouse_private_dns_name`과 일치해야 한다. 예를 들어 `clickhouse.internal.example.com` 인증서를 발급하고 동일한 private hosted zone record를 Terraform이 만들게 한다. ClickHouse Cloud의 관리형 인증서나 개인 키를 재사용하지 않는다.

### 15.4 Terraform 실행

```bash
cd chc/cloud-to-oss-peerdb/terraform
cp terraform.tfvars.example terraform.tfvars
# VPC/subnet/route table/private DNS/secret ARN을 실제 값으로 수정

terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

`terraform apply` 완료는 EC2 API 리소스 생성 완료를 의미하며, ClickHouse와 PeerDB 설치 완료를 의미하지 않는다. `user_data`는 별도 EBS attachment를 기다린 후 설치하므로 SSM에서 cloud-init 완료를 확인한다.

### 15.5 ClickHouse 자동 설치 내용

ClickHouse bootstrap은 다음 순서로 실행된다.

1. 별도 gp3 device가 보일 때까지 대기한다.
2. 새 volume일 때만 XFS로 포맷하고 UUID 기준으로 `/var/lib/clickhouse`에 mount한다.
3. 공식 ClickHouse `lts` 또는 `stable` apt repository에서 server/client를 설치한다.
4. Secrets Manager에서 TLS JSON과 admin/PeerDB password를 읽는다.
5. 평문 8123/9000을 제거하고 HTTPS 8443, native TLS 9440만 구성한다.
6. admin 사용자는 VPC CIDR로, `peerdb_ingest` 사용자는 PeerDB private IP `/32`로 제한한다.
7. 인증서 검증을 포함한 HTTPS health check 후 완료 marker를 만든다.

현재 single node이므로 Keeper와 9010 interserver listener는 설치하지 않는다. 패키지를 완전히 재현해야 하는 운영 환경은 검증된 ClickHouse 버전으로 AMI를 bake하고 패키지 업데이트를 명시적인 maintenance 절차로 분리한다.

SSM 접속 후 확인:

```bash
sudo cloud-init status --wait
sudo test -f /var/log/clickhouse-bootstrap.done
sudo tail -n 200 /var/log/clickhouse-bootstrap.log
sudo systemctl status clickhouse-server --no-pager
sudo ss -lntp | grep -E ':(8443|9440)'
```

다음이 모두 성립해야 한다.

- 8443/9440만 LISTEN
- 8123/9000/9010은 LISTEN하지 않음
- `/var/lib/clickhouse`가 별도 gp3 UUID로 mount됨
- server certificate chain과 hostname 검증 성공
- ClickHouse SG의 9440 source가 PeerDB SG 하나로 제한됨

### 15.6 PeerDB 자동 설치 내용

PeerDB bootstrap은 다음 순서로 실행된다.

1. 별도 gp3 volume을 XFS로 포맷하고 `/opt/peerdb-data`에 UUID mount한다.
2. Docker 공식 apt repository에서 Engine과 Compose plugin을 설치한다.
3. Docker data root를 PeerDB gp3의 `/opt/peerdb-data/docker`로 옮긴다.
4. ClickHouse CA와 PeerDB dotenv secret을 Secrets Manager에서 읽는다.
5. 고정한 image tag로 catalog PostgreSQL, Temporal, Temporal admin bootstrap, Flow API/worker/snapshot worker, PeerDB server/UI를 실행한다.
6. Temporal `MirrorName` custom search attribute 등록이 끝난 후 Flow service를 시작한다.
7. catalog PostgreSQL은 named volume으로 보존하고 Docker log rotation을 적용한다.
8. Compose 상태 확인 후 완료 marker를 만든다.

기본 `operator_cidr=null`에서는 PeerDB UI 3000과 SQL 9900이 `127.0.0.1`에만 bind된다. Terraform output의 SSM port-forward command로 접속한다. `operator_cidr`을 지정하면 두 포트가 private interface에 bind되고 해당 CIDR만 Security Group에서 허용된다. 인터넷 CIDR을 넣지 않는다.

SSM 접속 후 확인:

```bash
sudo cloud-init status --wait
sudo test -f /var/log/peerdb-bootstrap.done
sudo tail -n 200 /var/log/peerdb-bootstrap.log
cd /opt/peerdb
sudo docker compose config --quiet
sudo docker compose ps
sudo docker compose logs --tail=100
findmnt /opt/peerdb-data
```

이 Docker Compose 구성은 **production-lite 단일 호스트** 배포다. 프로세스 재시작과 EC2 간 장애 격리는 제공하지만 PeerDB HA는 제공하지 않는다. catalog/Temporal PostgreSQL volume의 EBS snapshot과 애플리케이션 수준 backup/restore를 모두 시험한다. 더 높은 HA가 필요하면 catalog를 RDS로 분리하고 공식 enterprise Helm/Kubernetes 구성을 검토한다.

### 15.7 SSM 포트 포워딩

실제 instance ID는 `terraform output`에서 확인한다. Terraform이 출력한 명령을 사용하거나 다음 형식으로 접속한다.

```bash
# PeerDB UI: 브라우저에서 http://localhost:3000
aws ssm start-session \
  --target i-peerdb \
  --document-name AWS-StartPortForwardingSession \
  --parameters portNumber=3000,localPortNumber=3000

# ClickHouse HTTPS: https://localhost:8443
aws ssm start-session \
  --target i-clickhouse \
  --document-name AWS-StartPortForwardingSession \
  --parameters portNumber=8443,localPortNumber=8443
```

인증서가 private DNS용이면 `localhost` hostname 검증은 실패한다. SQL client는 private DNS 이름을 사용하거나 로컬 hosts/사내 DNS를 통해 해당 이름이 tunnel endpoint로 해석되게 한다. 검증 편의를 이유로 `--insecure`를 운영 절차에 넣지 않는다.

### 15.8 PeerDB target 권한 부여

Bootstrap은 `peerdb_ingest` 계정을 만들지만 데이터베이스별 권한은 자동 부여하지 않는다. 실제 대상 database가 확정된 뒤 admin으로 최소 권한 role을 만든다.

```sql
CREATE DATABASE IF NOT EXISTS analytics;

CREATE ROLE IF NOT EXISTS peerdb_writer;
GRANT INSERT, SELECT, DROP, CREATE TABLE
    ON analytics.* TO peerdb_writer;
GRANT CREATE TEMPORARY TABLE, S3 ON *.* TO peerdb_writer;
GRANT ALTER ADD COLUMN ON analytics.* TO peerdb_writer;
GRANT peerdb_writer TO peerdb_ingest;
```

실제 고정 PeerDB 릴리스가 요구하는 권한 목록과 mirror mode를 확인해 불필요한 `DROP`/`ALTER`는 제거한다. `peerdb_ingest` password는 PeerDB target 등록 화면에서 Secrets Manager 값으로 설정하고, host는 `clickhouse_private_dns_name`, port는 `9440`, TLS와 CA 검증을 켠다. admin 계정을 PeerDB target에 사용하지 않는다.

### 15.9 Source peer와 mirror 생성

PeerDB UI에서 source와 ClickHouse target을 등록할 때 다음을 적용한다.

- DocumentDB: cluster endpoint, TLS ON, AWS CA 검증, change stream retention 확인
- RDS MySQL: ROW binlog, GTID, TLS ON, RDS CA 검증, binlog retention 확인
- ClickHouse: private DNS, 9440, `peerdb_ingest`, TLS/CA 검증
- Stage: Terraform이 만든 private S3 bucket과 EC2 instance role 사용
- Initial snapshot concurrency: 1~2개 table부터 시작
- Mirror: 10개를 한 번에 시작하지 않고 source별 소그룹으로 시작

PeerDB container가 instance role을 사용할 수 있도록 PeerDB EC2만 IMDSv2 hop limit 2로 설정한다. ClickHouse EC2는 container를 사용하지 않으므로 hop limit 1이다. 두 인스턴스 모두 IMDSv2 token을 필수로 한다.

### 15.10 설치 후 end-to-end 검증

1. PeerDB EC2에서 private DNS와 9440 연결을 확인한다.
2. 잘못된 CA 또는 hostname으로 연결이 거부되는지 negative test한다.
3. 작은 source table 하나로 initial snapshot과 CDC mirror를 실행한다.
4. INSERT, UPDATE, DELETE 각각을 발생시키고 target 결과와 lag를 확인한다.
5. S3 stage object가 SSE-KMS이며 public access가 차단됐는지 확인한다.
6. PeerDB container restart와 EC2 reboot 후 mirror checkpoint가 이어지는지 확인한다.
7. ClickHouse EBS snapshot restore와 PeerDB catalog/Temporal restore를 별도 staging에서 시험한다.
8. 검증 완료 후에만 기존 ClickPipes와 dual-run을 시작한다.

### 15.11 Upgrade와 제거

- Terraform `user_data` 변경은 기존 EC2에 설치 절차를 자동 재실행하지 않는다.
- ClickHouse package와 PeerDB image는 staging에서 호환성을 검증한 뒤 SSM maintenance 또는 새 AMI/EC2 교체 방식으로 올린다.
- PeerDB upgrade 전 catalog/Temporal backup과 rollback image tag를 확보한다.
- `terraform destroy`를 uninstall 명령처럼 사용하지 않는다.
- S3 bucket은 `force_destroy=false`이며, 별도 EBS와 backup의 보존·폐기 승인을 받은 뒤 명시적으로 처리한다.
- 데이터 폐기 시 KMS key의 30일 deletion window와 backup retention을 함께 검토한다.

## 16. 참고 자료와 버전 주의사항

- [ClickHouse TLS 구성](https://clickhouse.com/docs/concepts/features/security/tls/configuring-tls)
- [ClickHouse `remote`/`remoteSecure`](https://clickhouse.com/docs/reference/functions/table-functions/remote)
- [ClickHouse 사용자 인증과 HOST 제한](https://clickhouse.com/docs/reference/statements/create/user)
- [ClickHouse Named Collections](https://clickhouse.com/docs/concepts/features/configuration/server-config/named-collections)
- [ClickHouse Backup/Restore](https://clickhouse.com/docs/concepts/features/backup-restore/overview)
- [Amazon DocumentDB Change Streams](https://docs.aws.amazon.com/documentdb/latest/devguide/change_streams.html)
- [PeerDB ClickHouse target 권한과 TLS port](https://docs.peerdb.io/connect/clickhouse/clickhouse-cloud)
- [PeerDB architecture](https://docs.peerdb.io/architecture)
- [PeerDB connector status/source](https://github.com/PeerDB-io/peerdb)
- [PeerDB ClickHouse/Mongo TLS fields](https://github.com/PeerDB-io/peerdb/blob/main/protos/peers.proto)
- [PeerDB `_peerdb_version` 생성 코드](https://github.com/PeerDB-io/peerdb/blob/main/flow/connectors/clickhouse/normalize_query.go)
- [AWS M7i 인스턴스 사양](https://aws.amazon.com/ec2/instance-types/m7i/)
- [AWS R7i 인스턴스 사양](https://aws.amazon.com/ec2/instance-types/r7i/)
- [AWS gp3 성능과 확장](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html)
- [AWS instance store 데이터 지속성 주의사항](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-retirement.html)
- [Docker Engine Ubuntu 설치](https://docs.docker.com/engine/install/ubuntu/)
- [AWS EBS NVMe device mapping](https://docs.aws.amazon.com/ebs/latest/userguide/nvme-ebs-volumes.html)
- [AWS EC2 IMDSv2와 container hop limit](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-IMDS-new-instances.html)
- [AWS Systems Manager VPC endpoint](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)
- [PeerDB Enterprise 배포 resource 예시](https://github.com/PeerDB-io/peerdb-enterprise)

문서와 main branch는 실제 배포 버전보다 앞설 수 있다. 다음 항목은 반드시 고정 릴리스의 tag 또는 image digest 기준으로 다시 확인한다.

- PeerDB Mongo/DocumentDB CDC 동작
- ClickHouse target mTLS 필드와 UI/API 노출 여부
- `_peerdb_timestamp`와 `_peerdb_version` 의미
- ClickHouse `default_password_type=bcrypt_password` 지원
- TLS protocol/cipher 설정 이름
- 필요한 ClickHouse `GRANT` 목록
