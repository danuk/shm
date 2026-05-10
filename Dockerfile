FROM danuk/shm-api:latest AS api
COPY nginx/nginx.conf /etc/nginx/
COPY entry-api.sh /entry.sh


FROM danuk/shm-core-base:latest AS core
ARG SHM_VERSION=2.13.0-beta
ARG SHM_COMMIT_SHA=local
COPY entry-core.sh /entry.sh
COPY app /app
RUN printf '{"version":"%s","commitSha":"%s"}\n' "$SHM_VERSION" "$SHM_COMMIT_SHA" > /app/version.json
COPY patches/telegram_oidc_proxy.pl /tmp/telegram_oidc_proxy.pl
RUN perl /tmp/telegram_oidc_proxy.pl /app/lib/Core/Transport/Telegram.pm && rm /tmp/telegram_oidc_proxy.pl

