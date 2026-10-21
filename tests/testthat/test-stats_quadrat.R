data(bei, package = "spatstat.data")

test_that("the bei example matches Example 7.1", {
  res <- run_quadrat(bei, nx = 6, ny = 6)
  expect_equal(unname(res$chisq$statistic), 2681.077, tolerance = 1e-6)
  expect_equal(unname(res$chisq$df), 35)
  expect_equal(res$vtmr$m, 36)
  expect_equal(res$vtmr$mean, 100.1111, tolerance = 1e-6)
  expect_equal(res$vtmr$vtmr, 76.60219, tolerance = 1e-6)
  expect_equal(res$vtmr$statistic, 35 * res$vtmr$vtmr)
  expect_lt(res$vtmr$p_value, 1e-10)
  expect_equal(sum(res$tiles$count), 3604)
  expect_match(res$interpretation, "clustered")
})

test_that("tile counts line up with their tiles", {
  res <- run_quadrat(bei, nx = 6, ny = 6)
  # Count the points inside each tile polygon directly.
  pts <- sf::st_as_sf(as.data.frame(bei), coords = c("x", "y"))
  direct <- lengths(sf::st_intersects(res$tiles, pts))
  expect_equal(res$tiles$count, direct)
  expect_s3_class(res$tiles, "sf")
  expect_equal(nrow(res$tiles), 36)
})

test_that("a perfect grid reads as regular", {
  g <- spatstat.geom::ppp(rep(seq(5, 95, 10), 10), rep(seq(5, 95, 10), each = 10), c(0, 100), c(0, 100))
  res <- run_quadrat(g, nx = 2, ny = 2) # 25 points per quadrat

  expect_equal(res$vtmr$vtmr, 0)
  expect_match(res$interpretation, "regular")
})

test_that("a random pattern reads as random", {
  set.seed(1)
  X <- spatstat.random::rpoispp(200)
  res <- run_quadrat(X, nx = 3, ny = 3)
  expect_gt(res$vtmr$p_value, 0.05)
  expect_match(res$interpretation, "consistent with a random pattern")
})

test_that("too few points, or too many quadrats, give user messages", {
  set.seed(3)
  few <- spatstat.random::runifpoint(10)
  expect_error(run_quadrat(few), "^Only 10 points", class = "user_error")
  forty <- spatstat.random::runifpoint(40)
  expect_error(run_quadrat(forty, nx = 10, ny = 10), "fewer than 5", class = "user_error")
})

test_that("as_ppp drops points outside the window", {
  win <- sf::st_as_sfc(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 1e5, ymax = 1e5), crs = 3035))
  set.seed(4)
  pts <- c(sf::st_sample(win, 50), sf::st_sfc(sf::st_point(c(2e5, 2e5)), crs = 3035))
  expect_equal(spatstat.geom::npoints(as_ppp(pts, win)), 50)
})

test_that("as_ppp keeps duplicate points without warning", {
  win <- sf::st_as_sfc(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 10, ymax = 10)))
  pts <- sf::st_sfc(sf::st_point(c(5, 5)), sf::st_point(c(5, 5)))
  expect_no_warning(X <- as_ppp(pts, win))
  expect_equal(spatstat.geom::npoints(X), 2)
})

test_that("the sample aircraft run in an irregular region window", {
  aircraft <- prep_states(readRDS(sample_path)$data)
  pts <- to_region_sf(aircraft, "europe")
  X <- as_ppp(pts, region_window("europe"))
  res <- run_quadrat(X, nx = 6, ny = 6, crs = region_crs("europe"))

  expect_equal(sum(res$tiles$count), spatstat.geom::npoints(X))
  expect_equal(nrow(res$tiles), res$vtmr$m)
  expect_lt(res$vtmr$m, 36) # corner tiles outside the curved window are left out
  expect_equal(sf::st_crs(res$tiles), sf::st_crs(region_crs("europe")))
})

test_that("quadrat_window is a large axis-aligned rectangle inside each region", {
  for (r in c("europe", "north_america", "southern_africa", "east_asia")) {
    win <- region_window(r)
    rect <- quadrat_window(win)
    area <- as.numeric(sf::st_area(rect))
    bbox_area <- as.numeric(sf::st_area(sf::st_as_sfc(sf::st_bbox(rect))))

    expect_true(sf::st_covers(win, rect, sparse = FALSE)[1, 1], info = r)
    expect_equal(area, bbox_area, tolerance = 1e-9, info = r) # a rectangle
    expect_gt(area / as.numeric(sf::st_area(win)), 0.5, label = paste(r, "area share"))
    expect_equal(sf::st_crs(rect), sf::st_crs(win), info = r)
  }
})

test_that("quadrat_window of a rectangle is the rectangle", {
  win <- sf::st_as_sfc(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 300, ymax = 100), crs = 3035))
  rect <- quadrat_window(win)
  expect_equal(as.numeric(sf::st_bbox(rect)), c(0, 0, 300, 100), tolerance = 1e-6)
})

test_that("random points in a region rectangle read as random", {
  # In the curved window, the clipped edge tiles are small, so the VTMR
  # wrongly reports clustering for random points. Equal quadrats fix this.
  win <- quadrat_window(region_window("europe"))
  set.seed(1)
  X <- as_ppp(sf::st_sample(win, 3000), win)
  res <- run_quadrat(X, nx = 6, ny = 6)

  expect_equal(res$vtmr$m, 36)
  expect_equal(min(res$tiles$expected), max(res$tiles$expected), tolerance = 1e-6)
  expect_gt(res$vtmr$p_value, 0.05)
})

test_that("the sample aircraft run at 6 x 6 in the region rectangles", {
  aircraft <- prep_states(readRDS(sample_path)$data)
  for (r in c("europe", "north_america", "east_asia")) {
    win <- quadrat_window(region_window(r))
    res <- run_safely(run_quadrat(as_ppp(to_region_sf(aircraft, r), win), crs = region_crs(r)))
    expect_true(res$ok, info = paste(r, res$message))
  }
})
