#!/bin/bash

TOKEN=""
URL="bill.DOMAIN.ru"
SHM_TEMPLATE="telegram_bot"

curl https://api.telegram.org/bot${TOKEN}/deleteWebhook?drop_pending_updates=True

cat << EOF | curl -X POST \
    -H 'content-type: application/json' \
    https://api.telegram.org/bot${TOKEN}/setWebhook \
    -d @-
{
    "url": "https://${URL}/shm/v1/telegram/bot/${SHM_TEMPLATE}",
    "allowed_updates": [
        "message",
        "inline_query",
        "callback_query",
        "my_chat_member",
        "pre_checkout_query"
    ]
}
EOF

