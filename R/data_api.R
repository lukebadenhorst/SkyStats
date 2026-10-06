# OpenSky state vectors: fetch, parse, cache, and fall back to the sample.
#
# get_states() is the only function the app calls. It returns a list:
#   data    tibble of parsed state vectors (one row per aircraft)
#   time    POSIXct snapshot time (UTC)
#   source  "live" | "cache" | "sample"
#   message why we are not live (NULL when live)

opensky_token_url <- "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
opensky_states_url <- "https://opensky-network.org/api/states/all"
sample_states_path <- file.path("data", "sample", "states_sample.rds")

opensky_has_credentials <- function() {
  nzchar(Sys.getenv("OPENSKY_CLIENT_ID")) &&
    nzchar(Sys.getenv("OPENSKY_CLIENT_SECRET"))
}

opensky_client <- function() {
  httr2::oauth_client(
    id = Sys.getenv("OPENSKY_CLIENT_ID"),
    secret = Sys.getenv("OPENSKY_CLIENT_SECRET"),
    token_url = opensky_token_url
  )
}

# ---- Parsing ---------------------------------------------------------------

# State vector fields by position (1-based), from the OpenSky REST docs.
# Index 13 (sensors) and 16 (spi) are not used. 18 (category) only comes back
# with extended = 1.
state_fields <- list(
  icao24 = list(i = 1, na = NA_character_, cast = as.character),
  callsign = list(i = 2, na = NA_character_, cast = as.character),
  origin_country = list(i = 3, na = NA_character_, cast = as.character),
  time_position = list(i = 4, na = NA_real_, cast = as.numeric),
  last_contact = list(i = 5, na = NA_real_, cast = as.numeric),
  longitude = list(i = 6, na = NA_real_, cast = as.numeric),
  latitude = list(i = 7, na = NA_real_, cast = as.numeric),
  baro_altitude = list(i = 8, na = NA_real_, cast = as.numeric),
  on_ground = list(i = 9, na = NA, cast = as.logical),
  velocity = list(i = 10, na = NA_real_, cast = as.numeric),
  true_track = list(i = 11, na = NA_real_, cast = as.numeric),
  vertical_rate = list(i = 12, na = NA_real_, cast = as.numeric),
  geo_altitude = list(i = 14, na = NA_real_, cast = as.numeric),
  squawk = list(i = 15, na = NA_character_, cast = as.character),
  position_source = list(i = 17, na = NA_integer_, cast = as.integer),
  category = list(i = 18, na = NA_integer_, cast = as.integer)
)

# `body` is the /states/all JSON parsed with simplifyVector = FALSE.
parse_states <- function(body) {
  rows <- body$states
  if (is.null(rows)) {
    rows <- list()
  }
  cols <- lapply(state_fields, function(f) {
    vapply(
      rows,
      function(r) {
        v <- if (length(r) >= f$i) r[[f$i]] else NULL
        if (is.null(v)) f$na else f$cast(v)
      },
      f$na
    )
  })
  dplyr::as_tibble(cols)
}

states_time <- function(body) {
  as.POSIXct(body$time %||% NA_real_, origin = "1970-01-01", tz = "UTC")
}

# ---- Fetching --------------------------------------------------------------

# One live call to /states/all (4 credits). Errors on any HTTP failure.
fetch_states_live <- function() {
  resp <- httr2::request(opensky_states_url) |>
    httr2::req_url_query(extended = 1) |>
    httr2::req_oauth_client_credentials(opensky_client()) |>
    httr2::req_timeout(30) |>
    httr2::req_perform()
  body <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  list(data = parse_states(body), time = states_time(body))
}

load_sample_states <- function(path = sample_states_path) {
  if (!file.exists(path)) {
    stop("Sample snapshot not found at ", path, call. = FALSE)
  }
  readRDS(path)
}

# ---- Cache + fallback ------------------------------------------------------

# A store holds the 10-minute cache plus the last good live snapshot (kept
# without expiry so we can serve it if the API later fails). One store per R
# process means every Shiny session shares a single API call per 10 minutes.
new_states_store <- function(max_age = 600, min_force_interval = 60) {
  store <- new.env(parent = emptyenv())
  store$cache <- cachem::cache_mem(max_age = max_age)
  store$last_good <- NULL
  store$backoff_until <- -Inf
  store$min_force_interval <- min_force_interval
  store
}

states_store <- new_states_store()

get_states <- function(
  force = FALSE,
  store = states_store,
  fetch = fetch_states_live,
  has_creds = opensky_has_credentials(),
  sample_path = sample_states_path
) {
  now <- as.numeric(Sys.time())

  # A forced refresh is ignored if the cached snapshot is very recent.
  if (force && !is.null(store$last_good)) {
    age <- now - store$last_good$fetched_at
    if (age < store$min_force_interval) force <- FALSE
  }

  cached <- store$cache$get("states")
  if (!force && !cachem::is.key_missing(cached)) {
    return(cached)
  }

  fallback <- function(message) {
    if (!is.null(store$last_good)) {
      out <- store$last_good
      out$source <- "cache"
      out$message <- message
      return(out)
    }
    s <- load_sample_states(sample_path)
    list(data = s$data, time = s$time, source = "sample", message = message)
  }

  if (!has_creds) {
    return(fallback("No OpenSky credentials set, so showing the sample snapshot."))
  }
  if (now < store$backoff_until) {
    return(fallback("OpenSky rate limit reached, so polling is paused."))
  }

  result <- tryCatch(
    {
      live <- fetch()
      out <- list(
        data = live$data,
        time = live$time,
        source = "live",
        message = NULL,
        fetched_at = now
      )
      store$cache$set("states", out)
      store$last_good <- out
      out
    },
    httr2_http_429 = function(cnd) {
      wait <- suppressWarnings(as.numeric(
        httr2::resp_header(cnd$resp, "X-Rate-Limit-Retry-After-Seconds")
      ))
      store$backoff_until <- now + (if (is.na(wait)) 600 else wait)
      fallback("OpenSky rate limit reached, so polling is paused.")
    },
    error = function(cnd) {
      fallback(paste0("OpenSky request failed (", conditionMessage(cnd), ")."))
    }
  )
  result
}
