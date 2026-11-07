live_bigquery_identifier <- function(value) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !grepl("^[A-Za-z0-9_][A-Za-z0-9_-]*$", value)
  ) {
    stop("Use simple BigQuery fixture identifiers.", call. = FALSE)
  }
  value
}

live_bigquery_table <- function(name = live_env("OAUTHDB_BIGQUERY_TABLE")) {
  paste0(
    "`",
    paste(
      vapply(
        c(
          live_env("OAUTHDB_BIGQUERY_PROJECT"),
          live_env("OAUTHDB_BIGQUERY_DATASET"),
          name
        ),
        live_bigquery_identifier,
        ""
      ),
      collapse = "."
    ),
    "`"
  )
}

live_bigquery_spec <- function() {
  project <- live_env("OAUTHDB_BIGQUERY_PROJECT")
  dataset <- live_env("OAUTHDB_BIGQUERY_DATASET")
  location <- live_env("OAUTHDB_BIGQUERY_LOCATION")
  sql <- paste(
    "SELECT SESSION_USER() AS database_user, visible_marker FROM",
    live_bigquery_table(),
    "ORDER BY visible_marker"
  )
  list(
    service = "bigquery",
    helper = "oauth_db_bigquery_api",
    auth_mode = "google",
    retires_handle = FALSE,
    bind = function(auth) {
      api <- shinyOAuthDB::oauth_db_bigquery_api(
        auth,
        project,
        dataset,
        location = location,
        page_size = 1L,
        timeout = 60
      )
      function() api
    },
    native_args = function(value) {
      list(
        sql = sql,
        maximum_bytes_billed = "10485760",
        use_query_cache = FALSE
      )
    },
    query = function(native, args) do.call(native$query, args),
    checks = function(native) {
      live_bigquery_roundtrip(
        native,
        dataset,
        live_env("OAUTHDB_BIGQUERY_TABLE")
      )
    }
  )
}

live_bigquery_roundtrip <- function(api, dataset, table) {
  payload <- "quoted ' text; -- café 雪\t\n\\"
  instant <- as.POSIXct("2020-02-29 12:34:56", tz = "UTC") + 0.125
  rows <- api$query(
    paste(
      "SELECT @text AS text_value, @integer AS integer_value, @decimal AS decimal_value,",
      "@day AS day_value, @instant AS instant_value, @missing AS missing_value,",
      "@array AS array_value, STRUCT(@integer AS id) AS record_value"
    ),
    parameters = list(
      text = payload,
      integer = "9223372036854775807",
      decimal = "123456789.123456789",
      day = as.Date("2020-02-29"),
      instant = instant,
      missing = NULL,
      array = 1:3
    ),
    parameter_types = c(
      integer = "INT64",
      decimal = "NUMERIC",
      missing = "STRING"
    ),
    maximum_bytes_billed = "10485760",
    use_query_cache = FALSE
  )
  empty <- api$query(
    "SELECT CAST(NULL AS STRING) AS value WHERE FALSE",
    maximum_bytes_billed = "10485760"
  )
  stopifnot(
    nrow(rows) == 1L,
    identical(rows$text_value, payload),
    identical(rows$integer_value, "9223372036854775807"),
    identical(rows$decimal_value, "123456789.123456789"),
    identical(rows$day_value, as.Date("2020-02-29")),
    inherits(rows$instant_value, "POSIXct"),
    abs(as.numeric(rows$instant_value) - as.numeric(instant)) < 1e-6,
    is.na(rows$missing_value),
    identical(rows$array_value, list(as.character(1:3))),
    identical(rows$record_value, list(list(id = "9223372036854775807"))),
    nrow(empty) == 0L,
    identical(names(empty), "value"),
    dataset %in% api$datasets(),
    table %in% api$tables(dataset)
  )
  TRUE
}
