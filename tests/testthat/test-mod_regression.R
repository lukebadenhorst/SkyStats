library(shiny)
library(bslib)
for (f in c("mod_common.R", "mod_regression.R")) source(file.path(root, "R", f))

sample_aircraft <- prep_states(readRDS(sample_path)$data)
airports <- load_airports(file.path(root, airports_path))

test_that("the tab runs on the sample in Europe, and other regions are refused", {
  region <- reactiveVal("europe")
  testServer(
    regression_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = region, airports = airports, active = reactive(TRUE)),
    {
      session$setInputs(
        covariates = c("pop", "gdpPercap"), log_y = TRUE, weights = "knn", k = 4,
        alpha = "0.05", resid = "ols_resid", setup_region = "europe", setup_run = 1
      )
      session$elapse(700)
      expect_true(result()$ok)
      expect_gte(result()$value$n, 15)

      region("north_america")
      # A reactiveVal needs a flush so the debounce sees the change.
      session$flushReact()
      session$elapse(700)
      expect_match(result()$message, "only available for Europe")
      expect_true(result()$region_refused)
    }
  )
})

test_that("no covariates give the user message", {
  testServer(
    regression_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = reactive("europe"), airports = airports, active = reactive(TRUE)),
    {
      session$setInputs(
        covariates = character(), log_y = TRUE, weights = "queen", k = 4, alpha = "0.05",
        setup_region = "europe", setup_run = 1
      )
      session$elapse(700)
      expect_match(result()$message, "at least one covariate")
    }
  )
})

test_that("queen weights in Europe report the countries with no neighbours", {
  testServer(
    regression_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = reactive("europe"), airports = airports, active = reactive(TRUE)),
    {
      # spdep warns that some countries have no neighbours; that is the point.
      suppressWarnings({
        session$setInputs(
          covariates = c("pop", "gdpPercap", "airports"), log_y = TRUE, weights = "queen", k = 4,
          alpha = "0.05", resid = "lag_resid", setup_region = "europe", setup_run = 1
        )
        session$elapse(700)
      })
      expect_true(result()$ok)
      expect_gte(result()$value$n_isolates, 1)
      expect_match(output$isolates$html, "no land neighbours")
      expect_match(output$short$html, "Spatial lag residuals")
    }
  )
})

test_that("changing the residual type recolours the legend and does not re-run the model", {
  # run_regression() is a global function (sourced by helper-source.R), so
  # swap in a counting wrapper for this test.
  original <- get("run_regression", envir = globalenv())
  runs <- 0
  assign("run_regression", function(...) {
    runs <<- runs + 1
    original(...)
  }, envir = globalenv())
  on.exit(assign("run_regression", original, envir = globalenv()))

  testServer(
    regression_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = reactive("europe"), airports = airports, active = reactive(TRUE)),
    {
      session$setInputs(
        covariates = c("pop", "gdpPercap"), log_y = TRUE, weights = "knn", k = 4,
        alpha = "0.05", resid = "ols_resid", setup_region = "europe", setup_run = 1
      )
      session$elapse(700)
      expect_true(result()$ok)
      expect_equal(runs, 1)
      first_params <- params()
      ols_legend <- output$resid_legend$html

      session$setInputs(resid = "lag_resid")
      session$elapse(700)
      expect_equal(runs, 1)
      expect_identical(params(), first_params)
      lag_legend <- output$resid_legend$html
      expect_match(ols_legend, "OLS residual")
      expect_match(lag_legend, "Lag residual")
      expect_false(identical(ols_legend, lag_legend))

      # A real input change still re-runs, so the counter is a fair check.
      # (spdep warns about countries with no neighbours under queen weights.)
      suppressWarnings({
        session$setInputs(weights = "queen")
        session$elapse(700)
      })
      expect_equal(runs, 2)
    }
  )
})

test_that("residual_scale gives eight bins centred on zero", {
  s <- residual_scale(c(-1.2, 0.3, 0.9))
  expect_length(s$mids, 8)
  expect_equal(sum(s$mids), 0, tolerance = 1e-9)
  expect_length(s$pal(s$mids), 8)
})

test_that("no aircraft gives a plain message, not an R error", {
  testServer(
    regression_server,
    args = list(aircraft = reactive(sample_aircraft[0, ]), region_id = reactive("europe"), airports = airports, active = reactive(TRUE)),
    {
      session$setInputs(
        covariates = c("pop", "gdpPercap"), log_y = TRUE, weights = "knn", k = 4,
        alpha = "0.05", resid = "ols_resid", setup_region = "europe", setup_run = 1
      )
      session$elapse(700)
      expect_false(result()$ok)
      expect_match(result()$message, "^No aircraft match the current filters")
    }
  )
})
