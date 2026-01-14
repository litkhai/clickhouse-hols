#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found. Please copy .env.template to .env and fill in your credentials."
    exit 1
fi

echo "=================================================="
echo "ClickPipes S3 Test - Create ClickPipe (Terraform)"
echo "=================================================="

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Error: Terraform is not installed"
    echo ""
    echo "Install Terraform:"
    echo "  macOS:  brew install terraform"
    echo "  Linux:  https://www.terraform.io/downloads"
    exit 1
fi

cd terraform

# Create terraform.tfvars from .env
echo "Creating terraform.tfvars from .env..."

cat > terraform.tfvars << EOF
# Auto-generated from ../.env
organization_id       = "$CHC_ORGANIZATION_ID"
service_id            = "$CHC_SERVICE_ID"
api_key               = "$CHC_API_KEY"
pipe_name             = "$TEST_PIPE_NAME"
table_name            = "$TEST_TABLE_NAME"
s3_bucket             = "$AWS_S3_BUCKET"
aws_region            = "$AWS_REGION"
test_prefix           = "$TEST_PREFIX"
aws_access_key_id     = "$AWS_ACCESS_KEY_ID"
aws_secret_access_key = "$AWS_SECRET_ACCESS_KEY"
EOF

echo "✓ terraform.tfvars created"

# Initialize Terraform
echo ""
echo "Initializing Terraform..."
terraform init

# Plan
echo ""
echo "Planning Terraform changes..."
terraform plan

# Apply
echo ""
read -p "Apply these changes? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    cd ..
    exit 0
fi

echo ""
echo "Creating ClickPipe..."
terraform apply -auto-approve

# Get pipe ID
PIPE_ID=$(terraform output -raw pipe_id)

if [ -z "$PIPE_ID" ] || [ "$PIPE_ID" = "null" ]; then
    echo ""
    echo "❌ Error: Failed to get pipe ID from Terraform output"
    cd ..
    exit 1
fi

# Save pipe ID for other scripts
echo "$PIPE_ID" > ../.pipe_id

cd ..

echo ""
echo "✅ ClickPipe created successfully!"
echo "Pipe ID: $PIPE_ID"
echo "Pipe ID saved to .pipe_id"

echo ""
echo "Waiting for pipe to start ingesting data..."
sleep 10

echo ""
echo "Checking pipe status..."
./04-check-pipe-status.sh

echo ""
echo "=================================================="
echo "✅ ClickPipe Creation Complete (Terraform)!"
echo "=================================================="
echo ""
echo "The pipe is now running and ingesting data from S3."
echo ""
echo "Next steps:"
echo "  1. Monitor ingestion: ./04-check-pipe-status.sh"
echo "  2. Query data: ./05-query-data.sh"
echo "  3. When ready to test, pause: ./06-pause-pipe.sh"
echo ""
echo "To destroy via Terraform:"
echo "  cd terraform && terraform destroy"
