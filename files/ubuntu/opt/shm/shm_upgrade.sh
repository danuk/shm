#!/bin/bash

./mysql_backup.sh

docker compose pull
docker compose up -d --remove-orphans

