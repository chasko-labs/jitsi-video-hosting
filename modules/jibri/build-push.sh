#!/bin/bash
set -euo pipefail

ACCOUNT_ID="170473530355"
REGION="us-west-2"
REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/jitsi-jibri"
TAG="latest"
PROFILE="jitsi-video-hosting"
CLUSTER="jitsi-cluster"
SERVICE="jitsi-video-platform-jibri-service"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[build-push] Authenticating to ECR..."
aws ecr get-login-password --region "${REGION}" --profile "${PROFILE}" |
	docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "[build-push] Building image..."
docker build -t "${REPO}:${TAG}" "${SCRIPT_DIR}"

echo "[build-push] Pushing ${REPO}:${TAG}..."
docker push "${REPO}:${TAG}"

echo "[build-push] Forcing new ECS deployment..."
aws ecs update-service \
	--cluster "${CLUSTER}" \
	--service "${SERVICE}" \
	--force-new-deployment \
	--region "${REGION}" \
	--profile "${PROFILE}" \
	--no-cli-pager

echo "[build-push] Done. New jibri task will pull the updated image on next launch."
