# cloud-to-oss-peerdb

PeerDB를 이용해 **Amazon RDS for MySQL**과 **Amazon DocumentDB**의 데이터를 **ClickHouse
OSS**로 옮기는 경로(초기 스냅샷 + CDC)가 기능적으로 동작하는지 검증한 기록.

- 최종 판정: **PASS**
- 전체 보고서: [`REPORT.md`](./REPORT.md) / [`REPORT.pdf`](./REPORT.pdf)
- 세부 진행 기록: [`details/`](./details)
- 운영 보안·이관 런북: [`clickhouse-cloud-to-self-managed-security-runbook.md`](./clickhouse-cloud-to-self-managed-security-runbook.md)
- AI 전체 사이클 검증 지시서: [`AI-VALIDATION-WORK-INSTRUCTIONS.md`](./AI-VALIDATION-WORK-INSTRUCTIONS.md)
- EC2 배포 코드: [`terraform/`](./terraform/)

## 요약

| 항목 | 결과 |
|---|---|
| RDS MySQL → ClickHouse OSS 초기 적재 | 3개 테이블(customers/orders/order_items) 전수 일치 |
| DocumentDB → ClickHouse OSS 초기 적재 | 3개 컬렉션(profiles/events/mutable_docs) 전수 일치 |
| CDC (INSERT/UPDATE/DELETE) | 양쪽 소스 모두 정상 반영, 지연 15초 이내 |
| 보안 통제(TLS/암호화/네트워크 격리) | **검증 범위에서 완전히 제외** — 운영 전환 전 별도 재검증 필수 |
| ClickPipes 대조, remoteSecure backfill, cutover/rollback | 미수행 (범위 밖) |

## 왜 이 정도만 검증했는가

동일 디렉터리의 운영 런북은 ClickPipes와 PeerDB 경로를 나란히 돌려 대조하고,
cutover/rollback까지 시뮬레이션하는 전체 마이그레이션 절차를 다룬다. 이번 작업은 그중
**"PeerDB로 데이터가 실제로 옮겨지는가"** 한 가지 질문에 답하기 위한 최소 규모 기능
검증이었고, 성능·보안 검증은 처음부터 범위 밖이었다. 자세한 배경은 `REPORT.md` 1장,
[`details/scope-decisions.md`](./details/scope-decisions.md) 참고.

## 가장 중요한 발견

**PeerDB의 MongoDB 커넥터는 MongoDB 4.2 이상 호환 wire protocol(버전 8+)을 요구한다.**
이번 실행에서는 Amazon DocumentDB 4.0이 실패하고 8.0.1이 통과했다. DocumentDB 5.0은 AWS가
MongoDB 5.0 호환으로 제공하지만 이 실행에서는 직접 검증하지 않았으므로, 실제 고정 PeerDB
릴리스에서 peer validation과 snapshot/CDC smoke test를 먼저 수행해야 한다. 그 외에 실제로
부딪힌 이슈(11건)와 해결 방법은
[`details/bootstrap-issues.md`](./details/bootstrap-issues.md)에 순서대로 정리되어 있다 —
PeerDB의 공개 문서가 다루지 않는, 실제로 동작을 확인해야만 알 수 있는 내용들이다.

## 디렉터리 구성

```text
cloud-to-oss-peerdb/
├── README.md                       — 이 파일
├── REPORT.md / REPORT.pdf          — 완료된 기능 검증의 역사적 보고서
├── AI-VALIDATION-WORK-INSTRUCTIONS.md
├── clickhouse-cloud-to-self-managed-security-runbook.md
├── terraform/                      — EC2/EBS/KMS/S3/IAM/TLS 배포 코드
└── details/
    ├── scope-decisions.md   — 범위를 두 차례 좁힌 결정과 사유
    ├── bootstrap-issues.md  — 부트스트랩 중 만난 문제 11건과 해결책 (가장 상세한 기록)
    ├── source-fixtures.md   — 테스트에 사용한 소스 데이터 스키마
    ├── cdc-verification.md  — INSERT/UPDATE/DELETE 검증 결과 상세
    └── cleanup.md           — 사용한 AWS 리소스 정리 기록
```

## 재현 시 참고

이 저장소에는 실행에 사용한 자격 증명이나 특정 AWS 계정/리소스 식별자를 포함하지 않는다
(검증에 사용한 모든 AWS 리소스는 작업 완료 후 삭제했다). 동일한 방식으로 재현하려면
`REPORT.md`의 환경/버전 표와 `details/bootstrap-issues.md`의 각 항목을 참고하되, 운영 재현은
보안 런북의 SEC-2와 `terraform/`을 기준으로 구성할 것. 기존 보고서와 PDF는 당시 제한된
평문/public-subnet 기능 검증의 역사적 증적이며 현재 운영 권장 구성을 나타내지 않는다.
