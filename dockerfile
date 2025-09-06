FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    mariadb-client \
    tar \
    gzip \
    curl \
    dcron \
    bash \
    su-exec \
    netcat-openbsd \
    busybox-suid

# Install MinIO client
RUN curl -o /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc && \
    chmod +x /usr/local/bin/mc

# Create necessary directories and log file
RUN mkdir -p /backup/data /var/log/backup /var/spool/cron/crontabs /tmp && \
    touch /var/log/cron.log && \
    chmod 600 /var/spool/cron/crontabs/root

# Copy scripts
COPY backup-script.sh /backup/backup-script.sh
COPY entrypoint.sh /backup/entrypoint.sh

# Make scripts executable
RUN chmod +x /backup/*.sh

# Set proper permissions for directories
RUN chmod 755 /backup/data \
    && chmod 755 /var/log/backup \
    && chmod 1777 /tmp

WORKDIR /backup
ENTRYPOINT ["./entrypoint.sh"]