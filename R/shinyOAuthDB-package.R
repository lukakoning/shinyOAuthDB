#' Bridge Shiny user authorizations to native database clients
#'
#' shinyOAuthDB connects module-owned shinyOAuth authorizations to existing
#' database and data platform packages. Use [oauth_db_connect()] or a backend
#' helper to obtain a reactive native connection accessor. Queries and their
#' results stay in the native package and normal Shiny code.
#'
#' @keywords internal
"_PACKAGE"
