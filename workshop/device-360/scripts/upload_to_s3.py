#!/usr/bin/env python3
"""
S3 Upload Script with Progress Tracking
Uploads generated data files to S3 with multipart upload and progress monitoring
"""

import os
import sys
from pathlib import Path
import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
from datetime import datetime

# Load .env file
def load_env():
    env_file = Path(__file__).parent.parent / '.env'
    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key] = value

load_env()


class S3Uploader:
    def __init__(self, bucket_name, aws_region=None):
        self.bucket_name = bucket_name
        self.aws_region = aws_region or os.getenv("AWS_REGION", "us-east-1")

        # Initialize S3 client
        try:
            self.s3_client = boto3.client(
                's3',
                region_name=self.aws_region,
                aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
                aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY")
            )
            print(f"✓ Connected to AWS S3 (region: {self.aws_region})")
        except NoCredentialsError:
            print("ERROR: AWS credentials not found!")
            print("Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables")
            sys.exit(1)

        self.upload_lock = threading.Lock()
        self.total_uploaded = 0
        self.total_bytes = 0

    def ensure_bucket_exists(self):
        """Create bucket if it doesn't exist"""
        try:
            self.s3_client.head_bucket(Bucket=self.bucket_name)
            print(f"✓ Bucket '{self.bucket_name}' exists")
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == '404':
                print(f"Creating bucket '{self.bucket_name}'...")
                try:
                    if self.aws_region == 'us-east-1':
                        self.s3_client.create_bucket(Bucket=self.bucket_name)
                    else:
                        self.s3_client.create_bucket(
                            Bucket=self.bucket_name,
                            CreateBucketConfiguration={'LocationConstraint': self.aws_region}
                        )
                    print(f"✓ Bucket created successfully")
                except ClientError as create_error:
                    print(f"ERROR: Failed to create bucket: {create_error}")
                    sys.exit(1)
            else:
                print(f"ERROR: Failed to access bucket: {e}")
                sys.exit(1)

    def upload_file(self, file_path, s3_key):
        """Upload a single file to S3 with progress callback"""
        try:
            file_size = file_path.stat().st_size
            file_size_mb = file_size / (1024 * 1024)

            print(f"Uploading {file_path.name} ({file_size_mb:.2f} MB)...")

            # Upload with progress callback
            self.s3_client.upload_file(
                str(file_path),
                self.bucket_name,
                s3_key,
                Callback=lambda bytes_transferred: self._upload_progress(file_path.name, bytes_transferred, file_size)
            )

            with self.upload_lock:
                self.total_uploaded += 1
                self.total_bytes += file_size

            print(f"✓ Uploaded {file_path.name}")
            return True

        except Exception as e:
            print(f"✗ Failed to upload {file_path.name}: {e}")
            return False

    def _upload_progress(self, filename, bytes_transferred, total_bytes):
        """Progress callback for upload"""
        percent = (bytes_transferred / total_bytes) * 100
        if bytes_transferred == total_bytes:
            pass  # Completed, main thread will print
        elif bytes_transferred % (10 * 1024 * 1024) == 0:  # Print every 10MB
            print(f"  {filename}: {percent:.1f}% ({bytes_transferred / (1024*1024):.1f} MB)")

    def upload_directory(self, data_dir, s3_prefix="device360", max_workers=4):
        """Upload all files from directory to S3 with parallel upload"""
        data_path = Path(data_dir)

        if not data_path.exists():
            print(f"ERROR: Directory {data_dir} does not exist")
            sys.exit(1)

        # Find all .json.gz files
        files = list(data_path.glob("*.json.gz"))

        if not files:
            print(f"ERROR: No .json.gz files found in {data_dir}")
            sys.exit(1)

        print("="*60)
        print(f"S3 Upload Summary")
        print("="*60)
        print(f"Source directory: {data_dir}")
        print(f"Target bucket: s3://{self.bucket_name}/{s3_prefix}/")
        print(f"Files to upload: {len(files)}")
        print(f"Parallel workers: {max_workers}")
        print("="*60)

        # Ensure bucket exists
        self.ensure_bucket_exists()

        start_time = datetime.now()

        # Upload files in parallel
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = []

            for file_path in files:
                s3_key = f"{s3_prefix}/{file_path.name}"
                future = executor.submit(self.upload_file, file_path, s3_key)
                futures.append(future)

            # Wait for all uploads to complete
            for future in as_completed(futures):
                future.result()

        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()

        print("\n" + "="*60)
        print("Upload Complete!")
        print("="*60)
        print(f"Files uploaded: {self.total_uploaded}/{len(files)}")
        print(f"Total size: {self.total_bytes / (1024**3):.2f} GB")
        print(f"Duration: {duration:.1f} seconds")
        print(f"Average speed: {(self.total_bytes / (1024**2)) / duration:.2f} MB/s")
        print(f"S3 Location: s3://{self.bucket_name}/{s3_prefix}/")
        print("="*60)

    def list_uploaded_files(self, s3_prefix="device360"):
        """List all uploaded files in S3"""
        try:
            response = self.s3_client.list_objects_v2(
                Bucket=self.bucket_name,
                Prefix=s3_prefix
            )

            if 'Contents' not in response:
                print(f"No files found in s3://{self.bucket_name}/{s3_prefix}/")
                return

            print("\nFiles in S3:")
            print("-"*60)
            total_size = 0
            for obj in response['Contents']:
                size_mb = obj['Size'] / (1024 * 1024)
                total_size += obj['Size']
                print(f"  {obj['Key']}: {size_mb:.2f} MB")

            print("-"*60)
            print(f"Total: {len(response['Contents'])} files, {total_size / (1024**3):.2f} GB")

        except ClientError as e:
            print(f"ERROR: Failed to list files: {e}")


def main():
    # Load environment variables
    bucket_name = os.getenv("S3_BUCKET_NAME")
    data_dir = os.getenv("DATA_OUTPUT_DIR", "./data")
    aws_region = os.getenv("AWS_REGION", "us-east-1")
    max_workers = int(os.getenv("S3_UPLOAD_WORKERS", "4"))

    if not bucket_name:
        print("ERROR: S3_BUCKET_NAME environment variable not set")
        print("Please set S3_BUCKET_NAME in your .env file")
        sys.exit(1)

    # Allow command line override
    if len(sys.argv) > 1:
        data_dir = sys.argv[1]

    if len(sys.argv) > 2:
        bucket_name = sys.argv[2]

    uploader = S3Uploader(bucket_name, aws_region)

    # Upload files
    uploader.upload_directory(data_dir, s3_prefix="device360", max_workers=max_workers)

    # List uploaded files
    uploader.list_uploaded_files("device360")


if __name__ == "__main__":
    main()
