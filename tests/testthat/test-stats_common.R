test_that("stop_user signals a user_error", {
  expect_error(stop_user("Too few points: ", 3), "Too few points: 3", class = "user_error")
})

test_that("run_safely returns the value or a message", {
  expect_equal(run_safely(1 + 1), list(ok = TRUE, value = 2))
  expect_equal(run_safely(stop_user("Pick a region.")), list(ok = FALSE, message = "Pick a region."))
  expect_equal(run_safely(stop("boom"))$message, "The analysis failed: boom")
})

test_that("p-values and decisions are worded consistently", {
  expect_equal(format_p(0.0004), "< 0.001")
  expect_equal(format_p(0.00588), "0.006")
  expect_equal(decision_text(0.00588, 0.05), "p = 0.006 < α = 0.05, so we reject H0.")
  expect_equal(decision_text(0.4, 0.05), "p = 0.400 ≥ α = 0.05, so we do not reject H0.")
  expect_equal(decision_text(0.0001, 0.05), "p < 0.001 < α = 0.05, so we reject H0.")
})
