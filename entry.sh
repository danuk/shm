#!/bin/sh

cat <<EOF > /etc/environment
SHM_DATA_DIR=${SHM_DATA_DIR}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
EOF

MYSQL_PWD=$DB_PASS
mysql="mysql -h $DB_HOST -P $DB_PORT -u $DB_USER $DB_NAME"

tables=$(echo 'SHOW TABLES' | $mysql)

if [ -z "$tables" ]; then
    $mysql < "/app/sql/shm/shm_structure.sql"
    $mysql < "/app/sql/shm/shm_data.sql"
fi

/etc/init.d/fcgiwrap start
nginx -g "daemon off;"
$@

