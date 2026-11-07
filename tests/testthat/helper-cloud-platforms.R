cloud_platform_settings <- function() list(
  fabric = list(server = "example.datawarehouse.fabric.microsoft.com", database = "Reporting",
    tenant_id = "11111111-2222-3333-4444-555555555555", client_id = "demo-client", client_type = "public"),
  bigquery = list(project = "example-project", client_id = "demo-client", client_type = "confidential"),
  snowflake = list(server = "org-account.snowflakecomputing.com", role = "REPORTING_READER",
    warehouse = "REPORTING_WH", client_id = "demo-client", client_type = "confidential"),
  `azure-sql` = list(server = "example.database.windows.net", database = "Reporting",
    tenant_id = "11111111-2222-3333-4444-555555555555", client_id = "demo-client", client_type = "public"),
  `azure-postgres` = list(server = "example.postgres.database.azure.com", database = "reporting",
    user = "reporting-readers", sslrootcert = "fixture-root-ca.pem",
    tenant_id = "11111111-2222-3333-4444-555555555555", client_id = "demo-client", client_type = "public")
)

cloud_platform_app <- function(platform) {
  secret_env <- paste0("OAUTHDB_", toupper(gsub("-", "_", platform)), "_CLIENT_SECRET")
  withr::local_envvar(stats::setNames("fixture-client-secret", secret_env))
  path <- cloud_demo_path()
  do.call(oauth_db_cloud_demo, c(list(platform = platform, action = "files", prompt = FALSE, path = path),
    cloud_platform_settings()[[platform]]))
  envir <- new.env(parent = globalenv())
  withr::with_dir(path, eval(parse("app.R"), envir))
  envir
}
