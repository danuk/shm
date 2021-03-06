#!/bin/sh -e

cat <<EOF > /etc/environment
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
    sudo --preserve-env=PERL5LIB -u nginx /app/bin/spool.pl
else
    # Create SHM database structure and fill data
    sudo --preserve-env=PERL5LIB -u nginx /app/bin/init.pl

    /etc/init.d/fcgiwrap start
    nginx -g 'daemon off;'
fi

