#!/bin/bash
set -e

# Set default backup interval if not provided
BACKUP_INTERVAL="${BACKUP_INTERVAL:-daily}"

# Configure AWS if credentials are provided
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
    aws configure set default.region "${AWS_DEFAULT_REGION:-eu-central-1}"
fi

# Create cron schedule based on interval
case "$BACKUP_INTERVAL" in
    "hourly")
        echo "0 * * * * /usr/local/bin/backup-script.sh" > /tmp/crontab
        ;;
    "daily")
        echo "0 2 * * * /usr/local/bin/backup-script.sh" > /tmp/crontab
        ;;
    "weekly")
        echo "0 2 * * 0 /usr/local/bin/backup-script.sh" > /tmp/crontab
        ;;
    "monthly")
        echo "0 2 1 * * /usr/local/bin/backup-script.sh" > /tmp/crontab
        ;;
    *)
        # Custom cron expression
        echo "$BACKUP_INTERVAL /usr/local/bin/backup-script.sh" > /tmp/crontab
        ;;
esac

# Add environment variables to crontab for the backup script
{
    echo "MYSQL_HOST=${MYSQL_HOST:-db}"
    echo "MYSQL_USER=${MYSQL_USER:-root}"
    echo "MYSQL_PASSWORD=${MYSQL_PASSWORD}"
    echo "MYSQL_DATABASE=${MYSQL_DATABASE:-wordpress}"
    echo "S3_BUCKET=${S3_BUCKET:-wordpress-backups}"
    echo "RETENTION_DAYS=${RETENTION_DAYS:-7}"
    echo "WP_CONTENT_PATH=${WP_CONTENT_PATH:-/var/www/html}"
    echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
    echo "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
    echo "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-eu-central-1}"
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    echo ""
    cat /tmp/crontab
} > /tmp/crontab_with_env

# Install the crontab
crontab /tmp/crontab_with_env

# Create log directory
mkdir -p /var/log/backup

# Log startup information
echo "[$(date '+%Y-%m-%d %H:%M:%S')] WordPress Backup Service Started"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup interval: $BACKUP_INTERVAL"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] S3 Bucket: ${S3_BUCKET:-wordpress-backups}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Retention: ${RETENTION_DAYS:-7} days"

# Show the installed crontab for debugging
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installed crontab:"
crontab -l

# Run initial backup if requested
if [ "$RUN_INITIAL_BACKUP" = "true" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running initial backup..."
    /usr/local/bin/backup-script.sh
fi

# Start cron daemon
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting cron daemon..."
exec crond -f -l 2