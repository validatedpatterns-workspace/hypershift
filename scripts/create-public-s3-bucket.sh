#!/bin/bash
set -o pipefail

# Script to create an S3 bucket with a public read policy
# Usage: ./create-public-s3-bucket.sh <bucket-name> <region>

BUCKET_NAME="${1}"
REGION="${2}"

if [ -z "${BUCKET_NAME}" ] || [ -z "${REGION}" ]; then
    echo "Usage: $0 <bucket-name> <region>"
    echo "Example: $0 my-public-bucket us-east-1"
    exit 1
fi

echo "Creating S3 bucket: ${BUCKET_NAME} in region: ${REGION}"

# Create the bucket
# Note: us-east-1 doesn't need LocationConstraint
if [ "${REGION}" == "us-east-1" ]; then
    aws s3api create-bucket \
        --bucket "${BUCKET_NAME}" \
        --region "${REGION}"
else
    aws s3api create-bucket \
        --bucket "${BUCKET_NAME}" \
        --region "${REGION}" \
        --create-bucket-configuration LocationConstraint="${REGION}"
fi

if [ $? -ne 0 ]; then
    echo "Failed to create bucket"
    exit 1
fi

echo "Bucket created successfully"

# Disable block public access
echo "Disabling block public access..."
aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

if [ $? -ne 0 ]; then
    echo "Failed to disable block public access"
    exit 1
fi

# Apply public read policy
echo "Applying public read policy..."
POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
        }
    ]
}
EOF
)

aws s3api put-bucket-policy \
    --bucket "${BUCKET_NAME}" \
    --policy "${POLICY}"

if [ $? -ne 0 ]; then
    echo "Failed to apply bucket policy"
    exit 1
fi

echo "S3 bucket '${BUCKET_NAME}' created with public read policy in region '${REGION}'"
