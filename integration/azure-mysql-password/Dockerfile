FROM python:3.12.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir mysql-mimic==3.0.5 sqlglot==30.30.0
COPY server.py /fixture/server.py
ENTRYPOINT ["python", "/fixture/server.py"]
