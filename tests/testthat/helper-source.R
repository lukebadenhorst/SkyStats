# Source the non-Shiny app code so tests can call it directly: every R/*.R
# file whose name does not start with mod_.
# testthat runs with tests/testthat/ as the working directory.
root <- normalizePath(file.path("..", ".."))
for (f in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE)) {
  if (!startsWith(basename(f), "mod_")) source(f, local = FALSE, encoding = "UTF-8")
}

read_fixture <- function(name) {
  jsonlite::fromJSON(test_path("fixtures", name), simplifyVector = FALSE)
}

sample_path <- file.path(root, "data", "sample", "states_sample.rds")

test_airlines <- data.frame(
  icao = c("SAA", "BAW"),
  name = c("South African Airways", "British Airways"),
  country = c("South Africa", "United Kingdom")
)
