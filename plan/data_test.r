library(httr2)
library(purrr)
library(dplyr)

client <- oauth_client(
  id = Sys.getenv("OPENSKY_CLIENT_ID"),
  secret = Sys.getenv("OPENSKY_CLIENT_SECRET"),
  token_url = "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"
)

day_start <- as.numeric(as.POSIXct(Sys.Date() - 1, tz = "UTC"))
windows <- seq(day_start, day_start + 22 * 3600, by = 7200) # 12 × 2h

get_window <- function(begin) {
  request("https://opensky-network.org/api/flights/all") |>
    req_url_query(begin = begin, end = begin + 7200) |>
    req_oauth_client_credentials(client) |>
    req_error(is_error = \(r) resp_status(r) >= 400 && resp_status(r) != 404) |>
    req_perform() |>
    (\(r) {
      if (resp_status(r) == 404) {
        NULL
      } else {
        resp_body_json(r, simplifyVector = TRUE)
      }
    })()
}

flights_yday <- map(windows, get_window, .progress = TRUE) |> list_rbind()

routes <- flights_yday |>
  filter(!is.na(estDepartureAirport), !is.na(estArrivalAirport)) |>
  count(estDepartureAirport, estArrivalAirport, sort = TRUE)
