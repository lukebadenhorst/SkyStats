# STAT3037A Global Flights dashboard.
# Files in R/ are sourced automatically by Shiny before this file runs.

library(shiny)
library(bslib)
library(bsicons)
library(leaflet)

poll_ms <- 10 * 60 * 1000
airlines <- load_airlines()
airports <- load_airports()

theme <- bs_theme(
  version = 5,
  primary = "#1d3557",
  secondary = "#457b9d",
  "navbar-bg" = "#1d3557"
)

# Dark mode (the sun/moon switch in the navbar). Bootstrap themes the page;
# these rules handle the Leaflet maps. Inverting the light basemap tiles gives
# a dark basemap without loading a second tile set.
theme <- bs_add_rules(
  theme,
  '/* The switch defaults to dark grey; make it white on the navy navbar. */
  bslib-input-dark-mode {
    --text-1-light: #ffffff;
    --text-2-light: rgba(255, 255, 255, 0.85);
  }
  [data-bs-theme="dark"] {
    .leaflet-container { background: #1a1a1a; }
    .leaflet-tile-pane { filter: invert(1) hue-rotate(180deg) brightness(0.9); }
    .leaflet-bar a, .info.legend, .leaflet-popup-content-wrapper, .leaflet-popup-tip {
      background: var(--bs-body-bg);
      color: var(--bs-body-color);
    }
    .study-window { stroke: #a8dadc; }
  }'
)

sidebar_filters <- sidebar(
  title = "Filters",
  width = 280,
  selectInput("region", "Region", region_choices()),
  selectizeInput(
    "airline",
    "Airline",
    choices = NULL,
    multiple = TRUE,
    options = list(placeholder = "All (type a name or code)")
  ),
  checkboxGroupInput(
    "categories",
    "Category",
    choices = category_levels,
    selected = category_levels
  ),
  checkboxGroupInput(
    "bands",
    "Altitude band",
    choices = altitude_levels,
    selected = altitude_levels
  ),
  input_switch("airborne_only", "Airborne only", value = FALSE),
  hr(),
  actionButton("refresh", "Refresh data", icon = icon("rotate"), class = "btn-outline-primary"),
  p(
    class = "small text-muted",
    "Live data refreshes every 10 minutes. Filters apply to every tab; airport points ignore the airline, category and altitude filters."
  )
)

ui <- page_navbar(
  title = tagList(bs_icon("airplane-engines"), "Global Flights"),
  window_title = "Global Flights",
  theme = theme,
  sidebar = sidebar_filters,
  fillable = "Live Map",
  nav_panel("Live Map", icon = bs_icon("map"), mod_live_ui("live")),
  nav_panel("Autocorrelation", icon = bs_icon("grid-3x3"), autocorr_ui("autocorr")),
  nav_panel("Point Patterns", icon = bs_icon("dot"), quadrat_ui("quadrat")),
  nav_panel("Spatial Regression", icon = bs_icon("graph-up"), regression_ui("regression")),
  nav_panel("About", icon = bs_icon("info-circle"), about_ui("about")),
  nav_spacer(),
  nav_item(uiOutput("source_badge")),
  # Opens in light mode (clearer on a projector); the switch flips it.
  nav_item(input_dark_mode(id = "dark_mode", mode = "light"))
)

server <- function(input, output, session) {
  snapshot <- reactiveVal(NULL)

  # Re-read the shared cache every 10 minutes. get_states() only calls the
  # API when the process-level cache has expired.
  observe({
    invalidateLater(poll_ms)
    snapshot(get_states())
  })

  observeEvent(input$refresh, {
    snapshot(get_states(force = TRUE))
    showNotification("Data refreshed.", type = "message", duration = 3)
  })

  # One toast per session explaining why we are not live.
  warned <- FALSE
  observe({
    s <- req(snapshot())
    if (!warned && !is.null(s$message)) {
      warned <<- TRUE
      showNotification(s$message, type = "warning", duration = 8)
    }
  })

  states <- reactive(prep_states(req(snapshot())$data, airlines))

  # Offer the airlines present in the data by name, most common first.
  # Values stay as ICAO codes, so filtering is unchanged.
  observe({
    updateSelectizeInput(
      session,
      "airline",
      choices = airline_choices(states()),
      selected = isolate(input$airline),
      server = TRUE
    )
  })

  aircraft <- reactive({
    # Unticking every category or altitude band means "show nothing", not
    # "no filter".
    if (length(input$categories) == 0 || length(input$bands) == 0) {
      return(states()[0, ])
    }
    filter_states(
      states(),
      region_id = input$region,
      airlines = input$airline,
      bands = input$bands,
      categories = input$categories,
      airborne_only = input$airborne_only
    )
  })

  mod_live_server("live", aircraft = aircraft, region_id = reactive(input$region))
  autocorr_server("autocorr", aircraft = aircraft, region_id = reactive(input$region))
  quadrat_server("quadrat", aircraft = aircraft, region_id = reactive(input$region), airports = airports)
  regression_server("regression", aircraft = aircraft, region_id = reactive(input$region), airports = airports)

  output$source_badge <- renderUI({
    s <- req(snapshot())
    when <- format(s$time, "%H:%M UTC")
    switch(
      s$source,
      live = span(class = "badge text-bg-success", bs_icon("broadcast"), paste(" Live, updated", when)),
      cache = span(
        class = "badge text-bg-warning",
        title = s$message,
        bs_icon("clock-history"),
        paste(" Cached, from", when)
      ),
      sample = span(
        class = "badge text-bg-secondary",
        title = s$message,
        bs_icon("archive"),
        paste(" Sample snapshot,", format(s$time, "%d %b %Y %H:%M UTC"))
      )
    )
  })
}

shinyApp(ui, server)
