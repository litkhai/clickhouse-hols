# STATUS.md

Repository health snapshot. Regenerate the numbers with the commands in each
section rather than trusting the date at the top.

**As of 2026-10-06 (langfuse-on-clickhouse)** — `usecase/langfuse-on-clickhouse` added (#7): a T0 lab on a committed snapshot of Langfuse v4's ClickHouse tables, published to the notes site (`third-party`). Before that, **as of 2026-10-06 (notes-site migration)** — 11 labs moved in from the author's notes site, Korean as written plus an LLM-assisted English translation, each opening with a "migrated, not verified" banner and carrying publishing keys only (no runner keys, no verification claim): `chc/{getting-started,mcp-claude-desktop,clickpipes-kafka,elasticity-idling,metabase,spark-streaming-conversion}`, `local/oss-single-node-analytics`, `usecase/{json-survey-consolidation,url-webhook-slack-alert}`, `workload/{cascading-mv-ttl,mv-chain-failure}`. 17 existing labs gained publishing keys, and `usecase/customer360` and `usecase/security-traffic-analysis` a migrated subsection with the notes the README lacked. `docs/labs.json`: 29 labs. Screenshots with a service host or a personal path were pixelated or left out. Before that, **as of 2026-10-06** — `usecase/korean-rag-tokenizers` added, the first lab outside `local/releases` with a runner `lab.yaml` (T0), and the first published to the notes site (`web: true`, `case-study`). As of 2026-10-03, `docs/labs.json` added: the notes-site export written by `build_site.py`, 0 labs published (none sets `web: true`). Before that, as of 2026-09-27: repository split done (see [MOVED.md](MOVED.md)), `local/oss-mac-setup` renamed to `local/oss-docker`, `tools/hol` runner and `smoke` workflow added. All checks green locally.

---

## CI

| Job | State | Notes |
|-----|-------|-------|
| `links` | ✅ | 172 markdown files, every relative link resolves (local, 2026-10-06) |
| `syntax` | ✅ | 204 shell, 69 python, 68 yaml files parse (local, 2026-10-06) |
| `site` | ✅ | `docs/` matches 21 releases + 40 labs = 61 lab pages, plus 19 redirects from [MOVED.md](MOVED.md) and `labs.json` (30 published); 88 files on 2026-10-06, local `build_site.py --check` |
| `hygiene` | ✅ | no shadowed tracked files, no `/Users/` paths, no TF state |
| `secrets` | ✅ | gitleaks, `.gitleaks.toml` rules |
| `smoke` | ✅ manual | every T0 lab via `tools/hol`, started by hand. Last full run: 20/20 T0 labs pass ([run 36706392271](https://github.com/litkhai/clickhouse-hols/actions/runs/36706392271) on `ed625f8`, 2026-09-30). The monthly schedule only runs the stub-expiry check (last 2026-10-01, pass). `local/releases/25.8` is T1, so not in it |

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

40 indexed labs plus 21 per-release labs. Counts are rows in the **English**
area tables of `README.md`:

| Area | Labs |
|------|-----:|
| `chc/` — ClickHouse Cloud integrations | 7 |
| `local/` — local environments | 8 |
| `usecase/` | 14 |
| `workload/` | 11 |
| `local/releases/` — per-release feature labs | 21 |

```bash
for a in chc local usecase workload; do
  printf '%-18s %s\n' "$a" "$(grep -c "^| \[$a/" README.md)"   # EN+KO, so halve
done
```

### Related repositories

Split out on 2026-09-27 with history; the last version here is at the
`pre-split-2026-10` tag. Old paths keep a stub README until 2027-03-31 and a
site redirect after that.

| Repository | Labs | From |
|------------|-----:|------|
| [clickhouse-managed-postgres-hols](https://github.com/litkhai/clickhouse-managed-postgres-hols) | 5 | `managed-postgres/*`, `local/pg-clickhouse-lab` |
| [clickstack-hyperdx-hols](https://github.com/litkhai/clickstack-hyperdx-hols) | 3 | `chc/tool/ch2otel`, `workshop/o11y-vector-ai`, `workshop/observability-waf` |
| [langfuse-hols](https://github.com/litkhai/langfuse-hols) | 2 | `usecase/langfuse-ee`, `usecase/langfuse-eval` |
| [clickhouse-cloud-aws-hols](https://github.com/litkhai/clickhouse-cloud-aws-hols) | 7 | `chc/{kafka,lake,s3}/*` — kept, not archived; each lab opens with a last-verified banner |
| [tpcds-scripts](https://github.com/litkhai/tpcds-scripts) | — | successor to `tpcds`, whose Altinity GPL-3.0 queries stay at the tag only |

`workshop/device-360` moved inside this repository to `usecase/device-360`.

## Known gaps

| Gap | Impact | Notes |
|-----|--------|-------|
| 12 of 39 indexed labs are single-language (2026-10-06, after #42; was 18) | Low | Predate the `[English](#english) \| [한국어](#한국어)` layout. The site shows the same body under both toggle positions, so nothing renders broken. Mostly `chc/` and older `local/` and `workload/` labs. |
| `chc/{api,tool}` have no `README.md` | None | They are category directories, not labs; their children are indexed individually. |
| `core.hooksPath` is per-clone | Medium | Not set automatically. An unconfigured clone commits without the secret / host-path / syntax guard and only finds out in CI.  |

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

Published history (`origin/main`, 256 commits) has **19 findings, none
exploitable**:

| Count | Where | Assessment |
|------:|-------|------------|
| 10 | `local/llm-mac-librechat/docker-compose*.yml` (d7bf236, 2025-12-07) | Real generated LibreChat app secrets (`JWT_SECRET`, `CREDS_KEY`, …), but they scope to a local single-user container, not a cloud resource. Path no longer exists. Regenerate if you ever reused them. |
| 3 | `terraform-glue-s3-chc-integration/CREDENTIAL_SOLUTIONS.md` (dfd8efc, 2025-11-16) | Ellipsis-truncated sample output of `ASIA`-prefixed STS **temporary** credentials, pasted to show their shape. Incomplete, and expired within hours of being written. The lab now lives in `clickhouse-cloud-aws-hols`, whose `.gitleaksignore` lists the same three. |
| 4 | `usecase/bug-bounty/05-generate-demo-data.sql` | Deliberately synthetic — MD5 of the word `password`, an `sk-proj-abcd1234…` stub, the canonical jwt.io sample token. The lab plants fake secrets on purpose. |
| 2 | `tpcds/00-set-{GUIDE,README}.md` | The password is the literal word *secret* in an example export line. Path removed from `main` in the split; still in history. |

## Open work

Tracked as issues — [all open](https://github.com/litkhai/clickhouse-hols/issues) · [needs a re-run](https://github.com/litkhai/clickhouse-hols/issues?q=is%3Aopen+label%3Are-verify):

- [Confirm Cloud credentials exposed before the 2026-09-07 rewrite were rotated](https://github.com/litkhai/clickhouse-hols/issues/4)
- [Re-run usecase/device-360 scripts](https://github.com/litkhai/clickhouse-hols/issues/10)
- [Delete the MOVED.md stub directories after 2027-03-31 (track J)](https://github.com/litkhai/clickhouse-hols/issues/12)

## Licensing exceptions

One tracked path is not MIT. It is documented in the root README and must stay
that way if the files move:

- `usecase/korea-geo/data/` — KOSTAT terms, no SPDX licence

`tpcds/queries/` (GPL-3.0, adapted from Altinity/tpc-ds) left `main` in the
2026-09-27 split and remains only at the `pre-split-2026-10` tag.

## AWS identifiers in public history (D8)

Reviewed 2026-09-27. `origin/main` history — not the current tree — holds real AWS
identifiers from the Terraform labs that moved to `clickhouse-cloud-aws-hols`:

- a saved `tfplan` with the full state inside (added `e0042aa`, moved `5f95b01`,
  untracked `a9ebaf1`), plus `backup-metadata-*/state.txt` and
  `backup-*/state.txt` dumps;
- in those and in several glue-lab docs: the AWS account ID, a ClickHouse Cloud
  service IAM role ARN, S3 bucket names, EC2 instance / security-group / VPC IDs,
  public IPs and hostnames.

No credentials: gitleaks finds none, and the one `password` key is Terraform's
`get_password_data = false`. gitleaks does not flag account IDs or ARNs, which is
why the secret-scan count above does not include any of this.

Decision: **this repository's history is not rewritten.** A rewrite would change
every SHA, including the `pre-split-2026-10` tag that `MOVED.md`, the 20 stub
READMEs and the new repositories point to, and the history has been public long
enough to have been copied. The resources behind the identifiers — the S3
buckets and the IAM role — no longer exist. `clickhouse-cloud-aws-hols`, public
for only a few hours, was rewritten instead: its state dumps and
`deployment-info.txt` files are gone and the identifiers are replaced with
documentation values. The same S3 bucket name and an EC2 address that were still
in the current tree (`usecase/device-360`) are now placeholders.

## Repository size

`.git` is 7.1 MB, 6.07 MiB packed. Largest tracked file is
`chc/cloud-to-oss-peerdb/REPORT.pdf` at 0.62 MB. No LFS, no archives — the
`hygiene` job rejects zip-shaped files because a saved `tfplan` embeds
Terraform state.

---

## 한국어 요약

- **CI 상태**: 6개 작업 모두 통과.
- **주의**: `check_links.py`는 `git ls-files`를 읽으므로 **추적되지 않은**
  새 실습은 아예 검사하지 않습니다. 녹색 결과를 믿기 전에 `git add` 하세요.
- **규모**: 색인된 실습 39개 + 릴리스별 실습 21개 = 사이트 페이지 60개, 그 외
  [MOVED.md](MOVED.md)의 redirect 19개. 2026-09-27 분리로 18개 실습이 새 저장소 4곳으로
  옮겨 갔고 `tpcds`는 은퇴(태그에만 남음). `device-360`은 `usecase/`로 이동.
- **알려진 격차**: 39개 중 18개가 단일 언어(구형 실습). 사이트는 양쪽 토글에
  같은 본문을 보여주므로 깨지지는 않음 — 백로그 항목.
- **주의**: `git config core.hooksPath .githooks`는 클론마다 직접 설정해야
  합니다.
- **시크릿 스캔**: 추적 중인 파일 0건. 공개 히스토리 19건은 모두 악용 불가.
- **AWS 식별자 (D8, 2026-09-27 검토)**: 공개 히스토리에 계정 ID, CHC 서비스 IAM role ARN,
  버킷 이름, EC2 ID·IP가 남아 있음 (`tfplan`, state 덤프, glue 문서). 자격증명은 없음.
  SHA와 `pre-split-2026-10` 태그를 지키기 위해 **이 저장소 히스토리는 재작성하지 않음**.
  해당 리소스는 이미 삭제됨. `clickhouse-cloud-aws-hols`는 공개 직후라 히스토리를
  재작성해 제거했고, 현재 트리의 `usecase/device-360` 버킷 이름과 EC2 주소는 placeholder로 바꿈.
- **할 일**: GitHub 이슈로 관리합니다 (위 "Open work").
