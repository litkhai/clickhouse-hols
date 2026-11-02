# Decryption with an audit trail for Langfuse fields (open-source stack)

[English](#english) | [한국어](#한국어)

---

## English

**Verified end to end on 2026-11-02** against Langfuse 4.56.0 (OSS, no licence key, from the
[langfuse-hols](https://github.com/litkhai/langfuse-hols) v4 stack), ClickHouse 26.8.22.13, OpenBao 2.7.2 and Keycloak 26.8.1. Fresh volumes; the decryption service ran on `python:3.12.15-slim`; Docker 29.9.2, Compose v5.6.1. `02` passed 7 checks and `03` passed 28. A fault injected on purpose (bob added to `svc-a-readers`) made `03` fail 5 checks, and it passed again once the fault was removed.

Regulated teams ask for three things around LLM traces: encrypt sensitive fields, let only authorised people see them in clear, and keep a record of **who decrypted what, when and why**. Langfuse stores whatever it receives and has no decryption or read-audit feature. Its audit log, an Enterprise feature, records create/update/delete only. So the record has to come from the decryption path. This lab builds that path from open-source parts and tests it.

### Architecture

```
  app ── encrypt (OpenBao Transit, encrypt-only token) ──► Langfuse OSS  (stores enc:<key>:vault:v1:…)
                                                              │ public API (service's project key)
  user ── IdP login (Keycloak) ── POST /decrypt + reason ──► decrypt-service ──► audit ClickHouse
                                                              │  1. attempt row      (audit.decrypt_events,
                                                              │  2. OpenBao login     insert-only writer,
                                                              │     with the USER's JWT                select-only auditor)
                                                              │  3. transit/decrypt + X-Request-Id
                                                              ▼  4. outcome row
                                                           OpenBao ── audit file ──► read in place by ClickHouse file()
```

- **The service holds no OpenBao token.** It logs in with the user's own JWT, through a role per key (`reader-svc-a`, `reader-svc-b`). OpenBao checks the signature against Keycloak and checks the `groups` claim, so the identity in OpenBao's audit log is the user's own.
- **No trail, no decryption.** The `attempt` row is written before OpenBao is asked to decrypt. If it cannot be written, the service answers 503 and OpenBao is never called.
- **Two records, reconciled.** The service's rows have the who, why and result. OpenBao's file shows that the key was actually used. ClickHouse reads that file with `file()`, and a query lists decryptions OpenBao performed that have no `attempt` row. Someone with the right who goes to OpenBao directly shows up there.

### Prerequisites

- The langfuse-hols v4 stack running: in that repository, `_base/bin/up.sh v4`. No licence key is needed. The lab looks for the clone next to this repository; set `LANGFUSE_HOLS_DIR` otherwise.
- Docker with Compose, `curl`, `jq`, `openssl`, `python3`.
- Free loopback ports 8090 (Keycloak), 8095 (decrypt-service), 8200 (OpenBao) and 18123 (audit ClickHouse).

### Run

```bash
cd usecase/langfuse-decryption-audit
./01-up.sh               # .env with generated passwords, 4 containers, OpenBao/ClickHouse/Keycloak config
./02-encrypt-and-send.sh # the "app": encrypt with OpenBao, send 2 encrypted + 1 plaintext trace to Langfuse
./03-decrypt-checks.sh   # 9 request scenarios, a bypass, the trail, the reconciliation, immutability
./04-audit-report.sh     # the reviewer's queries (per user, refusals, reconciliation)
./99-down.sh [--purge]   # --purge also deletes the audit table, OpenBao's audit file, .env and .state
```

OpenBao runs in dev mode (in memory), so `01-up.sh` applies its configuration on every run. Langfuse is not touched by `99-down.sh`.

### What the checks found (2026-11-02)

`02-encrypt-and-send.sh`: 7 PASS
- The app's token encrypts with both keys and gets **HTTP 403** when it tries to decrypt.
- Langfuse's API returns `enc:svc-a:vault:v1:…` for the encrypted traces; Langfuse's ClickHouse holds **0** rows with their plaintext, and the plaintext control is found by the same query.

`03-decrypt-checks.sh`: 28 PASS

| Request | Result | OpenBao's reason (in the service row) |
|---|---|---|
| alice (`svc-a-readers`) → A, with a reason | 200, plaintext | — |
| carol (`svc-b-readers`) → B, with a reason | 200, plaintext | — |
| alice → B | 403 | `claim "groups" does not match any associated bound claim values` |
| bob (no group) → A | 403 | `"groups" claim not found in token` |
| alice → A, no reason | 400 | (stopped by the service before OpenBao) |
| no token | 401 | — |
| alice's token edited to carol / `svc-b-readers`, signature kept | 403 | `error verifying token signature` |
| audit ClickHouse stopped | 503, no plaintext | OpenBao received **0** decrypt calls for that request |
| alice straight to OpenBao (bypass) | plaintext | she holds the right; no service row |

- **The service's rows:** after these requests the table holds `attempt 2, denied 3, reason_missing 1, success 2, unauthenticated 1`. A refusal records the user the token *claimed* (`claimed_user`) and an empty verified `user`. The edited token is logged as `carol (claimed)`. The table holds 0 plaintext, and so does the service's container log.
- **OpenBao's file:** the entry for alice's request id carries `username: alice` and `transit/decrypt/svc-a`. The three refused logins match the three denied rows by request id. The file holds 0 plaintext (raw or base64) and 0 token signatures; the request id is there in clear.
- **Reconciliation:** exactly 1 decryption without an `attempt` row, alice's bypass.
- **Immutability:** `audit_writer` gets Code 497 for SELECT, `ALTER … DELETE` and TRUNCATE. `auditor` gets Code 497 for INSERT and `ALTER … UPDATE`. The row count is unchanged afterwards.

### Things worth knowing

- **OpenBao 2.7.2 does not enable audit devices through the API.** It returns `cannot enable audit device via API; use declarative, config-based audit device management instead`. The device is an `audit` block in [openbao/audit.hcl](openbao/audit.hcl). Dev mode accepts it with `-config`.
- **A refused login is a normal response in OpenBao's audit file, and its message is HMAC'd** (`response.data.error = "hmac-sha256:…"`). The file says *that* a login failed; only the service row says *why*.
- **The request id is the join key.** `sys/config/auditing/request-headers/X-Request-Id` with `hmac: false` keeps it in clear. The ciphertext and the returned plaintext are HMAC'd.
- **ClickHouse 26.8:** `GRANT READ ON FILE` is shown as `GRANT FILE ON *.*`. The reconciliation's `IN (subquery)` also needs `CREATE TEMPORARY TABLE ON *.*` for the auditor; without it the query fails with Code 497.
- **Log the intent before decrypting.** The first version wrote its row after decrypting: with the audit store down, OpenBao had already decrypted though the user got nothing. The `attempt` row closes that gap. Report 4 lists attempts with no outcome row.

### Mapping to Azure (documented, not run)

| Here | On Azure |
|---|---|
| OpenBao Transit key per service | Azure Key Vault key per service, `decrypt` / `unwrapKey` operations |
| OpenBao audit file | Key Vault diagnostic logs (`AuditEvent`) to Log Analytics or a storage account |
| Keycloak | Microsoft Entra ID; groups claim or app roles |
| the user's JWT → OpenBao role | the service calls Key Vault with the user's token (on-behalf-of), so the caller identity in Key Vault's log is the user |
| audit ClickHouse + reconciliation | the same table; Key Vault's logs exported and joined by request id |

### Not production

- OpenBao runs in dev mode (in-memory storage, auto-unsealed, root token in `.env`). Production needs real storage, unseal, TLS and no root token in use.
- Users get tokens through the password grant only to script the lab. A real portal uses the authorization code flow.
- The service is single-instance, stdlib, without TLS. OpenBao's audit file is shared with ClickHouse through a volume; in production ship it (or a socket device) to the audit store.

### Files

| File | What |
|---|---|
| [docker-compose.yml](docker-compose.yml) | OpenBao, Keycloak, audit ClickHouse, decrypt-service |
| [openbao/audit.hcl](openbao/audit.hcl) | declarative file audit device |
| [keycloak/realm-corp.json](keycloak/realm-corp.json) | realm, groups, `decrypt-portal` client (groups claim, `openbao` audience) |
| [decrypt-service/service.py](decrypt-service/service.py) | the decryption service (stdlib) |
| [clickhouse/schema.sql](clickhouse/schema.sql) | `audit.decrypt_events` with TTL |
| [04-audit-report.sql](04-audit-report.sql) | reviewer queries, incl. the reconciliation over `file()` |
| `01`–`04`, `99`, [lib.sh](lib.sh) | setup, checks, report, teardown |

Related: field encryption in the Python SDK's export hook is langfuse-hols [`labs/v4/langfuse-ee` step 14](https://github.com/litkhai/langfuse-hols/tree/main/labs/v4/langfuse-ee).

---

## 한국어

**2026-11-02에 처음부터 끝까지 검증**했습니다. Langfuse 4.56.0(OSS, 라이선스 키 없음, [langfuse-hols](https://github.com/litkhai/langfuse-hols) v4 스택), ClickHouse 26.8.22.13, OpenBao 2.7.2, Keycloak 26.8.1 기준입니다. 새 볼륨으로 실행했고, 복호화 서비스는 `python:3.12.15-slim`에서 돌렸습니다. Docker 29.9.2, Compose v5.6.1입니다. `02`는 확인 7개, `03`은 28개를 통과했습니다. 일부러 넣은 결함(bob을 `svc-a-readers`에 추가)에서 `03`은 5개가 실패했고, 결함을 되돌리자 다시 통과했습니다.

규제가 있는 조직은 LLM trace에 세 가지를 요구합니다. 민감 필드를 암호화할 것, 권한이 있는 사람만 평문을 볼 것, 그리고 **누가 언제 무엇을 왜 복호화했는지** 기록할 것입니다. Langfuse는 받은 값을 그대로 저장할 뿐 복호화 기능도 조회 감사 기능도 없습니다. Enterprise 기능인 감사 로그도 생성·수정·삭제만 기록합니다. 그래서 기록은 복호화 경로에서 남겨야 합니다. 이 실습은 그 경로를 오픈소스로 만들고 시험합니다.

### 구조

```
  앱 ── 암호화 (OpenBao Transit, 암호화 전용 토큰) ──► Langfuse OSS  (enc:<키>:vault:v1:… 저장)
                                                           │ public API (서비스의 프로젝트 키)
  사용자 ── IdP 로그인 (Keycloak) ── POST /decrypt + 사유 ──► decrypt-service ──► 감사 ClickHouse
                                                           │  1. attempt 행        (audit.decrypt_events,
                                                           │  2. 사용자 JWT로        쓰기 전용 writer,
                                                           │     OpenBao 로그인       읽기 전용 auditor)
                                                           │  3. transit/decrypt + X-Request-Id
                                                           ▼  4. 결과 행
                                                        OpenBao ── 감사 파일 ──► ClickHouse file()로 그 자리에서 읽음
```

- **서비스는 OpenBao 토큰을 갖고 있지 않습니다.** 사용자 본인의 JWT로, 키마다 있는 role(`reader-svc-a`, `reader-svc-b`)에 로그인합니다. OpenBao가 Keycloak 기준으로 서명과 `groups` claim을 확인하므로, OpenBao 감사 로그에 남는 신원도 사용자 본인입니다.
- **이력이 없으면 복호화도 없습니다.** OpenBao에 복호화를 요청하기 전에 `attempt` 행을 씁니다. 쓰지 못하면 503으로 끝나고 OpenBao는 호출되지 않습니다.
- **두 기록을 대조합니다.** 서비스 행에는 누가, 왜, 결과가 있습니다. OpenBao 파일은 키가 실제로 쓰였다는 기록입니다. ClickHouse가 그 파일을 `file()`로 읽고, `attempt` 행이 없는 OpenBao 복호화를 쿼리로 찾습니다. 권한이 있는 사람이 OpenBao로 직접 간 경우가 여기에 걸립니다.

### 사전 준비

- langfuse-hols v4 스택 실행: 그 저장소에서 `_base/bin/up.sh v4`. 라이선스 키는 필요 없습니다. 이 저장소 옆에 clone이 있다고 보고, 다르면 `LANGFUSE_HOLS_DIR`을 지정합니다.
- Docker와 Compose, `curl`, `jq`, `openssl`, `python3`.
- 비어 있는 loopback 포트 8090(Keycloak), 8095(decrypt-service), 8200(OpenBao), 18123(감사 ClickHouse).

### 실행

```bash
cd usecase/langfuse-decryption-audit
./01-up.sh               # 생성한 비밀번호로 .env, 컨테이너 4개, OpenBao·ClickHouse·Keycloak 설정
./02-encrypt-and-send.sh # "앱" 역할: OpenBao로 암호화, Langfuse에 암호화 trace 2개와 평문 대조 1개 전송
./03-decrypt-checks.sh   # 요청 시나리오 9개, 우회, 이력, 대조, 수정 불가 확인
./04-audit-report.sh     # 감사 담당 쿼리(사용자별, 거부, 대조)
./99-down.sh [--purge]   # --purge는 감사 테이블, OpenBao 감사 파일, .env, .state까지 삭제
```

OpenBao는 dev 모드(메모리)라 `01-up.sh`가 실행할 때마다 설정을 다시 넣습니다. `99-down.sh`는 Langfuse를 건드리지 않습니다.

### 확인한 것 (2026-11-02)

`02-encrypt-and-send.sh`: 7개 PASS
- 앱 토큰은 두 키로 암호화할 수 있고, 복호화를 시도하면 **HTTP 403**입니다.
- Langfuse API는 암호화한 trace에 `enc:svc-a:vault:v1:…`를 돌려주고, Langfuse의 ClickHouse에서 그 평문을 가진 행은 **0**개입니다. 같은 쿼리가 평문 대조는 찾습니다.

`03-decrypt-checks.sh`: 28개 PASS

| 요청 | 결과 | OpenBao의 거부 사유(서비스 행에 기록) |
|---|---|---|
| alice(`svc-a-readers`) → A, 사유 있음 | 200, 평문 | — |
| carol(`svc-b-readers`) → B, 사유 있음 | 200, 평문 | — |
| alice → B | 403 | `claim "groups" does not match any associated bound claim values` |
| bob(그룹 없음) → A | 403 | `"groups" claim not found in token` |
| alice → A, 사유 없음 | 400 | (OpenBao 전에 서비스가 막음) |
| 토큰 없음 | 401 | — |
| alice 토큰을 carol / `svc-b-readers`로 고치고 서명은 그대로 | 403 | `error verifying token signature` |
| 감사 ClickHouse 중지 | 503, 평문 없음 | 그 요청으로 OpenBao 복호화 호출 **0**회 |
| alice가 OpenBao로 직접(우회) | 평문 | 권한은 있음, 서비스 행은 없음 |

- **서비스 행:** 위 요청 뒤 테이블은 `attempt 2, denied 3, reason_missing 1, success 2, unauthenticated 1`입니다. 거부된 요청에는 토큰이 *주장한* 사용자(`claimed_user`)가 남고, 검증된 `user`는 비어 있습니다. 고친 토큰은 `carol (claimed)`로 남습니다. 테이블에도, 서비스 컨테이너 로그에도 평문은 0건입니다.
- **OpenBao 파일:** alice의 request id 항목에 `username: alice`와 `transit/decrypt/svc-a`가 있습니다. 거부된 로그인 3건이 서비스의 denied 행 3건과 request id로 맞습니다. 평문(원문, base64)과 토큰 서명은 0건이고, request id는 평문으로 있습니다.
- **대조:** `attempt` 행이 없는 복호화는 정확히 1건, alice의 우회입니다.
- **수정 불가:** `audit_writer`는 SELECT, `ALTER … DELETE`, TRUNCATE에서 Code 497을 받았습니다. `auditor`는 INSERT와 `ALTER … UPDATE`에서 Code 497입니다. 이후 행 수는 그대로였습니다.

### 알아 둘 것

- **OpenBao 2.7.2는 API로 감사 장치를 켜지 않습니다.** `cannot enable audit device via API; use declarative, config-based audit device management instead`로 거부합니다. 장치는 [openbao/audit.hcl](openbao/audit.hcl)의 `audit` 블록이고, dev 모드도 `-config`로 받습니다.
- **거부된 로그인은 OpenBao 감사 파일에 일반 응답으로 남고, 메시지는 HMAC으로 가려집니다**(`response.data.error = "hmac-sha256:…"`). 파일은 로그인이 실패했다는 *사실*만 알려 주고, *이유*는 서비스 행에만 있습니다.
- **request id가 연결 키입니다.** `sys/config/auditing/request-headers/X-Request-Id`에 `hmac: false`를 주면 평문으로 남습니다. 암호문과 돌려준 평문은 HMAC으로 남습니다.
- **ClickHouse 26.8:** `GRANT READ ON FILE`은 `GRANT FILE ON *.*`로 보입니다. 대조 쿼리의 `IN (subquery)`는 auditor에게 `CREATE TEMPORARY TABLE ON *.*`도 필요합니다. 없으면 Code 497로 실패합니다.
- **복호화 전에 의도를 남깁니다.** 첫 버전은 복호화한 뒤에 행을 썼습니다. 그래서 감사 저장소가 내려가 있으면 사용자는 아무것도 못 받았는데 OpenBao는 이미 복호화한 상태였습니다. `attempt` 행이 이 틈을 막습니다. 보고서 4번이 결과 행이 없는 attempt를 보여 줍니다.

### Azure에 대응하면 (문서 기준, 실행하지 않음)

| 여기 | Azure |
|---|---|
| 서비스별 OpenBao Transit 키 | 서비스별 Azure Key Vault 키, `decrypt` / `unwrapKey` 연산 |
| OpenBao 감사 파일 | Key Vault 진단 로그(`AuditEvent`)를 Log Analytics나 스토리지로 |
| Keycloak | Microsoft Entra ID, groups claim 또는 앱 역할 |
| 사용자 JWT → OpenBao role | 서비스가 사용자 토큰으로 Key Vault 호출(on-behalf-of), Key Vault 로그의 호출자가 사용자 |
| 감사 ClickHouse + 대조 | 같은 테이블, Key Vault 로그를 내보내 request id로 대조 |

### 운영용이 아닌 부분

- OpenBao는 dev 모드입니다(메모리 저장소, 자동 unseal, `.env`의 root 토큰). 운영에는 실제 저장소, unseal, TLS가 필요하고 root 토큰을 쓰지 않습니다.
- 사용자 토큰을 password grant로 받는 것은 실습을 스크립트로 돌리기 위해서입니다. 실제 화면은 authorization code 방식을 씁니다.
- 서비스는 단일 인스턴스, stdlib, TLS 없음입니다. OpenBao 감사 파일은 볼륨으로 ClickHouse와 나눕니다. 운영에서는 파일(또는 socket 장치)을 감사 저장소로 보냅니다.

### 파일

| 파일 | 내용 |
|---|---|
| [docker-compose.yml](docker-compose.yml) | OpenBao, Keycloak, 감사 ClickHouse, decrypt-service |
| [openbao/audit.hcl](openbao/audit.hcl) | 선언형 파일 감사 장치 |
| [keycloak/realm-corp.json](keycloak/realm-corp.json) | realm, 그룹, `decrypt-portal` client(groups claim, `openbao` audience) |
| [decrypt-service/service.py](decrypt-service/service.py) | 복호화 서비스(stdlib) |
| [clickhouse/schema.sql](clickhouse/schema.sql) | TTL이 있는 `audit.decrypt_events` |
| [04-audit-report.sql](04-audit-report.sql) | 감사 담당 쿼리, `file()` 위의 대조 포함 |
| `01`–`04`, `99`, [lib.sh](lib.sh) | 설정, 확인, 보고서, 정리 |

관련: Python SDK의 export hook에서 하는 필드 암호화는 langfuse-hols [`labs/v4/langfuse-ee` 14단계](https://github.com/litkhai/langfuse-hols/tree/main/labs/v4/langfuse-ee)입니다.
