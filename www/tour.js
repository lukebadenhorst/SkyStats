// SkyStats: the "How this app works" tour on the Home tab, which opens
// the class presentation. The steps and the regions come from the JSON in
// #tour-data (tour_steps and tour_regions() in R/mod_home.R).
//   - .tour-start (the hero button) starts it: body.touring fades the haze
//     and the hero out and raises the tour card in the bottom left
//   - Next / Back, the arrow keys and PageDown / PageUp (a presentation
//     clicker) move between steps; Escape ends it; so does leaving Home
//   - each step's action moves the shared map; leaving the step undoes it
// The "tour" pane holds the LISA hexes R draws on the first start; it is
// shown and hidden through app.js's gfSetPane(), like R's set_pane().

(function () {
  "use strict";

  var SWAP_MS = 220; // the card's text fades out, then changes
  var FLOW_START_MS = 300; // the pipeline boxes light up after this ...
  var FLOW_STEP_MS = 350; // ... one every this
  var REGION_MS = 2600; // the regions step moves on every this
  var HOME_VIEW = { center: [25, 10], zoom: 2 }; // shared_map()'s first view
  var WORLD_VIEW = { center: [30, 10], zoom: 2 };
  var COVERAGE_VIEW = { center: [0, 20], zoom: 3 };
  var FLOW = ["Fetch", "Clean", "Filter", "Project", "Analyse"];

  var mql = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)");
  function still() {
    return !!(mql && mql.matches);
  }

  var data = null;
  var cur = -1; // the step on screen, or -1 when not touring
  var card, body, dots, nextBtn;

  // What the current step has set, so leaving it can undo it all.
  var timers = [];
  var regionTimer = null;
  var regionRect = null;
  var ringed = null;
  var lisaShown = false;

  function later(fn, ms) {
    timers.push(setTimeout(fn, ms));
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function getMap() {
    var w = window.HTMLWidgets && HTMLWidgets.find("#map");
    return w && w.getMap ? w.getMap() : null;
  }

  function regionById(id) {
    var r = data.regions.filter(function (x) {
      return x.id === id;
    });
    return r.length ? r[0] : null;
  }

  // ---- Map moves (instant under reduced motion) ------------------------------

  function fly(view, duration) {
    var map = getMap();
    if (!map) return;
    if (still()) map.setView(view.center, view.zoom, { animate: false });
    else map.flyTo(view.center, view.zoom, { duration: duration || 1 });
  }

  // Clear of the top bar, and of the tour card when there is room beside it.
  function flyBounds(bounds) {
    var map = getMap();
    if (!map) return;
    var beside = card.offsetWidth + 48;
    var left = window.innerWidth - beside >= 360 ? beside : 40;
    var pad = { paddingTopLeft: [left, 70], paddingBottomRight: [40, 40] };
    if (still()) map.fitBounds(bounds, Object.assign({ animate: false }, pad));
    else map.flyToBounds(bounds, Object.assign({ duration: 1.2 }, pad));
  }

  // ---- Step actions ----------------------------------------------------------

  function showRegion(i) {
    var map = getMap();
    if (!map || !window.L) return;
    var r = data.regions[i % data.regions.length];
    if (regionRect) map.removeLayer(regionRect);
    regionRect = L.rectangle(r.bounds, {
      color: "#1d6fd8",
      weight: 2,
      fillColor: "#1d6fd8",
      fillOpacity: 0.06,
      dashArray: "6 4",
      interactive: false
    });
    regionRect.bindTooltip(escapeHtml(r.label + " · " + r.crs), {
      permanent: true,
      direction: "center",
      className: "region-label"
    });
    regionRect.addTo(map);
    flyBounds(r.bounds);
  }

  var actions = {
    world: function () {
      fly(WORLD_VIEW);
    },
    // The ring goes on the badge's output container, which survives the badge
    // being re-rendered by a data refresh.
    badge: function () {
      ringed = document.getElementById("source_badge");
      if (ringed) ringed.classList.add("tour-ring");
    },
    // The boxes light up once the card shows the step (see render()).
    pipeline: function () {},
    // The planes would bury the hexes, so they step aside meanwhile.
    lisa: function () {
      if (window.gfSetPane) {
        window.gfSetPane("tour", "shown");
        window.gfSetPane("planes", "hidden");
      }
      lisaShown = true;
      var europe = regionById("europe");
      if (europe) flyBounds(europe.bounds);
    },
    regions: function () {
      var i = 0;
      showRegion(i);
      regionTimer = setInterval(function () {
        showRegion(++i);
      }, REGION_MS);
    },
    coverage: function () {
      fly(COVERAGE_VIEW, 1.4);
    }
  };

  // Undo everything the current step set.
  function undo() {
    timers.forEach(clearTimeout);
    timers = [];
    clearInterval(regionTimer);
    regionTimer = null;
    if (regionRect) {
      var map = getMap();
      if (map) map.removeLayer(regionRect);
      regionRect = null;
    }
    if (ringed) {
      ringed.classList.remove("tour-ring");
      ringed = null;
    }
    if (lisaShown) {
      if (window.gfSetPane) {
        window.gfSetPane("tour", "hidden");
        // Back on only while still on Home: a new tab sets the planes pane
        // itself (app.R), whichever message arrives first.
        if (document.body.classList.contains("tab-home")) window.gfSetPane("planes", "shown");
      }
      lisaShown = false;
    }
  }

  // ---- The card ----------------------------------------------------------------

  function stepHtml(s, i) {
    var flow = "";
    if (s.action === "pipeline") {
      flow =
        '<div class="tour-flow">' +
        FLOW.map(function (name) {
          return '<span class="tour-flow-step">' + name + "</span>";
        }).join('<span class="tour-flow-sep">›</span>') +
        "</div>";
    }
    // Points may hold simple HTML (<b>), written in R/mod_home.R.
    var points = [].concat(s.points).map(function (p) {
      return "<li>" + p + "</li>";
    });
    return (
      '<div class="tour-step">Step ' + (i + 1) + " of " + data.steps.length + "</div>" +
      "<h3>" + escapeHtml(s.title) + "</h3>" +
      flow +
      "<ul>" + points.join("") + "</ul>"
    );
  }

  function lightFlow() {
    body.querySelectorAll(".tour-flow-step").forEach(function (box, k) {
      later(function () {
        box.classList.add("lit");
      }, FLOW_START_MS + k * FLOW_STEP_MS);
    });
  }

  function render(i) {
    undo();
    cur = i;
    var s = data.steps[i];
    body.classList.add("swap");
    later(
      function () {
        body.innerHTML = stepHtml(s, i);
        body.classList.remove("swap");
        if (s.action === "pipeline") lightFlow();
      },
      still() ? 0 : SWAP_MS
    );
    dots.querySelectorAll("i").forEach(function (d, k) {
      d.classList.toggle("on", k === i);
    });
    nextBtn.textContent = i === data.steps.length - 1 ? "Start exploring" : "Next";
    var act = actions[s.action];
    if (act) act();
  }

  function start() {
    if (!data || !data.steps.length) return;
    document.body.classList.add("touring");
    render(0);
    // Space / Enter (and many clickers) then press Next.
    nextBtn.focus({ preventScroll: true });
  }

  // flyHome: back to the Home view (not when the tour ends by leaving Home:
  // the new tab moves the map itself).
  function finish(flyHome) {
    if (cur < 0) return;
    undo();
    cur = -1;
    document.body.classList.remove("touring");
    if (card.contains(document.activeElement)) {
      // Blur, not back to "How this app works": a clicker's next Enter or
      // Space would start the tour again.
      document.activeElement.blur();
    }
    if (flyHome) fly(HOME_VIEW);
  }

  function next() {
    if (cur < data.steps.length - 1) render(cur + 1);
    else finish(true);
  }

  function back() {
    if (cur > 0) render(cur - 1);
    else finish(true);
  }

  // ---- Wiring ------------------------------------------------------------------

  document.addEventListener("DOMContentLoaded", function () {
    var json = document.getElementById("tour-data");
    card = document.querySelector(".tour-card");
    if (!json || !card) return;
    try {
      data = JSON.parse(json.textContent);
    } catch (err) {
      return;
    }
    body = card.querySelector(".tour-body");
    dots = card.querySelector(".tour-dots");
    nextBtn = card.querySelector(".tour-next");
    data.steps.forEach(function () {
      dots.appendChild(document.createElement("i"));
    });

    document.addEventListener("click", function (e) {
      if (e.target.closest(".tour-start")) {
        start();
        return;
      }
      if (cur < 0) return;
      if (e.target.closest(".tour-next")) next();
      else if (e.target.closest(".tour-prev")) back();
    });

    // Capture phase, so an arrow key on the focused map steps the tour
    // instead of panning it. Typing in a field is left alone.
    document.addEventListener(
      "keydown",
      function (e) {
        if (cur < 0 || e.altKey || e.ctrlKey || e.metaKey) return;
        var t = e.target;
        if (t && t.closest && t.closest("input, select, textarea, [contenteditable]")) return;
        var k = e.key;
        if (k === "ArrowRight" || k === "PageDown") next();
        else if (k === "ArrowLeft" || k === "PageUp") back();
        else if (k === "Escape") finish(true);
        else return;
        e.preventDefault();
        e.stopPropagation();
      },
      true
    );

    // Leaving Home ends the tour (app.js sets body.tab-<id> on tab-changed).
    new MutationObserver(function () {
      if (cur >= 0 && !document.body.classList.contains("tab-home")) finish(false);
    }).observe(document.body, { attributes: true, attributeFilter: ["class"] });
  });
})();
