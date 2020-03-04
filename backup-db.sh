#!/bin/bash

cd "$(dirname "$0")"
/usr/local/bin/docker-compose exec -T db /bin/sh -c "chmod 0744 /db/backup_mysql_cron.sh && /db/backup_mysql_cron.sh"
