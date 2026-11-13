# Query Elasticsearch as the signed-in user

Search documents, run SQL or use ES\|QL with each visitor's access
token. Results keep Elasticsearch's native JSON structure as R lists.

## Usage

``` r
oauth_db_elasticsearch_api(
  authorization,
  url,
  client_secret = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 30,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- url:

  HTTPS Elasticsearch deployment URL, including a proxy path if needed.

- client_secret:

  JWT realm's application shared secret. This is separate from the OAuth
  registration's client secret. Use `NULL` only when the realm
  explicitly disables client authentication.

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

- timeout:

  Maximum seconds for one HTTP operation, including a read retry.

- ca_bundle:

  Optional path to a trusted CA certificate bundle.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A client object with these methods:

- `$search(index = NULL, body = list(), query = list(), raw = FALSE)`
  runs a JSON search. The index may be a name, pattern or character
  vector; `NULL` searches across the deployment.

- `$sql(sql, parameters = list(), raw = FALSE)` returns one SQL result
  page, including `columns`, `rows` and any `cursor`.

- `$esql(query, parameters = list(), raw = FALSE)` returns ES\|QL
  `columns`, `values` and completion metadata.

- `$request(path, method = "GET", query = list(), body = NULL, raw = FALSE)`
  calls a JSON API using relative path segments.

## Details

Configure an Elasticsearch JWT realm to accept the provider's JWT access
tokens and map their principal and groups to Elasticsearch roles. The
`access_token` realm type requires allowed subjects or subject patterns.
JWT realms require Elasticsearch 8.7 or later for this token type and an
appropriate subscription. This route supports self-managed and Elastic
Cloud Hosted deployments; Elastic Cloud Serverless has no JWT realms.
Kibana OIDC sign-in alone does not configure API access.

Create the client inside `server()`. Each request obtains a current
access token and discards results after sign-out, account changes or
lost required permissions. GET and HEAD can refresh and retry once after
HTTP 401. POST queries and writes are never replayed automatically.
Requests use verified HTTPS and do not follow redirects.

The realm shared secret identifies the application; the visitor's token
determines their data permissions. It is sent in the redacted
`ES-Client-Authentication` header. No ID token, API key or impersonation
header is substituted for the visitor's access token.

## Parameters and results

SQL and ES\|QL accept `?` placeholders with an unnamed list of scalar
strings, logicals, finite numbers or `NULL` in `parameters`. Values are
sent separately from the query. ES\|QL and its parameter syntax require
a server version that supports them. Use `$request()` for other native
parameter forms or query options.

Large JSON integers remain strings; nested documents and multivalued
fields remain lists. Search timeouts, shard failures, skipped remote
clusters and partial query results raise errors. Use `raw = TRUE` for
the httr2 response instead.

There is no automatic pagination. Use `search_after` for searches, or
`$request("_sql", method = "POST", body = list(cursor = cursor))` for
SQL pages. Close unused SQL cursors with
`$request(c("_sql", "close"), method = "POST", body = list(cursor = cursor))`.
Keep cursors and point-in-time identifiers with the authorization that
created them and discard them on sign-out or account changes. NDJSON
APIs need a different client.

## See also

[`vignette("elasticsearch", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/elasticsearch.md).

## Examples

``` r
if (FALSE) { # \dontrun{
search <- oauth_db_elasticsearch_api(auth$connection,
  url = "https://search.example.org",
  client_secret = Sys.getenv("OAUTHDB_ELASTICSEARCH_REALM_SECRET"))
output$rows <- shiny::renderPrint({
  search$sql("SELECT country, total FROM orders WHERE country = ?",
    parameters = list("NL"))$rows
})
} # }
```
