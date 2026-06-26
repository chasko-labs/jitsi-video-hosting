#!/bin/bash
set -euo pipefail

RECORDING_DIR="${1:?Usage: finalize.sh <recording_dir>}"

: "${RECORDINGS_BUCKET:?RECORDINGS_BUCKET env var must be set}"

echo "[finalize] Uploading ${RECORDING_DIR} to s3://${RECORDINGS_BUCKET}/recordings/$(date +%F)/"
aws s3 cp "${RECORDING_DIR}" "s3://${RECORDINGS_BUCKET}/recordings/$(date +%F)/" --recursive
echo "[finalize] Upload complete."
