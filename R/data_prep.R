# Cleaning and filtering of parsed state vectors. Pure functions, no Shiny.

altitude_levels <- c(
  "On ground",
  "< 3,000 m",
  "3,000-9,000 m",
  "> 9,000 m",
  "Unknown"
)

# Commercial callsigns are a 3-letter ICAO airline code then a flight number,
# e.g. "SAA312", "BAW9AB". Anything else (registrations like "ZSABC") gets NA.
airline_code <- function(callsign) {
  code <- ifelse(
    grepl("^[A-Z]{3}[0-9]", callsign),
    substr(callsign, 1, 3),
    NA_character_
  )
  unname(code)
}

category_levels <- c(
  "Passenger airline",
  "Cargo",
  "Business jet",
  "Military / government",
  "Private / general aviation",
  "Unknown"
)

# ICAO allocates transponder addresses ADF7C8-AFFFFF to the US military.
us_military_icao24 <- function(icao24) {
  hex <- suppressWarnings(strtoi(icao24, 16L))
  !is.na(hex) & hex >= strtoi("adf7c8", 16L) & hex <= strtoi("afffff", 16L)
}

# One category per aircraft from its address, callsign and airline. Rules are
# checked top to bottom and the first match wins. Code lists and name
# patterns are in R/lookups.R.
flight_category <- function(icao24, callsign, airline_code, airline_name) {
  name <- ifelse(is.na(airline_name), "", airline_name)
  category <- dplyr::case_when(
    us_military_icao24(icao24) |
      airline_code %in% military_codes |
      grepl(military_name_pattern, name, ignore.case = TRUE) ~ "Military / government",
    airline_code %in% cargo_codes |
      grepl(cargo_name_pattern, name, ignore.case = TRUE) ~ "Cargo",
    airline_code %in% bizjet_codes ~ "Business jet",
    !is.na(airline_code) ~ "Passenger airline",
    !is.na(callsign) ~ "Private / general aviation",
    TRUE ~ "Unknown"
  )
  factor(category, levels = category_levels)
}

altitude_band <- function(on_ground, baro_altitude, geo_altitude) {
  alt <- ifelse(is.na(baro_altitude), geo_altitude, baro_altitude)
  band <- dplyr::case_when(
    on_ground %in% TRUE ~ "On ground",
    is.na(alt) ~ "Unknown",
    alt < 3000 ~ "< 3,000 m",
    alt <= 9000 ~ "3,000-9,000 m",
    TRUE ~ "> 9,000 m"
  )
  factor(band, levels = altitude_levels)
}

# `airlines` is the lookup from load_airlines(). Without it, names are NA.
prep_states <- function(df, airlines = NULL) {
  df <- df[!is.na(df$longitude) & !is.na(df$latitude), , drop = FALSE]
  callsign <- trimws(df$callsign)
  callsign[!nzchar(callsign)] <- NA_character_
  df$callsign <- callsign
  df$airline_code <- airline_code(callsign)
  df$airline_name <- if (is.null(airlines)) {
    rep(NA_character_, nrow(df))
  } else {
    airline_name(df$airline_code, airlines)
  }
  df$flight_category <- flight_category(df$icao24, callsign, df$airline_code, df$airline_name)
  df$altitude <-ifelse(is.na(df$baro_altitude), df$geo_altitude, df$baro_altitude)
  df$altitude_band <- altitude_band(df$on_ground, df$baro_altitude, df$geo_altitude)
  df$airborne <- !(df$on_ground %in% TRUE)
  df
}

# Sidebar filters. NULL / empty airlines, bands or categories mean "no filter".
filter_states <- function(
  df,
  region_id = "world",
  airlines = NULL,
  bands = NULL,
  categories = NULL,
  airborne_only = FALSE
) {
  df <- crop_to_region(df, region_id)
  if (length(airlines) > 0) {
    df <- df[df$airline_code %in% airlines, , drop = FALSE]
  }
  if (length(bands) > 0) {
    df <- df[df$altitude_band %in% bands, , drop = FALSE]
  }
  if (length(categories) > 0) {
    df <- df[df$flight_category %in% categories, , drop = FALSE]
  }
  if (isTRUE(airborne_only)) {
    df <- df[df$airborne, , drop = FALSE]
  }
  df
}

# Airline codes ordered by aircraft count, for the sidebar picker.
airline_counts <- function(df) {
  codes <- df$airline_code[!is.na(df$airline_code)]
  sort(table(codes), decreasing = TRUE)
}

# Picker choices: values are airline codes, labels are
# "Name (CODE) · count", or "CODE · count" when the name is unknown.
airline_choices <- function(df) {
  counts <- airline_counts(df)
  codes <- names(counts)
  airline <- df$airline_name[match(codes, df$airline_code)]
  label <- ifelse(is.na(airline), codes, paste0(airline, " (", codes, ")"))
  stats::setNames(codes, paste0(label, " · ", as.integer(counts)))
}

top_countries <- function(df, n = 5) {
  counts <- sort(table(df$origin_country), decreasing = TRUE)
  utils::head(counts, n)
}
