"""Generate TPC-H with DuckDB's tpch extension and stage it as Parquet in MinIO.

    python datagen/gen.py 10        -> s3://warehouse/staging/sf10/<table>/part-NN.parquet

dbgen runs in `children` slices so SF10 fits in the runner's 2 GB: each slice
is generated into a fresh in-memory database, written out, and dropped.
The output is deterministic (dbgen has a fixed seed), so every path reads
byte-identical source data.
"""
import os
import sys
import time

import boto3
import duckdb

TABLES = ["orders", "customer", "part", "partsupp", "supplier", "nation", "region", "lineitem"]
SMALL = {"nation", "region"}  # fixed 25 / 5 rows at every SF; dbgen slices them
                               # too, so they are written whole from their own run


def s3():
    return boto3.client("s3", endpoint_url="http://minio:9000",
                        aws_access_key_id=os.environ["S3_ACCESS_KEY"],
                        aws_secret_access_key=os.environ["S3_SECRET_KEY"])


def connect():
    con = duckdb.connect()
    con.sql("INSTALL tpch; LOAD tpch; INSTALL httpfs; LOAD httpfs;")
    con.sql("SET memory_limit='1500MB'; SET threads=2;")
    con.sql(f"""CREATE SECRET (TYPE s3, KEY_ID '{os.environ["S3_ACCESS_KEY"]}',
                SECRET '{os.environ["S3_SECRET_KEY"]}', ENDPOINT 'minio:9000',
                URL_STYLE 'path', USE_SSL false, REGION 'us-east-1')""")
    return con


def stage_small(bucket, prefix):
    """nation and region, whole (their content does not depend on SF)."""
    con = connect()
    con.sql("CALL dbgen(sf=0.01)")
    for t in sorted(SMALL):
        con.sql(f"COPY {t} TO 's3://{bucket}/{prefix}{t}/part-00.parquet' "
                f"(FORMAT parquet, COMPRESSION zstd)")
    con.close()


def main(sf: int):
    bucket = os.environ.get("S3_BUCKET", "warehouse")
    prefix = f"staging/sf{sf}/"
    done = s3().list_objects_v2(Bucket=bucket, Prefix=prefix + "_SUCCESS").get("KeyCount", 0)
    if done:
        print(f"sf{sf} already staged")
        return
    children = max(1, sf)  # ~1 GB of raw data per slice
    t0 = time.time()
    have = {o["Key"] for o in s3().list_objects_v2(Bucket=bucket, Prefix=prefix + "lineitem/")
            .get("Contents", [])}
    for step in range(children):
        if f"{prefix}lineitem/part-{step:02d}.parquet" in have:
            continue  # resume: lineitem is written last in a slice
        con = connect()
        if children == 1:
            con.sql(f"CALL dbgen(sf={sf})")
        else:
            con.sql(f"CALL dbgen(sf={sf}, children={children}, step={step})")
        for t in TABLES:
            if t in SMALL and children > 1:
                continue
            n = con.sql(f"SELECT count(*) FROM {t}").fetchone()[0]
            if n == 0:
                continue
            con.sql(f"COPY {t} TO 's3://{bucket}/{prefix}{t}/part-{step:02d}.parquet' "
                    f"(FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 122880)")
        con.close()
        print(f"sf{sf} slice {step + 1}/{children} staged ({time.time() - t0:.0f}s)", flush=True)
    stage_small(bucket, prefix)
    s3().put_object(Bucket=bucket, Key=prefix + "_SUCCESS", Body=b"")
    print(f"sf{sf} done in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main(int(sys.argv[1]))
