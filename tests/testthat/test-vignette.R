vignette_chunks <- function(name) {
  path <- test_path("..", "..", "vignettes", paste0(name, ".Rmd"))
  skip_if_not(file.exists(path), "Vignette source is unavailable")
  chunks <- list()
  label <- NULL
  for (line in readLines(path)) {
    if (grepl("^`{3}\\{r ", line)) {
      label <- sub("^`{3}\\{r ([^,}]+).*$", "\\1", line)
      chunks[[label]] <- character()
    } else if (identical(line, "```")) label <- NULL
    else if (!is.null(label)) chunks[[label]] <- c(chunks[[label]], line)
  }
  lapply(chunks, function(code) parse(text = code))
}

test_that("documented DBI queries wait quietly for sign-in", {
  withr::local_envvar(playground_env())
  introduction <- vignette_chunks("getting-started")
  recipes <- vignette_chunks("databases")
  app <- new.env(parent = globalenv())
  eval(introduction[["azure-sql-app"]], app)
  app$host <- "example.cloud.databricks.com"
  app$oauth_module_server <- function(...) list(connection = function() NULL)

  # Use the real helpers and DBI generic: resolving con() first must preserve
  # Shiny's missing-authorization signal before S4 method dispatch begins.
  shiny::testServer(app$server, {
    session$flushReact()
    expect_error(output$rows, class = "shiny.silent.error")
  })

  cases <- c("azure-sql", "fabric-sql", "azure-postgres", "databricks-dbi", "snowflake", "redshift")
  for (label in cases) {
    server <- app$server
    body(server) <- bquote({
      auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
      .(recipes[[label]][[1L]])
      .(recipes[["sql-query"]][[1L]])
    })
    shiny::testServer(server, {
      session$flushReact()
      expect_error(output$rows, class = "shiny.silent.error", info = label)
    })
  }
})

test_that("documented sign-in clients use the released shinyOAuth interface", {
  withr::local_envvar(playground_env())
  local_mocked_bindings(
    oauth_db_databricks_provider = playground_databricks_provider
  )
  chunks <- vignette_chunks("databases")
  app <- new.env(parent = globalenv())
  for (label in c("databricks-client", "snowflake-client", "redshift-client")) {
    eval(chunks[[label]], app)
    expect_s3_class(app$client, "shinyOAuth::OAuthClient")
  }
})
