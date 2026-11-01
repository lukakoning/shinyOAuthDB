#' Use a visitor's database access in a Shiny app
#'
#' shinyOAuthDB connects shinyOAuth sign-in to existing database packages.
#' Visitors query with their own account; your app uses familiar DBI, dbplyr,
#' fabricQueryR, or brickster functions.
#'
#' @section Getting started:
#' Choose your source in
#' `vignette("getting-started", package = "shinyOAuthDB")`.
#' Each source has its own guide with sign-in setup and a complete Shiny app,
#' for example `vignette("snowflake", package = "shinyOAuthDB")` or
#' `vignette("fabric", package = "shinyOAuthDB")`.
#'
#' @section Database queries:
#' Create a helper such as [oauth_db_azure_sql()] inside `server()`, passing
#' `auth$connection` from shinyOAuth. Call the returned function inside a
#' render or reactive expression to obtain a DBI connection. Query with your
#' usual database functions; the helper handles connection reuse and cleanup.
#'
#' @section Platform APIs:
#' [oauth_db_fabric_api()] and [oauth_db_databricks_api()] let you call native
#' R functions with the visitor's credentials. Fabric resource objects can
#' also use those credentials in their own methods.
#' [oauth_db_bigquery_api()] runs GoogleSQL through the BigQuery REST API.
#'
#' @section Sign-in settings:
#' Keep an existing shinyOAuth client or use [oauth_db_microsoft_client()],
#' [oauth_db_bigquery_client()], [oauth_db_databricks_client()], or
#' [oauth_db_snowflake_client()] to set one up.
#' Read `vignette("authorization", package = "shinyOAuthDB")` for permission
#' settings, multiple authorizations, and session behavior.
#'
#' @keywords package
#' @importFrom R6 R6Class
"_PACKAGE"
