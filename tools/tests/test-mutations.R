source(file.path("..", "mutation-policy.R"), local = TRUE)

testthat::test_that("mutation gates reject new survivors, timeouts, partial results and unexplained baselines", {
  baseline <- read.csv(
    file.path("..", "mutation-baseline.csv"),
    stringsAsFactors = FALSE
  )
  killed <- data.frame(
    file = "http.R",
    source_sha256 = "source-A",
    mutant_sha256 = "mutant-A",
    status = "KILLED"
  )
  testthat::expect_true(mutation_check_baseline(killed, baseline, "transport"))
  survivor <- killed
  survivor$status <- "SURVIVED"
  testthat::expect_error(
    mutation_check_baseline(survivor, baseline, "transport"),
    "New surviving"
  )
  reviewed <- cbind(
    profile = "transport",
    survivor,
    reason = "Equivalent result on supported input; fixture explanation."
  )
  testthat::expect_true(mutation_check_baseline(
    survivor,
    reviewed,
    "transport"
  ))
  changed <- survivor
  changed$source_sha256 <- "source-B"
  testthat::expect_error(
    mutation_check_baseline(changed, reviewed, "transport"),
    "New surviving"
  )
  changed <- survivor
  changed$mutant_sha256 <- "mutant-B"
  testthat::expect_error(
    mutation_check_baseline(changed, reviewed, "transport"),
    "New surviving"
  )
  testthat::expect_error(
    mutation_check_baseline(survivor, reviewed, "other-profile"),
    "New surviving"
  )
  hung <- survivor
  hung$status <- "HANG"
  testthat::expect_error(
    mutation_check_baseline(hung, reviewed, "transport"),
    "inconclusive"
  )
  reviewed$status <- "HANG"
  testthat::expect_error(
    mutation_check_baseline(hung, reviewed, "transport"),
    "reviewed baseline"
  )
  reviewed$status <- "SURVIVED"
  reviewed$reason <- " "
  testthat::expect_error(
    mutation_check_baseline(survivor, reviewed, "transport"),
    "explained"
  )
  testthat::expect_error(
    mutation_check_baseline(killed[FALSE, ], baseline, "transport"),
    "complete"
  )
  killed$status <- "ERROR"
  testthat::expect_error(
    mutation_check_baseline(killed, baseline, "transport"),
    "conclusive"
  )
})
