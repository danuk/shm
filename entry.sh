#!/bin/sh

cat <<EOF >> /etc/environment
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_HOST=${DB_HOST}
DB_NAME=${DB_NAME}
EOF

/etc/init.d/fcgiwrap start

nginx -g "daemon off;"

