FROM rocker/r-ver:4.5.1
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl cpio rpm2cpio python3 openssl unixodbc-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*
RUN Rscript -e 'options(repos=c(CRAN="https://cloud.r-project.org")); install.packages(c("DBI", "odbc", "openssl"))'
RUN curl --fail --location --retry 3 \
      https://aws-analytics-downloads-us-east-1.s3.us-east-1.amazonaws.com/athena/ODBC/v2.5.0.0/Linux/AmazonAthenaODBC-2.5.0.0-x86_64.rpm \
      -o /tmp/athena.rpm \
    && echo '6d5572377986329f02ef2f9b59e0818b4f692721c02b2e9ed1247df04d57a24c  /tmp/athena.rpm' | sha256sum --check - \
    && mkdir /opt/athena-driver \
    && cd /opt/athena-driver && rpm2cpio /tmp/athena.rpm | cpio -idm \
    && rm /tmp/athena.rpm
ENTRYPOINT []
