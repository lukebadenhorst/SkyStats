library(shiny)
library(bslib)
for (f in c("mod_common.R", "mod_home.R")) source(file.path(root, "R", f))

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
