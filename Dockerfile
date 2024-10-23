FROM nginx:stable-alpine AS api
EXPOSE 80
COPY nginx/default.conf /etc/nginx/conf.d/


FROM debian:bullseye-slim AS core
WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    uwsgi \
    default-libmysqlclient-dev \
    openssh-client \
    curl \
    qrencode

RUN apt-get install -y \
    perl \
    libdbi-perl \
    libdbd-mysql-perl \
    libcgi-pm-perl \
    libtime-parsedate-perl \
    libdate-calc-perl \
    libjson-perl \
    libtest-mocktime-perl \
    libsql-abstract-perl \
    libnet-openssh-perl \
    libnet-idn-encode-perl \
    libdata-validate-domain-perl \
    libdata-validate-email-perl \
    libdata-validate-ip-perl \
    libdigest-sha-perl \
    libscalar-util-numeric-perl \
    libtemplate-perl \
    libtemplate-plugin-dbi-perl \
    libtie-dbi-perl \
    libemail-sender-perl \
    libwww-perl \
    librouter-simple-perl

RUN set -x \
    && useradd shm -d /var/shm -m \
    && rm -rf /var/lib/apt/lists/*

COPY nginx/uwsgi.ini /etc/uwsgi/apps-enabled/shm.ini

ENV SHM_ROOT_DIR=/app
ENV SHM_DATA_DIR=/var/shm
ENV PERL5LIB=/app/lib:/app/conf
ENV DB_USER=shm
ENV DB_PASS=password
ENV DB_HOST=127.0.0.1
ENV DB_PORT=3306
ENV DB_NAME=shm

COPY entry.sh /entry.sh
CMD ["/entry.sh"]

COPY app /app

