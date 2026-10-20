#!/bin/bash

CONTAINER_NAME="shm-mysql-1"
BACKUP_DIR="/backups/mysql"

mkdir -p ${BACKUP_DIR}

VER=$(docker exec ${CONTAINER_NAME} /bin/bash -c 'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql -Ns -e "SELECT value->>'\''\$.version'\'' FROM config WHERE \`key\`='\''_shm'\'';" shm' | tr -d \('\r\\)n')
FILE=${BACKUP_DIR}/shm-${VER}-$(date +%s).sql.gz

docker exec ${CONTAINER_NAME} /bin/bash -c 'MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysqldump --single-transaction --quick --set-gtid-purged=OFF --routines --triggers --events --databases shm -u root' | gzip > ${FILE}

realpath $FILE
echo "done"

