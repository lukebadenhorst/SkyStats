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

# Keep the current region if the method accepts it, else fall back to Europe.
default_method_region <- function(current, method) {
  if (current %in% method_regions(method)) current else "europe"
}
