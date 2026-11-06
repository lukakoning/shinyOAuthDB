# DuckDB documents this user agent for Posit's Linux binary repository.
# The dated snapshot keeps the R client aligned with the Python server.
options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(),
  paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])))
install.packages("duckdb",
  repos = "https://p3m.dev/cran/__linux__/manylinux_2_28/2026-06-20/")
stopifnot(packageVersion("duckdb") == "1.5.4")
con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbExecute(con, "INSTALL quack")
DBI::dbExecute(con, "INSTALL httpfs")
DBI::dbDisconnect(con, shutdown = TRUE)
