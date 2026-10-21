# Spatial Regression tab (Ch 6): aircraft over each country explained by
# country covariates, following the course workflow (OLS, residual Moran's
# I, LM tests, spatial lag model). The statistics are in
# R/stats_regression.R.
#
# regression_server() takes from app.R:
#   aircraft  reactive: prepped + filtered state vectors
#   region_id reactive: the selected region (Europe or World only)
#   airports  data.frame with iso_country (not reactive; see load_airports())

regression_ui <- function(id) {
  ns <- NS(id)
  method_tab_ui(
    id,
    chapter = "Ch 6",
    summary = p(
      strong("Spatial regression."),
      " Models the number of aircraft over each country from population, GDP per capita, ",
      "area and airport count. Follows the course workflow: (1) OLS, (2) Moran's I on the ",
      "OLS residuals, (3) LM tests to choose a model, (4) a spatial lag model (lagsarlm) ",
      "compared with OLS by AIC. Available for Europe and the World only, which have at ",
      "least 15 countries."
    ),
    controls = function(ns) {
      tagList(
        p(
          class = "small mb-1",
          strong("Response: "), "aircraft over the country now. ",
          span(class = "text-muted", "The sidebar filters apply.")
        ),
        checkboxInput(ns("log_y"), "Use log(1 + y)", value = TRUE),
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
    # As in the other method tabs, the result cards are fixed and only shown
    # after a successful run, so the leaflet map sizes itself properly.
    results = div(
      uiOutput(ns("status")),
      conditionalPanel(
        "output.ok",
        ns = ns,
        card(
          card_header("Interpretation"),
          uiOutput(ns("interpretation")),
          uiOutput(ns("isolates"))
        ),
        card(
          card_header("1. OLS regression"),
          tableOutput(ns("ols")),
          uiOutput(ns("ols_note"))
        ),
        layout_columns(
          col_widths = c(6, 6),
          card(card_header("2. Moran's I of the OLS residuals"), tableOutput(ns("moran"))),
          card(
            card_header(
              class = "d-flex justify-content-between align-items-center",
              span("3. LM tests"),
              uiOutput(ns("badge"), inline = TRUE)
            ),
            tableOutput(ns("lm_tests"))
          )
        ),
        card(
          card_header("4. Spatial lag model"),
          tableOutput(ns("lag")),
          uiOutput(ns("rho")),
          tableOutput(ns("aic")),
          uiOutput(ns("lag_note"))
        ),
        card(
          full_screen = TRUE,
          card_header("5. Residual map"),
          radioButtons(
            ns("resid"),
            NULL,
            c("OLS residuals" = "ols_resid", "Spatial lag residuals" = "lag_resid"),
            inline = TRUE
          ),
          leaflet::leafletOutput(ns("map"), height = "480px")
        )
      )
    )
  )
}

regression_server <- function(id, aircraft, region_id, airports) {
  moduleServer(id, function(input, output, session) {
    result <- reactive({
      withProgress(message = "Running the regression...", {
        run_safely({
          formula <- regression_formula(input$covariates, log_y = isTRUE(input$log_y))
          units <- country_units(region_id(), aircraft(), airports)
          k <- if (is.null(input$k) || is.na(input$k)) 4 else input$k
          res <- run_regression(units, formula, weights = input$weights, k = k, alpha = as.numeric(input$alpha))
          res$formula <- formula
          res$n_units <- nrow(units)
          res$weights_type <- input$weights
          res
        })
      })
    }) |>
      bindEvent(input$run)

    ok_result <- reactive({
      res <- result()
      req(isTRUE(res$ok))
      res$value
    })

    # Drives the conditionalPanel in the UI, so it must update while hidden.
    output$ok <- reactive(isTRUE(result()$ok))
    outputOptions(output, "ok", suspendWhenHidden = FALSE)

    output$status <- renderUI({
      if (is.null(input$run) || input$run == 0) {
        return(card(p(class = "text-muted mb-0", "Choose the parameters and click Run analysis.")))
      }
      result_alert(result())
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
        class = "small text-muted mb-0",
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
        class = "small text-muted mb-0",
        "The LM tests point to a spatial error model, which this app does not fit. ",
        "The spatial lag model is step 4 of the course workflow, so it is shown for comparison with OLS."
      )
    })

    output$map <- leaflet::renderLeaflet({
      res <- ok_result()
      units <- sf::st_transform(res$residuals, 4326)
      values <- units[[input$resid]]
      # Eight equal bins centred on 0 (RdBu has at most 11 colours), up to a
      # rounded top so the legend reads cleanly.
      m <- max(abs(values), 1e-9)
      mag <- 10^floor(log10(m))
      top <- ceiling(m / mag * 2) / 2 * mag
      bins <- seq(-top, top, length.out = 9)
      pal <- leaflet::colorBin("RdBu", domain = c(-top, top), bins = bins, reverse = TRUE)
      label <- paste0(units$name_long, ": ", sprintf("%.3f", values), " (", units$aircraft, " aircraft)")
      title <- if (input$resid == "ols_resid") "OLS residual" else "Lag residual"

      leaflet::leaflet(units) |>
        leaflet::addProviderTiles(leaflet::providers$Esri.WorldGrayCanvas) |>
        leaflet::addPolygons(
          fillColor = pal(values),
          fillOpacity = 0.75,
          color = "#ffffff",
          weight = 1,
          label = label
        ) |>
        leaflet::addLegend(position = "bottomright", pal = pal, values = values, title = title, opacity = 1)
    })
  })
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
