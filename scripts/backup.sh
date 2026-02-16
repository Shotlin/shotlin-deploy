#!/bin/bash
# ═══════════════════════════════════════════════════════
#  Shotlin — Automated Database Backup
#  Keeps last 7 daily + 4 weekly + 3 monthly backups
# ═══════════════════════════════════════════════════════

set -euo pipefail

BACKUP_DIR="/backups"
RETENTION_DAILY=7
RETENTION_WEEKLY=4
RETENTION_MONTHLY=3

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

backup() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local day_of_week=$(date '+%u')  # 1=Monday, 7=Sunday
    local day_of_month=$(date '+%d')
    local filename="shotlin_db_${timestamp}.sql.gz"
    local filepath="${BACKUP_DIR}/${filename}"

    log "Starting backup: ${filename}"

    # Create compressed backup
    pg_dump -Fc | gzip > "${filepath}"

    if [ $? -eq 0 ] && [ -s "${filepath}" ]; then
        local size=$(du -h "${filepath}" | cut -f1)
        log "✅ Backup created: ${filename} (${size})"

        # Copy as weekly backup on Sundays
        if [ "${day_of_week}" -eq 7 ]; then
            cp "${filepath}" "${BACKUP_DIR}/weekly_${filename}"
            log "📅 Weekly backup saved"
        fi

        # Copy as monthly backup on 1st of month
        if [ "${day_of_month}" -eq "01" ]; then
            cp "${filepath}" "${BACKUP_DIR}/monthly_${filename}"
            log "📅 Monthly backup saved"
        fi
    else
        log "❌ Backup FAILED!"
        rm -f "${filepath}"
        return 1
    fi
}

cleanup() {
    log "Cleaning old backups..."

    # Keep only N daily backups (files without weekly_ or monthly_ prefix)
    ls -t "${BACKUP_DIR}"/shotlin_db_*.sql.gz 2>/dev/null | \
        tail -n +$((RETENTION_DAILY + 1)) | xargs -r rm -f

    # Keep only N weekly backups
    ls -t "${BACKUP_DIR}"/weekly_*.sql.gz 2>/dev/null | \
        tail -n +$((RETENTION_WEEKLY + 1)) | xargs -r rm -f

    # Keep only N monthly backups
    ls -t "${BACKUP_DIR}"/monthly_*.sql.gz 2>/dev/null | \
        tail -n +$((RETENTION_MONTHLY + 1)) | xargs -r rm -f

    log "Cleanup complete"
}

# ─── Main Loop: Run backup daily at 2 AM ───
log "🔄 Backup service started"
log "Schedule: Daily at 2:00 AM | Retention: ${RETENTION_DAILY}d / ${RETENTION_WEEKLY}w / ${RETENTION_MONTHLY}m"

while true; do
    # Calculate seconds until next 2 AM
    current_hour=$(date '+%H')
    current_min=$(date '+%M')
    current_sec=$(date '+%S')

    if [ "${current_hour}" -lt 2 ]; then
        # Before 2 AM today
        seconds_until=$((( (2 - current_hour) * 3600) - (current_min * 60) - current_sec))
    else
        # After 2 AM, wait until tomorrow 2 AM
        seconds_until=$(( ((26 - current_hour) * 3600) - (current_min * 60) - current_sec ))
    fi

    log "Next backup in $(( seconds_until / 3600 ))h $(( (seconds_until % 3600) / 60 ))m"
    sleep "${seconds_until}"

    backup && cleanup
done
