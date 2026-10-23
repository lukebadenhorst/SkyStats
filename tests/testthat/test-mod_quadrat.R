library(shiny)
library(bslib)
for (f in c("mod_common.R", "mod_quadrat.R")) source(file.path(root, "R", f))

sample_aircraft <- prep_states(readRDS(sample_path)$data)
no_airports <- data.frame(longitude = numeric(), latitude = numeric(), type = character())

test_that("the tab runs on the sample aircraft in Europe", {
  testServer(
    quadrat_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = reactive("europe"), airports = no_airports, active = reactive(TRUE)),
    {
      session$setInputs(points = "aircraft", airport_types = "large_airport", nx = 6, ny = 6, alpha = "0.05", setup_region = "europe", setup_run = 1)
      session$elapse(700)
      expect_true(result()$ok)
      res <- result()$value
      expect_equal(res$vtmr$m, 36)
      # Only airborne aircraft inside the test rectangle are used.
      expect_equal(nrow(res$points), sum(res$tiles$count))
      expect_lte(nrow(res$points), sum(sample_aircraft$airborne))
      expect_s3_class(res$rect, "sfc")
    }
  )
})

test_that("airports are filtered by type, and few points give the user message", {
  airports <- data.frame(longitude = c(10, 11), latitude = c(50, 51), type = c("large_airport", "small_airport"))
  testServer(
    quadrat_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = reactive("europe"), airports = airports, active = reactive(TRUE)),
    {
      session$setInputs(
        points = "airports", airport_types = c("large_airport", "medium_airport"),
        nx = 15, ny = 15, alpha = "0.05", setup_region = "europe", setup_run = 1
      )
      session$elapse(700)
      expect_match(result()$message, "^Only 1 points")
    }
  )
})

test_that("World is refused with the region message", {
  testServer(
    quadrat_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = reactive("world"), airports = no_airports, active = reactive(TRUE)),
    {
      session$setInputs(points = "aircraft", airport_types = "large_airport", nx = 6, ny = 6, alpha = "0.05", setup_region = "europe", setup_run = 1)
      session$elapse(700)
      expect_true(result()$region_refused)
      expect_match(result()$message, "World has no equal-area projection")
    }
  )
})

test_that("poisson_bins gives the expected quadrats per histogram bin", {
  b <- poisson_bins(c(0, 1, 1, 2, 3, 5), mean = 2)
  expect_equal(b$breaks, seq(-0.5, 5.5, 1))
  expect_equal(b$expected, 6 * stats::dpois(0:5, 2))

  wide <- poisson_bins(c(0, 100, 400), mean = 150)
  expect_lte(length(wide$breaks), 32)
  expect_equal(sum(wide$expected), 3 * stats::ppois(max(wide$breaks), 150), tolerance = 1e-9)
})
