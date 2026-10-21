library(shiny)
library(bslib)
for (f in c("mod_common.R", "mod_regression.R")) source(file.path(root, "R", f))

sample_aircraft <- prep_states(readRDS(sample_path)$data)
airports <- load_airports(file.path(root, airports_path))

test_that("the tab runs on the sample in Europe, and other regions are refused", {
  region <- reactiveVal("europe")
  testServer(
    regression_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = region, airports = airports),
    {
      session$setInputs(
        covariates = c("pop", "gdpPercap"), log_y = TRUE, weights = "knn", k = 4,
        alpha = "0.05", resid = "ols_resid", run = 1
      )
      expect_true(result()$ok)
      expect_gte(result()$value$n, 15)

      region("north_america")
      session$setInputs(run = 2)
      expect_match(result()$message, "only available for Europe")
    }
  )
})

test_that("no covariates give the user message", {
  testServer(
    regression_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = reactive("europe"), airports = airports),
    {
      session$setInputs(covariates = character(), log_y = TRUE, weights = "queen", k = 4, alpha = "0.05", run = 1)
      expect_match(result()$message, "at least one covariate")
    }
  )
})

test_that("queen weights in Europe report the countries with no neighbours", {
  testServer(
    regression_server,
    args = list(aircraft = reactive(sample_aircraft), region_id = reactive("europe"), airports = airports),
    {
      # spdep warns that some countries have no neighbours; that is the point.
      suppressWarnings(session$setInputs(
        covariates = c("pop", "gdpPercap", "airports"), log_y = TRUE, weights = "queen", k = 4,
        alpha = "0.05", resid = "lag_resid", run = 1
      ))
      expect_true(result()$ok)
      expect_gte(result()$value$n_isolates, 1)
      expect_match(output$isolates$html, "no land neighbours")
      expect_match(output$map, "addPolygons")
    }
  )
})
