# Deploying the app to shinyapps.io

We have to hand in both the GitHub repo and a published app. This doc explains how we publish it and how the OpenSky API works once the app is hosted. The app was deployed on 24 Oct with `deploy.R`; OpenSky turned out to block the server, so the hosted app shows the sample (section 1). It replaces stretch goal S5 in `docs/plan.md`, which is now required.

**Deploy by 24 Oct**, so there is time to fix problems before the 26 Oct deadline. The first deploy can take 10–20 minutes while the server installs the packages.

## 1. How the API works when the app is hosted

> **Confirmed on 24 Oct: OpenSky blocks shinyapps.io.** The hosted app is at <https://wjpfz8-luke-badenhorst.shinyapps.io/stat3037a-flights/>, and it always shows the bundled sample (badge: "Sample"). A test app on the same server could not open a connection to either `auth.opensky-network.org` or `opensky-network.org` (no reply within 15 seconds), while Google and GitHub answered in 0.1 seconds. So the server's internet works, and OpenSky silently drops connections from it, most likely because it blocks cloud data centres. No change to our code or credentials can fix this, and calling the API without signing in is blocked too. What we do instead:
>
> - **Hosted app:** recapture the sample shortly before submitting and redeploy (section 8), so the snapshot is recent.
> - **Class presentation:** run the app from a laptop in Positron, where live data works.
> - **README and write-up:** say why the hosted app shows a snapshot, so markers don't take it for a bug.
>
> The rest of this section describes how live mode works when OpenSky is reachable, as it is locally.

The app already works this way when you run it locally. Hosting changes nothing in the code.

- **The server calls OpenSky, not the visitor's browser.** The credentials stay on the server and visitors never see them.
- **All visitors share one snapshot.** `get_states()` in `R/data_api.R` keeps the snapshot in a cache for the whole R process and only calls OpenSky when the snapshot is more than 10 minutes old. So the lecturer, the class during the demo or anyone else all share the same call.
- **Credits are not a worry.** At most 144 calls a day × 4 credits = 576 of our 4,000 free daily credits. The host may run a few copies of the app, each with its own cache, but even 4 copies use about 2,300.
- **The app cannot break.** If OpenSky fails or we hit the rate limit, the app shows the last good snapshot, or else the bundled sample (`data/sample/states_sample.rds`). The badge in the top right always says which one is showing.
- **Idle apps go to sleep.** On the free plan the app stops after about 15 minutes without visitors. The next visitor waits 20–30 seconds for it to start, and it then fetches a fresh snapshot.
- **Our OpenSky account pays the credits.** Anyone who clones the repo without their own credentials gets sample mode, which the design allows for.

## 2. Which host

| Host | Secrets | Catch |
|---|---|---|
| **shinyapps.io** (our choice) | Upload a `.Renviron` file with the app (section 4). | Free plan: 5 apps, 25 active hours a month, which is plenty. Posit plans to retire it in 2027, after the deadline. |
| Posit Connect Cloud | Has a "secret variables" setting. | The free plan only deploys from **public** GitHub repos, and ours is private. It is also unclear whether free accounts get secrets. |

We use shinyapps.io because it works with the private repo as it is. One group member owns the account and deploys; everyone else just uses the URL.

## 3. One-time setup

1. Create a free account at <https://www.shinyapps.io>. The account name becomes part of the URL, for example `https://<account>.shinyapps.io/stat3037a-flights/`.
2. Install rsconnect in R: `install.packages("rsconnect")`.
3. On shinyapps.io, open **Account → Tokens → Show**, and copy the `rsconnect::setAccountInfo(...)` command. **Paste it into the R console only.** The token and secret give full control of the account, so never save them in a file in the repo.

## 4. Getting the OpenSky credentials onto the server

shinyapps.io has no settings page for secrets. Instead, rsconnect uploads a `.Renviron` file from the app folder along with the app, and R reads it when the app starts.

1. Create `.Renviron` in the repo folder (next to `app.R`) with the two lines from your personal `.Renviron`:

   ```
   OPENSKY_CLIENT_ID=...
   OPENSKY_CLIENT_SECRET=...
   ```

2. Check that git ignores it. `.gitignore` already lists `.Renviron`, so `git status` should not show it. **Never commit it.**

The uploaded files are private to our shinyapps.io account. The server only shows files in the `www/` folder to visitors. Ours holds the app's CSS and JavaScript (`app.css`, `app.js`, `planes.js`, `tour.js`), so never put a secret there.

Note: when R starts in the repo folder, it reads this project `.Renviron` instead of the one in your home folder. Because it holds the same two credentials, the app behaves the same locally.

## 5. Choosing which files to upload

By default rsconnect uploads **everything** in the folder. That includes files git ignores, like `context/course_notes.md` (the lecturer's notes, which must not be published). So the deploy script lists the files to upload:

| Upload | Leave out |
|---|---|
| `app.R` | `context/` (lecturer's material) |
| `R/` (Shiny sources it before `app.R`) | `docs/`, `tests/`, `data-raw/` |
| `data/` (lookups and the sample snapshot, about 0.5 MB) | `README.md`, `STATE.md`, `CLAUDE.md` |
| `www/` (the CSS and JavaScript; without it the map and the panels break) | `deploy.R`, `.git/` |
| `.Renviron` (the credentials) | |

If a new folder the app needs is added later, add it to the list in `deploy.R` too.

## 6. The deploy script

`deploy.R` at the repo root does the deploy. Shiny only runs `app.R` and the files in `R/`, so the app ignores it. Before deploying, it stops with a message if rsconnect is not installed, no shinyapps.io account is set up, or `.Renviron` is missing. The core of it:

```r
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
  appName = "stat3037a-flights",
  appTitle = "SkyStats (STAT3037A)",
  forceUpdate = TRUE
)
```

rsconnect reads our code to find the packages it needs (from `library()` calls and `pkg::fn()` calls), so every package must be installed locally before deploying. `.gitignore` lists `rsconnect/`: rsconnect creates that folder after the first deploy to remember the app's ID, and it is only useful on the computer that deploys.

To deploy, open the repo in Positron and run `source("deploy.R")`. To update the app later, run it again: the URL stays the same.

## 7. Checks after deploying

1. **Open the URL and look at the badge.** On shinyapps.io it says "Sample" with an "OpenSky request failed … Connection timeout" message, which is expected (section 1). Check that the sample time is recent. Any other message means something else is wrong (see section 8).
2. **Run each method once** (Spatial autocorrelation, Point patterns, Regression) in at least one region.
3. **Read the logs** if anything fails: the app's **Logs** tab on shinyapps.io, or `rsconnect::showLogs(appName = "stat3037a-flights")`.
4. **Check memory.** The free plan gives each app a limited amount of memory. If the logs show the app being killed, try a smaller region or hex size first.
5. **Test on a phone or another computer** that has never opened the app, to see what the lecturer will see.

## 8. Risks and what to do

| Risk | What happens | What to do |
|---|---|---|
| **Happened (24 Oct):** OpenSky does not answer requests from shinyapps.io's servers. Its docs don't mention this. | The badge shows "Sample" with a "request failed … Connection timeout" message. The app still works. | Recapture the sample shortly before submitting (`Rscript data-raw/capture_sample.R` from the repo folder, 4 credits) and run `source("deploy.R")`, so the sample is recent. The README says why. Recapture on a weekday afternoon UTC for the fullest sky: the 24 Oct Saturday-morning capture has 6,811 aircraft, against 13,233 on a Tuesday afternoon. |
| Wrong or missing credentials in `.Renviron` | Sample mode, with "No OpenSky credentials set". | Fix `.Renviron` and redeploy. |
| A package fails to install on the server | The deploy stops with an error in the build log. | Read the log. Usually updating the package locally and redeploying fixes it. |
| We use up the 25 free active hours | The app goes offline until next month. | Unlikely: the app sleeps when idle. Avoid leaving the app open in a browser tab for days. |
| The credentials leak (for example `.Renviron` gets committed) | Someone else could use our OpenSky credits. | Delete the API client on the OpenSky account page, create a new one, and update `.Renviron`. |

## 9. Hand-in

- The app URL is at the top of `README.md`, so it is in the repo too.
- Submit the GitHub repo link and the app URL. The repo is private, so the lecturer will need access to it (add them as a collaborator, or make the repo public before submitting).
- Leave the app deployed until marks are out.
