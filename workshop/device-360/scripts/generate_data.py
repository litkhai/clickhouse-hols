#!/usr/bin/env python3
"""
Device360 Synthetic Data Generator
Generates realistic advertising request data with high-cardinality device IDs
"""

import json
import gzip
import random
import uuid
from datetime import datetime, timedelta
from pathlib import Path
import os
import sys

# Power-law distribution parameters
# 1% of devices generate 50% of traffic
# 10% generate 30% of traffic
# 89% generate 20% of traffic

class DataGenerator:
    def __init__(self, num_devices, num_records, output_dir):
        self.num_devices = num_devices
        self.num_records = num_records
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Device distribution tiers
        self.heavy_devices = int(num_devices * 0.01)  # 1% - bots and heavy users
        self.medium_devices = int(num_devices * 0.10)  # 10% - regular users
        self.light_devices = num_devices - self.heavy_devices - self.medium_devices  # 89%

        # Record distribution
        self.heavy_records = int(num_records * 0.50)
        self.medium_records = int(num_records * 0.30)
        self.light_records = num_records - self.heavy_records - self.medium_records

        # Generate device IDs
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
        self.cities = {
            "US": ["New York", "Los Angeles", "Chicago", "Houston", "Phoenix"],
            "GB": ["London", "Manchester", "Birmingham", "Leeds", "Glasgow"],
            "JP": ["Tokyo", "Osaka", "Kyoto", "Yokohama", "Nagoya"],
            "KR": ["Seoul", "Busan", "Incheon", "Daegu", "Daejeon"],
            "DE": ["Berlin", "Munich", "Hamburg", "Frankfurt", "Cologne"],
            "FR": ["Paris", "Marseille", "Lyon", "Toulouse", "Nice"],
            "CA": ["Toronto", "Vancouver", "Montreal", "Calgary", "Ottawa"],
            "AU": ["Sydney", "Melbourne", "Brisbane", "Perth", "Adelaide"],
            "IN": ["Mumbai", "Delhi", "Bangalore", "Hyderabad", "Chennai"],
            "BR": ["São Paulo", "Rio de Janeiro", "Brasília", "Salvador", "Fortaleza"]
        }
        self.continents = {
            "US": "NA", "GB": "EU", "JP": "AS", "KR": "AS", "DE": "EU",
            "FR": "EU", "CA": "NA", "AU": "OC", "IN": "AS", "BR": "SA"
        }

        # Coordinate ranges for cities (approximate)
        self.coordinates = {
            "US": {"lat": (25.0, 49.0), "lon": (-125.0, -66.0)},
            "GB": {"lat": (50.0, 59.0), "lon": (-8.0, 2.0)},
            "JP": {"lat": (30.0, 45.0), "lon": (129.0, 146.0)},
            "KR": {"lat": (33.0, 39.0), "lon": (124.0, 132.0)},
            "DE": {"lat": (47.0, 55.0), "lon": (6.0, 15.0)},
            "FR": {"lat": (42.0, 51.0), "lon": (-5.0, 8.0)},
            "CA": {"lat": (42.0, 83.0), "lon": (-141.0, -52.0)},
            "AU": {"lat": (-44.0, -10.0), "lon": (113.0, 154.0)},
            "IN": {"lat": (8.0, 35.0), "lon": (68.0, 97.0)},
            "BR": {"lat": (-34.0, 5.0), "lon": (-74.0, -35.0)}
        }

    def generate_ip(self):
        """Generate a random IP address"""
        return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"

    def generate_coordinates(self, country):
        """Generate coordinates within country bounds"""
        coords = self.coordinates[country]
        lat = random.uniform(coords["lat"][0], coords["lat"][1])
        lon = random.uniform(coords["lon"][0], coords["lon"][1])
        return round(lat, 6), round(lon, 6)

    def generate_record(self, device_id, timestamp, is_bot=False):
        """Generate a single ad request record"""
        country = random.choice(self.countries)
        city = random.choice(self.cities[country])
        lat, lon = self.generate_coordinates(country)

        app_idx = random.randint(0, len(self.app_names) - 1)

        # Bot detection signals
        if is_bot:
            fraud_score_ifa = random.randint(60, 100)
            fraud_score_ip = random.randint(60, 100)
        else:
            fraud_score_ifa = random.randint(0, 40)
            fraud_score_ip = random.randint(0, 40)

        record = {
            "event_ts": timestamp.strftime("%Y-%m-%d %H:%M:%S"),
            "event_date": timestamp.strftime("%Y-%m-%d"),
            "event_hour": timestamp.hour,
            "device_id": device_id,
            "device_ip": self.generate_ip(),
            "device_brand": random.choice(self.device_brands),
            "device_model": random.choice(self.device_models),
            "os_version": random.randint(9, 15),
            "platform_type": random.randint(1, 3),
            "geo_country": country,
            "geo_region": f"{country}-{random.randint(1, 10)}",
            "geo_city": city,
            "geo_continent": self.continents[country],
            "geo_longitude": lon,
            "geo_latitude": lat,
            "app_id": f"app_{random.randint(1000, 9999)}",
            "app_bundle": self.app_bundles[app_idx],
            "app_name": self.app_names[app_idx],
            "app_category": self.app_categories[app_idx],
            "ad_type": random.randint(1, 5),
            "bid_floor": round(random.uniform(0.1, 5.0), 2),
            "final_cpm": round(random.uniform(0.5, 10.0), 2),
            "response_latency_ms": random.randint(10, 500),
            "response_size_bytes": random.randint(1000, 50000),
            "fraud_score_ifa": fraud_score_ifa,
            "fraud_score_ip": fraud_score_ip,
            "network_type": random.randint(1, 4),
            "screen_density": random.choice([120, 160, 240, 320, 480, 640]),
            "tracking_consent": random.choice(["authorized", "denied", "not_determined"])
        }

        return record

    def generate_batch(self, device_pool, num_records, start_date, end_date, is_bot=False):
        """Generate a batch of records for a device pool"""
        records = []

        for i in range(num_records):
            device_id = random.choice(device_pool)

            # Random timestamp within range
            time_delta = end_date - start_date
            random_seconds = random.randint(0, int(time_delta.total_seconds()))
            timestamp = start_date + timedelta(seconds=random_seconds)

            record = self.generate_record(device_id, timestamp, is_bot)
            records.append(record)

            if (i + 1) % 100000 == 0:
                print(f"  Generated {i + 1:,} records...")

        return records

    def write_to_file(self, records, filename):
        """Write records to gzipped JSON file"""
        filepath = self.output_dir / filename

        print(f"Writing {len(records):,} records to {filename}...")

        with gzip.open(filepath, 'wt', encoding='utf-8') as f:
            for record in records:
                f.write(json.dumps(record) + '\n')

        file_size_mb = filepath.stat().st_size / (1024 * 1024)
        print(f"  File size: {file_size_mb:.2f} MB")

        return file_size_mb

    def generate(self):
        """Generate all data files"""
        print("="*60)
        print("Device360 Data Generation")
        print("="*60)
        print(f"Total devices: {self.num_devices:,}")
        print(f"Total records: {self.num_records:,}")
        print(f"Heavy devices (1%): {self.heavy_devices:,} -> {self.heavy_records:,} records (50%)")
        print(f"Medium devices (10%): {self.medium_devices:,} -> {self.medium_records:,} records (30%)")
        print(f"Light devices (89%): {self.light_devices:,} -> {self.light_records:,} records (20%)")
        print("="*60)

        # Date range: last 30 days
        end_date = datetime.now()
        start_date = end_date - timedelta(days=30)

        total_size_mb = 0
        batch_size = 1000000  # 1M records per file

        # Generate heavy user data (bots)
        print("\n[1/3] Generating heavy device data (bots and heavy users)...")
        heavy_records_remaining = self.heavy_records
        file_num = 1

        while heavy_records_remaining > 0:
            records_to_generate = min(batch_size, heavy_records_remaining)
            records = self.generate_batch(
                self.heavy_device_ids,
                records_to_generate,
                start_date,
                end_date,
                is_bot=True
            )
            size_mb = self.write_to_file(records, f"device360_heavy_{file_num:04d}.json.gz")
            total_size_mb += size_mb
            heavy_records_remaining -= records_to_generate
            file_num += 1

        # Generate medium user data
        print("\n[2/3] Generating medium device data (regular users)...")
        medium_records_remaining = self.medium_records
        file_num = 1

        while medium_records_remaining > 0:
            records_to_generate = min(batch_size, medium_records_remaining)
            records = self.generate_batch(
                self.medium_device_ids,
                records_to_generate,
                start_date,
                end_date,
                is_bot=False
            )
            size_mb = self.write_to_file(records, f"device360_medium_{file_num:04d}.json.gz")
            total_size_mb += size_mb
            medium_records_remaining -= records_to_generate
            file_num += 1

        # Generate light user data
        print("\n[3/3] Generating light device data (occasional users)...")
        light_records_remaining = self.light_records
        file_num = 1

        while light_records_remaining > 0:
            records_to_generate = min(batch_size, light_records_remaining)
            records = self.generate_batch(
                self.light_device_ids,
                records_to_generate,
                start_date,
                end_date,
                is_bot=False
            )
            size_mb = self.write_to_file(records, f"device360_light_{file_num:04d}.json.gz")
            total_size_mb += size_mb
            light_records_remaining -= records_to_generate
            file_num += 1

        print("\n" + "="*60)
        print("Generation Complete!")
        print("="*60)
        print(f"Total size: {total_size_mb / 1024:.2f} GB")
        print(f"Output directory: {self.output_dir}")
        print(f"Files generated: {len(list(self.output_dir.glob('*.json.gz')))}")
        print("="*60)


def main():
    # Read from environment or use defaults
    num_devices = int(os.getenv("NUM_DEVICES", "10000000"))  # 10M devices default
    num_records = int(os.getenv("NUM_RECORDS", "50000000"))  # 50M records default
    output_dir = os.getenv("DATA_OUTPUT_DIR", "./data")

    # For 300GB target, we need approximately 500M records
    # Adjust based on TARGET_SIZE_GB
    target_size_gb = int(os.getenv("TARGET_SIZE_GB", "30"))

    # Estimate: 1M records ≈ 600MB compressed
    # So 300GB needs ~500M records
    estimated_records = int(target_size_gb * 1000000 / 0.6)

    print(f"Target size: {target_size_gb} GB")
    print(f"Estimated records needed: {estimated_records:,}")

    if len(sys.argv) > 1:
        num_records = int(sys.argv[1])

    if len(sys.argv) > 2:
        num_devices = int(sys.argv[2])

    generator = DataGenerator(num_devices, num_records, output_dir)
    generator.generate()


if __name__ == "__main__":
    main()
