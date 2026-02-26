#!/bin/sh
# Creates the database backup user on first database initialization.
# Runs automatically via /docker-entrypoint-initdb.d/ on first start.
mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e "GRANT LOCK TABLES, SELECT ON *.* TO '${MYSQL_BACKUP_USER}'@'%' IDENTIFIED BY '${MYSQL_BACKUP_PASSWORD}';"
