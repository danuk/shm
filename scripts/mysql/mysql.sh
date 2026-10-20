#!/bin/bash

CONTAINER_NAME="mysql-master-mysql-master-1"

docker exec -it ${CONTAINER_NAME} /bin/bash -c 'MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysql -u root shm'
