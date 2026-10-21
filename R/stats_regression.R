# Spatial regression (course notes Ch 6): OLS, Moran's I of the residuals,
# LM tests to choose a model, then a spatial lag model. Pure: no Shiny.

# Countries of spData::world whose centroid falls inside the region bbox,
# with the number of aircraft over each and airports in each.
# aircraft: data.frame with longitude and latitude.
# airports: data.frame with iso_country (see load_airports()).
# Returns sf with iso_a2, name_long, pop, gdpPercap, area_km2, airports,
# aircraft, in the region's CRS (World stays in EPSG:4326).
country_units <- function(region_id, aircraft, airports) {
  r <- get_region(region_id)
  if (!r$allow_regression) {
    stop_user("Regression needs at least 15 countries, so it is only available for Europe and the World.")
  }

  world <- spData::world
  xy <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(world)))
  inside <- xy[, "X"] >= r$lon_min &
    xy[, "X"] <= r$lon_max &
    xy[, "Y"] >= r$lat_min &
    xy[, "Y"] <= r$lat_max
  units <- world[inside, c("iso_a2", "name_long", "pop", "gdpPercap", "area_km2")]

  # Airports per country: 0 when there are none, NA when the country has no
  # ISO code (Northern Cyprus, Somaliland).
  n_airports <- table(airports$iso_country)
  units$airports <- as.numeric(n_airports[units$iso_a2])
  units$airports[is.na(units$airports)] <- 0
  units$airports[is.na(units$iso_a2)] <- NA

  # Aircraft over each country.
  ok <- !is.na(aircraft$longitude) & !is.na(aircraft$latitude)
  if (any(ok)) {
    pts <- sf::st_as_sf(aircraft[ok, c("longitude", "latitude")], coords = c("longitude", "latitude"), crs = 4326)
    units$aircraft <- lengths(sf::st_intersects(units, pts))
  } else {
    units$aircraft <- rep(0L, nrow(units))
  }

  if (!is.na(r$crs)) {
    units <- sf::st_transform(units, r$crs)
  }
  units
}

# Model formula from the covariate choices, in the order given.
# covariates: any of "pop", "gdpPercap", "area_km2", "airports".
regression_formula <- function(covariates, log_y = TRUE) {
  if (length(covariates) == 0) {
    stop_user("Pick at least one covariate.")
  }
  terms <- c(
    pop = "log(pop)",
    gdpPercap = "log(gdpPercap)",
    area_km2 = "log(area_km2)",
    airports = "log1p(airports)"
  )[covariates]
  lhs <- if (log_y) "log1p(aircraft)" else "aircraft"
  stats::as.formula(paste(lhs, "~", paste(terms, collapse = " + ")), env = globalenv())
}

# The Ch 6 workflow on units (sf) for formula:
#   1. OLS; 2. Moran's I of the OLS residuals; 3. LM tests and a
#   recommended model; 4. a spatial lag model, compared with OLS by AIC.
# Units with missing or non-finite model values are dropped first.
# Returns list(n, n_isolates, weights_label, ols, r_squared, resid_moran,
# lm_tests, recommendation, lag, rho, rho_p_value, aic, residuals,
# interpretation).
run_regression <- function(units, formula, weights = c("queen", "knn"), k = 4, alpha = 0.05, min_n = 15) {
  weights <- match.arg(weights)
  alpha <- as.numeric(alpha)

  # Complete cases: every variable present, and every transformed value
  # finite (log(0) would be -Inf).
  df <- sf::st_drop_geometry(units)
  complete <- stats::complete.cases(df[all.vars(formula)])
  mf <- stats::model.frame(formula, df, na.action = stats::na.pass)
  finite <- Reduce(`&`, lapply(mf, function(x) is.finite(as.numeric(x))))
  units_c <- units[complete & finite, ]
  n <- nrow(units_c)
  if (n < min_n) {
    stop_user("Only ", n, " countries have complete data. At least ", min_n, " are needed.")
  }
  data_c <- sf::st_drop_geometry(units_c)
  n_coef <- ncol(stats::model.matrix(formula, data_c))
  if (n <= n_coef + 2) {
    stop_user("Too many covariates for ", n, " countries. Remove one.")
  }

  w <- build_weights(units_c, weights, k = k, style = "W")
  listw <- w$listw

  # Step 1: OLS.
  ols <- stats::lm(formula, data = data_c)
  ols_coef <- summary(ols)$coefficients

  # Step 2: Moran's I of the OLS residuals.
  mt <- spdep::moran.test(stats::residuals(ols), listw, zero.policy = TRUE, alternative = "greater")
  resid_moran <- data.frame(
    observed = unname(mt$estimate["Moran I statistic"]),
    expectation = unname(mt$estimate["Expectation"]),
    variance = unname(mt$estimate["Variance"]),
    z = unname(mt$statistic),
    p_value = mt$p.value
  )

  # Step 3: LM tests.
  lm_raw <- spdep::lm.RStests(ols, listw, test = c("LMlag", "LMerr", "RLMlag", "RLMerr"), zero.policy = TRUE)
  lm_raw <- lm_raw[c("RSlag", "RSerr", "adjRSlag", "adjRSerr")]
  lm_tests <- data.frame(
    test = c("LMlag", "LMerr", "RLMlag", "RLMerr"),
    statistic = vapply(lm_raw, function(t) unname(t$statistic), numeric(1)),
    p_value = vapply(lm_raw, function(t) unname(t$p.value), numeric(1)),
    row.names = NULL
  )
  recommendation <- recommend_model(lm_tests$p_value, alpha)

  # Step 4: spatial lag model, always fitted (it is step 4 of the workflow).
  lag_fit <- spatialreg::lagsarlm(formula, data = data_c, listw = listw, zero.policy = TRUE)
  lag_sum <- summary(lag_fit)
  rho <- unname(lag_fit$rho)
  rho_p_value <- unname(lag_sum$LR1$p.value)
  aic <- data.frame(model = c("OLS", "Spatial lag"), aic = c(stats::AIC(ols), stats::AIC(lag_fit)))

  residuals <- units_c
  residuals$ols_resid <- unname(stats::residuals(ols))
  residuals$lag_resid <- unname(stats::residuals(lag_fit))

  list(
    n = n,
    n_isolates = w$n_isolates,
    weights_label = w$label,
    ols = coef_table(ols_coef),
    r_squared = summary(ols)$r.squared,
    resid_moran = resid_moran,
    lm_tests = lm_tests,
    recommendation = recommendation,
    lag = coef_table(lag_sum$Coef),
    rho = rho,
    rho_p_value = rho_p_value,
    aic = aic,
    residuals = residuals,
    interpretation = regression_text(resid_moran, lm_tests, recommendation, rho, rho_p_value, aic, alpha)
  )
}

# Coefficient matrix (lm or lagsarlm summary) as a data.frame with term,
# estimate, std_error, statistic, p_value.
coef_table <- function(m) {
  data.frame(
    term = rownames(m),
    estimate = unname(m[, 1]),
    std_error = unname(m[, 2]),
    statistic = unname(m[, 3]),
    p_value = unname(m[, 4]),
    row.names = NULL
  )
}

# The course rule. p: p-values of LMlag, LMerr, RLMlag, RLMerr.
# Neither LM test significant: OLS. One: that model. Both: the one whose
# robust test has the smaller p-value.
recommend_model <- function(p, alpha) {
  lag_sig <- p[1] < alpha
  err_sig <- p[2] < alpha
  if (!lag_sig && !err_sig) {
    "OLS"
  } else if (lag_sig && !err_sig) {
    "Spatial lag"
  } else if (err_sig && !lag_sig) {
    "Spatial error"
  } else if (p[3] <= p[4]) {
    "Spatial lag"
  } else {
    "Spatial error"
  }
}

# One sentence each for steps 2-4 of the workflow, as one string.
regression_text <- function(resid_moran, lm_tests, recommendation, rho, rho_p_value, aic, alpha) {
  p <- stats::setNames(lm_tests$p_value, lm_tests$test)
  pf <- function(x) if (x < 0.001) "p < 0.001" else paste("p =", format_p(x))

  step2 <- paste0(
    "Step 2: Moran's I of the OLS residuals is ", sprintf("%.3f", resid_moran$observed),
    " (H0: the residuals are not spatially autocorrelated); ",
    decision_text(resid_moran$p_value, alpha)
  )

  why <- if (recommendation == "OLS") {
    paste0("neither LMlag (", pf(p[["LMlag"]]), ") nor LMerr (", pf(p[["LMerr"]]), ") is significant")
  } else if (xor(p[["LMlag"]] < alpha, p[["LMerr"]] < alpha)) {
    test <- if (recommendation == "Spatial lag") "LMlag" else "LMerr"
    paste0("only ", test, " is significant (", pf(p[[test]]), ")")
  } else {
    paste0(
      "both LMlag and LMerr are significant, and the robust test is stronger for the ",
      if (recommendation == "Spatial lag") "lag" else "error",
      " model (RLMlag ", pf(p[["RLMlag"]]), ", RLMerr ", pf(p[["RLMerr"]]), ")"
    )
  }
  model_name <- c(OLS = "OLS", "Spatial lag" = "a spatial lag model", "Spatial error" = "a spatial error model")
  step3 <- paste0(
    "Step 3: At α = ", format(alpha), " ", why, ", so the LM tests recommend ",
    model_name[[recommendation]], "."
  )

  lag_better <- aic$aic[2] < aic$aic[1]
  step4 <- paste0(
    "Step 4: In the spatial lag model ρ = ", sprintf("%.3f", rho),
    " (LR test ", pf(rho_p_value), "). Its AIC is ", sprintf("%.2f", aic$aic[2]),
    " against ", sprintf("%.2f", aic$aic[1]), " for OLS, so ",
    if (lag_better) "the spatial lag model fits better." else "OLS fits better."
  )

  paste(step2, step3, step4)
}
