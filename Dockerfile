FROM nginx:alpine

ENV ROOT /app

RUN apk add fcgiwrap perl
RUN deploy/install_deps.sh

COPY nginx/default /etc/nginx/sites-available/

COPY app /

