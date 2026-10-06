prepped <- function() {
  prep_states(parse_states(read_fixture("states_small.json")))
}

test_that("prep_states drops rows without a position and trims callsigns", {
  df <- prepped()
  expect_equal(nrow(df), 4)
  expect_false("a1b2c3" %in% df$icao24)
  expect_equal(df$callsign[1], "SAA312")
})

test_that("airline codes come from commercial callsigns only", {
  expect_equal(
    airline_code(c("SAA312", "BAW9AB", "ZSABC", NA, "N136LM")),
    c("SAA", "BAW", NA, NA, NA)
  )
})

test_that("altitude bands use baro altitude, then geo altitude", {
  bands <- altitude_band(
    on_ground = c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE),
    baro_altitude = c(NA, 1000, 5000, 10000, NA, NA),
    geo_altitude = c(NA, NA, NA, NA, 9500, NA)
  )
  expect_equal(
    as.character(bands),
    c("On ground", "< 3,000 m", "3,000-9,000 m", "> 9,000 m", "> 9,000 m", "Unknown")
  )
  expect_equal(levels(bands), altitude_levels)
})

test_that("filter_states applies region, airline, band and airborne filters", {
  df <- prepped()
  expect_equal(nrow(filter_states(df)), 4)
  expect_equal(filter_states(df, "southern_africa")$icao24, c("00b1fa", "4ca7b3"))
  expect_equal(filter_states(df, "europe")$icao24, "400a1b")
  expect_equal(filter_states(df, "east_asia")$icao24, "780abc")
  expect_equal(filter_states(df, airlines = "SAA")$icao24, "00b1fa")
  expect_equal(filter_states(df, bands = "> 9,000 m")$icao24, "00b1fa")
  expect_false("4ca7b3" %in% filter_states(df, airborne_only = TRUE)$icao24)
})

test_that("get_region rejects unknown ids", {
  expect_error(get_region("atlantis"), "Unknown region")
})
