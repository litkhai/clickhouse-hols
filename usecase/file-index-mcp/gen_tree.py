#!/usr/bin/env python3
"""Generate a synthetic file tree for the file-index lab. Nothing here comes from a real disk.

The tree has two roots (docs, archive) and is deterministic for a given --seed:
  - office documents, contracts (some with Korean names), notes with short text bodies
  - large media and disk images as *sparse* files: st_size is large, disk use is near zero
  - duplicate groups (same bytes at several paths)
  - empty files, temp files (~$*, *.tmp, *.part), files with no extension, one very deep path
  - one crowded folder (archive/camera/DCIM) with 17,000 small files
  - mtimes spread over 2019-01 .. 2026-10, with one spike month (2025-03, video files)

Usage: gen_tree.py --out DIR [--seed 42]
Prints a JSON summary (file count, bytes) that the run script compares with the index.
"""
import argparse, json, os, random, time
from datetime import datetime, timezone
from pathlib import Path

WORDS = ["report", "budget", "plan", "minutes", "review", "draft", "summary", "design", "invoice", "notes"]
KO = ["보고서", "예산", "회의록", "계획", "검토", "요약"]
TEXT_LINES = [
    "This agreement renews every year unless either party gives notice.",
    "본 계약은 어느 한쪽이 통지하지 않으면 매년 자동으로 연장된다.",
    "Meeting notes: storage cleanup, archive policy, retention review.",
    "회의 메모: 보관 정책과 정리 대상 검토.",
    "Quarterly summary of usage by team.",
]


def ts(y, m, d=15):
    return datetime(y, m, d, 12, 0, tzinfo=timezone.utc).timestamp()


def rand_mtime(rng):
    y = rng.randint(2019, 2026)
    m = rng.randint(1, 10 if y == 2026 else 12)
    return ts(y, m, rng.randint(1, 28))


def write(p: Path, data: bytes = b"", size: int = None, mtime: float = None):
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("wb") as f:
        f.write(data)
        if size is not None and size > len(data):
            f.truncate(size)          # sparse: logical size only
    if mtime is not None:
        os.utime(p, (mtime, mtime))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    out = Path(a.out)
    docs, arch = out / "docs", out / "archive"
    files = 0

    # 1. office documents: 3,000 across team folders
    teams = ["finance", "hr", "sales", "eng", "ops", "legal"]
    for i in range(3000):
        t = rng.choice(teams)
        ext = rng.choices(["docx", "xlsx", "pptx", "pdf", "hwp", "txt", "md"], [30, 20, 10, 25, 5, 5, 5])[0]
        stem = f"{rng.choice(WORDS)}_{i:04d}" if rng.random() < 0.8 else f"{rng.choice(KO)}_{i:04d}"
        p = docs / t / str(rng.randint(2019, 2026)) / f"{stem}.{ext}"
        if ext in ("txt", "md"):
            body = "\n".join(rng.sample(TEXT_LINES, 2)).encode()
            write(p, body, mtime=rand_mtime(rng))
        else:
            write(p, rng.randbytes(rng.randint(200, 4000)), size=rng.randint(20_000, 3_000_000), mtime=rand_mtime(rng))
        files += 1

    # 2. contracts: 120, names in Korean and English, pdf/docx/hwp plus a few txt with a body
    for i in range(120):
        ext = ["pdf", "docx", "hwp", "txt"][i % 4]
        stem = (f"계약서_{i:03d}" if i % 3 == 0 else f"contract_{i:03d}" if i % 3 == 1 else f"service_agreement_{i:03d}")
        p = docs / "legal" / "contracts" / f"{stem}.{ext}"
        if ext == "txt":
            write(p, (TEXT_LINES[0] + "\n" + TEXT_LINES[1]).encode() if i % 8 == 3 else TEXT_LINES[4].encode(), mtime=rand_mtime(rng))
        else:
            write(p, rng.randbytes(1000), size=rng.randint(50_000, 900_000), mtime=rand_mtime(rng))
        files += 1

    # 3. media and disk images (sparse): 400 videos, 30 iso, 200 zip
    for i in range(400):
        y, m = (2025, 3) if i < 150 else (rng.randint(2019, 2026), rng.randint(1, 10))
        write(arch / "media" / f"{y}" / f"clip_{i:04d}.mp4", b"\0", size=rng.randint(200, 2500) * 1024 * 1024, mtime=ts(y, m, rng.randint(1, 28)))
        files += 1
    for i in range(30):
        write(arch / "images" / f"disk_{i:02d}.iso", b"\0", size=rng.randint(3, 8) * 1024 ** 3, mtime=ts(2019 + i % 4, 1 + i % 12))
        files += 1
    for i in range(200):
        write(arch / "backup" / f"backup_{i:03d}.zip", rng.randbytes(64), size=rng.randint(10, 900) * 1024 * 1024, mtime=rand_mtime(rng))
        files += 1

    # 4. duplicate groups: 40 groups, 2-6 copies each, real identical bytes (64 KB - 3 MB)
    for g in range(40):
        data = rng.randbytes(rng.randint(64, 3072) * 1024)
        mt = rand_mtime(rng)
        for c in range(rng.randint(2, 6)):
            where = rng.choice([docs / rng.choice(teams) / "shared", arch / "old_copies" / f"set{c}"])
            write(where / f"dataset_{g:02d}{'' if c == 0 else f' ({c})'}.csv", data, mtime=mt)
            files += 1

    # 5. anomalies: empty files, temp files, no extension, one deep path
    for i in range(60):
        write(docs / rng.choice(teams) / f"empty_{i:02d}.txt", b"", mtime=rand_mtime(rng)); files += 1
    for i in range(45):
        name = [f"~$report_{i:02d}.docx", f"upload_{i:02d}.tmp", f"video_{i:02d}.mp4.part"][i % 3]
        write(docs / rng.choice(teams) / name, rng.randbytes(100), size=rng.randint(1000, 50_000_000), mtime=ts(2026, 10, 1 + i % 20)); files += 1
    for i in range(25):
        write(arch / "misc" / f"README_{i:02d}" if i % 2 else arch / "misc" / f"Makefile{i:02d}", b"x" * 100, mtime=rand_mtime(rng)); files += 1
    deep = docs / "eng" / "/".join(f"level{n:02d}" for n in range(1, 19))
    write(deep / "deep_file.txt", b"deep", mtime=ts(2024, 6)); files += 1

    # 6. one crowded folder: 17,000 photos, ~300 KB logical each (sparse)
    for i in range(17000):
        write(arch / "camera" / "DCIM" / f"IMG_{i:05d}.jpg", b"\xff\xd8" + rng.randbytes(14), size=rng.randint(150_000, 450_000), mtime=ts(2022 + i % 4, 1 + i % 12, 1 + i % 28))
        files += 1

    total = sum(p.stat().st_size for p in out.rglob("*") if p.is_file())
    print(json.dumps({"files": files, "logical_bytes": total, "seed": a.seed, "generated_at": int(time.time())}))


if __name__ == "__main__":
    main()
