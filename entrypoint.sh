#!/bin/sh
set -e

# Set default backup interval
: "${BACKUP_INTERVAL:=daily}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/cron.log
}

# Configure MinIO client if credentials are provided
if [ -n "$S3_ACCESS_KEY" ] && [ -n "$S3_SECRET_KEY" ]; then
    if [ -n "$S3_ENDPOINT_URL" ]; then
        # Custom S3 endpoint
        mc alias set s3provider "$S3_ENDPOINT_URL" "$S3_ACCESS_KEY" "$S3_SECRET_KEY" || {
            log "ERROR: Failed to configure MinIO client for custom S3 endpoint: $S3_ENDPOINT_URL"
            exit 1
        }
        log "Configured MinIO client for custom S3 endpoint: $S3_ENDPOINT_URL"
    else
        # Generic S3
        mc alias set s3provider "https://s3.amazonaws.com" "$S3_ACCESS_KEY" "$S3_SECRET_KEY" --api S3v4 || {
            log "ERROR: Failed to configure MinIO client for generic S3"
            exit 1
        }
        log "Configured MinIO client for generic S3"
    fi
else
    log "ERROR: S3_ACCESS_KEY and S3_SECRET_KEY are required"
    exit 1
fi

# Create cron schedule based on interval
case "$BACKUP_INTERVAL" in
    "hourly")
        CRON_SCHEDULE="0 * * * *"
        ;;
    "daily")
        CRON_SCHEDULE="0 2 * * *"
        ;;
    "weekly")
        CRON_SCHEDULE="0 2 * * 0"
        ;;
    "monthly")
        CRON_SCHEDULE="0 2 1 * *"
        ;;
    *)
        CRON_SCHEDULE="$BACKUP_INTERVAL"
        ;;
esac

# Setup cron
log "Setting up cron job with schedule: ${CRON_SCHEDULE}"
echo "${CRON_SCHEDULE} /backup/backup-script.sh >> /var/log/cron.log 2>&1" > /var/spool/cron/crontabs/root
chmod 600 /var/spool/cron/crontabs/root

# Log startup information
log "WordPress Backup Service Started"
log "Backup interval: $BACKUP_INTERVAL"
log "S3 Bucket: ${S3_BUCKET:-wordpress-backups}"
log "S3 Endpoint: ${S3_ENDPOINT_URL:-default}"
log "Retention: ${RETENTION_DAYS:-7} days"

# Run initial backup if requested
if [ "$RUN_INITIAL_BACKUP" = "true" ]; then
    log "Running initial backup..."
    /backup/backup-script.sh || {
        log "ERROR: Initial backup failed"
        exit 1
    }
fi

# Start cron in background
log "Starting cron..."
crond

# Keep container alive
tail -f /var/log/cron.log