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

---

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
