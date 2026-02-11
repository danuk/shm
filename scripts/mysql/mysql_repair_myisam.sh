#!/bin/bash

SQL_QUERY="SELECT CONCAT('REPAIR TABLE ', table_name, ';') FROM information_schema.tables WHERE table_schema = 'shm' AND ENGINE = 'MyISAM';"
REPAIR_QUERY=$(echo "$SQL_QUERY" | docker compose exec -T mysql bash -c 'MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysql -u root -N shm')
echo "$REPAIR_QUERY" | docker compose exec -T mysql bash -c 'MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysql -u root -N shm'

