# Deploys the app to shinyapps.io (see docs/shiny_deployment.md).
# Run from the repo folder with source("deploy.R"), after
# rsconnect::setAccountInfo() (section 3) and with .Renviron in place (section 4).
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
if (!file.exists(".Renviron")) {
  stop(
    "Create .Renviron with the OpenSky credentials first ",
    "(docs/shiny_deployment.md, section 4)."
  )
}

# Upload only what the app needs. Everything else (context/, docs/, tests/,
# data-raw/, the notes files) stays local: context/ holds the lecturer's notes.
files <- c(
  "app.R",
  ".Renviron",
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
