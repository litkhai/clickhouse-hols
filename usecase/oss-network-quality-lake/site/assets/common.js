
/* Shared by the explainer and the demo: catalogue lookup, number format, step reveal, map. */
var LAB = (function () {
  var cat = JSON.parse(document.getElementById("i18n").textContent);
  var lang = document.documentElement.lang;
  var nf = new Intl.NumberFormat(lang);

  function fmt(v) { return typeof v === "number" ? nf.format(v) : String(v); }

  function T(key, params) {
    var s = cat[key] || key;
    Object.keys(params || {}).forEach(function (k) { s = s.split("{" + k + "}").join(fmt(params[k])); });
    return s;
  }

  function reducedMotion() {
    return window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  /* Steps fade in as they scroll into view; nothing is hidden without JS or under reduced motion. */
  function reveal(list) {
    if (!list || reducedMotion() || !("IntersectionObserver" in window)) return;
    list.classList.add("reveal");
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("seen"); io.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -10% 0px" });
    list.querySelectorAll(".step").forEach(function (s) { io.observe(s); });
  }

  var SVGNS = "http://www.w3.org/2000/svg";
  function el(name, attrs, parent) {
    var n = document.createElementNS(SVGNS, name);
    Object.keys(attrs).forEach(function (k) { n.setAttribute(k, attrs[k]); });
    if (parent) parent.appendChild(n);
    return n;
  }

  /* One panel per city: res-7 density background, the 20 ranked res-9 cells on top.
     Equirectangular around the city's centre; no tiles, no h3-js (boundaries come from ClickHouse). */
  function drawMaps(box, map, alerts) {
    alerts = alerts || [];
    box.textContent = "";
    var W = 300, H = 260, pad = 8;
    [0, 1, 2].forEach(function (city) {
      var dens = map.density.filter(function (d) { return d.city === city; });
      var cells = map.cells.filter(function (c) { return c.city === city; });
      var pts = [];
      dens.forEach(function (d) { pts = pts.concat(d.boundary); });
      if (!pts.length) return;
      var lat0 = pts.reduce(function (a, p) { return a + p[0]; }, 0) / pts.length;
      var k = Math.cos(lat0 * Math.PI / 180);
      var xs = pts.map(function (p) { return p[1] * k; }), ys = pts.map(function (p) { return -p[0]; });
      var x0 = Math.min.apply(null, xs), x1 = Math.max.apply(null, xs);
      var y0 = Math.min.apply(null, ys), y1 = Math.max.apply(null, ys);
      var s = Math.min((W - 2 * pad) / (x1 - x0), (H - 2 * pad) / (y1 - y0));
      var ox = (W - s * (x1 - x0)) / 2, oy = (H - s * (y1 - y0)) / 2;
      function xy(p) { return [(ox + (p[1] * k - x0) * s).toFixed(1), (oy + (-p[0] - y0) * s).toFixed(1)]; }
      function poly(b) { return b.map(function (p) { return xy(p).join(","); }).join(" "); }

      var fig = document.createElement("figure");
      var svg = el("svg", { viewBox: "0 0 " + W + " " + H, role: "img",
        "aria-label": T("map.aria", { city: T("city." + city), top: cells.filter(function (c) { return c.list === "users"; }).length,
          weak: cells.filter(function (c) { return c.list === "signal"; }).length }) });
      var max = Math.max.apply(null, dens.map(function (d) { return d.samples; }));
      dens.forEach(function (d) {
        var lvl = Math.min(5, Math.floor(6 * Math.sqrt(d.samples / max)));
        el("polygon", { points: poly(d.boundary), "class": "d h" + lvl }, svg);
      });
      /* alert cells: drawn under the ranked cells, one ring around their middle */
      var al = alerts.filter(function (a) { return a.city === city; });
      if (al.length) {
        var ax = 0, ay = 0;
        al.forEach(function (a) {
          el("polygon", { points: poly(a.boundary), "class": "alert" }, svg);
          var q = xy(a.boundary[0]); ax += +q[0]; ay += +q[1];
        });
        el("circle", { cx: (ax / al.length).toFixed(1), cy: (ay / al.length).toFixed(1), r: 16, "class": "halo-alert" }, svg);
      }
      cells.forEach(function (c) {
        var cls = c.list === "users" ? "top" : "weak";
        var cx = 0, cy = 0;
        c.boundary.forEach(function (p) { var q = xy(p); cx += +q[0]; cy += +q[1]; });
        cx /= c.boundary.length; cy /= c.boundary.length;
        /* a res-9 cell is ~1% of the panel: a ring marks where it is */
        el("circle", { cx: cx.toFixed(1), cy: cy.toFixed(1), r: 9, "class": "halo-" + cls }, svg);
        var g = el("polygon", { points: poly(c.boundary), "class": cls }, svg);
        var t = el("title", {}, g);
        t.textContent = T("map.tip." + c.list, { rnk: c.rnk, cell: c.cell, users: c.users, rsrp: c.avg_rsrp });
      });
      var cap = document.createElement("figcaption");
      cap.textContent = T("city." + city);
      fig.appendChild(svg); fig.appendChild(cap); box.appendChild(fig);
    });
  }

  /* Dashboard panel: weak-signal share per minute as small multiples, one panel per city on a
     shared y-scale (%), so a spike reads at a glance. Hover shows the minute and the value. */
  function drawChart(box, points) {
    box.textContent = "";
    var minutes = [], byCity = [[], [], []];
    points.forEach(function (p) {
      if (minutes.indexOf(p.minute) < 0) minutes.push(p.minute);
      byCity[p.city].push(p);
    });
    var vals = points.map(function (p) { return p.poor_pct; });
    var lo = Math.floor(Math.min.apply(null, vals)), hi = Math.ceil(Math.max.apply(null, vals));
    if (hi === lo) hi = lo + 1;
    var W = 640, H = 92, L = 40, R = 12, Tp = 8, B = 20;
    function x(i) { return L + (W - L - R) * i / Math.max(1, minutes.length - 1); }
    function y(v) { return Tp + (H - Tp - B) * (1 - (v - lo) / (hi - lo)); }
    byCity.forEach(function (ps, c) {
      var wrap = document.createElement("div");
      wrap.className = "sm";
      var title = document.createElement("p");
      title.className = "sm-t";
      title.textContent = T("city." + c);
      var svg = el("svg", { viewBox: "0 0 " + W + " " + H, role: "img",
        "aria-label": T("chart.aria") + " · " + T("city." + c) });
      [lo, hi].forEach(function (g) {
        el("line", { x1: L, x2: W - R, y1: y(g), y2: y(g), "class": "grid" }, svg);
        var tl = el("text", { x: L - 6, y: y(g) + 4, "text-anchor": "end", "class": "axis" }, svg);
        tl.textContent = g + "%";
      });
      if (c === 2) [0, Math.floor((minutes.length - 1) / 2), minutes.length - 1].forEach(function (i) {
        var t = el("text", { x: x(i), y: H - 4, "text-anchor": "middle", "class": "axis" }, svg);
        t.textContent = minutes[i].slice(11, 16);
      });
      var d = ps.map(function (p, i) { return (i ? "L" : "M") + x(minutes.indexOf(p.minute)).toFixed(1) + " " + y(p.poor_pct).toFixed(1); }).join(" ");
      el("path", { d: d, "class": "line" }, svg);
      var cross = el("line", { y1: Tp, y2: H - B, "class": "cross", visibility: "hidden" }, svg);
      var dot = el("circle", { r: 4, "class": "dot", visibility: "hidden" }, svg);
      var tip = document.createElement("div");
      tip.className = "tip"; tip.hidden = true;
      var hit = el("rect", { x: L, y: 0, width: W - L - R, height: H, "class": "hit" }, svg);
      hit.addEventListener("pointermove", function (ev) {
        var r = svg.getBoundingClientRect(), px = (ev.clientX - r.left) * W / r.width;
        var i = Math.max(0, Math.min(minutes.length - 1, Math.round((px - L) / (W - L - R) * (minutes.length - 1))));
        var p = ps.filter(function (q) { return q.minute === minutes[i]; })[0];
        if (!p) return;
        cross.setAttribute("x1", x(i)); cross.setAttribute("x2", x(i)); cross.setAttribute("visibility", "visible");
        dot.setAttribute("cx", x(i)); dot.setAttribute("cy", y(p.poor_pct)); dot.setAttribute("visibility", "visible");
        tip.textContent = minutes[i].slice(11, 16) + " · " + fmt(p.poor_pct) + "%";
        tip.hidden = false;
        tip.style.left = Math.min(r.width - 110, Math.max(0, ev.clientX - r.left + 10)) + "px";
      });
      hit.addEventListener("pointerleave", function () { tip.hidden = true; cross.setAttribute("visibility", "hidden"); dot.setAttribute("visibility", "hidden"); });
      wrap.appendChild(title); wrap.appendChild(svg); wrap.appendChild(tip);
      box.appendChild(wrap);
    });
  }

  return { T: T, fmt: fmt, reveal: reveal, drawMaps: drawMaps, drawChart: drawChart, reducedMotion: reducedMotion };
})();
