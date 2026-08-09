#!/usr/bin/env python3
"""Generate docs/index.html for GitHub Pages from the repository's own indexes.

The page is a rendering of two files, so it cannot drift from them:
  - local/releases/README.md : the per-release lab table (EN and KO)
  - README.md                : the area tables (EN and KO)

Run from the repository root:
    python3 .github/scripts/build_site.py            # write docs/index.html
    python3 .github/scripts/build_site.py --check    # fail if it would change
"""
import argparse
import html
import pathlib
import re
import subprocess
import sys

REPO = "litkhai/clickhouse-hols"
TREE = f"https://github.com/{REPO}/tree/main"

RELEASE_ROW = re.compile(
    r"^\|\s*\[([0-9.]+)\]\([0-9.]+/\)\s*\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(\S+)\s*\|\s*(.+?)\s*\|$"
)
AREA_ROW = re.compile(r"^\|\s*\[([^\]]+)\]\(([^)]+)\)\s*\|\s*(.+?)\s*\|$")
HEADING = re.compile(r"^### (.+)$")


def md_inline(text: str) -> str:
    """Render the small subset of markdown that appears in these tables."""
    out = html.escape(text)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    return out


def split_languages(text: str) -> tuple[str, str]:
    """Return the English and Korean halves of a bilingual README."""
    marker = "\n## 한국어"
    assert marker in text, "expected a Korean section"
    en, ko = text.split(marker, 1)
    return en, ko


def parse_releases(path: pathlib.Path):
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
    return [
        (v, en[v][1], int(en[v][2]), en[v][3], en[v][4], ko[v][4])
        for v in ordered
    ]


def parse_areas(path: pathlib.Path):
    """[(heading_en, heading_ko, [(label, href, desc_en, desc_ko)])] in document order."""
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

    en_sections = sections(en_half)
    ko_sections = sections(ko_half)

    # keep only the lab catalogues: those whose rows link into a repository path
    def is_catalogue(rows):
        return all("/" in href and not href.startswith("http") for _, href, _ in rows)

    en_sections = [s for s in en_sections if is_catalogue(s[1])]
    ko_sections = [s for s in ko_sections if is_catalogue(s[1])]
    assert len(en_sections) == len(ko_sections), (
        f"area sections disagree: {len(en_sections)} EN vs {len(ko_sections)} KO")

    merged = []
    for (h_en, rows_en), (h_ko, rows_ko) in zip(en_sections, ko_sections):
        by_href_ko = {href: desc for _, href, desc in rows_ko}
        items = []
        for label, href, desc_en in rows_en:
            items.append((label, href, desc_en, by_href_ko.get(href, desc_en)))
        merged.append((h_en, h_ko, items))
    return merged


def bi(en: str, ko: str, tag: str = "span") -> str:
    """Both languages, one shown at a time by CSS."""
    return f'<{tag} class="en">{en}</{tag}><{tag} class="ko">{ko}</{tag}>'


def render(releases, areas) -> str:
    verified = [r for r in releases if r[3] != "—"]
    src = f'<a href="https://github.com/{REPO}">'
    footer = bi(
        "Generated from the repository's own indexes by "
        "<code>.github/scripts/build_site.py</code>. MIT licensed. "
        + src + "Source on GitHub</a>.",
        "저장소의 인덱스 문서에서 <code>.github/scripts/build_site.py</code>로 "
        "생성됩니다. MIT 라이선스. " + src + "GitHub 저장소</a>.",
    )
    newest, oldest = releases[0][0], releases[-1][0]

    release_rows = []
    for version, released, labs, ver, feat_en, feat_ko in releases:
        badge = (
            f'<span class="badge ok" title="verified on {html.escape(ver)}">{html.escape(ver)}</span>'
            if ver != "—"
            else f'<span class="badge unknown">{bi("not run", "미실행")}</span>'
        )
        release_rows.append(f"""        <tr>
          <td><a class="ver" href="{TREE}/local/releases/{version}">{version}</a></td>
          <td class="num">{released}</td>
          <td class="num">{labs}</td>
          <td>{badge}</td>
          <td>{bi(md_inline(feat_en), md_inline(feat_ko))}</td>
        </tr>""")

    area_blocks = []
    for h_en, h_ko, items in areas:
        cards = []
        for label, href, desc_en, desc_ko in items:
            url = href if href.startswith("http") else f"{TREE}/{href.strip('/')}"
            cards.append(f"""          <li>
            <a href="{url}"><code>{html.escape(label)}</code></a>
            <p>{bi(md_inline(desc_en), md_inline(desc_ko))}</p>
          </li>""")
        area_blocks.append(f"""      <section class="area">
        <h3>{bi(html.escape(h_en), html.escape(h_ko))}</h3>
        <ul class="cards">
{chr(10).join(cards)}
        </ul>
      </section>""")

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ClickHouse Hands-On Labs</title>
<meta name="description" content="Hands-on ClickHouse labs: {len(releases)} per-release feature labs ({oldest} to {newest}), Cloud integrations, workload benchmarks and workshops.">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>&#128202;</text></svg>">
<style>
  :root {{
    --bg: #ffffff; --fg: #1a1a1a; --muted: #666; --line: #e4e4e7;
    --card: #fafafa; --accent: #f5c518; --accent-fg: #1a1a1a;
    --ok-bg: #e7f6ec; --ok-fg: #1a7f37; --unk-bg: #f3f4f6; --unk-fg: #6b7280;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --bg: #0d1117; --fg: #e6edf3; --muted: #9198a1; --line: #30363d;
      --card: #161b22; --accent: #faff69; --accent-fg: #0d1117;
      --ok-bg: #12261a; --ok-fg: #56d364; --unk-bg: #21262d; --unk-fg: #8b949e;
    }}
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; background: var(--bg); color: var(--fg);
    font: 16px/1.6 ui-sans-serif, -apple-system, "Segoe UI", "Apple SD Gothic Neo",
          "Noto Sans KR", Roboto, sans-serif;
  }}
  code {{ font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace; font-size: .89em; }}
  a {{ color: inherit; }}
  .wrap {{ max-width: 1080px; margin: 0 auto; padding: 0 20px; }}

  header {{ border-bottom: 1px solid var(--line); position: sticky; top: 0; background: var(--bg); z-index: 10; }}
  .bar {{ display: flex; align-items: center; gap: 16px; padding: 14px 0; }}
  .brand {{ font-weight: 700; letter-spacing: -.01em; text-decoration: none; }}
  .bar .spacer {{ flex: 1; }}
  .toggle {{ display: inline-flex; border: 1px solid var(--line); border-radius: 999px; overflow: hidden; }}
  .toggle button {{
    font: inherit; font-size: 13px; font-weight: 600; padding: 5px 14px;
    border: 0; background: transparent; color: var(--muted); cursor: pointer;
  }}
  .toggle button[aria-pressed="true"] {{ background: var(--accent); color: var(--accent-fg); }}
  .ghlink {{ font-size: 14px; color: var(--muted); text-decoration: none; }}
  .ghlink:hover {{ color: var(--fg); }}

  .hero {{ padding: 56px 0 32px; }}
  .hero h1 {{ font-size: clamp(28px, 5vw, 42px); line-height: 1.15; margin: 0 0 12px; letter-spacing: -.02em; }}
  .hero p {{ color: var(--muted); font-size: 17px; margin: 0 0 28px; max-width: 62ch; }}
  .stats {{ display: flex; flex-wrap: wrap; gap: 12px; }}
  .stat {{ background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 12px 18px; }}
  .stat b {{ display: block; font-size: 24px; line-height: 1.2; }}
  .stat span {{ font-size: 13px; color: var(--muted); }}

  h2 {{ font-size: 22px; margin: 48px 0 6px; letter-spacing: -.01em; }}
  .lede {{ color: var(--muted); margin: 0 0 18px; font-size: 15px; max-width: 74ch; }}

  table {{ width: 100%; border-collapse: collapse; font-size: 14.5px; }}
  th, td {{ text-align: left; padding: 9px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }}
  th {{ font-size: 12px; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); font-weight: 600; }}
  td.num {{ white-space: nowrap; color: var(--muted); font-variant-numeric: tabular-nums; }}
  a.ver {{ font-weight: 700; text-decoration: none; border-bottom: 2px solid var(--accent); }}
  .badge {{ display: inline-block; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 999px; white-space: nowrap; }}
  .badge.ok {{ background: var(--ok-bg); color: var(--ok-fg); }}
  .badge.unknown {{ background: var(--unk-bg); color: var(--unk-fg); }}

  .note {{ border-left: 3px solid var(--accent); background: var(--card); padding: 14px 18px; border-radius: 0 8px 8px 0; margin: 18px 0 0; font-size: 14.5px; }}

  .area {{ margin-top: 34px; }}
  .area h3 {{ font-size: 17px; margin: 0 0 12px; }}
  ul.cards {{ list-style: none; margin: 0; padding: 0; display: grid; gap: 10px; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); }}
  ul.cards li {{ background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 12px 14px; }}
  ul.cards a {{ text-decoration: none; }}
  ul.cards a code {{ font-weight: 600; }}
  ul.cards a:hover code {{ border-bottom: 1px solid var(--accent); }}
  ul.cards p {{ margin: 6px 0 0; font-size: 13.5px; color: var(--muted); }}

  pre {{ background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px; overflow-x: auto; font-size: 13.5px; }}

  footer {{ margin-top: 64px; border-top: 1px solid var(--line); padding: 24px 0 48px; color: var(--muted); font-size: 14px; }}

  html[lang="en"] .ko, html[lang="ko"] .en {{ display: none; }}
  .scroll {{ overflow-x: auto; }}
</style>
</head>
<body>
<header>
  <div class="wrap bar">
    <a class="brand" href="./">ClickHouse HOLs</a>
    <div class="spacer"></div>
    <div class="toggle" role="group" aria-label="Language">
      <button type="button" data-set-lang="ko" aria-pressed="false">KO</button>
      <button type="button" data-set-lang="en" aria-pressed="true">EN</button>
    </div>
    <a class="ghlink" href="https://github.com/{REPO}">GitHub</a>
  </div>
</header>

<main class="wrap">
  <div class="hero">
    <h1>{bi("Hands-on ClickHouse labs", "ClickHouse 실습 랩", "span")}</h1>
    <p>{bi(
        "One directory per ClickHouse release, plus Cloud integrations, workload experiments and workshops. "
        "Every lab brings up what it needs, generates its own data, and can be run on its own.",
        "ClickHouse 릴리스마다 디렉토리 하나, 여기에 Cloud 연동·워크로드 실험·워크숍을 더했습니다. "
        "각 랩은 필요한 환경을 스스로 띄우고 테스트 데이터를 생성하므로 독립적으로 실행됩니다.")}</p>
    <div class="stats">
      <div class="stat"><b>{len(releases)}</b><span>{bi("release labs", "릴리스 랩")}</span></div>
      <div class="stat"><b>{oldest} → {newest}</b><span>{bi("versions covered", "다루는 버전")}</span></div>
      <div class="stat"><b>{len(verified)}/{len(releases)}</b><span>{bi("run against their own build", "해당 빌드에서 실행 검증")}</span></div>
    </div>
  </div>

  <h2>{bi("Release labs", "릴리스 랩")}</h2>
  <p class="lede">{bi(
      "Each directory holds runnable SQL for that version's new features, with a bilingual guide.",
      "각 디렉토리에는 해당 버전 신기능의 실행 가능한 SQL과 영/한 가이드가 들어 있습니다.")}</p>
  <div class="scroll">
  <table>
    <thead>
      <tr>
        <th>{bi("Version", "버전")}</th>
        <th>{bi("Released", "출시일")}</th>
        <th>{bi("Labs", "랩")}</th>
        <th>{bi("Verified", "검증")}</th>
        <th>{bi("Features covered", "다루는 기능")}</th>
      </tr>
    </thead>
    <tbody>
{chr(10).join(release_rows)}
    </tbody>
  </table>
  </div>
  <p class="note">{bi(
      "<strong>Verified</strong> names the exact server build every lab in that directory was run against, "
      "end to end, with zero exceptions. <em>Not run</em> means the labs were written for that release but "
      "have not been executed here. Of the six directories that were re-run, four turned out to contain SQL "
      "that had never worked on the release it documents — so read <em>not run</em> as unknown, not as working.",
      "<strong>검증</strong>은 해당 디렉토리의 모든 랩을 예외 0으로 끝까지 실행해 본 정확한 서버 빌드입니다. "
      "<em>미실행</em>은 해당 릴리스를 위해 작성됐지만 여기서 실행해 보지 않았다는 뜻입니다. "
      "실제로 재실행한 6개 디렉토리 중 4개에서 해당 릴리스에서 한 번도 동작한 적 없는 SQL이 발견됐으므로, "
      "<em>미실행</em>은 '정상'이 아니라 '미상'으로 읽는 편이 안전합니다.")}</p>

  <h2>{bi("Everything else", "그 외 실습")}</h2>
  <p class="lede">{bi(
      "Cloud integrations, end-to-end use cases, focused workload experiments and multi-service workshops.",
      "Cloud 연동, 엔드투엔드 활용 사례, 집중 워크로드 실험, 다중 서비스 워크숍입니다.")}</p>
{chr(10).join(area_blocks)}

  <h2>{bi("Getting started", "시작하기")}</h2>
  <pre><code>git clone https://github.com/{REPO}.git
cd clickhouse-hols/local/releases/{newest}
./00-setup.sh</code></pre>
  <p class="lede">{bi(
      "Then run the numbered scripts in order. Every lab documents its own setup and teardown; nothing is global.",
      "이후 번호 순서대로 스크립트를 실행하세요. 각 랩이 자체 설정과 정리 방법을 문서화하며, 전역 설정은 없습니다.")}</p>
</main>

<footer class="wrap">
  <p>{footer}</p>
</footer>

<script>
  (function () {{
    var KEY = 'chhols-lang';
    function apply(lang) {{
      document.documentElement.lang = lang;
      document.querySelectorAll('[data-set-lang]').forEach(function (b) {{
        b.setAttribute('aria-pressed', String(b.dataset.setLang === lang));
      }});
    }}
    var saved = null;
    try {{ saved = localStorage.getItem(KEY); }} catch (e) {{}}
    apply(saved || ((navigator.language || 'en').toLowerCase().startsWith('ko') ? 'ko' : 'en'));
    document.querySelectorAll('[data-set-lang]').forEach(function (b) {{
      b.addEventListener('click', function () {{
        var lang = b.dataset.setLang;
        apply(lang);
        try {{ localStorage.setItem(KEY, lang); }} catch (e) {{}}
      }});
    }});
  }})();
</script>
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="exit non-zero if the committed page is out of date")
    args = ap.parse_args()

    root = pathlib.Path(subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True).stdout.strip())

    releases = parse_releases(root / "local" / "releases" / "README.md")
    areas = parse_areas(root / "README.md")
    page = render(releases, areas)

    out = root / "docs" / "index.html"
    if args.check:
        if not out.exists():
            print("docs/index.html is missing; run build_site.py")
            return 1
        if out.read_text() != page:
            print("docs/index.html is out of date; run:")
            print("    python3 .github/scripts/build_site.py")
            return 1
        print(f"OK: docs/index.html matches {len(releases)} releases and "
              f"{sum(len(a[2]) for a in areas)} other labs")
        return 0

    out.parent.mkdir(exist_ok=True)
    out.write_text(page)
    print(f"wrote {out.relative_to(root)}: {len(releases)} releases, "
          f"{sum(len(a[2]) for a in areas)} other labs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
