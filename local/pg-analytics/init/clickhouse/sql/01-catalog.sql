-- Path C engine side. Run by runner/setup.py with {reader_credential}
-- substituted from .state/polaris.json.
DROP DATABASE IF EXISTS polaris SYNC;
CREATE DATABASE polaris
ENGINE = DataLakeCatalog('http://polaris:8181/api/catalog', '{s3_key}', '{s3_secret}')
SETTINGS catalog_type = 'rest',
         warehouse = 'ilm',
         catalog_credential = '{reader_credential}',
         auth_scope = 'PRINCIPAL_ROLE:ALL',
         oauth_server_uri = 'http://polaris:8181/api/catalog/v1/oauth/tokens',
         storage_endpoint = 'http://minio:9000/warehouse',
         -- MinIO has no STS here; the engine arguments above are the static S3 keys
         vended_credentials = false;

-- Re-expose under FDW-friendly names: catalog tables are called `tpch.lineitem_cold`
DROP DATABASE IF EXISTS bench SYNC;
CREATE DATABASE bench;
CREATE VIEW bench.lineitem_cold AS SELECT * FROM polaris.`tpch.lineitem_cold`;
CREATE VIEW bench.orders_cold   AS SELECT * FROM polaris.`tpch.orders_cold`;
CREATE VIEW bench.customer      AS SELECT * FROM polaris.`tpch.customer`;
CREATE VIEW bench.part          AS SELECT * FROM polaris.`tpch.part`;
CREATE VIEW bench.partsupp      AS SELECT * FROM polaris.`tpch.partsupp`;
CREATE VIEW bench.supplier      AS SELECT * FROM polaris.`tpch.supplier`;
CREATE VIEW bench.nation        AS SELECT * FROM polaris.`tpch.nation`;
CREATE VIEW bench.region        AS SELECT * FROM polaris.`tpch.region`;
