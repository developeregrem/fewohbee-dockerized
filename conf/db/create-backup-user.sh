#!/bin/sh
# Superseded by the db-init service in the compose files, which creates the backup
# user on every start. Kept because local docker-compose.override.yml files from
# older installations may still mount it into /docker-entrypoint-initdb.d/.
mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e "GRANT LOCK TABLES, SELECT ON *.* TO '${MYSQL_BACKUP_USER}'@'%' IDENTIFIED BY '${MYSQL_BACKUP_PASSWORD}';"
