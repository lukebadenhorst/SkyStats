nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)

test_that("queen weights on nc reproduce the Ch 4 Moran's I", {
  w <- build_weights(nc, "queen", style = "W")
  expect_equal(w$n_isolates, 0)
  m <- spdep::moran.test(nc$SID74, w$listw, alternative = "greater")
  expect_equal(unname(m$estimate[1]), 0.147740529, tolerance = 1e-8)
})

test_that("knn gives exactly k neighbours", {
  w <- build_weights(nc, "knn", k = 4)
  expect_true(all(spdep::card(w$nb) == 4))
})

test_that("a too-short distance band is refused with the minimum", {
  expect_error(build_weights(nc, "dist", d_km = 1), "Use at least 42 km", class = "user_error")
  w <- build_weights(nc, "idw", d_km = 100, style = "W")
  expect_equal(w$n_isolates, 0)
  expect_equal(sum(w$listw$weights[[1]]), 1)
})

test_that("queen on points is refused, and islands are counted", {
  pts <- sf::st_centroid(sf::st_geometry(nc))
  expect_error(build_weights(pts, "queen"), "needs polygons", class = "user_error")
  w <- suppressWarnings(build_weights(spData::world, "queen"))
  expect_gt(w$n_isolates, 0)
})

test_that("an empty or impossible k or distance band gives a user message", {
  expect_error(build_weights(nc, "knn", k = NA), "whole number of neighbours", class = "user_error")
  expect_error(build_weights(nc, "knn", k = 0), "whole number of neighbours", class = "user_error")
  expect_error(build_weights(nc, "knn", k = 2.5), "whole number of neighbours", class = "user_error")
  expect_error(build_weights(nc, "knn", k = 100), "at most 99", class = "user_error")
  expect_error(build_weights(nc, "dist", d_km = NA), "distance band in km", class = "user_error")
  expect_error(build_weights(nc, "idw", d_km = -5), "distance band in km", class = "user_error")
})
