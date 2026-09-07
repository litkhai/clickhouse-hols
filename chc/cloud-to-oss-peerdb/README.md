# cloud-to-oss-peerdb

PeerDB를 이용해 **Amazon RDS for MySQL**과 **Amazon DocumentDB**의 데이터를 **ClickHouse
OSS**로 옮기는 경로(초기 스냅샷 + CDC)가 기능적으로 동작하는지 검증한 기록.

- 최종 판정: **PASS**
- 전체 보고서: [`REPORT.md`](./REPORT.md) / [`REPORT.pdf`](./REPORT.pdf)
- 세부 진행 기록: [`details/`](./details)

## 요약

| 항목 | 결과 |
|---|---|
| RDS MySQL → ClickHouse OSS 초기 적재 | 3개 테이블(customers/orders/order_items) 전수 일치 |
| DocumentDB → ClickHouse OSS 초기 적재 | 3개 컬렉션(profiles/events/mutable_docs) 전수 일치 |
| CDC (INSERT/UPDATE/DELETE) | 양쪽 소스 모두 정상 반영, 지연 15초 이내 |
| 보안 통제(TLS/암호화/네트워크 격리) | **검증 범위에서 완전히 제외** — 운영 전환 전 별도 재검증 필수 |
| ClickPipes 대조, remoteSecure backfill, cutover/rollback | 미수행 (범위 밖) |

## 왜 이 정도만 검증했는가

원래 대상 런북(`../cloud-to-oss/`)은 ClickPipes와 PeerDB 경로를 나란히 돌려 대조하고,
cutover/rollback까지 시뮬레이션하는 전체 마이그레이션 절차를 다룬다. 이번 작업은 그중
**"PeerDB로 데이터가 실제로 옮겨지는가"** 한 가지 질문에 답하기 위한 최소 규모 기능
검증이었고, 성능·보안 검증은 처음부터 범위 밖이었다. 자세한 배경은 `REPORT.md` 1장,
[`details/scope-decisions.md`](./details/scope-decisions.md) 참고.

## 가장 중요한 발견

**PeerDB의 MongoDB 커넥터는 MongoDB 4.2 이상 호환 wire protocol(버전 8+)을 요구한다.**
Amazon DocumentDB를 소스로 쓸 계획이라면, 엔진 버전이 이 요구사항을 만족하는지 계획
단계에서 반드시 먼저 확인할 것 — 이번 검증에서도 처음 선택한 엔진 버전이 호환되지 않아
클러스터를 다시 만들어야 했다. 그 외에 실제로 부딪힌 이슈(9건)와 해결 방법은
[`details/bootstrap-issues.md`](./details/bootstrap-issues.md)에 순서대로 정리되어 있다 —
PeerDB의 공개 문서가 다루지 않는, 실제로 동작을 확인해야만 알 수 있는 내용들이다.

## 디렉터리 구성

```text
cloud-to-oss-peerdb/
├── README.md              — 이 파일
├── REPORT.md / REPORT.pdf — 전체 보고서 (배경, 환경, 트러블슈팅, 검증 결과, 후속 권고)
└── details/
    ├── scope-decisions.md   — 범위를 두 차례 좁힌 결정과 사유
    ├── bootstrap-issues.md  — 부트스트랩 중 만난 문제 9건과 해결책 (가장 상세한 기록)
    ├── source-fixtures.md   — 테스트에 사용한 소스 데이터 스키마
    ├── cdc-verification.md  — INSERT/UPDATE/DELETE 검증 결과 상세
    └── cleanup.md           — 사용한 AWS 리소스 정리 기록
```

## 재현 시 참고

이 저장소에는 실행에 사용한 자격 증명이나 특정 AWS 계정/리소스 식별자를 포함하지 않는다
(검증에 사용한 모든 AWS 리소스는 작업 완료 후 삭제했다). 동일한 방식으로 재현하려면
`REPORT.md`의 환경/버전 표와 `details/bootstrap-issues.md`의 각 항목을 참고해 자체
환경에서 구성할 것.
