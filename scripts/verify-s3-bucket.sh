#!/bin/bash
set -o pipefail

# Script to verify that the OIDC S3 bucket is defined and exists
# If .global.hypershift.createBucket is true, will create the bucket if it doesn't exist
# Usage: ./verify-s3-bucket.sh [values-file]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Extract values from values file
BUCKET_NAME=$(yq '.global.hypershift.oidc.bucketName' "${VALUES_FILE}")
REGION=$(yq '.global.hypershift.oidc.region' "${VALUES_FILE}")
CREATE_BUCKET=$(yq '.global.hypershift.createBucket' "${VALUES_FILE}")

# Check if bucket name is defined and not empty
if [ -z "${BUCKET_NAME}" ] || [ "${BUCKET_NAME}" == "null" ] || [ "${BUCKET_NAME}" == "''" ] || [ "${BUCKET_NAME}" == "" ]; then
    echo "Error: .global.hypershift.oidc.bucketName is not defined in ${VALUES_FILE}"
    exit 1
fi

# Remove any quotes from the values
BUCKET_NAME=$(echo "${BUCKET_NAME}" | tr -d "'" | tr -d '"')

if [ -z "${BUCKET_NAME}" ]; then
    echo "Error: .global.hypershift.oidc.bucketName is empty in ${VALUES_FILE}"
    exit 1
fi

# Clean up region value
if [ -n "${REGION}" ] && [ "${REGION}" != "null" ] && [ "${REGION}" != "''" ]; then
    REGION=$(echo "${REGION}" | tr -d "'" | tr -d '"')
else
    REGION=""
fi

echo "Checking S3 bucket: ${BUCKET_NAME}"

# Function to check if bucket is public
check_bucket_public() {
    local bucket="$1"
    
    PUBLIC_ACCESS_BLOCK=$(aws s3api get-public-access-block --bucket "${bucket}" 2>&1)
    ret=$?

    # If get-public-access-block returns error "NoSuchPublicAccessBlockConfiguration", bucket is public
    if [ $ret -ne 0 ]; then
        if echo "${PUBLIC_ACCESS_BLOCK}" | grep -q "NoSuchPublicAccessBlockConfiguration"; then
            return 0  # Bucket is public
        else
            echo "Error: Failed to check public access block configuration"
            echo "${PUBLIC_ACCESS_BLOCK}"
            return 2  # Error checking
        fi
    fi

    # Check if any public access blocks are enabled
    BLOCK_PUBLIC_ACLS=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.BlockPublicAcls')
    IGNORE_PUBLIC_ACLS=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.IgnorePublicAcls')
    BLOCK_PUBLIC_POLICY=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.BlockPublicPolicy')
    RESTRICT_PUBLIC_BUCKETS=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.RestrictPublicBuckets')

    if [ "${BLOCK_PUBLIC_ACLS}" == "true" ] || [ "${IGNORE_PUBLIC_ACLS}" == "true" ] || \
       [ "${BLOCK_PUBLIC_POLICY}" == "true" ] || [ "${RESTRICT_PUBLIC_BUCKETS}" == "true" ]; then
        return 1  # Bucket is not public
    fi

    return 0  # Bucket is public
}

# Function to display not public error
show_not_public_error() {
    local bucket="$1"
    echo "Error: S3 bucket '${bucket}' is not public"
    echo ""
    echo "Current public access block settings:"
    echo "  BlockPublicAcls: ${BLOCK_PUBLIC_ACLS}"
    echo "  IgnorePublicAcls: ${IGNORE_PUBLIC_ACLS}"
    echo "  BlockPublicPolicy: ${BLOCK_PUBLIC_POLICY}"
    echo "  RestrictPublicBuckets: ${RESTRICT_PUBLIC_BUCKETS}"
    echo ""
    echo "To make the bucket public, run:"
    echo "  aws s3api put-public-access-block --bucket ${bucket} \\"
    echo "    --public-access-block-configuration 'BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false'"
}

# Check if bucket exists
BUCKET_EXISTS=false
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    BUCKET_EXISTS=true
fi

# Handle createBucket=true
if [ "${CREATE_BUCKET}" == "true" ]; then
    echo "createBucket is enabled"
    
    if [ "${BUCKET_EXISTS}" == "true" ]; then
        echo "S3 bucket '${BUCKET_NAME}' already exists, checking if public..."
        
        check_bucket_public "${BUCKET_NAME}"
        public_ret=$?
        
        if [ $public_ret -eq 0 ]; then
            echo "Success: S3 bucket '${BUCKET_NAME}' exists and is public (skipping creation)"
            exit 0
        elif [ $public_ret -eq 1 ]; then
            show_not_public_error "${BUCKET_NAME}"
            exit 1
        else
            exit 1
        fi
    else
        # Bucket doesn't exist, create it
        if [ -z "${REGION}" ]; then
            echo "Error: .global.hypershift.oidc.region is required to create the bucket"
            exit 1
        fi
        
        echo "Creating S3 bucket '${BUCKET_NAME}' in region '${REGION}'..."
        "${SCRIPT_DIR}/create-public-s3-bucket.sh" "${BUCKET_NAME}" "${REGION}"
        
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create S3 bucket"
            exit 1
        fi
        
        echo "Success: S3 bucket '${BUCKET_NAME}' created with public policy"
        exit 0
    fi
fi

# createBucket is not true - just verify bucket exists and is public
if [ "${BUCKET_EXISTS}" != "true" ]; then
    echo "Error: S3 bucket '${BUCKET_NAME}' does not exist or is not accessible"
    echo ""
    echo "To create the bucket, either:"
    echo "  1. Set .global.hypershift.createBucket to true in ${VALUES_FILE}"
    echo "  2. Or run manually:"
    if [ -n "${REGION}" ]; then
        echo "     ./pattern.sh make create-s3-bucket BUCKET_NAME=${BUCKET_NAME} REGION=${REGION}"
    else
        echo "     ./pattern.sh make create-s3-bucket BUCKET_NAME=${BUCKET_NAME} REGION=<your-region>"
    fi
    exit 1
fi

echo "S3 bucket '${BUCKET_NAME}' exists"

# Check if bucket is public
echo "Checking if bucket is public..."

check_bucket_public "${BUCKET_NAME}"
public_ret=$?

if [ $public_ret -eq 0 ]; then
    echo "Success: S3 bucket '${BUCKET_NAME}' exists and is public"
    exit 0
elif [ $public_ret -eq 1 ]; then
    show_not_public_error "${BUCKET_NAME}"
    exit 1
else
    exit 1
fi
