# Query Azure Cosmos DB for NoSQL as the signed-in user

Read documents with each visitor's Microsoft Entra access token and
Cosmos DB data-plane permissions. Queries use the NoSQL HTTPS API; no
database driver or Azure SDK is needed.

## Usage

``` r
oauth_db_cosmos_api(
  authorization,
  url,
  database,
  container,
  target = "cosmos",
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 300,
  page_size = 1000L,
  api_version = "2020-07-15",
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

  Cosmos DB account HTTPS origin, such as
  `"https://example.documents.azure.com"`.

- database:

  Database ID.

- container:

  Container ID.

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

  Total seconds allowed for an operation and all its pages.

- page_size:

  Maximum items requested per page, or `-1` for the service default. A
  page can contain fewer items, including none.

- api_version:

  Cosmos DB REST service version.

- ca_bundle:

  Optional trusted CA certificate bundle path.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A session-bound client with these methods:

- `$query(sql, parameters = list(), partition_key = NULL, raw = FALSE)`
  collects all pages and returns a data frame.

- `$query_page(sql, parameters = list(), partition_key = NULL, continuation = NULL, session_token = NULL)`
  returns one page as a list with `documents`, `continuation`,
  `request_charge` and `session_token`.

- `$read(id, partition_key)` reads one document as a named list.

## Details

Use
[`oauth_db_cosmos_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cosmos_client.md)
for sign-in. Users need Cosmos DB data-plane roles, such as Cosmos DB
Built-in Data Reader, scoped to the database or container. Azure
subscription roles alone don't grant data access. Other Cosmos DB APIs
and account administration aren't supported.

Create the client inside `server()`. Each operation stays bound to the
authorization that started it and gets a current token for every page.
Results arriving after account replacement or sign-out are discarded.
Read requests may refresh and retry once after HTTP 401. Throttling and
other errors stop the operation; no account key or host credentials are
used.

## Queries and partitions

Use named parameters without `@`, such as `list(country = "NL")` for SQL
containing `@country`. Values can be JSON scalars, arrays or objects;
`NULL` becomes JSON null. Dates and timestamps use ISO strings.

With `partition_key = NULL`, queries enable cross-partition execution.
Supply a scalar key to select one partition, or an unnamed list of up to
three components for a hierarchical key. `list(NULL)` selects a null
key. This selects data; it doesn't restrict the visitor's database
permissions. Some cross-partition query plans need the vendor SDK's
result merging; this client sends the query to the REST gateway without
rewriting it.

## Results and pagination

Object projections become columns. Missing and null fields become `NA`
in scalar columns; nested or mixed values stay in list columns. Scalar
or mixed `SELECT VALUE` results use a `value` list column. Large JSON
integers stay as strings. Empty results have no field schema.

`raw = TRUE` returns the collected native `documents`, total
`request_charge` and last `session_token`, with `continuation = NULL`. A
missing request-charge header produces `NA_real_`. `$query_page()`
preserves nested documents and nulls. Reuse its continuation and session
token only with the same query, parameters, partition and account.

Queries are synchronous and collect results in memory. Use
`$query_page()` for larger results. Session tokens are carried between
pages of one operation, never cached across accounts or independent
operations.

## See also

[`oauth_db_cosmos_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cosmos_client.md).
[`vignette("cosmos", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/cosmos.md)
has registration and role setup.

## Examples

``` r
if (FALSE) { # \dontrun{
cosmos <- oauth_db_cosmos_api(
  auth$connection, url = "https://example.documents.azure.com",
  database = "reporting", container = "orders"
)
output$rows <- shiny::renderTable({
  cosmos$query(
    "SELECT c.id, c.total FROM c WHERE c.country = @country",
    parameters = list(country = "NL"), partition_key = "NL"
  )
})
} # }
```
