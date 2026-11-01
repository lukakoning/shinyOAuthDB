#' Query data with a Shiny user's own account
#'
#' Build Shiny apps that query databases using each visitor's own permissions.
#' Use DBI or dbplyr for SQL, or call fabricQueryR and brickster functions with
#' the user's sign-in.
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
"_PACKAGE"
