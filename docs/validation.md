# Validation record — 3 October 2026

This record covers the minimal native-accessor redesign. Query/result wrappers,
source descriptors, operation mappings and worker execution have been removed.

Tested on Windows 11 with R 4.5.1. Development shinyOAuth, fabricQueryR and the
brickster fork, plus missing native dependencies, were installed into an isolated
temporary library. Sibling repositories and normal user libraries were unchanged.

## Completed checks

- **Repository suite:** 416 passing assertions, no failures, warnings or skips.
- **R CMD build and R CMD check --no-manual:** zero errors, warnings or notes.
- **Native backend boundaries:** 70 assertions covering explicit token injection,
  native options, Fabric audience/endpoint policy, and Databricks providers.
  Fabric also accepts a native authorization without named token targets.
- **Native OAuth presets:** 46 assertions covering default configuration,
  custom providers/scopes/targets, native client settings, and standalone
  Snowflake provider composition. Explicit Databricks providers bypass discovery.
- **Multiple authorizations:** two simultaneous database accessors use separate
  native client registrations and scopes. Disconnecting one leaves the other
  usable and cannot substitute another retained grant.
- **Connection lifecycle:** lazy acquisition, per-session reuse, stable native
  connections through refresh, invalid-connection reopening, permission loss and
  restoration, grant replacement, logout and session cleanup. Retained providers
  reject a replacement grant, including one reusing the previous grant ID.
- **Ordinary Shiny behavior:** native accessors participate in standard reactive
  expressions; no package-owned result cache or query executor is involved.
- **Source examples:** 258 assertions across actual live-app definitions,
  the offline SQLite demo, and the retained-authorization manager example.
  These assertions are included in the repository total above. All 13 examples
  parse; the 11 basic live apps are 35–40 lines each.
- **Offline HTTP smoke:** HTTP 200 with simulated A/B controls.
- **PostgreSQL/Keycloak integration:** 85 real-browser assertions, no failures,
  warnings or skips, plus native libpq hook regression checks. Tests exercised
  genuine PKCE sign-in, A/B database roles and row policies, table grants,
  cross-role denial, connection reuse, refresh without reconnecting, logout and
  replacement, wrong audience, missing scopes and a broken held connection.
  The runner installed the accessor redesign into its isolated container
  library. Both test runs' project containers, volumes and networks were removed.
  This browser suite preceded the OAuth-preset follow-up; that follow-up was
  checked by the repository suite and package check above.
- **Live-harness offline smoke:** supplied A/B authorization fixtures with native
  SQLite exercised replacement, reuse and logout through the opt-in runner.
- **Documentation:** all R blocks parse and repository-local links resolve.

The installed-package check excludes the repository-only example scripts. The
repository suite above includes their tests. Optional backend checks can skip
when native dependencies are absent; the recorded run had them available.

## Reproduce

Install the documented development dependencies, then run from the repository root:

```sh
Rscript --vanilla tools/check-package.R
Rscript --vanilla tools/check-playground.R --test
Rscript --vanilla tools/check-docs.R
```

The package checker also accepts a dependency-library path as its first argument.
It installs the tested package into a separate temporary library, and uses a
portable locale for child R processes. The Windows HTTP smoke command is:

```powershell
rtk proxy powershell -NoProfile -File tools/check-playground-http.ps1
```

See the [local PostgreSQL fixture](../integration/postgres-keycloak/README.md)
for the Docker/browser command and the [live transport checks](../tests/integration/README.md)
for opt-in cloud scenarios.

## Scope of evidence

No live cloud tokens were supplied. Cloud-specific user mapping, grants, consent,
network configuration and established-session behavior remain deployment-specific
acceptance work. The local PostgreSQL fixture validates its disposable configured
deployment; its libpq hook is integration-only, not a production RPostgres API.

The offline demo uses synthetic grants. Production examples obtain authorizations
from public shinyOAuth modules. The bridge manages native connection and provider
lifetime; application-owned caches and background results retain ordinary Shiny
and native-client semantics.
