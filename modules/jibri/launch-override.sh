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
echo "[launch.sh] Starting Jibri JVM..." >&2

exec java \
	-Djava.util.logging.config.file=/etc/jitsi/jibri/logging.properties \
	-Dconfig.file="/etc/jitsi/jibri/jibri.conf" \
	-Dwebdriver.chrome.logfile=/dev/stderr \
	-Dwebdriver.chrome.verboseLogging=true \
	-jar /opt/jitsi/jibri/jibri.jar \
	--config "/etc/jitsi/jibri/config.json"
