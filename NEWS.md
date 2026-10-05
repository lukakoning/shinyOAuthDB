# shinyOAuthDB 0.0.0.9000

* Define the generic connector as connection-time token injection and document native-handle, logout, acquisition-lifetime, and asynchronous-refresh limits. Put the existing-shinyOAuth path next to the first app, including explicit default and custom target selection.
* Make `oauth_db_databricks()` always return a DBI connection accessor, accepting either native `warehouse_id` or `http_path`. Replace its former bearer-string mode with `oauth_db_token(auth$connection, scopes = "all-apis")`; Entra REST calls use their configured target and permissions explicitly.
* Preserve target and authorization-selection errors, and display missing permissions as a Shiny validation message. Logged-out access still waits quietly; failures retire cached connections without terminating the cleanup observer.
* Add small connection examples to backend help pages and a navigable package overview. Explain passing `auth$connection` without parentheses and reusing existing shinyOAuth clients with `target = NULL`.
* Make configuration errors identify protected option names, the public `scopes` argument, and the expected authorization input. Share named-argument validation across client, provider, and connector configuration.
* Introduce the simple-apps vignette gradually: purpose and one complete app first, familiar SQL examples next, then other Fabric APIs, advanced transports, custom OAuth configuration, and multiple authorizations.
* Isolate each backend's connections, OAuth presets, scope recipes, and native option policy in one `backend__*.R` file. Shared lifecycle and validation code contain no backend-specific branches.
* Keep Microsoft `.default` consent in client configuration instead of requiring it as a granted token permission. Generic accessors pass operation scopes unchanged to shinyOAuth.
* Simplify connection setup: remove SQL Server's `entra_enabled` flag, derive native Snowflake scopes from `role`, and allow `oauth_db_databricks(auth$connection)` for a bearer string without a redundant host.
* Resolve DBI connections before method dispatch in the simple-apps vignette, so outputs wait quietly for login and clear on logout. Token callbacks can still be passed inline to native functions.
* Add a simple-apps vignette with direct connection and query examples for every backend and Fabric interface.
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
