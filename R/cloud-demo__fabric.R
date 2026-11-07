.odb_cloud_spec_fabric <- function() {
  list(
    title = "Microsoft Fabric",
    purpose = "Query a Fabric Warehouse or SQL analytics endpoint as the person who signs in. The first query shows your database identity and needs no tables.",
    account_url = "https://learn.microsoft.com/en-us/fabric/get-started/fabric-trial",
    setup_url = "https://learn.microsoft.com/en-us/fabric/data-warehouse/connectivity",
    registration_url = "https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app",
    registration = .odb_cloud_entra_registration(
      "Azure SQL Database",
      "user_impersonation"
    ),
    cost = "Running SQL uses your Fabric capacity. Stopping the local app does not stop or change that capacity.",
    client_types = c("public", "confidential"),
    packages = list(fabricQueryR = "1.0.1", odbc = "1.4.2"),
    driver_url = "https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server",
    required = c("server", "database", "tenant_id", "client_id"),
    fields = list(
      server = .odb_cloud_field(
        "Find the SQL server",
        "Open your Fabric Warehouse or Lakehouse SQL analytics endpoint > Settings > SQL connection string. Copy only the server hostname, such as example.datawarehouse.fabric.microsoft.com. This is not a workspace URL.",
        "hostname"
      ),
      database = .odb_cloud_field(
        "Find the database",
        "Copy the database/catalog name from the same SQL connection settings. Your account needs access to this item and its data.",
        "odbc"
      ),
      tenant_id = .odb_cloud_tenant_field(),
      driver = .odb_cloud_sql_driver_field()
    )
  )
}

.odb_cloud_entra_registration <- function(service, permission) {
  c(
    "In the Microsoft Entra admin center, open App registrations > New registration in the tenant that owns the data. Copy Application (client) ID and Directory (tenant) ID from Overview.",
    "For a local public PKCE app, register the callback under Mobile and desktop applications. For a confidential app, use Web and create a client secret; copy its Value through the masked prompt. Use the same registration type in this guide.",
    paste0(
      "Under API permissions > Add a permission, add the delegated ",
      service,
      " permission ",
      permission,
      ". Your organization may require administrator consent. The app requests user access, not application/service-principal permissions."
    ),
    "Share the database or item with the people using the app. Consent to OAuth permissions does not itself grant access to data."
  )
}

.odb_cloud_tenant_field <- function() {
  .odb_cloud_field(
    "Find your Microsoft tenant",
    "Open Entra admin center > App registrations > your app > Overview. Copy Directory (tenant) ID. A personal Microsoft account alone does not grant access to your organization's data.",
    "uuid"
  )
}
.odb_cloud_sql_driver_field <- function() {
  .odb_cloud_field(
    "SQL Server ODBC driver",
    "Install Microsoft ODBC Driver 18 for SQL Server on this computer. If its registered name differs, supply driver when resuming.",
    "odbc",
    "ODBC Driver 18 for SQL Server"
  )
}
