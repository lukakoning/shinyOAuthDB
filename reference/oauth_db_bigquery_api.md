# Query BigQuery as the signed-in user

Run BigQuery SQL and browse datasets using each visitor's Google
account. Queries run as jobs in your chosen Google Cloud project and
return data frames for the Shiny app. Users need permission to run jobs
in that project and read the data.

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

  Function providing the visitor's current sign-in authorization. Pass
  `auth$connection` from shinyOAuth without parentheses. To select a
  saved account, use a function calling `auth$connection(id)`.

- project:

  Google Cloud project in which to run and bill queries.

- dataset:

  Default dataset for unqualified table names, or `NULL`.

- location:

  Dataset location, such as `"EU"` or `"us-central1"`. `NULL` lets
  BigQuery choose it.

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

  Maximum seconds to submit, poll, and fetch an operation.

- page_size:

  Maximum number of rows requested per result page.

- session:

  The visitor's Shiny session. Usually inferred when you create the
  helper inside `server()`.

## Value

A client object with these methods:

- `$query(sql, parameters = NULL, parameter_types = NULL, maximum_bytes_billed = NULL, use_query_cache = TRUE, raw = FALSE)`
  runs GoogleSQL and returns a data frame.

- `$datasets()` lists dataset IDs in the project.

- `$tables(dataset)` lists table IDs. If omitted, `dataset` uses the
  client's default.

## Details

Create the client inside `server()` and call its methods from render or
reactive expressions. Use
[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md)
for Google sign-in. No BigQuery database driver is needed.

Set `project` to the Google Cloud project that runs and bills queries.
The data can be in another project the user can access. Set `location`
to match the datasets you query.

## Query parameters

Use named R values in `parameters`, such as `list(country = "NL")` for
SQL containing `@country`. Character, logical, integer, numeric, `Date`
and `POSIXct` values are supported; vectors become arrays.

Use a named character vector of `parameter_types` to choose the type or
type a `NULL` value. Use `"ARRAY<INT64>"` for a one-element integer
array.

## Query options

Set `maximum_bytes_billed` to limit the bytes a query may bill. Set
`use_query_cache = FALSE` to disable cached query results.

## Result types

INT64 and decimal columns stay as strings to preserve precision. Dates
become `Date`, timestamps become UTC `POSIXct`, and nested or repeated
fields use list columns. BYTES fields keep their API representation.

Use `raw = TRUE` for the combined API response, schema and job
reference. For statements that change data, inspect `numDmlAffectedRows`
in that result; the data frame can have no columns.

## Longer queries

Queries wait for completion and collect all result pages in R memory.
Polling is synchronous: other Shiny sessions in the same R process can
wait until the call returns. A timeout or sign-out stops fetching
results but doesn't cancel a submitted BigQuery job. Each request uses a
current token. HTTP 401 can trigger one refresh attempt; other errors
stop the operation without resubmitting SQL.

## See also

[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md).
[`vignette("bigquery", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.md)
has sign-in setup and a complete app.

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
