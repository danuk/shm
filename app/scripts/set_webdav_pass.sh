#!/bin/bash

USER=$1

if [ -z "$USER" ]; then
    echo "Usage: $0 USERNAME"
    exit 1
fi

htdigest -c /app/data/.htpasswd dav ${USER}

