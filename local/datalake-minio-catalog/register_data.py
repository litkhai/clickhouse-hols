#!/usr/bin/env python3
"""
Register sample data with Iceberg catalog and MinIO
"""

import os
import sys
import json
from minio import Minio
from minio.error import S3Error
import time

def load_config():
    """Load configuration from config.env"""
    config = {}
    with open('config.env', 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                key, value = line.split('=', 1)
                config[key] = value
    return config

def upload_to_minio(config):
    """Upload sample data to MinIO"""
    print("\n" + "="*50)
    print("Uploading Sample Data to MinIO")
    print("="*50)

    # Initialize MinIO client
    minio_client = Minio(
        f"localhost:{config.get('MINIO_PORT', '9000')}",
        access_key=config.get('MINIO_ROOT_USER', 'admin'),
        secret_key=config.get('MINIO_ROOT_PASSWORD', 'password123'),
        secure=False
    )

    bucket_name = config.get('SAMPLE_DATA_BUCKET', 'warehouse')

    # Ensure bucket exists
    try:
        if not minio_client.bucket_exists(bucket_name):
            minio_client.make_bucket(bucket_name)
            print(f"✓ Created bucket: {bucket_name}")
        else:
            print(f"✓ Bucket exists: {bucket_name}")
    except S3Error as e:
        print(f"✗ Error creating bucket: {e}")
        return False

    # Upload JSON file
    json_file = "sample-data/customers.json"
    if os.path.exists(json_file):
        try:
            minio_client.fput_object(
                bucket_name,
                "data/customers.json",
                json_file
            )
            print(f"✓ Uploaded: {json_file} -> s3://{bucket_name}/data/customers.json")
        except S3Error as e:
            print(f"✗ Error uploading {json_file}: {e}")

    # Upload Parquet file
    parquet_file = "sample-data/orders.parquet"
    if os.path.exists(parquet_file):
        try:
            minio_client.fput_object(
                bucket_name,
                "data/orders.parquet",
                parquet_file
            )
            print(f"✓ Uploaded: {parquet_file} -> s3://{bucket_name}/data/orders.parquet")
        except S3Error as e:
            print(f"✗ Error uploading {parquet_file}: {e}")

    print("\n✓ Upload complete!")
    return True

def create_iceberg_tables_nessie(config):
    """Create Iceberg tables using Nessie catalog"""
    print("\n" + "="*50)
    print("Creating Iceberg Tables with Nessie")
    print("="*50)

    try:
        from pyiceberg.catalog import load_catalog
        import pyarrow.parquet as pq

        # Configure catalog
        catalog = load_catalog(
            "nessie",
            **{
                "uri": f"http://localhost:{config.get('NESSIE_PORT', '19120')}/api/v2",
                "warehouse": f"s3://{config.get('SAMPLE_DATA_BUCKET', 'warehouse')}/",
                "s3.endpoint": f"http://localhost:{config.get('MINIO_PORT', '9000')}",
                "s3.access-key-id": config.get('MINIO_ROOT_USER', 'admin'),
                "s3.secret-access-key": config.get('MINIO_ROOT_PASSWORD', 'password123'),
                "s3.path-style-access": "true",
            }
        )

        # Create namespace
        try:
            catalog.create_namespace("demo")
            print("✓ Created namespace: demo")
        except Exception as e:
            print(f"ℹ Namespace 'demo' may already exist: {e}")

        # Read parquet file and create table
        if os.path.exists("sample-data/orders.parquet"):
            table = pq.read_table("sample-data/orders.parquet")
            try:
                iceberg_table = catalog.create_table(
                    "demo.orders",
                    schema=table.schema
                )
                print("✓ Created Iceberg table: demo.orders")

                # Append data
                iceberg_table.append(table)
                print("✓ Loaded data into demo.orders")
            except Exception as e:
                print(f"ℹ Table creation: {e}")

        print("\n✓ Nessie setup complete!")
        return True

    except ImportError:
        print("✗ PyIceberg not installed. Install with: pip install pyiceberg")
        return False
    except Exception as e:
        print(f"✗ Error: {e}")
        return False

def create_iceberg_tables_rest(config):
    """Create Iceberg tables using REST catalog"""
    print("\n" + "="*50)
    print("Creating Iceberg Tables with REST Catalog")
    print("="*50)

    try:
        from pyiceberg.catalog import load_catalog
        import pyarrow.parquet as pq

        # Configure catalog
        catalog = load_catalog(
            "rest",
            **{
                "uri": f"http://localhost:{config.get('ICEBERG_REST_PORT', '8181')}",
                "warehouse": f"s3://{config.get('SAMPLE_DATA_BUCKET', 'warehouse')}/",
                "s3.endpoint": f"http://localhost:{config.get('MINIO_PORT', '9000')}",
                "s3.access-key-id": config.get('MINIO_ROOT_USER', 'admin'),
                "s3.secret-access-key": config.get('MINIO_ROOT_PASSWORD', 'password123'),
                "s3.path-style-access": "true",
            }
        )

        # Create namespace
        try:
            catalog.create_namespace("demo")
            print("✓ Created namespace: demo")
        except Exception as e:
            print(f"ℹ Namespace 'demo' may already exist: {e}")

        # Read parquet file and create table
        if os.path.exists("sample-data/orders.parquet"):
            table = pq.read_table("sample-data/orders.parquet")
            try:
                iceberg_table = catalog.create_table(
                    "demo.orders",
                    schema=table.schema
                )
                print("✓ Created Iceberg table: demo.orders")

                # Append data
                iceberg_table.append(table)
                print("✓ Loaded data into demo.orders")
            except Exception as e:
                print(f"ℹ Table creation: {e}")

        print("\n✓ REST catalog setup complete!")
        return True

    except ImportError:
        print("✗ PyIceberg not installed. Install with: pip install pyiceberg")
        return False
    except Exception as e:
        print(f"✗ Error: {e}")
        return False

def show_summary(config):
    """Show summary of registered data"""
    print("\n" + "="*50)
    print("Data Registration Summary")
    print("="*50)

    bucket_name = config.get('SAMPLE_DATA_BUCKET', 'warehouse')
    catalog_type = config.get('CATALOG_TYPE', 'nessie')

    print(f"\n📦 MinIO Bucket: {bucket_name}")
    print(f"   └─ data/")
    print(f"      ├─ customers.json")
    print(f"      └─ orders.parquet")

    if catalog_type != "hive":
        print(f"\n📊 Iceberg Tables ({catalog_type}):")
        print(f"   └─ demo.orders")

    print(f"\n🔗 Access URLs:")
    print(f"   MinIO Console: http://localhost:{config.get('MINIO_CONSOLE_PORT', '9001')}")
    print(f"   Jupyter: http://localhost:8888")

    if catalog_type == "nessie":
        print(f"   Nessie: http://localhost:{config.get('NESSIE_PORT', '19120')}")
    elif catalog_type == "iceberg-rest":
        print(f"   Iceberg REST: http://localhost:{config.get('ICEBERG_REST_PORT', '8181')}")

def main():
    # Load configuration
    config = load_config()
    catalog_type = config.get('CATALOG_TYPE', 'nessie')

    print("\n" + "="*50)
    print("Data Lake Registration Script")
    print("="*50)
    print(f"Catalog Type: {catalog_type}")

    # Wait a bit for services to be ready
    print("\nWaiting for services to be ready...")
    time.sleep(5)

    # Upload to MinIO
    if not upload_to_minio(config):
        print("\n✗ Failed to upload data to MinIO")
        sys.exit(1)

    # Create Iceberg tables based on catalog type
    if catalog_type == "nessie":
        create_iceberg_tables_nessie(config)
    elif catalog_type == "iceberg-rest":
        create_iceberg_tables_rest(config)
    elif catalog_type == "hive":
        print("\nℹ Hive catalog setup requires manual table creation")
        print("  Use the Jupyter notebook for examples")

    # Show summary
    show_summary(config)

    print("\n✓ Registration complete!")

if __name__ == "__main__":
    main()
