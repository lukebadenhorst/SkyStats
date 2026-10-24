nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
nc$value <- nc$SID74

test_that("Moran's I matches Example 4.1", {
  g <- run_autocorr(nc, "queen", style = "W", statistic = "moran")$global
  expect_equal(g$observed, 0.147740529, tolerance = 1e-8)
  expect_equal(g$expectation, -0.010101010, tolerance = 1e-8)
  expect_equal(g$variance, 0.003925567, tolerance = 1e-8)
  expect_equal(g$z, 2.519243, tolerance = 1e-6)
  expect_equal(g$p_value, 0.005880369, tolerance = 1e-8)
})

test_that("Geary's C and Global G match spdep", {
  expect_equal(run_autocorr(nc, statistic = "geary")$global$observed, 0.843876721, tolerance = 1e-8)
  expect_equal(run_autocorr(nc, style = "B", statistic = "globalg")$global$observed, 0.06740078, tolerance = 1e-7)
})

test_that("permutation inference keeps the observed value", {
  set.seed(1)
  g <- run_autocorr(nc, statistic = "moran", inference = "perm", nsim = 499)$global
  expect_equal(g$observed, 0.147740529, tolerance = 1e-8)
  expect_lt(g$p_value, 0.05)
  expect_error(run_autocorr(nc, statistic = "globalg", inference = "perm"), "Global G", class = "user_error")
})

test_that("LISA labels every unit", {
  res <- run_autocorr(nc)
  expect_equal(nrow(res$lisa), 100)
  expect_equal(levels(res$lisa$cluster), c("High-High", "Low-Low", "High-Low", "Low-High", "Not significant"))
  expect_true(all(run_autocorr(nc, alpha = 1e-12)$lisa$cluster == "Not significant"))
  expect_match(res$interpretation, "so we reject H0")
})

test_that("hex_counts counts every point once", {
  win <- sf::st_as_sfc(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 1e5, ymax = 1e5), crs = 3035))
  set.seed(2)
  pts <- sf::st_sample(win, 200)
  hx <- hex_counts(pts, win, hex_km = 10)
  expect_equal(sum(hx$count), 200)
  expect_equal(hx$value, log1p(hx$count))
})

test_that("too few hexes or constant values give a user message", {
  win <- sf::st_as_sfc(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 1e5, ymax = 1e5), crs = 3035))
  big <- hex_counts(sf::st_sample(win, 50), win, hex_km = 50)
  expect_error(run_autocorr(big), "^Only \\d+ hexes", class = "user_error")
  flat <- nc
  flat$value <- 1
  expect_error(run_autocorr(flat), "same value", class = "user_error")
})

test_that("an empty number of simulations gives a user message", {
  expect_error(run_autocorr(nc, inference = "perm", nsim = NA), "99 simulations", class = "user_error")
})
