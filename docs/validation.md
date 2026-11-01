# Validation record

## 1 November 2026

Checked on Windows 11 with R 4.5.1, shinyOAuth 0.7.0, fabricQueryR 1.0.1,
brickster 0.2.15, and RTrino 0.1.0. Dependencies were installed in an isolated library.

| Check | Result |
| --- | --- |
| Package test suite | 982 passing assertions; no skipped scenarios |
| `R CMD check --no-manual` | No errors, warnings, or notes |
| Four vignettes | Built and rebuilt during the package check |
| README apps | All eight construct; all ten outputs wait for sign-in |
| Playground apps | Client setup, queries, account replacement, and sign-out pass with mocked services |
| Documentation examples and local links | 43 R blocks parse; 70 local links resolve |
| BigQuery REST client | Polling, paging, typed results, bound parameters, 401 renewal, and grant isolation |
| Redshift adapter | Explicit ODBC token mode, verified TLS, argument protection, and connection lifecycle |
| Trino DBI client | Native RTrino requests, pagination, refresh, username changes, and callback retirement |

The tests cover connection reuse and cleanup, authorization changes,
permission checks, token refresh, API routing, and the example apps.
Cloud responses are mocked. No live cloud queries or browser sign-ins were
performed for this update.

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
