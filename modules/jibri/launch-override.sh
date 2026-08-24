#!/bin/bash
# Custom launch script that adds verbose chromedriver/Selenium logging.
# Overrides /opt/jitsi/jibri/launch.sh from the upstream image.

# Debug: log what the jibri user can see
echo "[launch.sh] Running as: $(whoami)" >&2
echo "[launch.sh] PATH: $PATH" >&2
echo "[launch.sh] which chromedriver: $(which chromedriver 2>&1)" >&2
echo "[launch.sh] which google-chrome: $(which google-chrome 2>&1)" >&2
echo "[launch.sh] DISPLAY=$DISPLAY" >&2
echo "[launch.sh] DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" >&2
echo "[launch.sh] /dev/snd contents: $(ls /dev/snd/ 2>&1)" >&2
echo "[launch.sh] pulseaudio check: $(
	pulseaudio --check 2>&1
	echo exit=$?
)" >&2
echo "[launch.sh] Chrome processes: $(ps aux 2>&1 | grep -c chrom)" >&2
echo "[launch.sh] All procs: $(ps aux 2>&1 | grep -E 'chrom|java|pulse|xorg|icewm' | grep -v grep)" >&2
echo "[launch.sh] Listening ports: $(ss -tlnp 2>&1 | head -10)" >&2
echo "[launch.sh] Starting Jibri JVM..." >&2

# Wait for PulseAudio to be responsive before starting Jibri.
# ffmpeg uses -f pulse -i default; if PA isn't ready, ffmpeg dies immediately.
echo "[launch.sh] Waiting for PulseAudio..." >&2
export HOME=/home/jibri
for i in $(seq 1 30); do
	if pactl info >/dev/null 2>&1; then
		echo "[launch.sh] PulseAudio ready (attempt $i)" >&2
		# Load null sink if not already loaded
		if ! pactl list sinks short 2>/dev/null | grep -q jibri; then
			pactl load-module module-null-sink sink_name=jibri-sink 2>&1 >&2 || true
			pactl set-default-sink jibri-sink 2>&1 >&2 || true
			pactl set-default-source jibri-sink.monitor 2>&1 >&2 || true
		fi
		break
	fi
	# If PA isn't running at all, start it ourselves
	if ! pulseaudio --check 2>/dev/null; then
		pulseaudio --daemonize --exit-idle-time=-1 2>/dev/null || true
	fi
	sleep 1
done
# Log PA state
pactl list sinks short 2>&1 >&2 || true
pactl list sources short 2>&1 >&2 || true
pactl info 2>&1 | grep -i "default" >&2 || echo "[launch.sh] PA info failed" >&2

exec java \
	-Djava.util.logging.config.file=/etc/jitsi/jibri/logging.properties \
	-Dconfig.file="/etc/jitsi/jibri/jibri.conf" \
	-Dwebdriver.chrome.logfile=/dev/stderr \
	-Dwebdriver.chrome.verboseLogging=true \
	-jar /opt/jitsi/jibri/jibri.jar \
	--config "/etc/jitsi/jibri/config.json"
