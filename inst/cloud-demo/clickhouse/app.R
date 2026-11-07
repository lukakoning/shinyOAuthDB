library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_microsoft_client(
  tenant_id = settings$tenant_id, client_id = settings$client_id,
  client_secret = if (settings$client_type == "confidential") Sys.getenv("OAUTHDB_CLICKHOUSE_CLIENT_SECRET") else NULL,
  redirect_uri = paste0("http://localhost:", settings$port),
  token_targets = list(clickhouse = list(resource = settings$resource, scopes = settings$scope))
)

demo_title <- "Your ClickHouse Cloud Shiny demo"
demo_context <- paste("HTTPS query endpoint:", settings$url)
demo_guide <- "https://lukakoning.github.io/shinyOAuthDB/articles/clickhouse.html"
example_query <- "SELECT currentUser() AS signed_in_user, version() AS server_version"
result_explanation <- "This first query checks your database identity. To try data access, replace it with SQL for a table you can read; the platform applies your existing permissions."
query_target <- "clickhouse"
query_scopes <- character()
query_notice <- "The service must trust your Entra access token and map its role claims to ClickHouse grants. Queries use normal service compute."
query_help <- "Couldn't run the query. Check the HTTPS endpoint, trusted JWT issuer/audience/JWKS, role claims and ClickHouse grants. Retry explicitly when ready."

make_access <- function(authorization) {
  oauth_db_clickhouse_api(authorization, url = settings$url, database = settings$database,
    target = "clickhouse", required_scopes = settings$scope)
}
run_query <- function(access) access$query(example_query)

source("demo-ui.R", local = TRUE)$value
