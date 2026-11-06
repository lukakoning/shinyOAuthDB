fixture_dbplyr_checks <- function(con, table, username) {
  rows <- dplyr::tbl(con, table)
  marker <- paste0(username, "-visible-1")
  filtered <- dplyr::collect(dplyr::select(dplyr::filter(rows, .data$marker == !!marker), "marker"))
  empty <- dplyr::collect(dplyr::select(dplyr::filter(rows, .data$marker == "absent-fixture-row"), "marker"))
  list(dbplyr_filter = identical(filtered$marker, marker),
    dbplyr_empty = identical(names(empty), "marker") && nrow(empty) == 0L)
}
