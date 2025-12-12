#!/usr/bin/env python3
"""
Data Generator with Time Persistence
- Each device_id has consistent temporal behavior
- Events for same device follow chronological order
- High cardinality (10M devices)
"""
import json
import gzip
import random
import uuid
import io
from datetime import datetime, timedelta
import boto3
import os

# AWS credentials - should be set in environment before running
# Example:
# export AWS_ACCESS_KEY_ID="your_key"
# export AWS_SECRET_ACCESS_KEY="your_secret"
# export AWS_SESSION_TOKEN="your_token"  # if using temporary credentials
if 'AWS_ACCESS_KEY_ID' not in os.environ:
    print("ERROR: AWS credentials not found in environment variables")
    print("Please set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN")
    exit(1)

NUM_RECORDS = 500000000
NUM_DEVICES = 10000000
S3_BUCKET = 'device360-test-orangeaws'
S3_PREFIX = 'device360'
RECORDS_PER_CHUNK = 2000000

print("="*80)
print("Device360 Data Generator with Time Persistence")
print("="*80)
print(f"Records: {NUM_RECORDS:,}")
print(f"Devices: {NUM_DEVICES:,}")
print(f"Chunk: {RECORDS_PER_CHUNK:,}")
print("="*80)

s3 = boto3.client('s3', region_name='ap-northeast-2')

# Device tiers
heavy_count = int(NUM_DEVICES * 0.01)
medium_count = int(NUM_DEVICES * 0.10)
light_count = NUM_DEVICES - heavy_count - medium_count

heavy_records = int(NUM_RECORDS * 0.50)
medium_records = int(NUM_RECORDS * 0.30)
light_records = NUM_RECORDS - heavy_records - medium_records

print(f"\nGenerating {NUM_DEVICES:,} devices with temporal profiles...")

# Time range: 30 days
end_time = datetime.now()
start_time = end_time - timedelta(days=30)
total_seconds = int((end_time - start_time).total_seconds())

# Generate devices with their first appearance time
class Device:
    def __init__(self, device_id, first_seen_offset, events_count, is_bot=False):
        self.device_id = device_id
        self.first_seen = start_time + timedelta(seconds=first_seen_offset)
        self.events_count = events_count
        self.is_bot = is_bot
        self.events_generated = 0

        # Device attributes (consistent per device)
        self.brand = random.choice(["Samsung", "Apple", "Xiaomi", "Oppo", "Vivo"])
        self.model = random.choice(["Galaxy S21", "iPhone 13", "Redmi Note 10", "Pixel 6"])
        self.app = random.choice(["GameApp", "NewsReader", "SocialHub", "ShoppingApp"])
        self.country = random.choice(["US", "GB", "JP", "KR", "DE"])
        self.city = random.choice(["New York", "London", "Tokyo", "Seoul", "Berlin"])

    def generate_event(self):
        """Generate next event for this device with temporal progression"""
        if self.events_generated >= self.events_count:
            return None

        # Events spread over time after first_seen
        time_offset = int(total_seconds * (self.events_generated / self.events_count))
        event_time = self.first_seen + timedelta(seconds=time_offset + random.randint(-3600, 3600))

        # Ensure event is within valid range
        if event_time < start_time:
            event_time = start_time
        if event_time > end_time:
            event_time = end_time

        clicked = random.random() < (0.95 if self.is_bot else 0.03)

        record = {
            "event_ts": event_time.strftime("%Y-%m-%d %H:%M:%S"),
            "event_date": event_time.strftime("%Y-%m-%d"),
            "event_hour": event_time.hour,
            "device_id": self.device_id,
            "device_ip": f"{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}",
            "device_brand": self.brand,
            "device_model": self.model,
            "app_name": self.app,
            "country": self.country,
            "city": self.city,
            "click": 1 if clicked else 0,
            "impression_id": str(uuid.uuid4()),
        }

        self.events_generated += 1
        return record

# Create device profiles
print("Creating HEAVY devices (1%, bot-like, 50% of traffic)...")
heavy_devices = []
events_per_heavy = heavy_records // heavy_count
for i in range(heavy_count):
    device_id = str(uuid.uuid4())
    first_seen = random.randint(0, total_seconds // 2)  # Appear in first half
    heavy_devices.append(Device(device_id, first_seen, events_per_heavy, is_bot=True))
    if (i + 1) % 10000 == 0:
        print(f"  {i+1:,}/{heavy_count:,}")

print("Creating MEDIUM devices (10%, 30% of traffic)...")
medium_devices = []
events_per_medium = medium_records // medium_count
for i in range(medium_count):
    device_id = str(uuid.uuid4())
    first_seen = random.randint(0, total_seconds)
    medium_devices.append(Device(device_id, first_seen, events_per_medium, is_bot=False))
    if (i + 1) % 100000 == 0:
        print(f"  {i+1:,}/{medium_count:,}")

print("Creating LIGHT devices (89%, 20% of traffic)...")
light_devices = []
events_per_light = light_records // light_count
for i in range(light_count):
    device_id = str(uuid.uuid4())
    first_seen = random.randint(0, total_seconds)
    light_devices.append(Device(device_id, first_seen, events_per_light, is_bot=False))
    if (i + 1) % 500000 == 0:
        print(f"  {i+1:,}/{light_count:,}")

print("✓ All device profiles created")

def upload_chunk(chunk_id, devices, target_records):
    """Generate chunk of records maintaining temporal order per device"""
    print(f"\nChunk {chunk_id}: Generating {target_records:,} records...")

    buf = io.BytesIO()
    records_written = 0

    with gzip.GzipFile(fileobj=buf, mode='wb') as gz:
        while records_written < target_records and devices:
            # Pick a random device that still has events
            device = random.choice(devices)

            record = device.generate_event()
            if record is None:
                # This device is done, remove from pool
                devices.remove(device)
                continue

            gz.write((json.dumps(record) + '\n').encode('utf-8'))
            records_written += 1

            if records_written % 500000 == 0:
                print(f"  {records_written:,}/{target_records:,} (active devices: {len(devices):,})")

    buf.seek(0)
    data = buf.read()

    # Verify gzip
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(data), mode='rb') as test:
            test.read(1000)
        print(f"  ✓ Gzip OK")
    except Exception as e:
        print(f"  ✗ Gzip FAIL: {e}")
        raise

    # Upload
    key = f"{S3_PREFIX}/device360_chunk_{chunk_id:04d}.json.gz"
    print(f"  Uploading to s3://{S3_BUCKET}/{key}...")
    s3.upload_fileobj(io.BytesIO(data), S3_BUCKET, key)
    print(f"  ✓ Uploaded {len(data)/1024/1024:.2f} MB")

    return len(data)

total = 0
chunk = 1

print(f"\n{'='*80}")
print("Generating HEAVY traffic (temporal progression per device)")
print(f"{'='*80}")
remaining = heavy_records
heavy_pool = heavy_devices.copy()
while remaining > 0 and heavy_pool:
    size = min(RECORDS_PER_CHUNK, remaining)
    total += upload_chunk(chunk, heavy_pool, size)
    remaining -= size
    chunk += 1
    print(f"Heavy: {heavy_records - remaining:,}/{heavy_records:,}, Total: {total/1024**3:.2f} GB")

print(f"\n{'='*80}")
print("Generating MEDIUM traffic (temporal progression per device)")
print(f"{'='*80}")
remaining = medium_records
medium_pool = medium_devices.copy()
while remaining > 0 and medium_pool:
    size = min(RECORDS_PER_CHUNK, remaining)
    total += upload_chunk(chunk, medium_pool, size)
    remaining -= size
    chunk += 1
    print(f"Medium: {medium_records - remaining:,}/{medium_records:,}, Total: {total/1024**3:.2f} GB")

print(f"\n{'='*80}")
print("Generating LIGHT traffic (temporal progression per device)")
print(f"{'='*80}")
remaining = light_records
light_pool = light_devices.copy()
while remaining > 0 and light_pool:
    size = min(RECORDS_PER_CHUNK, remaining)
    total += upload_chunk(chunk, light_pool, size)
    remaining -= size
    chunk += 1
    print(f"Light: {light_records - remaining:,}/{light_records:,}, Total: {total/1024**3:.2f} GB")

print(f"\n{'='*80}")
print("✓ COMPLETE!")
print(f"{'='*80}")
print(f"Records: {NUM_RECORDS:,}")
print(f"Chunks: {chunk - 1}")
print(f"Size: {total/1024**3:.2f} GB")
print(f"Location: s3://{S3_BUCKET}/{S3_PREFIX}/")
print(f"{'='*80}")
