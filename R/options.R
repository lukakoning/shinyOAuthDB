# Validate option names mechanically; the calling backend owns its policy.
.odb_options <- function(options, blocked) {
  key <- function(x) tolower(gsub("[^A-Za-z0-9]", "", x))
  nms <- names(options)
  .odb_named_args(options, "Native options in ...")
  if (anyDuplicated(key(nms))) {
    .odb_abort("Native options in ... must have unique names, ignoring case and punctuation.")
  }
  protected <- nms[key(nms) %in% key(blocked)]
  if (length(protected)) {
    .odb_abort(paste0(
      "Options ", paste0("`", protected, "`", collapse = ", "),
      " cannot be overridden through ... . The helper supplies authentication, connection identity and TLS settings."))
  }
  options
}

.odb_named_args <- function(args, label = "Native configuration") {
  nms <- names(args)
  if (length(args) && (is.null(nms) || anyNA(nms) || any(!nzchar(nms)) || anyDuplicated(nms))) {
    .odb_abort(paste0(label, " must have nonempty, unique names."))
  }
  invisible(args)
}
