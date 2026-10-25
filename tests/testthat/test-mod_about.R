library(shiny)
library(bslib)
library(bsicons)
source(file.path(root, "R", "mod_common.R"))
source(file.path(root, "R", "mod_about.R"), encoding = "UTF-8")

about_html <- function() as.character(about_ui("about"))

test_that("the About panel has one tab and one section per part, Data sources first", {
  html <- about_html()
  for (sec in about_sections$id) {
    expect_match(html, sprintf('id="about-tab-%s"', sec), fixed = TRUE)
    expect_match(html, sprintf('id="about-view-%s"', sec), fixed = TRUE)
  }
  expect_equal(lengths(regmatches(html, gregexpr('class="about-tab"', html))), 4)
  expect_equal(lengths(regmatches(html, gregexpr('aria-selected="true"', html))), 1)
  expect_match(html, 'aria-selected="true"[^>]*>Data sources', perl = TRUE)
  # Only the first section shows at the start.
  expect_equal(lengths(regmatches(html, gregexpr('role="tabpanel"[^>]*hidden', html, perl = TRUE))), 3)
})

test_that("the section tabs do not use data-tab, which switches app tabs", {
  expect_no_match(about_html(), "data-tab=", fixed = TRUE)
})

test_that("the team is listed alphabetically by surname with student numbers", {
  surnames <- vapply(strsplit(about_team$name, " "), function(p) p[length(p)], character(1))
  expect_equal(surnames, sort(surnames))
  html <- about_html()
  for (i in seq_len(nrow(about_team))) {
    expect_match(html, about_team$name[i], fixed = TRUE)
    expect_match(html, about_team$student_no[i], fixed = TRUE)
  }
  expect_match(html, "Dr Raessa Manjoo-Docrat", fixed = TRUE)
})

test_that("every method and limitation group is on the page", {
  html <- about_html()
  for (x in c("Autocorrelation", "Point Patterns", "Spatial Regression", "The data", "Labels", "The analyses")) {
    expect_match(html, x, fixed = TRUE)
  }
})
