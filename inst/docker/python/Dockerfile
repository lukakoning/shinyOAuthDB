FROM python:3.12.12-slim AS python
RUN pip install --no-cache-dir cryptography==50.0.2
ENV PYTHONUNBUFFERED=1
WORKDIR /demo

FROM python AS duckdb
ENV DATAZOO_DISABLE_TELEMETRY=1
RUN pip install --no-cache-dir duckdb==1.5.4 \
    && python -c "import duckdb; c=duckdb.connect(); c.execute('INSTALL quack'); c.execute('INSTALL httpfs'); c.execute('INSTALL quack_oauth FROM community')"

FROM ghcr.io/tursodatabase/libsql-server:v0.24.33@sha256:f8ca0134cdded747793888e48591aece07647d9d598d3ac229aabfa93159ca88 AS libsql-binary
FROM python AS libsql
COPY --from=libsql-binary /bin/sqld /usr/local/bin/sqld
