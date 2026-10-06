prepped <- function() {
  prep_states(parse_states(read_fixture("states_small.json")), test_airlines)
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

test_that("prep_states looks up airline names by ICAO code", {
  df <- prepped()
  expect_equal(df$airline_name[df$airline_code %in% "SAA"], "South African Airways")
  expect_true(all(is.na(df$airline_name[is.na(df$airline_code)])))
})

test_that("prep_states works without an airline table", {
  df <- prep_states(parse_states(read_fixture("states_small.json")))
  expect_true(all(is.na(df$airline_name)))
})

test_that("airline_choices labels codes with names and counts", {
  df <- data.frame(
    airline_code = c("BAW", "BAW", "SAA", "XYZ", NA),
    airline_name = c("British Airways", "British Airways", "South African Airways", NA, NA)
  )
  choices <- airline_choices(df)
  expect_equal(unname(choices), c("BAW", "SAA", "XYZ"))
  expect_equal(
    names(choices),
    c("British Airways (BAW) · 2", "South African Airways (SAA) · 1", "XYZ · 1")
  )
})

test_that("flight_category applies the rules in order", {
  cats <- flight_category(
    icao24 = c("ae1234", "43c001", "43c002", "a00001", "a00002", "a00003", "a00004", "a00005", "a00006", "a00007"),
    callsign = c("BLZR298", "RCH123", "XYZ1", "FDX12", "ABC12", "EJA350", "SAA312", "N73AB", NA, "GAF601"),
    airline_code = c(NA, "RCH", "XYZ", "FDX", "ABC", "EJA", "SAA", NA, NA, "GAF"),
    airline_name = c(NA, "Air Mobility Command", "Royal Air Force", "Federal Express", "Mountain Air Cargo", "NetJets", "South African Airways", NA, NA, "German Air Force")
  )
  expect_equal(
    as.character(cats),
    c(
      "Military / government", # US military icao24 block
      "Military / government", # hand-listed code
      "Military / government", # air force by name
      "Cargo", # hand-listed code
      "Cargo", # cargo by name
      "Business jet",
      "Passenger airline",
      "Private / general aviation",
      "Unknown",
      "Military / government"
    )
  )
  expect_equal(levels(cats), category_levels)
})

test_that("military rules win over cargo, and cargo over business jet", {
  cats <- flight_category(
    icao24 = c("ae0001", "a00001"),
    callsign = c("FDX1", "EJA1"),
    airline_code = c("FDX", "EJA"),
    airline_name = c("Federal Express", "NetJets Cargo")
  )
  expect_equal(as.character(cats), c("Military / government", "Cargo"))
})

test_that("the US military block is ADF7C8 to AFFFFF", {
  expect_equal(
    us_military_icao24(c("adf7c7", "adf7c8", "AE1234", "afffff", "b00000", NA, "zz")),
    c(FALSE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE)
  )
})

test_that("prep_states adds a flight category", {
  df <- prepped()
  expect_equal(
    as.character(df$flight_category),
    c("Passenger airline", "Private / general aviation", "Passenger airline", "Passenger airline")
  )
})

test_that("load_airlines returns an empty table when the file is missing", {
  a <- load_airlines(tempfile(fileext = ".rds"))
  expect_equal(nrow(a), 0)
  expect_equal(airline_name("SAA", a), NA_character_)
})

test_that("the committed airline lookup covers major carriers", {
  a <- load_airlines(file.path(root, airlines_path))
  expect_false(anyDuplicated(a$icao) > 0)
  expect_equal(
    airline_name(c("SAA", "BAW", "UAE"), a),
    c("South African Airways", "British Airways", "Emirates")
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
  expect_equal(filter_states(df, categories = "Private / general aviation")$icao24, "4ca7b3")
})

test_that("get_region rejects unknown ids", {
  expect_error(get_region("atlantis"), "Unknown region")
})
