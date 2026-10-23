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

test_that("changing the residual type does not re-run the model", {
  testServer(
    regression_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = reactive("europe"), airports = airports, active = reactive(TRUE)),
    {
      session$setInputs(
        covariates = c("pop", "gdpPercap"), log_y = TRUE, weights = "knn", k = 4,
        alpha = "0.05", resid = "ols_resid", setup_region = "europe", setup_run = 1
      )
      session$elapse(700)
      first <- result()
      session$setInputs(resid = "lag_resid")
      session$elapse(700)
      expect_identical(result(), first)
    }
  )
})

test_that("residual_scale gives eight bins centred on zero", {
  s <- residual_scale(c(-1.2, 0.3, 0.9))
  expect_length(s$mids, 8)
  expect_equal(sum(s$mids), 0, tolerance = 1e-9)
  expect_length(s$pal(s$mids), 8)
})
