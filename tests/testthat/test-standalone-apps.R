# Execute real app definitions while mocking only OAuth and native transports.
playground_cases <- list(
  list("azure-sql", "azure_sql", "DBI", "dbGetQuery"),
  list("sql-server", "sql_server", "DBI", "dbGetQuery"),
  list("azure-postgres", "azure_postgres", "DBI", "dbGetQuery"),
  list("snowflake", "snowflake", "DBI", "dbGetQuery"),
  list("databricks", "databricks", "brickster", "db_sql_query")
)

for (playground_case in playground_cases) local({
  case <- playground_case
  filename <- paste0("example-", case[[1L]], ".R")

  test_that(paste(filename, "builds its real OAuth client and UI"), {
    withr::local_envvar(playground_env())
    if (case[[3L]] == "brickster") {
      local_mocked_bindings(oauth_db_databricks_provider = playground_databricks_provider)
    }
    app <- playground_load_example(filename)
    expect_s3_class(app$app, "shiny.appobj")
    expect_identical(app$client@client_id, playground_env()[["OAUTHDB_CLIENT_ID"]])
    expect_identical(app$client@redirect_uri, "http://localhost:8100")
    response <- app$ui(playground_request())
    expect_equal(response$status, 200L)
    expect_match(response$content, 'id="login"', fixed = TRUE)
    expect_match(response$content, 'id="rows"', fixed = TRUE)
  })

  test_that(paste(filename, "passes native values directly to its database package"), {
    skip_if_not_installed(case[[3L]])
    skip_if_not_installed("RSQLite")
    withr::local_envvar(playground_env())
    if (case[[3L]] == "brickster") {
      local_mocked_bindings(oauth_db_databricks_provider = playground_databricks_provider)
    }
    app <- playground_load_example(filename)
    calls <- new.env(parent = emptyenv())
    calls$requests <- list()
    calls$connections <- list()
    calls$login <- 0L
    calls$fail <- FALSE
    app$oauth_module_server <- playground_module(calls)
    if (case[[3L]] == "DBI") app[[paste0("oauth_db_", case[[2L]])]] <- function(authorization, ...) {
      oauth_db_connect(authorization, connect = function(token) {
        force(token)
        con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
        attr(con, "example_user") <- sub("^fixture-", "", token)
        calls$connections <- c(calls$connections, list(con))
        con
      })
    }
    spy <- playground_spy(getExportedValue(case[[3L]], case[[4L]]), function(args) {
      calls$requests <- c(calls$requests, list(args))
      if (calls$fail) stop("Example query failed")
      user <- if (case[[3L]] == "DBI") attr(args$conn, "example_user") else {
        sub("^fixture-", "", args$token)
      }
      data.frame(user = user)
    })
    do.call(local_mocked_bindings, c(
      stats::setNames(list(spy), case[[4L]]),
      list(.package = case[[3L]], .env = environment())
    ))

    shiny::testServer(app$server, {
      session$flushReact()
      expect_match(output$rows, "\\bA\\b")
      expect_length(calls$requests, 1L)
      session$setInputs(login = 1L)
      expect_equal(calls$login, 1L)
      expect_length(calls$requests, 1L)
      if (case[[3L]] == "DBI") expect_identical(con(), con())

      calls$select("B")
      session$flushReact()
      expect_match(output$rows, "\\bB\\b")
      expect_false(grepl("\\bA\\b", output$rows))
      expect_length(calls$requests, 2L)

      calls$fail <- TRUE
      calls$select("C")
      session$flushReact()
      expect_error(output$rows, "Example query failed")
      calls$fail <- FALSE
      calls$select("D")
      session$flushReact()
      expect_match(output$rows, "\\bD\\b")
      session$setInputs(logout = 1L)
      expect_error(output$rows, class = "shiny.silent.error")
    })
    for (con in calls$connections) expect_false(DBI::dbIsValid(con))
  })
})
