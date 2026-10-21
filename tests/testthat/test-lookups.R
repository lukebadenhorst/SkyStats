test_that("the airport lookup keeps large and medium airports", {
  a <- load_airports(file.path(root, airports_path))
  expect_gt(nrow(a), 5000)
  expect_setequal(unique(a$type), c("large_airport", "medium_airport"))
  expect_false(anyNA(a$latitude) || anyNA(a$longitude))
})

test_that("Namibia's ISO code survives as the string NA", {
  a <- load_airports(file.path(root, airports_path))
  expect_true("NA" %in% a$iso_country)
})

test_that("a missing airport file gives an empty table", {
  a <- load_airports("nope.rds")
  expect_equal(nrow(a), 0)
  expect_named(a, c("ident", "type", "name", "latitude", "longitude", "iso_country"))
})
