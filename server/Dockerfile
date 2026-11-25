FROM python:3.13-alpine

RUN addgroup -S -g 10001 nala \
    && adduser -S -D -H -u 10001 -G nala nala \
    && mkdir /data \
    && chown 10001:10001 /data \
    && chmod 700 /data

WORKDIR /app
COPY nala_server/*.py ./nala_server/
COPY --chmod=755 nala-server /usr/local/bin/nala-server

ENV NALA_DATA_DIR=/data NALA_PORT=8080 PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["nala-server"]
CMD ["serve"]
