# Spatial weights for the autocorrelation and regression methods. Pure: no
# Shiny.

# Build a spatial weights list for units (sf polygons, or points for the
# distance-based types).
# type: "queen" (shared edge or corner), "knn" (k nearest centroids),
#   "dist" (all centroids within d_km) or "idw" (as dist, weighted 1 / d).
# style: "W" (row-standardised) or "B" (binary).
# Returns list(listw, nb, n_isolates, label). Units with no neighbours are
# allowed (zero.policy = TRUE) and counted in n_isolates.
build_weights <- function(units, type = c("queen", "knn", "dist", "idw"), k = 6, d_km = 300,
                          style = c("W", "B")) {
  type <- match.arg(type)
  style <- match.arg(style)
  glist <- NULL

  if (type == "queen") {
    is_poly <- sf::st_geometry_type(units) %in% c("POLYGON", "MULTIPOLYGON")
    if (!all(is_poly)) {
      stop_user("Queen contiguity needs polygons.")
    }
    nb <- spdep::poly2nb(units, queen = TRUE)
  } else {
    # Distances in km: spdep uses great-circle km for lon/lat, and projected
    # coordinates (metres) are divided by 1000.
    longlat <- isTRUE(sf::st_is_longlat(units))
    coords <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(units)))
    if (!longlat) {
      coords <- coords / 1000
    }

    if (type == "knn") {
      nb <- spdep::knn2nb(spdep::knearneigh(coords, k = k, longlat = longlat))
    } else {
      # A band shorter than the largest nearest-neighbour distance leaves
      # some units with no neighbours, so refuse it. The k = 1 graph is only
      # used for its distances, so its "sub-graphs" warning is muted.
      nn <- withCallingHandlers(
        spdep::knn2nb(spdep::knearneigh(coords, k = 1, longlat = longlat)),
        warning = function(w) {
          if (grepl("sub-graphs", conditionMessage(w))) invokeRestart("muffleWarning")
        }
      )
      min_d <- max(unlist(spdep::nbdists(nn, coords, longlat = longlat)))
      if (d_km < min_d) {
        stop_user(
          "A distance band of ", d_km, " km leaves some units with no neighbours. ",
          "Use at least ", ceiling(min_d), " km."
        )
      }
      nb <- spdep::dnearneigh(coords, 0, d_km, longlat = longlat)
      if (type == "idw") {
        glist <- lapply(spdep::nbdists(nb, coords, longlat = longlat), function(d) 1 / d)
      }
    }
  }

  label <- switch(
    type,
    queen = "Queen contiguity",
    knn = paste0(k, " nearest neighbours"),
    dist = paste0("Distance band ", d_km, " km"),
    idw = paste0("Inverse distance within ", d_km, " km")
  )

  list(
    listw = spdep::nb2listw(nb, glist = glist, style = style, zero.policy = TRUE),
    nb = nb,
    n_isolates = sum(spdep::card(nb) == 0),
    label = paste0(label, ", style ", style)
  )
}
