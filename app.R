# STAT3037A Global Flights dashboard (demo).
# Files in R/ are sourced automatically by Shiny before this file runs.

library(shiny)
library(bslib)
library(bsicons)
library(leaflet)

poll_ms <- 10 * 60 * 1000

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
    "Airline code",
    choices = NULL,
    multiple = TRUE,
    options = list(placeholder = "All airlines")
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

  states <- reactive(prep_states(req(snapshot())$data))

  # Offer the airline codes present in the data, most common first.
  observe({
    counts <- airline_counts(states())
    choices <- stats::setNames(
      names(counts),
      paste0(names(counts), " (", as.integer(counts), ")")
    )
    updateSelectizeInput(
      session,
      "airline",
      choices = choices,
      selected = isolate(input$airline),
      server = TRUE
    )
  })

  aircraft <- reactive({
    # Unticking every altitude band means "show nothing", not "no filter".
    if (length(input$bands) == 0) {
      return(states()[0, ])
    }
    filter_states(
      states(),
      region_id = input$region,
      airlines = input$airline,
      bands = input$bands,
      airborne_only = input$airborne_only
    )
  })

  mod_live_server("live", aircraft = aircraft, region_id = reactive(input$region))

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
