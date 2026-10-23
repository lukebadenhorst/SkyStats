test_that("the tab list has the six tabs in order", {
  expect_equal(app_tabs$id, c("home", "live", "autocorr", "quadrat", "regression", "about"))
  expect_equal(app_tabs$kind[app_tabs$id == "autocorr"], "method")
})

test_that("each method offers only the regions it accepts", {
  expect_equal(method_regions("autocorr"), c("europe", "north_america", "southern_africa", "east_asia"))
  expect_equal(method_regions("quadrat"), method_regions("autocorr"))
  expect_equal(method_regions("regression"), c("world", "europe"))
  expect_error(method_regions("live"))
})

test_that("the default region keeps an accepted region and falls back to Europe", {
  expect_equal(default_method_region("east_asia", "autocorr"), "east_asia")
  expect_equal(default_method_region("world", "autocorr"), "europe")
  expect_equal(default_method_region("world", "regression"), "world")
  expect_equal(default_method_region("north_america", "regression"), "europe")
})
