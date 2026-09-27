#!/usr/bin/env python3
"""
Terminate EC2 data generation instance
"""

import boto3
import os
import sys
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

def terminate_instance(instance_id):
    """Terminate EC2 instance"""

    load_env()
    ec2 = boto3.client('ec2', region_name=os.getenv('AWS_REGION', 'ap-northeast-2'))

    print("="*80)
    print(f"Terminating EC2 Instance: {instance_id}")
    print("="*80)

    # Get instance details before termination
    try:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]

        print(f"Instance Type: {instance['InstanceType']}")
        print(f"State: {instance['State']['Name']}")
        print(f"Launch Time: {instance['LaunchTime']}")
        print()

        # Confirm termination
        confirm = input("Are you sure you want to terminate this instance? (yes/no): ")
        if confirm.lower() != 'yes':
            print("Termination cancelled")
            return

        # Terminate
        print("Terminating instance...")
        ec2.terminate_instances(InstanceIds=[instance_id])
        print(f"✓ Instance {instance_id} is terminating")

        # Clean up instance file
        instance_file = Path(__file__).parent.parent / 'ec2_instance.txt'
        if instance_file.exists():
            instance_file.unlink()
            print(f"✓ Removed {instance_file}")

    except Exception as e:
        print(f"✗ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        # Try to read from file
        instance_file = Path(__file__).parent.parent / 'ec2_instance.txt'
        if instance_file.exists():
            with open(instance_file, 'r') as f:
                instance_id = f.readline().strip()
            print(f"Found instance ID in file: {instance_id}")
        else:
            print("Usage: python3 terminate_ec2.py <instance-id>")
            print("Or run after launching with launch_ec2_data_generator.py")
            sys.exit(1)
    else:
        instance_id = sys.argv[1]

    terminate_instance(instance_id)
