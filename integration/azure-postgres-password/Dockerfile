FROM postgres:18.3-alpine
RUN apk add --no-cache openssl
COPY start.sh /usr/local/bin/azure-postgres-fixture.sh
ENTRYPOINT ["sh", "/usr/local/bin/azure-postgres-fixture.sh"]
