#!/usr/bin/env bash
# One-time bootstrap of the Terraform remote state backend (S3 + DynamoDB lock).
# Run with credentials for the target account before the first `terraform init`.
set -euo pipefail

REGION="${REGION:-ca-central-1}"
BUCKET="${BUCKET:-stratos-tfstate-prod}"
TABLE="${TABLE:-stratos-tf-locks}"

echo "Creating state bucket s3://${BUCKET} in ${REGION}"
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"},"BucketKeyEnabled":true}]}'

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Creating lock table ${TABLE}"
aws dynamodb create-table --region "$REGION" --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

echo "Done. Now: cd terraform/environments/prod && terraform init"
