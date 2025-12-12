#!/usr/bin/env python3
"""
EC2-optimized Data Generator with Direct S3 Upload
Generates data and streams directly to S3 without local storage
"""

import json
import gzip
import random
import uuid
import io
from datetime import datetime, timedelta
import boto3
import os
from pathlib import Path

class StreamingDataGenerator:
    def __init__(self, num_devices, num_records, s3_bucket, s3_prefix):
        self.num_devices = num_devices
        self.num_records = num_records
        self.s3_bucket = s3_bucket
        self.s3_prefix = s3_prefix

        # AWS S3 client
        self.s3_client = boto3.client('s3', region_name=os.getenv('AWS_REGION', 'ap-northeast-2'))

        # Device distribution tiers (1% heavy, 10% medium, 89% light)
        self.heavy_devices = int(num_devices * 0.01)
        self.medium_devices = int(num_devices * 0.10)
        self.light_devices = num_devices - self.heavy_devices - self.medium_devices

        # Record distribution (50% heavy, 30% medium, 20% light)
        self.heavy_records = int(num_records * 0.50)
        self.medium_records = int(num_records * 0.30)
        self.light_records = num_records - self.heavy_records - self.medium_records

        print(f"Generating {num_devices:,} device IDs...")
        self.heavy_device_ids = [str(uuid.uuid4()) for _ in range(self.heavy_devices)]
        self.medium_device_ids = [str(uuid.uuid4()) for _ in range(self.medium_devices)]
        self.light_device_ids = [str(uuid.uuid4()) for _ in range(self.light_devices)]

        # Reference data
        self.device_brands = ["Samsung", "Apple", "Xiaomi", "Oppo", "Vivo", "Huawei", "OnePlus", "Google", "LG", "Motorola"]
        self.device_models = ["Galaxy S21", "iPhone 13", "Redmi Note 10", "Pixel 6", "Galaxy A52", "iPhone 12", "Mi 11", "Reno 5"]
        self.app_names = ["GameApp", "NewsReader", "SocialHub", "ShoppingApp", "VideoStream", "MusicPlayer", "FitnessTracker", "WeatherApp"]
        self.app_bundles = [f"com.example.{name.lower()}" for name in self.app_names]
        self.app_categories = ["Games", "News", "Social", "Shopping", "Entertainment", "Music", "Health", "Weather"]
        self.countries = ["US", "GB", "JP", "KR", "DE", "FR", "CA", "AU", "IN", "BR"]
        self.cities = ["New York", "London", "Tokyo", "Seoul", "Berlin", "Paris", "Toronto", "Sydney", "Mumbai", "Sao Paulo"]
        self.device_types = ["phone", "tablet", "phone", "phone", "tablet"]
        self.os_names = ["Android", "iOS", "Android", "Android", "iOS"]
        self.os_versions = ["11", "14", "12", "13", "15"]
        self.carriers = ["Verizon", "AT&T", "T-Mobile", "Vodafone", "Orange", "China Mobile", "KT", "SK Telecom"]
        self.connection_types = ["wifi", "4g", "5g", "3g", "wifi"]
        self.ad_formats = ["banner", "interstitial", "rewarded_video", "native", "banner"]
        self.ad_sizes = ["320x50", "728x90", "300x250", "1024x768", "320x50"]

        # Bot detection signals
        self.user_agents_normal = [
            "Mozilla/5.0 (Linux; Android 11; SM-G991B) AppleWebKit/537.36",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15",
        ]
        self.user_agents_bot = [
            "curl/7.68.0",
            "python-requests/2.26.0",
            "okhttp/4.9.0",
        ]

        # Time range: last 30 days
        self.end_time = datetime.now()
        self.start_time = self.end_time - timedelta(days=30)

    def generate_record(self, device_id, is_bot=False):
        """Generate a single ad request record"""
        event_time = self.start_time + timedelta(
            seconds=random.randint(0, int((self.end_time - self.start_time).total_seconds()))
        )

        # Bot behavior patterns
        if is_bot:
            click_probability = 0.95  # Bots click almost everything
            user_agent = random.choice(self.user_agents_bot)
            viewability_score = random.uniform(0, 0.3)  # Low viewability
            time_to_click = random.uniform(0.01, 0.5)  # Very fast clicks
        else:
            click_probability = 0.03  # Normal users click 3%
            user_agent = random.choice(self.user_agents_normal)
            viewability_score = random.uniform(0.5, 1.0)  # Normal viewability
            time_to_click = random.uniform(1.0, 30.0)  # Human-like delay

        clicked = random.random() < click_probability

        record = {
            "event_ts": event_time.strftime("%Y-%m-%d %H:%M:%S"),
            "event_date": event_time.strftime("%Y-%m-%d"),
            "event_hour": event_time.hour,
            "device_id": device_id,
            "device_ip": f"{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}",
            "device_brand": random.choice(self.device_brands),
            "device_model": random.choice(self.device_models),
            "device_type": random.choice(self.device_types),
            "os_name": random.choice(self.os_names),
            "os_version": random.choice(self.os_versions),
            "app_name": random.choice(self.app_names),
            "app_bundle": random.choice(self.app_bundles),
            "app_version": f"{random.randint(1,5)}.{random.randint(0,20)}.{random.randint(0,50)}",
            "app_category": random.choice(self.app_categories),
            "country": random.choice(self.countries),
            "city": random.choice(self.cities),
            "carrier": random.choice(self.carriers),
            "connection_type": random.choice(self.connection_types),
            "ad_format": random.choice(self.ad_formats),
            "ad_size": random.choice(self.ad_sizes),
            "ad_position": random.randint(1, 10),
            "publisher_id": f"pub_{random.randint(1000, 9999)}",
            "advertiser_id": f"adv_{random.randint(100, 999)}",
            "campaign_id": f"cmp_{random.randint(10000, 99999)}",
            "creative_id": f"crv_{random.randint(100000, 999999)}",
            "bid_price": round(random.uniform(0.1, 5.0), 2),
            "win_price": round(random.uniform(0.05, 4.5), 2),
            "impression_id": str(uuid.uuid4()),
            "click": 1 if clicked else 0,
            "conversion": 1 if clicked and random.random() < 0.1 else 0,
            "user_agent": user_agent,
            "viewability_score": round(viewability_score, 2),
            "time_to_click": round(time_to_click, 2) if clicked else 0,
        }

        return record

    def generate_and_upload_chunk(self, chunk_id, records_in_chunk, device_ids, is_bot=False):
        """Generate a chunk of data and upload directly to S3"""

        # Create in-memory gzip buffer
        buffer = io.BytesIO()

        with gzip.GzipFile(fileobj=buffer, mode='wb') as gz:
            for i in range(records_in_chunk):
                device_id = random.choice(device_ids)
                record = self.generate_record(device_id, is_bot=is_bot)
                gz.write((json.dumps(record) + '\n').encode('utf-8'))

                if (i + 1) % 100000 == 0:
                    print(f"  Chunk {chunk_id}: {i+1:,}/{records_in_chunk:,} records generated")

        # Verify gzip integrity before upload
        buffer.seek(0)
        compressed_data = buffer.read()

        try:
            # Test decompression
            test_buffer = io.BytesIO(compressed_data)
            with gzip.GzipFile(fileobj=test_buffer, mode='rb') as test_gz:
                # Read first 1000 bytes to verify
                test_gz.read(1000)
            print(f"  ✓ Gzip integrity verified for chunk {chunk_id}")
        except Exception as e:
            print(f"  ✗ ERROR: Gzip validation failed for chunk {chunk_id}: {e}")
            raise Exception(f"Gzip file corrupted for chunk {chunk_id}")

        # Upload to S3
        buffer = io.BytesIO(compressed_data)
        s3_key = f"{self.s3_prefix}/device360_chunk_{chunk_id:04d}.json.gz"

        print(f"  Uploading chunk {chunk_id} to s3://{self.s3_bucket}/{s3_key}...")
        self.s3_client.upload_fileobj(buffer, self.s3_bucket, s3_key)

        return len(compressed_data)  # Return compressed size

    def generate_all_data(self, records_per_chunk=2000000):
        """Generate all data in chunks and upload to S3"""

        print(f"\n{'='*80}")
        print(f"Starting data generation and S3 upload")
        print(f"Total records: {self.num_records:,}")
        print(f"Records per chunk: {records_per_chunk:,}")
        print(f"Target: s3://{self.s3_bucket}/{self.s3_prefix}/")
        print(f"{'='*80}\n")

        total_size = 0
        chunk_id = 1

        # Generate heavy traffic (50% of records from 1% of devices)
        print(f"Generating HEAVY traffic (50% records, 1% devices - bot-like behavior)...")
        remaining_heavy = self.heavy_records
        while remaining_heavy > 0:
            chunk_size = min(records_per_chunk, remaining_heavy)
            size = self.generate_and_upload_chunk(chunk_id, chunk_size, self.heavy_device_ids, is_bot=True)
            total_size += size
            remaining_heavy -= chunk_size
            chunk_id += 1
            print(f"  Progress: {self.heavy_records - remaining_heavy:,}/{self.heavy_records:,} heavy records, {total_size/1024**3:.2f} GB uploaded")

        # Generate medium traffic (30% of records from 10% of devices)
        print(f"\nGenerating MEDIUM traffic (30% records, 10% devices)...")
        remaining_medium = self.medium_records
        while remaining_medium > 0:
            chunk_size = min(records_per_chunk, remaining_medium)
            size = self.generate_and_upload_chunk(chunk_id, chunk_size, self.medium_device_ids, is_bot=False)
            total_size += size
            remaining_medium -= chunk_size
            chunk_id += 1
            print(f"  Progress: {self.medium_records - remaining_medium:,}/{self.medium_records:,} medium records, {total_size/1024**3:.2f} GB uploaded")

        # Generate light traffic (20% of records from 89% of devices)
        print(f"\nGenerating LIGHT traffic (20% records, 89% devices)...")
        remaining_light = self.light_records
        while remaining_light > 0:
            chunk_size = min(records_per_chunk, remaining_light)
            size = self.generate_and_upload_chunk(chunk_id, chunk_size, self.light_device_ids, is_bot=False)
            total_size += size
            remaining_light -= chunk_size
            chunk_id += 1
            print(f"  Progress: {self.light_records - remaining_light:,}/{self.light_records:,} light records, {total_size/1024**3:.2f} GB uploaded")

        print(f"\n{'='*80}")
        print(f"✓ Data generation complete!")
        print(f"  Total records: {self.num_records:,}")
        print(f"  Total chunks: {chunk_id - 1}")
        print(f"  Total size: {total_size/1024**3:.2f} GB")
        print(f"  Location: s3://{self.s3_bucket}/{self.s3_prefix}/")
        print(f"{'='*80}\n")


def load_env():
    """Load environment variables from .env file"""
    env_file = Path('/tmp/device360/.env')
    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key] = value


if __name__ == "__main__":
    # Load environment variables
    load_env()

    # Parameters from environment or defaults
    NUM_RECORDS = int(os.getenv('NUM_RECORDS', 500000000))  # 500M records
    NUM_DEVICES = int(os.getenv('NUM_DEVICES', 10000000))   # 10M devices
    S3_BUCKET = os.getenv('S3_BUCKET_NAME', 'device360-test-orangeaws')
    S3_PREFIX = os.getenv('S3_PREFIX', 'device360')
    RECORDS_PER_CHUNK = int(os.getenv('RECORDS_PER_CHUNK', 2000000))  # 2M per chunk (~1GB compressed)

    print(f"Configuration:")
    print(f"  Records: {NUM_RECORDS:,}")
    print(f"  Devices: {NUM_DEVICES:,}")
    print(f"  Chunk size: {RECORDS_PER_CHUNK:,}")
    print(f"  Target: s3://{S3_BUCKET}/{S3_PREFIX}/")
    print()

    # Generate and upload
    generator = StreamingDataGenerator(NUM_DEVICES, NUM_RECORDS, S3_BUCKET, S3_PREFIX)
    generator.generate_all_data(records_per_chunk=RECORDS_PER_CHUNK)
