# OpenSearch with user OAuth tokens

OpenSearch is an open-source search and analytics engine. It stores
documents in indexes and can search them or query them with its SQL
plugin. Use
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md)
to search OpenSearch with each Shiny visitor’s current OAuth access
token. It supports Query DSL, aggregations and the SQL plugin through
HTTPS. You do not need an OpenSearch R driver or JDBC.

## Try OpenSearch locally

Start Docker and run:

``` r

shinyOAuthDB::oauth_db_demo("opensearch")
```

The package starts OpenSearch 3.9.0 with its Security plugin, Keycloak
and a Shiny app. Alice and Bob see their own documents, and **Try a
write** shows that their roles cannot change the index. See [Local
Docker
demos](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.md)
for accounts and cleanup; allow at least 2 GB of Docker memory for
OpenSearch.

`oauth_db_demo("opensearch", action = "files")` copies the
configuration. `opensearch/prepare.py` creates the signing-key, role and
document-permission settings; `realm-extended.json` configures the
corresponding Shiny client. The signing key is a startup snapshot. For
rotating keys, use the OIDC authenticator described later in this guide.

## Settings for the example

The cluster needs the Security plugin, HTTPS and bearer-token
authentication. Its OIDC/JWT and role configuration follow the app
example.

| Setting | Where to get it |
|----|----|
| `url` | The cluster’s HTTPS API endpoint, rather than the Dashboards page |
| Index, such as `orders` | OpenSearch Dashboards’ index list or your administrator |
| Issuer, client ID, secret | The [Shiny registration](https://lukakoning.github.io/shinyOAuthDB/articles/oauth-setup.md) with the cluster’s trusted provider |
| `search.read` | The example API scope; define it in your provider or use your deployment’s scope |

Save `OAUTHDB_OPENSEARCH_ISSUER`, `OAUTHDB_CLIENT_ID` and
`OAUTHDB_CLIENT_SECRET` in `.Renviron`, then restart R. AWS endpoints
that require SigV4 need a different client.

## A complete app

Replace the cluster URL and index name. This example assumes the
provider exposes a `search.read` scope; use your own registration’s
scopes.

``` r

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_OPENSEARCH_ISSUER")
)
client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = "http://localhost:8100",
  scopes = c("openid", "search.read")
)

ui <- oauth_ui(
  fluidPage(
    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),
    verbatimTextOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  search <- oauth_db_opensearch_api(
    auth$connection,
    url = "https://search.example.org",
    required_scopes = "search.read"
  )
  output$rows <- renderPrint({
    result <- search$search(
      "orders",
      body = list(
        size = 20L,
        query = list(term = list(country = "NL"))
      )
    )
    result$hits
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

Run `source("example.R")`. The app waits for sign-in before making
requests and clears the output on sign-out. If your provider requires a
resource parameter or named token target, configure it in shinyOAuth and
pass the target name to the helper’s `target` argument.

## Configure cluster authentication and permissions

Enable the Security plugin and configure its [OpenID Connect
authentication](https://docs.opensearch.org/latest/security/authentication-backends/openid-connect/)
or [JWT
authentication](https://docs.opensearch.org/latest/security/authentication-backends/jwt/).
The cluster must accept the access tokens issued to your Shiny client,
validate their issuer and audience, and map their subject and backend
roles to OpenSearch roles. Enable HTTPS with a trusted certificate.

For JWT authentication, the relevant HTTP authentication settings are:

``` yaml
jwt_auth_domain:
  http_enabled: true
  transport_enabled: false
  order: 0
  http_authenticator:
    type: jwt
    challenge: false
    config:
      jwt_header: Authorization
      jwt_url_parameter: null
      subject_key: sub
      roles_key: roles
      required_issuer: https://login.example.org/realms/reporting
      required_audience: opensearch-reporting
      signing_key: |
        -----BEGIN PUBLIC KEY-----
        Replace with the trusted issuer's public signing key.
        -----END PUBLIC KEY-----
  authentication_backend:
    type: noop
```

This is a configuration fragment, with a placeholder key. Add it to the
cluster’s HTTP authentication configuration using the Security plugin’s
administration procedure. For discovery and rotating signing keys,
configure the OIDC authenticator instead of copying this static-key
example.

Map the provider’s role claims to roles granting access to the required
indexes and operations. OpenSearch document-level and field-level
security can further limit which documents and fields each visitor
receives. The helper forwards the token; the server makes these
decisions. A login to OpenSearch Dashboards alone does not establish API
access.

The endpoint must accept OAuth bearer tokens. AWS IAM/SigV4
authentication requires a different client; this helper does not sign
AWS requests.

## Register the Shiny client

Register an OAuth client with the trusted identity provider. Allow
`http://localhost:8100` as its redirect URI and request an access token
for the audience configured on OpenSearch. Configure any role claims the
cluster requires. Request your provider’s scopes, including
`offline_access` if it requires that scope for renewal.

Save the registration in `.Renviron` and restart R:

``` text
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
OAUTHDB_OPENSEARCH_ISSUER=https://login.example.org/realms/reporting
```

## Search results and aggregations

Results retain their native structure: `result$hits$hits` contains
documents and metadata, `result$hits$total` contains the total and its
relation, and `result$aggregations` contains aggregation results. Arrays
stay lists and large JSON integers remain strings. This avoids
flattening nested documents or losing precision. Select the fields you
need when building a table.

An empty `body = list()` becomes
[`{}`](https://rdrr.io/r/base/Paren.html). Use named R lists for JSON
objects and unnamed lists for JSON arrays, including single-element
arrays. For a nested empty JSON object, use
`structure(list(), names = character())`.

``` r

result <- search$search(
  "orders",
  body = list(
    size = 0L,
    aggs = list(countries = list(terms = list(field = "country")))
  )
)
result$aggregations$countries$buckets
```

An index can be a pattern or a vector such as
`c("orders-*", "archive")`. Omitting it uses the cluster-wide endpoint;
permissions may reject searches spanning restricted indexes. Paginate
explicitly with `from`/`size`, or a stable sort and `search_after`. The
helper never fetches additional pages automatically. Searches reporting
a timeout or failed shards raise an error. Use `raw = TRUE` to inspect
their native response, or `$request()` for responses reduced with
`filter_path`.

## SQL and native JSON requests

SQL requires the server’s SQL plugin and permissions for its APIs, index
reads and required index metadata. The response preserves `schema`,
`datarows`, totals and any cursor, using the plugin’s JDBC JSON format:

``` r

page <- search$sql(
  "SELECT owner, total FROM orders WHERE country = ?",
  parameters = list(list(type = "keyword", value = "NL"))
)
page$schema
page$datarows
```

Parameters use the plugin’s native typed descriptors and `?`
placeholders; values are not interpolated into SQL. Dates and other
values requiring a specific representation should be encoded according
to the server’s type.

Use `$request()` for other JSON APIs. For example, a paginated SQL
request uses
`list(query = "SELECT owner FROM orders", fetch_size = 20L)` as its
body, followed by `list(cursor = page$cursor)` to obtain another page
from the same SQL endpoint. Close an unfinished cursor by posting its
value to `c("_plugins", "_sql", "close")`. Consume or close cursors
before switching accounts; the client does not store cursor state or
close server resources automatically. Bulk NDJSON needs a separate
native client.

## Tokens, errors and TLS

Each operation obtains a current token and checks the authorization
again after the response arrives. Responses from an ended or replaced
authorization are discarded. GET and HEAD may renew once after HTTP 401;
POST searches, SQL, writes and other mutations are never replayed. A
timeout or sign-out stops local access; submitted work can continue on
the server.

HTTP errors report a status and safe diagnostics without echoing
response bodies or credentials. `raw = TRUE` returns an httr2 response
for successful requests. Use it with httr2 response helpers when
inspecting native JSON.

Pass `ca_bundle = "path/to/private-ca.pem"` for a private CA. On
Windows, if the default Schannel curl backend does not accept your PEM
CA bundle, set `CURL_SSL_BACKEND=openssl` in `.Renviron` and restart R
before loading the package. Certificate and hostname verification remain
enabled.

The source checkout’s [OpenSearch OAuth
fixture](https://github.com/lukakoning/shinyOAuthDB/tree/main/integration/opensearch-oauth)
tests real signed JWTs, document and field permissions, SQL and TLS.
With Docker and the R test dependencies installed, run
`Rscript --vanilla tools/check-opensearch-oauth.R` from the repository
root. It creates its own certificates and tokens; no production
credentials are used.
