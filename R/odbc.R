# Shared ODBC connection-string validation, independent of any driver.
.odb_odbc_values <- function(values) {
  if (any(grepl("[;={}\"'[:cntrl:]]", names(values)))) {
    .odb_abort(
      "ODBC option names cannot contain connection-string delimiters or control characters."
    )
  }
  for (value in values) {
    if (is.null(value)) {
      next
    }
    if (
      !typeof(value) %in% c("character", "integer", "double", "logical") ||
        length(value) != 1L ||
        !is.null(dim(value)) ||
        anyNA(value) ||
        is.object(value) &&
          !(is.character(value) && identical(class(value), "AsIs"))
    ) {
      .odb_abort(
        "ODBC option values must be NULL or one non-missing character, numeric, or logical scalar; only quoted character values may have a class."
      )
    }
    # odbc pastes a list of values; named numeric scalars can also contribute
    # connection-string syntax through their names during that conversion.
    text <- paste(list(value))
    if (
      grepl("[[:cntrl:]]", text) ||
        grepl("[;{}]", text) && !.odb_odbc_quoted(text)
    ) {
      .odb_abort(paste0(
        "Quote ODBC values containing connection-string delimiters with ",
        "odbc::quote_value(); missing values and control characters are not allowed."
      ))
    }
  }
  invisible(values)
}

# The forms emitted by odbc::quote_value(): one enclosing quote pair, with no
# matching quote inside. Checking the entire value prevents trailing keywords.
.odb_odbc_quoted <- function(value) grepl("^\"[^\"]*\"$|^'[^']*'$", value)

# Keep credential values out of calls and evaluation frames retained by driver errors.
.odb_odbc_connect <- function(args) {
  on.exit(
    {
      args <- NULL
    },
    add = TRUE
  )
  values <- lapply(seq_along(args), function(i) {
    substitute(args[[index]], list(index = i))
  })
  names(values) <- names(args)
  tryCatch(
    eval(
      as.call(c(list(quote(DBI::dbConnect)), values)),
      envir = environment()
    ),
    error = function(error) {
      error$call <- rlang::zap_srcref(error$call)
      if (inherits(error$trace, "rlang_trace")) {
        error$trace$call <- lapply(error$trace$call, rlang::zap_srcref)
      }
      stop(error)
    }
  )
}
