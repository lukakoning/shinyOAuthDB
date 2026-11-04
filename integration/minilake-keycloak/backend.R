minilake_warehouse <- function() jsonlite::read_json("/results/warehouse.json")$id
minilake_statement <- function(statement, warehouse) {
  response <- httr2::request("https://localhost/api/2.0/sql/statements") |>
    httr2::req_auth_bearer_token("fixture-seed") |>
    httr2::req_body_json(list(warehouse_id = warehouse, statement = statement,
      disposition = "INLINE", format = "JSON_ARRAY")) |>
    httr2::req_perform() |> httr2::resp_body_json()
  stopifnot(identical(response$status$state, "SUCCEEDED"))
  invisible(response)
}

fixture_backend <- list(
  dbi = FALSE, # The fixture value contains both a DBI accessor and an API client.
  test_file = "integration/minilake-keycloak/test-browser.R",
  prepare = function() {
    warehouse <- httr2::request("https://localhost/api/2.0/sql/warehouses") |>
      httr2::req_auth_bearer_token("fixture-seed") |>
      httr2::req_body_json(list(name = "oauthdb-local", cluster_size = "Small")) |>
      httr2::req_perform() |> httr2::resp_body_json()
    stopifnot(is.character(warehouse$id), nzchar(warehouse$id))
    jsonlite::write_json(list(id = warehouse$id), "/results/warehouse.json", auto_unbox = TRUE)
    minilake_statement("CREATE TABLE fixture_rows (id INTEGER, owner_name VARCHAR, marker VARCHAR)", warehouse$id)
    minilake_statement(paste("INSERT INTO fixture_rows VALUES",
      "(1,'alice','alice-visible-1'),(2,'alice','alice-visible-2'),",
      "(3,'bob','bob-visible-1'),(4,'bob','bob-visible-2')"), warehouse$id)
  },
  version = function() list(emulator = "MiniLake / DuckDB", brickster = as.character(packageVersion("brickster")),
    image = "sha256:cad09d7bff0ddc5f67e2d80e025efd281639e8196a09545463b79e0d0d074113",
    scope = "Client compatibility only: MiniLake accepts any token and does not enforce grants."),
  bind = function(authorization, username, config) {
    state <- new.env(parent = emptyenv())
    state$con <- shinyOAuthDB::oauth_db_databricks(authorization, host = "localhost",
      warehouse_id = minilake_warehouse(), disposition = "EXTERNAL_LINKS", show_progress = FALSE,
      required_scopes = "database.read", min_valid_for = 1)
    state$api <- shinyOAuthDB::oauth_db_databricks_api(authorization, host = "localhost",
      required_scopes = "database.read", min_valid_for = 1)
    state$authorization <- authorization
    state$username <- username
    state$previous <- state$first <- NULL
    state$generation <- 0L
    function() state
  },
  read = function(state) {
    con <- state$con()
    if (!identical(con, state$previous)) {
      state$generation <- state$generation + 1L
      state$previous <- con
      if (is.null(state$first)) state$first <- con
    }
    username <- shiny::isolate(state$username())
    stopifnot(username %in% c("alice", "bob"))
    # This WHERE clause is fixture data selection, NOT a server policy test.
    sql <- paste0("SELECT marker FROM fixture_rows WHERE owner_name = '", username, "' ORDER BY id")
    rows <- DBI::dbGetQuery(con, sql)
    api_current <- FALSE
    via_api <- state$api$call(function(host, token) {
      api_current <<- identical(token, con@token)
      brickster::db_sql_query(warehouse_id = minilake_warehouse(), statement = sql,
        disposition = "EXTERNAL_LINKS", show_progress = FALSE, host = host, token = token)
    })
    stopifnot(identical(rows, via_api))
    rows$generation <- state$generation
    rows$dbi_token_current <- identical(con@token,
      shiny::isolate(state$authorization()$access_token(min_valid_for_seconds = 0)))
    rows$api_token_current <- api_current
    rows$old_token_replaced <- !identical(state$first@token, con@token)
    rows
  },
  data_checks = function(state, username, config) {
    con <- state$con()
    payload <- "quoted ' text; -- café 雪"
    # The pinned emulator ignores named parameters. Keep that limitation
    # explicit, and use the real driver's SQL quoting for value round trips.
    parameters <- list(list(name = "payload", value = payload, type = "STRING"))
    parameter_dbi <- tryCatch(DBI::dbGetQuery(con, "SELECT :payload", parameters = parameters), error = identity)
    parameter_api <- tryCatch(state$api$call(brickster::db_sql_query,
      warehouse_id = minilake_warehouse(), statement = "SELECT :payload", parameters = parameters,
      disposition = "INLINE", show_progress = FALSE), error = identity)
    unsupported <- function(error) inherits(error, "error") &&
      grepl("HTTP 400", conditionMessage(error), fixed = TRUE) &&
      grepl("syntax error", conditionMessage(error), fixed = TRUE)
    sql <- paste("SELECT", as.character(DBI::dbQuoteLiteral(con, payload)),
      "AS value, CAST(NULL AS VARCHAR) AS missing,",
      "CAST(9223372036854775807 AS VARCHAR) AS integer_text,",
      "CAST('2020-02-29 12:34:56' AS TIMESTAMP) AS time_value")
    dbi <- DBI::dbGetQuery(con, sql)
    api_query <- function(statement, ...) state$api$call(brickster::db_sql_query,
      warehouse_id = minilake_warehouse(), statement = statement, disposition = "EXTERNAL_LINKS",
      show_progress = FALSE, ...)
    api <- api_query(sql)
    empty_dbi <- DBI::dbGetQuery(con, "SELECT marker FROM fixture_rows WHERE FALSE")
    empty_api <- api_query("SELECT marker FROM fixture_rows WHERE FALSE")
    # MiniLake's pinned chunk size is 100,000 rows. Both real brickster paths
    # must fetch a second chunk, including its first and last row.
    pages_sql <- "SELECT range AS id FROM range(100005) ORDER BY id"
    pages_dbi <- DBI::dbGetQuery(con, pages_sql)
    pages_api <- api_query(pages_sql)
    list(quoted_value = identical(dbi$value, payload),
      named_parameter_gap = unsupported(parameter_dbi) && unsupported(parameter_api),
      both_helpers = identical(dbi, api), null = is.na(dbi$missing),
      bigint_text = identical(dbi$integer_text, "9223372036854775807"),
      timestamp = inherits(dbi$time_value, "POSIXct") &&
        identical(format(dbi$time_value, tz = "UTC"), "2020-02-29 12:34:56"),
      empty = nrow(empty_dbi) == 0L && identical(empty_dbi, empty_api) && identical(names(empty_dbi), "marker"),
      pages = nrow(pages_dbi) == 100005L && identical(pages_dbi, pages_api) &&
        identical(as.numeric(pages_dbi$id), as.numeric(0:100004)))
  }
)
