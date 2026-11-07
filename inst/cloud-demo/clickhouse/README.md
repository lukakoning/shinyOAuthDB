# Your ClickHouse Cloud Shiny demo

Resume with `shinyOAuthDB::oauth_db_cloud_demo("clickhouse", path = ".")`.
This example uses Microsoft Entra as a custom JWT issuer. The Cloud service
must have the qualifying plan/version, trusted issuer/audience/JWKS and role
mapping configured. A standard console login or management API key does not
provide that setup. Resume with `jwt_ready = "yes"` once configured.

Edit `app.R` to change the SQL or connection code, or `demo-ui.R` for the UI.
Save and reload the browser. Click **Run example query** to send a request;
the first query needs no table. Stopping the local app does not stop the
Cloud service or change billing settings.

A confidential registration uses masked input or
`OAUTHDB_CLICKHOUSE_CLIENT_SECRET`. Keep secrets and tokens out of files.
See the [ClickHouse guide](https://lukakoning.github.io/shinyOAuthDB/articles/clickhouse.html)
for availability, JWT configuration and provider/role requirements.
