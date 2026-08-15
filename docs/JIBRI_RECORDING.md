# Jibri Recording — Admin Runbook

Jibri provides server-side recording for Jitsi Meet. This stack uses one Jibri instance shared across both NE3D and Cloud Del Norte rooms.

---

## Current State (2026-08-15)

| component                   | value                                                                                        |
| --------------------------- | -------------------------------------------------------------------------------------------- |
| ECS task definition (web)   | jitsi-web:25 — 4 containers (prosody, jicofo, jvb, web), NO jibri sidecar                    |
| ECS task definition (jibri) | jitsi-video-platform-jibri:6 — standalone on EC2                                             |
| custom Jibri image          | 170473530355.dkr.ecr.us-west-2.amazonaws.com/jitsi-jibri:latest (adds aws-cli + finalize.sh) |
| XMPP_RECORDER_DOMAIN        | `hidden.meet.jitsi` (NOT `recorder.meet.jitsi` — the VirtualHost name matters)               |
| PUBLIC_URL                  | `https://meet.clouddelnorte.org` (tells Jibri's Chrome where to connect)                     |
| DISABLE_LOCAL_RECORDING     | `true` on jitsi-web (forces server-side Jibri instead of in-browser)                         |
| config.js confirms          | `localRecording.disable=true`, `recordingService.enabled=true`                               |
| S3 bucket                   | jitsi-video-platform-recordings-4b917dff                                                     |

**Status:** dispatch chain works (UI → jicofo → jibri), but Chrome fails to launch inside the container. Suspected cause: missing Xvfb or Chrome binary issue in custom image after aws-cli install.

---

## Known Issues

**Chrome launch timeout**

After receiving the start command, Jibri loads Chrome flags but Chrome never actually starts. Jicofo's 15-second timeout fires and reports "all recorders busy." Likely cause: the custom Docker image's `pip install` may have broken Chrome's apt dependencies, or Xvfb is not starting on DISPLAY=:0.

**XMPP reconnection cycles**

Jibri drops its XMPP connection every 3–7 minutes and reconnects. Non-blocking for normal operation but may cause recording start failures if the disconnect is timed during jicofo's dispatch window.

**Jibri sidecar on Fargate crash-loops**

Removed in jitsi-web:25 (standalone EC2 is the correct architecture). Earlier task definition revisions (18–24) included a Jibri sidecar container on Fargate. If anyone reverts to an older task def, the sidecar will crash-loop because SYS_ADMIN capability is not available on Fargate.

---

## Next Fix Required

1. Rebuild the custom Jibri image ensuring Chrome + chromedriver + Xvfb are intact after the aws-cli install. Test approach:
   - Build image locally
   - `docker run --cap-add SYS_ADMIN` the image
   - Verify `google-chrome --version` and `chromedriver --version` produce output
   - Verify Xvfb starts on DISPLAY=:0
2. Alternative: use a multi-stage build that installs aws-cli in a separate stage and copies only the binary, avoiding any interaction with Chrome's apt dependencies.

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

**"All recorders are currently busy"**

Jicofo dispatched to Jibri but Chrome failed to start within the 15-second timeout. Check Jibri logs for Chrome flag loading followed by silence — no further output means Chrome never launched. See "Next Fix Required" above.

**Recording button triggers local download instead of server recording**

`DISABLE_LOCAL_RECORDING=true` is missing from jitsi-web container env. Deploy jitsi-web:25 or later which includes it. Without this flag, the UI falls back to in-browser recording (download to user's machine) instead of dispatching to Jibri.

**"No such host: recorder.meet.jitsi" in Jibri logs**

`XMPP_RECORDER_DOMAIN` must be `hidden.meet.jitsi` — this matches the VirtualHost that prosody actually creates. Both prosody AND jibri must agree on this value. The name `recorder.meet.jitsi` appears in some upstream docs but is not what this stack uses.
