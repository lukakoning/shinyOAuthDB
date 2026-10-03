# shinyOAuthDB 0.0.0.9000

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
