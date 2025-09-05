#!/bin/bash
set -e

# Configuration from environment variables
S3_BUCKET="${S3_BUCKET:-wordpress-backups}"
BACKUP_DIR="/backup/data"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
RETENTION_DAYS="${RETENTION_DAYS:-7}"
LOG_FILE="/var/log/backup/backup-${DATE}.log"

# Database configuration
MYSQL_HOST="${MYSQL_HOST:-db}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD}"
MYSQL_DATABASE="${MYSQL_DATABASE:-wordpress}"

# WordPress content path
WP_CONTENT_PATH="${WP_CONTENT_PATH:-/var/www/html}"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    if [ -d "$CURRENT_BACKUP_DIR" ]; then
        rm -rf "$CURRENT_BACKUP_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

log "Starting WordPress backup process..."

# Create timestamped backup directory
CURRENT_BACKUP_DIR="${BACKUP_DIR}/${DATE}"
mkdir -p "$CURRENT_BACKUP_DIR"

# Database backup
log "Dumping MySQL database..."
if [ -z "$MYSQL_PASSWORD" ]; then
    error_exit "MYSQL_PASSWORD environment variable is required"
fi

mysqldump -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" > "${CURRENT_BACKUP_DIR}/db.sql" || error_exit "Failed to dump database"

# WordPress content backup
log "Archiving WordPress content..."
if [ ! -d "$WP_CONTENT_PATH" ]; then
    error_exit "WordPress content directory not found: $WP_CONTENT_PATH"
fi

tar czf "${CURRENT_BACKUP_DIR}/wp-content.tar.gz" -C "$WP_CONTENT_PATH" . || error_exit "Failed to archive WordPress content"

# Upload to S3
log "Uploading backups to S3 bucket: $S3_BUCKET"
aws s3 cp "$CURRENT_BACKUP_DIR/" "s3://$S3_BUCKET/wordpress/" --recursive || error_exit "Failed to upload to S3"

# Create backup manifest
log "Creating backup manifest..."
DB_SIZE=$(du -sh "${CURRENT_BACKUP_DIR}/db.sql" | cut -f1)
CONTENT_SIZE=$(du -sh "${CURRENT_BACKUP_DIR}/wp-content.tar.gz" | cut -f1)
TOTAL_SIZE=$(du -sh "$CURRENT_BACKUP_DIR" | cut -f1)

cat > "${CURRENT_BACKUP_DIR}/manifest-${DATE}.json" << EOF
{
    "backup_date": "$DATE",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "files": {
        "database": "db.sql",
        "wp_content": "wp-content.tar.gz"
    },
    "sizes": {
        "database": "$DB_SIZE",
        "wp_content": "$CONTENT_SIZE",
        "total": "$TOTAL_SIZE"
    },
    "mysql_host": "$MYSQL_HOST",
    "mysql_database": "$MYSQL_DATABASE",
    "wp_content_path": "$WP_CONTENT_PATH"
}
EOF

aws s3 cp "${CURRENT_BACKUP_DIR}/manifest-${DATE}.json" "s3://$S3_BUCKET/wordpress/" || log "WARNING: Failed to upload manifest"

# Clean up old local backups
log "Cleaning old local backups (keeping last $RETENTION_DAYS)..."
ls -1dt "$BACKUP_DIR"/* 2>/dev/null | tail -n +$((RETENTION_DAYS + 1)) | xargs rm -rf || true

# Clean up old S3 backups if retention is set
if [ "$RETENTION_DAYS" -gt 0 ]; then
    log "Cleaning up S3 backups older than $RETENTION_DAYS days..."
    
    # Calculate cutoff date (format: YYYY-MM-DD)
    cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d)
    
    # List and delete old backups from S3
    aws s3 ls "s3://$S3_BUCKET/wordpress/" --recursive | while read -r line; do
        # Extract filename and date from S3 listing
        file_path=$(echo "$line" | awk '{print $4}')
        file_date=$(echo "$file_path" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | head -1)
        
        if [ -n "$file_date" ] && [ "$file_date" \< "$cutoff_date" ]; then
            log "Deleting old S3 backup: $file_path"
            aws s3 rm "s3://$S3_BUCKET/wordpress/$file_path" || log "WARNING: Failed to delete $file_path"
        fi
    done
fi

log "Backup completed successfully!"
log "Local backup: $CURRENT_BACKUP_DIR"
log "S3 location: s3://$S3_BUCKET/wordpress/"
log "Database size: $DB_SIZE"
log "Content size: $CONTENT_SIZE"
log "Total backup size: $TOTAL_SIZE"
log "Log file: $LOG_FILE"