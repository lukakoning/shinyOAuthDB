# Validation record

## 1 November 2026

Checked on Windows 11 with R 4.5.1, shinyOAuth 0.7.0, fabricQueryR 1.0.1,
brickster 0.2.15, and RTrino 0.1.0. Dependencies were installed in an isolated library.

| Check | Result |
| --- | --- |
| Package test suite | 1,029 passing assertions; no skipped scenarios |
| `R CMD check --no-manual` | No errors, warnings, or notes |
| Ten vignettes | Eight source guides, getting started, and sessions; built and rebuilt during the package check |
| Source guide apps | All eight construct with real OAuth clients and wait for sign-in |
| Rendered guides | All ten pages present; 20 local page links and anchors resolve |
| README apps | All eight construct; all ten outputs wait for sign-in |
| Playground apps | Client setup, queries, account replacement, and sign-out pass with mocked services |
| Documentation examples and local links | 46 R blocks parse; 89 local links resolve |
| BigQuery REST client | Bound parameters, result types, paging, refresh, and account separation |
| Redshift adapter | ODBC token and TLS options; connection reuse and cleanup |
| Trino DBI client | RTrino requests, paging, refresh, username changes, and sign-out |

Cloud responses are mocked. No live cloud queries or browser sign-ins ran
for this update. The tests cover connection cleanup, account and permission
changes, token refresh, and the example apps.

## Reproduce

Run from the repository root:

```sh
Rscript --vanilla tools/check-package.R path/to/check-library
Rscript --vanilla tools/check-docs.R
```

The extra library path is optional. The checker installs the package into a
temporary library and leaves the user's installed packages alone.

For real sign-in, platform permissions, and driver validation, use the
[integration checks](../tests/integration/README.md).
