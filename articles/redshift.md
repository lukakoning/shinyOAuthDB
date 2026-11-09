# Amazon Redshift

Amazon Redshift is AWS’s hosted SQL data warehouse. Use it to supply
analytics data to a Shiny app with each visitor’s own database
permissions.
[`oauth_db_redshift()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_redshift.md)
opens a DBI connection for your SQL queries.

This guide signs users in with Microsoft Entra. It needs a Redshift
deployment linked to AWS IAM Identity Center, with the two services
configured to recognize those users. Your administrator must arrange
that connection before the app can use their sign-in.

## Try the guided demo

Run `shinyOAuthDB::oauth_db_cloud_demo("redshift")` in the R console for
an editable app. It checks whether your IAM Identity Center integration
is ready before asking for the database and Microsoft sign-in settings.
You can save a draft while an administrator configures access.

Install `odbc`, `bslib`, `processx`, `askpass` and the Redshift ODBC 2.x
driver. The app waits for **Run example query** before connecting;
stopping it leaves Redshift compute running. See
[`?oauth_db_cloud_demo`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_demo.md)
for launcher arguments and [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#more-ways-to-try-an-app)
for editing the app.

## Set up access

Install the [AWS Redshift ODBC 2.x
driver](https://docs.aws.amazon.com/redshift/latest/mgmt/odbc20-install.html)
with `IdpTokenAuthPlugin` support. Ask your administrator to configure
[Redshift’s IAM Identity Center
integration](https://docs.aws.amazon.com/redshift/latest/mgmt/redshift-iam-access-control-idp-connect-oauth.html)
and set up users’ database permissions.

Create an Entra Web app registration with `http://localhost:8100` as its
redirect URI. Ask the administrator for the OAuth resource and delegated
scope this deployment accepts.

Save those values and the app credentials in a local `.Renviron` file,
then restart R:

``` text
OAUTHDB_TENANT_ID=your-tenant-id
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
OAUTHDB_REDSHIFT_RESOURCE=your-redshift-resource
OAUTHDB_REDSHIFT_SCOPE=your-redshift-delegated-scope
```

| Value | Where to get it |
|----|----|
| `server` | AWS Redshift console: cluster or serverless workgroup endpoint, without the port suffix |
| `database` | Database name in that endpoint’s connection settings |
| Tenant ID, client ID, secret | The [Entra Web registration](https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html#register-a-microsoft-entra-app) |
| Resource and scope | The administrator who configured IAM Identity Center’s trusted token issuer and application |

For Entra, the resource is the accepted API identifier; the scope is the
delegated permission exposed by that registration. These values depend
on your AWS/Entra integration and aren’t the Redshift hostname. Give
this exact resource/scope pair to `token_targets` as below.

## A complete app

Save this as `example.R`, replacing the server and database:

After signing in, click **Load rows**. The app starts its workers once
and stops them at shutdown.

``` r

pkgs <- c("shiny", "shinyOAuth", "shinyOAuthDB", "mirai", "odbc")
for (pkg in pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
}

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  token_targets = list(
    redshift = list(
      resource = Sys.getenv("OAUTHDB_REDSHIFT_RESOURCE"),
      scopes = Sys.getenv("OAUTHDB_REDSHIFT_SCOPE")
    )
  )
)

ui <- oauth_ui(
  fluidPage(
    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),
    actionButton("load", "Load rows"),
    tableOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server(
    "auth",
    client,
    auto_redirect = FALSE,
    async = TRUE
  )
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())
  con <- oauth_db_redshift(
    auth$connection,
    server = "cluster.example.eu-west-1.redshift.amazonaws.com",
    database = "reporting",
    target = "redshift"
  )
  query_task <- oauth_db_task(con)
  observeEvent(input$load, {
    query_task$invoke("SELECT current_user AS database_user")
  })
  output$rows <- renderTable(query_task$result())
}

runApp(
  shinyApp(ui, server, uiPattern = ".*", onStart = function() {
    mirai::daemons(2)
    onStop(function() mirai::daemons(0))
  }),
  port = 8100,
  launch.browser = FALSE
)

# Open the app in your regular browser at its registered redirect URI.
```

Run `source("example.R")` and open `http://localhost:8100`. Sign in to
run the query; signing out clears the output.

The query shows the Redshift database user. Replace it with SQL for a
table that user can read. Call `con()` inside the reactive expression
before querying with DBI.

## Driver settings

The default driver name is `"Amazon Redshift (x64)"`. Set `driver` if
your installed driver has a different name or path. You can also pass
`CaFile` and `LoginTimeout` to the driver. The helper configures token
authentication and verified TLS.

## Other OAuth configurations

The default `token_type = "EXT_JWT"` uses an external provider’s JWT
access token, as in the Entra example. To use an IAM Identity Center
access token, set `token_type = "ACCESS_TOKEN"` and configure a
shinyOAuth client that obtains it. Other identity providers can use
their own shinyOAuth client with the same connection helper.

`target = "redshift"` selects the token target defined in the example
client. Match that name to your client, or use `target = NULL` if your
client has no named targets. [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#sessions-saved-results-and-extra-permissions)
explains these settings.
