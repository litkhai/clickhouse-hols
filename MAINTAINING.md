# MAINTAINING.md

How this repository holds together: the couplings between labs, the root README, the generated site
and CI that are easy to miss and have already broken `main`. Agents read this before adding, renaming,
moving or linking a lab, and before committing. Lab conventions and credentials: root [`README.md`](README.md).

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

The `hygiene` job enforces the shared Secrets rules below.

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
Windows. The `smoke` workflow runs every T0 lab when started by hand. `verified_on` still
follows the shared Verification claims rule below — a green smoke run on a newer image
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
