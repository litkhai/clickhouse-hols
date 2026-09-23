# STATUS.md

Repository health snapshot. Regenerate the numbers with the commands in each
section rather than trusting the date at the top.

**As of 2026-09-23** — 26.9 release lab added, all checks green locally.

---

## CI

| Job | State | Notes |
|-----|-------|-------|
| `links` | ✅ | 185 markdown files, every relative link resolves |
| `syntax` | ✅ | 268 shell, 78 python, 26 yaml files parse |
| `site` | ✅ | `docs/` matches 21 releases + 55 labs = 76 lab pages, 82 files |
| `hygiene` | ✅ | no shadowed tracked files, no `/Users/` paths, no TF state |
| `secrets` | ✅ | gitleaks, `.gitleaks.toml` rules |
| `shellcheck` | ⚠️ advisory | style findings across 200+ scripts, non-blocking by design |

`main` was **red from 2026-09-20 08:45 to 2026-09-23** — runs
[35500418709](https://github.com/litkhai/clickhouse-hols/actions/runs/35500418709)
and
[35501474415](https://github.com/litkhai/clickhouse-hols/actions/runs/35501474415)
failed `links` and `site`. Both causes are fixed:

- `usecase/timeseries-promql-oss/README.md` linked to
  `../timeseries-promql-cloud/`, a lab that was never written. The dead link is
  replaced with prose explaining that `TimeSeries` is Private Preview only on
  Cloud, which is why no Cloud counterpart exists.
- The new lab's page was never generated into `docs/`.

Note that `check_links.py` reads `git ls-files`, so an **untracked** new lab is
not checked at all. `git add` before you trust a green run.

Reproduce locally:

```bash
python3 .github/scripts/check_links.py
./.github/scripts/check_syntax.sh
python3 .github/scripts/build_site.py --check
gitleaks detect --config .gitleaks.toml --no-banner --redact
```

## Inventory

55 indexed labs plus 21 per-release labs. Counts are rows in the **English**
area tables of `README.md`:

| Area | Labs |
|------|-----:|
| `chc/` — ClickHouse Cloud integrations | 15 |
| `local/` — local environments | 8 |
| `managed-postgres/` | 4 |
| `usecase/` | 13 |
| `workload/` | 11 |
| `workshop/` | 3 |
| `tpcds/` — benchmark | 1 |
| `local/releases/` — per-release feature labs | 21 |

```bash
for a in chc local managed-postgres usecase workload workshop; do
  printf '%-18s %s\n' "$a" "$(grep -c "^| \[$a/" README.md)"   # EN+KO, so halve
done
```

## Known gaps

| Gap | Impact | Notes |
|-----|--------|-------|
| 28 of 55 indexed labs are single-language | Low | Predate the `[English](#english) \| [한국어](#한국어)` layout. The site shows the same body under both toggle positions, so nothing renders broken. Mostly `chc/` Terraform labs and older `workshop/` material. |
| `chc/{api,kafka,lake,s3,tool}` have no `README.md` | None | They are category directories, not labs; their children are indexed individually. |
| `shellcheck` findings unaddressed | Low | Deliberately advisory — see the comment in `.github/workflows/checks.yml`. |
| `core.hooksPath` is per-clone | Medium | Not set automatically. An unconfigured clone commits without the secret / host-path / syntax guard and only finds out in CI. This is what let the two failures above reach `main`. |

List the single-language labs:

```bash
python3 - <<'PY'
import re, pathlib
root = pathlib.Path('.')
rows = re.findall(r"^\|\s*\[([^\]]+)\]\(([^)]+)\)\s*\|", (root/'README.md').read_text(), re.M)
paths = sorted({p.strip('/') for _, p in rows if '/' in p and not p.startswith('http')})
for p in paths:
    f = root/p/'README.md'
    if f.exists() and '[English](#english)' not in f.read_text():
        print(p)
PY
```

## Secret scan

**Tracked working-tree files: 0 findings.** Every hit from `gitleaks detect
--no-git` (86) is in a gitignored local file — `.credentials`, `.env`,
`.claude/settings.local.json`, local result dumps. None are committed.

Beware the scan you run. `gitleaks detect` with no `--log-opts` walks **all
refs**, including the local-only `backup-local-main-20260907` branch, and
reports 80 findings. That branch is the pre-rewrite history; it is not on
`origin` and never was. To scan what is actually public:

```bash
gitleaks detect --config .gitleaks.toml --log-opts="origin/main" --no-banner --redact
```

Published history (`origin/main`, 256 commits) has **19 findings, none
exploitable**:

| Count | Where | Assessment |
|------:|-------|------------|
| 10 | `local/llm-mac-librechat/docker-compose*.yml` (d7bf236, 2025-12-07) | Real generated LibreChat app secrets (`JWT_SECRET`, `CREDS_KEY`, …), but they scope to a local single-user container, not a cloud resource. Path no longer exists. Regenerate if you ever reused them. |
| 3 | `terraform-glue-s3-chc-integration/CREDENTIAL_SOLUTIONS.md` (dfd8efc, 2025-11-16) | Ellipsis-truncated sample output of `ASIA`-prefixed STS **temporary** credentials, pasted to show their shape. Incomplete, and expired within hours of being written. |
| 4 | `usecase/bug-bounty/05-generate-demo-data.sql` | Deliberately synthetic — MD5 of the word `password`, an `sk-proj-abcd1234…` stub, the canonical jwt.io sample token. The lab plants fake secrets on purpose. |
| 2 | `tpcds/00-set-{GUIDE,README}.md` | The password is the literal word *secret* in an example export line. |

The ClickHouse Cloud API key, service password and hostname that appear in the
`backup-local-main-20260907` branch are **not** in published history — the
2026-09-07 rewrite removed them successfully. Two caveats worth a decision:

- Those credentials were public before the rewrite. Confirm they were rotated;
  a Cloud API key is organization-wide.
- The backup branch keeps them alive in this clone. Delete it once you no
  longer need the pre-rewrite history:
  `git branch -D backup-local-main-20260907 && git reflog expire --expire=now --all && git gc --prune=now`

## Licensing exceptions

Two tracked paths are not MIT. Both are documented in the root README and must
stay that way if the files move:

- `tpcds/queries/` — GPL-3.0, adapted from Altinity/tpc-ds
- `usecase/korea-geo/data/` — KOSTAT terms, no SPDX licence

## Repository size

`.git` is 7.1 MB, 6.07 MiB packed. Largest tracked file is
`chc/cloud-to-oss-peerdb/REPORT.pdf` at 0.62 MB. No LFS, no archives — the
`hygiene` job rejects zip-shaped files because a saved `tfplan` embeds
Terraform state.

---

## 한국어 요약

- **CI 상태**: 위 6개 작업 모두 통과. `main`은 2026-09-20 08:45부터
  2026-09-23까지 `links`·`site` 실패로 red 상태였고, 두 원인 모두 수정됨
  (존재하지 않는 `timeseries-promql-cloud` 링크, 누락된 `docs/` 페이지).
- **주의**: `check_links.py`는 `git ls-files`를 읽으므로 **추적되지 않은**
  새 실습은 아예 검사하지 않습니다. 녹색 결과를 믿기 전에 `git add` 하세요.
- **규모**: 색인된 실습 55개 + 릴리스별 실습 21개 = 사이트 페이지 76개.
- **알려진 격차**: 55개 중 28개가 단일 언어(구형 실습). 사이트는 양쪽 토글에
  같은 본문을 보여주므로 깨지지는 않음 — 백로그 항목.
- **주의**: `git config core.hooksPath .githooks`는 클론마다 직접 설정해야
  합니다. 설정하지 않은 클론이 위 두 실패를 `main`까지 통과시켰습니다.
- **시크릿 스캔**: 추적 중인 작업 트리 파일에서 발견 0건. `gitleaks detect`를
  옵션 없이 실행하면 로컬 전용 `backup-local-main-20260907` 브랜치까지 훑어
  80건이 나오지만, 공개된 `origin/main` 기준으로는 19건이며 모두 악용 불가
  (로컬 전용 LibreChat 앱 시크릿, 잘린 만료 STS 자격증명, 의도적 더미 데이터,
  `'secret'` 리터럴). 공개 범위만 보려면
  `--log-opts="origin/main"`을 붙이세요.
- 다만 rewrite 이전에는 Cloud API 키가 공개돼 있었으므로 **로테이션 여부를
  확인**하세요 (Cloud API 키는 조직 전체 범위입니다).
