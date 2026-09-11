#!/usr/bin/env bash
# inject short-lived creds from the working SSO CLI session into the env, then
# run the labeler. boto3 reads AWS_* env vars -> never touches the root-owned
# SSO cache file that breaks the python profile path.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${AWS_PROFILE_OVERRIDE:-bryanchasko-kiro}"

eval "$(aws configure export-credentials --profile "$PROFILE" --format env)"

exec python3 "$HERE/label_screenshots.py" "$@"
