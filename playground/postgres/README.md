# PostgreSQL and Keycloak demo

Install shinyOAuthDB and start Docker with Linux containers, then run:

```r
shinyOAuthDB::oauth_db_demo("postgres")
```

The installed package includes the app, Docker configuration and demo
accounts. Open `http://localhost:18100` when ready. Sign in with `alice` /
`alice` or `bob` / `bob` (username / password); each sees their own rows.
Your browser may ask you to accept Keycloak's local test
certificate.

Click **Stop demo** or interrupt R to remove containers and data. After a
forced exit, use `oauth_db_demo("postgres", action = "stop")`.

See [Local Docker demos](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.html)
for editing the packaged app, alternate databases and build requirements.
The [PostgreSQL guide](https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html)
explains how to configure your own server.

The separate [integration fixture](../../integration/postgres-keycloak/README.md)
is for contributors running native and browser regression tests.
