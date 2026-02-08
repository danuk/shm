#!/bin/bash

DOCKER_COMPOSE_PATH="."

BACKUP_DIR="${DOCKER_COMPOSE_PATH}/backups"
FILE="${BACKUP_DIR}/shm_$(date +%Y%m%d-%H%M%S).sql.gz"

mkdir -p ${BACKUP_DIR}
cd ${DOCKER_COMPOSE_PATH}
docker compose exec -T mysql /bin/bash -c 'MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysqldump --no-create-info --complete-insert -u root shm' | gzip > ${FILE}

echo $FILE
echo "done"

