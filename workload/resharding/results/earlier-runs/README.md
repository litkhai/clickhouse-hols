# Earlier runs (2026-11-07, 26.8.36.3, 12,000,000 rows)

Kept because the failure case's third variant (retry with the same `insert_deduplication_token`) gave different
answers from run to run. These runs used earlier revisions of `run.py`; the final result is `../26.8.36.3.json`.

| File | Started (KST) | What differed | Same-token retry of 202607 (1,957,895 rows expected) |
|---|---|---|---|
| `1-fail-only.log` | 13:00 | `run.py fail` only; `ch-s1r1` 900 MiB; variants 2–3 at the default `receive_timeout` (300 s). The last recovery copy hit the 900 MiB cap, so no JSON | exact: PASS |
| `2-all-crashed-in-probe-check.log` | 13:18 | `ch-s1r1` 1,400 MiB; variants 2–3 at `receive_timeout = 30`. Crashed after the failure case: the probe check sent its query in the URL, which became too long | 1,960,631 rows, 1,944,417 distinct: FAIL |
| `3-all-crashed-in-b-reset.{log,json}` | 13:32 | As 2, query in the POST body. Crashed loading data for B (900 MiB cap on `ch-s2r1`); the JSON holds selftest, A, D and the failure case | 1,957,662 rows, 1,952,329 distinct: FAIL |

Earlier development runs with 600,000 rows are not kept.

---

# 이전 실행 (2026-11-07, 26.8.36.3, 1,200만 행)

장애 사례의 세 번째 변형(같은 `insert_deduplication_token`으로 재시도)이 실행마다 다른 답을 내서 남겨 둡니다. 이 실행들은
이전 버전의 `run.py`를 썼고, 최종 결과는 `../26.8.36.3.json`입니다. 위 표: 1은 `fail`만 실행(같은 토큰 재시도 PASS),
2와 3은 `all`이 장애 사례 뒤에 멈춘 실행(같은 토큰 재시도 FAIL, 중복과 누락이 섞임)입니다. 60만 행 개발 실행은 남기지 않았습니다.
