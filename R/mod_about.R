# About tab: a full-screen panel with four sections (data sources, methods,
# limitations, team and credits), switched by a segmented control at the top.
# The switching happens in the browser (www/app.js). Static text, so there is
# no server function.

about_sections <- data.frame(
  id = c("data", "methods", "limits", "team"),
  label = c("Data sources", "Methods", "Limitations", "Team & credits")
)

about_team <- data.frame(
  name = c("Anthony Akueche", "Luke Badenhorst", "Wenda Nyanda", "Ofentse Rakoo"),
  student_no = c("2881188", "2658321", "2857845", "2823020")
)

about_ui <- function(id) {
  ns <- NS(id)
  float_panel(
    class = "about-panel",
    div(
      class = "about-head",
      div(
        class = "about-title",
        h1("About SkyStats"),
        p("Where the data comes from and how we analyse it")
      ),
      div(
        class = "about-seg",
        role = "tablist",
        `aria-label` = "About sections",
        lapply(seq_len(nrow(about_sections)), function(i) {
          sec <- about_sections$id[i]
          first <- i == 1
          tags$button(
            type = "button",
            class = "about-tab",
            role = "tab",
            id = ns(paste0("tab-", sec)),
            `data-about` = sec,
            `aria-controls` = ns(paste0("view-", sec)),
            `aria-selected` = if (first) "true" else "false",
            tabindex = if (first) "0" else "-1",
            about_sections$label[i]
          )
        })
      ),
      div(class = "about-head-end")
    ),
    div(
      class = "about-views",
      about_view(ns, "data", about_data(), first = TRUE),
      about_view(ns, "methods", about_methods()),
      about_view(ns, "limits", about_limits()),
      about_view(ns, "team", about_team_view())
    )
  )
}

about_view <- function(ns, sec, ..., first = FALSE) {
  div(
    class = "about-view",
    id = ns(paste0("view-", sec)),
    role = "tabpanel",
    `aria-labelledby` = ns(paste0("tab-", sec)),
    `data-about` = sec,
    hidden = if (!first) NA,
    ...
  )
}

about_intro <- function(title, text) {
  div(class = "about-intro", h2(title), p(text))
}

about_label <- function(..., class = NULL) {
  span(class = paste(c("about-label", class), collapse = " "), ...)
}

# ---- Data sources -----------------------------------------------------------

about_data <- function() {
  arrow <- div(class = "about-arrow", `aria-hidden` = "true", bs_icon("arrow-right"))
  tagList(
    about_intro(
      "Where the data comes from",
      paste(
        "Each aircraft on the map is a position report from the OpenSky Network, which collects them",
        "from volunteer receivers. Three lookup tables add airline names, airports and country data."
      )
    ),
    div(
      class = "about-flow",
      div(
        class = "about-node main",
        about_label("Source"),
        strong("OpenSky Network REST API"),
        span(
          inline_code("/states/all"),
          ": position, altitude, speed and callsign for every aircraft seen by ADS-B receivers."
        )
      ),
      arrow,
      div(
        class = "about-node",
        about_label("Shared cache"),
        strong("Fetched at most every 10 minutes"),
        span("Everyone using the app shares one request, so we stay inside OpenSky's rate limit.")
      ),
      arrow,
      div(
        class = "about-node",
        about_label("App"),
        strong("Map and analyses"),
        span("You filter by region, airline, category and altitude. Each region has its own projection."),
        div(
          class = "about-fallback",
          "If there are no credentials or the API is down, the app uses a bundled snapshot (",
          inline_code("states_sample.rds"),
          "). The badge at the top right says which one you are seeing."
        )
      )
    ),
    about_label("Lookup tables", class = "about-table-label"),
    div(
      class = "about-table-wrap",
      tags$table(
        class = "about-table",
        tags$thead(tags$tr(
          tags$th(about_label("Dataset")),
          tags$th(about_label("What it adds")),
          tags$th(about_label("Used on")),
          tags$th(about_label("File"))
        )),
        tags$tbody(
          about_source_row(
            "OpenFlights airlines",
            "Airline names, matched on the first three letters of the callsign. A few newer airlines added by hand.",
            c("Filters", "Live Map"),
            inline_code("data/lookups/airlines.rds")
          ),
          about_source_row(
            "OurAirports",
            "Large and medium airports, as points and as a count per country.",
            c("Point Patterns", "Regression"),
            inline_code("data/lookups/airports.rds")
          ),
          about_source_row(
            inline_code("spData::world"),
            "Country outlines, population, GDP per capita and area. The same data as the regression example in the course notes.",
            "Regression",
            "R package"
          )
        )
      )
    ),
    p(class = "about-cite", "Data courtesy of The OpenSky Network, https://opensky-network.org")
  )
}

about_source_row <- function(name, adds, used_on, file) {
  tags$tr(
    tags$td(name),
    tags$td(adds),
    tags$td(div(class = "about-uses", lapply(used_on, span))),
    tags$td(file)
  )
}

# ---- Methods ----------------------------------------------------------------

about_methods <- function() {
  tagList(
    about_intro(
      "Three methods from the course notes",
      paste(
        "Each method tab asks one question about where aircraft are. They run in the region's",
        "equal-area projection when you click Run analysis."
      )
    ),
    div(
      class = "about-cols",
      about_method(
        "hexagon",
        "Autocorrelation",
        "Do busy areas of sky sit next to other busy areas?",
        list(
          tagList("Count aircraft in a hexagonal grid over the region (", inline_code("sf::st_make_grid"), ")."),
          tagList(
            "Build spatial weights: queen contiguity, k nearest neighbours, a distance band or inverse distance (",
            inline_code("spdep::nb2listw"), ")."
          ),
          tagList(
            "Test for clustering with global Moran's I, Geary's C or Global G (",
            inline_code("moran.test"), ", ", inline_code("geary.test"), ", ", inline_code("globalG.test"),
            ", or ", inline_code("moran.mc"), " by permutation)."
          ),
          tagList(
            "Map local clusters and outliers with Local Moran's I (", inline_code("spdep::localmoran"), ")."
          )
        ),
        "Reading Moran's I",
        list(c("I < 0", "dispersed"), c("I ≈ 0", "random"), c("I > 0", "clustered"))
      ),
      about_method(
        "grid-3x3",
        "Point Patterns",
        "Are aircraft or airports spread at random, or bunched together?",
        list(
          tagList(
            "Turn airborne aircraft or airports into a point pattern in the region's projection (",
            inline_code("spatstat.geom::ppp"), ")."
          ),
          "Split the largest rectangle inside the region into an nx × ny grid of equal quadrats.",
          tagList(
            "Test the counts for complete spatial randomness with the chi-squared quadrat test (",
            inline_code("spatstat.explore::quadrat.test"), ")."
          ),
          "Compute the variance-to-mean ratio and test (m − 1) × VTMR on m − 1 degrees of freedom."
        ),
        "Reading the VTMR",
        list(c("< 1", "regular"), c("≈ 1", "random"), c("> 1", "clustered"))
      ),
      about_method(
        "graph-up",
        "Spatial Regression",
        "What explains how many aircraft are over a country, once neighbours are accounted for?",
        list(
          tagList(
            "Fit OLS: aircraft count on population, GDP per capita, area and airports (", inline_code("lm"), ")."
          ),
          tagList(
            "Check the residuals for spatial autocorrelation with Moran's I (", inline_code("spdep::moran.test"), ")."
          ),
          tagList("Choose a model with the Lagrange multiplier tests (", inline_code("spdep::lm.RStests"), ")."),
          tagList(
            "Fit a spatial lag model (", inline_code("spatialreg::lagsarlm"), ") and compare it with OLS by AIC."
          )
        ),
        "Reading ρ (rho)",
        list(
          c("ρ < 0", "neighbours pull down"),
          c("ρ ≈ 0", "no spillover"),
          c("ρ > 0", "neighbours push up")
        )
      )
    ),
    div(
      class = "about-foot",
      "Each result ends with a plain-English reading at the significance level (α) you pick. ",
      "The Real-world uses button explains what the statistic means for aviation."
    )
  )
}

# scale: a list of c(value, meaning) pairs, shown as three boxes.
about_method <- function(icon, title, question, steps, scale_label, scale) {
  div(
    class = "about-col about-method",
    div(class = "about-method-top", div(class = "about-icon", bs_icon(icon)), h3(title)),
    p(class = "about-question", question),
    tags$ol(class = "about-steps", lapply(steps, tags$li)),
    div(
      class = "about-read",
      about_label(scale_label),
      div(class = "about-scale", lapply(scale, function(s) div(tags$b(s[1]), s[2])))
    )
  )
}

# ---- Limitations ------------------------------------------------------------

about_limits <- function() {
  tagList(
    about_intro(
      "Limitations",
      "Most of these come from the data. Each result describes one moment of traffic, as seen by volunteer receivers."
    ),
    div(
      class = "about-cols",
      about_limit_group(
        "The data",
        "Where positions come from",
        about_limit(
          "A single snapshot",
          "Each analysis uses the positions at one moment. The API only serves the last hour.",
          "Patterns change with time of day"
        ),
        about_limit(
          "Uneven receiver coverage",
          paste(
            "Receivers are dense over North America and Europe and sparse over oceans, Africa and parts",
            "of Asia. An empty patch of sky may just have no receivers."
          ),
          "Clustering is partly a coverage effect"
        ),
        about_limit(
          "Origin country means registration",
          "It is the country the aircraft is registered in. The flight may have left from somewhere else."
        )
      ),
      about_limit_group(
        "Labels",
        "How airlines and categories are guessed",
        about_limit(
          "Airline from the callsign",
          paste(
            "Taken from the first three characters. Private and military flights have no code, and",
            "OpenFlights has no name for some newer airlines."
          )
        ),
        about_limit(
          "Categories are inferred",
          paste(
            "From the callsign, airline and transponder address. Military flights with tactical callsigns",
            "are only caught inside the US military address block."
          ),
          "Some military flights show as private"
        ),
        about_limit(
          "Mixed airlines count as passenger",
          "Airlines that fly both passengers and freight are filed as passenger airlines."
        )
      ),
      about_limit_group(
        "The analyses",
        "Choices the methods need",
        about_limit(
          "One region at a time",
          paste(
            "No single equal-area projection covers the globe, so Autocorrelation and Point Patterns",
            "need one of the four regions."
          )
        ),
        about_limit(
          "Quadrats use a rectangle",
          paste(
            "The VTMR assumes every quadrat has the same area, so the test uses the largest rectangle",
            "that fits inside the region. Points outside it are left out."
          ),
          "Edges of the region are ignored"
        ),
        about_limit(
          "Regression needs 15+ countries",
          tagList(
            "It only runs for Europe and the World. ", inline_code("spData::world"),
            " has no population or GDP for a few countries, including France and Norway, ",
            "so the model leaves them out."
          )
        )
      )
    )
  )
}

about_limit_group <- function(title, subtitle, ...) {
  div(class = "about-col", h3(title), p(class = "about-sub", subtitle), ...)
}

about_limit <- function(title, text, effect = NULL) {
  div(
    class = "about-limit",
    strong(title),
    span(text),
    if (!is.null(effect)) div(class = "about-effect", effect)
  )
}

# ---- Team and credits -------------------------------------------------------

about_team_view <- function() {
  initials <- vapply(
    strsplit(about_team$name, " "),
    function(p) paste(substr(p, 1, 1), collapse = ""),
    character(1)
  )
  packages <- list(
    list(c("shiny", "bslib"), "app"),
    list("leaflet", "map"),
    list("httr2", "OpenSky API"),
    list("sf", "grids, projections"),
    list("spdep", "weights, Moran's I"),
    list("spatialreg", "lag model"),
    list("spatstat", "quadrat test"),
    list("spData", "country data")
  )
  tagList(
    about_intro(
      "Team and credits",
      "We built SkyStats in R Shiny as a group assignment for Introduction to Spatial Statistics."
    ),
    div(
      class = "about-credits",
      div(
        div(
          class = "about-course",
          span(class = "about-course-code", "STAT3037A"),
          strong("Introduction to Spatial Statistics"),
          span("University of the Witwatersrand · Lecturer: Dr Raessa Manjoo-Docrat · Due 26 October 2026")
        ),
        about_label("The group"),
        div(
          class = "about-team",
          lapply(seq_len(nrow(about_team)), function(i) {
            div(
              class = "about-person",
              div(class = "about-avatar", `aria-hidden` = "true", initials[i]),
              div(strong(about_team$name[i]), span(class = "about-student-no", about_team$student_no[i]))
            )
          })
        )
      ),
      div(
        about_label("Built with"),
        div(
          class = "about-pkgs",
          lapply(packages, function(p) {
            div(class = "about-pkg", div(lapply(p[[1]], inline_code)), span(p[[2]]))
          })
        ),
        div(
          class = "about-thanks",
          about_label("Data credits"),
          p("The OpenSky Network, https://opensky-network.org"),
          p("OpenFlights airline database · OurAirports"),
          p("Basemap: Esri World Gray Canvas")
        )
      )
    )
  )
}

# code() and strong() without the space htmltools puts around each child, so
# "(" code ")" renders as "(x)" rather than "( x )". The text around them
# carries its own spaces.
inline_code <- function(x) code(x, .noWS = "outside")
inline_strong <- function(x) strong(x, .noWS = "outside")
