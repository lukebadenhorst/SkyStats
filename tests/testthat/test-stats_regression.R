# sf:: loads sf first, so merge() dispatches to merge.sf and keeps the geometry.
wb <- sf::st_as_sf(merge(spData::world, spData::worldbank_df, by = "iso_a2"))
f <- unemployment ~ literacy + log(urban_pop)

# Numbers below are from the 23 countries with complete data (Ch 6 workflow,
# KNN k = 2 on great-circle distances). The notes' printout used 4 countries.
test_that("the Ch 6 workflow gives the pinned values", {
  res <- suppressWarnings(run_regression(wb, f, weights = "knn", k = 2))
  expect_equal(res$n, 23)
  expect_equal(res$ols$estimate, c(-5.63978612, 0.13080027, 0.16700095), tolerance = 1e-7)
  expect_equal(res$resid_moran$observed, 0.155019369, tolerance = 1e-7)
  expect_equal(res$lm_tests$test, c("LMlag", "LMerr", "RLMlag", "RLMerr"))
  expect_equal(res$lm_tests$statistic, c(0.21337483, 0.63562008, 3.54754354, 3.96978878), tolerance = 1e-6)
  expect_equal(res$rho, 0.13104414, tolerance = 1e-6)
  expect_equal(res$aic$aic, c(162.0058, 163.7267), tolerance = 1e-4)
  expect_equal(res$recommendation, "OLS")
})

test_that("too few countries give a user message", {
  expect_error(
    suppressWarnings(run_regression(wb, f, "knn", k = 2, min_n = 30)),
    "^Only 23 countries",
    class = "user_error"
  )
})

test_that("the formula is built from the covariate choices", {
  expect_equal(deparse(regression_formula(c("pop", "airports"))), "log1p(aircraft) ~ log(pop) + log1p(airports)")
  expect_equal(deparse(regression_formula("area_km2", log_y = FALSE)), "aircraft ~ log(area_km2)")
  expect_error(regression_formula(character()), "at least one", class = "user_error")
})

test_that("country_units counts aircraft and airports per country", {
  ac <- data.frame(longitude = c(2.35, 13.4, 13.5), latitude = c(48.86, 52.5, 52.5))
  ap <- data.frame(iso_country = c("FR", "DE", "NA"))
  u <- country_units("europe", ac, ap) # 44, including Northern Cyprus (iso_a2 NA)
  expect_equal(nrow(u), 44)
  expect_equal(sf::st_crs(u), sf::st_crs("EPSG:3035"))
  expect_equal(u$aircraft[which(u$iso_a2 == "FR")], 1)
  expect_equal(u$aircraft[which(u$iso_a2 == "DE")], 2)
  expect_equal(u$airports[which(u$iso_a2 == "FR")], 1)
  expect_error(country_units("north_america", ac, ap), "only available for Europe", class = "user_error")
})

test_that("queen weights in Europe run despite the islands", {
  ac <- readRDS(sample_path)$data
  ac <- ac[!is.na(ac$longitude), ]
  u <- country_units("europe", ac, data.frame(iso_country = character()))
  res <- suppressWarnings(run_regression(u, log1p(aircraft) ~ log(pop) + log(gdpPercap), weights = "queen"))
  expect_gte(res$n_isolates, 1)
  expect_true(is.finite(res$rho))
})
