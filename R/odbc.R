# Shared ODBC connection-string validation, independent of any driver.
.odb_odbc_values <- function(values) {
  if (any(grepl("[;={}\"'[:cntrl:]]", names(values)))) {
    .odb_abort("ODBC option names cannot contain connection-string delimiters or control characters.")
  }
  for (value in values) {
    if (!is.character(value)) next
    if (anyNA(value) || any(grepl("[[:cntrl:]]", value)) ||
        any(grepl("[;{}]", value) & !.odb_odbc_quoted(value))) {
      .odb_abort(paste0("Quote ODBC values containing connection-string delimiters with ",
        "odbc::quote_value(); missing values and control characters are not allowed."))
    }
  }
  invisible(values)
}

# The forms emitted by odbc::quote_value(): one enclosing quote pair, with no
# matching quote inside. Checking the entire value prevents trailing keywords.
.odb_odbc_quoted <- function(value) grepl("^\"[^\"]*\"$|^'[^']*'$", value)
