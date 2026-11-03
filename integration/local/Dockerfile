ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a
FROM ${DEBIAN_IMAGE} AS tls
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY prepare-tls.sh /usr/local/bin/prepare-tls.sh
ENTRYPOINT ["bash", "/usr/local/bin/prepare-tls.sh"]

FROM ${DEBIAN_IMAGE} AS runner
ENV R_LIBS_USER=/opt/fixture-r-library \
    CHROMOTE_CHROME=/usr/local/bin/fixture-chromium \
    SHINYOAUTHDB_POSTGRES_OAUTH=disabled
RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base-dev chromium fonts-liberation libnss3-tools ca-certificates curl \
    libcurl4-openssl-dev libssl-dev libxml2-dev libuv1-dev unixodbc-dev \
    && rm -rf /var/lib/apt/lists/* && mkdir -p /opt/fixture-r-library
RUN Rscript -e 'options(repos=c(CRAN="https://cloud.r-project.org")); required <- c("DBI","shiny","promises","later","R6","rlang","S7","jsonlite","openssl","httr2","curl","urltools","cachem","jose","lifecycle","cli","htmltools","otel","chromote","callr","testthat","withr"); install.packages(required, Ncpus=2L); stopifnot(all(vapply(required, requireNamespace, logical(1), quietly=TRUE)))'
COPY runner-entrypoint.sh fixture-chromium /usr/local/bin/
WORKDIR /workspace/shinyOAuthDB
ENTRYPOINT ["bash", "/usr/local/bin/runner-entrypoint.sh"]
CMD ["Rscript", "integration/local/run-tests.R"]
