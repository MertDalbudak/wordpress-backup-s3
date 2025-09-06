#!/bin/bash
set -e

# Configuration from environment variables
S3_BUCKET="${S3_BUCKET:-wordpress-backups}"
S3_ENDPOINT_URL="${S3_ENDPOINT_URL:-}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
S3_SECRET_KEY="${S3_SECRET_KEY:-}"
BACKUP_DIR="/backup/data"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
RETENTION_DAYS="${RETENTION_DAYS:-7}"
LOG_FILE="/var/log/backup/backup-${DATE}.log"

# Database configuration
MYSQL_HOST="${MYSQL_HOST:-db}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
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

# Use mariadb-dump (newer) or fall back to mysqldump
DUMP_CMD="mysqldump"
if command -v mariadb-dump >/dev/null 2>&1; then
    DUMP_CMD="mariadb-dump"
fi

# Wait for database to be ready
log "Waiting for database connection at $MYSQL_HOST:3306..."
for i in {1..30}; do
    if nc -z "$MYSQL_HOST" 3306 2>/dev/null; then
        log "Database connection established"
        break
    fi
    if [ $i -eq 30 ]; then
        error_exit "Database connection failed after 30 attempts to $MYSQL_HOST:3306"
    fi
    log "Attempt $i/30: Waiting for database..."
    sleep 2
done

# Database backup
log "Dumping MySQL database..."
if [ -z "$MYSQL_PASSWORD" ]; then
    error_exit "MYSQL_PASSWORD environment variable is required"
fi

$DUMP_CMD -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
    --skip-ssl \
    --single-transaction --routines --triggers \
    "$MYSQL_DATABASE" > "${CURRENT_BACKUP_DIR}/db.sql" || error_exit "Failed to dump database"

log "Database dump completed successfully"

# WordPress content backup
log "Archiving WordPress content..."
if [ ! -d "$WP_CONTENT_PATH" ]; then
    error_exit "WordPress content directory not found: $WP_CONTENT_PATH"
fi

tar czf "${CURRENT_BACKUP_DIR}/wp-content.tar.gz" -C "$WP_CONTENT_PATH" . || error_exit "Failed to archive WordPress content"

# Upload to S3
log "Uploading backup to S3 bucket: $S3_BUCKET..."
mc cp "${CURRENT_BACKUP_DIR}/db.sql" "s3provider/$S3_BUCKET/$DATE/db.sql" || error_exit "Failed to upload database backup to S3"
mc cp "${CURRENT_BACKUP_DIR}/wp-content.tar.gz" "s3provider/$S3_BUCKET/$DATE/wp-content.tar.gz" || error_exit "Failed to upload WordPress content to S3"
log "Backup successfully uploaded to S3"

# Clean up old backups based on retention policy
log "Cleaning up backups older than $RETENTION_DAYS days..."
mc find "s3provider/$S3_BUCKET" --older-than "${RETENTION_DAYS}d" --exec "mc rm {}" || log "Warning: Failed to clean up old backups"
log "Old backup cleanup completed"

log "WordPress backup process completed successfully"