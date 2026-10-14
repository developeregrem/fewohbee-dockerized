#!/bin/sh
# Creates the read-only database user for backups (MYSQL_BACKUP_USER).
# Runs inside the db container; install.sh pipes it in:
#   docker compose exec -T db sh -s < conf/db/create-backup-user.sh
# Older local docker-compose.override.yml files may still mount it into
# /docker-entrypoint-initdb.d/, which sources it, so it must not call exit.
if [ -n "${MYSQL_BACKUP_USER}" ] && [ -n "${MYSQL_BACKUP_PASSWORD}" ]; then
    mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${MYSQL_BACKUP_USER}'@'%' IDENTIFIED BY '${MYSQL_BACKUP_PASSWORD}'; GRANT LOCK TABLES, SELECT ON *.* TO '${MYSQL_BACKUP_USER}'@'%';"
else
    echo "MYSQL_BACKUP_USER or MYSQL_BACKUP_PASSWORD not set, skipping backup user"
fi
