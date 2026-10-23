test_that("the shared map has one pane per layer, in z-order", {
  expect_equal(names(map_panes), c("autocorr", "quadrat", "regression", "tour", "planes"))
  expect_true(all(diff(map_panes) > 0))
})

test_that("shared_map() builds a leaflet widget", {
  expect_s3_class(shared_map(), "leaflet")
})
