FROM danuk/shm-api:latest AS api


FROM danuk/shm-core-base:latest AS core
COPY app /app

