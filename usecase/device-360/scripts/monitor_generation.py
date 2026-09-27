#!/usr/bin/env python3
"""
Real-time monitoring for Device360 data generation
Shows detailed progress, speed, and ETA
"""

import boto3
import time
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

def load_env():
    """Load environment variables from .env file"""
    env_file = Path(__file__).parent.parent / '.env'
    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key] = value

def format_size(bytes_size):
    """Format bytes to human readable size"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"

def format_duration(seconds):
    """Format seconds to human readable duration"""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)

    if hours > 0:
        return f"{hours}h {minutes}m {secs}s"
    elif minutes > 0:
        return f"{minutes}m {secs}s"
    else:
        return f"{secs}s"

def get_s3_stats(s3_client, bucket, prefix):
    """Get statistics from S3"""
    try:
        response = s3_client.list_objects_v2(
            Bucket=bucket,
            Prefix=prefix
        )

        if 'Contents' not in response:
            return 0, 0, []

        files = [obj for obj in response['Contents']
                if 'device360_chunk_' in obj['Key']]

        total_size = sum(obj['Size'] for obj in files)
        file_count = len(files)

        # Get latest files
        latest_files = sorted(files, key=lambda x: x['LastModified'], reverse=True)[:5]

        return file_count, total_size, latest_files

    except Exception as e:
        print(f"Error getting S3 stats: {e}")
        return 0, 0, []

def monitor_generation():
    """Monitor data generation progress"""

    load_env()

    # Configuration
    bucket = os.getenv('S3_BUCKET_NAME', 'device360-test-orangeaws')
    prefix = os.getenv('S3_PREFIX', 'device360')
    target_chunks = 250
    target_size_gb = 300

    s3_client = boto3.client('s3', region_name=os.getenv('AWS_REGION', 'ap-northeast-2'))

    print("=" * 100)
    print("Device360 Data Generation - Real-time Monitor")
    print("=" * 100)
    print(f"Target: {target_chunks} chunks (~{target_size_gb} GB)")
    print(f"Bucket: s3://{bucket}/{prefix}/")
    print(f"Refresh: Every 30 seconds")
    print("=" * 100)
    print()

    start_time = time.time()
    prev_count = 0
    prev_size = 0
    prev_check_time = start_time

    history = []  # Store history for trend analysis

    try:
        while True:
            current_time = time.time()
            elapsed = current_time - start_time

            # Clear screen
            os.system('clear' if os.name != 'nt' else 'cls')

            print("=" * 100)
            print("Device360 Data Generation Progress")
            print("=" * 100)
            print(f"Monitoring Time: {format_duration(elapsed)}")
            print(f"Last Update: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print()

            # Get current stats
            file_count, total_size, latest_files = get_s3_stats(s3_client, bucket, prefix)

            if file_count == 0:
                print("⏳ Waiting for data generation to start...")
                print()
                print("If you haven't started yet, SSH into EC2 and run:")
                print("  ssh -i ~/.ssh/kenlee_seoul_key.pem ubuntu@15.165.33.167")
                print("  curl -s https://device360-test-orangeaws.s3.ap-northeast-2.amazonaws.com/scripts/manual_ec2_setup.sh | sudo bash")
                print()
            else:
                # Calculate statistics
                total_size_gb = total_size / (1024**3)
                progress_pct = (file_count / target_chunks) * 100
                size_pct = (total_size_gb / target_size_gb) * 100

                # Calculate speeds
                time_since_last_check = current_time - prev_check_time
                new_files = file_count - prev_count
                new_size = total_size - prev_size

                if elapsed > 0:
                    avg_speed_mb = (total_size / (1024**2)) / elapsed
                    chunks_per_min = (file_count / elapsed) * 60
                else:
                    avg_speed_mb = 0
                    chunks_per_min = 0

                instant_speed_mb = (new_size / (1024**2)) / time_since_last_check if time_since_last_check > 0 else 0

                # Store history
                history.append({
                    'time': current_time,
                    'files': file_count,
                    'size': total_size,
                    'speed': instant_speed_mb
                })

                # Keep last 10 measurements
                if len(history) > 10:
                    history.pop(0)

                # Calculate ETA
                if chunks_per_min > 0:
                    remaining_chunks = target_chunks - file_count
                    eta_minutes = remaining_chunks / chunks_per_min
                    eta_seconds = eta_minutes * 60
                    eta_time = datetime.now() + timedelta(seconds=eta_seconds)
                    eta_str = f"{format_duration(eta_seconds)} (완료 예상: {eta_time.strftime('%H:%M:%S')})"
                else:
                    eta_str = "계산 중..."

                print("📊 Progress Statistics")
                print("-" * 100)
                print(f"{'Files Uploaded:':<25} {file_count:>3} / {target_chunks} chunks ({progress_pct:>5.1f}%)")
                print(f"{'Total Size:':<25} {total_size_gb:>6.2f} / {target_size_gb} GB ({size_pct:>5.1f}%)")
                print(f"{'Average Speed:':<25} {avg_speed_mb:>6.2f} MB/s")
                print(f"{'Instant Speed:':<25} {instant_speed_mb:>6.2f} MB/s")
                print(f"{'Chunks per Minute:':<25} {chunks_per_min:>6.2f} chunks/min")
                print(f"{'ETA:':<25} {eta_str}")
                print()

                print("📈 Last Interval (30s)")
                print("-" * 100)
                print(f"{'New Files:':<25} {new_files} chunks")
                print(f"{'Data Uploaded:':<25} {format_size(new_size)}")
                print()

                # Progress bar
                bar_length = 70
                filled_length = int(bar_length * file_count / target_chunks)
                bar = '█' * filled_length + '░' * (bar_length - filled_length)
                print(f"Progress: [{bar}] {progress_pct:.1f}%")
                print()

                # Show speed trend
                if len(history) >= 3:
                    recent_speeds = [h['speed'] for h in history[-3:]]
                    avg_recent_speed = sum(recent_speeds) / len(recent_speeds)

                    if avg_recent_speed > avg_speed_mb * 1.1:
                        trend = "📈 속도 증가 중"
                    elif avg_recent_speed < avg_speed_mb * 0.9:
                        trend = "📉 속도 감소 중"
                    else:
                        trend = "➡️  안정적"

                    print(f"Speed Trend: {trend} (최근 평균: {avg_recent_speed:.2f} MB/s)")
                    print()

                # Show latest files
                print("📁 Latest Uploaded Files")
                print("-" * 100)
                for obj in latest_files[:5]:
                    filename = obj['Key'].split('/')[-1]
                    size = format_size(obj['Size'])
                    modified = obj['LastModified'].strftime('%Y-%m-%d %H:%M:%S')
                    print(f"  {filename:<35} {size:>12}  {modified}")
                print()

                # Check if complete
                if file_count >= target_chunks:
                    print("=" * 100)
                    print("✅ DATA GENERATION COMPLETE!")
                    print("=" * 100)
                    print(f"Total Files: {file_count} chunks")
                    print(f"Total Size: {total_size_gb:.2f} GB")
                    print(f"Total Time: {format_duration(elapsed)}")
                    print(f"Average Speed: {avg_speed_mb:.2f} MB/s")
                    print()
                    print("Next steps:")
                    print("  1. Terminate EC2: python3 scripts/terminate_ec2.py")
                    print("  2. Start ClickHouse ingestion testing")
                    print("=" * 100)
                    break

                prev_count = file_count
                prev_size = total_size
                prev_check_time = current_time

            print()
            print("Refreshing in 30 seconds... (Press Ctrl+C to stop)")
            time.sleep(30)

    except KeyboardInterrupt:
        print("\n\nMonitoring stopped by user")
        print(f"Final count: {file_count} files, {format_size(total_size)}")

if __name__ == "__main__":
    monitor_generation()
