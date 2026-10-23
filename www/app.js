// Global Flights: client-side behaviour for the map-first layout.
//   - shared map panes shown, hidden or dimmed from R (set_pane())
//   - tab switching from any [data-tab] element, and the tab bar highlight
//   - folding panels (fold_panel())
//   - results cards that expand (.btn-more inside .results-card), and their
//     busy progress line
//   - the method tabs' setup box (settings_panel() in .setup-mode)
//   - region buttons in a method tab's "region refused" message
//   - numbers that count up (.count-up outputs, and .count-up spans inside
//     a results card's HTML output)

(function () {
  "use strict";

  var reduceMotion =
    window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---- Shared map panes ----------------------------------------------------

  // The pane messages can arrive before the map exists, so keep the latest
  // state per pane and apply it once the map is ready (see shared_map()).
  var map = null;
  var paneStates = {};

  // A method's results card ("<pane>-card") shows a progress line while busy.
  function applyBusy(pane) {
    var card = document.getElementById(pane + "-card");
    if (card) card.classList.toggle("busy", paneStates[pane] === "busy");
  }

  function applyPane(pane) {
    if (!map) return;
    var el = map.getPane(pane);
    if (!el) return;
    var state = paneStates[pane];
    el.classList.add("gf-pane");
    el.classList.toggle("pane-hidden", state === "hidden");
    el.classList.toggle("pane-busy", state === "busy");
    // A popup from a layer that just faded out would be left floating.
    if (state === "hidden") map.closePopup();
  }

  // Keep --gf-br-height at the height of the bottom-right control stack
  // (zoom, legend, attribution), so results cards stop above it. It changes
  // when the altitude legend is added or removed.
  function watchControlCorner(m) {
    var corner = m.getContainer().querySelector(".leaflet-bottom.leaflet-right");
    if (!corner) return;
    function update() {
      var top = corner.getBoundingClientRect().top;
      var height = Math.max(0, window.innerHeight - top);
      document.documentElement.style.setProperty("--gf-br-height", Math.ceil(height) + "px");
    }
    update();
    if (window.ResizeObserver) new ResizeObserver(update).observe(corner);
    window.addEventListener("resize", update);
  }

  window.gfMapReady = function (m) {
    map = m;
    Object.keys(paneStates).forEach(applyPane);
    watchControlCorner(m);
  };

  // ---- Tabs ----------------------------------------------------------------

  function placeSlider() {
    var bar = document.querySelector(".tab-bar");
    if (!bar) return;
    var slider = bar.querySelector(".tab-slider");
    var btn = bar.querySelector(".tab-btn.active");
    if (!slider || !btn) return;
    slider.style.left = btn.offsetLeft + "px";
    slider.style.width = btn.offsetWidth + "px";
    // Animate moves only after the first placement.
    if (!bar.classList.contains("ready")) {
      requestAnimationFrame(function () {
        bar.classList.add("ready");
      });
    }
  }

  function showTabButton(id) {
    document.querySelectorAll(".tab-btn").forEach(function (b) {
      var on = b.getAttribute("data-tab") === id;
      b.classList.toggle("active", on);
      if (on) b.setAttribute("aria-current", "page");
      else b.removeAttribute("aria-current");
    });
    placeSlider();
  }

  function setBodyTab(id) {
    var body = document.body;
    Array.prototype.slice.call(body.classList).forEach(function (c) {
      if (c.indexOf("tab-") === 0) body.classList.remove(c);
    });
    body.classList.add("tab-" + id);
  }

  // ---- Folding panels ------------------------------------------------------

  function toggleFold(head) {
    var panel = head.closest(".fold-panel");
    if (!panel) return;
    // .folding keeps the body clipped while it animates open.
    panel.classList.add("folding");
    var closed = panel.classList.toggle("closed");
    head.setAttribute("aria-expanded", closed ? "false" : "true");
    clearTimeout(panel._gfFoldTimer);
    panel._gfFoldTimer = setTimeout(function () {
      panel.classList.remove("folding");
    }, 450);
  }

  // ---- Results cards -------------------------------------------------------

  // Generic: any .btn-more toggles .expanded on its .results-card. The label
  // swaps between data-more and data-less.
  function toggleMore(btn) {
    var card = btn.closest(".results-card");
    if (!card) return;
    var expanded = card.classList.toggle("expanded");
    btn.textContent = expanded
      ? btn.getAttribute("data-less") || "Show less"
      : btn.getAttribute("data-more") || "Show all results";
    btn.setAttribute("aria-expanded", expanded ? "true" : "false");

    // Tables and plots inside fit themselves to the new width once the card
    // has finished widening.
    var done = false;
    function fit(e) {
      if (e && (e.target !== card || e.propertyName !== "width")) return;
      if (done) return;
      done = true;
      card.removeEventListener("transitionend", fit);
      window.dispatchEvent(new Event("resize"));
    }
    card.addEventListener("transitionend", fit);
    setTimeout(fit, 700);
  }

  // ---- Setup box (a method's settings panel in .setup-mode) ----------------

  // R opens the box on a method tab's first visit and closes it on Run or
  // when the tab is left. Escape and the dim overlay close it only once the
  // panel's own Run button has been pressed (panel._gfRan), i.e. when it was
  // reopened from "Settings guide".
  var setupDim = null;

  function openSetupPanel() {
    return document.querySelector(".settings-panel.setup-mode:not(.setup-closing)");
  }

  function openSetup(panel) {
    clearTimeout(panel._gfSetupTimer);
    panel.classList.remove("setup-closing");
    panel.classList.add("setup-mode");
    document.body.classList.add("setup-open");
  }

  function closeSetup(panel) {
    if (!panel.classList.contains("setup-mode") || panel.classList.contains("setup-closing")) {
      if (!openSetupPanel()) document.body.classList.remove("setup-open");
      return;
    }
    document.body.classList.remove("setup-open");
    function finish() {
      panel.classList.remove("setup-mode", "setup-closing");
    }
    // A panel in a hidden tab has nothing to animate.
    if (!panel.getClientRects().length) {
      finish();
      return;
    }
    panel.classList.add("setup-closing");
    clearTimeout(panel._gfSetupTimer);
    panel._gfSetupTimer = setTimeout(finish, reduceMotion ? 150 : 400);
  }

  function dismissSetup() {
    var panel = openSetupPanel();
    if (panel && panel._gfRan) closeSetup(panel);
  }

  // ---- Count-up numbers ----------------------------------------------------

  // "13,233" -> {value: 13233, suffix: ""}; "87%" -> {value: 87, suffix: "%"};
  // anything else ("-", "") -> null.
  function parseNumber(text) {
    var m = String(text)
      .trim()
      .match(/^(-?[\d,]*\.?\d+)(%?)$/);
    if (!m) return null;
    return { value: parseFloat(m[1].replace(/,/g, "")), suffix: m[2] };
  }

  function formatNumber(value, digits, suffix) {
    return (
      value.toLocaleString("en-US", {
        minimumFractionDigits: digits,
        maximumFractionDigits: digits
      }) + suffix
    );
  }

  // Called on shiny:value for a .count-up output: Shiny renders the number
  // already on screen, then this animates it to the new value.
  function countUp(event) {
    var el = event.target;
    var finalText = String(event.value);
    var from = parseNumber(el.textContent);
    var start = from ? from.value : 0;
    var shown = animateNumber(el, start, finalText);
    if (shown !== null) event.value = shown;
  }

  // Called on shiny:value for an HTML output (such as a results card's
  // summary_ui()): remember the numbers on screen, then, once Shiny has put
  // the new content in, count each .count-up span up from the old number at
  // the same place (or from zero).
  function countUpInside(event) {
    var el = event.target;
    if (reduceMotion || !window.MutationObserver) return;
    var old = Array.prototype.map.call(el.querySelectorAll(".count-up"), function (n) {
      var p = parseNumber(n.textContent);
      return p ? p.value : 0;
    });
    var mo = new MutationObserver(function () {
      mo.disconnect();
      el.querySelectorAll(".count-up").forEach(function (n, i) {
        if (n.classList.contains("shiny-bound-output")) return;
        var finalText = n.textContent;
        var shown = animateNumber(n, old[i] || 0, finalText);
        if (shown !== null) n.textContent = shown;
      });
    });
    mo.observe(el, { childList: true });
    setTimeout(function () {
      mo.disconnect();
    }, 2000);
  }

  // Animate el's text from start to finalText. Returns the text to show
  // first, or null when there is nothing to animate.
  function animateNumber(el, start, finalText) {
    var to = parseNumber(finalText);
    if (el._gfCount) cancelAnimationFrame(el._gfCount);
    el._gfCount = null;
    if (reduceMotion || !to || start === to.value) return null;

    var digits = parseInt(el.getAttribute("data-digits") || "0", 10);
    var duration = 1400;
    var t0 = null;

    function step(t) {
      if (t0 === null) t0 = t;
      var p = Math.min((t - t0) / duration, 1);
      var eased = 1 - Math.pow(1 - p, 3);
      if (p < 1) {
        el.textContent = formatNumber(start + (to.value - start) * eased, digits, to.suffix);
        el._gfCount = requestAnimationFrame(step);
      } else {
        el.textContent = finalText;
        el._gfCount = null;
      }
    }
    el._gfCount = requestAnimationFrame(step);
  }

  // ---- Wiring ----------------------------------------------------------------

  document.addEventListener("DOMContentLoaded", function () {
    // The app opens on Home.
    showTabButton("home");
    setBodyTab("home");

    document.addEventListener("click", function (e) {
      var tab = e.target.closest("[data-tab]");
      if (tab && window.Shiny && Shiny.setInputValue) {
        var id = tab.getAttribute("data-tab");
        // Move the highlight at once; the server confirms with tab-changed.
        if (tab.classList.contains("tab-btn")) showTabButton(id);
        Shiny.setInputValue("tab_click", id, { priority: "event" });
        return;
      }
      var head = e.target.closest(".fold-head");
      if (head) {
        toggleFold(head);
        return;
      }
      var more = e.target.closest(".btn-more");
      if (more) {
        toggleMore(more);
        return;
      }
      var guide = e.target.closest(".guide-link");
      if (guide) {
        e.preventDefault();
        var guided = guide.closest(".settings-panel");
        if (guided) openSetup(guided);
        return;
      }
      // Run analysis: close the box at once (R confirms with "setup") and
      // remember that this tab has run.
      var run = e.target.closest(".btn-run");
      if (run) {
        var ran = run.closest(".settings-panel");
        if (ran) {
          ran._gfRan = true;
          closeSetup(ran);
        }
        return;
      }
      var pick = e.target.closest(".region-btn");
      if (pick && window.Shiny && Shiny.setInputValue) {
        Shiny.setInputValue("region_pick", pick.getAttribute("data-region"), { priority: "event" });
      }
    });

    // The dim overlay behind the setup box.
    setupDim = document.createElement("div");
    setupDim.className = "setup-dim";
    document.body.appendChild(setupDim);
    setupDim.addEventListener("click", dismissSetup);

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        dismissSetup();
        return;
      }
      if (e.key !== "Enter" && e.key !== " ") return;
      var head = e.target.closest && e.target.closest(".fold-head");
      if (head) {
        e.preventDefault();
        toggleFold(head);
      }
    });

    // Keep the highlight under the active tab when the tab widths change
    // (web font loaded, window resized, narrow-screen styles).
    window.addEventListener("resize", placeSlider);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(placeSlider);
    var bar = document.querySelector(".tab-bar");
    if (bar && window.ResizeObserver) new ResizeObserver(placeSlider).observe(bar);

    if (window.jQuery) {
      jQuery(document).on("shiny:value", function (e) {
        var cl = e.target.classList;
        if (!cl) return;
        if (cl.contains("count-up")) countUp(e);
        else if (cl.contains("shiny-html-output") && e.target.closest(".results-card")) countUpInside(e);
      });
    }

    if (window.Shiny && Shiny.addCustomMessageHandler) {
      Shiny.addCustomMessageHandler("map-pane", function (msg) {
        paneStates[msg.pane] = msg.state;
        applyPane(msg.pane);
        applyBusy(msg.pane);
      });
      Shiny.addCustomMessageHandler("setup", function (msg) {
        var panel = document.getElementById(msg.id);
        if (!panel) return;
        if (msg.open) openSetup(panel);
        else closeSetup(panel);
      });
      Shiny.addCustomMessageHandler("tab-changed", function (msg) {
        showTabButton(msg.tab);
        setBodyTab(msg.tab);
      });
    }
  });
})();
