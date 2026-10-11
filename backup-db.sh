#!/bin/bash

cd "$(dirname "$0")"
dockerBin=$(/usr/bin/which docker)
# The script is piped into the container, so no bind mount is needed.
$dockerBin compose exec -T db /bin/sh -s < conf/db/backup_mysql_cron.sh
