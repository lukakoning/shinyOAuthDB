cloud_platform_settings <- function() list(
  fabric = list(server = "example.datawarehouse.fabric.microsoft.com", database = "Reporting",
    tenant_id = "11111111-2222-3333-4444-555555555555", client_id = "demo-client", client_type = "public")
)

cloud_platform_app <- function(platform) {
  path <- cloud_demo_path()
  do.call(oauth_db_cloud_demo, c(list(platform = platform, action = "files", prompt = FALSE, path = path),
    cloud_platform_settings()[[platform]]))
  envir <- new.env(parent = globalenv())
  withr::with_dir(path, eval(parse("app.R"), envir))
  envir
}
