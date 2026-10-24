# The one full-screen map that every tab draws on. app.R renders it once as
# output$map; modules draw into their own pane through shared_map_proxy() and
# never re-render it. www/app.js fades the panes in and out (set_pane()).
# Uses leaflet:: prefixes because the test helper sources this file without
# attaching leaflet.

# Pane z-indexes: the method layers above the tiles and below the planes.
map_panes <- c(autocorr = 410L, quadrat = 411L, regression = 412L, tour = 413L, planes = 450L)

shared_map <- function() {
  m <- leaflet::leaflet(
    options = leaflet::leafletOptions(
      zoomControl = FALSE,
      worldCopyJump = TRUE,
      zoomSnap = 0.25,
      zoomDelta = 0.5
    )
  ) |>
    leaflet::addProviderTiles(leaflet::providers$Esri.WorldGrayCanvas)
  for (pane in names(map_panes)) {
    m <- leaflet::addMapPane(m, pane, zIndex = map_panes[[pane]])
  }
  m |>
    leaflet::setView(lng = 10, lat = 25, zoom = 2) |>
    # The zoom buttons sit bottom right, clear of the floating panels.
    # gfMapReady (www/app.js) applies any pane states sent before the map existed.
    # Leaflet defers drawing (the panes included) while the map has no size,
    # for example when the page loads in a hidden viewer, so wait for the panes.
    htmlwidgets::onRender(
      "function(el, x) {
        var map = this;
        L.control.zoom({position: 'bottomright'}).addTo(map);
        (function ready() {
          if (!map.getPane('planes')) return setTimeout(ready, 100);
          if (window.gfMapReady) window.gfMapReady(map);
        })();
      }"
    )
}

# A proxy for the shared map that works from inside any module.
shared_map_proxy <- function(session) {
  leaflet::leafletProxy("map", session = session$rootScope())
}

# Show, hide or dim one pane. state: "shown", "hidden" or "busy".
set_pane <- function(session, pane, state = c("shown", "hidden", "busy")) {
  state <- match.arg(state)
  session$sendCustomMessage("map-pane", list(pane = pane, state = state))
}

# Glide the map to a region: the default world view, or the region's bbox.
fly_to_region <- function(proxy, region_id) {
  r <- get_region(region_id)
  if (r$id == "world") {
    leaflet::flyTo(proxy, lng = 10, lat = 25, zoom = 2)
  } else {
    leaflet::flyToBounds(proxy, r$lon_min, r$lat_min, r$lon_max, r$lat_max)
  }
}
