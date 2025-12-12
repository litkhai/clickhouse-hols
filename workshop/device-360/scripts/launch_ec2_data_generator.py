#!/usr/bin/env python3
"""
Launch EC2 instance for data generation
Creates instance, runs data generation, uploads to S3, and terminates
"""

import boto3
import time
import os
import sys
from pathlib import Path
import base64

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

def create_user_data_script():
    """Create EC2 user data script for data generation"""

    user_data = f"""#!/bin/bash
set -e

echo "Starting Device360 Data Generation on EC2"
echo "=========================================="

# Update system
apt-get update -y

# Install Python 3 and pip
apt-get install -y python3 python3-pip awscli

# Install required Python packages
pip3 install boto3

# Create working directory
mkdir -p /tmp/device360
cd /tmp/device360

# Configure AWS credentials from environment
mkdir -p /root/.aws
cat > /root/.aws/credentials << 'AWSCREDS'
[default]
aws_access_key_id = {os.getenv('AWS_ACCESS_KEY_ID')}
aws_secret_access_key = {os.getenv('AWS_SECRET_ACCESS_KEY')}
aws_session_token = {os.getenv('AWS_SESSION_TOKEN', '')}
AWSCREDS

cat > /root/.aws/config << 'AWSCONFIG'
[default]
region = {os.getenv('AWS_REGION', 'ap-northeast-2')}
AWSCONFIG

# Download scripts from S3
echo "Downloading scripts from S3..."
aws s3 cp s3://{os.getenv('S3_BUCKET_NAME')}/scripts/ec2_generate_and_upload.py /tmp/device360/generate.py
aws s3 cp s3://{os.getenv('S3_BUCKET_NAME')}/scripts/.env /tmp/device360/.env

chmod +x /tmp/device360/generate.py

# Run data generation
echo "Starting data generation..."
python3 /tmp/device360/generate.py 2>&1 | tee /tmp/device360/generation.log

# Upload log to S3
aws s3 cp /tmp/device360/generation.log s3://{os.getenv('S3_BUCKET_NAME')}/logs/ec2_generation_$(date +%Y%m%d_%H%M%S).log

echo "Data generation complete!"
"""

    return user_data

def launch_ec2_instance():
    """Launch EC2 instance for data generation"""

    load_env()

    ec2 = boto3.client('ec2', region_name=os.getenv('AWS_REGION', 'ap-northeast-2'))

    # Instance configuration
    instance_type = os.getenv('EC2_INSTANCE_TYPE', 'c5.4xlarge')  # 16 vCPU, 32GB RAM
    ami_id = os.getenv('EC2_AMI_ID', 'ami-0c9c942bd7bf113a2')  # Amazon Linux 2023 in ap-northeast-2
    key_name = os.getenv('EC2_KEY_NAME', '')  # Optional SSH key
    subnet_id = os.getenv('EC2_SUBNET_ID', '')  # Optional subnet
    security_group_id = os.getenv('EC2_SECURITY_GROUP_ID', '')  # Optional security group

    user_data = create_user_data_script()

    print("="*80)
    print("Launching EC2 Instance for Data Generation")
    print("="*80)
    print(f"Instance Type: {instance_type}")
    print(f"AMI: {ami_id}")
    print(f"Region: {os.getenv('AWS_REGION', 'ap-northeast-2')}")
    print()

    # Launch parameters
    launch_params = {
        'ImageId': ami_id,
        'InstanceType': instance_type,
        'MinCount': 1,
        'MaxCount': 1,
        'UserData': user_data,
        'TagSpecifications': [
            {
                'ResourceType': 'instance',
                'Tags': [
                    {'Key': 'Name', 'Value': 'Device360-Data-Generator'},
                    {'Key': 'Project', 'Value': 'Device360-PoC'},
                    {'Key': 'AutoTerminate', 'Value': 'true'},
                ]
            }
        ],
        'BlockDeviceMappings': [
            {
                'DeviceName': '/dev/xvda',
                'Ebs': {
                    'VolumeSize': 100,  # 100GB root volume
                    'VolumeType': 'gp3',
                    'DeleteOnTermination': True
                }
            }
        ]
    }

    # Add optional parameters
    if key_name:
        launch_params['KeyName'] = key_name
    if subnet_id:
        launch_params['SubnetId'] = subnet_id
    if security_group_id:
        launch_params['SecurityGroupIds'] = [security_group_id]

    # Launch instance
    print("Launching instance...")
    response = ec2.run_instances(**launch_params)

    instance_id = response['Instances'][0]['InstanceId']
    print(f"✓ Instance launched: {instance_id}")
    print()

    # Wait for instance to be running
    print("Waiting for instance to be running...")
    waiter = ec2.get_waiter('instance_running')
    waiter.wait(InstanceIds=[instance_id])
    print("✓ Instance is running")
    print()

    # Get instance details
    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance = response['Reservations'][0]['Instances'][0]

    print("="*80)
    print("Instance Details")
    print("="*80)
    print(f"Instance ID: {instance_id}")
    print(f"Instance Type: {instance['InstanceType']}")
    print(f"Private IP: {instance.get('PrivateIpAddress', 'N/A')}")
    print(f"Public IP: {instance.get('PublicIpAddress', 'N/A')}")
    print(f"State: {instance['State']['Name']}")
    print()

    print("="*80)
    print("Next Steps")
    print("="*80)
    print("1. Data generation has started automatically via User Data")
    print("2. Monitor progress:")
    print(f"   aws ec2 get-console-output --instance-id {instance_id}")
    print("3. Check S3 for uploaded data:")
    print(f"   aws s3 ls s3://{os.getenv('S3_BUCKET_NAME')}/device360/")
    print("4. View generation log when complete:")
    print(f"   aws s3 ls s3://{os.getenv('S3_BUCKET_NAME')}/logs/")
    print("5. Terminate instance when done:")
    print(f"   python3 scripts/terminate_ec2.py {instance_id}")
    print("="*80)
    print()

    # Save instance ID to file
    instance_file = Path(__file__).parent.parent / 'ec2_instance.txt'
    with open(instance_file, 'w') as f:
        f.write(f"{instance_id}\n")
        f.write(f"Launched at: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")

    print(f"Instance ID saved to: {instance_file}")

    return instance_id


def monitor_instance(instance_id):
    """Monitor instance console output"""

    load_env()
    ec2 = boto3.client('ec2', region_name=os.getenv('AWS_REGION', 'ap-northeast-2'))

    print(f"\nMonitoring instance {instance_id}...")
    print("Press Ctrl+C to stop monitoring\n")

    try:
        while True:
            try:
                response = ec2.get_console_output(InstanceId=instance_id)
                if 'Output' in response:
                    print(response['Output'])
                else:
                    print("Waiting for console output...")
            except Exception as e:
                print(f"Error getting console output: {e}")

            time.sleep(30)

    except KeyboardInterrupt:
        print("\nStopped monitoring")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == 'monitor':
        # Monitor existing instance
        instance_file = Path(__file__).parent.parent / 'ec2_instance.txt'
        if instance_file.exists():
            with open(instance_file, 'r') as f:
                instance_id = f.readline().strip()
            monitor_instance(instance_id)
        else:
            print("No instance ID found. Launch instance first.")
    else:
        # Launch new instance
        instance_id = launch_ec2_instance()

        # Ask if user wants to monitor
        response = input("\nWould you like to monitor the instance? (y/n): ")
        if response.lower() == 'y':
            monitor_instance(instance_id)
