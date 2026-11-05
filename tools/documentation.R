documentation_paths <- function() {
  unique(c("README.md", "NEWS.md", "tools/README.md",
    list.files("vignettes", "\\.Rmd$", full.names = TRUE),
    unlist(lapply(c("docs", "playground", "integration", "tests/integration"),
      list.files, pattern = "\\.md$", full.names = TRUE, recursive = TRUE), use.names = FALSE)))
}

documentation_attributes <- function(html, attribute) {
  tag <- if (attribute == "href") "a\\b" else "[A-Za-z][A-Za-z0-9]*\\b"
  pattern <- paste0("<", tag, "[^>]*[[:space:]]", attribute, "[[:space:]]*=[[:space:]]*([\"'])(.*?)\\1")
  matches <- unlist(regmatches(html, gregexpr(pattern, html, perl = TRUE)), use.names = FALSE)
  values <- sub(paste0("^.*[[:space:]]", attribute, "[[:space:]]*=[[:space:]]*([\"'])(.*?)\\1$"),
    "\\2", matches, perl = TRUE)
  positions <- gregexpr("&#([xX][0-9a-fA-F]+|[0-9]+);", values, perl = TRUE)
  regmatches(values, positions) <- lapply(regmatches(values, positions), function(references) {
    vapply(references, function(reference) {
      number <- substring(reference, 3L, nchar(reference) - 1L)
      hex <- startsWith(tolower(number), "x")
      value <- strtoi(if (hex) substring(number, 2L) else number, if (hex) 16L else 10L)
      if (!is.na(value) && value > 0L && value <= 1114111L &&
          !(value >= 55296L && value <= 57343L)) intToUtf8(value) else reference
    }, "")
  })
  for (entity in list(c("&quot;", "\""), c("&apos;", "'"), c("&lt;", "<"),
    c("&gt;", ">"), c("&amp;", "&"))) values <- gsub(entity[[1L]], entity[[2L]], values, fixed = TRUE)
  values
}

documentation_check <- function(paths) {
  if (!requireNamespace("rmarkdown", quietly = TRUE) || !rmarkdown::pandoc_available()) {
    stop("Install rmarkdown and Pandoc to check rendered documentation links.", call. = FALSE)
  }
  documents <- new.env(parent = emptyenv())
  render <- function(path) {
    key <- normalizePath(path, winslash = "/", mustWork = TRUE)
    if (!is.null(documents[[key]])) return(documents[[key]])
    if (tolower(tools::file_ext(path)) == "html") {
      html <- readLines(path, warn = FALSE, encoding = "UTF-8")
    } else {
      output <- tempfile(fileext = ".html")
      on.exit(unlink(output), add = TRUE)
      # Pandoc reads Markdown directly; R chunks are never evaluated.
      vignette <- grepl("\\.Rmd$", path)
      input <- key
      if (vignette) {
        input <- tempfile(fileext = ".md")
        on.exit(unlink(input), add = TRUE)
        source <- readLines(key, warn = FALSE, encoding = "UTF-8")
        writeLines(sub("^(```+)\\{r.*\\}[[:space:]]*$", "\\1r", source), input, useBytes = TRUE)
      }
      rmarkdown::pandoc_convert(input, from = if (vignette) "markdown" else "gfm",
        to = "html", output = output, options = c("--wrap=none", "--no-highlight"), verbose = FALSE)
      html <- readLines(output, warn = FALSE, encoding = "UTF-8")
    }
    documents[[key]] <- html
    html
  }
  failures <- character()
  blocks <- links <- anchors <- 0L
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
        error <- tryCatch({ parse(text = code); NULL }, error = conditionMessage)
        if (!is.null(error)) failures <- c(failures, paste(path, "R block", blocks, error))
        inside <- FALSE
      } else if (inside) code <- c(code, line)
    }
    if (inside) failures <- c(failures, paste(path, "has an unclosed R fence"))
    for (target in documentation_attributes(render(path), "href")) {
      if (grepl("^(https?://|mailto:)", target)) next
      fragment <- if (grepl("#", target, fixed = TRUE)) utils::URLdecode(sub("^[^#]*#", "", target)) else ""
      file <- utils::URLdecode(sub("#.*$", "", target))
      absolute <- grepl("^[A-Za-z]:[/\\\\]|^/", file)
      resolved <- if (!nzchar(file)) path else if (absolute) file else file.path(dirname(path), file)
      if (!file.exists(resolved) && grepl("\\.html$", resolved) &&
          file.exists(sub("\\.html$", ".Rmd", resolved))) resolved <- sub("\\.html$", ".Rmd", resolved)
      links <- links + 1L
      if (!file.exists(resolved)) {
        failures <- c(failures, paste(path, "missing local target:", target))
      } else if (nzchar(fragment)) {
        anchors <- anchors + 1L
        if (dir.exists(resolved) || !fragment %in% documentation_attributes(render(resolved), "id")) {
          failures <- c(failures, paste(path, "missing local anchor:", target))
        }
      }
    }
  }
  list(blocks = blocks, links = links, anchors = anchors, failures = failures)
}
