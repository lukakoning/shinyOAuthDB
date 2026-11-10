# Source-built PostgreSQL and libpq deliberately omit the device-flow module.
# Both the database and R runner use the same libpq build and headers.
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a
FROM ${DEBIAN_IMAGE} AS postgres-build
ARG POSTGRES_VERSION=18.3
ARG POSTGRES_SHA256=d95663fbbf3a80f81a9d98d895266bdcb74ba274bcc04ef6d76630a72dee016f
ARG VALIDATOR_COMMIT=ba9c4cb2dc9bd2e9779c7a33f7a30c9bb8c97862
ENV PATH=/opt/postgresql/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/postgresql/lib \
    PKG_CONFIG_PATH=/opt/postgresql/lib/pkgconfig
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bison flex ca-certificates curl git patch pkg-config \
    libssl-dev libreadline-dev zlib1g-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl --fail --location --retry 3 \
      "https://ftp.postgresql.org/pub/source/v${POSTGRES_VERSION}/postgresql-${POSTGRES_VERSION}.tar.bz2" \
      -o /tmp/postgresql.tar.bz2 \
    && echo "${POSTGRES_SHA256}  /tmp/postgresql.tar.bz2" | sha256sum --check - \
    && mkdir /tmp/postgresql-src \
    && tar -xjf /tmp/postgresql.tar.bz2 -C /tmp/postgresql-src --strip-components=1 \
    && cd /tmp/postgresql-src \
    && ./configure --prefix=/opt/postgresql --with-openssl --without-libcurl --without-icu \
    && make -j2 && make install \
    && rm -rf /tmp/postgresql-src /tmp/postgresql.tar.bz2
# Keep validator builds separate from the libpq/R dependency stage: a server
# validator change must not invalidate the runner's CRAN package installation.
FROM postgres-build AS validator-build
ARG POSTGRES_VERSION=18.3
ARG POSTGRES_SHA256=d95663fbbf3a80f81a9d98d895266bdcb74ba274bcc04ef6d76630a72dee016f
ARG VALIDATOR_COMMIT=ba9c4cb2dc9bd2e9779c7a33f7a30c9bb8c97862
COPY postgres/patches/validator-audience.patch /tmp/validator-audience.patch
RUN git clone https://github.com/percona/pg_oidc_validator.git /tmp/validator \
    && cd /tmp/validator && git checkout --detach "${VALIDATOR_COMMIT}" \
    && test "$(git rev-parse HEAD)" = "${VALIDATOR_COMMIT}" \
    && git apply --check /tmp/validator-audience.patch \
    && git apply /tmp/validator-audience.patch \
    && make USE_PGXS=1 PG_CONFIG=/opt/postgresql/bin/pg_config CC=g++ -j2 \
    && make USE_PGXS=1 PG_CONFIG=/opt/postgresql/bin/pg_config CC=g++ install \
    && mkdir -p /opt/fixture-provenance \
    && printf '%s\n' "postgresql=${POSTGRES_VERSION}" "postgresql_sha256=${POSTGRES_SHA256}" \
      "validator_commit=${VALIDATOR_COMMIT}" "validator_link_driver=g++" \
      "libpq_configure=--without-libcurl" \
      > /opt/fixture-provenance/build.txt \
    && sha256sum /tmp/validator-audience.patch >> /opt/fixture-provenance/build.txt \
    && rm -rf /tmp/validator /tmp/validator-audience.patch

FROM ${DEBIAN_IMAGE} AS postgres
ENV PATH=/opt/postgresql/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/postgresql/lib \
    PGDATA=/var/lib/postgresql/data
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openssl libssl3t64 libreadline8t64 zlib1g libcurl4t64 util-linux passwd \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system postgres \
    && useradd --system --gid postgres --home-dir /var/lib/postgresql postgres
COPY --from=validator-build /opt/postgresql /opt/postgresql
COPY --from=validator-build /opt/fixture-provenance /opt/fixture-provenance
COPY postgres/postgres-entrypoint.sh postgres/postgres-healthcheck.sh /usr/local/bin/
COPY postgres/config /etc/oauthdb-fixture
COPY postgres/sql /docker-entrypoint-initdb.d
RUN chmod 755 /usr/local/bin/postgres-entrypoint.sh /usr/local/bin/postgres-healthcheck.sh
ENTRYPOINT ["/usr/local/bin/postgres-entrypoint.sh"]


FROM postgres-build AS app
ENV R_LIBS_USER=/opt/demo-r-library SHINYOAUTHDB_POSTGRES_OAUTH=required
RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base-dev libxml2-dev libuv1-dev && rm -rf /var/lib/apt/lists/*
COPY install.R /tmp/install.R
COPY package-source/version /tmp/demo-version
RUN Rscript /tmp/install.R && Rscript -e 'install.packages("RPostgres", repos="https://cloud.r-project.org", type="source"); stopifnot(requireNamespace("RPostgres"))'
RUN Rscript -e 'if (!requireNamespace("bslib", quietly=TRUE) || packageVersion("bslib") < "0.9.0") install.packages("bslib", repos="https://cloud.r-project.org"); stopifnot(packageVersion("bslib") >= "0.9.0")'
COPY package-source /tmp/demo-package
RUN Rscript /tmp/demo-package/install.R
COPY entrypoint.sh /usr/local/bin/demo-entrypoint.sh
WORKDIR /demo
ENTRYPOINT ["bash", "/usr/local/bin/demo-entrypoint.sh"]
CMD ["Rscript", "run.R"]
