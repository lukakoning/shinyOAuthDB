# Amazon Athena

Amazon Athena runs SQL queries over data in Amazon S3 and other
configured sources.
[`oauth_db_athena()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_athena.md)
opens a DBI connection using the visitor’s JWT access token through IAM
Identity Center trusted identity propagation. AWS applies the data
permissions configured for that identity.

This requires an administrator to connect your identity provider to AWS.
An ordinary AWS console login or an AWS access key isn’t that
integration.

## Prepare the workgroup and sign-in

Install `odbc` in R and the [Amazon Athena ODBC 2.x
driver](https://docs.aws.amazon.com/athena/latest/ug/odbc-v2-driver.html),
version 2.5.0.0 or later, on the Shiny server. The driver is available
for Windows, macOS and Linux x86_64. You don’t need an AWS SDK for R or
Python.

Ask your AWS administrator to follow [Connect Athena to IAM Identity
Center](https://docs.aws.amazon.com/athena/latest/ug/using-trusted-identity-propagation-setup.html).
The deployment needs a trusted external token issuer, a federated IAM
application role, an access role and an Identity Center customer managed
application associated with the Athena workgroup. Configure user
matching and the users’ Lake Formation/data permissions too. Signing in
doesn’t create those grants.

Register a Web OAuth app with your identity provider, with
`http://localhost:8100` as the redirect URI. It must issue **JWT access
tokens** whose issuer and audience AWS accepts. Ask the administrator
for the delegated scopes to request; there is no universal Athena scope.
AWS also needs to be able to reach the issuer’s signing keys.

Save the settings in a local `.Renviron`, then restart R:

``` text
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
OAUTHDB_ATHENA_ISSUER=https://login.example.org/realms/reporting
OAUTHDB_ATHENA_SCOPES=database.read
OAUTHDB_ATHENA_WORKGROUP_ARN=arn:aws:athena:eu-west-1:123456789012:workgroup/reporting
OAUTHDB_ATHENA_APPLICATION_ROLE_ARN=arn:aws:iam::123456789012:role/AthenaApplication
OAUTHDB_ATHENA_OUTPUT=s3://your-query-results/reporting/
```

| Setting | Where to get it |
|----|----|
| Issuer, client ID, secret and scopes | Your identity provider’s OAuth registration and the administrator who configured AWS trust |
| Workgroup ARN | Athena console, under the configured workgroup; includes its region and name |
| Application role ARN | The IAM application role configured for `AssumeRoleWithWebIdentity` |
| S3 output location | The results bucket/prefix approved for this workgroup |

The application role and access role serve different purposes. Supply
the application role to `application_role_arn`; the driver uses the
deployment’s tags to discover the other role and Identity Center
application. Workgroup settings can override the supplied results
location or encryption settings. Follow your organization’s rules for
access to saved query results.

## A complete app

Save this as `example.R`. Replace the query’s table name with one that
your users can read. Signing in runs the query, and Athena may charge
for it.

After signing in, click **Load rows**. The app starts its workers once
and stops them at shutdown.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

athena_scopes <- strsplit(
  Sys.getenv("OAUTHDB_ATHENA_SCOPES"),
  " ",
  fixed = TRUE
)[[1L]]

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_ATHENA_ISSUER")
)

client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("openid", "profile", "offline_access", athena_scopes)
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

  con <- oauth_db_athena(
    auth$connection,
    workgroup_arn = Sys.getenv("OAUTHDB_ATHENA_WORKGROUP_ARN"),
    application_role_arn = Sys.getenv("OAUTHDB_ATHENA_APPLICATION_ROLE_ARN"),
    s3_output_location = Sys.getenv("OAUTHDB_ATHENA_OUTPUT"),
    required_scopes = athena_scopes,
    schema = "default"
  )

  query_task <- oauth_db_task(con)

  observeEvent(input$load, {
    query_task$invoke("SELECT * FROM example_table LIMIT 20")
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

If your provider needs a resource/audience parameter, configure that on
the shinyOAuth client according to your provider’s requirements. For
Microsoft Entra, use
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md)
with a custom token target for your registered resource, then select it
with `target` on
[`oauth_db_athena()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_athena.md).
The [Redshift
guide](https://lukakoning.github.io/shinyOAuthDB/articles/redshift.html#a-complete-app)
shows this client configuration pattern; use your Athena integration’s
resource and scopes.

## Driver settings

`workgroup_arn` supplies both `AwsRegion` and `Workgroup`, so those
settings can’t point to different workgroups. Set `catalog` and `schema`
to select the data catalog and database. Set `driver` if your installed
driver’s registered name differs from `"Amazon Athena ODBC Driver"`.

For a deployment without ARN-discovery tags, supply `access_role_arn`
and `customer_idc_application_arn` explicitly. Both must belong to the
same AWS partition as the workgroup; their accounts can differ.

The helper accepts these options through `...`:

- R odbc options: `timeout`, `timezone`, `timezone_out`, `bigint`,
  `encoding`, `name_encoding`, `interruptible`.
- Driver timeouts/polling: `ConnectionTimeout`, `RequestTimeout`,
  `MaxPollDuration`, `MinQueryExecutionPollingInterval`,
  `MaxQueryExecutionPollingInterval`,
  `QueryExecutionPollingIntervalMultiplier`.
- Results/metadata: `RowsToFetchPerBlock`, `ResultFetcher`,
  `StringColumnLength`, `ComplexTypeColumnLength`, `BinaryColumnLength`,
  `S3ResultBlockSize`, `UseWCharForStringTypes`,
  `UseSingleCatalogAndSchema`, `QueryExternalCatalogs`.
- Results encryption and CA configuration: `S3OutputEncOption`,
  `S3OutputEncKMSKey`, `TrustedCerts`.

See AWS’s [main connection
parameters](https://docs.aws.amazon.com/athena/latest/ug/odbc-v2-driver-main-connection-parameters.html)
and [advanced
options](https://docs.aws.amazon.com/athena/latest/ug/odbc-v2-driver-advanced-options.html)
for their values and units. `TrustedCerts` follows the driver’s platform
rules: Windows uses its system trust store. TLS verification stays
enabled. The default result fetcher can use S3 or streaming; check the
driver’s network and permission requirements, including port 444 for
streaming.

DSNs, AWS keys/profiles, alternate authentication, endpoint overrides
and native logging options aren’t accepted. The helper supplies
`JWT_TIP`, the visitor token and a random role session name, and
disables file credential caching, connection-check caching and result
reuse. It doesn’t write the token to a file or replace the Shiny
process’s AWS credentials.

## Connections and renewal

Call `con()` before each operation. The helper reuses a valid connection
while its token is unchanged. A changed token replaces the connection on
the next access; finish reading and clear outstanding DBI results first.
Ordinary token renewal doesn’t rerun completed reactive queries.
Sign-out, account changes, permission loss and session end close the
connection.

Identity Center may restrict repeated exchanges of tokens containing a
`jti` claim. A reconnect can therefore require a newly issued access
token; if the provider can’t renew it, sign in again. The helper doesn’t
enable a shared credential cache or replay a failed query to work around
this.

Closing the connection doesn’t guarantee that AWS cancels a submitted
query. Use Athena’s query history and your workgroup’s limits to manage
running queries and costs. Clear app-cached results on account changes
as described in [Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#sessions-saved-results-and-extra-permissions).

## Validation boundary

Offline tests cover driver arguments, credential isolation, token
renewal, connection cleanup, rejected overrides and construction of this
app. The native Linux fixture checks token forwarding and TLS hostname
rejection, then opens connections and runs SQL using synthetic AWS
protocol responses. It checks separate users and renewed tokens with
interleaved queries. These checks don’t establish live Identity Center
exchange, Lake Formation grants, S3 result access or query execution.
Validate those with two differently authorized users in your configured
AWS deployment before relying on it.
