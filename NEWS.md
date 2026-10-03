# shinyOAuthDB 0.0.0.9000

- Base database sessions on pinned authorization connection objects. Modern
  shinyOAuth single-module and multiple-connection references work directly.
- Accept direct objects, reactive inputs and no-argument connection accessors;
  provide `oauth_db_authorization()` for other provider interfaces without a
  required class or a separate login/refresh implementation.
- Keep app login and explicitly selected database grants independent. Report
  ambiguous manager selection and invalidate replaced references, even when
  their IDs were reused.
- Add multiple-connection playground and custom-authorization lifecycle tests.
- Add an opt-in Docker Compose PostgreSQL 18/Keycloak fixture with real browser
  OAuth, database-enforced grants/RLS, native RPostgres token handoff and lifecycle
  integration tests.
