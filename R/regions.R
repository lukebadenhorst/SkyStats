# Analysis regions: one row per region, with a lon/lat bbox and the
# equal-area CRS the spatial methods will project into. Bboxes avoid the
# antimeridian. World has no projected CRS (regression only, country level).
# Regression needs at least 15 countries, so only World and Europe allow it
# (checked with spData::world: the other regions have 8 to 11).

regions <- data.frame(
  id = c("world", "europe", "north_america", "southern_africa", "east_asia"),
  label = c(
    "World",
    "Europe",
    "North America",
    "Southern Africa",
    "East Asia"
  ),
  lon_min = c(-180, -25, -170, 10, 95),
  lat_min = c(-90, 34, 15, -35, 18),
  lon_max = c(180, 45, -50, 41, 150),
  lat_max = c(90, 72, 72, -8, 55),
  crs = c(NA, "EPSG:3035", "ESRI:102008", "ESRI:102022", "ESRI:102025"),
  allow_regression = c(TRUE, TRUE, FALSE, FALSE, FALSE),
  stringsAsFactors = FALSE
)

# Named vector for selectInput(): labels shown, ids returned.
region_choices <- function() {
  stats::setNames(regions$id, regions$label)
}

get_region <- function(id) {
  r <- regions[regions$id == id, , drop = FALSE]
  if (nrow(r) != 1) {
    stop("Unknown region: ", id, call. = FALSE)
  }
  as.list(r)
}

# Keep rows whose lon/lat fall inside the region bbox.
crop_to_region <- function(df, region_id) {
  r <- get_region(region_id)
  keep <- !is.na(df$longitude) &
    !is.na(df$latitude) &
    df$longitude >= r$lon_min &
    df$longitude <= r$lon_max &
    df$latitude >= r$lat_min &
    df$latitude <= r$lat_max
  df[keep, , drop = FALSE]
}

# The region's bbox as a polygon in EPSG:4326, with n points along each
# edge so the edges stay curved after projection. Built by hand because
# sf::st_segmentize() needs lwgeom.
region_polygon <- function(region_id, n = 60) {
  r <- get_region(region_id)
  edge <- function(from, to) seq(from, to, length.out = n + 1)[-(n + 1)]
  lon <- c(
    edge(r$lon_min, r$lon_max),
    rep(r$lon_max, n),
    edge(r$lon_max, r$lon_min),
    rep(r$lon_min, n)
  )
  lat <- c(
    rep(r$lat_min, n),
    edge(r$lat_min, r$lat_max),
    rep(r$lat_max, n),
    edge(r$lat_max, r$lat_min)
  )
  ring <- cbind(c(lon, lon[1]), c(lat, lat[1]))
  sf::st_sfc(sf::st_polygon(list(ring)), crs = 4326)
}

# The region's equal-area CRS. World has none, so the point and hex methods
# cannot run there.
region_crs <- function(region_id) {
  r <- get_region(region_id)
  if (is.na(r$crs)) {
    stop_user("World has no equal-area projection. Pick a region to run this method.")
  }
  r$crs
}

# The region polygon projected into the region's CRS.
region_window <- function(region_id) {
  sf::st_transform(region_polygon(region_id), region_crs(region_id))
}

# Points inside the region as sf POINTs in the region's CRS. All columns
# are kept, including longitude and latitude. Zero rows is allowed.
to_region_sf <- function(df, region_id) {
  crs <- region_crs(region_id)
  df <- crop_to_region(df, region_id)
  if (nrow(df) == 0) {
    # st_as_sf() warns when computing the bbox of zero points.
    empty <- sf::st_sfc(sf::st_point(), crs = 4326)[0]
    pts <- sf::st_sf(df, geometry = empty)
  } else {
    pts <- sf::st_as_sf(df, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
  }
  sf::st_transform(pts, crs)
}
