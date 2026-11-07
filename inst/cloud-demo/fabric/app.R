library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_microsoft_client(
  services = "sql",
  tenant_id = settings$tenant_id,
  client_id = settings$client_id,
  client_secret = if (settings$client_type == "confidential") {
    Sys.getenv("OAUTHDB_FABRIC_CLIENT_SECRET")
  } else {
    NULL
  },
  redirect_uri = paste0("http://localhost:", settings$port)
)

# Change the SQL here after the identity query works.
demo_title <- "Microsoft Fabric Shiny demo"
demo_details <- list(
  "SQL server" = settings$server,
  "Database" = settings$database,
  "ODBC driver" = settings$driver
)
platform_note <- "This connects to the Warehouse or SQL analytics endpoint. Fabric item permissions and SQL grants determine which tables you can read."
demo_guide <- "https://lukakoning.github.io/shinyOAuthDB/articles/fabric.html"
example_query <- "SELECT CURRENT_USER AS signed_in_user"
result_explanation <- "This first query checks your database identity. To try data access, replace it with SQL for a table you can read; the platform applies your existing permissions."
query_target <- "sql"
query_scopes <- character()
query_notice <- "Running SQL uses your Fabric capacity. The local demo doesn't change that capacity."
query_help <- "Couldn't run the query. Check the SQL server/database, item permissions, tenant and network access. Retry explicitly when ready."

make_access <- function(authorization) {
  oauth_db_fabric_sql(
    authorization,
    server = settings$server,
    database = settings$database,
    driver = settings$driver
  )
}
run_query <- function(access) DBI::dbGetQuery(access(), example_query)

source("demo-ui.R", local = TRUE)$value
