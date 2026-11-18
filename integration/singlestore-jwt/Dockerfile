FROM shinyoauthdb-starrocks-runner:1
RUN apt-get update && apt-get install -y --no-install-recommends libsecret-1-0 \
    && rm -rf /var/lib/apt/lists/*
RUN curl --fail --location --retry 3 \
      https://github.com/memsql/singlestore-odbc-connector/releases/download/v1.2.1/singlestore-connector-odbc-1.2.1-ubuntu-amd64.tar.gz \
      -o /tmp/driver.tar.gz \
    && echo '3d431f066e1520715d59569a777222ea3c59190d1bcbf7a6e9d07f51c0ef78dd  /tmp/driver.tar.gz' | sha256sum --check - \
    && mkdir /opt/singlestore-driver \
    && tar -xzf /tmp/driver.tar.gz -C /opt/singlestore-driver --strip-components=1 \
    && rm /tmp/driver.tar.gz
RUN Rscript -e 'options(repos=c(CRAN="https://cloud.r-project.org")); install.packages("remotes"); remotes::install_github("lukakoning/shinyOAuth@9eb34e7d38f9393d995a9a8437a1bc546c849a78", upgrade="never")'
ENTRYPOINT []
