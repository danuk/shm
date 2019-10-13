FROM nginx
WORKDIR /app

RUN apt-get update && apt-get install -y \
    fcgiwrap \
    default-libmysqlclient-dev \
    perl \
    libdbi-perl \
    openssh-client \
    sudo \
    gcc \
    make

COPY deploy /app/deploy
RUN set -x \
    && cd /app/deploy \
    && /app/deploy/install_deps.sh \
    && usermod nginx -d /var/shm \
    && apt-get remove --purge --auto-remove -y gcc make \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /app/deploy \
    && rm -rf /root/.cpanm \
    && mkdir /var/shm && chown nginx: /var/shm

COPY nginx/default.conf /etc/nginx/conf.d/
COPY nginx/fcgiwrap /etc/default/

ENV SHM_ROOT_DIR /app
ENV SHM_DATA_DIR /var/shm
ENV PERL5LIB /app/lib:/app/conf
ENV DB_USER shm
ENV DB_PASS password
ENV DB_HOST 127.0.0.1
ENV DB_PORT 3306
ENV DB_NAME shm

COPY entry.sh /entry.sh
CMD ["/entry.sh"]

COPY app /app

