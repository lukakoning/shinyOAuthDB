# Query Neo4j as the signed-in user

Run Cypher queries with each Shiny visitor's access token and Neo4j
roles. The client uses the HTTPS Query API v2 and returns data frames,
keeping nodes, relationships, paths and other nested values in list
columns.

## Usage

``` r
oauth_db_neo4j_api(
  authorization,
  url,
  database = "neo4j",
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

  Neo4j HTTPS base URL, including any reverse-proxy prefix. Use the
  Query API host, not a `neo4j+s://` or `bolt://` connection URI.

- database:

  Database name, default `"neo4j"`.

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

- `$query(statement, parameters = list(), raw = FALSE)` runs one Cypher
  statement. Use named parameters such as `list(name = "Alice")` for
  `$name` placeholders. Returns a data frame, or the parsed Query API
  response with fields, values and metadata when `raw = TRUE`.

- `$execute(statement, parameters = list())` runs one statement and
  invisibly returns the server's update counters.

## Details

Configure Neo4j Enterprise SSO to accept the provider's JWT access
tokens and map users or groups to database roles. Aura requires a tier
and SSO configuration that permit user-token access to the database's
Query API. Console API credentials do not establish database access.
Query API v2 requires Neo4j 5.19 or later; self-managed versions before
5.25 must enable it.

Create the client inside `server()`. Each call gets a current access
token and discards responses after sign-out, account changes or lost
required scopes. Requests require verified HTTPS, do not follow
redirects and never replay a statement, including after HTTP 401. Neo4j
query errors raise an error even when the server returns HTTP 202 or
`raw = TRUE`.

Each statement uses an auto-commit transaction. There is no persistent
Bolt connection, explicit transaction handle, automatic pagination or
retained bookmark. A submitted write may commit after a client timeout;
check its outcome before resubmitting it.

## Parameters and results

Parameters are a named list of JSON-compatible values. Nested named
lists become maps and unnamed lists become arrays. Missing scalar values
become JSON null. Numbers must be finite; pass exact large integers as
strings and convert them in Cypher with `toInteger($value)`. Dates and
timestamps become ISO strings; use `date($value)` or `datetime($value)`
in the query.

Results use Neo4j's plain JSON format. Large JSON integers remain
strings; temporal, spatial and binary values keep the server's string
representation. Scalar columns of one type become atomic vectors; mixed
or nested values remain lists. Empty or entirely null columns are
logical. Duplicate field names are preserved. Use `raw = TRUE` for
bookmarks, notifications and native graph values; discard saved results
and metadata when changing users.

## See also

[`vignette("neo4j", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/neo4j.md).

## Examples

``` r
if (FALSE) { # \dontrun{
graph <- oauth_db_neo4j_api(auth$connection,
  url = "https://graph.example.org:7473", database = "neo4j")
output$rows <- shiny::renderTable({
  graph$query("MATCH (p:Person) WHERE p.country = $country RETURN p.name AS name LIMIT 20",
    parameters = list(country = "NL"))
})
} # }
```
