#!/bin/bash

cd "$(dirname "$0")"
dockerBin=$(/usr/bin/which docker)
$dockerBin compose exec -T db /bin/sh /db/backup_mysql_cron.sh
