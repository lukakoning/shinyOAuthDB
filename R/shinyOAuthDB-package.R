#' Bridge Shiny user authorizations to native database clients
#'
#' Let Shiny visitors access a database using their own authorization.
#' shinyOAuth handles sign-in and token renewal; shinyOAuthDB supplies the
#' visitor's credentials to your database package, which runs ordinary queries.
#'
#' @section Start here:
#' Read `vignette("simple-apps", package = "shinyOAuthDB")` for a complete app
#' followed by short connection examples. Inside `server()`, pass
#' `auth$connection` to a helper and resolve its accessor
#' inside your normal Shiny render or reactive expression.
#'
#' @section Choose a connection:
#' * [oauth_db_azure_sql()] and [oauth_db_sql_server()]: SQL through DBI/odbc.
#' * [oauth_db_azure_postgres()]: Azure PostgreSQL through RPostgres.
#' * [oauth_db_fabric_sql()]: Fabric SQL through fabricQueryR.
#' * [oauth_db_databricks()]: brickster DBI with a warehouse ID or HTTP path.
#' * [oauth_db_snowflake()]: Snowflake through DBI/odbc.
#' * [oauth_db_fabric()]: a token callback for fabricQueryR's native functions.
#' * [oauth_db_connect()]: other native connections.
#' * [oauth_db_token()]: bearer strings for brickster REST and other native APIs.
#'
#' @section Configure sign-in:
#' [oauth_db_microsoft_client()], [oauth_db_databricks_client()], and
#' [oauth_db_snowflake_client()] are optional presets returning ordinary
#' shinyOAuth clients. You retain control over providers, scopes, targets,
#' and multiple authorizations through shinyOAuth.
#'
#' @keywords package
"_PACKAGE"
