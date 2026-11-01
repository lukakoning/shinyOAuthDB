# Read-only repository documentation check: Rscript tools/check-docs.R
paths <- c(
  "README.md",
  "NEWS.md",
  list.files("vignettes", "\\.Rmd$", full.names = TRUE),
  list.files("docs", "\\.md$", full.names = TRUE),
  list.files("playground", "\\.md$", full.names = TRUE, recursive = TRUE),
  "tests/integration/README.md",
  "integration/postgres-keycloak/README.md",
  "integration/postgres-keycloak/native/README.md"
)
failures <- character()
blocks <- 0L
links <- 0L

for (path in paths) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  inside <- FALSE
  code <- character()

  for (line in lines) {
    if (!inside && grepl("^```[[:space:]]*\\{?r([ ,}]|$)", line)) {
      inside <- TRUE
      code <- character()
    } else if (inside && grepl("^```[[:space:]]*$", line)) {
      blocks <- blocks + 1L

      error <- tryCatch(
        {
          parse(text = code)

          NULL
        },

        error = function(e) conditionMessage(e)
      )

      if (!is.null(error)) {
        failures <- c(failures, paste(path, "R block", blocks, error))
      }

      inside <- FALSE
    } else if (inside) {
      code <- c(code, line)
    }
  }

  if (inside) {
    failures <- c(failures, paste(path, "has an unclosed R fence"))
  }

  matches <- regmatches(
    lines,
    gregexpr("\\[[^]]*\\]\\([^)]+\\)", lines, perl = TRUE)
  )
  for (match in unlist(matches, use.names = FALSE)) {
    target <- sub("^.*\\]\\((.*)\\)$", "\\1", match)
    target <- sub("^<|>$", "", target)
    if (grepl("^(https?://|mailto:|#)", target)) {
      next
    }

    target <- utils::URLdecode(sub("#.*$", "", target))
    absolute <- grepl("^[A-Za-z]:[/\\\\]|^/", target)
    resolved <- if (absolute) target else file.path(dirname(path), target)
    # Vignette links use the installed HTML name; check its source in a checkout.
    if (!file.exists(resolved) && grepl("\\.html$", resolved) &&
        identical(dirname(path), "vignettes")) {
      resolved <- sub("\\.html$", ".Rmd", resolved)
    }
    links <- links + 1L
    if (!file.exists(resolved)) {
      failures <- c(failures, paste(path, "missing local target:", target))
    }
  }
}

if (length(failures)) {
  stop(paste(failures, collapse = "\n"), call. = FALSE)
}

cat(blocks, "R documentation blocks parsed;", links, "local links exist.\n")
