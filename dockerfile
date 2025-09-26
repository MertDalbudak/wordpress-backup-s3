# Build stage for downloading MinIO client
FROM alpine:latest AS builder

RUN apk add --no-cache curl && \
    curl -o /mc https://dl.min.io/client/mc/release/linux-amd64/mc && \
    chmod +x /mc

# Final runtime stage
FROM alpine:latest

# Install only essential runtime packages in a single layer
RUN apk add --no-cache \
    mariadb-client \
    tar \
    gzip \
    dcron \
    bash \
    su-exec \
    netcat-openbsd \
    busybox-suid && \
    rm -rf /var/cache/apk/* /tmp/*

# Copy MinIO client from builder stage
COPY --from=builder /mc /usr/local/bin/mc

# Copy scripts and set up directories in minimal layers
COPY backup-script.sh entrypoint.sh /backup/

# Create directories, set permissions, and make scripts executable in one layer
RUN mkdir -p /backup/data /var/log/backup /var/spool/cron/crontabs && \
    touch /var/log/cron.log && \
    chmod 600 /var/spool/cron/crontabs/root && \
    chmod +x /backup/*.sh && \
    chmod 755 /backup/data /var/log/backup && \
    chmod 1777 /tmp

WORKDIR /backup
ENTRYPOINT ["./entrypoint.sh"]