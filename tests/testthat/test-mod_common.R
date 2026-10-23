library(shiny)
library(bslib)
source(file.path(root, "R", "mod_common.R"))

test_that("plot_palette picks light colours for dark text", {
  pal <- plot_palette("rgb(33, 37, 41)")
  expect_false(pal$dark)
  expect_equal(pal$fg, "#212529")
  expect_equal(pal$line, "#1d3557")
})

test_that("plot_palette picks dark-mode colours for light text", {
  pal <- plot_palette("rgb(222, 226, 230)")
  expect_true(pal$dark)
  expect_equal(pal$fg, "#DEE2E6")
  expect_equal(pal$line, "#a8dadc")
})

test_that("plot_palette reads hex colours, as Shiny sends them", {
  expect_true(plot_palette("#DEE2E6")$dark)
  expect_false(plot_palette("#212529")$dark)
})

test_that("plot_palette falls back to light mode with no colour", {
  expect_false(plot_palette(NULL)$dark)
  expect_false(plot_palette("not a colour")$dark)
  expect_equal(plot_palette(NULL)$fg, "#000000")
})

# ---- Method tab pieces ------------------------------------------------------

test_that("settings_panel offers only the regions the method accepts", {
  html <- as.character(settings_panel(
    NS("autocorr"), "autocorr", "Autocorrelation", "Ch 4",
    question = "Do busy areas sit next to other busy areas?",
    intro = "We cover the region in hexagons.",
    fields = setting(sliderInput("autocorr-hex_km", "Hex size", 50, 500, 150), "How big each hexagon is.")
  ))
  expect_match(html, 'id="autocorr-settings"')
  expect_match(html, "settings-panel")
  expect_match(html, 'id="autocorr-setup_region"')
  expect_match(html, 'id="autocorr-setup_run"')
  expect_match(html, "Autocorrelation settings")
  expect_match(html, "Settings guide")
  expect_match(html, "How big each hexagon is.")
  expect_match(html, "World is not offered")
  expect_no_match(html, 'value="world"')
  expect_match(html, 'value="europe"')

  reg <- as.character(settings_panel(NS("regression"), "regression", "Regression", "Ch 6", "Q", "I", NULL))
  expect_match(reg, 'value="world"')
  expect_no_match(reg, 'value="north_america"')
  expect_match(reg, "at least 15 of them")
})

test_that("results_card has the short output, the button and the full results", {
  html <- as.character(results_card(NS("quadrat"), p("full results here")))
  expect_match(html, 'id="quadrat-card"')
  expect_match(html, 'id="quadrat-short"')
  expect_match(html, "Show all results")
  expect_match(html, "results-full")
  expect_match(html, "full results here")
})

test_that("summary_ui renders the number, the badge and the 2 x 2 grid", {
  s <- list(
    label = "Global Moran's I", value = 0.4213, digits = 3L, badge = "Clustered",
    tone = "hot", mini = c("z-score" = "8.14", "p-value" = "< 0.001"), text = "Busy hexes cluster."
  )
  html <- as.character(summary_ui(s, legend = legend_ui(c("#d7301f", "#2c7bb6"), c("High-High", "Low-Low"))))
  expect_match(html, "Global Moran's I", fixed = TRUE)
  expect_match(html, 'class="count-up" data-digits="3">0.421<')
  expect_match(html, "badge-pill tone-hot")
  expect_match(html, "z-score")
  expect_match(html, "&lt; 0.001")
  expect_match(html, "Busy hexes cluster.")
  expect_match(html, "#d7301f")
  expect_match(html, "Low-Low")
})

test_that("region_alert offers the accepted regions only when the region was refused", {
  expect_null(region_alert(list(ok = TRUE, value = 1), "autocorr"))
  plain <- as.character(region_alert(list(ok = FALSE, message = "Too few aircraft."), "autocorr"))
  expect_match(plain, "Too few aircraft.")
  expect_no_match(plain, "region-btn")
  refused <- as.character(region_alert(
    list(ok = FALSE, message = "World has no equal-area projection.", region_refused = TRUE),
    "regression"
  ))
  expect_match(refused, 'class="region-btn" data-region="europe"')
  expect_match(refused, 'data-region="world"')
  expect_no_match(refused, 'data-region="east_asia"')
})

# ---- method_runner() --------------------------------------------------------

runner_test_server <- function(id, active, region, calls) {
  moduleServer(id, function(input, output, session) {
    res <- method_runner(
      input, session, "autocorr", active, region,
      params = reactive(list(n = input$n)),
      compute = function(p, region) {
        calls(calls() + 1)
        run_safely(p$n * 2)
      }
    )
    observe({
      req(active())
      res()
    })
    session$userData$res <- res
  })
}

test_that("the runner waits for the setup box, then debounces changes", {
  calls <- reactiveVal(0)
  testServer(runner_test_server, args = list(active = reactive(TRUE), region = reactive("europe"), calls = calls), {
    session$setInputs(n = 1)
    session$elapse(1000)
    expect_equal(calls(), 0) # no run before Run analysis
    session$setInputs(setup_region = "europe", setup_run = 1)
    session$elapse(700)
    expect_equal(calls(), 1)
    expect_equal(session$userData$res()$value, 2)
    session$setInputs(n = 2)
    session$elapse(200)
    session$setInputs(n = 3)
    session$elapse(200)
    session$setInputs(n = 4)
    session$elapse(700)
    expect_equal(calls(), 2) # one run for the burst (Review Focus 3)
    expect_equal(session$userData$res()$value, 8)
  })
})

test_that("an inactive tab does not run, and a refused region is flagged", {
  calls <- reactiveVal(0)
  active <- reactiveVal(TRUE)
  region <- reactiveVal("world")
  testServer(runner_test_server, args = list(active = active, region = region, calls = calls), {
    session$setInputs(n = 1, setup_region = "europe", setup_run = 1)
    session$elapse(700)
    expect_true(session$userData$res()$region_refused) # region() is still "world" in the mock
    n_before <- calls()
    active(FALSE)
    session$setInputs(n = 5)
    session$elapse(700)
    expect_equal(calls(), n_before) # nothing ran while inactive (Review Focus 4)
  })
})

test_that("coming back to a tab that has run shows the last result without re-running", {
  calls <- reactiveVal(0)
  active <- reactiveVal(TRUE)
  testServer(runner_test_server, args = list(active = active, region = reactive("europe"), calls = calls), {
    session$setInputs(n = 1, setup_region = "europe", setup_run = 1)
    session$elapse(700)
    expect_equal(calls(), 1)
    active(FALSE)
    session$elapse(700)
    active(TRUE)
    session$elapse(700)
    expect_equal(calls(), 1)
    expect_equal(session$userData$res()$value, 2)
  })
})
