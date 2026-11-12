.pragma library

// Pure hourglass arithmetic. Everything that comes out of shell.json passes
// through here first, so a hand-edited or damaged entry cannot put the widget
// into a state it does not know how to draw.

var DEFAULT_MINUTES = 25
// A run-out older than this when the shell starts is not announced.
var STALE_RUN_OUT_MS = 10 * 60000
var MIN_MINUTES = 1
var MAX_MINUTES = 720
var PRESETS = [5, 15, 25, 45, 60]

function duration(value) {
  var minutes = Math.round(Number(value))
  if (!isFinite(minutes)) return DEFAULT_MINUTES
  return Math.max(MIN_MINUTES, Math.min(MAX_MINUTES, minutes))
}

// Milliseconds since the epoch at which the glass was last flipped; 0 means
// it has not been flipped and stands empty.
function flippedAt(value) {
  var at = Number(value)
  return isFinite(at) && at > 0 ? Math.floor(at) : 0
}

// phase:     "idle" (never flipped), "running", or "done" (run out)
// elapsedMs: time since the flip, still counting after the sand has run out
// leftMs:    time until the sand runs out
// overMs:    time since the sand ran out
// remaining: share of the sand still in the top bulb, 1 down to 0
function state(flipped, minutes, nowMs) {
  var total = duration(minutes) * 60000
  var at = flippedAt(flipped)
  if (at === 0)
    return { phase: "idle", elapsedMs: 0, leftMs: total, overMs: 0, remaining: 0 }

  // A flip stamped in the future (the clock was set back) reads as just now.
  var elapsed = Math.max(0, Number(nowMs) - at)
  if (!isFinite(elapsed)) elapsed = 0
  if (elapsed >= total)
    return { phase: "done", elapsedMs: elapsed, leftMs: 0, overMs: elapsed - total, remaining: 0 }
  return { phase: "running", elapsedMs: elapsed, leftMs: total - elapsed, overMs: 0, remaining: 1 - elapsed / total }
}

// The bar icon only moves in a few large steps. Rounded up, so the top bulb
// shows some sand for as long as any is left.
function chunked(remaining, chunks) {
  var steps = Math.max(1, Math.round(chunks))
  var share = Math.max(0, Math.min(1, Number(remaining) || 0))
  return Math.ceil(share * steps - 1e-9) / steps
}

function pad(value) {
  return value < 10 ? "0" + value : String(value)
}

// 0:07, 12:34, 1:02:03
function clock(ms) {
  var seconds = Math.max(0, Math.floor((Number(ms) || 0) / 1000))
  var h = Math.floor(seconds / 3600)
  var m = Math.floor((seconds % 3600) / 60)
  var s = seconds % 60
  return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
}

// Whole minutes left, rounded up so the last minute reads 1, not 0.
function minutesLeft(ms) {
  return Math.max(0, Math.ceil((Number(ms) || 0) / 60000))
}

// ---------------------------------------------------------------------------
// Glass styles. "matrix" is an hourglass made of dots; "turned" is a curved
// outline glass on posts; "square" is a square of dots that fills up as time
// passes. Each has a large form for the panel and a simplified form below
// BIG_SIZE for the bar icon.

var STYLES = ["matrix", "turned", "square"]
var DEFAULT_STYLE = "matrix"
var BIG_SIZE = 40

function style(value) {
  return STYLES.indexOf(String(value)) >= 0 ? String(value) : DEFAULT_STYLE
}

function nextStyle(value) {
  return STYLES[(STYLES.indexOf(style(value)) + 1) % STYLES.length]
}

function clamp01(v) {
  v = Number(v)
  return isFinite(v) ? Math.max(0, Math.min(1, v)) : 0
}

function r2(v) { return Math.round(v * 100) / 100 }

// --- shared bulb geometry ---------------------------------------------------
// A bulb is described by its half-width w(d) at distance d from the neck.

function cubicAt(c, t) {
  var u = 1 - t, a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
  return [a * c[0][0] + b * c[1][0] + d * c[2][0] + e * c[3][0],
          a * c[0][1] + b * c[1][1] + d * c[2][1] + e * c[3][1]]
}

// Control points are [halfWidth, d]; d must rise monotonically along the curve.
function cubicProfile(c) {
  return function(d) {
    if (d <= c[0][1]) return c[0][0]
    if (d >= c[3][1]) return c[3][0]
    var lo = 0, hi = 1
    for (var i = 0; i < 26; i++) {
      var m = (lo + hi) / 2
      if (cubicAt(c, m)[1] < d) lo = m; else hi = m
    }
    return cubicAt(c, (lo + hi) / 2)[0]
  }
}

// The profile moved inward by a perpendicular gap g, so sand keeps clear of
// the glass evenly even where the wall slopes.
function inset(w, g) {
  return function(d) {
    var m = Infinity
    for (var k = -6; k <= 6; k++) {
      var o = k / 6 * g
      m = Math.min(m, w(d + o) - Math.sqrt(Math.max(0, g * g - o * o)))
    }
    return Math.max(0, m)
  }
}

// Sample a profile once into a lookup table; everything after reads the table.
function table(fn, a, b, n) {
  var v = []
  for (var i = 0; i <= n; i++) v.push(fn(a + (b - a) * i / n))
  return function(d) {
    var t = Math.max(0, Math.min(1, (d - a) / (b - a))) * n
    var i = Math.min(n - 1, Math.floor(t))
    return v[i] + (v[i + 1] - v[i]) * (t - i)
  }
}

function area(w, a, b) {
  if (b <= a) return 0
  var n = 64, h = (b - a) / n, s = 0
  for (var i = 0; i < n; i++) s += w(a + (i + 0.5) * h)
  return 2 * s * h
}

function solve(fn, lo, hi, target) {
  for (var i = 0; i < 34; i++) {
    var m = (lo + hi) / 2
    if (fn(m) < target) lo = m; else hi = m
  }
  return (lo + hi) / 2
}

function firstOpen(w, a, b) {
  for (var i = 0; i <= 60; i++) {
    var d = a + (b - a) * i / 60
    if (w(d) > 0.35) return d
  }
  return b
}

// Sand left in the top bulb: filled from the neck up to the level that holds
// `share` of the sand, with a shallow V dip once it has begun to drain.
// Points are in bulb space [x, d].
function topSand(w, d0, dFull, share, dipMax) {
  if (share <= 0.002) return null
  var full = area(w, d0, dFull)
  var ramp = Math.min(1, (1 - share) / 0.12)
  function dipAt(s) {
    var dip = Math.min(dipMax * ramp, (s - d0) * 0.8, w(s) * 0.42)
    for (var k = 0; k < 24 && dip > 0.01; k++) {
      var ok = true
      for (var i = 1; i < 10; i++) {
        var u = i / 10
        if (w(s) * u > w(s - dip * (1 - u)) + 0.01) { ok = false; break }
      }
      if (ok) break
      dip *= 0.8
    }
    return Math.max(0, dip)
  }
  var s = solve(function(x) { return area(w, d0, x) - w(x) * dipAt(x) }, d0, dFull, share * full)
  var dip = dipAt(s), n = 28, L = [], R = []
  for (var i = 0; i <= n; i++) {
    var d = d0 + (s - d0) * i / n, x = w(d)
    L.push([-x, d])
    R.push([x, d])
  }
  R.reverse()
  return { pts: L.concat([[0, s - dip]], R), level: s }
}

// Sand piled in the bottom bulb: a cone of the given slope standing on the
// floor and cut off by the glass, its peak found by area.
function bottomSand(w, d0, d1, areaWanted, slope) {
  if (areaWanted <= 0.002) return null
  function h(d, p) { return Math.max(0, Math.min(w(d), (d - p) / slope)) }
  function A(p) {
    var n = 64, st = (d1 - p) / n, s = 0
    for (var i = 0; i < n; i++) s += h(p + (i + 0.5) * st, p)
    return 2 * s * st
  }
  var q = solve(function(x) { return A(d1 - x) }, 0, d1 - d0, areaWanted)
  var p = d1 - q, n = 32, L = [], R = []
  for (var i = 0; i <= n; i++) {
    var d = p + (d1 - p) * i / n, x = h(d, p)
    L.push([-x, d])
    R.push([x, d])
  }
  R.reverse()
  return { pts: L.concat(R), peak: p }
}

function mapPoints(pts, cx, cy, sign) {
  var out = []
  for (var i = 0; i < pts.length; i++) out.push({ x: cx + pts[i][0], y: cy + sign * pts[i][1] })
  return out
}

// --- Turned -----------------------------------------------------------------

var turnedCache = {}

function turnedGlass(size) {
  var S = Math.max(4, Number(size) || 16)
  var key = String(r2(S))
  if (turnedCache[key]) return turnedCache[key]

  var q = { size: S, big: S >= BIG_SIZE }
  if (q.big) {
    q.sw = Math.max(1.5, S / 74)
    q.width = Math.round(S * 0.64)
    q.slab = S * 0.042
    q.top = q.sw / 2 + q.slab
    q.L = S / 2 - q.top
    q.Wb = q.width * 0.36
    q.n = Math.max(q.sw * 1.3, S * 0.02)
    q.c = [[q.n, 0], [q.n, q.L * 0.35], [q.Wb * 1.35, q.L * 0.2], [q.Wb * 0.86, q.L]]
    q.gap = q.sw * 1.6
    q.ws = table(inset(cubicProfile(q.c), q.gap), 0, q.L, 200)
    q.d0 = firstOpen(q.ws, 0, q.L)
    q.floor = q.L - q.gap
    q.dFull = q.L * 0.8
    q.dip = q.L * 0.1
    q.slope = 0.44
  } else {
    var k = S / 12
    q.sw = Math.max(1, k)
    q.width = Math.round(9 * k)
    q.L = S / 2 - q.sw
    q.Wb = 3.5 * k
    q.n = 0.5 * k
    q.c = [[q.n, 0], [q.n, q.L * 0.45], [q.Wb, q.L * 0.15], [q.Wb, q.L]]
    q.ws = table(cubicProfile(q.c), 0, q.L, 100)
    q.d0 = 0
    q.floor = q.L
    q.dFull = q.L
    q.dip = 0
    q.slope = 0.02
  }
  q.full = area(q.ws, q.d0, q.dFull)

  var cx = q.width / 2, cy = S / 2, c = q.c
  function side(sg) {
    function pt(i, dir) { return r2(cx + sg * c[i][0]) + "," + r2(cy + dir * c[i][1]) }
    return "M" + pt(3, -1) + " C" + pt(2, -1) + " " + pt(1, -1) + " " + pt(0, 1) +
      " C" + pt(1, 1) + " " + pt(2, 1) + " " + pt(3, 1)
  }
  q.outline = side(-1) + " " + side(1)

  if (q.big) {
    var sw = q.sw, px = q.width / 2 - sw * 2.4, rr = S * 0.021
    var caps = [], posts = []
    var ys = [sw / 2, S - sw / 2 - q.slab]
    for (var i = 0; i < ys.length; i++) {
      caps.push("M" + r2(sw / 2) + "," + r2(ys[i]) + " h" + r2(q.width - sw) + " v" + r2(q.slab) +
        " h" + r2(-(q.width - sw)) + " Z")
    }
    var sides = [-1, 1]
    for (var j = 0; j < sides.length; j++) {
      var x = cx + sides[j] * px
      posts.push("M" + r2(x) + "," + r2(q.top + sw / 2) + " V" + r2(cy - rr))
      posts.push("M" + r2(x) + "," + r2(cy + rr) + " V" + r2(S - q.top - sw / 2))
      posts.push("M" + r2(x - rr) + "," + r2(cy) + " a" + r2(rr) + "," + r2(rr) + " 0 1,0 " + r2(2 * rr) + ",0" +
        " a" + r2(rr) + "," + r2(rr) + " 0 1,0 " + r2(-2 * rr) + ",0")
    }
    q.caps = caps.join(" ")
    q.posts = posts.join(" ")
  } else {
    var h = q.sw / 2
    q.caps = "M0," + r2(h) + " H" + q.width + " M0," + r2(S - h) + " H" + q.width
    q.posts = ""
  }

  turnedCache[key] = q
  return q
}

// The sand for one moment: polygons for each bulb ({x, y} points, null when
// that bulb is empty) and the span the falling stream covers.
function turnedSand(size, remaining) {
  var q = turnedGlass(size)
  var r = clamp01(remaining)
  var cx = q.width / 2, cy = q.size / 2
  var T = topSand(q.ws, q.d0, q.dFull, r, q.dip)
  var B = bottomSand(q.ws, q.d0, q.floor, (1 - r) * q.full, q.slope)
  return {
    top: T ? mapPoints(T.pts, cx, cy, -1) : null,
    bottom: B ? mapPoints(B.pts, cx, cy, 1) : null,
    streamFrom: cy - q.d0,
    streamTo: cy + (B ? B.peak : q.floor)
  }
}

// Three grains falling beside the stream, at `phase` 0..1 through their fall.
function turnedGrains(size, sand, phase) {
  var q = turnedGlass(size)
  var off = [2.4, -2.6, 1.7], out = []
  var y0 = sand.streamFrom, y1 = sand.streamTo
  for (var k = 0; k < 3; k++) {
    var f = (k / 3 + (Number(phase) || 0)) % 1
    out.push({
      x: q.width / 2 + off[k] * q.sw * 0.8,
      y: y0 + (y1 - y0) * (0.25 + 0.75 * f),
      r: q.sw * 0.45
    })
  }
  return out
}

// --- Dot matrix -------------------------------------------------------------
// Cells keep a fixed order so a Repeater can hold one delegate per cell and
// only their state changes. The icon form is a 7 by 12 grid at one cell per
// pixel when drawn 12px tall.

var matrixCache = {}

function matrixLayout(size) {
  var S = Math.max(4, Number(size) || 12)
  var key = String(r2(S))
  if (matrixCache[key]) return matrixCache[key]

  var big = S >= BIG_SIZE
  var rows = big ? [7, 9, 9, 9, 7, 5, 3, 1] : [5, 5, 5, 3, 1]
  var cols = big ? 11 : 7
  var neck = big ? 1 : 0
  var nrows = rows.length * 2 + neck + 2
  var p = S / nrows
  var W = cols * p, cx = W / 2
  var top = [], bot = []
  for (var i = 0; i < rows.length; i++) {
    var hw = (rows[i] - 1) / 2
    for (var c = -hw; c <= hw; c++) {
      var k = i + (big ? Math.abs(c) * 0.45 + (c > 0 ? 0.001 : 0) : Math.abs(c) * 0.01)
      top.push({ row: 1 + i, c: c, key: k })
      bot.push({ row: nrows - 2 - i, c: c, key: k })
    }
  }
  function byKey(a, z) { return a.key - z.key }
  top.sort(byKey)
  bot.sort(byKey)

  // The icon only moves whole rows, counted from the neck, so it stays even.
  var snaps = [0]
  for (var j = rows.length - 1; j >= 0; j--) snaps.push(snaps[snaps.length - 1] + rows[j])

  function cell(row, col, kind) {
    if (big) {
      var rad = p * 0.31
      return { x: cx + col * p - rad, y: (row + 0.5) * p - rad, w: 2 * rad, h: 2 * rad, radius: rad, kind: kind, row: row, c: col }
    }
    return { x: cx + col * p - p / 2, y: row * p, w: p, h: p, radius: 0, kind: kind, row: row, c: col }
  }

  var cells = []
  for (i = 0; i < top.length; i++) cells.push(cell(top[i].row, top[i].c, "top"))
  for (i = 0; i < bot.length; i++) cells.push(cell(bot[i].row, bot[i].c, "bottom"))
  if (neck) cells.push(cell(rows.length + 1, 0, "neck"))
  if (big) {
    var th = p * 0.5
    cells.push({ x: 0, y: p / 2 - th / 2, w: W, h: th, radius: 0, kind: "cap" })
    cells.push({ x: 0, y: S - p / 2 - th / 2, w: W, h: th, radius: 0, kind: "cap" })
  } else {
    cells.push({ x: 0, y: 0, w: W, h: p, radius: 0, kind: "cap" })
    cells.push({ x: 0, y: S - p, w: W, h: p, radius: 0, kind: "cap" })
  }

  var layout = { size: S, big: big, width: W, cells: cells, count: top.length, snaps: snaps, dim: big ? 0.16 : 0.3 }
  matrixCache[key] = layout
  return layout
}

// --- Dot square -------------------------------------------------------------
// Not an hourglass: a square of dots that lights one dot at a time, bottom row
// first, left to right, until the time is up. The panel form is 10 by 10, so
// each dot is one percent. The icon is 4 by 4 square pixels in a 12px frame,
// so each quarter of the time lights one row.

var squareCache = {}

function squareLayout(size) {
  var S = Math.max(4, Number(size) || 12)
  var key = String(r2(S))
  if (squareCache[key]) return squareCache[key]

  var big = S >= BIG_SIZE
  var n = big ? 10 : 4
  var cells = []
  var side, pitch, dot, offset
  if (big) {
    side = S * 0.84
    pitch = side / n
    dot = pitch * 0.62
    offset = (pitch - dot) / 2
  } else {
    // 2px cells on a 3px pitch make an 11px block, centred in the frame.
    var k = S / 12
    side = S
    pitch = 3 * k
    dot = 2 * k
    offset = 0.5 * k
  }
  for (var row = n - 1; row >= 0; row--) {
    for (var col = 0; col < n; col++) {
      cells.push({ x: offset + col * pitch, y: offset + row * pitch, w: dot, h: dot, radius: big ? dot / 2 : 0 })
    }
  }

  var layout = { size: S, big: big, width: side, height: side, cells: cells, count: n * n, dim: big ? 0.16 : 0.3 }
  squareCache[key] = layout
  return layout
}

// One state per cell, parallel to layout.cells: 0 empty, 1 lit, 2 accent.
// `filled` is the share of the time gone, 0..1. While running, the next dot
// to light blinks in the accent.
function squareStates(size, filled, pouring, step) {
  var m = squareLayout(size)
  var f = clamp01(filled)
  var lit = Math.min(m.count, Math.floor(f * m.count + 1e-9))
  var out = []
  for (var i = 0; i < m.count; i++) {
    if (i < lit) out.push(1)
    else if (i === lit && pouring && m.big && step === 0) out.push(2)
    else out.push(0)
  }
  return out
}

// One state per cell, parallel to layout.cells: 0 empty, 1 sand, 2 accent.
function matrixStates(size, remaining, pouring, step) {
  var m = matrixLayout(size)
  var r = clamp01(remaining), N = m.count
  var left = Math.round(r * N)
  if (!m.big) {
    var want = r * N
    left = m.snaps.reduce(function(a, z) { return Math.abs(z - want) < Math.abs(a - want) ? z : a }, 0)
  }
  var down = N - left
  var run = !!pouring && m.big && r > 0.002
  var out = []
  for (var i = 0; i < m.cells.length; i++) {
    var cell = m.cells[i]
    if (cell.kind === "cap") out.push(1)
    else if (cell.kind === "neck") out.push(run ? 2 : 0)
    else if (cell.kind === "top") out.push(i >= N - left ? 1 : 0)
    else {
      var b = i - N
      if (b < down) out.push(1)
      else if (run && cell.c === 0 && (cell.row + step) % 2 === 0) out.push(2)
      else out.push(0)
    }
  }
  return out
}
