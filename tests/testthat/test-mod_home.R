library(shiny)
library(bslib)
for (f in c("mod_common.R", "mod_autocorr.R", "mod_home.R")) source(file.path(root, "R", f))

test_that("the tour has six steps in speaking order", {
  expect_length(tour_steps, 6)
  expect_equal(vapply(tour_steps, `[[`, "", "action"), c("world", "badge", "pipeline", "lisa", "regions", "coverage"))
  for (s in tour_steps) {
    expect_true(nzchar(s$title))
    expect_gte(length(s$points), 2)
  }
})

test_that("the home page links every tab it shows to a real tab", {
  html <- as.character(home_ui("home"))
  targets <- regmatches(html, gregexpr('data-tab="[a-z]+"', html))[[1]]
  expect_true(all(sub('data-tab="([a-z]+)"', "\\1", targets) %in% app_tabs$id))
  expect_match(html, 'id="tour-data"')
})

test_that("the tour hexes use the unfiltered data and are retried after a failure", {
  sample_aircraft <- prep_states(readRDS(sample_path)$data)
  # The hero count follows `aircraft`; the tour reads `tour_aircraft`.
  count_source <- reactiveVal(sample_aircraft[0, ])
  tour_source <- reactiveVal(sample_aircraft[0, ])
  testServer(
    home_server,
    args = list(aircraft = count_source, tour_aircraft = tour_source),
    {
      expect_equal(output$count, "0")
      count_source(sample_aircraft)
      session$flushReact()
      expect_equal(output$count, format(nrow(sample_aircraft), big.mark = ","))

      # No aircraft: the run fails quietly and nothing is marked as drawn.
      session$setInputs(tour_start = 1)
      expect_false(tour_drawn())
      # The next start tries again, and a success is not redrawn.
      tour_source(sample_aircraft)
      session$setInputs(tour_start = 2)
      expect_true(tour_drawn())
    }
  )
})
