#' Query Amazon Athena as the signed-in user
#'
#' Read Athena data with each visitor's access token and permissions through
#' AWS IAM Identity Center trusted identity propagation. The helper opens a
#' DBI connection through the Amazon Athena ODBC 2.x driver.
#'
#' @inheritParams oauth_db_connect
#' @param workgroup_arn Athena workgroup ARN. Its region and workgroup name
#'   supply the driver's `AwsRegion` and `Workgroup` settings.
#' @param application_role_arn IAM role ARN trusted for the external provider's
#'   `AssumeRoleWithWebIdentity` requests in your Identity Center integration.
#' @param s3_output_location S3 URI for query results, such as
#'   `"s3://query-results/reporting/"`. Workgroup settings may override it.
#' @param schema Default Athena database name, default `"default"`.
#' @param catalog Athena data catalog, default `"AwsDataCatalog"`.
#' @param access_role_arn Optional IAM access role ARN. When omitted, the
#'   driver discovers it through the integration's application tags.
#' @param customer_idc_application_arn Optional IAM Identity Center customer
#'   managed application ARN. When omitted, the driver uses workgroup tags.
#' @param driver Installed Amazon Athena ODBC driver name.
#' @param ... Named result and timeout options for odbc or the Athena driver.
#'   See the source guide for accepted options. Authentication, endpoints,
#'   caching and TLS settings cannot be overridden.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install odbc and Amazon Athena ODBC 2.5.0.0 or later. Configure IAM Identity
#' Center's trusted token issuer, IAM roles and workgroup association first.
#' The sign-in provider must issue JWT access tokens accepted by that setup.
#' There is no universal Athena OAuth registration or scope preset.
#'
#' The helper uses `AuthenticationType = "JWT_TIP"` with an explicit visitor
#' token. It disables the driver's file credential cache, connection-check
#' cache, result reuse and logging, and requires TLS certificate verification.
#' Each native connection gets a random role session name. It doesn't supply
#' AWS keys, select an AWS profile or start the driver's browser login.
#'
#' Create the helper inside `server()` and call `con()` before each query.
#' Token replacement closes the old connection on the next access. Account
#' changes, permission loss, sign-out and session end also close it.
#' Consume and clear outstanding DBI results before another operation.
#'
#' A failed query isn't replayed by this helper. Closing an ODBC connection
#' doesn't guarantee cancellation of an already submitted Athena query.
#' @examples
#' \dontrun{
#' con <- oauth_db_athena(
#'   auth$connection,
#'   workgroup_arn = "arn:aws:athena:eu-west-1:123456789012:workgroup/reporting",
#'   application_role_arn = "arn:aws:iam::123456789012:role/AthenaApplication",
#'   s3_output_location = "s3://query-results/reporting/"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT * FROM sales LIMIT 20")
#' })
#' }
#' @seealso [oauth_db_connect()].
#'   `vignette("athena", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_athena <- function(
  authorization,
  workgroup_arn,
  application_role_arn,
  s3_output_location,
  ...,
  schema = "default",
  catalog = "AwsDataCatalog",
  access_role_arn = NULL,
  customer_idc_application_arn = NULL,
  driver = "Amazon Athena ODBC Driver",
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  .odb_string(workgroup_arn, "workgroup_arn")
  workgroup <- regmatches(
    workgroup_arn,
    regexec(
      "^arn:(aws[a-z0-9-]*):athena:([a-z0-9-]+):[0-9]{12}:workgroup/([A-Za-z0-9._-]{1,128})$",
      workgroup_arn
    )
  )[[1L]]
  if (!length(workgroup)) {
    .odb_abort("workgroup_arn must be an Athena workgroup ARN.")
  }
  role_pattern <- paste0(
    "^arn:",
    workgroup[[2L]],
    ":iam::[0-9]{12}:role/[A-Za-z0-9_+=,.@/-]+$"
  )
  for (name in c("application_role_arn", "access_role_arn")) {
    value <- if (name == "application_role_arn") {
      application_role_arn
    } else {
      access_role_arn
    }
    .odb_string(value, name, optional = name == "access_role_arn")
    if (!is.null(value) && !grepl(role_pattern, value)) {
      .odb_abort(paste0(
        name,
        " must be an IAM role ARN in the workgroup's partition."
      ))
    }
  }
  .odb_string(
    customer_idc_application_arn,
    "customer_idc_application_arn",
    optional = TRUE
  )
  if (
    !is.null(customer_idc_application_arn) &&
      !grepl(
        paste0(
          "^arn:",
          workgroup[[2L]],
          ":sso:[a-z0-9-]*:[0-9]{12}:application/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$"
        ),
        customer_idc_application_arn
      )
  ) {
    .odb_abort(
      "customer_idc_application_arn must be an Identity Center application ARN in the workgroup's partition."
    )
  }
  .odb_string(s3_output_location, "s3_output_location")
  if (!grepl("^s3://[^/[:space:]]+(/|$)", s3_output_location)) {
    .odb_abort("s3_output_location must be an s3:// URI for query results.")
  }
  .odb_string(schema, "schema")
  .odb_string(catalog, "catalog")
  .odb_string(driver, "driver")
  options <- .odb_athena_options(list(...))
  settings <- list(
    driver = driver,
    AwsRegion = workgroup[[3L]],
    Workgroup = workgroup[[4L]],
    WorkGroupArn = workgroup_arn,
    ApplicationRoleArn = application_role_arn,
    S3OutputLocation = s3_output_location,
    Schema = schema,
    Catalog = catalog
  )
  if (!is.null(access_role_arn)) {
    settings$AccessRoleArn <- access_role_arn
  }
  if (!is.null(customer_idc_application_arn)) {
    settings$CustomerIdcApplicationArn <- customer_idc_application_arn
  }
  .odb_odbc_values(c(settings, options))
  .odb_bind(
    authorization,
    .odb_backend_athena,
    settings = settings,
    options = options,
    target = target,
    required_scopes = required_scopes,
    cache_key = function(token) openssl::sha256(charToRaw(token())),
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_athena_options <- function(options) {
  options <- .odb_options(options, blocked = character())
  allowed <- c(
    "timeout",
    "timezone",
    "timezone_out",
    "bigint",
    "encoding",
    "name_encoding",
    "interruptible",
    "ConnectionTimeout",
    "RequestTimeout",
    "RowsToFetchPerBlock",
    "MaxPollDuration",
    "ResultFetcher",
    "StringColumnLength",
    "ComplexTypeColumnLength",
    "BinaryColumnLength",
    "S3ResultBlockSize",
    "UseWCharForStringTypes",
    "UseSingleCatalogAndSchema",
    "QueryExternalCatalogs",
    "MinQueryExecutionPollingInterval",
    "MaxQueryExecutionPollingInterval",
    "QueryExecutionPollingIntervalMultiplier",
    "S3OutputEncOption",
    "S3OutputEncKMSKey",
    "TrustedCerts"
  )
  key <- function(x) tolower(gsub("[^A-Za-z0-9]", "", x))
  indices <- match(key(names(options)), key(allowed))
  if (anyNA(indices)) {
    .odb_abort(
      "Unsupported Athena options in ... . Use only the documented result and timeout options; authentication, endpoints, caching and TLS verification are fixed."
    )
  }
  names(options) <- allowed[indices]
  options
}

.odb_backend_athena <- function(token, settings, options) {
  .odb_odbc_connect(c(
    list(
      drv = odbc::odbc(),
      AuthenticationType = "JWT_TIP",
      web_identity_token = token(),
      role_session_name = paste0(
        "shinyOAuthDB-",
        paste(format(openssl::rand_bytes(16)), collapse = "")
      ),
      JwtTipFileCache = 0L,
      EnableConnectionCaching = 0L,
      EnableResultReuse = 0L,
      VerifySSL = 1L,
      LogLevel = 0L
    ),
    settings,
    options
  ))
}
