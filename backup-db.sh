#!/bin/bash
# Backs up the database and the uploaded images and fonts into the db-backup-vol
# volume, one file per weekday (rotated weekly).

set -o pipefail

cd "$(dirname "$0")"
dockerBin=$(/usr/bin/which docker)
weekday=$(date +%u)
status=0

# Database dump. The script is piped into the container, so no bind mount is needed.
$dockerBin compose exec -T db /bin/sh -s < conf/db/backup_mysql_cron.sh || status=1

# Uploaded images and fonts live in their own volumes, all mounted in the php container.
# The archive is written to a temporary file first, so a failed run keeps the last good one.
if $dockerBin compose exec -T php sh -c 'cd /var/www/html && tar -czf - public/resources/images/export public/resources/images/room-categories var/storage/fonts' \
    | $dockerBin compose exec -T db sh -c "cat > /dbbackup/files_$weekday.tar.gz.tmp"; then
    $dockerBin compose exec -T db mv "/dbbackup/files_$weekday.tar.gz.tmp" "/dbbackup/files_$weekday.tar.gz" || status=1
else
    echo "Backup of uploaded images and fonts failed." >&2
    $dockerBin compose exec -T db rm -f "/dbbackup/files_$weekday.tar.gz.tmp"
    status=1
fi

exit $status
