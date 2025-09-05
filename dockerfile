FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    aws-cli \
    mysql-client \
    tar \
    gzip \
    curl \
    dcron \
    bash \
    su-exec

# Create backup directories with proper permissions
RUN mkdir -p /backup/data \
    && mkdir -p /var/log/backup \
    && mkdir -p /tmp

# Copy scripts
COPY backup-script.sh /usr/local/bin/backup-script.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/backup-script.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

# Set proper permissions for directories
RUN chmod 755 /backup/data \
    && chmod 755 /var/log/backup \
    && chmod 1777 /tmp

# Remove any existing crontab references since entrypoint.sh manages cron
# RUN rm -f /etc/cron.d/backup-cron

# Run as root initially (entrypoint will handle user switching if needed)
# The cron daemon typically needs to run as root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]