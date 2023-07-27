#!/bin/bash

cd "$(dirname "$0")"
dockerBin=$(/usr/bin/which docker)
$dockerBin compose exec -T db /bin/sh -c "chmod 0744 /db/backup_mysql_cron.sh && /db/backup_mysql_cron.sh"
