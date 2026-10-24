# Live Map tab: the aircraft on the shared map, and a results card with the
# aircraft count, the share airborne and the top origin countries. The card
# expands to a table of the filtered set.
#
# mod_live_server() takes one reactive from app.R:
#   aircraft  prepped + filtered state vectors
# app.R shows and hides the "planes" pane and the altitude legend, and flies
# the map to the region.

altitude_colours <- c(
  "On ground" = "#9aa0a6",
  "< 3,000 m" = "#f4a261",
  "3,000-9,000 m" = "#2a9d8f",
  # Indigo rather than the theme navy, so it shows on the dark basemap too.
  "> 9,000 m" = "#5e60ce",
  "Unknown" = "#d0d0d0"
)
# Brighter versions for the dark basemap (www/planes.js picks by theme).
altitude_colours_dark <- c(
  "On ground" = "#c3c8cd",
  "< 3,000 m" = "#f6b57f",
  "3,000-9,000 m" = "#4fd1c0",
  "> 9,000 m" = "#8f91ff",
  "Unknown" = "#e0e0e0"
)

mod_live_ui <- function(id) {
  ns <- NS(id)
  float_panel(
    class = "results-card live-card",
    div(class = "card-label", "Aircraft in view"),
    div(
      class = "big-number",
      tagAppendAttributes(textOutput(ns("n_aircraft"), inline = TRUE), class = "count-up")
    ),
    div(
      class = "card-stat",
      div(class = "card-label", "Airborne"),
      div(
        class = "stat-number",
        tagAppendAttributes(textOutput(ns("pct_airborne"), inline = TRUE), class = "count-up")
      ),
      uiOutput(ns("airborne_bar"))
    ),
    div(
      class = "card-stat",
      div(class = "card-label", "Top origin countries"),
      uiOutput(ns("top_countries"))
    ),
    tags$button(
      type = "button",
      class = "btn-more",
      `data-more` = "Show all aircraft",
      `data-less` = "Show less",
      "Show all aircraft"
    ),
    div(class = "card-more", div(class = "card-more-inner", DT::DTOutput(ns("table"))))
  )
}

mod_live_server <- function(id, aircraft) {
  moduleServer(id, function(input, output, session) {
    output$n_aircraft <- renderText(comma(nrow(aircraft())))

    share_airborne <- reactive({
      df <- aircraft()
      if (nrow(df) == 0) NA_real_ else 100 * mean(df$airborne)
    })

    output$pct_airborne <- renderText({
      pct <- share_airborne()
      if (is.na(pct)) "-" else sprintf("%.0f%%", pct)
    })

    # A thin bar under the percentage; www/app.css grows it from zero.
    output$airborne_bar <- renderUI({
      pct <- share_airborne()
      div(class = "stat-bar", tags$i(style = sprintf("width: %.1f%%", if (is.na(pct)) 0 else pct)))
    })

    countries <- reactive(top_countries(aircraft(), 5))

    output$top_countries <- renderUI({
      tc <- countries()
      if (length(tc) == 0) {
        return(div(class = "stat-number", "-"))
      }
      tags$ol(
        class = "country-list",
        lapply(seq_along(tc), function(i) {
          tags$li(span(names(tc)[i]), span(class = "country-count", comma(as.integer(tc[[i]]))))
        })
      )
    })

    # The aircraft as plane icons on the shared map's "planes" pane, drawn
    # and animated in the browser by www/planes.js. I() keeps length-0 and
    # length-1 vectors as JSON arrays.
    observe({
      df <- aircraft()
      session$sendCustomMessage(
        "planes-data",
        list(
          lon = I(round(df$longitude, 5)),
          lat = I(round(df$latitude, 5)),
          hdg = I(round(df$true_track, 1)),
          spd = I(round(df$velocity, 1)),
          alt = I(round(df$altitude)),
          band = I(as.character(df$altitude_band)),
          ground = I(df$on_ground %in% TRUE),
          callsign = I(df$callsign),
          popup = I(aircraft_popup(df)),
          palette = list(light = as.list(altitude_colours), dark = as.list(altitude_colours_dark))
        )
      )
    })

    output$table <- DT::renderDT({
      df <- aircraft()
      DT::datatable(
        data.frame(
          Callsign = df$callsign,
          Airline = df$airline_name,
          Code = df$airline_code,
          Category = df$flight_category,
          `Origin country` = df$origin_country,
          `Altitude (m)` = round(df$altitude),
          `Speed (km/h)` = round(df$velocity * 3.6),
          `Heading (deg)` = round(df$true_track),
          Band = df$altitude_band,
          check.names = FALSE
        ),
        rownames = FALSE,
        filter = "top",
        options = list(pageLength = 15, scrollX = TRUE)
      )
    })
  })
}

comma <- function(x) {
  formatC(x, format = "d", big.mark = ",")
}

# "Name (CODE)", just "CODE" when the name is unknown, "n/a" with no code.
airline_label <- function(name, code) {
  esc <- htmltools::htmlEscape
  ifelse(
    is.na(code),
    "n/a",
    ifelse(is.na(name), esc(code), paste0(esc(name), " (", esc(code), ")"))
  )
}

aircraft_popup <- function(df) {
  fmt <- function(x, unit, digits = 0) {
    ifelse(is.na(x), "n/a", paste(comma(round(x, digits)), unit))
  }
  esc <- function(x) htmltools::htmlEscape(ifelse(is.na(x), "n/a", x))
  paste0(
    "<b>", esc(df$callsign), "</b>",
    "<br>Airline: ", airline_label(df$airline_name, df$airline_code),
    "<br>Category: ", esc(as.character(df$flight_category)),
    "<br>Origin country: ", esc(df$origin_country),
    "<br>Altitude: ", ifelse(df$on_ground %in% TRUE, "on ground", fmt(df$altitude, "m")),
    "<br>Speed: ", fmt(df$velocity * 3.6, "km/h"),
    "<br>Heading: ", ifelse(is.na(df$true_track), "n/a", paste0(round(df$true_track), "&deg;"))
  )
}
