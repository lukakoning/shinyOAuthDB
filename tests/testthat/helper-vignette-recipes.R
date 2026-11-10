vignette_recipe_chunk <- function(name, label) {
  path <- test_path("..", "..", "vignettes", paste0(name, ".Rmd"))
  skip_if_not(file.exists(path), "Vignette source is unavailable")
  lines <- readLines(path, encoding = "UTF-8")
  start <- grep(paste0("^`{3}\\{r ", label, "[,}]"), lines)
  stopifnot(length(start) == 1L)
  end <- which(seq_along(lines) > start & lines == "```")[[1L]]
  parse(text = lines[seq.int(start + 1L, end - 1L)], keep.source = FALSE)
}
