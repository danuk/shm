#!/bin/bash

FILE=$1
CONTAINER_NAME="shm-mysql-1"

if [ -z $FILE ]; then
    echo "Usage: $0 /backups/mysql/FILE.sql.gz"
    exit 1
fi

if [ ! -f $FILE ]; then
    echo "Error: file $FILE not exits";
    exit 2
fi

gunzip -c ${FILE} | docker exec -i ${CONTAINER_NAME} /bin/bash -c 'MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysql -u root shm'

