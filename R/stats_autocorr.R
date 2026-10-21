# Spatial autocorrelation (Ch 4): global Moran's I, Geary's C and Global G,
# plus LISA (local Moran's I) on a hex grid. Pure: no Shiny.

# Count points in a hexagonal grid over window.
# points: sf or sfc, in the window's (projected, metres) CRS.
# hex_km: distance between opposite hex edges, in km.
# Returns sf POLYGONs with hex_id, count (integer) and value (log1p(count)
# when log, else count). Only hexes that touch the window are kept. A point
# on a shared edge is counted once, in the first hex it falls in.
hex_counts <- function(points, window, hex_km, log = TRUE) {
  hexes <- sf::st_make_grid(window, cellsize = hex_km * 1000, square = FALSE)
  hexes <- hexes[lengths(sf::st_intersects(hexes, window)) > 0]

  hits <- sf::st_intersects(sf::st_geometry(points), hexes)
  first_hex <- vapply(hits, function(h) if (length(h)) h[1] else NA_integer_, integer(1))
  count <- tabulate(first_hex[!is.na(first_hex)], nbins = length(hexes))

  sf::st_sf(
    hex_id = seq_along(hexes),
    count = as.integer(count),
    value = if (log) log1p(count) else as.numeric(count),
    geometry = hexes
  )
}

# Global and local autocorrelation of units$value.
# weights, k, d_km, style: passed to build_weights().
# statistic: "moran", "geary" or "globalg". inference: "analytic" or "perm"
# (permutation, not available for Global G). alpha: significance level for
# the decision and the LISA clusters.
# Returns list(global, scatter, lisa, weights_label, n_isolates,
# interpretation).
run_autocorr <- function(units, weights = "queen", k = 6, d_km = 300, style = "W",
                         statistic = c("moran", "geary", "globalg"),
                         inference = c("analytic", "perm"), nsim = 499, alpha = 0.05) {
  statistic <- match.arg(statistic)
  inference <- match.arg(inference)
  alpha <- as.numeric(alpha)
  value <- units$value

  if (nrow(units) < 30) {
    stop_user("Only ", nrow(units), " hexes in this region. Use smaller hexes (at least 30 are needed).")
  }
  if (length(unique(value)) < 2) {
    stop_user(
      "Every hex has the same value, so autocorrelation can't be measured. ",
      "Change the filters or the hex size."
    )
  }
  if (statistic == "globalg" && inference == "perm") {
    stop_user("Permutation inference isn't available for Global G. Use analytic.")
  }

  w <- build_weights(units, weights, k = k, d_km = d_km, style = style)
  listw <- w$listw

  global <- global_test(value, listw, statistic, inference, min(nsim, 999))

  lm <- spdep::localmoran(value, listw, zero.policy = TRUE)
  p_local <- lm[, 5]
  cluster <- as.character(attr(lm, "quadr")$mean)
  cluster[is.na(p_local) | p_local > alpha] <- "Not significant"
  lisa <- units
  lisa$Ii <- lm[, "Ii"]
  lisa$p_value <- p_local
  lisa$cluster <- factor(cluster, levels = c("High-High", "Low-Low", "High-Low", "Low-High", "Not significant"))

  list(
    global = global,
    scatter = data.frame(value = value, lag = spdep::lag.listw(listw, value, zero.policy = TRUE)),
    lisa = lisa,
    weights_label = w$label,
    n_isolates = w$n_isolates,
    interpretation = autocorr_text(global, statistic, lisa$cluster, alpha)
  )
}

# One-row data.frame: statistic, observed, expectation, variance, z, p_value.
# All tests use alternative = "greater" (positive autocorrelation), so for
# Geary's C a positive z means C below its expectation, as in geary.test().
global_test <- function(value, listw, statistic, inference, nsim) {
  name <- c(moran = "Moran's I", geary = "Geary's C", globalg = "Global G")[[statistic]]

  if (inference == "analytic") {
    test <- switch(
      statistic,
      moran = spdep::moran.test(value, listw, alternative = "greater", zero.policy = TRUE),
      geary = spdep::geary.test(value, listw, alternative = "greater", zero.policy = TRUE),
      globalg = spdep::globalG.test(value, listw, alternative = "greater", zero.policy = TRUE)
    )
    est <- unname(test$estimate)
    return(data.frame(
      statistic = name, observed = est[1], expectation = est[2], variance = est[3],
      z = unname(test$statistic), p_value = test$p.value
    ))
  }

  mc <- switch(
    statistic,
    moran = spdep::moran.mc(value, listw, nsim = nsim, alternative = "greater", zero.policy = TRUE),
    geary = spdep::geary.mc(value, listw, nsim = nsim, alternative = "greater", zero.policy = TRUE)
  )
  sims <- mc$res[seq_len(nsim)]
  observed <- unname(mc$statistic)
  expectation <- mean(sims)
  variance <- stats::var(sims)
  z <- (observed - expectation) / sqrt(variance)
  if (statistic == "geary") z <- -z
  data.frame(
    statistic = name, observed = observed, expectation = expectation, variance = variance,
    z = z, p_value = mc$p.value
  )
}

# Plain-English interpretation of the global test and the LISA clusters.
autocorr_text <- function(global, statistic, cluster, alpha) {
  symbol <- c(moran = "I", geary = "C", globalg = "G")[[statistic]]
  reject <- global$p_value < alpha
  digits <- if (statistic == "globalg") "%.4f" else "%.3f"

  stat_txt <- paste0(
    global$statistic, " = ", sprintf(digits, global$observed),
    " (expected ", sprintf(digits, global$expectation), " under H0), z = ", sprintf("%.2f", global$z), "."
  )

  meaning <- if (!reject) {
    "There is no evidence that neighbouring hexes have more similar counts than chance would give."
  } else {
    switch(
      statistic,
      moran = paste0(
        "I is above E[I]: neighbouring hexes have similar counts, so air traffic is clustered ",
        "rather than spread at random."
      ),
      geary = paste0(
        "C is below 1: neighbouring hexes have similar counts (positive autocorrelation), ",
        "so air traffic is clustered."
      ),
      globalg = paste0(
        "G is above E[G]: high counts sit next to other high counts, so the busy hexes form hot spots."
      )
    )
  }

  lisa_txt <- paste0(
    "LISA finds ", sum(cluster == "High-High"), " High-High and ", sum(cluster == "Low-Low"),
    " Low-Low hexes at α = ", format(alpha), "."
  )

  paste(
    paste0("H0: aircraft counts are spread randomly across the hexes (no spatial autocorrelation). ", stat_txt),
    decision_text(global$p_value, alpha),
    meaning,
    lisa_txt
  )
}
