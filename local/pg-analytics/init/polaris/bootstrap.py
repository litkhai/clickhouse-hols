"""Create the Polaris catalog, principals and grants the bench needs.

Idempotent: re-running rotates the two principals' secrets and rewrites
.state/polaris.json, which every other script reads.

  catalog  ilm           INTERNAL, s3://warehouse/  (MinIO, static keys, no STS)
  principal ilm_writer -> role ilm_writer_role -> catalog role ilm_admin  (CATALOG_MANAGE_CONTENT)
  principal ilm_reader -> role ilm_reader_role -> catalog role ilm_read   (read-only privileges)

pg_lake writes with ilm_writer. pg_duckdb and ClickHouse read with ilm_reader,
so a reader that tries to commit fails at the catalog instead of silently
forking the table.
"""
import json
import os
import pathlib

import requests

POLARIS = "http://polaris:8181"
CATALOG = os.environ.get("ILM_DB", "ilm")
BUCKET = os.environ.get("S3_BUCKET", "warehouse")
STATE = pathlib.Path(__file__).resolve().parents[2] / ".state" / "polaris.json"

READ_PRIVS = ["CATALOG_READ_PROPERTIES", "NAMESPACE_LIST", "NAMESPACE_READ_PROPERTIES",
              "TABLE_LIST", "TABLE_READ_PROPERTIES", "TABLE_READ_DATA"]


def token(client_id, secret):
    r = requests.post(f"{POLARIS}/api/catalog/v1/oauth/tokens", data={
        "grant_type": "client_credentials", "client_id": client_id,
        "client_secret": secret, "scope": "PRINCIPAL_ROLE:ALL"})
    r.raise_for_status()
    return r.json()["access_token"]


class Mgmt:
    def __init__(self, tok):
        self.s = requests.Session()
        self.s.headers.update({"Authorization": f"Bearer {tok}",
                               "Content-Type": "application/json"})

    def call(self, method, path, body=None, ok_conflict=True):
        r = self.s.request(method, f"{POLARIS}/api/management/v1{path}", json=body)
        if r.status_code == 409 and ok_conflict:
            return None
        if r.status_code >= 400:
            raise RuntimeError(f"{method} {path}: {r.status_code} {r.text}")
        return r.json() if r.text else None


def principal(m, name, role, catalog_role, privileges):
    creds = m.call("POST", "/principals", {"principal": {"name": name}})
    if creds is None:  # exists: rotate to learn a usable secret
        creds = m.call("POST", f"/principals/{name}/rotate", ok_conflict=False)
    m.call("POST", "/principal-roles", {"principalRole": {"name": role}})
    m.call("PUT", f"/principals/{name}/principal-roles", {"principalRole": {"name": role}})
    m.call("POST", f"/catalogs/{CATALOG}/catalog-roles", {"catalogRole": {"name": catalog_role}})
    for p in privileges:
        m.call("PUT", f"/catalogs/{CATALOG}/catalog-roles/{catalog_role}/grants",
               {"grant": {"type": "catalog", "privilege": p}})
    m.call("PUT", f"/principal-roles/{role}/catalog-roles/{CATALOG}",
           {"catalogRole": {"name": catalog_role}})
    c = creds["credentials"]
    return {"client_id": c["clientId"], "client_secret": c["clientSecret"]}


def main():
    m = Mgmt(token(os.environ["POLARIS_ROOT_ID"], os.environ["POLARIS_ROOT_SECRET"]))
    m.call("POST", "/catalogs", {"catalog": {
        "name": CATALOG, "type": "INTERNAL", "readOnly": False,
        "properties": {"default-base-location": f"s3://{BUCKET}/lake/"},
        "storageConfigInfo": {
            "storageType": "S3",
            "allowedLocations": [f"s3://{BUCKET}/"],
            "endpoint": "http://localhost:19000",
            "endpointInternal": "http://minio:9000",
            "pathStyleAccess": True,
            "region": "us-east-1",
            # MinIO here has no STS: every engine uses static keys instead of vended ones
            "stsUnavailable": True,
        }}})
    state = {
        "catalog": CATALOG,
        "rest_uri": f"{POLARIS}/api/catalog",
        "oauth_uri": f"{POLARIS}/api/catalog/v1/oauth/tokens",
        "writer": principal(m, "ilm_writer", "ilm_writer_role", "ilm_admin",
                            ["CATALOG_MANAGE_CONTENT"]),
        "reader": principal(m, "ilm_reader", "ilm_reader_role", "ilm_read", READ_PRIVS),
    }
    for who in ("writer", "reader"):
        token(state[who]["client_id"], state[who]["client_secret"])  # prove it logs in
    STATE.parent.mkdir(exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2))
    print(json.dumps(m.call("GET", f"/catalogs/{CATALOG}"), indent=2))
    print(f"principals written to {STATE.relative_to(STATE.parents[1])}")


if __name__ == "__main__":
    main()
