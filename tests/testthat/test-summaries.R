lisa <- data.frame(cluster = factor(c("High-High", "Low-Low", "Not significant", "High-High")))
moran <- list(global = data.frame(statistic = "Moran's I", observed = 0.421, expectation = -0.005,
                                  variance = 0.001, z = 8.14, p_value = 1e-6), lisa = lisa)

test_that("autocorrelation summary: significant Moran's I reads as clustered", {
  s <- autocorr_summary(moran, "moran", 0.05)
  expect_equal(s$label, "Global Moran's I")
  expect_equal(s$value, 0.421)
  expect_equal(s$digits, 3L)
  expect_equal(s$badge, "Clustered")
  expect_equal(s$tone, "hot")
  expect_equal(unname(s$mini), c("8.14", "< 0.001", "4", "3"))
  expect_equal(names(s$mini), c("z-score", "p-value", "Hexes", "Significant"))
  expect_match(s$text, "2 High-High and 1 Low-Low")
})

test_that("autocorrelation summary: Global G and a non-significant result", {
  g <- moran
  g$global$statistic <- "Global G"
  expect_equal(autocorr_summary(g, "globalg", 0.05)$badge, "Hot spots")
  expect_equal(autocorr_summary(g, "globalg", 0.05)$label, "Global G")
  expect_equal(autocorr_summary(g, "globalg", 0.05)$digits, 4L)
  ns <- moran
  ns$global$p_value <- 0.4
  expect_equal(autocorr_summary(ns, "moran", 0.05)$badge, "No clear pattern")
  expect_equal(autocorr_summary(ns, "moran", 0.05)$tone, "neutral")
})

quad <- function(vtmr, p) list(
  chisq = data.frame(statistic = 120.5, df = 35, p_value = 0.001),
  vtmr = data.frame(m = 36, mean = 10, variance = 10 * vtmr, vtmr = vtmr, statistic = 35 * vtmr, df = 35, p_value = p)
)

test_that("quadrat summary reads the VTMR", {
  expect_equal(quadrat_summary(quad(3.4, 0.001), 0.05)$badge, "Clustered")
  expect_equal(quadrat_summary(quad(0.4, 0.001), 0.05)$badge, "Regular")
  expect_equal(quadrat_summary(quad(0.4, 0.001), 0.05)$tone, "cool")
  expect_equal(quadrat_summary(quad(1.1, 0.6), 0.05)$badge, "Random")
  s <- quadrat_summary(quad(3.4, 0.001), 0.05)
  expect_equal(s$label, "Variance-to-mean ratio")
  expect_equal(s$value, 3.4)
  expect_equal(names(s$mini), c("χ²", "χ² p-value", "VTMR p-value", "Quadrats"))
  expect_equal(unname(s$mini[4]), "36")
})

reg <- function(rec) list(
  recommendation = rec, rho = 0.312, rho_p_value = 0.004,
  resid_moran = data.frame(observed = 0.214, expectation = -0.03, variance = 0.01, z = 2.4, p_value = 0.008),
  aic = data.frame(model = c("OLS", "Spatial lag"), aic = c(101.23, 95.4))
)

test_that("regression summary shows rho and the recommended model", {
  s <- regression_summary(reg("Spatial lag"))
  expect_equal(s$label, "Spatial lag ρ")
  expect_equal(s$value, 0.312)
  expect_equal(s$badge, "Spatial lag model")
  expect_equal(s$tone, "info")
  expect_equal(unname(s$mini), c("0.004", "0.214", "101.23", "95.40"))
  expect_equal(names(s$mini), c("ρ p-value", "Residual Moran's I", "AIC (OLS)", "AIC (lag)"))
  expect_equal(regression_summary(reg("OLS"))$badge, "OLS is enough")
  expect_equal(regression_summary(reg("OLS"))$tone, "neutral")
  expect_equal(regression_summary(reg("Spatial error"))$badge, "Spatial error model")
})
