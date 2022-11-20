#!/bin/sh -e

cat <<EOF > /etc/environment
TZ=${TZ}
SHM_ROOT_DIR=${SHM_ROOT_DIR}
SHM_DATA_DIR=${SHM_DATA_DIR}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
EOF

if [ "${SHM_ROLE}" = "spool" ]; then
    # Start SHM spool daemon
    /app/bin/spool.pl
else
    # Create SHM database structure and fill data
    /app/bin/init.pl

    uwsgi --ini=/etc/uwsgi/apps-enabled/shm.ini
fi

