# The app's tabs and which regions each method accepts. Pure: no Shiny.

# One row per tab, in display order. `icon` is a bsicons name; `kind` is
# "page" for the plain pages and "method" for the three analysis tabs.
app_tabs <- data.frame(
  id = c("home", "live", "autocorr", "quadrat", "regression", "about"),
  label = c("Home", "Live Map", "Autocorrelation", "Point Patterns", "Spatial Regression", "About"),
  icon = c("house", "map", "grid-3x3", "dot", "graph-up", "info-circle"),
  kind = c("page", "page", "method", "method", "method", "page"),
  stringsAsFactors = FALSE
)

# Region ids a method accepts. Autocorrelation and the quadrat test need an
# equal-area CRS; regression needs enough countries (see regions.R).
method_regions <- function(method) {
  switch(
    method,
    autocorr = ,
    quadrat = regions$id[!is.na(regions$crs)],
    regression = regions$id[regions$allow_regression],
    stop("Unknown method: ", method)
  )
}

# Where the shared map should glide when the tab or the region changes: a
# region id, or NULL to leave it where it is. Home always shows the world.
# The method tabs always show their region. The Live Map and About follow a
# region change; the Live Map also goes back to the region when the map was
# left elsewhere (by Home), but otherwise keeps the user's own zoom.
#   last_target  the region id the map was last sent to
map_view_target <- function(tab, region, last_target, region_changed) {
  if (tab == "home") {
    return("world")
  }
  if (tab %in% app_tabs$id[app_tabs$kind == "method"] || region_changed) {
    return(region)
  }
  if (tab == "live" && !identical(last_target, region)) {
    return(region)
  }
  NULL
}

# Keep the current region if the method accepts it, else fall back to Europe.
default_method_region <- function(current, method) {
  if (current %in% method_regions(method)) current else "europe"
}
