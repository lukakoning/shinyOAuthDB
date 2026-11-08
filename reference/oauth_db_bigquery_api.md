# Query BigQuery as the signed-in user

Run GoogleSQL and browse datasets with the visitor's Google account.
Queries return data frames for use in your Shiny app.

## Usage

``` r
oauth_db_bigquery_api(
  authorization,
  project,
  dataset = NULL,
  location = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 300,
  page_size = 10000L,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- authorization:

  `auth$connection` from a shinyOAuth server module, without
  parentheses. To select a saved authorization, pass a function that
  calls `auth$connection(id)`.

- project:

  Google Cloud project in which to run and bill queries.

- dataset:

  Default dataset for unqualified table names, or `NULL`.

- location:

  Dataset location, such as `"EU"` or `"us-central1"`. `NULL` lets
  BigQuery choose it.

- target:

  Token target name in the shinyOAuth client. `NULL` uses its default
  token, including for clients without named targets.

- required_scopes:

  Additional permissions to check before use. Request consent and set
  the client's permission requirements in shinyOAuth.

- min_valid_for:

  Minimum remaining token lifetime, in seconds, when obtaining a token.
  Use `0` to accept any unexpired token.

- timeout:

  Maximum seconds to submit, poll, and fetch an operation.

- page_size:

  Maximum number of rows requested per result page.

- session:

  Shiny session. Inferred when the helper is created in `server()`.

## Value

An R6 client with these methods:

- `$query(sql, parameters = NULL, parameter_types = NULL, maximum_bytes_billed = NULL, use_query_cache = TRUE, raw = FALSE)`
  runs GoogleSQL and returns a data frame.

- `$datasets()` lists dataset IDs in the project.

- `$tables(dataset)` lists table IDs. If omitted, `dataset` uses the
  client's default.

## Details

Create the client inside `server()` and call its methods inside render
or reactive expressions. Use
[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md)
for Google sign-in. Users need permission to create query jobs in
`project` and read the data. The client uses BigQuery's REST API;
bigrquery and ODBC aren't required. Dataset discovery fails if BigQuery
reports unreachable locations, so a partial listing cannot appear as a
complete or empty collection.

## Query parameters

Supply named R values in `parameters`, such as `list(country = "NL")`
for SQL containing `@country`. Supported values include character,
logical, integer, numeric, `Date`, and `POSIXct`.

Vectors become ARRAY parameters. Use a named character vector of
`parameter_types` to override the scalar element type or type a `NULL`
value. Use `"ARRAY<INT64>"` for a one-element array.

## Query options

Set `maximum_bytes_billed` to limit the bytes a query may bill. Set
`use_query_cache = FALSE` to disable cached query results.

## Result types

INT64 and decimal columns remain strings to preserve precision. DATE
becomes `Date`, TIMESTAMP becomes UTC `POSIXct`, and nested or repeated
fields become list columns. BYTES fields keep their REST representation.

`raw = TRUE` returns an R list with the combined REST response, schema,
and job reference. DML may return a data frame with no columns; use the
raw result to inspect `numDmlAffectedRows`.

## Longer queries

Queries run synchronously and collect their results in R memory. A
timeout or sign-out stops fetching results but doesn't cancel a
submitted BigQuery job.

Each request obtains a current token for the authorization that started
the operation. A 401 response triggers one refresh attempt. Other errors
stop the operation without resubmitting SQL.

## See also

[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md).
[`vignette("bigquery", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.md)
has sign-in setup and a complete app.

Other platform API clients:
[`oauth_db_clickhouse_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_clickhouse_api.md),
[`oauth_db_cratedb_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cratedb_api.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md),
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md),
[`oauth_db_libsql_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_libsql_api.md),
[`oauth_db_opensearch_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_opensearch_api.md),
[`oauth_db_oracle_ords_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_oracle_ords_api.md),
[`oauth_db_postgrest_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_postgrest_api.md),
[`oauth_db_salesforce_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_api.md),
[`oauth_db_salesforce_data_cloud_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_salesforce_data_cloud_api.md),
[`oauth_db_supabase_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_supabase_api.md)

## Examples

``` r
if (FALSE) { # \dontrun{
bigquery <- oauth_db_bigquery_api(
  auth$connection, project = "billing-project", location = "EU"
)
output$rows <- shiny::renderTable({
  bigquery$query(
    "SELECT * FROM reporting.Orders WHERE country = @country LIMIT 20",
    parameters = list(country = "NL")
  )
})
} # }
```
