# STAT3037A Global Flights dashboard (demo).
# Files in R/ are sourced automatically by Shiny before this file runs.

library(shiny)
library(bslib)
library(bsicons)
library(leaflet)

poll_ms <- 10 * 60 * 1000
airlines <- load_airlines()

theme <- bs_theme(
  version = 5,
  primary = "#1d3557",
  secondary = "#457b9d",
  "navbar-bg" = "#1d3557"
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
    "Live data refreshes every 10 minutes. Filters apply to the Live Map in this demo."
  )
)

ui <- page_navbar(
  title = tagList(bs_icon("airplane-engines"), "Global Flights"),
  window_title = "Global Flights",
  theme = theme,
  sidebar = sidebar_filters,
  fillable = "Live Map",
  nav_panel("Live Map", icon = bs_icon("map"), mod_live_ui("live")),
  nav_panel("Airports & Routes", icon = bs_icon("signpost-split"), routes_ui("routes")),
  nav_panel("Autocorrelation", icon = bs_icon("grid-3x3"), autocorr_ui("autocorr")),
  nav_panel("Point Patterns", icon = bs_icon("dot"), quadrat_ui("quadrat")),
  nav_panel("Spatial Regression", icon = bs_icon("graph-up"), regression_ui("regression")),
  nav_panel("About", icon = bs_icon("info-circle"), about_ui("about")),
  nav_spacer(),
  nav_item(uiOutput("source_badge"))
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
