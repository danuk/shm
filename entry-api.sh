#!/bin/sh -e

[ -z "$RESOLVER" ] || sed -i "s|resolver 127.0.0.11|resolver $RESOLVER|" /etc/nginx/conf.d/default.conf

nginx -g "daemon off;"

