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
