#!/bin/bash
set -o pipefail

# Script to verify that the OIDC S3 bucket is defined and exists
# Usage: ./verify-s3-bucket.sh [values-file]

VALUES_FILE="${1:-values-hypershift.yaml}"

if [ ! -f "${VALUES_FILE}" ]; then
    echo "Error: Values file '${VALUES_FILE}' not found"
    exit 1
fi

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed"
    exit 1
fi

# Extract bucket name and region from values file
BUCKET_NAME=$(yq '.global.hypershift.oidc.bucketName' "${VALUES_FILE}")
REGION=$(yq '.global.hypershift.oidc.region' "${VALUES_FILE}")

# Check if bucket name is defined and not empty
if [ -z "${BUCKET_NAME}" ] || [ "${BUCKET_NAME}" == "null" ] || [ "${BUCKET_NAME}" == "''" ] || [ "${BUCKET_NAME}" == "" ]; then
    echo "Error: .global.hypershift.oidc.bucketName is not defined in ${VALUES_FILE}"
    exit 1
fi

# Remove any quotes from the value
BUCKET_NAME=$(echo "${BUCKET_NAME}" | tr -d "'" | tr -d '"')

if [ -z "${BUCKET_NAME}" ]; then
    echo "Error: .global.hypershift.oidc.bucketName is empty in ${VALUES_FILE}"
    exit 1
fi

echo "Checking S3 bucket: ${BUCKET_NAME}"

# Clean up region value for later use
if [ -n "${REGION}" ] && [ "${REGION}" != "null" ] && [ "${REGION}" != "''" ]; then
    REGION=$(echo "${REGION}" | tr -d "'" | tr -d '"')
fi

# Check if bucket exists
if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo "Error: S3 bucket '${BUCKET_NAME}' does not exist or is not accessible"
    echo ""
    echo "To create the bucket, run:"
    if [ -n "${REGION}" ]; then
        echo "  ./pattern.sh make create-s3-bucket BUCKET_NAME=${BUCKET_NAME} REGION=${REGION}"
    else
        echo "  ./pattern.sh make create-s3-bucket BUCKET_NAME=${BUCKET_NAME} REGION=<your-region>"
    fi
    exit 1
fi

echo "S3 bucket '${BUCKET_NAME}' exists"

# Check if bucket is public (public access block is disabled)
echo "Checking if bucket is public..."

PUBLIC_ACCESS_BLOCK=$(aws s3api get-public-access-block --bucket "${BUCKET_NAME}" 2>&1)
ret=$?

# If get-public-access-block returns error "NoSuchPublicAccessBlockConfiguration", bucket is public
if [ $ret -ne 0 ]; then
    if echo "${PUBLIC_ACCESS_BLOCK}" | grep -q "NoSuchPublicAccessBlockConfiguration"; then
        echo "Success: S3 bucket '${BUCKET_NAME}' is public (no public access block configured)"
        exit 0
    else
        echo "Error: Failed to check public access block configuration"
        echo "${PUBLIC_ACCESS_BLOCK}"
        exit 1
    fi
fi

# Check if any public access blocks are enabled
BLOCK_PUBLIC_ACLS=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.BlockPublicAcls')
IGNORE_PUBLIC_ACLS=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.IgnorePublicAcls')
BLOCK_PUBLIC_POLICY=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.BlockPublicPolicy')
RESTRICT_PUBLIC_BUCKETS=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.RestrictPublicBuckets')

if [ "${BLOCK_PUBLIC_ACLS}" == "true" ] || [ "${IGNORE_PUBLIC_ACLS}" == "true" ] || \
   [ "${BLOCK_PUBLIC_POLICY}" == "true" ] || [ "${RESTRICT_PUBLIC_BUCKETS}" == "true" ]; then
    echo "Error: S3 bucket '${BUCKET_NAME}' is not public"
    echo ""
    echo "Current public access block settings:"
    echo "  BlockPublicAcls: ${BLOCK_PUBLIC_ACLS}"
    echo "  IgnorePublicAcls: ${IGNORE_PUBLIC_ACLS}"
    echo "  BlockPublicPolicy: ${BLOCK_PUBLIC_POLICY}"
    echo "  RestrictPublicBuckets: ${RESTRICT_PUBLIC_BUCKETS}"
    echo ""
    echo "To make the bucket public, run:"
    echo "  aws s3api put-public-access-block --bucket ${BUCKET_NAME} \\"
    echo "    --public-access-block-configuration 'BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false'"
    exit 1
fi

echo "Success: S3 bucket '${BUCKET_NAME}' exists and is public"
