# Jibri Recording — Admin Runbook

Jibri provides server-side recording for Jitsi Meet. This stack uses one Jibri instance shared across both NE3D and Cloud Del Norte rooms.

---

## Current State (2026-08-24)

| component                   | value                                                                          |
| --------------------------- | ------------------------------------------------------------------------------ |
| ECS task definition (web)   | jitsi-web:25 — 4 containers (prosody, jicofo, jvb, web), NO jibri sidecar      |
| ECS task definition (jibri) | jitsi-video-platform-jibri:13 — standalone on EC2, custom image                |
| custom Jibri image          | 170473530355.dkr.ecr.us-west-2.amazonaws.com/jitsi-jibri:latest                |
| Dockerfile                  | `modules/jibri/Dockerfile` (in this repo, committed)                           |
| XMPP_RECORDER_DOMAIN        | `hidden.meet.jitsi` (NOT `recorder.meet.jitsi` — the VirtualHost name matters) |
| PUBLIC_URL                  | `http://jitsi.jitsi.local` (internal Cloud Map DNS — see Network section)      |
| CHROMIUM_FLAGS              | see Chrome Flags section below                                                 |
| DISABLE_LOCAL_RECORDING     | `true` on jitsi-web (forces server-side Jibri instead of in-browser)           |
| config.js confirms          | `localRecording.disable=true`, `recordingService.enabled=true`                 |
| S3 bucket                   | jitsi-video-platform-recordings-4b917dff                                       |
| EC2 instance type           | t3.medium (m5.xlarge in terraform, t3.medium currently deployed)               |

**Status (2026-08-24):** Chrome launches and Selenium session is created successfully. Recording fails at the `driver.get(url)` step — Chrome crashes or times out when navigating to the meeting URL. Root cause identified: network/TLS issue between Jibri's Chrome and the Jitsi web container (see Remaining Fix section).

---

## What Works

- Custom Docker image builds and deploys from `modules/jibri/Dockerfile`
- AWS CLI v2 standalone bundle (no pip, no shared lib contamination)
- dbus daemon running inside container (Chrome 143 requirement)
- PulseAudio with null-sink virtual audio (no snd-aloop kernel module needed)
- Xorg with dummy video driver on DISPLAY=:0
- Jibri JVM starts, connects to XMPP, authenticates, joins brewery MUC
- Jicofo detects Jibri as IDLE/HEALTHY and dispatches recording requests
- ChromeDriver 143 starts and creates a Selenium session
- Chrome 143 launches within the session

## What Fails

- Chrome crashes or hangs when `driver.get("http://jitsi.jitsi.local/cloud-del-norte-awsug")` is called
- Error: `java.io.UncheckedIOException: Failed to execute request (POST http://localhost:PORT/session/ID/url)`
- Jicofo marks Jibri as failed after 15-second timeout, reports "all recorders busy" to users

---

## Root Cause Analysis (2026-08-24 debugging session)

### Timeline of investigation

| Hypothesis                                   | Tested                                                    | Result                                                                         |
| -------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------ |
| pip3 install broke Chrome shared libs        | Rebuilt with standalone AWS CLI zip                       | Chrome binary works (`--version` outputs correctly)                            |
| Network: task ENI can't reach public URL     | Changed PUBLIC_URL to internal `http://jitsi.jitsi.local` | Same hang (but now we know Chrome DOES start)                                  |
| Missing dbus daemon (Chrome 143 requirement) | Installed dbus + dbus-x11, added s6 service               | dbus running, RealtimeKit activated — not the blocker                          |
| Chrome flags (sandbox, GPU, DevTools port)   | Tried every combination documented for Docker Jibri       | No effect on the hang                                                          |
| Missing /dev/snd (ALSA loopback)             | Replaced instance (new user_data)                         | snd-aloop module not available on Amazon Linux 2 ECS AMI                       |
| PulseAudio failing without audio device      | Added null-sink config to user-level default.pa           | PA starts via dbus but pactl check still exit=1 at boot                        |
| Chrome never launching at all                | Added console logging to JVM                              | REVEALED: Chrome DOES launch, session IS created                               |
| Selenium can't talk to ChromeDriver          | Console logs showed the actual error                      | POST to chromedriver succeeds for session creation, fails on `driver.get(url)` |

### Actual failure point

Chrome starts, ChromeDriver creates a session (session ID visible in logs), then Chrome crashes when navigating to `http://jitsi.jitsi.local/cloud-del-norte-awsug`. The Selenium HTTP call to chromedriver fails with `UncheckedIOException`.

### Most likely root causes (in order)

1. **HTTP vs HTTPS**: Jitsi web may require HTTPS or redirect to it. The internal URL `http://jitsi.jitsi.local` bypasses TLS but the web app config might not work over plain HTTP. Original PUBLIC_URL was `https://meet.clouddelnorte.org`.

2. **Network routing**: The Jibri task (awsvpc, private IP only, no NAT gateway) cannot reach the public internet. If Chrome needs to load external resources (CDN JS, fonts, etc.) it hangs.

3. **Memory pressure**: 3GB container with 2GB shm + JVM (~512MB) + Chrome (~300MB) + Xorg + ffmpeg is tight. Chrome may OOM during page load.

---

## Remaining Fix (P0 — blocks Aug 30 event)

**Option A (recommended): Add NAT gateway to the Jibri subnet**

This gives the task ENI outbound internet access. Set PUBLIC_URL back to `https://meet.clouddelnorte.org`. Chrome loads the meeting page over the public internet like it was designed to. Cost: ~$32/month.

**Option B: Configure internal TLS on jitsi-web**

Add TLS termination at the web container so `https://jitsi.jitsi.local:443` works internally. Requires a self-signed cert + Chrome `--ignore-certificate-errors` flag (already in the flags list). More complex, saves $32/month.

**Option C: Bridge networking**

Switch the Jibri task from `awsvpc` to `bridge` network mode. The task uses the EC2 instance's network stack (which has internet via the instance's public IP). Requires terraform change to the task definition.

---

## Chrome Flags (task-def rev 13)

```
--use-fake-ui-for-media-stream
--start-maximized
--kiosk
--autoplay-policy=no-user-gesture-required
--disable-infobars
--ignore-certificate-errors
--disable-dev-shm-usage
--disable-setuid-sandbox
--disable-background-timer-throttling
--disable-backgrounding-occluded-windows
--disable-renderer-backgrounding
```

---

## Custom Docker Image Layers

The Dockerfile at `modules/jibri/Dockerfile` adds these layers to `jitsi/jibri:stable`:

| Layer                                           | Purpose                                                        |
| ----------------------------------------------- | -------------------------------------------------------------- |
| dbus + dbus-x11 + fontconfig + pulseaudio-utils | Chrome 143 dbus requirement + font cache + PA control          |
| SSM agent                                       | ECS Exec support (requires task role ssmmessages permissions)  |
| AWS CLI v2 standalone zip                       | S3 upload in finalize.sh (no pip, no shared lib contamination) |
| PulseAudio null-sink config                     | Virtual audio without snd-aloop kernel module                  |
| Custom .asoundrc                                | Routes ALSA through PulseAudio (not hardware loopback)         |
| dbus-run.sh (s6 service 05)                     | Starts dbus system bus before other services                   |
| ssm-agent-run.sh (s6 service 06)                | Starts SSM agent for ECS Exec                                  |
| launch-override.sh                              | JVM startup with verbose chromedriver logging + diagnostics    |
| logging.properties                              | Console handler so Selenium output goes to CloudWatch          |
| finalize.sh                                     | S3 upload of completed recordings                              |

---

## Build and Deploy

```bash
cd modules/jibri
bash build-push.sh
```

This script:

1. Authenticates to ECR (account 170473530355, us-west-2)
2. Builds the Docker image
3. Pushes to `170473530355.dkr.ecr.us-west-2.amazonaws.com/jitsi-jibri:latest`
4. Forces new ECS deployment

Future: CodeBuild pipeline (tracked in issue #41).

---

## Key Architectural Facts

- **snd-aloop does NOT exist on Amazon Linux 2 ECS-optimized AMI**. The launch template's `modprobe snd-aloop` fails silently. PulseAudio null-sink replaces the hardware loopback entirely.
- **awsvpc mode gives each task its own ENI**. The task ENI has a private IP only. Without a NAT gateway, the task cannot reach the public internet (even though the EC2 instance can via its own public IP).
- **PulseAudio reads user config from `/home/jibri/.config/pulse/default.pa`**, NOT `/etc/pulse/default.pa`. The user-level config takes priority.
- **Jibri's logging goes to files by default** (`/var/log/jitsi/jibri/`). Our custom `logging.properties` redirects to ConsoleHandler so it goes to CloudWatch.
- **The Chrome pre-warm** in `40-jibri/run` (`google-chrome --timeout=1000 --headless about:blank`) runs before the JVM starts. It exits cleanly and does not interfere with recording sessions.

---

## Enable / Disable

Jibri is **off by default** (`enable_jibri = false` in terraform). Enable with:

```bash
# in jitsi-video-hosting-ops/terraform/terraform.tfvars
enable_jibri = true
terraform apply
```

Scale to zero without destroying:

```bash
aws ecs update-service --cluster jitsi-cluster --service jitsi-video-platform-jibri-service --desired-count 0 --region us-west-2 --profile jitsi-video-hosting
```

---

## How a Moderator Records

1. Join a Jitsi room as moderator (JWT with `recording: true` claim)
2. Click the three-dot menu (More actions) then Start recording
3. Red REC indicator shows while recording is active
4. Click Stop recording to end — Jibri finalizes and uploads to S3

---

## Where Recordings Land

```
s3://jitsi-video-platform-recordings-4b917dff/recordings/YYYY-MM-DD/<room-name>/
```

90-day lifecycle expiration.

---

## Cost

| state                     | additional monthly cost                                      |
| ------------------------- | ------------------------------------------------------------ |
| Jibri enabled, stack up   | ~$30/mo (1x t3.medium EC2) + ~$32/mo (NAT gateway, if added) |
| Jibri enabled, stack down | ~$0 compute; S3 storage only                                 |
| Jibri disabled            | $0                                                           |

---

## Troubleshooting

**"All recorders are currently busy"**

Jicofo dispatched to Jibri but Chrome failed. Check CloudWatch logs for `FailedToJoinCall`. Jicofo blacklists the instance for 1 minute after failure.

**Record button not visible**

Confirm `ENABLE_RECORDING=1` on prosody and JWT has `recording: true`.

**Recording starts but no S3 upload**

Check task role has `s3:PutObject` on recordings bucket. Check `RECORDINGS_BUCKET` env var matches.

**Chrome session created but navigation fails**

Network issue. Chrome can't reach the URL in PUBLIC_URL. Either add NAT gateway or fix internal routing.
