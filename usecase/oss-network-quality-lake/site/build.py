#!/usr/bin/env python3
"""Render the explainer and the demo page in every locale.

    python3 site/build.py        write site/dist/ (en at /, then /ko/, /ja/, /zh/)

Text comes from site/i18n/<locale>.json (ko is the authoring source, en the default page);
the build fails when the key sets differ or a template names a key that is missing. The explainer's numbers and
sample rows come from site/data/snapshot.json, so the pages work without ClickHouse.
ui/server.py imports this module and renders the same pages on request.

Template syntax:
    {{key}}                 catalogue text (authored HTML allowed)
    {{key|n=a.b,m=c}}       ... with {n} / {m} filled from the snapshot, numbers grouped
    [[name]]                a block rendered here (see BLOCKS)
"""
import html, json, pathlib, re, sys, textwrap

SITE = pathlib.Path(__file__).resolve().parent
LAB = SITE.parent
LOCALES = ["en", "ko", "ja", "zh"]
DEFAULT = "en"      # served at /; the others under a path prefix
SOURCE = "ko"       # the catalogue the others are checked against
NAMES = {"ko": "한국어", "en": "English", "ja": "日本語", "zh": "中文"}
PAGES = {"explainer": SITE / "explainer.html", "demo": LAB / "ui" / "demo.html"}


def load_catalogues():
    cats = {loc: json.loads((SITE / "i18n" / ("%s.json" % loc)).read_text()) for loc in LOCALES}
    base = set(cats[SOURCE])
    bad = []
    for loc in [l for l in LOCALES if l != SOURCE]:
        keys = set(cats[loc])
        if keys != base:
            bad.append("%s.json: missing %s; extra %s" % (
                loc, sorted(base - keys) or "-", sorted(keys - base) or "-"))
    if bad:
        sys.exit("i18n key sets differ from %s.json:\n  " % SOURCE + "\n  ".join(bad))
    for loc in ("ja", "zh"):
        cats[loc] = {k: cjk_spaces(v) for k, v in cats[loc].items()}
    return cats


def cjk_spaces(text):
    """ja/zh have no spaces between words, so under keep-all the only break points would be
    the spaces around numbers and Latin words ("1 分") -- breaking right after the number.
    Make those spaces non-breaking; overflow-wrap: anywhere then wraps as CJK text normally does."""
    return re.sub(r"(<[^>]*>)|( )", lambda m: m.group(1) or "\u00a0", text)


def snapshot():
    return json.loads((SITE / "data" / "snapshot.json").read_text())


def replay():
    """Recorded live-feed presses for hosts without ClickHouse (ui/server.py --record)."""
    p = SITE / "data" / "replay.json"
    return p.read_text().strip() if p.exists() else "null"


def get(obj, path):
    for part in path.split("."):
        obj = obj[int(part)] if isinstance(obj, list) else obj[part]
    return obj


def num(v):
    if isinstance(v, bool) or v is None:
        return str(v)
    if isinstance(v, int) or (isinstance(v, str) and v.isdigit()):
        return "{:,}".format(int(v))
    if isinstance(v, float):
        return "{:,}".format(v) if v != int(v) else "{:,}".format(int(v))
    return str(v)


def size(b):
    for unit in ("B", "KiB", "MiB", "GiB"):
        if b < 1024 or unit == "GiB":
            return ("%.0f %s" if unit in ("B", "KiB") else "%.1f %s") % (b, unit)
        b /= 1024.0


def esc(v):
    return html.escape("NULL" if v is None else str(v))


# ---------------------------------------------------------------- SQL excerpts

def statement(file, head):
    """The statement in <file> that starts with <head>, up to its closing semicolon;
    the whole file when <head> is None."""
    text = (LAB / file).read_text()
    if head is None:
        return text.strip()
    i = text.find(head)
    if i < 0:
        sys.exit("SQL excerpt not found: %s in %s" % (head, file))
    # keep the comment block right above the statement
    start = text.rfind("\n\n", 0, i) + 2
    end = text.find(";\n", i) + 1
    return text[start:end].strip()


SQL = {
    "phone": ("02-generate.sql", "CREATE VIEW oss_lake.synth_traces"),
    "bronze": ("01-schema.sql", "CREATE TABLE oss_lake.ue_trace_raw"),
    "silver": ("01-schema.sql", "CREATE MATERIALIZED VIEW oss_lake.ue_trace_mv"),
    "gold_table": ("01-schema.sql", "CREATE TABLE oss_lake.cell_kpi_1m"),
    "gold": ("01-schema.sql", "CREATE MATERIALIZED VIEW oss_lake.cell_kpi_1m_mv"),
    "serving": ("01-schema.sql", "CREATE MATERIALIZED VIEW oss_lake.cell_rank_rmv"),
    "noc_bronze": ("03-queries.sql", "CREATE OR REPLACE VIEW oss_lake.noc_from_bronze"),
    "noc_gold": ("03-queries.sql", "CREATE OR REPLACE VIEW oss_lake.noc_from_gold"),
    "inventory": ("02-generate.sql", "INSERT INTO oss_lake.cell_inventory"),
    "region": ("01-schema.sql", "CREATE MATERIALIZED VIEW oss_lake.region_kpi_1m_mv"),
    "gold10": ("01-schema.sql", "CREATE MATERIALIZED VIEW oss_lake.cell_kpi_10m_mv"),
    "noc_silver": ("03-queries.sql", "CREATE OR REPLACE VIEW oss_lake.noc_from_silver"),
    "uc_analysis": ("04-usecases.sql", "CREATE OR REPLACE VIEW oss_lake.uc_analysis"),
    "uc_dashboard": ("04-usecases.sql", "CREATE OR REPLACE VIEW oss_lake.uc_dashboard"),
    "uc_alert_cells": ("04-usecases.sql", "CREATE OR REPLACE VIEW oss_lake.uc_alert_cells"),
    "kafka": ("examples/subscribe-kafka.sql", None),
    "postgres": ("examples/postgres-pg-clickhouse.sql", None),
}


def sql_block(name):
    return "<pre class=\"sql\"><code>%s</code></pre>" % html.escape(statement(*SQL[name]))


# ---------------------------------------------------------------- blocks

def kv_table(row, cls=""):
    cells = "".join("<tr><th scope=\"row\"><code>%s</code></th><td><code>%s</code></td></tr>"
                    % (esc(k), esc(v)) for k, v in row.items())
    return "<table class=\"kv %s\">%s</table>" % (cls, cells)


def block_raw(s, t):
    return kv_table(s["story"]["raw"])


def block_compare(s, t):
    raw, sil = s["story"]["raw"], s["story"]["silver"]
    pairs = [("event_ts", "event_ts", "cmp.same"), ("h3_res09", "h3", "cmp.h3"),
             ("imsi", "imsi_hash", "cmp.imsi"), ("rsrp", "rsrp", "cmp.rsrp"),
             ("rsrq", "rsrq", "cmp.float"), ("sinr", "sinr", "cmp.float"),
             ("cqi", "cqi", "cmp.cqi"), ("pci", None, "cmp.dropped"), ("probe", None, "cmp.dropped"),
             (None, "region1", "cmp.region"), (None, "region2", "cmp.region")]
    body = []
    for b, sv, note in pairs:
        changed = note in ("cmp.h3", "cmp.imsi", "cmp.cqi", "cmp.dropped")
        body.append(
            "<tr%s><td><code>%s</code><br><code class=\"v\">%s</code></td>"
            "<td class=\"arrow\" aria-hidden=\"true\">→</td>"
            "<td>%s</td><td class=\"note\">%s</td></tr>" % (
                " class=\"changed\"" if changed else "",
                esc(b) if b else "—", esc(raw[b]) if b else "",
                ("<code>%s</code><br><code class=\"v\">%s</code>" % (esc(sv), esc(sil[sv]))) if sv else "—",
                t[note] if note in t else ""))
    return ("<div class=\"scroll\"><table class=\"compare\"><thead><tr><th scope=\"col\">%s</th><th></th>"
            "<th scope=\"col\">%s</th><th scope=\"col\">%s</th></tr></thead><tbody>%s</tbody></table></div>"
            % (t["layer.bronze"], t["layer.silver"], t["cmp.what"], "".join(body)))


def block_gold(s, t):
    g = dict(s["story"]["gold"])
    g["users_st"] = "uniqState(…) → %s" % g["users_st"]
    return kv_table(g)


def block_fold(s, t):
    """N dots (one per silver row of that cell-minute) folding into one gold row."""
    n = s["story"]["folded_rows"]
    shown = min(n, 96)
    dots = []
    for i in range(shown):
        x, y = 12 + (i % 16) * 13, 14 + (i // 16) * 13
        dots.append("<circle cx=\"%d\" cy=\"%d\" r=\"4.2\"/>" % (x, y))
    more = (t["fold.more"].replace("{n}", num(n - shown))) if n > shown else ""
    return (
        "<svg class=\"fold\" viewBox=\"0 0 420 100\" role=\"img\" aria-label=\"%s\">"
        "<g class=\"dots\">%s</g>"
        "<text x=\"110\" y=\"98\" text-anchor=\"middle\" class=\"lbl\">%s</text>"
        "<path class=\"flow\" d=\"M222 46 H300\" marker-end=\"url(#arrowhead)\"/>"
        "<rect class=\"one\" x=\"312\" y=\"30\" width=\"96\" height=\"32\" rx=\"6\"/>"
        "<text x=\"360\" y=\"51\" text-anchor=\"middle\" class=\"lbl-in\">%s</text>"
        "</svg>" % (
            html.escape(t["fold.aria"].replace("{n}", num(n))), "".join(dots),
            html.escape(more), html.escape(t["fold.one"])))


def block_funnel(s, t):
    top = max(l["rows"] for l in s["layers"]) or 1
    out = []
    for l in s["layers"]:
        pct = max(0.4, 100.0 * l["rows"] / top)
        out.append(
            "<li class=\"f-%s\"><span class=\"f-name\">%s <small>%s</small></span>"
            "<span class=\"f-bar\"><span style=\"width:%.2f%%\"></span></span>"
            "<span class=\"f-n\">%s</span></li>" % (
                l["key"], t["layer." + l["key"]], t["role." + l["key"]], pct, num(l["rows"])))
    return "<ol class=\"funnel\">%s</ol>" % "".join(out)


def block_serving(s, t):
    rows = s["queries"][3]["rows"]
    rank1 = s["story"]["rank1_cell"]
    cols = []
    for lst, metric, unit in (("users", "users", ""), ("signal", "avg_rsrp", " dBm")):
        trs = "".join(
            "<tr%s><td>%s</td><td><code>%s</code></td><td class=\"num\">%s%s</td></tr>" % (
                " class=\"mine\"" if r["cell"] == rank1 and lst == "users" else "",
                r["rnk"], esc(r["cell"]), num(r[metric]), unit)
            for r in rows if r["list"] == lst)
        cols.append(
            "<div class=\"list list-%s\"><h4>%s</h4><table class=\"rank\"><thead><tr><th scope=\"col\">#</th>"
            "<th scope=\"col\">%s</th><th scope=\"col\" class=\"num\">%s</th></tr></thead><tbody>%s</tbody></table></div>"
            % (lst, t["list." + lst], t["col.cell"], t["col." + metric], trs))
    return "<div class=\"lists\">%s</div>" % "".join(cols)


def block_timings(s, t):
    items = "".join(
        "<li><span>%s</span> <span class=\"num\">%s ms</span> <span class=\"muted\">· %s</span></li>" % (
            t["layer." + q["layer"]], num(q["elapsed_ms"]), t["timing.line"].replace("{rows}", num(q["read_rows"])))
        for q in s["queries"])
    return "<ul class=\"timings\">%s</ul>" % items


def block_measured(s, t):
    m = s["machine"]
    return html.escape(t["measured.line"].replace("{date}", s["generated"]).replace(
        "{version}", s["clickhouse"]).replace("{host}", m["host"]).replace(
        "{cpus}", str(m["cpus"])).replace("{mem}", m["mem"]))


def block_flow(s, t):
    """The four stages in plain words, each with a glimpse of the one measurement we follow."""
    st = s["story"]
    raw, sil = st["raw"], st["silver"]
    chips = {
        "bronze": "h3 '%s' · imsi '%s…'" % (raw["h3_res09"], raw["imsi"][:8]),
        "silver": "h3 %s · imsi → %s…" % (sil["h3"], str(sil["imsi_hash"])[:6]),
        "gold": t["flow.gold.chip"].replace("{n}", num(st["folded_rows"])),
        "serving": t["flow.serving.chip"],
    }
    cards = []
    for key in ("bronze", "silver", "gold", "serving"):
        cards.append(
            "<li class=\"stage stage-%s\"><p class=\"st-name\">%s</p><p class=\"st-what\">%s</p>"
            "<p class=\"st-chip\"><code>%s</code></p></li>" % (
                key, t["flow.%s.name" % key], t["flow.%s.what" % key], esc(chips[key])))
    return "<ol class=\"flow\">%s</ol>" % "".join(cards)


def block_uc_analysis(s, t):
    rows = s["usecases"]["analysis"]
    top = max(r["poor_pct"] for r in rows) or 1
    out = []
    for r in rows:
        out.append(
            "<tr><td>%s</td><td>%s</td><td class=\"num\">%s%%</td>"
            "<td class=\"barcell\"><span style=\"width:%.1f%%\"></span></td></tr>" % (
                t["city.short.%d" % r["city"]], t["zone." + r["zone"]], num(r["poor_pct"]),
                max(1.5, 100.0 * r["poor_pct"] / top)))
    return ("<div class=\"scroll\"><table class=\"rank analysis\"><thead><tr><th scope=\"col\">%s</th>"
            "<th scope=\"col\">%s</th><th scope=\"col\" class=\"num\">%s</th><th></th></tr></thead>"
            "<tbody>%s</tbody></table></div>" % (t["col.city"], t["col.zone"], t["col.poor"], "".join(out)))


def district(t, v):
    """'C North-West' (the lake's district value) in the page's language."""
    m = re.match(r"^([ABC]) (.+)$", v or "")
    if not m:
        return v
    return "%s %s" % (t["city.short.%d" % "ABC".index(m.group(1))], t["district." + m.group(2)])


def block_uc_alerts(s, t):
    items = []
    for a in s["usecases"]["alerts"]:
        items.append("<li><span class=\"al-dot\" aria-hidden=\"true\"></span>%s</li>" % html.escape(
            t["alert.line"].replace("{time}", a["minute"][11:16]).replace(
                "{city}", t["city.short.%d" % a["city"]]).replace("{cells}", num(a["cells"])).replace(
                "{drop}", num(a["drop_db"])).replace("{area}", a["area"]).replace(
                "{district}", district(t, a.get("district", "")))))
    return "<ul class=\"alerts\">%s</ul>" % ("".join(items) or "<li>%s</li>" % t["alert.none"])


def block_uc_http(s, t):
    h = s["usecases"]["http"]
    cmd = "curl 'http://localhost:18123/?user=oss_reader' \\\n  --data-binary '%s'" % h["query"]
    return "<pre class=\"sql\"><code>%s</code></pre><pre class=\"sql out\"><code>%s</code></pre>" % (
        html.escape(cmd), html.escape("\n".join(h["lines"])))


def block_regions(s, t):
    rows = s["lessons"]["regions"]
    top = max(r["poor_pct"] for r in rows) or 1
    out = "".join(
        "<tr><td>%s</td><td class=\"num\">%s%%</td><td class=\"barcell\"><span style=\"width:%.1f%%\"></span></td></tr>"
        % (esc(district(t, r["region2"])), num(r["poor_pct"]), max(1.5, 100.0 * r["poor_pct"] / top)) for r in rows)
    return ("<div class=\"scroll\"><table class=\"rank analysis\"><thead><tr><th scope=\"col\">%s</th>"
            "<th scope=\"col\" class=\"num\">%s</th><th></th></tr></thead><tbody>%s</tbody></table></div>"
            % (t["col.region"], t["col.poor"], out))


NOISE = r"(assumeNotNull\([^)]*\)|IS NOT NULL|stringToH3|cityHash64)"


def block_lesson_nullable(s, t):
    """The same NOC query on bronze and on silver, side by side, with the Nullable/parsing
    noise that silver removes marked."""
    def inner(name):
        text = statement(*SQL[name])
        a = text.index("    SELECT")
        b = text.index("    GROUP BY cell") + len("    GROUP BY cell")
        body = html.escape(textwrap.dedent(text[a:b]))
        return re.sub(NOISE, r"<mark>\1</mark>", body)
    return ("<div class=\"side\"><figure><figcaption>%s</figcaption><pre class=\"sql\"><code>%s</code></pre></figure>"
            "<figure><figcaption>%s</figcaption><pre class=\"sql\"><code>%s</code></pre></figure></div>" % (
                t["layer.bronze"], inner("noc_bronze"), t["layer.silver"], inner("noc_silver")))


def block_lesson_state(s, t):
    L = s["lessons"]
    top = max(r["bytes"] for r in L["state_size"])
    bars = "".join(
        "<li><span class=\"lb\"><code>%s</code> · %s · %s</span><span class=\"bar\"><span style=\"width:%.1f%%\"></span></span>"
        "<span class=\"num\">%s B</span></li>" % (
            esc(r["fn"]), esc(r["input"]), t["lesson.b.distinct"].replace("{n}", num(r["distinct_values"])),
            100.0 * r["bytes"] / top, num(r["bytes"]))
        for r in sorted(L["state_size"], key=lambda r: (r["distinct_values"], r["fn"], r["input"])))
    gtop = max(r["total_state_bytes"] for r in L["grain"])
    grain = "".join(
        "<li><span class=\"lb\">%s</span><span class=\"bar g\"><span style=\"width:%.1f%%\"></span></span>"
        "<span class=\"num\">%s</span></li>" % (
            html.escape(t["lesson.b.grain.row"].replace("{grain}", t["grain." + r["grain"].replace(" ", "")]).replace(
                "{rows}", num(r["rows"])).replace("{avg}", num(r["avg_state_bytes"]))),
            100.0 * r["total_state_bytes"] / gtop, size(r["total_state_bytes"]))
        for r in L["grain"])
    return ("<p class=\"sub\">%s</p><ul class=\"bars\">%s</ul><p class=\"sub\">%s</p><ul class=\"bars\">%s</ul>"
            % (t["lesson.b.types"], bars, t["lesson.b.grain"], grain))


def block_poc(s, t):
    """The features the PoC verified, each with how it was checked."""
    items = "".join(
        "<li><span class=\"ck\" aria-label=\"%s\">✓</span><div><b>%s</b><span class=\"d\">%s</span>"
        "<span class=\"v\">%s</span></div></li>" % (
            t["poc.verified"], t["poc.f%d" % i], t["poc.f%d.d" % i], t["poc.f%d.v" % i])
        for i in range(1, 12))
    return "<ul class=\"poc\">%s</ul>" % items


BLOCKS = {"raw": block_raw, "compare": block_compare, "gold": block_gold, "fold": block_fold,
          "funnel": block_funnel, "serving": block_serving, "timings": block_timings,
          "measured": block_measured, "flow": block_flow, "uc_analysis": block_uc_analysis,
          "uc_alerts": block_uc_alerts, "uc_http": block_uc_http, "regions": block_regions,
          "lesson_nullable": block_lesson_nullable, "lesson_state": block_lesson_state, "poc": block_poc}


# ---------------------------------------------------------------- page

def lang_menu(loc, page, t):
    """Header language menu (web 05 §3): globe + code, a popover of every locale."""
    items = "".join(
        "<li><a href=\"%s\" hreflang=\"%s\" lang=\"%s\" translate=\"no\"%s>%s</a></li>" % (
            html.escape(href(loc, other, page)), other, other,
            " aria-current=\"true\"" if other == loc else "", NAMES[other])
        for other in LOCALES)
    return (
        "<button class=\"lang-menu\" popovertarget=\"lang-list\" aria-label=\"%s\">"
        "<svg viewBox=\"0 0 24 24\" aria-hidden=\"true\"><circle cx=\"12\" cy=\"12\" r=\"9\"/>"
        "<path d=\"M3 12h18M12 3c2.6 2.8 2.6 15.2 0 18M12 3c-2.6 2.8-2.6 15.2 0 18\"/></svg>"
        "<span translate=\"no\">%s</span></button>"
        "<ul id=\"lang-list\" class=\"lang-menu-list\" popover>%s</ul>" % (
            html.escape(t["lang.aria"]), loc.upper(), items))


def prefix(loc):
    return "" if loc == DEFAULT else loc + "/"


def href(from_loc, to_loc, page):
    """Relative link to <page> in <to_loc>, from <page> in <from_loc>; works from file:// too."""
    depth = (0 if from_loc == DEFAULT else 1) + (1 if page == "demo" else 0)
    tail = prefix(to_loc) + ("demo/" if page == "demo" else "") + "index.html"
    return "../" * depth + tail


def render(page, loc, cats=None, snap=None):
    cats = cats or load_catalogues()
    snap = snap if snap is not None else snapshot()
    t = cats[loc]
    src = PAGES[page].read_text()
    css = (SITE / "assets" / "tokens.css").read_text() + (SITE / "assets" / "style.css").read_text()
    js = (SITE / "assets" / "common.js").read_text()

    def key(m):
        name, _, args = m.group(1).partition("|")
        if name not in t:
            sys.exit("%s: unknown i18n key {{%s}}" % (PAGES[page].name, name))
        text = t[name]
        for a in filter(None, args.split(",")):
            k, _, path = a.partition("=")
            text = text.replace("{%s}" % k, num(get(snap, path)))
        return text

    def block(m):
        name = m.group(1)
        if name.startswith("sql:"):
            return sql_block(name[4:])
        fixed = {
            "lang": loc, "langmenu": lang_menu(loc, page, t), "css": css, "js": js,
            "catalogue": json.dumps(t, ensure_ascii=False).replace("</", "<\\/"),
            "snapshot": json.dumps(snap, ensure_ascii=False).replace("</", "<\\/"),
            "replay": replay().replace("</", "<\\/"),
            "to_demo": "demo/index.html", "to_explainer": "../index.html",
        }
        if name in fixed:
            return fixed[name]
        if name in BLOCKS:
            return BLOCKS[name](snap, t)
        sys.exit("%s: unknown block [[%s]]" % (PAGES[page].name, name))

    out = re.sub(r"\[\[([a-z_:]+)\]\]", block, src)
    return re.sub(r"\{\{([a-z0-9_.]+(?:\|[^}]*)?)\}\}", key, out)


def page_for(path):
    """URL path -> rendered page, for ui/server.py. None when there is no such page."""
    parts = [p for p in path.split("/") if p and p != "index.html"]
    loc = DEFAULT
    if parts and parts[0] in LOCALES and parts[0] != DEFAULT:
        loc = parts.pop(0)
    if parts == []:
        return render("explainer", loc)
    if parts == ["demo"]:
        return render("demo", loc)
    return None


def main():
    cats, snap = load_catalogues(), snapshot()
    dist = SITE / "dist"
    for loc in LOCALES:
        for page in PAGES:
            out = dist / prefix(loc) / ("demo/" if page == "demo" else "") / "index.html"
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(render(page, loc, cats, snap))
    print("wrote %s/{,ko/,ja/,zh/}{index.html,demo/index.html}" % dist.relative_to(LAB))


if __name__ == "__main__":
    main()
