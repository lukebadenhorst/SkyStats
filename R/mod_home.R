# Home tab: the hero over a soft haze (the planes glide behind it), the live
# aircraft count, four shortcut cards, and the six-step "How this app works"
# tour that opens the class presentation. www/tour.js drives the tour in the
# browser from the JSON in #tour-data; each step moves the shared map.
#
# home_server() takes two reactives from app.R:
#   aircraft       prepped state vectors with the category/band filters but
#                  not the region (the hero count is the world total)
#   tour_aircraft  prepped state vectors with no filter at all, so the tour
#                  shows the same thing whatever the sidebar is set to
# On a tour start it runs the autocorrelation on Europe (until it has
# succeeded once) and draws the LISA hexes into the "tour" pane, which
# step 4 shows.

# The tour text, in speaking order. Placeholder wording (from the approved
# mockup): Luke rewrites it, so it all lives here. Each step: a headline
# (title), two or three short points (simple HTML such as <b> is allowed),
# and the map action www/tour.js runs for it.
tour_steps <- list(
  list(
    title = "Live positions of every aircraft OpenSky can hear.",
    points = c(
      "Each plane is one ADS-B signal picked up by a worldwide network of volunteer receivers.",
      "Airlines come from the callsign; airports from OurAirports; countries from spData."
    ),
    action = "world"
  ),
  list(
    title = "A fresh snapshot every 10 minutes, shared by everyone.",
    points = c(
      "That keeps us well inside OpenSky's free daily limit.",
      "No connection? The app falls back to a saved snapshot, and the badge always says which one you see."
    ),
    action = "badge"
  ),
  list(
    title = "From raw signal to a statistical test in five steps.",
    points = c(
      "Each region uses its own equal-area projection, so areas and distances are comparable.",
      "Change a filter or a setting and the analysis runs again by itself."
    ),
    action = "pipeline"
  ),
  list(
    title = "Three methods from the course notes.",
    points = c(
      "<b>Autocorrelation (Ch 4):</b> do busy hexes sit next to busy hexes?",
      "<b>Point Patterns (Ch 7):</b> are aircraft spread at random?",
      "<b>Regression (Ch 6):</b> what explains traffic per country?"
    ),
    action = "lisa"
  ),
  list(
    title = "Pick a region; each gets its own projection.",
    points = c(
      "Europe, North America, Southern Africa and East Asia.",
      "Regression also runs on the whole world, by country."
    ),
    action = "regions"
  ),
  list(
    title = "Empty sky can mean no receivers, not no aircraft.",
    points = c(
      "Coverage is dense over Europe and North America, thin over Africa and the oceans.",
      "A snapshot is one moment, not a full day of traffic."
    ),
    action = "coverage"
  )
)

# The shortcut cards: the tab each opens, its chapter tag and a blurb.
home_cards <- list(
  list(tab = "live", tag = "Live", title = "Live Map", text = "Every aircraft OpenSky is tracking right now."),
  list(tab = "autocorr", tag = "Ch 4", title = "Autocorrelation", text = "Is air traffic clustered? Moran's I and LISA."),
  list(tab = "quadrat", tag = "Ch 7", title = "Point Patterns", text = "Random, clustered or regular? Quadrats and VTMR."),
  list(tab = "regression", tag = "Ch 6", title = "Regression", text = "What explains traffic per country? OLS to spatial lag.")
)

# The regions step 5 visits (the ones with an equal-area CRS), with their
# bounds as Leaflet wants them: [[south, west], [north, east]].
tour_regions <- function() {
  r <- regions[!is.na(regions$crs), , drop = FALSE]
  lapply(seq_len(nrow(r)), function(i) {
    list(
      id = r$id[i],
      label = r$label[i],
      crs = r$crs[i],
      bounds = list(c(r$lat_min[i], r$lon_min[i]), c(r$lat_max[i], r$lon_max[i]))
    )
  })
}

home_ui <- function(id) {
  ns <- NS(id)
  tour_json <- jsonlite::toJSON(list(steps = tour_steps, regions = tour_regions()), auto_unbox = TRUE)
  tagList(
    div(class = "home-haze"),
    div(
      class = "home-hero",
      h1("Global Flights"),
      p(
        class = "hero-text",
        "Right now ",
        tagAppendAttributes(textOutput(ns("count"), inline = TRUE), class = "count-up hero-count"),
        " aircraft are in the sky. This app maps them live from the OpenSky Network and tests their pattern with three spatial statistics methods from STAT3037A."
      ),
      div(
        class = "hero-btns",
        actionButton(ns("tour_start"), "How this app works", class = "btn-dark tour-start"),
        tags$button(type = "button", class = "btn btn-hero-light", `data-tab` = "live", "Open the live map")
      ),
      div(
        class = "shortcuts",
        lapply(home_cards, function(card) {
          # no-enter: the cards have their own staggered entrance (app.css).
          tags$button(
            type = "button",
            class = "float-panel shortcut no-enter",
            `data-tab` = card$tab,
            span(class = "shortcut-tag", card$tag),
            span(class = "shortcut-title", card$title),
            span(class = "shortcut-text", card$text)
          )
        })
      )
    ),
    # Filled in by www/tour.js.
    float_panel(
      class = "tour-card no-enter",
      div(class = "tour-body", `aria-live` = "polite"),
      div(
        class = "tour-foot",
        div(class = "tour-dots"),
        div(
          class = "tour-nav",
          tags$button(type = "button", class = "btn btn-tour btn-hero-light tour-prev", "Back"),
          tags$button(type = "button", class = "btn btn-tour btn-dark tour-next", "Next")
        )
      )
    ),
    # HTML(): a JSON script must not be entity-escaped (jsonlite already
    # writes "</" as "<\/", so the text cannot close the tag).
    tags$script(type = "application/json", id = "tour-data", HTML(tour_json))
  )
}

# The tour's LISA hexes: the Autocorrelation tab's defaults (150 km hexes,
# log, queen, W, Moran's I, analytic, alpha = 0.05) on Europe.
tour_lisa <- function(aircraft) {
  pts <- to_region_sf(aircraft, "europe")
  hexes <- hex_counts(pts, region_window("europe"), 150, log = TRUE)
  res <- run_autocorr(hexes, weights = "queen", style = "W", statistic = "moran", inference = "analytic", alpha = 0.05)
  res$lisa
}

home_server <- function(id, aircraft, tour_aircraft = aircraft) {
  moduleServer(id, function(input, output, session) {
    output$count <- renderText(format(nrow(aircraft()), big.mark = ","))

    # The tour pane starts hidden (www/tour.js shows it on step 4). Sent at
    # the start, not with the run: a presenter who reaches step 4 before the
    # run ends would otherwise have the pane hidden again under them.
    set_pane(session, "tour", "hidden")

    # On each tour start until the hexes are drawn: a failed run draws
    # nothing and the next start tries again. If the hexes arrive while
    # step 4 is on screen, they simply appear.
    tour_drawn <- reactiveVal(FALSE)
    observeEvent(input$tour_start, {
      if (tour_drawn()) {
        return()
      }
      res <- run_safely(tour_lisa(tour_aircraft()))
      if (!isTRUE(res$ok)) {
        return()
      }
      tour_drawn(TRUE)
      lisa <- sf::st_transform(res$value, 4326)
      pal <- leaflet::colorFactor(unname(lisa_colours), levels = names(lisa_colours))
      popup <- paste0(
        "<b>Hex ", lisa$hex_id, "</b>",
        "<br>Aircraft: ", lisa$count,
        "<br>Local I: ", sprintf("%.3f", lisa$Ii),
        "<br>p-value: ", format_p(lisa$p_value),
        "<br>Cluster: ", lisa$cluster
      )
      leaflet::addPolygons(
        leaflet::clearGroup(shared_map_proxy(session), "tour"),
        data = lisa,
        fillColor = ~ pal(cluster),
        fillOpacity = 0.7,
        color = "#ffffff",
        weight = 0.5,
        popup = popup,
        group = "tour",
        options = leaflet::pathOptions(pane = "tour")
      )
    })
  })
}
