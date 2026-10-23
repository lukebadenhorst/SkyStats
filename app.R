# STAT3037A Global Flights dashboard.
# Files in R/ are sourced automatically by Shiny before this file runs.
#
# Layout: one full-screen Leaflet map (R/map_shared.R) behind floating panels:
# the top bar (brand, tab bar, data badge, refresh, dark mode), the left
# column (filters, then each tab's settings) and each tab's content. The look
# and the client-side behaviour live in www/app.css and www/app.js.

library(shiny)
library(bslib)
library(bsicons)
library(leaflet)

poll_ms <- 10 * 60 * 1000
airlines <- load_airlines()
airports <- load_airports()

method_tab_ids <- app_tabs$id[app_tabs$kind == "method"]

theme <- bs_theme(
  version = 5,
  primary = "#1c2430",
  base_font = font_google("Inter", local = FALSE),
  "border-radius" = "8px"
)

top_bar <- div(
  class = "top-bar",
  float_panel(
    class = "brand enter",
    bs_icon("airplane-fill", class = "brand-icon"),
    span(class = "brand-name", "Global Flights")
  ),
  float_panel(
    class = "tab-bar enter",
    span(class = "tab-slider"),
    lapply(seq_len(nrow(app_tabs)), function(i) {
      tags$button(
        type = "button",
        class = "tab-btn",
        `data-tab` = app_tabs$id[i],
        app_tabs$label[i]
      )
    })
  ),
  div(
    class = "top-right",
    uiOutput("source_badge", class = "enter"),
    float_panel(
      class = "icon-panel enter",
      tooltip(
        actionButton(
          "refresh",
          label = NULL,
          icon = bs_icon("arrow-clockwise"),
          class = "icon-btn",
          `aria-label` = "Refresh data"
        ),
        "Refresh data",
        placement = "bottom"
      )
    ),
    # Opens in light mode (clearer on a projector); the switch flips it.
    float_panel(class = "icon-panel enter", input_dark_mode(id = "dark_mode", mode = "light"))
  )
)

filters_panel <- fold_panel(
  "Filters",
  selectInput("region", "Region", region_choices(), selectize = FALSE),
  selectizeInput(
    "airline",
    "Airline",
    choices = NULL,
    multiple = TRUE,
    # The dropdown is attached to <body> so the scrolling left column does
    # not clip it.
    options = list(placeholder = "All (type a name or code)", dropdownParent = "body")
  ),
  div(
    class = "chips",
    checkboxGroupInput(
      "categories",
      "Category",
      choices = category_levels,
      selected = category_levels
    )
  ),
  div(
    class = "chips",
    checkboxGroupInput(
      "bands",
      "Altitude band",
      choices = altitude_levels,
      selected = altitude_levels
    )
  ),
  input_switch("airborne_only", "Airborne only", value = FALSE),
  p(
    class = "panel-note",
    "Live data refreshes every 10 minutes. Filters apply to every tab; airport points ignore the airline, category and altitude filters."
  )
)

# Each tab's settings panel goes here (method tabs, from Task 4 on: the
# module's settings_panel(), which doubles as the setup box).
settings_panes <- lapply(app_tabs$id, function(id) nav_panel_hidden(value = id))

left_col <- div(
  class = "left-col",
  filters_panel,
  do.call(navset_hidden, c(list(id = "settings_nav", selected = "home"), settings_panes))
)

content <- navset_hidden(
  id = "tab",
  selected = "home",
  # Placeholder until the Home page (Task 8).
  nav_panel_hidden("home", float_panel(class = "center-panel home-panel", h1("Global Flights"))),
  nav_panel_hidden("live", mod_live_ui("live")),
  # The method tabs keep their old layout for now, in a scrolling panel.
  nav_panel_hidden("autocorr", float_panel(class = "legacy-panel", autocorr_ui("autocorr"))),
  nav_panel_hidden("quadrat", float_panel(class = "legacy-panel", quadrat_ui("quadrat"))),
  nav_panel_hidden("regression", float_panel(class = "legacy-panel", regression_ui("regression"))),
  nav_panel_hidden("about", about_ui("about"))
)

ui <- page(
  title = "Global Flights",
  theme = theme,
  tags$head(
    tags$link(rel = "stylesheet", href = "app.css"),
    tags$script(src = "app.js")
  ),
  div(id = "map-wrap", leafletOutput("map", height = "100%")),
  top_bar,
  left_col,
  content
)

server <- function(input, output, session) {
  output$map <- renderLeaflet(shared_map())

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

  # Tabs. Any element with data-tab="<id>" sends tab_click (www/app.js).
  # Modules get active = reactive(active_tab() == "<id>") from later tasks on.
  active_tab <- reactiveVal("home")

  observeEvent(input$tab_click, {
    id <- input$tab_click
    req(id %in% app_tabs$id)
    nav_select("tab", id)
    nav_select("settings_nav", id)
    active_tab(id)
    session$sendCustomMessage("tab-changed", list(tab = id))
  })

  # A region button in a method tab's "region refused" message
  # (region_alert(), www/app.js) sets the shared region filter.
  observeEvent(input$region_pick, {
    req(input$region_pick %in% regions$id)
    updateSelectInput(session, "region", selected = input$region_pick)
  })

  # The planes and their altitude legend show on Home and the Live Map only.
  observe({
    planes_on <- active_tab() %in% c("home", "live")
    set_pane(session, "planes", if (planes_on) "shown" else "hidden")
    proxy <- shared_map_proxy(session)
    if (planes_on) {
      addLegend(
        proxy,
        position = "bottomright",
        colors = unname(altitude_colours),
        labels = names(altitude_colours),
        title = "Altitude",
        opacity = 1,
        layerId = "altitude-legend"
      )
    } else {
      removeControl(proxy, "altitude-legend")
    }
  })

  # Glide to the region when it changes, or when a method tab opens.
  last_region <- NULL
  observeEvent(list(input$region, active_tab()), {
    req(input$region)
    region_changed <- !identical(input$region, last_region)
    last_region <<- input$region
    if (region_changed || active_tab() %in% method_tab_ids) {
      fly_to_region(shared_map_proxy(session), input$region)
    }
  })

  mod_live_server("live", aircraft = aircraft)
  autocorr_server("autocorr", aircraft = aircraft, region_id = reactive(input$region))
  quadrat_server("quadrat", aircraft = aircraft, region_id = reactive(input$region), airports = airports)
  regression_server("regression", aircraft = aircraft, region_id = reactive(input$region), airports = airports)

  output$source_badge <- renderUI({
    s <- req(snapshot())
    when <- format(s$time, "%H:%M UTC")
    # The time is a separate span so narrow screens can hide it; the tooltip
    # always has the full text.
    badge <- function(class, icon, label, time, title = NULL) {
      float_panel(
        class = paste("source-badge", class),
        title = paste0(c(paste0(label, time), title), collapse = ". "),
        icon,
        span(
          class = "badge-text",
          span(class = "badge-label", label, .noWS = "outside"),
          span(class = "badge-time", time, .noWS = "outside")
        )
      )
    }
    switch(
      s$source,
      live = badge("badge-live", span(class = "live-dot"), "Live", paste(", updated", when)),
      cache = badge("badge-cache", bs_icon("clock-history"), "Cached", paste(", from", when), s$message),
      sample = badge(
        "badge-sample",
        bs_icon("archive"),
        "Sample snapshot",
        paste(",", format(s$time, "%d %b %Y %H:%M UTC")),
        s$message
      )
    )
  })
}

shinyApp(ui, server)
