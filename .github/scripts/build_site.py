#!/usr/bin/env python3
"""Generate the GitHub Pages site from the repository's own content.

Produces:
  docs/index.html                      the catalogue, built from the two indexes
  docs/labs/<repo path>/index.html     one page per lab, from its README
  docs/assets/site.css, site.js        shared, so the pages stay small

Nothing here is hand-written, so the site cannot drift from the repository.
The indexes it reads are:
  local/releases/README.md   the per-release table (EN and KO)
  README.md                  the area tables (EN and KO)

Run from the repository root:
    python3 .github/scripts/build_site.py            # write the site
    python3 .github/scripts/build_site.py --check    # fail if it would change

Requires the `markdown` package (pip install markdown).
"""
import argparse
import html
import pathlib
import re
import shutil
import subprocess
import sys

try:
    import markdown
except ImportError:
    sys.exit("this script needs the markdown package:  pip install markdown")

REPO = "litkhai/clickhouse-hols"
TREE = f"https://github.com/{REPO}/tree/main"
BLOB = f"https://github.com/{REPO}/blob/main"

RELEASE_ROW = re.compile(
    r"^\|\s*\[([0-9.]+)\]\([0-9.]+/\)\s*\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(\S+)\s*\|\s*(.+?)\s*\|$"
)
AREA_ROW = re.compile(r"^\|\s*\[([^\]]+)\]\(([^)]+)\)\s*\|\s*(.+?)\s*\|$")
HEADING = re.compile(r"^### (.+)$")
LANG_NAV = re.compile(r"^\[English\]\(#english\)\s*\|\s*\[한국어\]\(#한국어\)\s*$", re.M)


# --------------------------------------------------------------------------- #
# reading the repository
# --------------------------------------------------------------------------- #

def md_inline(text, has_page=frozenset()):
    """Render the small subset of markdown that appears in the index tables.

    Links in those tables are repository-relative; point them at the lab page
    when one exists and at GitHub otherwise.
    """
    def link(m):
        label, href = m.group(1), m.group(2)
        if not href.startswith(("http://", "https://", "#", "mailto:")):
            clean = href.strip("/")
            href = ("labs/%s/index.html" % clean if clean in has_page
                    else "%s/%s" % (TREE, clean))
        return '<a href="%s">%s</a>' % (href, label)

    out = html.escape(text)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, out)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    return out


def split_languages(text):
    """Return the English and Korean halves of a bilingual document."""
    marker = "\n## 한국어"
    if marker not in text:
        return text, None
    en, ko = text.split(marker, 1)
    return en, "## 한국어" + ko


def parse_releases(path):
    """[(version, released, labs, verified, features_en, features_ko)] newest first."""
    en_half, ko_half = split_languages(path.read_text())

    def rows(chunk):
        found = {}
        for line in chunk.splitlines():
            m = RELEASE_ROW.match(line.strip())
            if m:
                found[m.group(1)] = m.groups()
        return found

    en, ko = rows(en_half), rows(ko_half)
    assert en and set(en) == set(ko), "release tables disagree between languages"
    ordered = sorted(en, key=lambda v: tuple(int(p) for p in v.split(".")), reverse=True)
    return [(v, en[v][1], int(en[v][2]), en[v][3], en[v][4], ko[v][4]) for v in ordered]


def parse_areas(path):
    """[(heading_en, heading_ko, [(label, repo_path, desc_en, desc_ko)])]."""
    en_half, ko_half = split_languages(path.read_text())

    def sections(chunk):
        out, heading, rows = [], None, []
        for line in chunk.splitlines():
            h = HEADING.match(line)
            if h:
                if heading and rows:
                    out.append((heading, rows))
                heading, rows = h.group(1).strip(), []
                continue
            m = AREA_ROW.match(line.strip())
            if m and heading and not m.group(1).startswith(("Lab", "실습", "Version", "버전")):
                rows.append((m.group(1), m.group(2), m.group(3)))
        if heading and rows:
            out.append((heading, rows))
        return out

    def is_catalogue(rows):
        return all("/" in href and not href.startswith("http") for _, href, _ in rows)

    en_sections = [s for s in sections(en_half) if is_catalogue(s[1])]
    ko_sections = [s for s in sections(ko_half) if is_catalogue(s[1])]
    assert len(en_sections) == len(ko_sections), (
        "area sections disagree: %d EN vs %d KO" % (len(en_sections), len(ko_sections)))

    merged = []
    for (h_en, rows_en), (h_ko, rows_ko) in zip(en_sections, ko_sections):
        ko_by_href = {href: desc for _, href, desc in rows_ko}
        merged.append((h_en, h_ko, [
            (label, href.strip("/"), desc_en, ko_by_href.get(href, desc_en))
            for label, href, desc_en in rows_en
        ]))
    return merged


# --------------------------------------------------------------------------- #
# page shell
# --------------------------------------------------------------------------- #

def bi(en, ko, tag="span"):
    return '<%s class="en">%s</%s><%s class="ko">%s</%s>' % (tag, en, tag, tag, ko, tag)


FAVICON = ("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'>"
           "<rect width='64' height='64' rx='8' fill='%23faff69'/><g fill='%23000'>"
           "<rect x='10' y='12' width='8' height='40'/><rect x='22' y='12' width='8' height='40'/>"
           "<rect x='34' y='12' width='8' height='40'/><rect x='46' y='28' width='8' height='8'/>"
           "</g></svg>")


def shell(title, body, depth, description):
    """Wrap page content in the shared chrome. `depth` = directories below docs/."""
    up = "../" * depth
    footer = bi(
        "Generated from the repository by <code>.github/scripts/build_site.py</code>. "
        'MIT licensed. <a href="https://github.com/%s">Source on GitHub</a>.' % REPO,
        "저장소 내용에서 <code>.github/scripts/build_site.py</code>로 생성됩니다. "
        'MIT 라이선스. <a href="https://github.com/%s">GitHub 저장소</a>.' % REPO)
    return """<!DOCTYPE html>
<html lang="en" data-theme="auto">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%(title)s</title>
<meta name="description" content="%(desc)s">
<meta name="color-scheme" content="light dark">
<link rel="icon" href="%(favicon)s">
<link rel="stylesheet" href="%(up)sassets/site.css">
<script src="%(up)sassets/site.js" defer></script>
</head>
<body>
<header>
  <div class="wrap bar">
    <a class="brand" href="%(up)sindex.html">
      <span class="mark" aria-hidden="true"></span>ClickHouse HOLs
    </a>
    <div class="spacer"></div>
    <div class="switch" role="group" aria-label="Language">
      <button type="button" data-set-lang="ko" aria-pressed="false">KO</button>
      <button type="button" data-set-lang="en" aria-pressed="true">EN</button>
    </div>
    <div class="switch" role="group" aria-label="Theme">
      <button type="button" data-set-theme="light" title="Light" aria-pressed="false">☀</button>
      <button type="button" data-set-theme="auto" title="System" aria-pressed="true">◐</button>
      <button type="button" data-set-theme="dark" title="Dark" aria-pressed="false">☾</button>
    </div>
    <a class="ghlink" href="https://github.com/%(repo)s">GitHub</a>
  </div>
</header>

%(body)s

<footer class="wrap">
  <p>%(footer)s</p>
</footer>
</body>
</html>
""" % {"title": html.escape(title), "desc": html.escape(description), "favicon": FAVICON,
       "up": up, "repo": REPO, "body": body, "footer": footer}


# --------------------------------------------------------------------------- #
# lab pages
# --------------------------------------------------------------------------- #

def rewrite_links(html_text, repo_path):
    """Point the README's relative links at GitHub, since the site has no files."""
    def sub(m):
        href = m.group(1)
        if href.startswith(("http://", "https://", "#", "mailto:")):
            return m.group(0)
        target = pathlib.PurePosixPath(repo_path).joinpath(href.split("#")[0])
        parts = []
        for part in target.parts:
            if part == "..":
                if parts:
                    parts.pop()
            elif part != ".":
                parts.append(part)
        base = TREE if href.endswith("/") else BLOB
        return 'href="%s/%s"' % (base, "/".join(parts))
    return re.sub(r'href="([^"]+)"', sub, html_text)


def render_markdown(text, repo_path):
    md = markdown.Markdown(extensions=["tables", "fenced_code", "sane_lists", "attr_list"])
    return rewrite_links(md.convert(text), repo_path)


def lab_page(root, repo_path, label, verified):
    """Render one lab README, or None when the lab has no README."""
    readme = root / repo_path / "README.md"
    if not readme.is_file():
        return None
    raw = readme.read_text()
    raw = LANG_NAV.sub("", raw)                       # the site has its own switch
    en_raw, ko_raw = split_languages(raw)
    body_en = render_markdown(re.sub(r"^## English\s*$", "", en_raw, flags=re.M), repo_path)
    body_ko = (render_markdown(re.sub(r"^## 한국어\s*$", "", ko_raw, flags=re.M), repo_path)
               if ko_raw else body_en)

    m = re.search(r"^#\s+(.+)$", raw, re.M)
    title = m.group(1).strip() if m else label

    badge = ""
    if verified:
        badge = ('<span class="badge ok">%s %s</span>'
                 % (bi("verified on", "검증"), html.escape(verified)))

    depth = len(pathlib.PurePosixPath(repo_path).parts) + 1   # + labs/
    body = """<main class="wrap doc">
  <nav class="crumbs">
    <a href="%(up)sindex.html">%(all)s</a>
    <span aria-hidden="true">/</span><code>%(path)s</code>
    %(badge)s
  </nav>
  <div class="readme en">%(en)s</div>
  <div class="readme ko">%(ko)s</div>
  <p class="src"><a href="%(tree)s/%(path)s">%(open)s</a></p>
</main>""" % {"up": "../" * depth, "all": bi("All labs", "전체 실습"),
              "path": html.escape(repo_path), "badge": badge,
              "en": body_en, "ko": body_ko, "tree": TREE,
              "open": bi("Open this lab on GitHub →", "GitHub에서 이 실습 열기 →")}
    return shell("%s · ClickHouse HOLs" % title, body, depth,
                 "%s — hands-on ClickHouse lab." % title)


# --------------------------------------------------------------------------- #
# index page
# --------------------------------------------------------------------------- #

def index_page(releases, areas, has_page):
    newest, oldest = releases[0][0], releases[-1][0]

    def href(repo_path):
        return ("labs/%s/index.html" % repo_path if repo_path in has_page
                else "%s/%s" % (TREE, repo_path))

    rows = []
    for version, released, labs, ver, feat_en, feat_ko in releases:
        badge = ('<span class="badge ok">%s</span>' % html.escape(ver) if ver != "—"
                 else '<span class="badge unknown">%s</span>' % bi("not run", "미실행"))
        rows.append("""        <tr>
          <td><a class="ver" href="%s">%s</a></td>
          <td class="num">%s</td>
          <td class="num">%d</td>
          <td>%s</td>
          <td>%s</td>
        </tr>""" % (href("local/releases/%s" % version), version, released, labs,
                    badge, bi(md_inline(feat_en, has_page), md_inline(feat_ko, has_page))))

    blocks = []
    for h_en, h_ko, items in areas:
        cards = []
        for label, repo_path, desc_en, desc_ko in items:
            cards.append("""          <li>
            <a href="%s"><code>%s</code></a>
            <p>%s</p>
          </li>""" % (href(repo_path), html.escape(label),
                      bi(md_inline(desc_en, has_page), md_inline(desc_ko, has_page))))
        blocks.append("""      <section class="area">
        <h3>%s</h3>
        <ul class="cards">
%s
        </ul>
      </section>""" % (bi(html.escape(h_en), html.escape(h_ko)), chr(10).join(cards)))

    body = """<main class="wrap">
  <div class="hero">
    <h1>%(h1)s</h1>
    <p>%(lede)s</p>
    <div class="stats">
      <div class="stat"><b>%(n_rel)d</b><span>%(s1)s</span></div>
      <div class="stat"><b>%(oldest)s → %(newest)s</b><span>%(s2)s</span></div>
      <div class="stat"><b>%(n_sql)d</b><span>%(s3)s</span></div>
    </div>
  </div>

  <h2>%(h_rel)s</h2>
  <p class="lede">%(lede_rel)s</p>
  <div class="scroll">
  <table>
    <thead>
      <tr><th>%(c1)s</th><th>%(c2)s</th><th>%(c3)s</th><th>%(c4)s</th><th>%(c5)s</th></tr>
    </thead>
    <tbody>
%(rows)s
    </tbody>
  </table>
  </div>
  <p class="note">%(note)s</p>

  <h2>%(h_other)s</h2>
  <p class="lede">%(lede_other)s</p>
%(blocks)s

  <h2>%(h_start)s</h2>
  <pre><code>git clone https://github.com/%(repo)s.git
cd clickhouse-hols/local/releases/%(newest)s
./00-setup.sh</code></pre>
  <p class="lede">%(lede_start)s</p>
</main>""" % {
        "h1": bi("Hands-on ClickHouse labs", "ClickHouse 실습 랩"),
        "lede": bi(
            "One directory per ClickHouse release, plus Cloud integrations, workload experiments "
            "and workshops. Every lab brings up what it needs, generates its own data, and can be "
            "run on its own.",
            "ClickHouse 릴리스마다 디렉토리 하나, 여기에 Cloud 연동·워크로드 실험·워크숍을 "
            "더했습니다. 각 랩은 필요한 환경을 스스로 띄우고 테스트 데이터를 생성하므로 독립적으로 "
            "실행됩니다."),
        "n_rel": len(releases), "oldest": oldest, "newest": newest,
        "n_sql": sum(r[2] for r in releases),
        "s1": bi("release labs", "릴리스 랩"),
        "s2": bi("versions covered", "다루는 버전"),
        "s3": bi("runnable SQL labs", "실행 가능한 SQL 랩"),
        "h_rel": bi("Release labs", "릴리스 랩"),
        "lede_rel": bi(
            "Each directory holds runnable SQL for that version's new features, with a bilingual guide.",
            "각 디렉토리에는 해당 버전 신기능의 실행 가능한 SQL과 영/한 가이드가 들어 있습니다."),
        "c1": bi("Version", "버전"), "c2": bi("Released", "출시일"),
        "c3": bi("Labs", "랩"), "c4": bi("Verified", "검증"),
        "c5": bi("Features covered", "다루는 기능"),
        "rows": chr(10).join(rows),
        "note": bi(
            "<strong>Verified</strong> names the exact server build every lab in that directory was "
            "run against, end to end, with zero exceptions. Getting all nineteen there took fixing "
            "eleven of them: SQL referencing functions and settings that do not exist, arguments in "
            "the wrong order, aliases shadowing the column they aggregated. Re-run any of them with "
            "<code>.github/scripts/verify_release_lab.sh &lt;version&gt;</code>.",
            "<strong>검증</strong>은 해당 디렉토리의 모든 랩을 예외 0으로 끝까지 실행해 본 정확한 "
            "서버 빌드입니다. 19개 전부를 그 상태로 만드는 데 11개를 고쳐야 했습니다 — 존재하지 않는 "
            "함수·설정 참조, 뒤바뀐 인자 순서, 집계 대상 컬럼을 가리는 별칭 같은 문제였습니다. 직접 "
            "재현하려면 <code>.github/scripts/verify_release_lab.sh &lt;버전&gt;</code> 을 "
            "실행하세요."),
        "h_other": bi("Everything else", "그 외 실습"),
        "lede_other": bi(
            "Cloud integrations, end-to-end use cases, focused workload experiments and "
            "multi-service workshops.",
            "Cloud 연동, 엔드투엔드 활용 사례, 집중 워크로드 실험, 다중 서비스 워크숍입니다."),
        "blocks": chr(10).join(blocks),
        "h_start": bi("Getting started", "시작하기"),
        "repo": REPO,
        "lede_start": bi(
            "Then run the numbered scripts in order. Every lab documents its own setup and "
            "teardown; nothing is global.",
            "이후 번호 순서대로 스크립트를 실행하세요. 각 랩이 자체 설정과 정리 방법을 "
            "문서화하며, 전역 설정은 없습니다."),
    }
    return shell("ClickHouse Hands-On Labs", body, 0,
                 "Hands-on ClickHouse labs: %d per-release feature labs (%s to %s), Cloud "
                 "integrations, workload benchmarks and workshops." % (len(releases), oldest, newest))


# --------------------------------------------------------------------------- #
# assets
# --------------------------------------------------------------------------- #

CSS = """/* Generated by .github/scripts/build_site.py — do not edit by hand. */

/* ClickHouse palette: the signature yellow on near-black, or on white. */
:root {
  --yellow: #faff69;
  --bg: #ffffff; --surface: #f7f7f5; --fg: #16161a; --muted: #5f6169;
  --line: #e3e3df; --accent: var(--yellow); --accent-fg: #16161a;
  --accent-line: #d8dd3f;
  --ok-bg: #eef7e6; --ok-fg: #2f6b1f; --unk-bg: #f0f0ee; --unk-fg: #6b6d75;
  --code-bg: #f2f2ef;
}
:root[data-theme="dark"] {
  --bg: #16161a; --surface: #1f1f24; --fg: #ececf0; --muted: #9a9ca6;
  --line: #2e2e35; --accent-line: #5c5f22;
  --ok-bg: #24301a; --ok-fg: #b6e26a; --unk-bg: #26262c; --unk-fg: #8b8d97;
  --code-bg: #202027;
}
@media (prefers-color-scheme: dark) {
  :root[data-theme="auto"] {
    --bg: #16161a; --surface: #1f1f24; --fg: #ececf0; --muted: #9a9ca6;
    --line: #2e2e35; --accent-line: #5c5f22;
    --ok-bg: #24301a; --ok-fg: #b6e26a; --unk-bg: #26262c; --unk-fg: #8b8d97;
    --code-bg: #202027;
  }
}

* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0; background: var(--bg); color: var(--fg);
  font: 16px/1.65 ui-sans-serif, -apple-system, "Segoe UI", "Apple SD Gothic Neo",
        "Noto Sans KR", Roboto, sans-serif;
  -webkit-font-smoothing: antialiased;
}
code, pre { font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace; }
code { font-size: .89em; background: var(--code-bg); padding: .12em .38em; border-radius: 4px; }
pre { background: var(--surface); border: 1px solid var(--line); border-radius: 10px;
      padding: 14px 16px; overflow-x: auto; font-size: 13.5px; line-height: 1.55; }
pre code { background: none; padding: 0; }
a { color: inherit; text-underline-offset: 2px; }
.wrap { max-width: 1080px; margin: 0 auto; padding: 0 20px; }

header { border-bottom: 1px solid var(--line); position: sticky; top: 0;
         background: var(--bg); z-index: 20; }
.bar { display: flex; align-items: center; gap: 10px; padding: 12px 0; }
.brand { display: inline-flex; align-items: center; gap: 9px; font-weight: 700;
         text-decoration: none; letter-spacing: -.01em; white-space: nowrap; }
.mark { width: 15px; height: 15px; border-radius: 3px; background: var(--yellow);
        box-shadow: inset 0 0 0 3px var(--bg), 0 0 0 1px var(--accent-line); }
.bar .spacer { flex: 1; }
.switch { display: inline-flex; border: 1px solid var(--line); border-radius: 999px;
          overflow: hidden; }
.switch button { font: inherit; font-size: 13px; font-weight: 600; line-height: 1;
                 padding: 6px 11px; border: 0; background: transparent;
                 color: var(--muted); cursor: pointer; }
.switch button:hover { color: var(--fg); }
.switch button[aria-pressed="true"] { background: var(--accent); color: var(--accent-fg); }
.ghlink { font-size: 14px; color: var(--muted); text-decoration: none; }
.ghlink:hover { color: var(--fg); }

.hero { padding: 60px 0 34px; }
.hero h1 { font-size: clamp(28px, 5vw, 44px); line-height: 1.12; margin: 0 0 14px;
           letter-spacing: -.025em; }
.hero p { color: var(--muted); font-size: 17px; margin: 0 0 28px; max-width: 62ch; }
.stats { display: flex; flex-wrap: wrap; gap: 12px; }
.stat { background: var(--surface); border: 1px solid var(--line); border-radius: 12px;
        padding: 13px 18px; }
.stat b { display: block; font-size: 24px; line-height: 1.2; letter-spacing: -.02em; }
.stat span { font-size: 13px; color: var(--muted); }

h2 { font-size: 22px; margin: 52px 0 6px; letter-spacing: -.015em; }
.lede { color: var(--muted); margin: 0 0 18px; font-size: 15px; max-width: 76ch; }

table { width: 100%; border-collapse: collapse; font-size: 14.5px; }
th, td { text-align: left; padding: 9px 10px; border-bottom: 1px solid var(--line);
         vertical-align: top; }
th { font-size: 12px; text-transform: uppercase; letter-spacing: .06em;
     color: var(--muted); font-weight: 600; }
tbody tr:hover { background: var(--surface); }
td.num { white-space: nowrap; color: var(--muted); font-variant-numeric: tabular-nums; }
a.ver { font-weight: 700; text-decoration: none; border-bottom: 2px solid var(--accent); }
.badge { display: inline-block; font-size: 12px; font-weight: 600; padding: 2px 9px;
         border-radius: 999px; white-space: nowrap; }
.badge.ok { background: var(--ok-bg); color: var(--ok-fg); }
.badge.unknown { background: var(--unk-bg); color: var(--unk-fg); }

.note { border-left: 3px solid var(--accent); background: var(--surface);
        padding: 14px 18px; border-radius: 0 10px 10px 0; margin: 18px 0 0;
        font-size: 14.5px; }

.area { margin-top: 34px; }
.area h3 { font-size: 17px; margin: 0 0 12px; }
ul.cards { list-style: none; margin: 0; padding: 0; display: grid; gap: 10px;
           grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); }
ul.cards li { background: var(--surface); border: 1px solid var(--line);
              border-radius: 12px; padding: 12px 14px; transition: border-color .15s; }
ul.cards li:hover { border-color: var(--accent-line); }
ul.cards a { text-decoration: none; }
ul.cards a code { font-weight: 600; background: none; padding: 0; }
ul.cards p { margin: 6px 0 0; font-size: 13.5px; color: var(--muted); }

/* lab pages */
.doc { padding-bottom: 8px; }
.crumbs { display: flex; align-items: center; gap: 10px; flex-wrap: wrap;
          padding: 22px 0 6px; font-size: 13.5px; color: var(--muted); }
.crumbs a { text-decoration: none; border-bottom: 1px solid var(--line); }
.crumbs a:hover { border-color: var(--accent); }
.readme { max-width: 82ch; }
.readme h1 { font-size: clamp(25px, 4vw, 34px); letter-spacing: -.02em; margin: 18px 0 8px; }
.readme h2 { font-size: 21px; margin: 40px 0 8px; padding-bottom: 6px;
             border-bottom: 1px solid var(--line); }
.readme h3 { font-size: 17px; margin: 30px 0 6px; }
.readme h4 { font-size: 15.5px; margin: 24px 0 4px; }
.readme table { margin: 12px 0; }
.readme ul, .readme ol { padding-left: 1.3em; }
.readme li { margin: 3px 0; }
.readme hr { border: 0; border-top: 1px solid var(--line); margin: 34px 0; }
.readme blockquote { margin: 12px 0; padding: 2px 16px; border-left: 3px solid var(--accent);
                     color: var(--muted); }
.src { margin: 34px 0 0; font-size: 14.5px; }
.src a { text-decoration: none; border-bottom: 2px solid var(--accent); font-weight: 600; }

footer { margin-top: 64px; border-top: 1px solid var(--line); padding: 24px 0 48px;
         color: var(--muted); font-size: 14px; }

html[lang="en"] .ko, html[lang="ko"] .en { display: none; }
.scroll { overflow-x: auto; }

@media (max-width: 620px) {
  .bar { flex-wrap: wrap; gap: 8px; }
  .ghlink { order: 3; }
  .hero { padding: 36px 0 24px; }
}
"""

JS = """/* Generated by .github/scripts/build_site.py — do not edit by hand. */
(function () {
  var LANG = 'chhols-lang', THEME = 'chhols-theme';

  function read(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }
  function write(key, value) { try { localStorage.setItem(key, value); } catch (e) {} }

  function applyLang(lang) {
    document.documentElement.lang = lang;
    document.querySelectorAll('[data-set-lang]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.setLang === lang));
    });
  }

  function applyTheme(theme) {
    document.documentElement.dataset.theme = theme;
    document.querySelectorAll('[data-set-theme]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.setTheme === theme));
    });
  }

  var browserKo = (navigator.language || 'en').toLowerCase().indexOf('ko') === 0;
  applyLang(read(LANG) || (browserKo ? 'ko' : 'en'));
  applyTheme(read(THEME) || 'auto');

  document.addEventListener('click', function (e) {
    var el = e.target.closest('[data-set-lang], [data-set-theme]');
    if (!el) return;
    if (el.dataset.setLang) { applyLang(el.dataset.setLang); write(LANG, el.dataset.setLang); }
    else { applyTheme(el.dataset.setTheme); write(THEME, el.dataset.setTheme); }
  });
})();
"""


# --------------------------------------------------------------------------- #

def build(root):
    releases = parse_releases(root / "local" / "releases" / "README.md")
    areas = parse_areas(root / "README.md")

    wanted = [("local/releases/%s" % v, v, (b if b != "—" else None))
              for v, _, _, b, _, _ in releases]
    wanted += [(p, label, None) for _, _, items in areas for label, p, _, _ in items]

    files, has_page = {}, set()
    for repo_path, label, verified in wanted:
        page = lab_page(root, repo_path, label, verified)
        if page is not None:
            files["labs/%s/index.html" % repo_path] = page
            has_page.add(repo_path)

    files["index.html"] = index_page(releases, areas, has_page)
    files["assets/site.css"] = CSS
    files["assets/site.js"] = JS
    files[".nojekyll"] = ""      # Jekyll would otherwise skip some paths
    return files, len(releases), sum(len(a[2]) for a in areas), len(has_page)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="exit non-zero if the committed site is out of date")
    args = ap.parse_args()

    root = pathlib.Path(subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True).stdout.strip())
    docs = root / "docs"

    files, n_rel, n_area, n_pages = build(root)
    summary = ("%d releases, %d other labs, %d lab pages, %d files"
               % (n_rel, n_area, n_pages, len(files)))

    if args.check:
        on_disk = {str(p.relative_to(docs)) for p in docs.rglob("*") if p.is_file()} \
            if docs.exists() else set()
        if on_disk != set(files):
            print("docs/ holds a different set of files than the build produces")
            for label, diff in (("on disk only", on_disk - set(files)),
                                ("missing", set(files) - on_disk)):
                if diff:
                    print("  %s: %s" % (label, ", ".join(sorted(diff)[:5])))
            print("run: python3 .github/scripts/build_site.py")
            return 1
        for rel, content in files.items():
            if (docs / rel).read_text() != content:
                print("docs/%s is out of date; run:" % rel)
                print("    python3 .github/scripts/build_site.py")
                return 1
        print("OK: docs/ matches %s" % summary)
        return 0

    if docs.exists():
        shutil.rmtree(docs)
    for rel, content in files.items():
        out = docs / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(content)
    print("wrote docs/: %s" % summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
