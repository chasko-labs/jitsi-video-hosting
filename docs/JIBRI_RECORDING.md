# Jibri Recording — Admin Runbook

Jibri provides server-side recording for Jitsi Meet. This stack uses one Jibri instance shared across both NE3D and Cloud Del Norte rooms.

---

## Enable / Disable

Jibri is **off by default** (`enable_jibri = false`). Merging the Jibri module into prod.tf changes nothing live until the flag is set.

**Enable:**

```bash
# in jitsi-video-hosting-ops/terraform/terraform.tfvars
enable_jibri = true

# then apply (scale-up.pl calls terraform apply)
cd /path/to/jitsi-video-hosting-ops/terraform/
terraform apply
```

**Disable (scale to zero without destroying):**

```bash
# set desired_count to 0 — or simply power-down the whole stack
./power-down.pl
```

---

## How a Moderator Records

1. Join a Jitsi room as moderator (JWT with `recording: true` claim — already set by the token-exchange lambda).
2. Click the **·⋮** (More actions) menu → **Start recording**.
3. Jitsi UI shows a red REC indicator while recording is active.
4. Click **Stop recording** to end. Jibri finalizes the file and uploads it automatically.

No manual intervention needed. The finalize script (`modules/jibri/finalize.sh`) runs inside the Jibri container on completion.

---

## Where Recordings Land

```
s3://jitsi-video-platform-recordings-<suffix>/recordings/YYYY-MM-DD/<room-name>.<format>
```

Bucket name is in Terraform output `recordings_bucket_name` and in AWS console.

Lifecycle rule: recordings expire after **90 days** (configurable in `aws_s3_bucket_lifecycle_configuration.recordings`).

---

## Cost Delta

| state                             | additional monthly cost                      |
| --------------------------------- | -------------------------------------------- |
| Jibri enabled, stack powered up   | +~$30/mo (1× t3.medium EC2, ~$0.0416/hr)     |
| Jibri enabled, stack powered down | ~$0 compute; S3 storage only (~$0.023/GB/mo) |
| Jibri disabled                    | $0                                           |

The recordings S3 bucket persists through power-down and `terraform destroy` (`prevent_destroy = true`).

---

## Why EC2, Not Fargate

Jibri requires:

- **Privileged container** — needed by Chrome's sandbox and device access
- **`snd-aloop` kernel module** — ALSA loopback for audio capture
- **`/dev/snd` device** — mounted into the container

Fargate has no host OS control and does not support privileged containers. Jibri runs on a dedicated t3.medium with an ECS-optimized AMI; `snd-aloop` is loaded in EC2 user-data before the ECS agent starts the task.

---

## Troubleshooting

**Record button not visible**

- Confirm `ENABLE_RECORDING=1` is in the prosody container env (already set in prod.tf).
- Confirm JWT has `recording: true` — check the token-exchange lambda claims.

**Recording starts but Jibri never connects**

- Verify `jibri-service` is RUNNING in ECS console.
- Check `/ecs/jitsi-app` CloudWatch log stream `jibri/*` for XMPP auth errors.
- Verify `jibri_xmpp_password` SSM param exists and prosody has `JIBRI_XMPP_USER=jibri` set.

**S3 upload fails after recording**

- Check Jibri container logs for `aws s3 cp` errors.
- Verify `jibri-ecs-task-role` has `s3:PutObject` on the recordings bucket.
- Confirm `RECORDINGS_BUCKET` env var matches the actual bucket name.
