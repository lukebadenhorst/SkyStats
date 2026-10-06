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

prep_states <- function(df) {
  df <- df[!is.na(df$longitude) & !is.na(df$latitude), , drop = FALSE]
  callsign <- trimws(df$callsign)
  callsign[!nzchar(callsign)] <- NA_character_
  df$callsign <- callsign
  df$airline_code <- airline_code(callsign)
  df$altitude <- ifelse(is.na(df$baro_altitude), df$geo_altitude, df$baro_altitude)
  df$altitude_band <- altitude_band(df$on_ground, df$baro_altitude, df$geo_altitude)
  df$airborne <- !(df$on_ground %in% TRUE)
  df
}

# Sidebar filters. NULL / empty airlines or bands mean "no filter".
filter_states <- function(
  df,
  region_id = "world",
  airlines = NULL,
  bands = NULL,
  airborne_only = FALSE
) {
  df <- crop_to_region(df, region_id)
  if (length(airlines) > 0) {
    df <- df[df$airline_code %in% airlines, , drop = FALSE]
  }
  if (length(bands) > 0) {
    df <- df[df$altitude_band %in% bands, , drop = FALSE]
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

top_countries <- function(df, n = 5) {
  counts <- sort(table(df$origin_country), decreasing = TRUE)
  utils::head(counts, n)
}
