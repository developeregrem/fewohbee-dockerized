#!/bin/sh

removeCron() {
    cronName="$1"
    cronDirectory="${2:-/etc/cron.d}"
    targetCron="$cronDirectory/$cronName"

    if [ ! -e "$targetCron" ] && [ ! -L "$targetCron" ]; then
        return 0
    fi

    if ! rm -f -- "$targetCron"; then
        echo "Could not remove cronjob $targetCron. Do you have permission to write there?"
        return 1
    fi

    echo "Cronjob $targetCron was removed."
}

cleanupStatus=0
removeCron "backup_mysql_docker" || cleanupStatus=1
removeCron "update-docker" || cleanupStatus=1

dockerBin=$(command -v docker)
if [ -z "$dockerBin" ]; then
    echo "Docker must be installed!"
    exit 1
fi

# Remove network, volumes and containers.
if ! "$dockerBin" compose down -v; then
    cleanupStatus=1
fi

exit "$cleanupStatus"
