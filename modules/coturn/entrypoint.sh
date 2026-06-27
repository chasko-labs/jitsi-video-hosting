#!/bin/sh
# entrypoint.sh — write TLS files + turnserver.conf from injected env vars, then exec turnserver.
#
# EXTERNAL-IP NOTE: We use the Fargate task metadata endpoint (ECS_CONTAINER_METADATA_URI_V4)
# to retrieve the task's ENI public IPv4. This is preferred over hardcoding the NLB EIP because
# this module deliberately skips the NLB (see main.tf: option-b rationale). The public IP changes
# on redeploy; update your DNS A record (turn.clouddelnorte.org) after each deployment.

set -e

CERT_DIR=/etc/coturn
mkdir -p "$CERT_DIR"

# Write TLS material injected by ECS secrets
printf '%s' "$TURN_TLS_CERT_PEM" >"$CERT_DIR/cert.pem"
printf '%s' "$TURN_TLS_PKEY_PEM" >"$CERT_DIR/pkey.pem"
chmod 600 "$CERT_DIR/cert.pem" "$CERT_DIR/pkey.pem"

# Resolve ENI public IP via ECS task metadata v4
EXTERNAL_IP=""
if [ -n "$ECS_CONTAINER_METADATA_URI_V4" ]; then
	TASK_META=$(wget -qO- "${ECS_CONTAINER_METADATA_URI_V4}/task" 2>/dev/null || true)
	# Extract first PublicIpv4Address from the Containers array
	EXTERNAL_IP=$(printf '%s' "$TASK_META" | grep -o '"PublicIpv4Address":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

if [ -z "$EXTERNAL_IP" ]; then
	# Fallback: AWS instance metadata (IMDS v2) — works on Fargate too
	TOKEN=$(wget -qO- --header "X-aws-ec2-metadata-token-ttl-seconds: 10" \
		--method PUT http://169.254.169.254/latest/api/token 2>/dev/null || true)
	EXTERNAL_IP=$(wget -qO- --header "X-aws-ec2-metadata-token: $TOKEN" \
		http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
fi

if [ -z "$EXTERNAL_IP" ]; then
	echo "ERROR: could not determine external IP; coturn will not work correctly" >&2
	exit 1
fi

cat >"$CERT_DIR/turnserver.conf" <<EOF
listening-ip=0.0.0.0
listening-port=3478
tls-listening-port=5349
fingerprint
use-auth-secret
static-auth-secret=${TURN_STATIC_AUTH_SECRET}
realm=${TURN_REALM}
cert=${CERT_DIR}/cert.pem
pkey=${CERT_DIR}/pkey.pem
min-port=${RELAY_MIN_PORT}
max-port=${RELAY_MAX_PORT}
external-ip=${EXTERNAL_IP}
no-tlsv1
no-tlsv1_1
no-cli
no-multicast-peers
log-file=stdout
EOF

exec turnserver -c "$CERT_DIR/turnserver.conf"
