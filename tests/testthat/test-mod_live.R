library(shiny)
library(bslib)
for (f in c("mod_common.R", "mod_live.R")) source(file.path(root, "R", f))

sample_aircraft <- prep_states(readRDS(sample_path)$data)

# The mock session ignores custom messages: swap in a recorder on the root
# session (R6 locks its bindings) and return the list it fills.
record_messages <- function(session) {
  root <- session$rootScope()
  msgs <- new.env()
  msgs$all <- list()
  unlockBinding("sendCustomMessage", root)
  root$sendCustomMessage <- function(type, message) {
    msgs$all[[length(msgs$all) + 1]] <- list(type = type, message = message)
  }
  msgs
}

of_type <- function(msgs, type) Filter(function(m) m$type == type, msgs$all)

test_that("planes-data carries no popup HTML", {
  aircraft <- reactiveVal(sample_aircraft)
  testServer(mod_live_server, args = list(aircraft = aircraft, snapshot_id = reactive("s1")), {
    msgs <- record_messages(session)
    aircraft(sample_aircraft[1:50, ])
    session$flushReact()
    data_msgs <- of_type(msgs, "planes-data")
    expect_gte(length(data_msgs), 1)
    m <- data_msgs[[length(data_msgs)]]$message
    expect_null(m$popup)
    expect_length(m$lon, 50)
    expect_equal(m$click_input, session$ns("plane_click"))
  })
})

test_that("a plane click is answered with that plane's popup, and stale clicks are ignored", {
  aircraft <- reactiveVal(sample_aircraft[1:50, ])
  testServer(mod_live_server, args = list(aircraft = aircraft, snapshot_id = reactive("s1")), {
    msgs <- record_messages(session)
    session$flushReact()
    rev_now <- of_type(msgs, "planes-data")[[1]]$message$rev

    session$setInputs(plane_click = list(i = 3, rev = rev_now, snapshot = "s1", nonce = 1))
    popups <- of_type(msgs, "plane-popup")
    expect_length(popups, 1)
    expect_equal(popups[[1]]$message$i, 3)
    expect_equal(popups[[1]]$message$rev, rev_now)
    expect_equal(popups[[1]]$message$html, aircraft_popup(sample_aircraft[3, ]))

    # The filters change: a click made on the old data gets no answer.
    aircraft(sample_aircraft[51:60, ])
    session$flushReact()
    session$setInputs(plane_click = list(i = 3, rev = rev_now, snapshot = "s1", nonce = 2))
    expect_length(of_type(msgs, "plane-popup"), 1)

    # An index past the end is ignored too.
    new_rev <- tail(of_type(msgs, "planes-data"), 1)[[1]]$message$rev
    session$setInputs(plane_click = list(i = 99, rev = new_rev, snapshot = "s1", nonce = 3))
    expect_length(of_type(msgs, "plane-popup"), 1)
  })
})
