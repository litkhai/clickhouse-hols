#!/usr/bin/env python3
"""
AWS S3 Integration Setup for ClickHouse Cloud
Creates IAM role and policies for secure S3 access
"""

import os
import json
import sys
import boto3
from botocore.exceptions import ClientError


class S3IntegrationSetup:
    def __init__(self):
        self.iam_client = boto3.client('iam')
        self.sts_client = boto3.client('sts')
        self.s3_client = boto3.client('s3')

        self.account_id = self.sts_client.get_caller_identity()['Account']
        self.bucket_name = os.getenv('S3_BUCKET_NAME')
        self.role_name = 'ClickHouseS3AccessRole'
        self.policy_name = 'ClickHouseS3AccessPolicy'

    def create_trust_policy(self, clickhouse_role_id):
        """Create trust policy for ClickHouse to assume role"""
        return {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"arn:aws:iam::{clickhouse_role_id}:root"
                    },
                    "Action": "sts:AssumeRole",
                    "Condition": {}
                }
            ]
        }

    def create_s3_access_policy(self):
        """Create IAM policy for S3 bucket access"""
        return {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetObject",
                        "s3:ListBucket",
                        "s3:GetBucketLocation"
                    ],
                    "Resource": [
                        f"arn:aws:s3:::{self.bucket_name}",
                        f"arn:aws:s3:::{self.bucket_name}/*"
                    ]
                }
            ]
        }

    def create_or_update_role(self, clickhouse_role_id):
        """Create or update IAM role for ClickHouse"""
        trust_policy = self.create_trust_policy(clickhouse_role_id)

        try:
            # Try to create role
            response = self.iam_client.create_role(
                RoleName=self.role_name,
                AssumeRolePolicyDocument=json.dumps(trust_policy),
                Description='Allows ClickHouse Cloud to access S3 data'
            )
            print(f"✓ Created IAM role: {self.role_name}")
            role_arn = response['Role']['Arn']

        except ClientError as e:
            if e.response['Error']['Code'] == 'EntityAlreadyExists':
                print(f"Role {self.role_name} already exists, updating trust policy...")

                # Update trust policy
                self.iam_client.update_assume_role_policy(
                    RoleName=self.role_name,
                    PolicyDocument=json.dumps(trust_policy)
                )

                # Get role ARN
                response = self.iam_client.get_role(RoleName=self.role_name)
                role_arn = response['Role']['Arn']
                print(f"✓ Updated IAM role: {self.role_name}")
            else:
                raise

        return role_arn

    def attach_policy(self):
        """Attach S3 access policy to role"""
        policy_document = self.create_s3_access_policy()

        try:
            # Create inline policy
            self.iam_client.put_role_policy(
                RoleName=self.role_name,
                PolicyName=self.policy_name,
                PolicyDocument=json.dumps(policy_document)
            )
            print(f"✓ Attached policy: {self.policy_name}")

        except ClientError as e:
            print(f"✗ Failed to attach policy: {e}")
            raise

    def verify_bucket_access(self):
        """Verify S3 bucket exists and is accessible"""
        try:
            self.s3_client.head_bucket(Bucket=self.bucket_name)
            print(f"✓ S3 bucket verified: {self.bucket_name}")
            return True
        except ClientError:
            print(f"✗ S3 bucket not accessible: {self.bucket_name}")
            return False

    def setup(self):
        """Run complete setup"""
        print("="*60)
        print("ClickHouse S3 Integration Setup")
        print("="*60)
        print(f"AWS Account ID: {self.account_id}")
        print(f"S3 Bucket: {self.bucket_name}")
        print(f"IAM Role: {self.role_name}")
        print("="*60)

        if not self.bucket_name:
            print("ERROR: S3_BUCKET_NAME not set in environment")
            sys.exit(1)

        # Verify bucket access
        if not self.verify_bucket_access():
            print("ERROR: Cannot access S3 bucket")
            sys.exit(1)

        # Get ClickHouse role ID from user
        print("\nTo complete setup, you need the ClickHouse Role ID from your Cloud console.")
        print("Find it at: ClickHouse Cloud Console -> Settings -> S3 Integration")
        print("\nExample format: 123456789012")

        clickhouse_role_id = input("\nEnter ClickHouse Role ID (or press Enter to skip): ").strip()

        if not clickhouse_role_id:
            print("\nSkipping role creation. You can create it manually or run this script again.")
            clickhouse_role_id = "000000000000"  # Placeholder

        # Create/update role
        role_arn = self.create_or_update_role(clickhouse_role_id)

        # Attach policy
        self.attach_policy()

        print("\n" + "="*60)
        print("Setup Complete!")
        print("="*60)
        print(f"Role ARN: {role_arn}")
        print(f"\nAdd this to your .env file:")
        print(f"S3_ROLE_ARN={role_arn}")
        print("\nNext steps:")
        print("1. Configure this role in ClickHouse Cloud Console")
        print("2. Update your .env file with the role ARN")
        print("3. Run the data ingestion script")
        print("="*60)


def main():
    try:
        setup = S3IntegrationSetup()
        setup.setup()
    except Exception as e:
        print(f"\nERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
