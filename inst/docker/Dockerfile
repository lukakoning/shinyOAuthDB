FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a AS tls
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY prepare-tls.sh /usr/local/bin/prepare-tls.sh
ENTRYPOINT ["bash", "/usr/local/bin/prepare-tls.sh"]

FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a AS app-base
ENV R_LIBS_USER=/opt/demo-r-library SHINYOAUTHDB_POSTGRES_OAUTH=disabled
RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base-dev ca-certificates curl libcurl4-openssl-dev libssl-dev libxml2-dev libuv1-dev unixodbc-dev \
    && rm -rf /var/lib/apt/lists/*
COPY install.R /tmp/install.R
RUN Rscript /tmp/install.R
RUN Rscript -e 'if (!requireNamespace("bslib", quietly=TRUE) || packageVersion("bslib") < "0.9.0") install.packages("bslib", repos="https://cloud.r-project.org"); stopifnot(packageVersion("bslib") >= "0.9.0")'
COPY entrypoint.sh /usr/local/bin/demo-entrypoint.sh
WORKDIR /demo
ENTRYPOINT ["bash", "/usr/local/bin/demo-entrypoint.sh"]

FROM app-base AS app
COPY package-source /tmp/demo-package
RUN Rscript /tmp/demo-package/install.R

FROM app-base AS trino
RUN Rscript -e 'install.packages("RTrino", repos="https://cloud.r-project.org"); stopifnot(requireNamespace("RTrino"))'
COPY package-source /tmp/demo-package
RUN Rscript /tmp/demo-package/install.R

FROM app-base AS duckdb
COPY install-duckdb.R /tmp/install-duckdb.R
RUN Rscript /tmp/install-duckdb.R
COPY package-source /tmp/demo-package
RUN Rscript /tmp/demo-package/install.R

FROM app-base AS starrocks
RUN curl --fail --location --retry 3 \
      https://repo.mysql.com/apt/debian/pool/mysql-tools/m/mysql-connector-odbc/mysql-connector-odbc_9.5.0-1debian13_amd64.deb \
      -o /tmp/mysql-odbc.deb \
    && echo '62d4fa2b11c6d29115440a50d43357c235f2f3732335c389c0362a3946775585  /tmp/mysql-odbc.deb' | sha256sum --check - \
    && dpkg-deb --extract /tmp/mysql-odbc.deb / && rm /tmp/mysql-odbc.deb
RUN Rscript -e 'install.packages("odbc", repos="https://cloud.r-project.org"); stopifnot(requireNamespace("odbc"))'
COPY package-source /tmp/demo-package
RUN Rscript /tmp/demo-package/install.R
