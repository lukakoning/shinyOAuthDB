# Validate option names mechanically; the calling backend owns its policy.
.odb_options <- function(options, blocked) {
  key <- function(x) tolower(gsub("[^A-Za-z0-9]", "", x))
  nms <- names(options)
  if (length(options) && (is.null(nms) || any(!nzchar(nms)) || anyDuplicated(key(nms)))) {
    .odb_abort("Native options in ... must have unique names.")
  }
  if (any(key(nms) %in% key(blocked))) {
    .odb_abort("Authentication, connection identity and TLS settings cannot be overridden through ... .")
  }
  options
}
