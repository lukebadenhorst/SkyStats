// Global Flights: the aircraft on the shared map, drawn as plane icons on one
// <canvas> inside the "planes" pane (so set_pane() fades it like any other
// layer). R sends the data as the "planes-data" message (mod_live_server()).
//   - each plane is rotated to its heading and coloured by altitude band, in
//     the palette for the current theme (data-bs-theme on <html>)
//   - airborne planes glide along their heading from the moment the data
//     reached the browser, for at most 15 minutes (none under reduced motion)
//   - hover shows a small dark tooltip, click opens the aircraft's popup
// Loaded after app.js: it chains onto window.gfMapReady.
//
// Speed: the whole world is about 13,000 planes, and a full redraw then takes
// tens of milliseconds. So, like Leaflet's own canvas renderer, the canvas is
// a little larger than the view, rides along with the map while it is
// dragged, is scaled during zoom animations, and is redrawn when the map
// stops. Only when a redraw is cheap (a zoomed-in view) is it redrawn on
// every map event. The planes are stamped from a sprite sheet of pre-rotated
// glyphs (one row per altitude band, one column per 5 degrees of heading).

(function () {
  "use strict";

  var GLYPH = "M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5z";
  var MAX_GLIDE_S = 900; // stop extrapolating after 15 minutes
  var GLIDE_FRAME_MS = 1000 / 30; // glide redraws at most 30 times a second
  var GLIDE_STEP_PX = 0.5; // ... and only once the fastest plane has moved this far
  var GLIDE_REF_SPEED = 350; // m/s; ignores the odd glitchy speed in the data
  var CHEAP_DRAW_MS = 6; // redraw on every map event when a draw takes less
  var PADDING = 0.1; // canvas extends this share of the view on each side
  var MARGIN = 20; // px outside the canvas still drawn (half-visible planes)
  var HIT_PX = 8; // hover and click radius
  var ROTATIONS = 72; // sprite sheet columns: 5 degrees each
  var SPRITE_PAD = 3; // px around the glyph for its shadow
  var M_PER_DEG = 111320;
  var DEG = Math.PI / 180;
  var MAX_LAT = 85.0511287798; // Web Mercator limit

  // Length-0 and length-1 vectors can arrive as null or a bare value.
  function arr(x) {
    if (Array.isArray(x)) return x;
    return x === null || x === undefined ? [] : [x];
  }

  function isNum(x) {
    return typeof x === "number" && isFinite(x);
  }

  function comma(x) {
    return Math.round(x).toLocaleString("en-US");
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function currentTheme() {
    return document.documentElement.getAttribute("data-bs-theme") === "dark" ? "dark" : "light";
  }

  var PlaneLayer = L.Layer.extend({
    initialize: function () {
      this._n = 0;
      this._palette = { light: {}, dark: {} };
      this._bands = [];
      this._maxSpd = 0;
      this._t0 = 0;
      this._shown = false;
      this._dirty = false;
      this._moving = false;
      this._lastDraw = 0;
      this._drawMs = Infinity; // cost of the last draw; unknown at first
      this._raf = null;
      this._hitN = 0;
      this._hitX = new Float32Array(0);
      this._hitY = new Float32Array(0);
      this._hitI = new Int32Array(0);
      this._hover = -1;
      var mql = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)");
      this._still = !!(mql && mql.matches);
      if (mql && mql.addEventListener) {
        var self = this;
        mql.addEventListener("change", function (e) {
          self._still = e.matches;
          self._redraw();
        });
      }
    },

    onAdd: function (map) {
      this._pane = map.getPane("planes");
      var canvas = (this._canvas = L.DomUtil.create("canvas", "plane-canvas"));
      if (map.options.zoomAnimation && L.Browser.any3d) L.DomUtil.addClass(canvas, "leaflet-zoom-animated");
      this._ctx = canvas.getContext("2d");
      this._pane.appendChild(canvas);
      this._tip = L.DomUtil.create("div", "plane-tip", map.getContainer());

      map.on(this._mapEvents(), this);

      // Theme switch: redraw with the other palette.
      var self = this;
      this._themeObs = new MutationObserver(function () {
        self._buildSprites();
        self._redraw();
      });
      this._themeObs.observe(document.documentElement, { attributes: true, attributeFilter: ["data-bs-theme"] });
      // Pane hidden (method tab): drop the tooltip; shown again: catch up.
      this._paneObs = new MutationObserver(function () {
        if (self._paneHidden()) self._hideTip();
        self._redraw();
      });
      this._paneObs.observe(this._pane, { attributes: true, attributeFilter: ["class"] });

      this._resize();
    },

    onRemove: function (map) {
      map.off(this._mapEvents(), this);
      this._themeObs.disconnect();
      this._paneObs.disconnect();
      if (this._raf) cancelAnimationFrame(this._raf);
      this._raf = null;
      L.DomUtil.remove(this._canvas);
      L.DomUtil.remove(this._tip);
    },

    _mapEvents: function () {
      return {
        movestart: this._onMoveStart,
        move: this._onMove,
        zoom: this._onZoom,
        zoomanim: this._onZoomAnim,
        moveend: this._onMoveEnd,
        viewreset: this._onMoveEnd,
        resize: this._resize,
        mousemove: this._onMouseMove,
        mouseout: this._hideTip,
        click: this._onClick
      };
    },

    // ---- Data ----------------------------------------------------------------

    setData: function (msg) {
      var lon = arr(msg.lon),
        lat = arr(msg.lat),
        hdg = arr(msg.hdg),
        spd = arr(msg.spd),
        band = arr(msg.band),
        ground = arr(msg.ground);
      var n = lon.length;
      this._n = n;
      this._callsign = arr(msg.callsign);
      this._popup = arr(msg.popup);
      this._alt = arr(msg.alt);
      this._spd = spd;
      this._ground = ground;
      this._lon = new Float64Array(n);
      this._lat = new Float64Array(n);
      this._vlon = new Float64Array(n); // degrees per second
      this._vlat = new Float64Array(n);
      this._rot = new Uint8Array(n); // sprite sheet column
      this._band = new Uint8Array(n); // sprite sheet row

      if (msg.palette) this._palette = msg.palette;
      this._bands = Object.keys(this._palette.light || {});
      var bandIndex = {};
      this._bands.forEach(function (b, i) {
        bandIndex[b] = i;
      });
      var unknown = Math.max(this._bands.indexOf("Unknown"), 0);
      var maxSpd = 0;

      for (var i = 0; i < n; i++) {
        this._lon[i] = lon[i];
        this._lat[i] = lat[i];
        var h = hdg[i];
        if (isNum(h)) {
          // No heading: column 0, pointing north.
          this._rot[i] = ((Math.round(h / (360 / ROTATIONS)) % ROTATIONS) + ROTATIONS) % ROTATIONS;
          var v = spd[i];
          if (ground[i] !== true && isNum(v) && v > 0) {
            this._vlat[i] = (v * Math.cos(h * DEG)) / M_PER_DEG;
            this._vlon[i] = (v * Math.sin(h * DEG)) / (M_PER_DEG * Math.max(Math.cos(lat[i] * DEG), 0.01));
            if (v > maxSpd) maxSpd = v;
          }
        }
        var b = bandIndex[band[i]];
        this._band[i] = b === undefined ? unknown : b;
      }
      this._maxSpd = maxSpd;

      // Glide from when this snapshot reached the browser: a filter change
      // resends the same snapshot and keeps the clock running.
      var snapshot = msg.snapshot === undefined ? null : msg.snapshot;
      if (this._snapshot === undefined || snapshot === null || snapshot !== this._snapshot) {
        this._t0 = performance.now();
      }
      this._snapshot = snapshot;
      this._hideTip();
      this._buildSprites();
      this._draw();
      this._loop();

      // Fade in on the first data only.
      if (!this._shown) {
        this._shown = true;
        var canvas = this._canvas;
        requestAnimationFrame(function () {
          L.DomUtil.addClass(canvas, "shown");
        });
      }
    },

    // The sprite sheet: every band (rows) at every 5 degrees (columns), with
    // a light drop shadow, for the current theme, icon size and pixel ratio.
    _buildSprites: function () {
      var dpr = window.devicePixelRatio || 1;
      var size = this._iconSize();
      var colours = this._palette[currentTheme()] || this._palette.light || {};
      var cell = Math.ceil((size + 2 * SPRITE_PAD) * dpr);
      var sheet = this._sheet || (this._sheet = document.createElement("canvas"));
      sheet.width = cell * ROTATIONS;
      sheet.height = cell * Math.max(this._bands.length, 1);
      var g = sheet.getContext("2d");
      var path = new Path2D(GLYPH);
      g.shadowColor = "rgba(0, 0, 0, 0.25)";
      g.shadowBlur = dpr;
      g.shadowOffsetY = dpr; // always below the plane, whatever its heading
      for (var b = 0; b < this._bands.length; b++) {
        g.fillStyle = colours[this._bands[b]] || "#d0d0d0";
        for (var r = 0; r < ROTATIONS; r++) {
          g.setTransform(dpr, 0, 0, dpr, (r + 0.5) * cell, (b + 0.5) * cell);
          g.rotate((r * 2 * Math.PI) / ROTATIONS);
          g.scale(size / 24, size / 24);
          g.translate(-12, -12);
          g.fill(path);
        }
      }
      this._cell = cell;
      this._spriteSize = size;
      this._spriteDpr = dpr;
    },

    _iconSize: function () {
      return this._map && this._map.getZoom() >= 6 ? 16 : 14;
    },

    // ---- Map events ----------------------------------------------------------

    _onMoveStart: function () {
      this._moving = true;
      this._hideTip();
    },

    // Dragging: the canvas moves with the map; redraw only if that is cheap.
    _onMove: function () {
      if (this._cheap()) this._drawOnce();
    },

    // A zoom step without Leaflet's zoom animation (flyTo, pinch): redraw if
    // cheap, otherwise hide the planes until the map stops.
    _onZoom: function () {
      // (The "zoom" that ends a zoom animation is handled by moveend.)
      if (this._map._animatingZoom || this._zoomAnimating) return;
      if (this._cheap()) this._drawOnce();
      else L.DomUtil.addClass(this._canvas, "flying");
    },

    // Leaflet's zoom animation: scale the canvas with the tiles.
    _onZoomAnim: function (e) {
      var map = this._map;
      this._zoomAnimating = true;
      var scale = map.getZoomScale(e.zoom, this._drawZoom);
      var pad = map.getSize().multiplyBy(0.5 + PADDING);
      var offset = pad
        .multiplyBy(-scale)
        .add(map.project(this._drawCenter, e.zoom))
        .subtract(map._getNewPixelOrigin(e.center, e.zoom));
      L.DomUtil.setTransform(this._canvas, offset, scale);
    },

    _onMoveEnd: function () {
      this._moving = false;
      this._zoomAnimating = false;
      this._draw();
      this._loop();
    },

    _cheap: function () {
      return this._drawMs < CHEAP_DRAW_MS;
    },

    // Leaflet fires "zoom" and "move" together: draw once per burst.
    _drawOnce: function () {
      if (this._drawQueued) return;
      this._drawQueued = true;
      var self = this;
      Promise.resolve().then(function () {
        self._drawQueued = false;
      });
      this._draw();
    },

    _resize: function () {
      if (!this._map) return;
      var size = this._map.getSize();
      var w = Math.round(size.x * (1 + 2 * PADDING)),
        h = Math.round(size.y * (1 + 2 * PADDING));
      var dpr = window.devicePixelRatio || 1;
      this._canvas.width = Math.round(w * dpr);
      this._canvas.height = Math.round(h * dpr);
      this._canvas.style.width = w + "px";
      this._canvas.style.height = h + "px";
      if (this._sheet && dpr !== this._spriteDpr) this._buildSprites();
      this._draw();
    },

    // ---- Frame loop ----------------------------------------------------------

    _paneHidden: function () {
      return !this._pane || this._pane.classList.contains("pane-hidden");
    },

    _gliding: function () {
      return !this._still && this._maxSpd > 0 && performance.now() - this._t0 < MAX_GLIDE_S * 1000 + 1000;
    },

    // Redraw on the next frame.
    _redraw: function () {
      this._dirty = true;
      this._loop();
    },

    // Keep the frame loop running while gliding or a redraw is pending.
    _loop: function () {
      if (!this._raf && (this._dirty || this._gliding())) {
        this._raf = requestAnimationFrame(this._frame.bind(this));
      }
    },

    _frame: function (now) {
      this._raf = null;
      if (this._dirty && !this._moving) this._draw();
      // Glide frames are skipped while the pane is hidden (a method tab) and
      // while the map moves (the move events draw then).
      var glide = this._gliding() && !this._paneHidden();
      if (glide && !this._moving && now - this._lastDraw >= this._glideStepMs()) this._draw();
      if (glide || this._dirty) this._raf = requestAnimationFrame(this._frame.bind(this));
    },

    // Time between glide redraws: long enough for the fastest plane to move
    // about half a pixel at this zoom (a whole-world view needs a redraw only
    // every few seconds), and never more than 30 a second.
    _glideStepMs: function () {
      var map = this._map;
      var b = map.getBounds();
      var lat = Math.min(Math.max(Math.abs(b.getNorth()), Math.abs(b.getSouth())), 80);
      var pxPerM = (256 * Math.pow(2, map.getZoom())) / (40075016.686 * Math.cos(lat * DEG));
      var speed = Math.min(this._maxSpd, GLIDE_REF_SPEED);
      return Math.max(GLIDE_FRAME_MS, (1000 * GLIDE_STEP_PX) / (speed * pxPerM));
    },

    // ---- Drawing -------------------------------------------------------------

    _draw: function () {
      var map = this._map;
      // During a zoom animation the canvas is scaled by _onZoomAnim instead.
      if (!map || map._animatingZoom) return;
      var t = performance.now();
      this._dirty = false;
      this._lastDraw = t;

      var size = map.getSize();
      var padX = Math.round(size.x * PADDING),
        padY = Math.round(size.y * PADDING);
      this._drawCenter = map.getCenter();
      this._drawZoom = map.getZoom();
      L.DomUtil.setPosition(this._canvas, map.containerPointToLayerPoint([-padX, -padY]));
      L.DomUtil.removeClass(this._canvas, "flying");

      var ctx = this._ctx;
      ctx.clearRect(0, 0, this._canvas.width, this._canvas.height);
      this._hitN = 0;
      var n = this._n;
      if (!n || !this._sheet || !this._bands.length) return;
      if (this._spriteSize !== this._iconSize()) this._buildSprites();

      var dt = this._still ? 0 : Math.min((t - this._t0) / 1000, MAX_GLIDE_S);
      var scale = 256 * Math.pow(2, this._drawZoom); // world width in px (EPSG:3857)
      var origin = map.getPixelOrigin(),
        panePos = map._getMapPanePos();
      var ox = origin.x - panePos.x,
        oy = origin.y - panePos.y; // projected px of the container's top left
      var xMin = -padX - MARGIN,
        xMax = size.x + padX + MARGIN,
        yMin = -padY - MARGIN,
        yMax = size.y + padY + MARGIN;
      var dpr = this._spriteDpr,
        cell = this._cell,
        sheet = this._sheet;
      var lat = this._lat,
        lon = this._lon,
        vlat = this._vlat,
        vlon = this._vlon,
        rot = this._rot,
        band = this._band;

      // Room for every plane in every copy of the world that can be in view.
      var need = n * (Math.ceil((xMax - xMin) / scale) + 1);
      if (this._hitX.length < need) {
        this._hitX = new Float32Array(need);
        this._hitY = new Float32Array(need);
        this._hitI = new Int32Array(need);
      }
      var hitX = this._hitX,
        hitY = this._hitY,
        hitI = this._hitI,
        hits = 0,
        hitMax = hitX.length;

      for (var i = 0; i < n; i++) {
        var la = lat[i] + vlat[i] * dt;
        if (la > MAX_LAT) la = MAX_LAT;
        else if (la < -MAX_LAT) la = -MAX_LAT;
        var y = scale * (0.5 - Math.log(Math.tan(Math.PI / 4 + (la * DEG) / 2)) / (2 * Math.PI)) - oy;
        if (y < yMin || y > yMax) continue;
        var x0 = scale * ((lon[i] + vlon[i] * dt) / 360 + 0.5) - ox;
        // Every copy of the world in view.
        var kMin = Math.ceil((xMin - x0) / scale),
          kMax = Math.floor((xMax - x0) / scale);
        if (kMin > kMax) continue;
        var sx = rot[i] * cell,
          sy = band[i] * cell;
        var dy = Math.round((y + padY) * dpr - cell / 2);
        for (var k = kMin; k <= kMax; k++) {
          var x = x0 + k * scale;
          ctx.drawImage(sheet, sx, sy, cell, cell, Math.round((x + padX) * dpr - cell / 2), dy, cell, cell);
          if (hits < hitMax) {
            hitX[hits] = x;
            hitY[hits] = y;
            hitI[hits] = i;
            hits++;
          }
        }
      }
      this._hitN = hits;
      this._drawMs = performance.now() - t;
    },

    // ---- Hover and click -----------------------------------------------------

    // Index into the drawn list of the plane nearest a container point, or -1.
    _hitTest: function (p) {
      if (this._paneHidden() || this._moving) return -1;
      var best = -1,
        bestD = HIT_PX * HIT_PX;
      for (var j = 0; j < this._hitN; j++) {
        var dx = this._hitX[j] - p.x,
          dy = this._hitY[j] - p.y;
        var d = dx * dx + dy * dy;
        if (d <= bestD) {
          bestD = d;
          best = j;
        }
      }
      return best;
    },

    _onMouseMove: function (e) {
      var j = this._hitTest(e.containerPoint);
      if (j < 0) {
        this._hideTip();
        return;
      }
      var i = this._hitI[j];
      this._map.getContainer().style.cursor = "pointer";
      if (i === this._hover) return;
      this._hover = i;
      var tip = this._tip;
      tip.innerHTML = this._tipHtml(i);
      tip.style.left = this._hitX[j] + "px";
      tip.style.top = this._hitY[j] + "px";
      tip.classList.add("on");
    },

    // Callsign, then altitude and speed.
    _tipHtml: function (i) {
      var cs = this._callsign[i],
        alt = this._alt[i],
        spd = this._spd[i];
      var altText = this._ground[i] === true ? "On ground" : isNum(alt) ? comma(alt) + " m" : "Altitude n/a";
      var spdText = isNum(spd) ? comma(spd * 3.6) + " km/h" : "speed n/a";
      return "<b>" + escapeHtml(cs ? cs : "No callsign") + "</b><br>" + altText + " &middot; " + spdText;
    },

    _hideTip: function () {
      this._hover = -1;
      if (this._tip) this._tip.classList.remove("on");
      if (this._map) this._map.getContainer().style.cursor = "";
    },

    _onClick: function (e) {
      var j = this._hitTest(e.containerPoint);
      if (j < 0) return;
      var html = this._popup[this._hitI[j]];
      if (!html) return;
      this._hideTip();
      L.popup()
        .setLatLng(this._map.containerPointToLatLng([this._hitX[j], this._hitY[j]]))
        .setContent(html)
        .openOn(this._map);
    }
  });

  // ---- Wiring ----------------------------------------------------------------

  // "planes-data" can arrive before the map exists: keep the latest message
  // and apply it once the map is ready.
  var layer = null;
  var pending = null;

  var prevReady = window.gfMapReady;
  window.gfMapReady = function (m) {
    if (prevReady) prevReady(m);
    if (layer || !m.getPane("planes")) return;
    layer = new PlaneLayer();
    layer.addTo(m);
    window.gfPlanes = layer; // handy in the browser console
    if (pending) {
      layer.setData(pending);
      pending = null;
    }
  };

  document.addEventListener("DOMContentLoaded", function () {
    if (!window.Shiny || !Shiny.addCustomMessageHandler) return;
    Shiny.addCustomMessageHandler("planes-data", function (msg) {
      if (layer) layer.setData(msg);
      else pending = msg;
    });
  });
})();
