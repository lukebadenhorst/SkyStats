# Spatial Regression tab (Ch 6): aircraft over each country explained by
# country covariates, following the course workflow (OLS, residual Moran's
# I, LM tests, spatial lag model), drawn on the shared map. The statistics
# are in R/stats_regression.R.
#
# Three parts, all with module id "regression" (the method name):
#   regression_settings_ui()  the settings panel, which is also the setup box
#   regression_results_ui()   the results card
#   regression_server()       runs the method and draws the map layer
# regression_server() takes from app.R:
#   aircraft  reactive: prepped + filtered state vectors
#   region_id reactive: the selected region (Europe or World only)
#   airports  data.frame with iso_country (not reactive; see load_airports())
#   active    reactive: TRUE while the tab is open

regression_settings_ui <- function(id) {
  ns <- NS(id)
  settings_panel(
    ns,
    "regression",
    "Spatial Regression",
    "Ch 6",
    question = "What explains how many aircraft are over each country?",
    intro = "We model each country's aircraft count from its population, wealth, size and airports, then check whether neighbouring countries affect each other.",
    fields = tagList(
      setting(
        checkboxInput(ns("log_y"), "Use log(1 + y)", value = TRUE),
        "Aircraft counts are very uneven between countries. Taking logs stops a few busy countries from dominating the model."
      ),
      setting(
        checkboxGroupInput(
          ns("covariates"),
          "Covariates",
          c(
            "Population (log)" = "pop",
            "GDP per capita (log)" = "gdpPercap",
            "Area (log)" = "area_km2",
            "Airport count (log 1 + x)" = "airports"
          ),
          selected = c("pop", "gdpPercap")
        ),
        "The country facts used to explain the aircraft count. Pick at least one."
      ),
      setting(
        segmented_input(
          ns("weights"),
          "Spatial weights",
          c("Queen contiguity" = "queen", "K nearest neighbours" = "knn")
        ),
        "Who counts as a neighbour. Queen: countries that share a border. K nearest: the k closest countries, which also covers islands."
      ),
      conditionalPanel(
        "input.weights == 'knn'",
        ns = ns,
        setting(
          numericInput(ns("k"), "k", value = 4, min = 1, max = 10),
          "How many nearest countries count as neighbours."
        )
      ),
      setting(
        alpha_input(ns),
        "How strong the evidence must be before we call a pattern real. 0.05 means we accept a 5% chance of seeing a pattern that is really just chance."
      )
    )
  )
}

# The full results: the interpretation, then the four steps of the course
# workflow. The residual-type buttons (resid) are in the short card, so they
# show in both states (see regression_server()).
regression_results_ui <- function(id) {
  ns <- NS(id)
  results_card(
    ns,
    full = div(
      class = "results-grid",
      div(
        class = "results-section span-all",
        h5("Interpretation"),
        uiOutput(ns("interpretation")),
        uiOutput(ns("isolates"))
      ),
      div(
        class = "results-section span-all",
        h5("1. OLS regression"),
        tableOutput(ns("ols")),
        uiOutput(ns("ols_note"))
      ),
      div(class = "results-section", h5("2. Moran's I of the OLS residuals"), tableOutput(ns("moran"))),
      div(
        class = "results-section",
        h5("3. LM tests"),
        tableOutput(ns("lm_tests")),
        uiOutput(ns("badge"))
      ),
      div(
        class = "results-section span-all",
        h5("4. Spatial lag model"),
        tableOutput(ns("lag")),
        uiOutput(ns("rho")),
        tableOutput(ns("aic")),
        uiOutput(ns("lag_note"))
      )
    ),
    uses = uses_ui(
      c(
        "Forecasting air travel demand" = "ICAO, IATA and the World Bank model air traffic against population and income in much the same way, to forecast demand and spot countries that are under-connected for their size and wealth.",
        "Overflight spillover (ρ)" = "A positive ρ means a country's traffic depends on its neighbours'. Aircraft over Kazakhstan, Turkey or Sudan are often just passing through, and many such countries charge overflight fees, as Russia does on the Trans-Siberian route.",
        "Reading the residual map" = "Countries with positive residuals get more traffic than their economy and airports predict; these are usually transit corridors or hubs. Negative residuals are connectivity gaps, which the Single African Air Transport Market aims to close.",
        "Why test the residuals first" = "If the OLS residuals are spatially clustered and you keep OLS anyway, a coefficient such as GDP's is biased because it soaks up spillover from neighbours. The Moran's I and LM tests are the standard check."
      ),
      caveat = "A snapshot of aircraft over a country mixes departures, arrivals and overflights, which is why the area covariate matters so much."
    )
  )
}

regression_server <- function(id, aircraft, region_id, airports, active) {
  moduleServer(id, function(input, output, session) {
    # Only inputs and already-computed data: debounce reads this even while
    # the tab is closed, so nothing heavy goes in here. The residual type
    # (resid) is left out on purpose: it only recolours the layer.
    params <- reactive(list(
      aircraft = aircraft(),
      airports = airports,
      log_y = input$log_y,
      covariates = input$covariates,
      weights = input$weights,
      k = input$k,
      alpha = input$alpha
    ))

    result <- method_runner(
      input,
      session,
      "regression",
      active,
      region_id,
      params,
      compute = function(p, region) {
        if (nrow(p$aircraft) == 0) {
          return(no_aircraft_result())
        }
        run_safely({
          formula <- regression_formula(p$covariates, log_y = isTRUE(p$log_y))
          units <- country_units(region, p$aircraft, p$airports)
          k <- if (is.null(p$k) || is.na(p$k)) 4 else p$k
          res <- run_regression(units, formula, weights = p$weights, k = k, alpha = as.numeric(p$alpha))
          res$formula <- formula
          res$n_units <- nrow(units)
          # The card describes the run it shows, not inputs changed since.
          res$weights_type <- p$weights
          res
        })
      }
    )

    # Every output and the map layer start with req(active()), so a closed
    # tab never runs the method.
    ok_result <- reactive({
      req(active())
      res <- result()
      req(isTRUE(res$ok))
      res$value
    })

    # The residual type, defaulting to OLS before the buttons exist.
    resid_type <- reactive(if (is.null(input$resid)) "ols_resid" else input$resid)

    # The one set of residual buttons lives in the short card, above the
    # legend, so it shows whether the card is open or not (one input id can
    # only be in the page once). It keeps its choice when the card is
    # redrawn after a new run: the choice is read with isolate(), so picking
    # a type does not redraw the card (and the button keeps its focus). The
    # legend below it follows the choice.
    output$short <- renderUI({
      req(active())
      res <- result()
      if (!isTRUE(res$ok)) {
        return(region_alert(res, "regression"))
      }
      summary_ui(
        regression_summary(res$value),
        tagList(
          segmented_input(
            session$ns("resid"),
            "Colour the map by",
            c("OLS residuals" = "ols_resid", "Spatial lag residuals" = "lag_resid"),
            selected = isolate(resid_type())
          ),
          uiOutput(session$ns("resid_legend"))
        )
      )
    })

    output$resid_legend <- renderUI({
      scale <- residual_scale(ok_result()$residuals[[resid_type()]])
      legend_ui(
        scale$pal(scale$mids),
        sprintf("%.2f", scale$mids),
        title = if (resid_type() == "ols_resid") "OLS residual (bin centres)" else "Lag residual (bin centres)"
      )
    })

    output$interpretation <- renderUI(p(class = "mb-0", ok_result()$interpretation))

    output$isolates <- renderUI({
      res <- ok_result()
      if (res$weights_type != "queen" || res$n_isolates == 0) {
        return(NULL)
      }
      div(
        class = "alert alert-info mt-2 mb-0",
        res$n_isolates, " countries have no land neighbours. Try K nearest neighbours."
      )
    })

    output$ols <- renderTable(coef_display(ok_result()$ols, "t"), width = "100%")

    output$ols_note <- renderUI({
      res <- ok_result()
      p(
        class = "results-note",
        # One HTML string: separate children render with a space between
        # them, which would put spaces before the full stops.
        HTML(paste0(
          "Model: <code>", htmltools::htmlEscape(deparse(res$formula)), "</code>. ",
          "R² = ", sprintf("%.3f", res$r_squared), ". ",
          res$n, " of the ", res$n_units, " countries in the region have complete data. ",
          "Weights: ", res$weights_label, "."
        ))
      )
    })

    output$moran <- renderTable(
      {
        m <- ok_result()$resid_moran
        data.frame(
          Quantity = c("Moran's I", "E(I)", "Var(I)", "z", "p-value (one-sided)"),
          Value = c(
            sprintf("%.4f", m$observed), sprintf("%.4f", m$expectation), sprintf("%.5f", m$variance),
            sprintf("%.3f", m$z), format_p(m$p_value)
          )
        )
      },
      width = "100%"
    )

    output$lm_tests <- renderTable(
      {
        t <- ok_result()$lm_tests
        data.frame(Test = t$test, Statistic = sprintf("%.3f", t$statistic), `p-value` = format_p(t$p_value), check.names = FALSE)
      },
      width = "100%"
    )

    output$badge <- renderUI({
      rec <- ok_result()$recommendation
      cls <- if (rec == "OLS") "text-bg-secondary" else "text-bg-primary"
      span(class = paste("badge", cls), "Recommended: ", rec)
    })

    output$lag <- renderTable(coef_display(ok_result()$lag, "z"), width = "100%")

    output$rho <- renderUI({
      res <- ok_result()
      p(
        class = "mb-2",
        HTML(paste0(
          "ρ (spatial lag of the response) = <strong>", sprintf("%.3f", res$rho), "</strong>, ",
          "LR test p-value ", htmltools::htmlEscape(format_p(res$rho_p_value)), "."
        ))
      )
    })

    output$aic <- renderTable(
      {
        a <- ok_result()$aic
        data.frame(Model = a$model, AIC = sprintf("%.2f", a$aic))
      },
      width = "100%"
    )

    # The course workflow always fits the lag model, even when the LM tests
    # point to the error model, so say so.
    output$lag_note <- renderUI({
      if (ok_result()$recommendation != "Spatial error") {
        return(NULL)
      }
      p(
        class = "results-note",
        "The LM tests point to a spatial error model, which this app does not fit. ",
        "The spatial lag model is step 4 of the course workflow, so it is shown for comparison with OLS."
      )
    })

    # The residual layer on the shared map. Coming back to the tab with the
    # same result keeps the drawn layer (method_runner shows its pane again).
    # Changing the residual type redraws the layer only.
    drawn <- NULL
    drawn_type <- NULL
    observe({
      req(active())
      res <- result()
      type <- resid_type()
      if (identical(res, drawn) && identical(type, drawn_type)) {
        return()
      }
      drawn <<- res
      drawn_type <<- type
      # A failed run keeps the old layer so method_runner can fade its pane
      # out; the next good run replaces it.
      if (!isTRUE(res$ok)) {
        return()
      }
      units <- sf::st_transform(res$value$residuals, 4326)
      values <- units[[type]]
      scale <- residual_scale(values)
      label <- paste0(units$name_long, ": ", sprintf("%.3f", values), " (", units$aircraft, " aircraft)")
      proxy <- leaflet::clearGroup(shared_map_proxy(session), "regression")
      leaflet::addPolygons(
        proxy,
        data = units,
        fillColor = scale$pal(values),
        fillOpacity = 0.75,
        color = "#ffffff",
        weight = 1,
        label = label,
        group = "regression",
        options = leaflet::pathOptions(pane = "regression")
      )
    })
  })
}

# The residual colour scale: eight equal bins centred on 0 (RdBu has at
# most 11 colours), up to a rounded top so the legend reads cleanly. Returns
# the palette and each bin's centre (for the card's legend).
residual_scale <- function(values) {
  m <- max(abs(values), 1e-9)
  mag <- 10^floor(log10(m))
  top <- ceiling(m / mag * 2) / 2 * mag
  bins <- seq(-top, top, length.out = 9)
  list(
    pal = leaflet::colorBin("RdBu", domain = c(-top, top), bins = bins, reverse = TRUE),
    mids = utils::head(bins, -1) + diff(bins) / 2
  )
}

# Coefficient table for display. stat: "t" (OLS) or "z" (lag model).
coef_display <- function(coefs, stat) {
  out <- data.frame(
    Term = coefs$term,
    Estimate = sprintf("%.4f", coefs$estimate),
    `Std. error` = sprintf("%.4f", coefs$std_error),
    Statistic = sprintf("%.3f", coefs$statistic),
    `p-value` = format_p(coefs$p_value),
    check.names = FALSE
  )
  names(out)[4] <- stat
  out
}
