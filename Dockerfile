FROM nginx
WORKDIR /app

RUN apt-get update && apt-get install -y \
    fcgiwrap \
    default-libmysqlclient-dev \
    perl \
    libdbi-perl \
    gcc \
    make

COPY deploy /app/deploy
RUN set -x \
    && cd /app/deploy \
    && /app/deploy/install_deps.sh \
    && apt-get remove --purge --auto-remove -y gcc make \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /app/deploy \
    && sed -i 's/www-data/nginx/g' /etc/init.d/fcgiwrap \
    && mkdir /var/shm && chown nginx: /var/shm

COPY nginx/default.conf /etc/nginx/conf.d/

ENV ROOT /var/shm
ENV PERL5LIB /app/lib:/app/conf
ENV DB_USER shm
ENV DB_PASS password
ENV DB_HOST 127.0.0.1
ENV DB_NAME shm

COPY entry.sh /entry.sh
ENTRYPOINT ["/entry.sh"]

COPY app /app

