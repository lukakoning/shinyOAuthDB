.odb_cloud_spec_azure_postgres <- function() list(
  title = "Azure PostgreSQL",
  purpose = "Connect to Azure PostgreSQL with your Microsoft sign-in and an existing database role. The first query reports that role and database, without needing a table.",
  account_url = "https://learn.microsoft.com/en-us/azure/postgresql/overview",
  setup_url = "https://learn.microsoft.com/en-us/azure/postgresql/security/security-entra-configure",
  registration_url = "https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app",
  registration = c(.odb_cloud_entra_registration("Azure OSSRDBMS Database", "user_impersonation"),
    "The PostgreSQL sign-in preset requests https://ossrdbms-aad.database.windows.net/.default. Add the delegated API permission and consent before using this static scope.",
    "In Azure PostgreSQL > Authentication, enable Entra and set an Entra administrator. That administrator creates the user or group role with pgaadauth_create_principal and grants database access. The token's user must match that role or belong to the mapped group.",
    "Allow this computer through the PostgreSQL networking settings, or connect through the approved private network. Download the current trusted root CA bundle from Microsoft's TLS instructions; do not disable certificate verification."
  ),
  cost = "Connections use your existing Azure PostgreSQL server. Stopping this app does not stop the server or change its billing settings.",
  client_types = c("public", "confidential"), packages = list(RPostgres = NULL),
  required = c("server", "database", "user", "sslrootcert", "tenant_id", "client_id"),
  fields = list(
    server = .odb_cloud_field("Find the PostgreSQL server", "In Azure portal > your Azure Database for PostgreSQL server > Overview, copy Server name, such as example.postgres.database.azure.com. Use the full hostname.", "hostname"),
    database = .odb_cloud_field("Find the database", "Copy the PostgreSQL database name from your connection settings. The default administrative database is often postgres; use a database your role can connect to."),
    user = .odb_cloud_field("Choose the mapped database role", "Ask the Entra database administrator for the exact user or group role created in PostgreSQL. For a group role, each visitor still signs in individually and the server checks their membership."),
    sslrootcert = .odb_cloud_field("Find your trusted CA bundle", "Download the root certificates recommended for your server and save them as a PEM bundle. Paste its local file path. Microsoft's current TLS instructions: https://learn.microsoft.com/en-us/azure/postgresql/security/security-tls", "path"),
    tenant_id = .odb_cloud_tenant_field(),
    database_port = .odb_cloud_field("PostgreSQL port", "The default is 5432. Supply database_port if your endpoint uses another port.", "port", "5432")
  )
)
