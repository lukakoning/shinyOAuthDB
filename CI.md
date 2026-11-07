# CI

- [R-CMD-check](https://lukakoning.github.io/shinyOAuthDB/workflows/R-CMD-check.yaml):
  standard usethis matrix on Linux, macOS and Windows, with coverage on
  Linux release.
- [pkgdown](https://lukakoning.github.io/shinyOAuthDB/workflows/pkgdown.yaml):
  standard usethis build and gh-pages deployment, using `_site` because
  `docs/` contains maintained guides.
- [Air and
  Jarl](https://lukakoning.github.io/shinyOAuthDB/workflows/quality.yaml):
  formatting and linting in one job.
- [Integration](https://lukakoning.github.io/shinyOAuthDB/workflows/integration.yaml):
  database, browser and demo tests run sequentially on one Ubuntu
  runner.

Compatibility campaigns, documentation-validation jobs, mutation testing
and credentialed cloud acceptance are outside CI. Their scripts remain
available for local use.
