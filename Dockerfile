FROM nginx:stable-alpine AS api
EXPOSE 80
CMD ["/entry.sh"]
HEALTHCHECK --interval=10s --timeout=5s --retries=3 CMD curl -f 127.0.0.1/shm/healthcheck.cgi || exit 1
COPY nginx/default.conf /etc/nginx/conf.d/
COPY entry-api.sh /entry.sh


FROM debian:bullseye-slim AS core
WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    uwsgi \
    default-libmysqlclient-dev \
    openssh-client \
    curl \
    apache2-utils \
    qrencode

RUN apt-get install -y \
    perl \
    libdbi-perl \
    libdbd-mysql-perl \
    libredis-perl \
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
    librouter-simple-perl \
    libcryptx-perl \
    libbytes-random-secure-perl \
    libcrypt-jwt-perl

RUN cpan Crypt::Curve25519

RUN set -x \
    && mkdir /var/www && chown www-data: /var/www \
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

COPY entry-core.sh /entry.sh
CMD ["/entry.sh"]

COPY app /app


FROM httpd:2.4 AS webdav
EXPOSE 80
RUN mkdir -p /app/data && \
    ln -s /app/data /usr/local/apache2/webdav
COPY build/webdav/httpd.conf /usr/local/apache2/conf/httpd.conf

