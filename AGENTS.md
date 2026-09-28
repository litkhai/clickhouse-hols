# AGENTS.md

Instructions for coding agents working in this repository.

The root [`README.md`](README.md) already documents lab conventions, credential
handling and the CI jobs — read those sections rather than re-deriving them.
This file covers only what the README does not say: the couplings that are easy
to miss and that have already broken `main`.

---

## The one thing to know

**The published site is generated *from* the root README's area tables.**

`.github/scripts/build_site.py` discovers labs by regex-matching the area-table
rows in `README.md` — a linked lab path in the first cell, a one-line summary in
the second, as in [usecase/customer360](usecase/customer360/). It does not walk
the filesystem. The consequences:

- A lab directory with a perfectly good `README.md` but **no row in the root
  README gets no site page at all** — silently. It is not a broken link, so the
  `links` job stays green; the lab simply does not exist as far as the site is
  concerned.
- Adding a row changes the prev/next pager on the two *neighbouring* lab pages,
  so regenerating touches more files than the one you added. That is expected.

## Adding or renaming a lab

Four places, every time. Missing any one of them fails CI or silently drops the
lab:

1. The lab directory itself, with a bilingual `README.md`.
2. A row in the **English** area table in `README.md`.
3. A row in the **Korean** area table in `README.md` — the tables are separate
   and both are parsed.
4. Regenerate and **commit** the site:
   ```bash
   pip install --quiet markdown
   python3 .github/scripts/build_site.py
   ```
   The `site` CI job runs `build_site.py --check` and fails if the committed
   `docs/` differs from what the repository would generate. Generated output is
   tracked on purpose — do not gitignore it.

## Do not link to a lab that does not exist yet

Cross-references between labs are relative links, and the `links` job resolves
every one of them against the filesystem. A forward-looking pointer to a lab you
intend to write later breaks the build — that is exactly how `main` went red on
2026-09-20, with `usecase/timeseries-promql-oss` linking to a sibling
`timeseries-promql-cloud` directory that was never created. If the counterpart
does not exist, describe the situation in prose instead of linking.

The check is line-based and does **not** skip fenced code blocks, so an
illustrative link inside an example still has to resolve. Write example paths as
plain code spans rather than as markdown links.

## Bilingual parity

New labs carry both languages in one `README.md`, English first:

```markdown
[English](#english) | [한국어](#한국어)

## English
...
---
## 한국어
...
```

`build_site.py` splits on those headings to build the language toggle, and the
root README tables are duplicated per language. When you edit substance in one
language, edit the other — a claim that is true in the English half and stale in
the Korean half is the most common drift here.

Roughly half the indexed labs predate this layout and are single-language (see
[`STATUS.md`](STATUS.md)). The site degrades gracefully — `build_site.py` shows
the same body under both toggle positions when a lab has no `## 한국어` half — so
these are a backlog item, not a breakage. Follow the convention for new work,
and translate an older lab deliberately rather than as a drive-by edit.

## Before you commit

Enable the guard once per clone, then run what CI runs:

```bash
brew install gitleaks
git config core.hooksPath .githooks      # not set by default in a fresh clone

python3 .github/scripts/check_links.py
./.github/scripts/check_syntax.sh
python3 .github/scripts/build_site.py --check
```

The `hygiene` job additionally rejects:

- any tracked file that matches a `.gitignore` rule (ignore rules do not apply
  retroactively to tracked files, so the check catches inert rules),
- `/Users/...` host paths in non-markdown files — derive paths from
  `BASH_SOURCE` or `__file__`,
- committed Terraform state or any zip-shaped file (a saved `tfplan` embeds the
  whole state, including real account IDs and role ARNs).

## Verification claims

Lab READMEs state the ClickHouse version a lab was verified against
(e.g. *"Verified on ClickHouse 26.8.8"*). Only write or update that line when
the scripts were actually executed end to end against that version. If you
change a lab without running it, leave the existing version claim alone and say
what was not re-run.

## Running labs with `tools/hol`

A lab opts in to the runner with a flat `lab.yaml` next to its README
(`target`, `tier`, `clickhouse`, `services`, `verified_on`). Only the 21
release labs have one so far, all tier **T0**: SQL only, one ClickHouse
server, self-generated data.

```bash
tools/hol list --tier T0
tools/hol run local/releases/26.9     # fresh container, every NN-*.sql in order
```

It needs only Python 3 and Docker, so it is the same on macOS, Linux and
Windows. The `smoke` workflow runs every T0 lab daily. `verified_on` still
follows the Verification claims rule below — a green smoke run on a newer image
is not a reason to change it.

## Moving a lab out of this repository

Labs have been split into other repositories once (2026-09-27, see
[`MOVED.md`](MOVED.md)). To move another one, keep every old URL working:

1. Carry the history over from a **fresh clone of `origin`** with
   `git filter-repo`, never from a local clone — local clones may hold
   pre-rewrite branches with real credentials.
2. Delete the lab here and add a row to `MOVED.md`: old path, then an `http`
   URL (another repository) or a relative link (a move inside this repository).
3. Put a bilingual stub `README.md` at the old path pointing to the new
   location and to the last version at a tag.
4. Remove its rows from **both** area tables in `README.md`, and add the new
   repository to **Related repositories** in both languages. Those rows are
   `http`-only, so `build_site.py` does not treat that section as a lab table.
5. Regenerate `docs/`. `build_site.py` writes a `noindex` redirect page at
   `docs/labs/<old path>/` for every `MOVED.md` row that had a page, and fails
   if an old path still has a lab page or a relative target has none.
6. Move any `.gitleaks.toml` allowlist entry or `.gitignore` line for the lab
   to the new repository and delete it here.

Related repositories, all split from here with history:

| Repository | Holds |
|------------|-------|
| [clickhouse-managed-postgres-hols](https://github.com/litkhai/clickhouse-managed-postgres-hols) | Managed Postgres labs, `pg_clickhouse` |
| [clickstack-hyperdx-hols](https://github.com/litkhai/clickstack-hyperdx-hols) | ClickStack / HyperDX / OpenTelemetry labs and workshops |
| [langfuse-hols](https://github.com/litkhai/langfuse-hols) | Langfuse on ClickHouse |
| [clickhouse-cloud-aws-hols](https://github.com/litkhai/clickhouse-cloud-aws-hols) | Terraform on AWS for ClickHouse Cloud |

## Tracking work

Planned work, re-verification and follow-ups are **GitHub issues**; every change
lands through a **pull request** that references its issue (`Closes #N`).
`STATUS.md` is a snapshot of the current state and links to the open issues
instead of keeping its own to-do list. When you find something to do that you
are not doing now, open an issue rather than writing it into a README or
`STATUS.md`. Labels: `re-verify` (changed but not re-run), `enhancement`,
`docs`, `ops`, `security`.

---

## Model roles

Work in this repository is split across Claude models:

| Role | Model | Does |
|------|-------|------|
| Lead | **Opus** | Plans and designs the work, writes and updates documentation (READMEs, `AGENTS.md`, `STATUS.md`, issues, PR descriptions), splits the work into tasks and reviews what comes back |
| Implementer | **Sonnet** | Writes the code, scripts and SQL for a task the lead hands over, runs the checks, opens the PR |
| Status checker | **Haiku** | Read-only checks: CI and `smoke` results, open issues and PRs, link and syntax checks, what changed since the last look |

The lead gives the implementer one issue at a time with the design and the files
to touch; the implementer does not change the design or the docs' claims on its
own. Verification claims still follow the rule above: only a real end-to-end run
updates them, whichever model ran it.

## 한국어 요약

- **사이트는 루트 `README.md`의 표에서 생성됩니다.** 표에 행이 없는 실습은 조용히
  사이트에서 누락됩니다 — 링크 오류가 아니라 CI가 잡지 못합니다.
- 실습 추가 시 네 곳을 모두 고칩니다: 실습 디렉터리, 루트 README **영문** 표,
  루트 README **한글** 표, 그리고 `python3 .github/scripts/build_site.py`로
  재생성한 `docs/`를 **커밋**.
- 아직 없는 실습으로 상대 링크를 걸지 마세요. `links` 작업이 실패합니다.
- 한쪽 언어의 내용을 고치면 반대쪽도 같이 고칩니다.
- 클론마다 한 번: `git config core.hooksPath .githooks`.
- 검증 버전 문구는 실제로 끝까지 실행했을 때만 갱신합니다.
- `tools/hol run <lab>`: `lab.yaml`이 있는 실습(현재 릴리스 21개, T0)을 새 컨테이너에서 실행.
  `smoke` 워크플로가 매일 전부 돌립니다.
- 실습을 다른 저장소로 옮길 때는 옛 URL이 계속 동작해야 합니다. `origin`을 새로
  clone해서 `git filter-repo`로 히스토리를 옮기고, 여기서는 실습을 지운 뒤
  `MOVED.md` 행, 옛 경로의 영/한 stub README, 루트 README 두 언어의 표 수정과
  **관련 저장소** 행 추가, `docs/` 재생성(redirect 자동 생성)을 함께 합니다.
- 해야 할 일은 **GitHub 이슈**로, 변경은 이슈를 참조하는 **PR**(`Closes #N`)로 관리합니다.
  `STATUS.md`에는 할 일 목록을 따로 두지 않고 열린 이슈를 링크합니다.
- 모델 역할: **Opus**는 리드(설계, 문서, 이슈와 PR 설명, 작업 분배, 리뷰), **Sonnet**은
  구현(코드·스크립트·SQL, 검사, PR), **Haiku**는 현황 체크(CI·smoke 결과, 이슈·PR 상태, 읽기 전용).
