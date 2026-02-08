#!/bin/bash

FILE=$1

if [ -z $FILE ]; then
    echo "Usage: $0 ./backups/FILE.sql.gz"
    exit 1
fi

if [ ! -f $FILE ]; then
    echo "Error: file $FILE not exits";
    exit 2
fi

gunzip -c ${FILE} | docker compose exec -T mysql /bin/bash -c 'MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysql -u root shm'

