# Skeleton tabs for the tabs not built yet. Each shows the real parameter
# controls from the design spec with Run disabled, a card describing the
# method, and an owner line. UI only: there is no server logic. Each tab's
# function is deleted here once its real module exists (see docs/plan.md).
# method_tab_ui() and alpha_input() for the real tabs are in R/mod_common.R.

disabled_run_button <- function(id) {
  tagAppendAttributes(
    actionButton(id, "Run analysis", icon = icon("play"), class = "btn-primary w-100"),
    disabled = "disabled"
  )
}

# Placeholder layout: parameters on the left, method + planned outputs on the right.
placeholder_tab_ui <- function(id, chapter, summary, controls, outputs, owner = "TBD") {
  ns <- NS(id)
  layout_columns(
    col_widths = c(4, 8),
    card(
      card_header("Parameters"),
      controls(ns),
      disabled_run_button(ns("run")),
      p(class = "text-muted small mt-2 mb-0", "Coming soon: not wired up in the demo.")
    ),
    layout_columns(
      col_widths = 12,
      fill = FALSE,
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span("Method"),
          span(class = "badge text-bg-info", chapter)
        ),
        summary,
        p(class = "text-muted small mb-0", bs_icon("person"), " Owner: ", owner)
      ),
      card(
        card_header("Planned outputs"),
        tags$ul(class = "mb-0", lapply(outputs, tags$li))
      )
    )
  )
}

routes_ui <- function(id) {
  placeholder_tab_ui(
    id,
    chapter = "Descriptive",
    summary = p(
      "Busiest departure airports and the most-flown routes from yesterday's flights ",
      "(OpenSky ", code("/flights/all"), "), drawn as great-circle lines. ",
      "This is a descriptive view, not one of the three methods."
    ),
    controls = function(ns) {
      tagList(
        radioButtons(ns("view"), "Show", c("Top routes", "Busiest departure airports")),
        sliderInput(ns("top_n"), "Top N", min = 5, max = 50, value = 20, step = 5),
        checkboxInput(ns("domestic"), "Include domestic routes", value = TRUE)
      )
    },
    outputs = list(
      "Map of routes as great-circle lines, width by number of flights",
      "Table of routes or airports with flight counts"
    )
  )
}

regression_ui <- function(id) {
  placeholder_tab_ui(
    id,
    chapter = "Ch 6",
    summary = p(
      strong("Spatial lag regression."),
      " Models air traffic per country from population, GDP per capita, area and ",
      "airport count. Follows the course workflow: OLS, Moran's I on the residuals, ",
      "LM tests to choose a model, then a spatial lag model (lagsarlm)."
    ),
    controls = function(ns) {
      tagList(
        radioButtons(
          ns("response"),
          "Response",
          c(
            "Flights departing yesterday" = "departures",
            "Aircraft over the country now" = "present"
          )
        ),
        checkboxInput(ns("log_y"), "Use log(1 + y)", value = TRUE),
        checkboxGroupInput(
          ns("covariates"),
          "Covariates",
          c(
            "Population" = "pop",
            "GDP per capita" = "gdpPercap",
            "Area" = "area_km2",
            "Airport count" = "airports"
          ),
          selected = c("pop", "gdpPercap")
        ),
        radioButtons(
          ns("weights"),
          "Spatial weights",
          c("Queen contiguity" = "queen", "K nearest neighbours" = "knn"),
          inline = TRUE
        ),
        conditionalPanel(
          "input.weights == 'knn'",
          ns = ns,
          numericInput(ns("k"), "k", value = 4, min = 1, max = 10)
        ),
        alpha_input(ns)
      )
    },
    outputs = list(
      "1. OLS summary",
      "2. Moran's I on the OLS residuals",
      "3. LM tests (LMerr, LMlag, RLMerr, RLMlag) and a recommended model",
      "4. Spatial lag model: rho, coefficients, AIC against OLS",
      "5. Map of the residuals"
    )
  )
}

about_ui <- function(id) {
  layout_columns(
    col_widths = c(6, 6),
    card(
      card_header("Data sources"),
      tags$ul(
        tags$li(
          strong("OpenSky Network REST API"),
          " (", code("/states/all"), "): live aircraft positions, refreshed every 10 minutes ",
          "and shared across all users of the app."
        ),
        tags$li(
          strong("Bundled sample snapshot"),
          " (", code("data/sample/states_sample.rds"), "): used when there are no API ",
          "credentials or the API is unavailable, so the app always runs."
        ),
        tags$li(
          strong("Airline names"),
          " (", code("data/lookups/airlines.rds"), "): OpenFlights airlines, matched on the ICAO code, ",
          "plus a few newer airlines added by hand."
        ),
        tags$li(strong("Planned:"), " OurAirports, the OpenSky aircraft database, and ", code("spData::world"), ".")
      ),
      p(
        class = "small text-muted mb-0",
        "Data courtesy of The OpenSky Network, https://opensky-network.org."
      )
    ),
    card(
      card_header("Limitations"),
      tags$ul(
        tags$li("Coverage depends on volunteer ADS-B receivers, so it is dense over North America and Europe and sparse over oceans, Africa and parts of Asia."),
        tags$li("Each analysis uses a single snapshot; the API only serves the last hour of positions."),
        tags$li("Airline codes come from the first three characters of the callsign. Private and military flights have no code, and OpenFlights has no name for some newer airlines."),
        tags$li("Categories are inferred from the callsign, airline and transponder address. Military flights with tactical callsigns are only caught inside the US military address block, and airlines that fly both passengers and freight count as passenger airlines."),
        tags$li("Origin country is the country of aircraft registration, not where the flight departed.")
      )
    ),
    card(
      card_header("Methods (from the STAT3037A course notes)"),
      tags$ol(
        class = "mb-0",
        tags$li(strong("Ch 4: Spatial autocorrelation"), " (Moran's I, Geary's C, Global G, LISA) on a hex grid of aircraft counts."),
        tags$li(strong("Ch 7: Quadrat test for CSR"), " with the variance-to-mean ratio, on aircraft or airport points."),
        tags$li(strong("Ch 6: Spatial lag regression"), " of air traffic per country, following OLS, residual Moran's I, LM tests, lagsarlm.")
      )
    ),
    card(
      card_header("About this demo"),
      p(
        "STAT3037A Introduction to Spatial Statistics (Wits) group project. ",
        "This demo has a working Live Map; the method tabs show their planned controls ",
        "and outputs and will be built out next."
      ),
      p(class = "mb-0", "Sidebar filters currently apply to the Live Map only.")
    )
  )
}
