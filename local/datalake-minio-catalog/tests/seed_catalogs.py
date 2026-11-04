#!/usr/bin/env python3
"""Seed one small Iceberg table through each catalog's own API (pyiceberg).

Runs inside a pinned python container on the lab network (see test-datalakecatalog.sh).
Usage: seed_catalogs.py <nessie|hive|iceberg-rest|polaris|unity> ...
       seed_catalogs.py unity-props <out-file>   (write Unity server.properties with MinIO STS credentials)
Table: lab.events, 5 rows (id long, name string, amount double, ts timestamp).
Unity OSS has no Iceberg write path here: its table is Delta (written with deltalake, then
registered through the Unity REST API).
"""
import os
import sys
import time
from datetime import datetime

import pyarrow as pa
import requests
from pyiceberg.catalog import load_catalog
from pyiceberg.exceptions import NamespaceAlreadyExistsError, NoSuchTableError

USER = os.environ.get("MINIO_ROOT_USER", "admin")
PASSWORD = os.environ.get("MINIO_ROOT_PASSWORD", "password123")
BUCKET = os.environ.get("SAMPLE_DATA_BUCKET", "warehouse")
S3 = {
    "s3.endpoint": "http://minio:9000",
    "s3.access-key-id": USER,
    "s3.secret-access-key": PASSWORD,
    "s3.region": "us-east-1",
    "s3.path-style-access": "true",
}
POLARIS_CATALOG = "polaris_lab"

ROWS = {
    "id": [1, 2, 3, 4, 5],
    "name": ["alpha", "bravo", "charlie", "delta", "echo"],
    "amount": [10.5, 20.25, 30.0, 40.75, 50.5],
    "ts": [datetime(2026, 11, 4, h, 0, 0) for h in range(1, 6)],
}
SCHEMA = pa.schema([
    pa.field("id", pa.int64()),
    pa.field("name", pa.string()),
    pa.field("amount", pa.float64()),
    pa.field("ts", pa.timestamp("us")),
])


def polaris_provision():
    base = "http://polaris:8181/api"
    tok = requests.post(
        base + "/catalog/v1/oauth/tokens",
        data={"grant_type": "client_credentials", "client_id": "root",
              "client_secret": "s3cr3t", "scope": "PRINCIPAL_ROLE:ALL"},
    )
    tok.raise_for_status()
    h = {"Authorization": "Bearer " + tok.json()["access_token"]}
    body = {"catalog": {
        "name": POLARIS_CATALOG, "type": "INTERNAL", "readOnly": False,
        "properties": {"default-base-location": f"s3://{BUCKET}/polaris/"},
        "storageConfigInfo": {
            "storageType": "S3", "allowedLocations": [f"s3://{BUCKET}/polaris/"],
            "endpoint": "http://minio:9000", "pathStyleAccess": True,
            "stsUnavailable": True,
        }}}
    r = requests.post(base + "/management/v1/catalogs", json=body, headers=h)
    if r.status_code not in (201, 409):
        raise SystemExit(f"polaris create catalog: {r.status_code} {r.text}")
    r = requests.put(
        f"{base}/management/v1/principal-roles/service_admin/catalog-roles/{POLARIS_CATALOG}",
        json={"catalogRole": {"name": "catalog_admin"}}, headers=h)
    if r.status_code not in (200, 201, 204):
        raise SystemExit(f"polaris grant: {r.status_code} {r.text}")
    r = requests.put(
        f"{base}/management/v1/catalogs/{POLARIS_CATALOG}/catalog-roles/catalog_admin/grants",
        json={"grant": {"type": "catalog", "privilege": "CATALOG_MANAGE_CONTENT"}}, headers=h)
    if r.status_code not in (200, 201, 204):
        raise SystemExit(f"polaris privilege: {r.status_code} {r.text}")


def connect(kind):
    if kind == "nessie":
        return load_catalog("nessie", **{"type": "rest", "uri": "http://nessie:19120/iceberg",
                                         "warehouse": "warehouse", **S3})
    if kind == "iceberg-rest":
        return load_catalog("rest", **{"type": "rest", "uri": "http://iceberg-rest:8181", **S3})
    if kind == "hive":
        return load_catalog("hive", **{"type": "hive", "uri": "thrift://hive-metastore:9083",
                                       "warehouse": f"s3a://{BUCKET}/hive/", **S3})
    if kind == "polaris":
        polaris_provision()
        return load_catalog("polaris", **{
            "type": "rest", "uri": "http://polaris:8181/api/catalog",
            "warehouse": POLARIS_CATALOG, "credential": "root:s3cr3t",
            "scope": "PRINCIPAL_ROLE:ALL",
            "header.X-Iceberg-Access-Delegation": "", **S3})
    raise SystemExit("unknown catalog " + kind)


def unity_props(out):
    """Unity OSS reads S3 credentials from server.properties and cannot be pointed at a MinIO
    endpoint, so give it short-lived MinIO STS credentials (AssumeRole) for bucket s3://BUCKET."""
    import botocore.session
    sts = botocore.session.get_session().create_client(
        "sts", endpoint_url=S3["s3.endpoint"], aws_access_key_id=USER,
        aws_secret_access_key=PASSWORD, region_name="us-east-1")
    c = sts.assume_role(RoleArn="arn:aws:iam::000000000000:role/lab", RoleSessionName="unity",
                        DurationSeconds=3600)["Credentials"]
    with open(out, "w") as f:
        f.write("server.env=dev\nserver.authorization=disable\n"
                f"s3.bucketPath.0=s3://{BUCKET}\ns3.region.0=us-east-1\n"
                f"s3.accessKey.0={c['AccessKeyId']}\ns3.secretKey.0={c['SecretAccessKey']}\n"
                f"s3.sessionToken.0={c['SessionToken']}\n")


def seed_unity():
    import json
    from deltalake import write_deltalake
    base = "http://unity-catalog:8080/api/2.1/unity-catalog"
    loc = f"s3://{BUCKET}/unity/events"
    write_deltalake(loc, pa.Table.from_pydict(ROWS, schema=SCHEMA), mode="overwrite",
                    storage_options={"AWS_ENDPOINT_URL": "http://minio:9000",
                                     "AWS_ACCESS_KEY_ID": USER, "AWS_SECRET_ACCESS_KEY": PASSWORD,
                                     "AWS_REGION": "us-east-1", "AWS_ALLOW_HTTP": "true"})
    for path, body in (("/catalogs", {"name": "lab"}),
                       ("/schemas", {"name": "lab", "catalog_name": "lab"})):
        r = requests.post(base + path, json=body)
        if r.status_code != 200 and "ALREADY_EXISTS" not in r.text:
            raise SystemExit(f"unity {path}: {r.status_code} {r.text}")
    requests.delete(base + "/tables/lab.lab.events")
    cols = [("id", "LONG", "long"), ("name", "STRING", "string"),
            ("amount", "DOUBLE", "double"), ("ts", "TIMESTAMP_NTZ", "timestamp_ntz")]
    body = {"name": "events", "catalog_name": "lab", "schema_name": "lab", "table_type": "EXTERNAL",
            "data_source_format": "DELTA", "storage_location": loc,
            "columns": [{"name": n, "type_name": tn, "type_text": tt, "position": i, "nullable": True,
                         "type_json": json.dumps({"name": n, "type": tt, "nullable": True, "metadata": {}})}
                        for i, (n, tn, tt) in enumerate(cols)]}
    r = requests.post(base + "/tables", json=body)
    if r.status_code != 200:
        raise SystemExit(f"unity create table: {r.status_code} {r.text}")
    print(f"seeded unity: lab.lab.events (Delta, 5 rows) at {loc}")


def seed(kind):
    if kind == "unity":
        return seed_unity()
    cat = connect(kind)
    try:
        cat.create_namespace("lab")
    except NamespaceAlreadyExistsError:
        pass
    try:
        cat.drop_table("lab.events")
    except NoSuchTableError:
        pass
    # Hive has no catalog-wide warehouse for pyiceberg: give the table location explicitly.
    loc = f"s3a://{BUCKET}/hive/lab/events" if kind == "hive" else None
    tbl = cat.create_table("lab.events", schema=SCHEMA, location=loc)
    tbl.append(pa.Table.from_pydict(ROWS, schema=SCHEMA))
    print(f"seeded {kind}: lab.events rows={tbl.scan().to_arrow().num_rows} at {tbl.location()}")


def seed_with_retry(kind, tries=40):
    """Catalog containers start at different speeds (Hive runs under emulation on arm64)."""
    for i in range(tries):
        try:
            return seed(kind)
        except (Exception, SystemExit) as e:  # noqa: BLE001 - retry any startup failure
            if i == tries - 1:
                raise
            print(f"  {kind} not ready ({str(e)[:100]}), retry {i + 1}", flush=True)
            time.sleep(3)


if __name__ == "__main__":
    if sys.argv[1] == "unity-props":
        unity_props(sys.argv[2])
    else:
        for k in sys.argv[1:]:
            seed_with_retry(k)
