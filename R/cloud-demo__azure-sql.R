.odb_cloud_spec_azure_sql <- function() {
  spec <- .odb_cloud_spec_fabric()
  spec$title <- "Azure SQL"
  spec$purpose <- "Query an Entra-enabled Azure SQL database as the person who signs in. The first query reports your database identity without needing tables."
  spec$account_url <- "https://learn.microsoft.com/en-us/azure/azure-sql/database/free-offer"
  spec$setup_url <- "https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-configure"
  spec$registration <- c(spec$registration,
    "In Azure SQL, set an Entra administrator. That administrator creates database users or groups from the external provider and grants CONNECT and appropriate data privileges. Permit this computer through the server firewall, or connect through your organization's private network.")
  spec$cost <- "Queries use your existing Azure SQL database. Stopping this app does not pause or delete that database; normal service charges or allowances still apply."
  spec$packages <- list(odbc = "1.4.2")
  spec$fields$server <- .odb_cloud_field("Find the Azure SQL server", "In Azure portal > SQL databases > your database > Overview, copy Server name, such as example.database.windows.net. Copy the hostname rather than a full connection string.", "hostname")
  spec$fields$database <- .odb_cloud_field("Find the database name", "Copy the database name from its Overview page. This is not the server name. Your Entra user or group must exist inside this database.", "odbc")
  spec$fields$database_port <- .odb_cloud_field("Database TCP port", "Azure SQL Database normally uses port 1433. For a compatible managed/private endpoint, supply database_port from its connection settings.", "port", "1433")
  spec
}
