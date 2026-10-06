# Skeleton tabs for the demo. Each shows the real parameter controls from the
# design spec with Run disabled, a card describing the method, and an owner
# line for splitting the work. UI only: there is no server logic yet.

disabled_run_button <- function(id) {
  tagAppendAttributes(
    actionButton(id, "Run analysis", icon = icon("play"), class = "btn-primary w-100"),
    disabled = "disabled"
  )
}

# Shared layout: parameters on the left, method + planned outputs on the right.
method_tab_ui <- function(id, chapter, summary, controls, outputs, owner = "TBD") {
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

alpha_input <- function(ns) {
  selectInput(ns("alpha"), "Significance level (alpha)", c(0.10, 0.05, 0.01), selected = 0.05)
}

routes_ui <- function(id) {
  method_tab_ui(
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

autocorr_ui <- function(id) {
  method_tab_ui(
    id,
    chapter = "Ch 4",
    summary = tagList(
      p(
        strong("Spatial autocorrelation."),
        " Counts aircraft in a hexagonal grid over the region and tests whether ",
        "neighbouring hexes have similar values (global Moran's I, Geary's C or ",
        "Global G), then maps local clusters with Local Moran's I (LISA)."
      )
    ),
    controls = function(ns) {
      tagList(
        sliderInput(ns("hex_km"), "Hex size (km)", min = 50, max = 500, value = 150, step = 25),
        checkboxInput(ns("log"), "Use log(count + 1)", value = TRUE),
        selectInput(
          ns("weights"),
          "Spatial weights",
          c(
            "Queen contiguity" = "queen",
            "K nearest neighbours" = "knn",
            "Distance band" = "dist",
            "Inverse distance" = "idw"
          )
        ),
        conditionalPanel(
          "input.weights == 'knn'",
          ns = ns,
          numericInput(ns("k"), "k", value = 6, min = 1, max = 20)
        ),
        conditionalPanel(
          "input.weights == 'dist' || input.weights == 'idw'",
          ns = ns,
          numericInput(ns("d"), "Distance band d (km)", value = 300, min = 50)
        ),
        radioButtons(
          ns("style"),
          "Weights style",
          c("W (row-standardised)" = "W", "B (binary)" = "B"),
          inline = TRUE
        ),
        selectInput(
          ns("statistic"),
          "Global statistic",
          c("Moran's I" = "moran", "Geary's C" = "geary", "Global G" = "globalg")
        ),
        radioButtons(
          ns("inference"),
          "Inference",
          c("Analytic" = "analytic", "Permutation" = "perm"),
          inline = TRUE
        ),
        conditionalPanel(
          "input.inference == 'perm'",
          ns = ns,
          numericInput(ns("nsim"), "Simulations", value = 499, min = 99, max = 999, step = 100)
        ),
        alpha_input(ns)
      )
    },
    outputs = list(
      "Global test table: statistic, expectation, variance, z, p-value",
      "Moran scatterplot",
      "LISA cluster map (HH, LL, HL, LH, not significant)",
      "Local Moran's I table for the top hexes",
      "Plain-English interpretation at the chosen alpha"
    )
  )
}

quadrat_ui <- function(id) {
  method_tab_ui(
    id,
    chapter = "Ch 7",
    summary = p(
      strong("Quadrat test for complete spatial randomness (CSR)."),
      " Splits the region into an nx by ny grid of quadrats, counts points in each, ",
      "and tests the counts against a Poisson process with the chi-squared test and ",
      "the variance-to-mean ratio (VTMR: < 1 regular, about 1 random, > 1 clustered)."
    ),
    controls = function(ns) {
      tagList(
        radioButtons(
          ns("points"),
          "Point set",
          c("Airborne aircraft" = "aircraft", "Airports" = "airports")
        ),
        conditionalPanel(
          "input.points == 'airports'",
          ns = ns,
          checkboxGroupInput(
            ns("airport_types"),
            "Airport types",
            c("Large" = "large_airport", "Medium" = "medium_airport"),
            selected = c("large_airport", "medium_airport")
          )
        ),
        sliderInput(ns("nx"), "Quadrats across (nx)", min = 2, max = 15, value = 6),
        sliderInput(ns("ny"), "Quadrats down (ny)", min = 2, max = 15, value = 6),
        alpha_input(ns)
      )
    },
    outputs = list(
      "Quadrat count map with the points overlaid",
      "Chi-squared test: statistic, df, p-value",
      "VTMR and the (m - 1) x VTMR statistic against chi-squared(m - 1)",
      "Histogram of quadrat counts against the Poisson expectation",
      "Plain-English interpretation at the chosen alpha"
    )
  )
}

regression_ui <- function(id) {
  method_tab_ui(
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
        tags$li(strong("Planned:"), " OurAirports, OpenFlights airlines, the OpenSky aircraft database, and ", code("spData::world"), ".")
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
        tags$li("Airline codes come from the first three characters of the callsign. Private and military flights have no code."),
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
