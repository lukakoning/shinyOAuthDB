# Google Cloud SQL

Google Cloud SQL hosts PostgreSQL databases. With IAM database
authentication, visitors can sign in to your Shiny app with their Google
account and query the database using their own SQL permissions.

[`oauth_db_cloud_sql_postgres()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_sql_postgres.md)
opens native DBI connections using the visitor’s access token as the
database password. shinyOAuth handles browser sign-in and token renewal.
The app doesn’t need a Google service account or Application Default
Credentials.

## Set up access

Ask your administrator to enable IAM database authentication on the
instance, add the intended IAM users or groups, and grant **Cloud SQL
Instance User** (`roles/cloudsql.instanceUser`). They must also grant
database privileges, such as permission to connect to `reporting` and
read its tables. IAM login permission alone doesn’t grant access to
data.

Google documents these steps in its [PostgreSQL IAM login
guide](https://docs.cloud.google.com/sql/docs/postgres/iam-logins). This
package’s Cloud SQL helper supports PostgreSQL. MySQL support is
deferred pending driver validation, and Cloud SQL for SQL Server doesn’t
provide this IAM database login path.

Register a **Web application** OAuth client in Google Cloud, configure
its consent screen and register `http://localhost:8100` as an authorized
redirect URI. Use an internal audience for a Workspace organization when
appropriate; external apps may need test users or Google’s verification
process. See [Google’s Web server OAuth
setup](https://developers.google.com/identity/protocols/oauth2/web-server).
Save the client ID and secret in your local `.Renviron`, then restart R:

``` text
OAUTHDB_CLIENT_ID=your-google-client-id
OAUTHDB_CLIENT_SECRET=your-google-client-secret
```

The sign-in preset requests `openid`, `email`, and
`https://www.googleapis.com/auth/sqlservice.login`. It doesn’t request
Cloud SQL administration. Keep this Google client separate from clients
requesting permissions for other data platforms.

Install RPostgres linked to libpq 16 or later.

## Configure the network and certificates

The app host needs a direct route to the instance: an authorized public
IP, or access to its private network. These helpers enforce server
identity verification, so use a hostname matching the database’s server
certificate and a trusted CA bundle.

| Value | Where to find it |
|----|----|
| `host` | The DNS name in the instance’s server certificate; configure DNS so the app host can resolve it |
| `dbname` | A database created on the Cloud SQL instance |
| `user` | The signed-in IAM user’s full email address |
| `sslrootcert` | The CA bundle for the instance’s server certificate |
| Client certificate and key | The instance’s client certificate settings, if required |

Shared and customer-managed server CAs support DNS-based identity
verification. With a per-instance CA, Google restricts DNS-based
verification to instances configured with Private Service Connect.
Choose an instance configuration with a matching certificate name;
entering an ordinary instance IP as `host` won’t work if that IP isn’t
in its certificate. See Google’s [PostgreSQL TLS
setup](https://docs.cloud.google.com/sql/docs/postgres/configure-ssl-instance).

PostgreSQL also accepts `hostaddr` when you need to connect to an IP
while checking the certificate against the DNS name in `host`. It still
requires that name to match the certificate.

## A complete PostgreSQL app

Save this as `example.R`. Replace the hostname, database and CA file
path with your instance’s settings. The username function reads the
email from the selected sign-in’s validated identity, so switching
accounts also changes the database username.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_cloud_sql_client(
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100"
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

  database_user <- function() {
    reference <- req(auth$connection())
    identity <- reference$identity(claims = "email")
    req(identity$id_token_claims$email)
  }
  con <- oauth_db_cloud_sql_postgres(
    auth$connection,
    host = "db.example.org",
    dbname = "reporting",
    user = database_user,
    sslrootcert = "path/to/server-ca.pem"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT current_user AS database_user")
  })
}

runApp(
  shinyApp(ui, server, uiPattern = ".*"),
  port = 8100,
  launch.browser = FALSE
)

# Open the app in your regular browser at http://localhost:8100
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
```

Sign in to see your PostgreSQL username. To read a table, replace the
query with `SELECT * FROM reporting.orders LIMIT 20`, using your own
table name. The database enforces that user’s grants and any row
policies. Use DBI parameter binding for values entered by visitors.

## Connection lifetime and other settings

Create the helper inside `server()` and resolve `connection <- con()`
before each query. Ordinary token renewal doesn’t rerun completed
reactive queries. On the next access after the token changes, the helper
replaces the connection so reconnection uses current credentials. Finish
a transaction on the connection that started it. Account changes, loss
of required permissions, sign-out and session end close the connection.
A retained native handle isn’t a substitute for calling `con()`.

For instances requiring client certificates, supply `sslcert` and
`sslkey` together. Leave `PGSERVICE` and `PGSERVICEFILE` unset.
Authentication and TLS settings cannot be changed through `...`.

The default `required_scopes` checks Cloud SQL login permission in the
authorization. For a custom Google client using an alternative accepted
scope, set `required_scopes` to match that client’s granted scopes. The
database still validates the access token and IAM permissions.

These helpers implement Google’s **manual IAM database authentication**.
A shared Cloud SQL Auth Proxy started with `--auto-iam-authn` signs in
as the account that runs the proxy; it doesn’t select a different
identity for each Shiny visitor. This guide uses direct TLS connections.
The package doesn’t start or configure a proxy.
