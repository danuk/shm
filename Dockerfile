FROM nginx:stable-alpine AS api
EXPOSE 80
CMD ["/entry.sh"]
RUN mkdir -p /app/data
HEALTHCHECK --interval=10s --timeout=5s --retries=3 CMD curl -f 127.0.0.1/shm/healthcheck.cgi || exit 1
COPY nginx/nginx.conf /etc/nginx/
COPY entry-api.sh /entry.sh


FROM danuk/shm-core-base:latest AS core
COPY entry-core.sh /entry.sh
COPY app /app

