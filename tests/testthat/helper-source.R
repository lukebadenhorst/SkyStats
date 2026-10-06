# Source the non-Shiny app code so tests can call it directly.
# testthat runs with tests/testthat/ as the working directory.
root <- normalizePath(file.path("..", ".."))
for (f in c("regions.R", "data_api.R", "data_prep.R")) {
  source(file.path(root, "R", f), local = FALSE)
}

read_fixture <- function(name) {
  jsonlite::fromJSON(test_path("fixtures", name), simplifyVector = FALSE)
}

sample_path <- file.path(root, "data", "sample", "states_sample.rds")
