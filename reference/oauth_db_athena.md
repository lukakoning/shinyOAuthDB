# Query Amazon Athena as the signed-in user

Read Athena data with each visitor's access token and permissions
through AWS IAM Identity Center trusted identity propagation. The helper
opens a DBI connection through the Amazon Athena ODBC 2.x driver.

## Usage

``` r
oauth_db_athena(
  authorization,
  workgroup_arn,
  application_role_arn,
  s3_output_location,
  ...,
  schema = "default",
  catalog = "AwsDataCatalog",
  access_role_arn = NULL,
  customer_idc_application_arn = NULL,
  driver = "Amazon Athena ODBC Driver",
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

- workgroup_arn:

  Athena workgroup ARN. Its region and workgroup name supply the
  driver's `AwsRegion` and `Workgroup` settings.

- application_role_arn:

  IAM role ARN trusted for the external provider's
  `AssumeRoleWithWebIdentity` requests in your Identity Center
  integration.

- s3_output_location:

  S3 URI for query results, such as `"s3://query-results/reporting/"`.
  Workgroup settings may override it.

- ...:

  Named result and timeout options for odbc or the Athena driver. See
  the source guide for accepted options. Authentication, endpoints,
  caching and TLS settings cannot be overridden.

- schema:

  Default Athena database name, default `"default"`.

- catalog:

  Athena data catalog, default `"AwsDataCatalog"`.

- access_role_arn:

  Optional IAM access role ARN. When omitted, the driver discovers it
  through the integration's application tags.

- customer_idc_application_arn:

  Optional IAM Identity Center customer managed application ARN. When
  omitted, the driver uses workgroup tags.

- driver:

  Installed Amazon Athena ODBC driver name.

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

A reactive function, usually named `con`. Call `connection <- con()`
inside a render or reactive expression, then pass the connection to DBI.
Before sign-in, the function waits quietly.

## Details

Install odbc and Amazon Athena ODBC 2.5.0.0 or later. Configure IAM
Identity Center's trusted token issuer, IAM roles and workgroup
association first. The sign-in provider must issue JWT access tokens
accepted by that setup. There is no universal Athena OAuth registration
or scope preset.

The helper uses `AuthenticationType = "JWT_TIP"` with an explicit
visitor token. It disables the driver's file credential cache,
connection-check cache, result reuse and logging, and requires TLS
certificate verification. Each native connection gets a random role
session name. It doesn't supply AWS keys, select an AWS profile or start
the driver's browser login.

Create the helper inside `server()` and call `con()` before each query.
Token replacement closes the old connection on the next access. Account
changes, permission loss, sign-out and session end also close it.
Consume and clear outstanding DBI results before another operation.

A failed query isn't replayed by this helper. Closing an ODBC connection
doesn't guarantee cancellation of an already submitted Athena query.

## See also

[`oauth_db_connect()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_connect.md).
[`vignette("athena", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/athena.md)
has sign-in setup and a complete app.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- oauth_db_athena(
  auth$connection,
  workgroup_arn = "arn:aws:athena:eu-west-1:123456789012:workgroup/reporting",
  application_role_arn = "arn:aws:iam::123456789012:role/AthenaApplication",
  s3_output_location = "s3://query-results/reporting/"
)
output$rows <- shiny::renderTable({
  connection <- con()
  DBI::dbGetQuery(connection, "SELECT * FROM sales LIMIT 20")
})
} # }
```
