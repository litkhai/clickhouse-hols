"""Open the files an Iceberg table is made of, without Spark or an Iceberg library.

For every table under s3://warehouse/fv/: the current metadata.json, the manifest list and manifests
of the current snapshot (Avro), the delete files (Parquet position deletes, Puffin deletion vectors,
decoded to row positions) and the Parquet schema of one data file (with Iceberg field ids).

Run through run.sh (python container in the compose network). Output: results/inspect-<table>.txt.
"""
import io
import json
import os
import struct
import sys
import zlib

import fastavro
import pyarrow.parquet as pq
from pyarrow import fs

S3 = fs.S3FileSystem(access_key=os.environ["AWS_ACCESS_KEY_ID"], secret_key=os.environ["AWS_SECRET_ACCESS_KEY"],
                     endpoint_override=os.environ.get("S3_ENDPOINT", "minio:9000"), scheme="http",
                     region=os.environ.get("AWS_REGION", "us-east-1"))
ROOT = "warehouse/fv"
OUT_DIR = os.environ.get("OUT_DIR", "/lab/results")


def key(uri):
    """s3://warehouse/fv/t/... -> warehouse/fv/t/..."""
    return uri.split("://", 1)[-1]


def read(uri):
    with S3.open_input_file(key(uri)) as f:
        return f.read()


def short(uri):
    return uri.split("/fv/", 1)[-1] if uri else uri


# --- Puffin deletion vectors -------------------------------------------------------------------
# Iceberg spec, "Deletion Vectors": blob = length (4 bytes, big endian) | magic D1 D3 39 64 |
# 64-bit roaring bitmap, portable format | CRC-32 (big endian) of magic + bitmap.

def roaring32(buf, off):
    """Decode a 32-bit roaring bitmap in the portable format; return (values, next offset)."""
    cookie, = struct.unpack_from("<I", buf, off)
    if cookie & 0xFFFF == 12347:  # SERIAL_COOKIE: has run containers
        n = (cookie >> 16) + 1
        off += 4
        run_bitmap = buf[off:off + (n + 7) // 8]
        off += (n + 7) // 8
        has_offsets = n >= 4
    elif cookie == 12346:  # SERIAL_COOKIE_NO_RUNCONTAINER
        n, = struct.unpack_from("<I", buf, off + 4)
        off += 8
        run_bitmap = b"\0" * ((n + 7) // 8)
        has_offsets = True
    else:
        raise ValueError(f"not a roaring bitmap (cookie {cookie})")
    headers = [struct.unpack_from("<HH", buf, off + 4 * i) for i in range(n)]
    off += 4 * n
    if has_offsets:
        off += 4 * n
    values = []
    for i, (hi, card_minus_1) in enumerate(headers):
        card = card_minus_1 + 1
        base = hi << 16
        if run_bitmap[i // 8] >> (i % 8) & 1:
            runs, = struct.unpack_from("<H", buf, off)
            off += 2
            for r in range(runs):
                start, length = struct.unpack_from("<HH", buf, off + 4 * r)
                values.extend(base + start + j for j in range(length + 1))
            off += 4 * runs
        elif card <= 4096:
            values.extend(base + v for v in struct.unpack_from(f"<{card}H", buf, off))
            off += 2 * card
        else:
            words = struct.unpack_from("<1024Q", buf, off)
            values.extend(base + 64 * w + b for w, word in enumerate(words) for b in range(64) if word >> b & 1)
            off += 8192
    return values, off


def deletion_vector(blob):
    length, = struct.unpack_from(">I", blob, 0)
    magic = blob[4:8]
    bitmap = blob[8:4 + length]
    crc, = struct.unpack_from(">I", blob, 4 + length)
    ok_crc = zlib.crc32(blob[4:4 + length]) & 0xFFFFFFFF == crc
    buckets, = struct.unpack_from("<Q", bitmap, 0)
    off, positions = 8, []
    for _ in range(buckets):
        hi, = struct.unpack_from("<I", bitmap, off)
        vals, off = roaring32(bitmap, off + 4)
        positions.extend((hi << 32) | v for v in vals)
    return magic.hex(" "), ok_crc, positions


def puffin_footer(data):
    assert data[:4] == b"PFA1" and data[-4:] == b"PFA1", "not a Puffin file"
    size, = struct.unpack_from("<I", data, len(data) - 12)
    return json.loads(data[len(data) - 12 - size:len(data) - 12])


# --- per table ---------------------------------------------------------------------------------

def inspect(table_dir, w):
    metas = sorted(i.path for i in S3.get_file_info(fs.FileSelector(f"{table_dir}/metadata"))
                   if i.path.endswith(".metadata.json"))
    meta_key = metas[-1]
    m = json.loads(read(meta_key))
    w(f"metadata files: {len(metas)} (one per table change); current: {meta_key.rsplit('/', 1)[-1]}")
    w(f"  format-version: {m['format-version']}")
    for k in ("last-sequence-number", "next-row-id", "current-snapshot-id", "current-schema-id",
              "default-spec-id", "last-partition-id"):
        if k in m:
            w(f"  {k}: {m[k]}")
    w(f"  schemas: {len(m.get('schemas', [m.get('schema')]))}; current fields: " + ", ".join(
        f"{f['id']}:{f['name']}:{f['type'] if isinstance(f['type'], str) else f['type'].get('type')}"
        + (f" (initial-default {f['initial-default']})" if "initial-default" in f else "")
        for f in next(s for s in m.get("schemas", [m.get("schema")]) if s.get("schema-id", 0) == m.get("current-schema-id", 0))["fields"]))
    for spec in m.get("partition-specs", []):
        w(f"  partition spec {spec['spec-id']}: " + ", ".join(f"{p['name']}={p['transform']}" for p in spec["fields"]))
    props = {k: v for k, v in m.get("properties", {}).items() if k.startswith("write.") or k == "format-version"}
    w(f"  properties: {props}")
    w("  snapshots:")
    for s in m.get("snapshots", []):
        extra = "".join(f" {k}={s[k]}" for k in ("sequence-number", "first-row-id", "added-rows") if k in s)
        w(f"    {s['snapshot-id']} {s['summary'].get('operation')}{extra}")

    cur = next((s for s in m.get("snapshots", []) if s["snapshot-id"] == m.get("current-snapshot-id")), None)
    if not cur:
        return
    w(f"\nmanifest list: {short(cur['manifest-list'])}")
    mlist = list(fastavro.reader(io.BytesIO(read(cur["manifest-list"]))))
    sample_data = None
    for e in mlist:
        cols = {k: e.get(k) for k in ("content", "sequence_number", "min_sequence_number", "added_files_count",
                                      "existing_files_count", "deleted_files_count", "first_row_id") if k in e}
        w(f"  manifest {short(e['manifest_path'])}")
        w(f"    {cols}")
        reader = fastavro.reader(io.BytesIO(read(e["manifest_path"])))
        for me in reader:
            df = me["data_file"]
            status = {0: "EXISTING", 1: "ADDED", 2: "DELETED"}[me["status"]]
            info = {k: df.get(k) for k in ("content", "file_format", "record_count", "first_row_id",
                                           "referenced_data_file", "content_offset", "content_size_in_bytes") if df.get(k) is not None}
            if "referenced_data_file" in info:
                info["referenced_data_file"] = info["referenced_data_file"].rsplit("/", 1)[-1]
            seq = me.get("sequence_number")
            w(f"    {status:8} seq={seq} {short(df['file_path'])}")
            w(f"             {info}")
            if status == "DELETED":
                continue
            if df.get("content", 0) == 0 and sample_data is None:
                sample_data = df["file_path"]
            if df.get("content") == 1 and df["file_format"].upper() == "PARQUET":
                t = pq.read_table(io.BytesIO(read(df["file_path"])))
                rows = [(r["file_path"].rsplit("/", 1)[-1], r["pos"]) for r in t.to_pylist()]
                w(f"             position delete rows (file_path, pos): {rows}")
            if df.get("content") == 1 and df["file_format"].upper() == "PUFFIN":
                data = read(df["file_path"])
                blob = data[df["content_offset"]:df["content_offset"] + df["content_size_in_bytes"]]
                magic, ok, pos = deletion_vector(blob)
                w(f"             deletion vector: magic {magic}, crc ok={ok}, deleted positions {pos}")
                footer = puffin_footer(data)
                for b in footer["blobs"]:
                    props = dict(b.get("properties", {}))
                    if "referenced-data-file" in props:
                        props["referenced-data-file"] = props["referenced-data-file"].rsplit("/", 1)[-1]
                    w(f"             puffin footer blob: type={b['type']} offset={b['offset']} length={b['length']} {props}")
            if df.get("content") == 2:
                t = pq.read_table(io.BytesIO(read(df["file_path"])))
                w(f"             equality delete rows: {t.to_pylist()}")
    if sample_data:
        w(f"\nparquet schema of {short(sample_data)} (Iceberg field id per column):")
        schema = pq.read_schema(io.BytesIO(read(sample_data)))
        for f in schema:
            fid = (f.metadata or {}).get(b"PARQUET:field_id", b"-").decode()
            w(f"  {fid:>4}  {f.name}: {f.type}")


def main():
    tables = sorted(i.path for i in S3.get_file_info(fs.FileSelector(ROOT)) if i.type == fs.FileType.Directory)
    if not tables:
        sys.exit(f"no tables under s3://{ROOT}")
    for table_dir in tables:
        name = table_dir.rsplit("/", 1)[-1]
        path = os.path.join(OUT_DIR, f"inspect-{name}.txt")
        with open(path, "w") as out:
            def w(line=""):
                out.write(line + "\n")
            w(f"# {name}  (s3://{table_dir})")
            inspect(table_dir, w)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
