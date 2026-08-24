FROM jitsi/jibri:stable

# Install dbus — Chrome 143+ requires a running dbus session or it hangs on launch.
# Also install fontconfig (fixes cache warnings), and the SSM agent for ECS Exec.
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends dbus dbus-x11 fontconfig curl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/dbus \
    && dbus-uuidgen > /etc/machine-id

# Install AWS SSM agent for ECS Exec (allows `aws ecs execute-command` into container)
RUN curl -fsSL "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb" -o /tmp/ssm-agent.deb \
    && dpkg -i /tmp/ssm-agent.deb \
    && rm /tmp/ssm-agent.deb

# Install AWS CLI v2 via standalone zip bundle.
# CRITICAL: Do NOT use pip or apt-get install python3-pip here.
# pip pulls in shared library upgrades (libglib2.0, libnss3, libatk, etc.)
# that break Chrome's pre-installed dependencies and cause recording timeouts.
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && aws --version

# Ensure jibri user can write chromedriver logs and /tmp files
RUN mkdir -p /tmp/.org.chromium.Chromium /home/jibri/.config/pulse \
    && chown -R jibri:jibri /tmp/.org.chromium.Chromium /home/jibri/.config/pulse

# Start dbus daemon before other services (s6 init runs services in numeric order)
COPY dbus-run.sh /etc/services.d/05-dbus/run
RUN chmod +x /etc/services.d/05-dbus/run

# Start SSM agent for ECS Exec (allows live debugging)
COPY ssm-agent-run.sh /etc/services.d/06-ssm-agent/run
RUN chmod +x /etc/services.d/06-ssm-agent/run

# Install finalize.sh for S3 recording upload
COPY finalize.sh /config/finalize.sh
RUN chmod +x /config/finalize.sh

# Override Jibri launch script with verbose chromedriver logging
COPY launch-override.sh /opt/jitsi/jibri/launch.sh
RUN chmod +x /opt/jitsi/jibri/launch.sh
