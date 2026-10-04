# Shared ODBC connection-string validation, independent of any driver.
.odb_odbc_values <- function(values) {
  for (value in values) {
    if (is.character(value) && any(grepl("[;{}[:cntrl:]]", value))) {
      .odb_abort("ODBC values cannot contain connection-string delimiters or control characters.")
    }
  }
  invisible(values)
}
