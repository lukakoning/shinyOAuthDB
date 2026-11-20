test_that("dedicated PostgreSQL helpers replace failed native reconnects", {
  skip_if_not_installed("RPostgres")
  loadNamespace("RPostgres")
  for (backend in c("azure", "cloud_sql", "cockroachdb")) {
    local({
      opened <- character()
      closed <- integer()
      broken <- FALSE
      connect <- function(token, ...) {
        opened <<- c(opened, token())
        native <- methods::new("PqConnection")
        attr(native, "fixture") <- length(opened)
        native
      }
      local_mocked_bindings(
        .odb_backend_postgres = connect,
        .odb_backend_cloud_sql_postgres = connect,
        .odb_backend_cockroachdb = connect
      )
      local_mocked_bindings(
        dbIsValid = function(dbObj, ...) {
          !attr(dbObj, "fixture") %in% closed
        },
        dbGetInfo = function(dbObj, ...) {
          if (inherits(dbObj, "DBIDriver")) {
            return(list(client.version = package_version("16.0")))
          }
          if (broken && attr(dbObj, "fixture") == 1L) {
            stop("Failed native reconnect")
          }
          list(pid = attr(dbObj, "fixture"))
        },
        dbDisconnect = function(conn, ...) {
          closed <<- c(closed, attr(conn, "fixture"))
          invisible(TRUE)
        },
        .package = "DBI"
      )
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(session)
        factory <- switch(
          backend,
          azure = oauth_db_azure_postgres,
          cloud_sql = oauth_db_cloud_sql_postgres,
          cockroachdb = oauth_db_cockroachdb
        )
        con <- factory(
          auth$connection,
          host = "postgres.example",
          dbname = "reports",
          user = "reader",
          target = NULL,
          required_scopes = "read"
        )
        runs <- 0L
        rows <- shiny::reactive({
          native <- con()
          runs <<- runs + 1L
          attr(native, "fixture")
        })
        expect_identical(rows(), 1L)
        first <- con()
        expect_identical(con(), first)
        broken <<- TRUE
        expect_true(DBI::dbIsValid(first))
        expect_error(DBI::dbGetInfo(first), "Failed native reconnect")
        replacement <- con()
        expect_false(identical(replacement, first))
        expect_false(DBI::dbIsValid(first))
        expect_identical(opened, c("fixture-A", "fixture-A"))
        expect_identical(closed, 1L)
        expect_identical(con(), replacement)
        expect_identical(rows(), 1L)
        expect_identical(runs, 1L)
      })
      expect_identical(closed, c(1L, 2L))
    })
  }
})
