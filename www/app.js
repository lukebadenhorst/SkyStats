// Global Flights: client-side behaviour for the map-first layout.
//   - shared map panes shown, hidden or dimmed from R (set_pane())
//   - tab switching from any [data-tab] element, and the tab bar highlight
//   - folding panels (fold_panel())
//   - results cards that expand (.btn-more inside .results-card)
//   - numbers that count up (.count-up outputs)

(function () {
  "use strict";

  var reduceMotion =
    window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---- Shared map panes ----------------------------------------------------

  // The pane messages can arrive before the map exists, so keep the latest
  // state per pane and apply it once the map is ready (see shared_map()).
  var map = null;
  var paneStates = {};

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
    var to = parseNumber(finalText);
    if (el._gfCount) cancelAnimationFrame(el._gfCount);
    el._gfCount = null;
    if (reduceMotion || !to) return;

    var from = parseNumber(el.textContent);
    var start = from ? from.value : 0;
    if (start === to.value) return;
    var digits = parseInt(el.getAttribute("data-digits") || "0", 10);
    var duration = 1400;
    var t0 = null;

    event.value = formatNumber(start, digits, to.suffix);

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
      if (more) toggleMore(more);
    });

    document.addEventListener("keydown", function (e) {
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
        if (e.target.classList && e.target.classList.contains("count-up")) countUp(e);
      });
    }

    if (window.Shiny && Shiny.addCustomMessageHandler) {
      Shiny.addCustomMessageHandler("map-pane", function (msg) {
        paneStates[msg.pane] = msg.state;
        applyPane(msg.pane);
      });
      Shiny.addCustomMessageHandler("tab-changed", function (msg) {
        showTabButton(msg.tab);
        setBodyTab(msg.tab);
      });
    }
  });
})();
