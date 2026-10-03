# shinyOAuthDB 0.0.0.9000

* Use unmodified upstream brickster with bearer strings; refresh DBI connections when their fixed token rotates.
* Own Databricks OAuth provider discovery in `oauth_db_databricks_provider()`.
* Supply ordinary Fabric token callbacks without fabricQueryR Shiny helpers, new provider hooks, or private credential metadata.
* Remove the old Shiny integration from the sibling fabricQueryR checkout; keep its native APIs and persistent sandbox tooling there.
* Replace the separate Fabric apps with one integrated app for the persistent Shiny sandbox, including SQL, DAX, KQL, OneLake, GraphQL, and discovery.

## Breaking redesign

* Backend helpers take a shinyOAuth authorization directly and return reactive native connection or token-provider accessors.
* Query through existing DBI, fabricQueryR, and brickster functions in ordinary Shiny code.
* Remove source descriptors, operation mappings, managed query results, and background task execution.
* Keep session-local connection reuse, credential adaptation, and cleanup on authorization/session changes.
* Reduce complete live examples to roughly 35–40 lines.
* Keep Microsoft, Databricks, and Snowflake OAuth client helpers as optional configuration conveniences.
* Allow explicit native providers, client scopes, and Microsoft token targets to replace preset defaults; pass remaining native client settings through unchanged.
* Add a provider-only Snowflake preset and document simultaneous accessors bound to separate authorizations and client registrations.
* Remove the previous development API without compatibility aliases.
