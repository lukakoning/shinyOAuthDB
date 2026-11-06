FROM ghcr.io/tursodatabase/libsql-server:v0.24.33@sha256:f8ca0134cdded747793888e48591aece07647d9d598d3ac229aabfa93159ca88 AS libsql
FROM python:3.12.12-slim
RUN pip install --no-cache-dir cryptography==50.0.2
COPY --from=libsql /bin/sqld /usr/local/bin/sqld
COPY server.py /server.py
CMD ["python", "-u", "/server.py"]
