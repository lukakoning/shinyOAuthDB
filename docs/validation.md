# Validation record — 3 October 2026

Tested on Windows 11, R 4.5.1, using the local development shinyOAuth checkout and current sibling fabricQueryR/brickster checkouts. Updated client packages and missing dependencies were installed into an isolated temporary library; normal user libraries were preserved.

## Completed checks

- **R CMD build and R CMD check --no-manual:** zero errors, warnings or notes.
- **Repository test suite:** 523 passing assertions, zero test failures, errors, warnings or skips.
- **fabricQueryR public provider hook:** 85 passing focused assertions.
- **Real worker execution:** native SQLite queries through mirai daemons and future multisession, including a real bridge handle, shinyOAuth secondary-token acquisition and a custom-provider fixture. Worker payloads contain no live authentication object, refresh credential, client secret or token SDK attributes.
- **Shiny lifecycle:** native connection reuse and rotation, logout and replacement cleanup, permission-loss generations, ownership, A/B isolation, clearing cached values/errors, protected arguments, serial/latest/ignore queues, cancellation and stale outcomes.
- **Authorization object contract:** direct, reactive and accessor inputs, class-independent list/environment objects, explicit named-target routing, malformed permission evidence, same-ID reference replacement and stale asynchronous acquisition.
- **Multiple connections:** 62 passing assertions using shinyOAuth's actual manager with separate login/database profiles, explicit selections, wrong-profile/foreign-ID rejection, retained grants in a new session, logout and same-grant refresh preserving selected database credentials and cached results. Alongside 62 existing playground assertions, 25 app/integration scripts parse successfully.
- **Adapter boundaries:** explicit native credential injection, exact public operation bindings, Fabric/Databricks provider forwarding, ODBC delimiters, custom configuration secret rejection and worker credential expiry.
- **Offline playground HTTP:** status 200 and expected simulated-user/native-call controls; isolated server and logs cleaned up.
- **Local PostgreSQL/Keycloak integration:** 89 passing real-browser assertions, zero failures, errors, warnings or skips. Docker Desktop Linux containers ran PostgreSQL/libpq 18.3, Keycloak 26.6.1, R 4.5.0, RPostgres 1.4.10 and Shiny 1.14.0. The current sibling shinyOAuth and bridge sources were installed inside an isolated container library. Alice/Bob sessions demonstrated native OAuth, database roles, table grants/RLS, cross-role denial, reuse, real refresh, logout/replacement, wrong audience, missing scope at both bridge/server boundaries, and failed recovery of a terminated native connection. Native hook restoration/isolation regressions passed separately.
- **Interactive PostgreSQL playground:** `--playground` serves the real Shiny fixture with HTTP 200 and its granted-data controls. The standalone Compose fixture and cleanup use only their own project containers and volumes.
- **Documentation:** 21 R code blocks parsed and 36 checked repository-local links resolved.

The installed-package check skips repository-only playground smoke tests because those scripts are excluded from the source package. The repository suite above includes them. Optional client/worker tests can skip when their packages are absent; the recorded run had the required packages installed.

## Reproduce locally

Install the development authentication/client dependencies first, then run from the repository root:

```sh
Rscript --vanilla tools/check-package.R
Rscript --vanilla tools/check-playground.R --test
Rscript --vanilla tools/check-docs.R
```

The package checker installs the current bridge into a temporary validation library so background workers resolve the tested revision. It retains the existing dependency library paths and performs the ordinary package checks. Windows HTTP smoke:

```powershell
rtk proxy powershell -NoProfile -File tools/check-playground-http.ps1
```

## Not yet exercised

No live cloud tokens or existing database deployments were supplied. Cloud browser login, consent/refresh, individual/group principal mapping, RLS/grants, native pooling/reconnect behavior and service-specific denial timing remain unverified for those deployments. The local PostgreSQL fixture proves its configured user/role/grant path; it does not validate an existing server's settings. All cloud adapters stay experimental until the [integration scenarios](../tests/integration/README.md) pass against the chosen deployment. The [native PostgreSQL fixture](../integration/postgres-keycloak/README.md) uses an integration-only Linux helper. Production support still needs a supported RPostgres token-hook API.

Offline authorization constructors are deterministic fixtures, including a test-only internal shinyOAuth reference constructor. Production code obtains references from public shinyOAuth module factories. The fixed-token live runner checks transport with operator-supplied delegated A/B credentials; the separate browser checklist covers actual OAuth and refresh.
