# Amazon Redshift

Amazon Redshift is AWS’s hosted SQL data warehouse. Query Amazon
Redshift from Shiny using each visitor’s own database access. The
connection works with DBI, so you can use your existing SQL queries.

This example signs users in through Microsoft Entra. It requires a
Redshift deployment already linked to AWS IAM Identity Center.

## Try the guided demo

Run `shinyOAuthDB::oauth_db_cloud_demo("redshift")` in your R console.
The guide first asks whether IAM Identity Center and Entra trusted-token
integration are ready. Choose **Not ready yet** to save a draft and get
setup links. An AWS account and SQL endpoint alone don’t provide this
flow. Once configured, resume with `identity_center_ready = "yes"`.

The guide asks for `server`, `database`, `tenant_id`, accepted API
`resource`, fully qualified delegated `scope` and Shiny OAuth
`client_id`. Administrators must coordinate the trusted issuer, JWT
audience and user mappings; the resource and scope are not the Redshift
hostname. The generated example uses Microsoft Entra and `EXT_JWT`
through `IdpTokenAuthPlugin`.

Install `odbc`, `processx`, `askpass` and the Redshift ODBC 2.x driver.
Optional `driver` and `database_port` adjust its connection settings. A
confidential client uses `OAUTHDB_REDSHIFT_CLIENT_SECRET` or masked
input. The editable app waits for **Run example query**; stopping it
doesn’t stop Redshift compute or billing. See [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#more-ways-to-try-an-app).

With no AWS deployment, read [Getting started with
Redshift](https://docs.aws.amazon.com/redshift/latest/gsg/getting-started.html).
Trial availability does not establish trusted-identity readiness; this
guide doesn’t provision resources or configure IAM Identity Center.

## Set up access

In R, run `install.packages("odbc")`. Install the [AWS Redshift ODBC 2.x
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

OAuth setup spans AWS and the identity provider. The [AWS integration
guide](https://docs.aws.amazon.com/redshift/latest/mgmt/redshift-iam-access-control-idp-connect-oauth.html)
explains which tokens `IdpTokenAuthPlugin` accepts. This needs a real
AWS deployment; there is no local Docker equivalent.

## A complete app

Save this as `example.R`, replacing the server and database:

``` r

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
    tableOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_redshift(
    auth$connection,
    server = "cluster.example.eu-west-1.redshift.amazonaws.com",
    database = "reporting",
    target = "redshift"
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
