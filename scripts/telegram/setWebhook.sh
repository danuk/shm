#!/bin/bash

TOKEN=""
URL="bill.DOMAIN.ru"

curl https://api.telegram.org/bot${TOKEN}/deleteWebhook?drop_pending_updates=True

curl -X POST \
    -H 'content-type: application/json' \
    https://api.telegram.org/bot${TOKEN}/setWebhook \
    -d '{"url": "https://'$URL'/shm/v1/telegram/bot" }"'


