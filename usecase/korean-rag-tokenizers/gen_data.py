#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["kiwipiepy==0.24.0"]
# ///
"""Build 00-data.sql from data/*.jsonl, adding Kiwi morphemes.

    uv run usecase/korean-rag-tokenizers/gen_data.py

Reads  data/chunks.jsonl, data/queries.jsonl, data/phrases.jsonl
Writes 00-data.sql next to this script (committed; the lab runs it as step 00,
so running the lab needs neither Python nor Kiwi).

The morphological analysis happens here, outside ClickHouse, and lands in a
`morphemes Array(String)` column. Step 02 indexes that column with
`tokenizer = array`; every other tokenizer works on the raw text.

Re-running with unchanged inputs and an unchanged Kiwi writes a byte-identical file.

    --data DIR        read the three jsonl files from DIR instead of data/
    --out FILE        write FILE instead of 00-data.sql
    --allow-small     skip the size checks (290-310 chunks, 40 queries, 8 per case);
                      for development samples only
"""
import argparse
import json
import sys
from importlib.metadata import version
from pathlib import Path

HERE = Path(__file__).resolve().parent

FCASES = ["particle", "spacing", "ending", "mixed", "short"]
PHRASE_FCASES = {"recheck", *FCASES}

# Kiwi tag, first part (VA-I -> VA). Content words only; particles, endings and
# punctuation are what the other tokenizers cannot get rid of.
KEEP_TAGS = ["NNG", "NNP", "NR", "SL", "SN", "SH", "XR", "VV", "VA"]
# Light verbs and the like that would match half the corpus.
DROP_FORMS = ["하", "되", "있", "어떻"]
POS_RULE = ("Kiwi().tokenize(text); keep tags whose base (before '-') is in {%s}; "
            "lowercase; drop forms {%s}; keep order and duplicates"
            % (", ".join(KEEP_TAGS), ", ".join(DROP_FORMS)))


def fail(msg):
    sys.exit("gen_data.py: " + msg)


def read_jsonl(path):
    if not path.exists():
        fail("missing input %s" % path)
    rows = []
    with path.open(encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if not line.strip():
                fail("%s:%d blank line" % (path.name, n))
            try:
                rows.append(json.loads(line))
            except ValueError as e:
                fail("%s:%d not JSON: %s" % (path.name, n, e))
    return rows


def validate(chunks, queries, phrases, small_ok):
    ids = [c.get("id") for c in chunks]
    if ids != list(range(1, len(chunks) + 1)):
        fail("chunk ids must be contiguous 1..N, in order")
    if not small_ok and not 290 <= len(chunks) <= 310:
        fail("expected 290-310 chunks, got %d" % len(chunks))
    for c in chunks:
        for key in ("doc", "text"):
            if not isinstance(c.get(key), str) or not c[key].strip():
                fail("chunk %s: empty or missing %r" % (c.get("id"), key))
        if "\t" in c["text"] or "\n" in c["text"]:
            fail("chunk %s: tab or newline inside text" % c["id"])

    qids = [q.get("qid") for q in queries]
    if qids != list(range(1, len(queries) + 1)):
        fail("qids must be contiguous 1..N, in order")
    if not small_ok and len(queries) != 40:
        fail("expected 40 queries, got %d" % len(queries))
    seen = []
    for q in queries:
        if q.get("fcase") not in FCASES:
            fail("query %s: fcase %r not in %s" % (q.get("qid"), q.get("fcase"), FCASES))
        if not isinstance(q.get("question"), str) or not q["question"].strip():
            fail("query %s: empty question" % q["qid"])
        if not isinstance(q.get("note"), str):
            fail("query %s: missing note" % q["qid"])
        rel = q.get("relevant")
        if not isinstance(rel, list) or not 1 <= len(rel) <= 3:
            fail("query %s: relevant must hold 1-3 chunk ids" % q["qid"])
        if len(set(rel)) != len(rel):
            fail("query %s: duplicate relevant id" % q["qid"])
        for r in rel:
            if r not in ids:
                fail("query %s: relevant id %r is not a chunk" % (q["qid"], r))
        if not seen or seen[-1] != q["fcase"]:
            seen.append(q["fcase"])
    if seen != [c for c in FCASES if c in seen]:
        fail("queries must be grouped by case in the order %s, got %s" % (FCASES, seen))
    if not small_ok:
        for case in FCASES:
            n = sum(q["fcase"] == case for q in queries)
            if n != 8:
                fail("case %s has %d queries, expected 8" % (case, n))

    if [p.get("pid") for p in phrases] != list(range(1, len(phrases) + 1)):
        fail("phrase pids must be contiguous 1..N, in order")
    if not small_ok and len(phrases) != 11:
        fail("expected 11 phrases, got %d" % len(phrases))
    for p in phrases:
        if p.get("fcase") not in PHRASE_FCASES:
            fail("phrase %s: fcase %r not in %s" % (p.get("pid"), p.get("fcase"), sorted(PHRASE_FCASES)))
        if not isinstance(p.get("phrase"), str) or not p["phrase"].strip():
            fail("phrase %s: empty" % p["pid"])


def sql_str(s):
    out = (s.replace("\\", "\\\\").replace("'", "\\'")
            .replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r"))
    return "'" + out + "'"


def sql_arr(items):
    return "[" + ", ".join(items) + "]"


def sql_strs(items):
    return sql_arr([sql_str(x) for x in items])


def insert(table, cols, rows):
    head = "INSERT INTO %s (%s) VALUES\n" % (table, ", ".join(cols))
    return head + ",\n".join("(" + ", ".join(r) + ")" for r in rows) + ";\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--data", type=Path, default=HERE / "data")
    ap.add_argument("--out", type=Path, default=HERE / "00-data.sql")
    ap.add_argument("--allow-small", action="store_true")
    args = ap.parse_args()

    chunks = read_jsonl(args.data / "chunks.jsonl")
    queries = read_jsonl(args.data / "queries.jsonl")
    phrases = read_jsonl(args.data / "phrases.jsonl")
    validate(chunks, queries, phrases, args.allow_small)

    from kiwipiepy import Kiwi
    kiwi = Kiwi()
    keep, drop = set(KEEP_TAGS), set(DROP_FORMS)

    def morphemes(text):
        out = []
        for t in kiwi.tokenize(text):
            form = t.form.lower()
            if t.tag.split("-")[0] in keep and form not in drop:
                out.append(form)
        return out

    v_kiwi, v_model = version("kiwipiepy"), version("kiwipiepy_model")

    parts = []
    parts.append(
        "-- GENERATED by gen_data.py from data/*.jsonl -- do not edit; re-run\n"
        "--   uv run usecase/korean-rag-tokenizers/gen_data.py\n"
        "--\n"
        "-- Morphemes come from Kiwi, outside ClickHouse:\n"
        "--   kiwipiepy %s, kiwipiepy_model %s\n"
        "--   POS rule: %s.\n"
        "-- The same rule produced every `morphemes` column below. A different Kiwi\n"
        "-- version or model can change them; lab_meta records what was used.\n"
        "\n"
        "CREATE DATABASE IF NOT EXISTS korean_rag;\n"
        "USE korean_rag;\n" % (v_kiwi, v_model, POS_RULE))

    parts.append(
        "\nDROP TABLE IF EXISTS chunks_src;\n"
        "CREATE TABLE chunks_src\n"
        "(\n"
        "    id         UInt32,\n"
        "    doc        String,\n"
        "    body       String,\n"
        "    morphemes  Array(String)\n"
        ")\n"
        "ENGINE = MergeTree ORDER BY id;\n")
    parts.append(insert("chunks_src", ["id", "doc", "body", "morphemes"],
                        [[str(c["id"]), sql_str(c["doc"]), sql_str(c["text"]),
                          sql_strs(morphemes(c["text"]))] for c in chunks]))

    parts.append(
        "\nDROP TABLE IF EXISTS queries;\n"
        "CREATE TABLE queries\n"
        "(\n"
        "    qid        UInt16,\n"
        "    fcase      LowCardinality(String),\n"
        "    question   String,\n"
        "    morphemes  Array(String),\n"
        "    relevant   Array(UInt32),\n"
        "    note       String\n"
        ")\n"
        "ENGINE = MergeTree ORDER BY qid;\n")
    parts.append(insert("queries", ["qid", "fcase", "question", "morphemes", "relevant", "note"],
                        [[str(q["qid"]), sql_str(q["fcase"]), sql_str(q["question"]),
                          sql_strs(morphemes(q["question"])),
                          sql_arr([str(r) for r in q["relevant"]]), sql_str(q["note"])]
                         for q in queries]))

    parts.append(
        "\nDROP TABLE IF EXISTS phrases;\n"
        "CREATE TABLE phrases\n"
        "(\n"
        "    pid        UInt8,\n"
        "    fcase      String,\n"
        "    phrase     String,\n"
        "    morphemes  Array(String)\n"
        ")\n"
        "ENGINE = MergeTree ORDER BY pid;\n")
    parts.append(insert("phrases", ["pid", "fcase", "phrase", "morphemes"],
                        [[str(p["pid"]), sql_str(p["fcase"]), sql_str(p["phrase"]),
                          sql_strs(morphemes(p["phrase"]))] for p in phrases]))

    parts.append(
        "\nDROP TABLE IF EXISTS lab_meta;\n"
        "CREATE TABLE lab_meta\n"
        "(\n"
        "    key    String,\n"
        "    value  String\n"
        ")\n"
        "ENGINE = MergeTree ORDER BY key;\n")
    parts.append(insert("lab_meta", ["key", "value"], [
        [sql_str("kiwipiepy"), sql_str(v_kiwi)],
        [sql_str("kiwipiepy_model"), sql_str(v_model)],
        [sql_str("pos_rule"), sql_str(POS_RULE)],
    ]))

    # newline="\n": the same bytes on every platform
    with args.out.open("w", encoding="utf-8", newline="\n") as f:
        f.write("".join(parts))
    print("wrote %s: %d chunks, %d queries, %d phrases (kiwipiepy %s, model %s)"
          % (args.out.name, len(chunks), len(queries), len(phrases), v_kiwi, v_model))


if __name__ == "__main__":
    main()
