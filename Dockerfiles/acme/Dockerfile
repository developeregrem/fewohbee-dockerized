# docker-compose build
FROM python:3.9-alpine

RUN apk add --no-cache \
        curl \
        tzdata \
        jq \
        gcc \
        musl-dev \
        libffi-dev \
        openssl \
        openssl-dev \
        dialog \
        bash \
        cargo \
        && pip install certbot
