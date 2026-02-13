FROM danuk/shm-api:latest AS api
COPY nginx/nginx.conf /etc/nginx/
COPY entry-api.sh /entry.sh


FROM danuk/shm-core-base:latest AS core
COPY entry-core.sh /entry.sh
COPY app /app

