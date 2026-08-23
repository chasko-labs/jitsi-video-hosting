FROM jitsi/jibri:stable

# Install AWS CLI v2 via standalone zip bundle.
# CRITICAL: Do NOT use pip or apt-get install python3-pip here.
# pip pulls in shared library upgrades (libglib2.0, libnss3, libatk, etc.)
# that break Chrome's pre-installed dependencies and cause recording timeouts.
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && aws --version

# Install finalize.sh for S3 recording upload
COPY finalize.sh /config/finalize.sh
RUN chmod +x /config/finalize.sh
