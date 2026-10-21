# Quadrat test for complete spatial randomness (Ch 7): the chi-squared
# quadrat test and the variance-to-mean ratio (VTMR). Pure: no Shiny.

# A large axis-aligned rectangle inside window (sf or sfc polygon, in a
# projected CRS), as an sfc POLYGON in the same CRS.
# The VTMR assumes equal quadrats. A projected region is curved, so a grid
# over it has small clipped tiles at the edges, which make the VTMR report
# clustering for random points and fail the expected-count check. A grid
# over this rectangle has equal quadrats. Points outside it are left out.
# Method: grow a rectangle from the window's centre (same shape as the
# bbox) until it no longer fits, then push each side out as far as it can.
quadrat_window <- function(window) {
  crs <- sf::st_crs(window)
  # The search runs without a CRS: with one, sf looks it up on every
  # check, which makes EPSG:3035 (Europe) several times slower.
  win <- sf::st_set_crs(sf::st_union(sf::st_geometry(window)), NA)
  bb <- as.numeric(sf::st_bbox(win)) # xmin, ymin, xmax, ymax
  centre <- as.numeric(sf::st_coordinates(sf::st_point_on_surface(win)))

  rect <- function(b) {
    ring <- cbind(b[c(1, 3, 3, 1, 1)], b[c(2, 2, 4, 4, 2)])
    sf::st_polygon(list(ring))
  }
  fits <- function(b) sf::st_covers(win, sf::st_sfc(rect(b)), sparse = FALSE)[1, 1]
  # Largest t in [0, 1] with fits(make(t)), by bisection (make(0) fits).
  grow <- function(make) {
    if (fits(make(1))) {
      return(make(1))
    }
    lo <- 0
    hi <- 1
    for (i in 1:20) {
      mid <- (lo + hi) / 2
      if (fits(make(mid))) lo <- mid else hi <- mid
    }
    make(lo)
  }

  b <- grow(function(t) c(centre - t * (centre - bb[1:2]), centre + t * (bb[3:4] - centre)))
  for (round in 1:2) {
    for (side in 1:4) {
      start <- b
      b <- grow(function(t) {
        out <- start
        out[side] <- start[side] + t * (bb[side] - start[side])
        out
      })
    }
  }
  sf::st_sfc(rect(b), crs = crs)
}

# Convert points to a spatstat point pattern in window.
# points: sf or sfc, in the window's (projected, metres) CRS.
# window: sf or sfc polygon. Points outside it are dropped first, so the
# pattern is built with check = FALSE and ppp() never warns (live data
# often has duplicate positions, which ppp() would otherwise warn about).
as_ppp <- function(points, window) {
  win <- spatstat.geom::as.owin(sf::st_geometry(window))
  xy <- sf::st_coordinates(sf::st_geometry(points))
  x <- if (length(xy)) xy[, "X"] else numeric()
  y <- if (length(xy)) xy[, "Y"] else numeric()
  keep <- spatstat.geom::inside.owin(x, y, win)
  spatstat.geom::ppp(x[keep], y[keep], window = win, check = FALSE)
}

# Quadrat test of X (a ppp) on an nx by ny grid of quadrats.
# alpha: significance level for both decisions. crs: the CRS of X's
# coordinates, given to the returned tiles.
# Returns list(chisq, vtmr, tiles, interpretation).
run_quadrat <- function(X, nx = 6, ny = 6, alpha = 0.05, crs = NA) {
  alpha <- as.numeric(alpha)
  n <- spatstat.geom::npoints(X)
  if (n < 30) {
    stop_user("Only ", n, " points in this region. At least 30 are needed; widen the filters.")
  }

  # The app checks the expected counts itself, so the "expected counts are
  # small" warning from quadrat.test() is not needed.
  qt <- suppressWarnings(spatstat.explore::quadrat.test(X, nx = nx, ny = ny))
  if (min(qt$expected) < 5) {
    stop_user(
      "Some quadrats expect fewer than 5 points (smallest: ",
      sprintf("%.1f", min(qt$expected)), "). Use fewer quadrats."
    )
  }

  chisq <- data.frame(
    statistic = unname(qt$statistic),
    df = unname(qt$parameter),
    p_value = qt$p.value
  )

  # Tiles outside an irregular window are left out of the counts.
  Q <- spatstat.geom::quadratcount(X, nx = nx, ny = ny)
  counts <- as.vector(Q)
  m <- length(counts)
  mean_count <- mean(counts)
  var_count <- stats::var(counts)
  vtmr_value <- var_count / mean_count
  stat <- (m - 1) * vtmr_value
  p_vtmr <- min(1, 2 * min(
    stats::pchisq(stat, m - 1),
    stats::pchisq(stat, m - 1, lower.tail = FALSE)
  ))
  vtmr <- data.frame(
    m = m, mean = mean_count, variance = var_count, vtmr = vtmr_value,
    statistic = stat, df = m - 1, p_value = p_vtmr
  )

  # as.vector(Q) runs down the columns but the tiles run along the rows.
  # quadrat.test()$observed is in tile order, so use it for the tiles.
  tile_list <- spatstat.geom::tiles(spatstat.geom::as.tess(Q))
  geoms <- do.call(c, lapply(tile_list, sf::st_as_sfc))
  tiles <- sf::st_sf(
    count = as.integer(qt$observed),
    expected = as.numeric(qt$expected),
    geometry = sf::st_set_crs(geoms, crs)
  )

  list(
    chisq = chisq,
    vtmr = vtmr,
    tiles = tiles,
    interpretation = quadrat_text(chisq, vtmr, alpha)
  )
}

# Plain-English reading of the two tests.
quadrat_text <- function(chisq, vtmr, alpha) {
  pattern <- if (vtmr$p_value >= alpha) {
    "which is consistent with a random pattern."
  } else if (vtmr$vtmr < 1) {
    "which suggests a regular pattern."
  } else {
    "which suggests a clustered pattern."
  }
  paste0(
    "H0: the points follow complete spatial randomness (a homogeneous Poisson process). ",
    "χ² = ", sprintf("%.2f", chisq$statistic), " on ", chisq$df, " df. ",
    decision_text(chisq$p_value, alpha), " ",
    "VTMR = ", sprintf("%.2f", vtmr$vtmr), ", ", pattern
  )
}
