#' Query data with a Shiny user's own account
#'
#' Build Shiny apps that query databases using each visitor's own permissions.
#' Use DBI or dbplyr for SQL, or call fabricQueryR and brickster functions with
#' the user's sign-in.
#'
#' Supports commercial and cloud-hosted data platforms, as well as self-hosted
#' PostgreSQL, Trino and DuckDB configured for OAuth. Users sign in through a provider
#' the database or query engine trusts; that server enforces their permissions.
#'
#' @section Try a self-hosted database locally:
#' With Docker running, use [oauth_db_demo()] to start PostgreSQL 18,
#' Keycloak and a Shiny app with demo accounts and sample data. The installed
#' package includes the configuration; Docker provides R and native libraries.
#' PostgREST, Trino, StarRocks, DuckDB Quack, libSQL, CrateDB and OpenSearch
#' demos use the same launcher.
#' See [Getting started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#build-a-small-app)
#' for demo accounts and cleanup, and [oauth_db_demo()] for editing options.
#'
#' @section Start with your source:
#' `vignette("getting-started", package = "shinyOAuthDB")` links to a guide
#' for each source. Each includes sign-in setup and a complete Shiny app.
#' Read the guides on the
#' [documentation website](https://lukakoning.github.io/shinyOAuthDB/articles/index.html),
#' or install with `build_vignettes = TRUE` for local `vignette()` help.
#' For example, use `vignette("snowflake", package = "shinyOAuthDB")` for
#' Snowflake or `vignette("fabric", package = "shinyOAuthDB")` for Fabric.
#'
#' @section Database queries:
#' Inside `server()`, pass shinyOAuth's `auth$connection` to a helper such
#' as [oauth_db_azure_sql()]. It returns a connection function, `con`.
#' Get `connection <- con()` inside a render or reactive expression, then
#' query with DBI or dbplyr.
#'
#' @section Platform functions:
#' [oauth_db_fabric_api()] and [oauth_db_databricks_api()] call functions from
#' their platforms' R packages with the visitor's credentials.
#' [oauth_db_bigquery_api()] runs GoogleSQL and returns data frames.
#'
#' @section Cleanup diagnostics:
#' A failed native disconnect emits a message while local authorization
#' retirement continues. To send these failures to your application's logger,
#' set `options(shinyOAuthDB.on_cleanup_error = function(error) { ... })`.
#' The handler receives a `shinyOAuthDB_cleanup_failed` condition containing
#' a fixed message and reason, without the original driver error, connection,
#' or credential. If the handler errors, the default message is emitted.
#'
#' @section HTTP request failures:
#' BigQuery, PostgREST and ClickHouse HTTP failures raise
#' `shinyOAuthDB_request_failed`. Catch this condition inside the Shiny
#' operation to inspect its `status`. Recognized service codes and UUID
#' request identifiers appear as `service_code` and `request_id`; unavailable
#' values are `NULL`. The condition excludes server messages, response bodies
#' and credentials.
#'
#' @section Sign-in settings:
#' The source guides create clients with [oauth_db_microsoft_client()],
#' [oauth_db_bigquery_client()], [oauth_db_databricks_client()], or
#' [oauth_db_snowflake_client()]. You can also use an existing shinyOAuth client.
#'
#' See `vignette("getting-started", package = "shinyOAuthDB")` for custom
#' permissions, multiple accounts, and saved query results.
#'
#' @keywords package
#' @importFrom R6 R6Class
#' @useDynLib shinyOAuthDB, .registration = TRUE
"_PACKAGE"
