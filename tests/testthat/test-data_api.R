test_that("parse_states reads fields by position and turns nulls into NA", {
  body <- read_fixture("states_small.json")
  df <- parse_states(body)

  expect_equal(nrow(df), 5)
  expect_named(df, names(state_fields))
  expect_type(df$longitude, "double")
  expect_type(df$on_ground, "logical")
  expect_type(df$category, "integer")
  expect_equal(df$icao24[1], "00b1fa")
  expect_equal(df$origin_country[3], "United Kingdom")
  expect_true(is.na(df$baro_altitude[2]))
  expect_true(is.na(df$latitude[4]))
  expect_equal(df$squawk[3], "4321")
})

test_that("parse_states handles an empty snapshot and missing category", {
  empty <- parse_states(list(time = 1, states = NULL))
  expect_equal(nrow(empty), 0)
  expect_named(empty, names(state_fields))

  short <- list(states = list(list(
    "abc123", "TST1", "Nowhere", 1, 1, 10, 20, 100, FALSE,
    50, 90, 0, NULL, 110, NULL, FALSE, 0
  )))
  expect_true(is.na(parse_states(short)$category))
})

test_that("states_time converts the epoch to UTC", {
  t <- states_time(read_fixture("states_small.json"))
  expect_equal(attr(t, "tzone"), "UTC")
  expect_equal(as.numeric(t), 1791298080)
})

fake_live <- function() {
  body <- read_fixture("states_small.json")
  list(data = parse_states(body), time = states_time(body))
}
failing <- function() stop("boom")

test_that("no credentials falls back to the sample without calling the API", {
  called <- FALSE
  out <- get_states(
    store = new_states_store(),
    fetch = function() {
      called <<- TRUE
      fake_live()
    },
    has_creds = FALSE,
    sample_path = sample_path
  )
  expect_false(called)
  expect_equal(out$source, "sample")
  expect_match(out$message, "credentials")
  expect_gt(nrow(out$data), 1000)
})

test_that("an API failure with no previous data falls back to the sample", {
  out <- get_states(
    store = new_states_store(),
    fetch = failing,
    has_creds = TRUE,
    sample_path = sample_path
  )
  expect_equal(out$source, "sample")
  expect_match(out$message, "boom")
})

test_that("live results are cached so sessions share one API call", {
  store <- new_states_store()
  n_calls <- 0
  fetch <- function() {
    n_calls <<- n_calls + 1
    fake_live()
  }
  first <- get_states(store = store, fetch = fetch, has_creds = TRUE)
  second <- get_states(store = store, fetch = fetch, has_creds = TRUE)
  expect_equal(first$source, "live")
  expect_equal(second$source, "live")
  expect_equal(n_calls, 1)
})

test_that("a forced refresh soon after a fetch is ignored", {
  store <- new_states_store(min_force_interval = 60)
  n_calls <- 0
  fetch <- function() {
    n_calls <<- n_calls + 1
    fake_live()
  }
  get_states(store = store, fetch = fetch, has_creds = TRUE)
  get_states(force = TRUE, store = store, fetch = fetch, has_creds = TRUE)
  expect_equal(n_calls, 1)
})

test_that("a failure after a good fetch serves the stale live data", {
  store <- new_states_store(min_force_interval = 0)
  get_states(store = store, fetch = fake_live, has_creds = TRUE)
  out <- get_states(
    force = TRUE,
    store = store,
    fetch = failing,
    has_creds = TRUE,
    sample_path = sample_path
  )
  expect_equal(out$source, "cache")
  expect_equal(nrow(out$data), 5)
  expect_match(out$message, "boom")
})

test_that("the bundled sample snapshot exists and is well formed", {
  s <- load_sample_states(sample_path)
  expect_named(s, c("data", "time"))
  expect_s3_class(s$time, "POSIXct")
  expect_true(all(names(state_fields) %in% names(s$data)))
})
