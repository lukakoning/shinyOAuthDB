FROM python:3.12.12-slim
ARG DUCKDB_VERSION=1.5.4
RUN pip install --no-cache-dir "duckdb==${DUCKDB_VERSION}" cryptography==50.0.2
COPY server.py /server.py
CMD ["python", "-u", "/server.py"]
