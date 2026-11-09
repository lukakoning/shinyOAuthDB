# Exercise the production ODBC constructor; endpoint injection belongs only
# to this transport fixture and isn't accepted by the public helper.
source("/src/R/conditions.R")
source("/src/R/odbc.R")
source("/src/R/backend__athena.R")
cat(
  "R",
  as.character(getRversion()),
  "; odbc",
  as.character(utils::packageVersion("odbc")),
  "\n"
)

drivers <- list.files(
  "/opt/athena-driver",
  "lib.*athena.*\\.so$",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
)
stopifnot(length(drivers) == 1L)
settings <- list(
  driver = drivers[[1L]],
  AwsRegion = "eu-west-1",
  Workgroup = "reporting",
  WorkGroupArn = "arn:aws:athena:eu-west-1:123456789012:workgroup/reporting",
  ApplicationRoleArn = "arn:aws:iam::123456789012:role/AthenaApplication",
  AccessRoleArn = "arn:aws:iam::123456789012:role/AthenaAccess",
  CustomerIdcApplicationArn = "arn:aws:sso::123456789012:application/ssoins-fixture/apl-fixture",
  S3OutputLocation = "s3://query-results/reporting/",
  Schema = "default",
  Catalog = "AwsDataCatalog",
  StsEndpointOverride = paste0(
    "https://localhost:",
    Sys.getenv("ATHENA_PROBE_PORT")
  )
)
options <- list(
  TrustedCerts = Sys.getenv("ATHENA_PROBE_CERT"),
  ConnectionTimeout = 1000L,
  RequestTimeout = 1000L
)
for (subject in c("alice", "bob")) {
  token <- paste0("eyJhbGciOiJSUzI1NiJ9.", subject, ".c2lnbmF0dXJl")
  error <- tryCatch(
    .odb_backend_athena(function() token, settings, options),
    error = identity
  )
  stopifnot(inherits(error, "error"))
  stopifnot(grepl(
    "InvalidIdentityToken",
    conditionMessage(error),
    fixed = TRUE
  ))
  stopifnot(
    !grepl(token, rawToChar(serialize(error, NULL, ascii = TRUE)), fixed = TRUE)
  )
}

settings$StsEndpointOverride <- paste0(
  "https://127.0.0.1:",
  Sys.getenv("ATHENA_PROBE_PORT")
)
error <- tryCatch(
  .odb_backend_athena(function() token, settings, options),
  error = identity
)
stopifnot(inherits(error, "error"))
stopifnot(!grepl("InvalidIdentityToken", conditionMessage(error), fixed = TRUE))
cat("Native JWT_TIP rejects fixture tokens and an incorrect TLS hostname.\n")
