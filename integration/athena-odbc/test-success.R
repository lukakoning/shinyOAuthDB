# Synthetic AWS responses exercise the real driver's credential and query state.
source("/src/R/conditions.R")
source("/src/R/odbc.R")
source("/src/R/backend__athena.R")

settings <- list(
  driver = "/opt/athena-driver/opt/amazon/athena-odbc/lib/libathenaodbc.so",
  AwsRegion = "eu-west-1",
  Workgroup = "reporting",
  WorkGroupArn = "arn:aws:athena:eu-west-1:123456789012:workgroup/reporting",
  ApplicationRoleArn = "arn:aws:iam::123456789012:role/AthenaApplication",
  AccessRoleArn = "arn:aws:iam::123456789012:role/AthenaAccess",
  CustomerIdcApplicationArn = "arn:aws:sso::123456789012:application/ssoins-fixture/apl-fixture",
  S3OutputLocation = "s3://query-results/reporting/",
  Schema = "default",
  Catalog = "AwsDataCatalog",
  StsEndpointOverride = "https://localhost:443",
  EndpointOverride = "https://localhost:443"
)
options <- list(
  TrustedCerts = Sys.getenv("ATHENA_PROBE_CERT"),
  ConnectionTimeout = 1000L,
  RequestTimeout = 1000L,
  ResultFetcher = "GetQueryResults"
)

run <- function() {
  connections <- list()
  on.exit(lapply(connections, DBI::dbDisconnect), add = TRUE)
  for (grant in c("alice-1", "bob-1", "alice-2")) {
    token <- readLines(
      file.path(Sys.getenv("ATHENA_PROBE_DIR"), paste0(grant, ".token")),
      warn = FALSE
    )
    con <- .odb_backend_athena(function() token, settings, options)
    connections[[grant]] <- con
    rows <- DBI::dbGetQuery(con, "SELECT fixture_user")
    stopifnot(identical(rows$who, grant))
  }
  # Older connections must keep their own derived credentials after another
  # visitor connects and after Alice receives a different access token.
  for (grant in names(connections)) {
    rows <- DBI::dbGetQuery(connections[[grant]], "SELECT fixture_user")
    stopifnot(identical(rows$who, grant))
  }
}
run()
cat(
  "Native connections and SQL results retain separate synthetic credentials.\n"
)
