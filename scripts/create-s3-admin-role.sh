#!/bin/bash
set -o pipefail

# Script to create an IAM role with a policy that can only manage S3 buckets
# Usage: ./create-s3-admin-role.sh <role-name> [trusted-account-id]

ROLE_NAME="${1}"
TRUSTED_ACCOUNT="${2:-$(aws sts get-caller-identity --query Account --output text)}"

if [ -z "${ROLE_NAME}" ]; then
    echo "Usage: $0 <role-name> [trusted-account-id]"
    echo "Example: $0 s3-admin-role 123456789012"
    echo "If trusted-account-id is not provided, the current account will be used"
    exit 1
fi

POLICY_NAME="${ROLE_NAME}-policy"

echo "Creating IAM role: ${ROLE_NAME}"
echo "Trusted account: ${TRUSTED_ACCOUNT}"

# Trust policy - allows the account to assume this role
TRUST_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${TRUSTED_ACCOUNT}:root"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)

# Create the IAM role
aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_POLICY}" \
    --description "Role for S3 bucket management only"

if [ $? -ne 0 ]; then
    echo "Failed to create IAM role"
    exit 1
fi

echo "IAM role created successfully"

# S3 management policy - full S3 bucket management permissions
S3_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3BucketManagement",
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:DeleteBucket",
                "s3:ListBucket",
                "s3:ListAllMyBuckets",
                "s3:GetBucketLocation",
                "s3:GetBucketPolicy",
                "s3:PutBucketPolicy",
                "s3:DeleteBucketPolicy",
                "s3:GetBucketAcl",
                "s3:PutBucketAcl",
                "s3:GetBucketVersioning",
                "s3:PutBucketVersioning",
                "s3:GetBucketPublicAccessBlock",
                "s3:PutBucketPublicAccessBlock",
                "s3:DeletePublicAccessBlock",
                "s3:GetBucketTagging",
                "s3:PutBucketTagging",
                "s3:GetBucketLogging",
                "s3:PutBucketLogging",
                "s3:GetBucketEncryption",
                "s3:PutBucketEncryption",
                "s3:DeleteBucketEncryption",
                "s3:GetLifecycleConfiguration",
                "s3:PutLifecycleConfiguration",
                "s3:GetBucketCORS",
                "s3:PutBucketCORS",
                "s3:DeleteBucketCORS"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3ObjectManagement",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:GetObjectAcl",
                "s3:PutObjectAcl",
                "s3:GetObjectTagging",
                "s3:PutObjectTagging",
                "s3:DeleteObjectTagging",
                "s3:ListMultipartUploadParts",
                "s3:AbortMultipartUpload"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)

echo "Creating IAM policy: ${POLICY_NAME}"

# Create the policy
POLICY_ARN=$(aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document "${S3_POLICY}" \
    --description "Policy for S3 bucket management only" \
    --query 'Policy.Arn' \
    --output text)

if [ $? -ne 0 ]; then
    echo "Failed to create IAM policy"
    exit 1
fi

echo "IAM policy created: ${POLICY_ARN}"

# Attach the policy to the role
echo "Attaching policy to role..."
aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "${POLICY_ARN}"

if [ $? -ne 0 ]; then
    echo "Failed to attach policy to role"
    exit 1
fi

echo ""
echo "Successfully created:"
echo "  Role: ${ROLE_NAME}"
echo "  Policy: ${POLICY_NAME}"
echo "  Policy ARN: ${POLICY_ARN}"
echo ""
echo "To assume this role, use:"
echo "  aws sts assume-role --role-arn arn:aws:iam::${TRUSTED_ACCOUNT}:role/${ROLE_NAME} --role-session-name mysession"
