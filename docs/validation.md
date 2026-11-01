# Validation record

## 1 November 2026: released clients and native API interface

Validated on Windows 11 with R 4.5.1 in an isolated library using CRAN
shinyOAuth 0.7.0, fabricQueryR 1.0.1, and brickster 0.2.15. The user's normal R
library was not updated. These checks use released dependencies, not sibling
development checkouts or modified database packages.

- Repository suite: **723 passing assertions**, no failures or skipped scenarios.
- `R CMD build` and `R CMD check --no-manual`: **zero errors, warnings, or notes**.
  The vignette builds and its outputs rebuild successfully during the check.
- Documentation checker: **59 R blocks parse and 59 local links resolve**.
- `git diff --check`: clean.

The added integration tests exercise native fabricQueryR workspace and
Lakehouse R6 objects through real discovery functions, with HTTP responses
mocked. A discovered Lakehouse then opens a SQL connection through its retained
callback, using a different target's credential; only DBI's transport is mocked.
Native brickster warehouse discovery is also exercised with mocked HTTP and
compared with its direct native call's result.

Other new checks cover lazy acquisition, custom and untargeted configurations,
scope requirements, forced refresh, ordinary token rotation without query
reruns, permission loss, grant replacement, cross-session use, session closure,
credential overrides including positional arguments, and rejection of mixed or
undeclared audiences. Existing SQL, Snowflake, multiple-authorization, and
playground checks continue to pass. The integrated Fabric app now uses one
multi-resource API client; the Databricks app uses its native `$call()` path.

No live cloud queries or browser sign-ins were performed in this run. Remote
user mapping, deployment grants, native driver installation, and live refresh
still require deployment-specific validation. Snowflake remains DBI + odbc;
skiLift and skiPatrol are deferred as recorded in `snowflake-backends.md`.

Reproduce with the released dependencies installed in a check library:

```sh
Rscript --vanilla tools/check-package.R path/to/check-library
Rscript --vanilla tools/check-docs.R
```

## Earlier validation: 4 October 2026

The record below concerns the earlier development snapshots and is retained
for reference.

This follow-up removes dependencies on fork-only brickster APIs and Fabric's
Shiny integration. Tested on Windows 11 with R 4.5.1 using isolated libraries:

- **brickster 0.2.14:** unchanged upstream `databrickslabs/brickster` commit
  `8a56667f15494d7e01d880d0815e9b213ffce1b8`.
- **fabricQueryR 1.0.1:** unchanged commit
  `c6523dec95a4520e2acdc88e574465e8bf8b33b4`, before its Shiny integration.
- **fabricQueryR 1.0.1.9000:** sibling checkout after removing its Shiny
  helpers, provider metadata, duplicate apps, and eight optional dependencies.
- **shinyOAuth 0.6.1.9000:** the target-enabled development dependency.

The database packages expose their ordinary bearer/callback arguments; no
fork-only provider classes, private credential metadata, or Shiny extensions
are used by the bridge.

## Completed local checks

- **Repository suite:** 406 passing assertions, no failures, warnings or skips.
- **R CMD build and R CMD check --no-manual:** zero errors, warnings or notes.
- **Native backends:** 98 assertions, including real upstream brickster DBI
  construction with only its network query mocked. Credentials remain strings;
  repeated access reuses the object, refresh replaces it, and logout blocks the
  accessor. Fabric callbacks enforce audience routing and propagate refresh.
  Snowflake's default role scope and explicit External OAuth overrides are
  checked against real shinyOAuth grants, including permission denial and logout.
- **OAuth presets:** 54 assertions covering native customization and Databricks
  discovery through shinyOAuth, independent of brickster.
- **Lifecycle and configuration:** 45 assertions covering ownership, grant replacement, permission
  loss/restoration, invalid connections, and persistent SQL reuse across refresh.
  Configuration errors point to the public authorization/scopes arguments and
  identify protected option names without including credential values.
- **Backend isolation:** source audit of six backend files and seven shared
  files found no shared-to-backend calls or vendor settings in shared code.
  Seventeen scope regressions check that Microsoft consent markers stay out of
  permission checks, a real shinyOAuth PostgreSQL grant works with `.default`
  consent, and generic accessors preserve another provider's literal scopes.
- **Examples:** 183 assertions across standalone apps, the integrated Fabric app,
  the offline demo, and multiple simultaneous client registrations. These are
  included in the total above. All nine playground R files parse.
- **Fabric app:** all ten source choices route to their native functions with
  the proper credential; errors remain source-local; A/B replacement and logout
  clear dependent results. Shared and delegated settings remain separate.
- **Documentation:** R blocks parse and repository-local links resolve.
- **Simple apps vignette:** the complete UI, client definitions, and all 21
  connection/query variants executed in a one-off local smoke check with native
  transports mocked while preserving real DBI S4 dispatch. All query variants
  also cleared their output on logout. Nine regression assertions exercise the
  DBI snippets before sign-in without mocking DBI's generic function, verifying
  that they preserve Shiny's silent wait rather than a method-dispatch error.
  R CMD build created the HTML vignette, and R CMD check rebuilt it successfully
  with zero errors, warnings, or notes. The documentation checker now includes
  vignettes: 47 R blocks parse and 49 local links resolve. After reorganizing
  the vignette from introductory material to advanced topics, its HTML rendered
  successfully and the UI, all client definitions (including the new custom
  Snowflake client), and the same 21 query variants passed the smoke check again.

The 406-assertion bridge suite and clean R CMD check also passed against the
cleaned fabricQueryR checkout, with unmodified upstream brickster. The cleaned
fabricQueryR passed 7,638 offline assertions without failures, warnings, or
skips, and installed into an isolated library. Live Fabric and opt-in Python
Delta-oracle scenarios were excluded from that offline run. Its sandbox's
provisioning and launch-summary tests passed all 18 cases. Searches of its
package code, namespace, and dependencies found no remaining Shiny coupling.
Its separate R CMD check also reported zero errors, warnings, or notes with
`--no-tests --no-manual --ignore-vignettes`; tests and vignette code had already
passed in the offline suite. That build used a temporary copy of distributable
package inputs to avoid traversing the checkout's large ignored build libraries.

## Persistent Fabric sandbox

The app discovers `fabricqueryr-shiny-dhrkoning` using the existing sandbox
credentials. A real Chrome smoke test passed: explicit shared-identity banner,
ten sources, live workspace discovery, and rendered item rows.

The first guarded start failed on a GitHub API timeout before resume. The retry
resumed F2, but fixture preparation failed with `InvalidDefinitionFormat` while
creating the mirrored database. Its cleanup successfully paused capacity.

A narrow fix in the sibling fabricQueryR sandbox script omits the invalid
`definition.format = "Default"` field, matching the
[documented mirrored-database request](https://learn.microsoft.com/en-us/rest/api/fabric/mirroreddatabase/items/create-mirrored-database).
Its eight Python tests pass. The fix affects sandbox provisioning only; it adds
no dependency or integration API to fabricQueryR.

The corrected local provisioning run uses the existing independent shutdown
protocol and an armed one-hour
[GitHub shutdown job](https://github.com/KennispuntTwente/fabricQueryR/actions/runs/37157326198).
All ten live sources passed against the prepared sandbox:

| Source | Observed rows |
|---|---:|
| Warehouse SQL (ODBC) | 3 |
| Lakehouse SQL (ODBC) | 3 |
| DAX JSON | 2 |
| DAX Arrow | 2 |
| KQL | 3 |
| OneLake CSV | 3 |
| OneLake Delta | 3 |
| Mirrored Delta | 3 |
| Paginated GraphQL | 3 |
| Workspace discovery | 11 items |

The actual app also passed its Chrome check after provisioning. Query summaries
are in `tests/integration/results/fabric-sandbox.csv`; the browser screenshot is
in the same ignored results directory. SQL's optional ADBC selection was not
included in these live reads. Cleanup confirmed **F2 paused**, retaining the
prepared workspace and data.

## Reproduce

```sh
Rscript --vanilla tools/check-package.R
Rscript --vanilla tools/check-playground.R --test
Rscript --vanilla tools/check-docs.R
```

The package checker accepts dependency-library paths as positional arguments,
in priority order. It installs the tested package into a separate temporary
library and uses a portable locale for child R processes.

After the existing sandbox's guarded start succeeds, use the configured shared
sandbox credentials for the read-only checks:

```sh
Rscript tools/check-fabric-sandbox.R
Rscript tools/check-fabric-browser.R
```

Both runners also accept dependency-library paths. See the
[integrated app instructions](../playground/fabric/README.md) for setup.

## Scope of evidence

Live Fabric checks use the shared sandbox application. No delegated Shiny Web
registration or live Databricks account was configured for this run. Visitor
sign-in, cloud-specific user mapping and permissions still require deployment
acceptance. Local tests use actual shinyOAuth connections with fixture tokens.

The previous accessor redesign passed 85 real-browser PostgreSQL/Keycloak
assertions, including genuine PKCE, A/B row policies, refresh and logout. That
Docker suite was not rerun for this backend follow-up. Its native libpq helper
is integration-only, not a production RPostgres API.

Native objects and bearer strings already returned to application code retain
their native lifetime. In particular, upstream brickster's disconnect does not
revoke a bearer; call the session accessor for each operation. App-owned caches
and background results keep ordinary Shiny and database-client semantics.
