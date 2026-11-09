# Query MongoDB as the signed-in user

Read MongoDB collections, run aggregation pipelines and issue database
commands using the visitor's OAuth access token. Uses the official
PyMongo driver through reticulate, with a separate client for each Shiny
session.

## Usage

``` r
oauth_db_mongodb(
  authorization,
  url,
  db,
  issuer,
  user = NULL,
  client_id = NULL,
  allowed_hosts = NULL,
  timeout = 30,
  ca_bundle = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- url:

  Credential-free `mongodb://` or `mongodb+srv://` connection URL.
  Authentication, TLS, retry and timeout options are set by the helper.

- db:

  Database name.

- issuer:

  Exact HTTPS issuer configured for MongoDB workforce OIDC.

- user:

  Optional MongoDB OIDC username, or a function returning it. Useful
  when the deployment uses the username to select an identity provider.

- client_id:

  Optional expected client ID in MongoDB's OIDC challenge.

- allowed_hosts:

  Hostnames to which PyMongo may send visitor tokens. An entry can start
  with `*.` to allow subdomains. Defaults to the seed hosts for ordinary
  URLs, or the cluster's parent domain for Atlas SRV URLs. Supply this
  explicitly for other SRV deployments or additional replica hosts.

- timeout:

  Positive operation timeout in seconds, including server selection,
  authentication and fetching result pages.

- ca_bundle:

  Optional trusted CA certificate file. TLS always verifies certificates
  and hostnames.

- target:

  Name of the service token to use in your shinyOAuth client. Named
  targets let one sign-in obtain tokens for different services. `NULL`
  uses the client's default token.

- required_scopes:

  Additional OAuth permissions to check before use. Request them on the
  shinyOAuth client first; this check doesn't request consent or grant
  database privileges.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A client with these methods:

- `$find(collection, filter = "{}", projection = "{\"_id\":0}", sort = "{}", skip = 0, limit = 100, simplify = TRUE)`
  reads documents.

- `$aggregate(collection, pipeline, simplify = TRUE)` consumes an
  aggregation cursor, including all result pages.

- `$count(collection, filter = "{}")` counts matching documents.

- `$run(command, simplify = FALSE)` issues one database command.
  Authentication, transaction and cursor commands are excluded.

Inputs use MongoDB JSON or Extended JSON strings. Reads return data
frames by default; `simplify = FALSE` preserves lists. BSON-specific
values retain their Extended JSON representation, and large integers
remain strings.

## Details

MongoDB must support workforce OIDC: Atlas with workforce federation, or
a supported Linux MongoDB Enterprise deployment. Community Server
doesn't provide this authentication. Configure the issuer, audience and
database user or group permissions before connecting.

Install reticulate and PyMongo 4.10 or later in its selected Python
environment. Python is initialized only on the first signed-in
operation; the helper never installs dependencies or chooses a different
interpreter. mongolite currently has no public OIDC callback for
supplying visitor tokens.

Create the client inside `server()`. shinyOAuth obtains and renews
tokens. PyMongo's human OIDC callback supplies only the current client's
access token after checking the server's issuer and optional client ID.
It never starts browser sign-in or uses workload credentials from the
app host.

Clients are replaced on their next use after token or username changes.
Sign-out, permission loss and session end close them. Results arriving
after an authorization change are discarded. Cursors are consumed and
closed in the operation that created them; transactions and retained
cursors aren't exposed. `limit = 0` fetches all matching documents.

Driver retryable reads and writes are disabled, and the helper doesn't
replay failed operations. PyMongo handles protocol reauthentication with
the same supplied token. A failed or timed-out operation can still have
effects on the server, including aggregation pipelines that write data.

## See also

[`vignette("mongodb", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/mongodb.md).

## Examples

``` r
if (FALSE) { # \dontrun{
mongo <- oauth_db_mongodb(auth$connection,
  url = "mongodb://mongo.example.org:27017", db = "reporting",
  issuer = "https://login.example.org/realms/reporting")
output$rows <- shiny::renderTable({
  mongo$find("orders", filter = '{"country":"NL"}', limit = 20)
})
} # }
```
