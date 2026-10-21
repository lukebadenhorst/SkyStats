test_that("region_polygon follows the bbox with dense edges", {
  p <- region_polygon("europe")
  expect_equal(as.numeric(sf::st_bbox(p)), c(-25, 34, 45, 72))
  expect_gte(nrow(sf::st_coordinates(p)), 4 * 60)
})

test_that("region_window is in the region's equal-area CRS", {
  w <- region_window("europe")
  expect_equal(sf::st_crs(w), sf::st_crs("EPSG:3035"))
  area_km2 <- as.numeric(sf::st_area(w)) / 1e6
  expect_gt(area_km2, 19e6)
  expect_lt(area_km2, 20e6)
})

test_that("World has no window", {
  expect_error(region_window("world"), "World has no equal-area projection", class = "user_error")
})

test_that("to_region_sf crops and projects", {
  df <- data.frame(longitude = c(10, 100, 2), latitude = c(50, 10, 48), id = 1:3)
  pts <- to_region_sf(df, "europe")
  expect_equal(pts$id, c(1L, 3L))
  expect_equal(sf::st_crs(pts), sf::st_crs("EPSG:3035"))
  expect_equal(nrow(to_region_sf(df[0, ], "europe")), 0)
})

test_that("regression is allowed only in Europe and World", {
  expect_equal(regions$id[regions$allow_regression], c("world", "europe"))
})
