# Oracle Database

Use
[`oauth_db_oracle()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle.md)
to query Oracle Database with each visitor’s OAuth access token. It
returns a DBI connection for SQL and dbplyr. Oracle must trust the
token’s provider and map the visitor to database privileges.

The helper supports two authorization models:

| Model | Oracle setup | Helper argument |
|----|----|----|
| Global schema | A database global user mapped to an external identity; existing Entra configurations use this model | `authorization_model = "global"` (default) |
| End-user context | Oracle Deep Data Security direct logon with user data roles, including configured OCI IAM OAuth and Keycloak integrations | `authorization_model = "end_user"` |

For OAuth-protected HTTP resources, use the separate [Oracle REST Data
Services
guide](https://lukakoning.github.io/shinyOAuthDB/articles/oracle-ords.md).

## Set up the database and driver

Ask your administrator for a TCPS listener address, port, service name,
trusted identity provider and database access scope. The server needs
the corresponding global-schema or data-role mappings. Signing in to the
Shiny app does not create those mappings.

Choose the provider setup that matches your deployment:

- **Microsoft Entra:** configure the [Entra database
  integration](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/configuring-oracle-database-microsoft-entra-id-integration.html).
  Existing global-schema configurations use `"global"`; Deep Data
  Security direct-logon configurations use `"end_user"`.
- **OCI IAM Identity Domains OAuth:** configure
  `IDENTITY_PROVIDER_TYPE=OCI_IAM` and the database’s OAuth application
  and domain. Oracle documents the [OAuth configuration
  parameter](https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/IDENTITY_PROVIDER_OAUTH_CONFIG.html)
  from Oracle 26ai RU 23.26.2. Follow the database’s supported
  administrative setup, particularly for Autonomous Database. This is an
  OAuth bearer-token flow, separate from OCI IAM proof-of-possession
  authentication.
- **Keycloak:** Oracle’s current 26ai Deep Data Security guide documents
  `IDENTITY_PROVIDER_TYPE=OAUTH2` with issuer, JWKS, audience and claim
  mappings. Keycloak is the initial supported configurable provider;
  this integration is unavailable on Autonomous Database. Follow
  [database IAM
  configuration](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/configure-database-iam-integration.html)
  and the [direct-login
  procedure](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/configure-sql-client-end-user-direct-logon.html).

Install the R package `odbc` and Oracle Instant Client’s **Basic** and
**ODBC** packages for the architecture of your R process. Register the
Oracle ODBC driver and find its name with
[`odbc::odbcListDrivers()`](https://odbc.r-dbi.org/reference/odbcListDrivers.html).
Use a current supported Oracle client with the required token
integration. The Entra thick-client path is documented from 19c 19.16,
excluding the 21c thick client. OCI IAM OAuth and configurable-provider
Deep Data Security require newer database features and a compatible
current client. Check your actual server release, update level and
driver against Oracle’s [ODBC setup
guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/odbcd/using-oracle-database-odbc-driver.html)
and [client support
table](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/supported-client-drivers-entra-ad-connections.html).

The client needs a trusted TLS certificate chain. Depending on the
client, platform and database, use its configured trust store or pass an
Oracle wallet directory as `wallet_location`. A database requiring
mutual TLS also needs the client certificate in that wallet. Use
`server_cert_dn` when your administrator supplies the expected
certificate distinguished name; otherwise the client matches the
hostname. Certificate matching is always enabled.

For OCI IAM OAuth, Oracle’s direct-login procedure specifies the server
certificate DN. Copy it from the administrator’s connection details (or
the downloaded Autonomous wallet alias) into `server_cert_dn` when
calling the helper. Use the matching wallet when the service requires
mutual TLS.

## Register the Shiny application

Register an authorization-code client with PKCE at the provider trusted
by the database. Register `http://localhost:8100` as its redirect URI.
The app needs the database access scope and the corresponding user or
group assignments. Configure the provider to issue the database audience
and required identity and role claims. For Keycloak, configure an
audience mapper and a top-level role claim matching Oracle’s provider
configuration.

The complete app below uses OIDC discovery for a Keycloak or OCI IAM
Identity Domains provider with OpenID Connect enabled. Its `"end_user"`
mode requires Oracle Deep Data Security direct logon. Enable
refresh-token issuance when requesting `offline_access`, or replace that
scope with your provider’s documented refresh setup. An Entra
alternative follows the app.

Save the app settings in your local `.Renviron` and restart R:

``` text
OAUTHDB_CLIENT_ID=your-shiny-app-client-id
OAUTHDB_CLIENT_SECRET=your-shiny-app-client-secret
OAUTHDB_ORACLE_ISSUER=https://login.example.org/realms/reporting
OAUTHDB_ORACLE_SCOPE=database.read
OAUTHDB_ORACLE_HOST=database.example.org
OAUTHDB_ORACLE_SERVICE=reporting.example.org
OAUTHDB_ORACLE_DRIVER=Oracle in instantclient_19_30
```

| Setting | Where to find it |
|----|----|
| `OAUTHDB_ORACLE_ISSUER` | OIDC issuer configured for the database’s provider |
| `OAUTHDB_ORACLE_SCOPE` | Exact database access scope supplied by the administrator; OCI IAM uses the resource audience concatenated with the scope name |
| Host, service and TCPS port | Oracle connection details supplied by the administrator |
| Driver | Installed driver name reported by [`odbc::odbcListDrivers()`](https://odbc.r-dbi.org/reference/odbcListDrivers.html) |
| Wallet and certificate DN, if needed | Oracle administrator’s TLS configuration |

## A complete app

The scope name below is checked literally. Configure the token audience
on the authorization server for this client and database:

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

scope <- Sys.getenv("OAUTHDB_ORACLE_SCOPE")
provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_ORACLE_ISSUER")
)
client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("openid", "profile", "offline_access", scope),
  required_scopes = scope
)

ui <- oauth_ui(
  fluidPage(
    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),
    tableOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_oracle(
    auth$connection,
    host = Sys.getenv("OAUTHDB_ORACLE_HOST"),
    service_name = Sys.getenv("OAUTHDB_ORACLE_SERVICE"),
    driver = Sys.getenv("OAUTHDB_ORACLE_DRIVER"),
    port = 1522L,
    authorization_model = "end_user"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(
      connection,
      "SELECT ORA_END_USER_CONTEXT.username AS database_user FROM DUAL"
    )
  })
}

runApp(
  shinyApp(ui, server, uiPattern = ".*"),
  port = 8100,
  launch.browser = FALSE
)
```

Save the code as `example.R`, set your TCPS port and any wallet or
certificate DN arguments, then run `source("example.R")`. Open
`http://localhost:8100` in your regular browser and sign in. The example
shows the Oracle end-user identity. Replace the query with a table or
view the user can read.

## Microsoft Entra alternative

For Entra, use the Microsoft client with a custom database resource
target. Register a **Web** application with the same redirect URI and
the database’s delegated permission, commonly `session:scope:connect`.
Your administrator must configure global-schema or data-role mappings
and access-token claims; Entra v2 setup includes the `upn` claim. See
Oracle’s [registration
example](https://docs.oracle.com/en/learn/ocidb-auth-msentraid/) and
[Microsoft app
registration](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.html#register-a-microsoft-entra-app).

``` r

resource <- Sys.getenv("OAUTHDB_ORACLE_RESOURCE")
scope <- paste0(resource, "/session:scope:connect")
client <- oauth_db_microsoft_client(
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  token_targets = list(
    oracle = list(resource = resource, scopes = scope, required_scopes = scope)
  )
)
```

`OAUTHDB_ORACLE_RESOURCE` is the database server’s Entra Application ID
URI, not the Shiny application’s client ID. In the app’s connection
helper, set `target = "oracle"`. For an existing global-schema
deployment, set `authorization_model = "global"` and query
`SELECT USER FROM DUAL` to inspect the database schema identity. For
Deep Data Security use `authorization_model = "end_user"` and retain the
end-user identity query. Keep `/.default` consent markers in client
settings; `required_scopes` now treats every provider’s scope names
literally.

## Connections and token files

shinyOAuth handles browser sign-in and token renewal. The adapter
obtains the current access token when opening a connection. It supplies
a separate Oracle Net descriptor containing `TOKEN_AUTH=OAUTH` and the
location of a temporary token file. It does not change shared Oracle
configuration files or the process’s `TNS_ADMIN` environment variable.

The token file is removed after connection opening, including on error
or interrupt. On Unix, its directory is private (`0700`) and the file
has mode `0600`. On Windows, use a private R temporary directory because
access rules are inherited from its parent directory.

Before returning a connection, the helper verifies the chosen model:

- `"global"` requires `SYS_CONTEXT('USERENV', 'AUTHENTICATION_METHOD')`
  to report `TOKEN_GLOBAL`.
- `"end_user"` reads only issuer, subject and audience from Oracle’s
  system-managed `ORA_END_USER_CONTEXT.USER.TOKEN` and requires them to
  match the submitted JWT. Local decoding establishes the expected
  claims; Oracle validates the token and establishes the context.
  Missing or mismatched context closes the connection, even if a
  global-schema login succeeded. This prevents global-user precedence
  from silently bypassing the requested Deep Data Security model.

Global-schema connections survive ordinary token renewal. End-user
connections reopen on the next `con()` call when the token changes, so
updated role claims reach the database. This does not replay completed
reactive queries. Account changes, permission loss, sign-out and Shiny
session end close both types. Always call `con()` before each operation.

The helper disables Oracle ODBC failover. Reopen a broken connection by
calling `con()` so the new connection gets a current token. It does not
implement OCI IAM proof-of-possession authentication, password login,
proxy-user connections or application-mediated two-token contexts.

Automated checks cover ODBC arguments, token and context verification,
credential cleanup and the Shiny lifecycle. Live Oracle/client/provider
compatibility remains unverified; there is no local Oracle identity
demo.
