# Validation record

## 1 November 2026

Checked on Windows 11 with R 4.5.1, shinyOAuth 0.7.0, fabricQueryR 1.0.1,
and brickster 0.2.15. Dependencies were installed in an isolated library.

| Check | Result |
| --- | --- |
| Package test suite | 721 passing assertions; no skipped scenarios |
| `R CMD check --no-manual` | No errors, warnings, or notes |
| Four vignettes | Built and rebuilt during the package check |
| Five README apps | OAuth clients and apps construct; all seven outputs wait for sign-in |
| Documentation examples and local links | Parse and resolve |
| Executable R code | Unchanged by the documentation rewrite |

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
