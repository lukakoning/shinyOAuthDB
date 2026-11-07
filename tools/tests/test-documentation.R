root <- normalizePath(file.path("..", ".."), winslash = "/")
source(file.path(root, "tools", "documentation.R"), local = TRUE)

test_that("rendered links resolve headings, explicit IDs, duplicate IDs and encoded paths", {
  directory <- withr::local_tempdir()
  guide <- file.path(directory, "guide with spaces.md")
  writeLines(
    c(
      "# Hello, *world*!",
      "# Hello, *world*!",
      '<a id="manual"></a>',
      "```text",
      "# Fake heading",
      "[ignored](missing.md#missing)",
      "```"
    ),
    guide
  )
  index <- file.path(directory, "index.md")
  writeLines(
    c(
      "# Index",
      "[self](#index)",
      "[one](guide%20with%20spaces.md#hello-world)",
      "[duplicate](guide%20with%20spaces.md#hello-world-1)",
      "[explicit](guide%20with%20spaces.md#manual)",
      '[title](guide%20with%20spaces.md "Guide")',
      "[external](https://example.invalid/#anything)"
    ),
    index
  )
  result <- documentation_check(c(index, guide))
  expect_identical(result$failures, character())
  expect_identical(result$links, 5L)
  expect_identical(result$anchors, 4L)
})

test_that("missing local files and section anchors fail validation", {
  directory <- withr::local_tempdir()
  index <- file.path(directory, "index.md")
  writeLines(
    c(
      "# Present",
      "[missing](#absent)",
      "[missing file](missing.md)",
      "[missing section](index.md#absent)"
    ),
    index
  )
  result <- documentation_check(index)
  expect_length(result$failures, 3L)
  expect_true(any(grepl("missing local target", result$failures)))
  expect_equal(sum(grepl("missing local anchor", result$failures)), 2)
})

test_that("local links retain apostrophes inside quoted HTML attributes", {
  directory <- withr::local_tempdir()
  writeLines("# Reader", file.path(directory, "reader's.md"))
  index <- file.path(directory, "index.md")
  writeLines(
    c("[reader](reader's.md)", "<a href=\"reader's.md\">reader</a>"),
    index
  )
  result <- documentation_check(index)
  expect_identical(result$failures, character())
  expect_identical(result$links, 2L)
})

test_that("vignette HTML anchors use source Markdown without executing R", {
  directory <- withr::local_tempdir()
  guide <- file.path(directory, "guide.Rmd")
  writeLines(
    c(
      "---",
      "title: Guide",
      "output: html_document",
      "---",
      "## Use a `token`",
      "```{r}",
      'stop("Must never execute")',
      "```"
    ),
    guide
  )
  index <- file.path(directory, "index.Rmd")
  writeLines("[guide](guide.html#use-a-token)", index)
  result <- documentation_check(c(index, guide))
  expect_identical(result$failures, character())
  expect_identical(result$blocks, 1L)
  expect_identical(result$anchors, 1L)
  writeLines(c("```r", "function(", "```"), guide)
  result <- documentation_check(guide)
  expect_length(result$failures, 1L)
  expect_match(result$failures, "R block")
})

test_that("documentation discovery includes every integration guide", {
  withr::local_dir(root)
  guides <- list.files(
    "integration",
    "\\.md$",
    recursive = TRUE,
    full.names = TRUE
  )
  expect_true(length(guides) > 1L)
  expect_true(all(guides %in% documentation_paths()))
})
