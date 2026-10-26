# Deploys the app to shinyapps.io (see docs/shiny_deployment.md).
# Run from the repo folder with source("deploy.R"), after
# rsconnect::setAccountInfo() (section 3).
# Run it again to update the app: the URL stays the same.

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Install rsconnect first: install.packages(\"rsconnect\")")
}
if (nrow(rsconnect::accounts()) == 0) {
  stop(
    "No shinyapps.io account set up. Paste the rsconnect::setAccountInfo(...) ",
    "command from shinyapps.io (Account > Tokens) into the console first."
  )
}

# Upload only what the app needs. Everything else (context/, docs/, tests/,
# data-raw/, the notes files) stays local: context/ holds the lecturer's notes.
# .Renviron stays local too: OpenSky blocks shinyapps.io, so the hosted app
# runs on the sample and needs no credentials (docs/shiny_deployment.md).
files <- c(
  "app.R",
  list.files("R", full.names = TRUE),
  list.files("data", recursive = TRUE, full.names = TRUE),
  list.files("www", recursive = TRUE, full.names = TRUE)
)

rsconnect::deployApp(
  appDir = ".",
  appFiles = files,
  appName = "stat3037a-skystats",
  appTitle = "SkyStats (STAT3037A)",
  forceUpdate = TRUE
)
