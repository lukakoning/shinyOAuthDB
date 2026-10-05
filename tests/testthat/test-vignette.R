test_that("vignette DBI examples wait for sign-in through real S4 dispatch", {
  path <- test_path("..", "..", "vignettes", "simple-apps.Rmd")
  skip_if_not(file.exists(path), "Vignette source is unavailable")
  chunks <- list()
  label <- NULL
  for (line in readLines(path)) {
    if (grepl("^```\\{r ", line)) {
      label <- sub("^```\\{r ([^,}]+).*$", "\\1", line)
      chunks[[label]] <- character()
    } else if (identical(line, "```")) label <- NULL
    else if (!is.null(label)) chunks[[label]] <- c(chunks[[label]], line)
  }

  withr::local_envvar(playground_env())
  app <- new.env(parent = globalenv())
  eval(parse(text = chunks[["fabric-sql-app"]]), app)
  app$host <- "workspace.example"
  app$oauth_module_server <- function(...) list(connection = function() NULL)
  # Use the real bridge's missing-authorization signal. No driver is opened.
  # Keep DBI::dbGetQuery unmocked: S4 dispatch must not wrap that signal.
  for (name in c("oauth_db_fabric_sql", "oauth_db_azure_sql", "oauth_db_sql_server",
                 "oauth_db_azure_postgres", "oauth_db_databricks", "oauth_db_snowflake",
                 "oauth_db_connect")) {
    app[[name]] <- function(authorization, ...) {
      oauth_db_connect(authorization, connect = function(token) {
        stop("A signed-out example must not open a database connection")
      })
    }
  }
  cases <- c("fabric-sql-app", "fabric-sql-adbc", "databricks-http-path", "azure-sql", "sql-server",
             "azure-postgres", "databricks-dbi", "databricks-entra", "snowflake",
             "generic-connection")
  for (label in cases) {
    server <- app$server
    if (label != "fabric-sql-app") {
      code <- as.list(parse(text = chunks[[label]]))
      if (label %in% c("fabric-sql-adbc", "databricks-http-path", "sql-server", "generic-connection")) {
        code <- c(code, tail(as.list(body(app$server)), 1L))
      }
      body(server) <- as.call(c(list(quote(`{`)), as.list(body(app$server))[2:4], code))
    }
    shiny::testServer(server, {
      session$flushReact()
      expect_error(output$rows, class = "shiny.silent.error", info = label)
    })
  }
})
