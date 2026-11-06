.odb_cloud_spec_snowflake <- function() list(
  title = "Snowflake",
  purpose = "Query Snowflake with your own account and an allowed role. The first query reports your user and role, without needing a table.",
  account_url = "https://docs.snowflake.com/en/user-guide/admin-trial-account",
  setup_url = "https://docs.snowflake.com/en/user-guide/admin-account-identifier",
  registration_url = "https://docs.snowflake.com/en/user-guide/oauth-custom",
  registration = c(
    "Ask an account administrator or a role with CREATE INTEGRATION to create a Snowflake OAuth security integration: TYPE = OAUTH, OAUTH_CLIENT = CUSTOM, OAUTH_CLIENT_TYPE = 'CONFIDENTIAL', ENABLED = TRUE.",
    "Set OAUTH_REDIRECT_URI to the local callback below, OAUTH_ALLOW_NON_TLS_REDIRECT_URI = TRUE for this local HTTP demo, OAUTH_ENFORCE_PKCE = TRUE and OAUTH_ISSUE_REFRESH_TOKENS = TRUE. Use HTTPS callbacks when deploying.",
    "Copy OAUTH_CLIENT_ID and OAUTH_CLIENT_SECRET from SYSTEM$SHOW_OAUTH_CLIENT_SECRETS for that integration. Enter only the client ID here; use the masked prompt or OAUTHDB_SNOWFLAKE_CLIENT_SECRET for its secret.",
    "Choose an ordinary role granted to the user and allowed by the integration. Administrative roles are blocked by default. The role needs USAGE on the warehouse and, for table queries, database/schema USAGE and SELECT. The Snowflake vignette contains example registration SQL."
  ),
  cost = "Queries can resume the selected warehouse and consume credits. Stopping this app does not suspend the warehouse or change auto-suspend settings.",
  client_types = "confidential", packages = list(odbc = "1.4.2"),
  driver_url = "https://docs.snowflake.com/en/developer-guide/odbc/odbc",
  required = c("server", "role", "warehouse", "client_id"),
  fields = list(
    server = .odb_cloud_field("Find the Snowflake account server", "In Snowsight, open your account details and copy the account/connection URL hostname ending in snowflakecomputing.com. Do not paste the app.snowflake.com browser URL.", "hostname"),
    role = .odb_cloud_field("Choose your database role", "Copy an ordinary role you can use, such as REPORTING_READER. Use the exact spelling from Snowflake. This demo requests that role at sign-in and for the SQL connection.", "role"),
    warehouse = .odb_cloud_field("Choose a warehouse", "In Snowsight > Compute > Warehouses, copy a warehouse name your selected role can use. Ask for USAGE if needed; the demo doesn't create a warehouse.", "odbc"),
    database = .odb_cloud_field("Optional database", "Supply database when resuming if your later SQL needs a default database.", "odbc"),
    schema = .odb_cloud_field("Optional schema", "Supply schema when resuming if your later SQL needs a default schema.", "odbc"),
    driver = .odb_cloud_field("Snowflake ODBC driver", "Install the Snowflake ODBC driver on this computer. Supply driver if its registered name differs.", "odbc", "SnowflakeDSIIDriver")
  )
)
