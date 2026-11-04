FROM shinyoauthdb-local-runner:1 AS runner
RUN curl --fail --location --retry 3 \
      https://repo.mysql.com/apt/debian/pool/mysql-tools/m/mysql-connector-odbc/mysql-connector-odbc_9.5.0-1debian13_amd64.deb \
      -o /tmp/mysql-odbc.deb \
    && echo '62d4fa2b11c6d29115440a50d43357c235f2f3732335c389c0362a3946775585  /tmp/mysql-odbc.deb' | sha256sum --check - \
    && dpkg-deb --extract /tmp/mysql-odbc.deb / && rm /tmp/mysql-odbc.deb \
    && test -f /usr/lib/x86_64-linux-gnu/mysql/libmyodbc9/plugin/authentication_openid_connect_client.so
RUN Rscript -e 'options(repos=c(CRAN="https://cloud.r-project.org")); install.packages("odbc", Ncpus=2L); stopifnot(requireNamespace("odbc", quietly=TRUE), packageVersion("odbc") >= "1.4.2")'
