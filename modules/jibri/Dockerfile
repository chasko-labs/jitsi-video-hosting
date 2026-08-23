FROM jitsi/jibri:stable

# Install dbus — Chrome 143+ requires a running dbus session or it hangs on launch.
# The jitsi/jibri:stable image ships Chrome but not dbus. Without it, Chrome emits
# "Failed to connect to socket /run/dbus/system_bus_socket" and blocks indefinitely.
# Also install fontconfig to fix "No writable cache directories" warnings.
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends dbus dbus-x11 fontconfig \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/dbus \
    && dbus-uuidgen > /etc/machine-id

# Install AWS CLI v2 via standalone zip bundle.
# CRITICAL: Do NOT use pip or apt-get install python3-pip here.
# pip pulls in shared library upgrades (libglib2.0, libnss3, libatk, etc.)
# that break Chrome's pre-installed dependencies and cause recording timeouts.
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && aws --version

# Start dbus daemon before other services (s6 init runs services in numeric order)
COPY dbus-run.sh /etc/services.d/05-dbus/run
RUN chmod +x /etc/services.d/05-dbus/run

# Install finalize.sh for S3 recording upload
COPY finalize.sh /config/finalize.sh
RUN chmod +x /config/finalize.sh
