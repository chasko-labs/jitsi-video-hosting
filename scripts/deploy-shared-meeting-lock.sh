#!/usr/bin/env bash
# deploy-shared-meeting-lock.sh — creates the shared-meeting-lock DDB table
# account: 170473530355 (jitsi-video-hosting), region: us-west-2
# both CDN and NE3D portals use this table to prevent simultaneous meetings
set -euo pipefail

TABLE_NAME="shared-meeting-lock"
REGION="us-west-2"
PROFILE="jitsi-video-hosting"

echo "creating DynamoDB table: ${TABLE_NAME} in ${REGION}"

aws dynamodb create-table \
	--table-name "${TABLE_NAME}" \
	--attribute-definitions \
	AttributeName=pk,AttributeType=S \
	--key-schema \
	AttributeName=pk,KeyType=HASH \
	--billing-mode PAY_PER_REQUEST \
	--region "${REGION}" \
	--profile "${PROFILE}" \
	--tags Key=project,Value=jitsi-shared Key=purpose,Value=cross-site-meeting-lock \
	2>&1 || {
	echo "table may already exist — checking..."
}

echo "enabling TTL on attribute 'expiresAt'..."
aws dynamodb update-time-to-live \
	--table-name "${TABLE_NAME}" \
	--time-to-live-specification Enabled=true,AttributeName=expiresAt \
	--region "${REGION}" \
	--profile "${PROFILE}" \
	2>&1 || echo "TTL may already be enabled"

echo "verifying table exists..."
aws dynamodb describe-table \
	--table-name "${TABLE_NAME}" \
	--region "${REGION}" \
	--profile "${PROFILE}" \
	--query 'Table.{Name:TableName,Status:TableStatus}' \
	--output table

echo "done — shared-meeting-lock table ready"
