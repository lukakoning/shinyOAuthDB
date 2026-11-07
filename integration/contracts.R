integration_require_checks <- function(values, expected, label) {
  if (
    !is.list(values) ||
      !length(expected) ||
      anyDuplicated(names(values)) ||
      !setequal(names(values), expected) ||
      length(values) != length(expected)
  ) {
    stop(label, " must report exactly its required checks.", call. = FALSE)
  }
  if (!all(vapply(values, identical, logical(1), TRUE))) {
    stop(label, " has a failed or non-logical check.", call. = FALSE)
  }
  invisible(TRUE)
}

integration_check_names <- function(backend, kind) {
  checks <- list(
    postgrest = list(
      denied = c(
        "other_table_denied",
        "count_header",
        "paging",
        "row_filter",
        "bound_argument",
        "write_denied"
      ),
      data = c(
        "parameter",
        "null",
        "bigint",
        "timestamp",
        "empty",
        "successful_write_once",
        "failed_response_once",
        "dropped_response_once",
        "timeout_response_once"
      )
    ),
    trino = list(
      denied = c("other_table_denied", "impersonation_denied", "native_fetch"),
      data = c(
        "unicode",
        "null",
        "bigint",
        "timestamp",
        "empty",
        "dbplyr_filter",
        "dbplyr_empty"
      )
    ),
    starrocks = list(
      denied = c(
        "table_access",
        "impersonation_denied",
        "password_fallback_denied",
        "token_files_removed"
      ),
      data = c(
        "parameter",
        "null",
        "bigint",
        "timestamp",
        "empty",
        "revoked_grant",
        "restored_grant",
        "dbplyr_filter",
        "dbplyr_empty"
      )
    ),
    minilake = list(
      data = c(
        "quoted_value",
        "named_parameter_gap",
        "both_helpers",
        "null",
        "bigint_text",
        "timestamp",
        "empty",
        "pages",
        "dbplyr_filter",
        "dbplyr_empty"
      )
    )
  )
  if (!backend %in% names(checks)) {
    stop("Unknown integration backend.", call. = FALSE)
  }
  value <- if (identical(kind, "tls")) {
    c("untrusted_ca", "wrong_hostname")
  } else {
    checks[[backend]][[kind]]
  }
  if (is.null(value)) {
    stop("Unknown integration check group.", call. = FALSE)
  }
  value
}

integration_scenarios <- function(backend) {
  if (identical(backend, "postgres")) {
    return(c(
      "browser PKCE users receive their PostgreSQL grants and lifecycle",
      "the playground switches accounts, cancels refresh and stops cleanly",
      "browser-issued wrong audience is denied by PostgreSQL OAuth",
      "browser-issued missing scope never reaches PostgreSQL connect",
      "PostgreSQL independently rejects tampered, expired and TLS-invalid credentials",
      "PostgreSQL delegated connections support dbplyr and native typed parameters",
      "PostgreSQL reads renew natural expiry while retaining the SQL session",
      "a rejected PostgreSQL refresh closes local access and recovers with Bob"
    ))
  }
  if (identical(backend, "minilake")) {
    return(c(
      "both public Databricks helpers execute real local SQL and rotate copied credentials",
      "the bridge blocks missing Databricks operation scopes before SQL",
      "a real invalid_grant retires local access without replaying SQL",
      "normal reads renew naturally expired browser credentials"
    ))
  }
  if (!backend %in% c("postgrest", "trino", "starrocks")) {
    stop("Unknown integration backend.", call. = FALSE)
  }
  c(
    "real browser users receive only their server-enforced rows",
    "the real service rejects a valid token for another audience",
    "missing operation scope blocks fixture read attempts",
    "the service rejects an expired browser-issued token independently of local access",
    "a real invalid_grant retires local access without replaying SQL",
    "normal reads renew naturally expired browser credentials"
  )
}

integration_validate_results <- function(counts, expected) {
  fields <- c("test", "passed", "failed", "error", "warning", "skipped")
  if (
    !is.data.frame(counts) ||
      !all(fields %in% names(counts)) ||
      !nrow(counts) ||
      !length(expected) ||
      anyNA(counts[fields]) ||
      anyDuplicated(counts$test) ||
      !setequal(counts$test, expected) ||
      nrow(counts) != length(expected)
  ) {
    stop("Integration must execute exactly its named scenarios.", call. = FALSE)
  }
  if (
    any(
      counts$passed <= 0 |
        counts$failed > 0 |
        counts$error |
        counts$warning > 0 |
        counts$skipped
    )
  ) {
    stop(
      "Integration requires passing assertions in every scenario and zero failures, errors, warnings or skips.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}
