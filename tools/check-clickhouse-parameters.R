# Real-engine parameter checks, independent of the Cloud JWT configuration.
# Run from the checkout with Docker: Rscript tools/check-clickhouse-parameters.R
source("R/conditions.R")
source("R/options.R")
source("R/backend__clickhouse.R")
docker <- Sys.which("docker")
if (!nzchar(docker)) {
  stop("Docker is required for the ClickHouse parameter check.", call. = FALSE)
}
image <- Sys.getenv(
  "OAUTHDB_CLICKHOUSE_TEST_IMAGE",
  "clickhouse/clickhouse-server:26.1.2.11"
)
at <- as.POSIXct("2026-11-04 12:00:00", tz = "UTC")
amsterdam <- as.POSIXct("2026-11-04 13:00:00", tz = "Europe/Amsterdam")
values <- .odb_clickhouse_parameters(list(
  whole = at,
  fractional = at + 0.125,
  missing = NULL,
  amsterdam = amsterdam
))
sql <- paste(
  "SELECT toUnixTimestamp({whole:DateTime('UTC')}),",
  "toUnixTimestamp64Micro({whole:DateTime64(6, 'UTC')}),",
  "toUnixTimestamp64Micro({fractional:DateTime64(6, 'UTC')}),",
  "isNull({missing:Nullable(DateTime('UTC'))}),",
  "toUnixTimestamp({amsterdam:DateTime('UTC')})",
  "SETTINGS session_timezone = 'Pacific/Auckland' FORMAT TSV"
)
arguments <- c(
  "run",
  "--rm",
  "--network",
  "none",
  "--cpus",
  "1",
  "--memory",
  "512m",
  "--entrypoint",
  "clickhouse",
  image,
  "local",
  "--query",
  sql
)
for (name in names(values)) {
  arguments <- c(arguments, paste0("--", name), values[[name]])
}
result <- processx::run(docker, arguments, error_on_status = FALSE)
if (result$status != 0L) {
  stop(result$stderr, call. = FALSE)
}
expected <- paste(
  "1793793600",
  "1793793600000000",
  "1793793600125000",
  "1",
  "1793793600",
  sep = "\t"
)
stopifnot(identical(trimws(result$stdout), expected))
cat(
  "ClickHouse DateTime, DateTime64, nullable and timezone parameter checks passed.\n"
)
