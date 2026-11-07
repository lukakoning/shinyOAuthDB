mutation_check_baseline <- function(details, baseline, profile) {
  fields <- c("file", "source_sha256", "mutant_sha256", "status")
  if (
    !is.data.frame(details) ||
      !nrow(details) ||
      !all(fields %in% names(details)) ||
      anyNA(details[fields]) ||
      !all(details$status %in% c("KILLED", "SURVIVED", "HANG"))
  ) {
    stop("Mutation results must be complete and conclusive.", call. = FALSE)
  }
  required <- c("profile", fields, "reason")
  if (
    !is.data.frame(baseline) ||
      !all(required %in% names(baseline)) ||
      anyNA(baseline[required]) ||
      any(baseline$status != "SURVIVED") ||
      !all(nzchar(trimws(baseline$reason)))
  ) {
    stop(
      "A reviewed baseline permits only explained surviving mutants.",
      call. = FALSE
    )
  }
  key <- function(x) paste(x$file, x$source_sha256, x$mutant_sha256, sep = ":")
  allowed <- baseline[baseline$profile == profile, , drop = FALSE]
  if (anyDuplicated(key(allowed))) {
    stop("Mutation baseline contains duplicate fingerprints.", call. = FALSE)
  }
  unresolved <- details$status == "HANG" |
    details$status == "SURVIVED" & !key(details) %in% key(allowed)
  if (any(unresolved)) {
    stop(
      "New surviving or inconclusive mutations require a regression or an explained baseline review: ",
      paste(details$file[unresolved], collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}
