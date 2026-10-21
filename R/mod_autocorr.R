# Autocorrelation tab (Ch 4): counts aircraft in a hex grid over the region,
# runs a global test (Moran's I, Geary's C or Global G) and maps the LISA
# clusters. The statistics are in R/stats_autocorr.R.
#
# autocorr_server() takes two reactives from app.R:
#   aircraft  prepped + filtered state vectors
#   region_id the selected region

lisa_colours <- c(
  "High-High" = "#d7191c",
  "Low-Low" = "#2c7bb6",
  "High-Low" = "#fdae61",
  "Low-High" = "#abd9e9",
  "Not significant" = "#eeeeee"
)

autocorr_ui <- function(id) {
  ns <- NS(id)
  method_tab_ui(
    id,
    chapter = "Ch 4",
    summary = p(
      strong("Spatial autocorrelation."),
      " Counts aircraft in a hexagonal grid over the region and tests whether ",
      "neighbouring hexes have similar values (global Moran's I, Geary's C or ",
      "Global G), then maps local clusters with Local Moran's I (LISA)."
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
        selectInput(
          ns("statistic"),
          "Global statistic",
          c("Moran's I" = "moran", "Geary's C" = "geary", "Global G" = "globalg")
        ),
        # Global G needs binary weights, and spdep has no permutation test
        # for it, so those choices are hidden (the server enforces them too).
        conditionalPanel(
          "input.statistic != 'globalg'",
          ns = ns,
          radioButtons(
            ns("style"),
            "Weights style",
            c("W (row-standardised)" = "W", "B (binary)" = "B"),
            inline = TRUE
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
          )
        ),
        conditionalPanel(
          "input.statistic == 'globalg'",
          ns = ns,
          p(class = "small text-muted", "Global G uses binary weights (style B) and the analytic test.")
        ),
        alpha_input(ns)
      )
    },
    # The result cards are fixed and only shown after a successful run (a
    # leaflet map built inside renderUI sizes itself before it is visible).
    results = div(
      uiOutput(ns("status")),
      conditionalPanel(
        "output.ok",
        ns = ns,
        card(card_header("Interpretation"), uiOutput(ns("interpretation"))),
        layout_columns(
          col_widths = c(5, 7),
          card(card_header("Global test"), tableOutput(ns("global")), uiOutput(ns("setup"))),
          card(card_header("Moran scatterplot"), plotOutput(ns("scatter"), height = "320px"))
        ),
        card(
          full_screen = TRUE,
          card_header("LISA cluster map"),
          leaflet::leafletOutput(ns("map"), height = "480px")
        ),
        card(
          card_header("Strongest local clusters (top 10 significant hexes by local I)"),
          tableOutput(ns("top"))
        )
      )
    )
  )
}

autocorr_server <- function(id, aircraft, region_id) {
  moduleServer(id, function(input, output, session) {
    result <- reactive({
      globalg <- input$statistic == "globalg"
      withProgress(message = "Running the autocorrelation analysis...", {
        run_safely({
          region <- region_id()
          pts <- to_region_sf(aircraft(), region)
          hexes <- hex_counts(pts, region_window(region), input$hex_km, log = isTRUE(input$log))
          res <- run_autocorr(
            hexes,
            weights = input$weights,
            k = input$k,
            d_km = input$d,
            style = if (globalg) "B" else input$style,
            statistic = input$statistic,
            inference = if (globalg) "analytic" else input$inference,
            nsim = input$nsim,
            alpha = as.numeric(input$alpha)
          )
          res$hex_km <- input$hex_km
          res$value_label <- if (isTRUE(input$log)) "log(count + 1)" else "Aircraft count"
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

    output$global <- renderTable(
      {
        g <- ok_result()$global
        data.frame(
          Quantity = c(g$statistic, "Expectation under H0", "Variance", "z", "p-value"),
          Value = c(
            sprintf("%.4f", g$observed),
            sprintf("%.4f", g$expectation),
            formatC(g$variance, format = "g", digits = 3),
            sprintf("%.3f", g$z),
            format_p(g$p_value)
          )
        )
      },
      width = "100%"
    )

    output$setup <- renderUI({
      res <- ok_result()
      isolates <- if (res$n_isolates > 0) {
        paste0(res$n_isolates, " hexes have no neighbours.")
      } else {
        "Every hex has at least one neighbour."
      }
      p(
        class = "small text-muted mb-0",
        paste0(
          nrow(res$lisa), " hexes of ", res$hex_km, " km, value = ", res$value_label, ". ",
          "Weights: ", res$weights_label, ". ", isolates
        )
      )
    })

    output$scatter <- renderPlot({
      res <- ok_result()
      s <- res$scatter
      par(mar = c(4.5, 4.5, 1, 1))
      plot(
        s$value, s$lag,
        pch = 21, bg = lisa_colours[as.character(res$lisa$cluster)], col = "#555555",
        xlab = res$value_label, ylab = "Spatially lagged value"
      )
      abline(stats::lm(lag ~ value, data = s), col = "#1d3557", lwd = 2)
      abline(v = mean(s$value), h = mean(s$lag), lty = 2, col = "#888888")
    })

    output$map <- leaflet::renderLeaflet({
      lisa <- sf::st_transform(ok_result()$lisa, 4326)
      pal <- leaflet::colorFactor(unname(lisa_colours), levels = names(lisa_colours))
      popup <- paste0(
        "<b>Hex ", lisa$hex_id, "</b>",
        "<br>Aircraft: ", lisa$count,
        "<br>Local I: ", sprintf("%.3f", lisa$Ii),
        "<br>p-value: ", format_p(lisa$p_value),
        "<br>Cluster: ", lisa$cluster
      )
      leaflet::leaflet(lisa) |>
        leaflet::addProviderTiles(leaflet::providers$Esri.WorldGrayCanvas) |>
        leaflet::addPolygons(
          fillColor = ~ pal(cluster),
          fillOpacity = 0.7,
          color = "#ffffff",
          weight = 0.5,
          popup = popup
        ) |>
        leaflet::addLegend(
          position = "bottomright",
          colors = unname(lisa_colours),
          labels = names(lisa_colours),
          title = "LISA cluster",
          opacity = 1
        )
    })

    output$top <- renderTable(
      {
        lisa <- ok_result()$lisa
        sig <- lisa[lisa$cluster != "Not significant", ]
        sig <- utils::head(sig[order(-sig$Ii), ], 10)
        validate(need(nrow(sig) > 0, "No hex is significant at this alpha."))
        centre <- sf::st_coordinates(sf::st_centroid(sf::st_transform(sf::st_geometry(sig), 4326)))
        data.frame(
          Hex = sig$hex_id,
          `Centre (lat, lon)` = sprintf("%.1f, %.1f", centre[, "Y"], centre[, "X"]),
          Aircraft = sig$count,
          `Local I` = sprintf("%.3f", sig$Ii),
          `p-value` = format_p(sig$p_value),
          Cluster = as.character(sig$cluster),
          check.names = FALSE
        )
      },
      width = "100%"
    )
  })
}
