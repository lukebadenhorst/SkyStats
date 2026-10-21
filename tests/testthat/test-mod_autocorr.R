library(shiny)
library(bslib)
for (f in c("mod_common.R", "mod_autocorr.R")) source(file.path(root, "R", f))

sample_aircraft <- prep_states(readRDS(sample_path)$data)

test_that("the tab runs Moran's I on the sample in Europe and refuses World", {
  region <- reactiveVal("europe")
  testServer(autocorr_server, args = list(aircraft = reactive(sample_aircraft), region_id = region), {
    session$setInputs(hex_km = 150, log = TRUE, weights = "queen", k = 6, d = 300, style = "W",
                      statistic = "moran", inference = "analytic", nsim = 499, alpha = "0.05", run = 1)
    expect_true(result()$ok)
    expect_equal(result()$value$global$statistic, "Moran's I")
    region("world")
    session$setInputs(run = 2)
    expect_match(result()$message, "World has no equal-area projection")
  })
})

test_that("Global G always uses binary weights and analytic inference", {
  testServer(autocorr_server, args = list(aircraft = reactive(sample_aircraft), region_id = reactive("europe")), {
    session$setInputs(hex_km = 200, log = TRUE, weights = "queen", k = 6, d = 300, style = "W",
                      statistic = "globalg", inference = "perm", nsim = 499, alpha = "0.05", run = 1)
    expect_true(result()$ok)
    expect_equal(result()$value$global$statistic, "Global G")
    expect_match(result()$value$weights_label, "style B")
  })
})
