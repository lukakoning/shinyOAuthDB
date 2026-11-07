.odb_cloud_spec_clickhouse <- function() list(
  title = "ClickHouse Cloud",
  purpose = "Query a JWT-enabled ClickHouse Cloud service using your Microsoft account and existing role grants. This example uses Entra as the service's custom identity provider.",
  account_url = "https://clickhouse.com/docs/cloud/get-started/cloud-quick-start",
  setup_url = "https://clickhouse.com/blog/introducing-jwt-authentication-in-clickhouse-cloud",
  registration_url = "https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-configure-app-access-web-apis",
  registration = c(
    "Custom identity providers require a ClickHouse Cloud Enterprise service running 26.4 or later (26.8 for EC signing keys). In the service's Settings > Security > JWT authentication, configure the trusted issuer, token audience and public HTTPS JWKS URL. A standard Cloud login or management API key does not establish this setup.",
    "For this Entra demo, expose a delegated scope on an API registration, and configure that API to issue v2 access tokens. Use the actual access-token issuer and audience accepted by ClickHouse; the API's Application ID URI used for requesting scopes can differ from its token audience.",
    "Define Entra app-role values that match existing ClickHouse roles, assign users or groups to them, and configure the service to read the roles claim. Grant those ClickHouse roles the data permissions your app needs. OAuth consent alone grants no table access.",
    "Register the Shiny client in Entra with the callback below and permission for the API's delegated scope. Use Mobile and desktop applications for public PKCE, or Web for a confidential app. Copy Directory (tenant) ID and Application (client) ID; enter a confidential secret through masked input or OAUTHDB_CLICKHOUSE_CLIENT_SECRET."
  ),
  cost = "Queries use your ClickHouse Cloud service and its normal compute allowance. Stopping the local app does not stop the service or change billing settings.",
  client_types = c("public", "confidential"), packages = list(jsonlite = NULL),
  readiness = "jwt_ready", validate = .odb_cloud_resource_scope,
  required = c("jwt_ready", "url", "tenant_id", "resource", "scope", "client_id"),
  fields = list(
    jwt_ready = .odb_cloud_field("Check custom JWT sign-in", "Does your qualifying ClickHouse Cloud service already trust your Entra issuer, audience and role claims? 1: Yes; 2: Not ready yet (save a draft with setup links). A normal trial or console login alone is not sufficient.", "ready"),
    url = .odb_cloud_field("Find the HTTPS query endpoint", "Open the service's Connect dialog and copy its HTTPS endpoint, commonly https://your-service.clickhouse.cloud:8443. Use the database query endpoint, not the Cloud console or management API URL.", "https"),
    tenant_id = .odb_cloud_tenant_field(), resource = .odb_cloud_resource_field(), scope = .odb_cloud_scope_field(),
    database = .odb_cloud_field("Optional database", "Supply database when resuming to choose a default for your table queries. The first identity query needs none.")
  )
)
