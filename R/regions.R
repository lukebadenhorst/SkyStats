# Analysis regions: one row per region, with a lon/lat bbox and the
# equal-area CRS the spatial methods will project into. Bboxes avoid the
# antimeridian. World has no projected CRS (regression only, country level).

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
  allow_regression = c("yes", "yes", "no", "if >= 15 countries", "if >= 15 countries"),
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
