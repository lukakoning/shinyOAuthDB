#' Query data with a Shiny user's own account
#'
#' Build Shiny apps that query databases using each visitor's own permissions.
#' Use DBI or dbplyr for SQL, or call fabricQueryR and brickster functions with
#' the user's sign-in.
#'
#' Supports commercial and cloud-hosted data platforms, as well as self-hosted
#' PostgreSQL and Trino configured for OAuth. Users sign in through a provider
#' the database or query engine trusts; that server enforces their permissions.
#'
#' @section Try a self-hosted database locally:
#' The [PostgreSQL Docker playground](https://github.com/lukakoning/shinyOAuthDB/blob/main/playground/postgres/README.md)
#' runs PostgreSQL 18, Keycloak and a Shiny app with demo accounts and data.
#' Docker provides the R packages and native libraries. The
#' [configuration files](https://github.com/lukakoning/shinyOAuthDB/tree/main/integration/postgres-keycloak)
#' are available in the source repository.
#' See `vignette("postgres", package = "shinyOAuthDB")` for downloads,
#' launch commands and your own server setup, or [oauth_db_postgres()] for
#' the connection helper. `vignette("trino", package = "shinyOAuthDB")`
#' covers self-hosted Trino and Starburst Enterprise.
#'
#' @section Start with your source:
#' `vignette("getting-started", package = "shinyOAuthDB")` links to a guide
#' for each source. Each includes sign-in setup and a complete Shiny app.
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
#' @section Sign-in settings:
#' The source guides create clients with [oauth_db_microsoft_client()],
#' [oauth_db_bigquery_client()], [oauth_db_databricks_client()], or
#' [oauth_db_snowflake_client()]. You can also use an existing shinyOAuth client.
#'
#' See `vignette("authorization", package = "shinyOAuthDB")` for custom
#' permissions, multiple accounts, and saved query results.
#'
#' @keywords package
#' @importFrom R6 R6Class
#' @useDynLib shinyOAuthDB, .registration = TRUE
"_PACKAGE"
