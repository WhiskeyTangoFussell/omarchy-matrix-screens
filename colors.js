.pragma library

// The color chooser's logic: hex/HSV conversion, the editable draft of a
// palette, and turning a draft back into a palette file. Pure JS so
// `node --test` covers it.

var MAX_COLORS = 12
// What a saved palette file holds: colors only. Fade, hue shift, speed and
// the font are display settings, saved in shell.json.
var COLOR_KEYS = ["color", "head_color", "tail_colors", "background_color"]

function clamp(x, lo, hi) { return Math.max(lo, Math.min(hi, x)) }

function normalizeHex(value) {
  var text = String(value === undefined || value === null ? "" : value).trim()
  if (text.charAt(0) !== "#") text = "#" + text
  if (/^#[0-9a-fA-F]{3}$/.test(text)) text = "#" + text[1] + text[1] + text[2] + text[2] + text[3] + text[3]
  if (/^#[0-9a-fA-F]{8}$/.test(text)) text = text.substring(0, 7)
  return /^#[0-9a-fA-F]{6}$/.test(text) ? text.toLowerCase() : ""
}

// h 0..360, s and v 0..1.
function hexToHsv(hex) {
  var n = normalizeHex(hex) || "#000000"
  var r = parseInt(n.substr(1, 2), 16) / 255
  var g = parseInt(n.substr(3, 2), 16) / 255
  var b = parseInt(n.substr(5, 2), 16) / 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
  var h = 0
  if (d > 0) {
    if (max === r) h = ((g - b) / d) % 6
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h *= 60
    if (h < 0) h += 360
  }
  return { h: h, s: max === 0 ? 0 : d / max, v: max }
}

function hsvToHex(h, s, v) {
  h = ((Number(h) % 360) + 360) % 360
  s = clamp(Number(s), 0, 1)
  v = clamp(Number(v), 0, 1)
  var c = v * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = v - c
  var rgb = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x]
    : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x]
  var out = "#"
  for (var i = 0; i < 3; i++) {
    var byte = Math.round((rgb[i] + m) * 255)
    out += (byte < 16 ? "0" : "") + byte.toString(16)
  }
  return out
}

// The palette as the rain draws it now, as plain hex values to edit.
// palette is Settings.palette() output (slot 0 head, 1 color, 8.. tails).
function draftFrom(config, palette, background) {
  var groups = []
  var slot = 8
  var tails = config.tailColors || []
  for (var i = 0; i < tails.length; i++) {
    var group = []
    for (var k = 0; k < tails[i].length; k++) group.push(normalizeHex(palette[slot++]) || "#00ff00")
    groups.push(group)
  }
  if (groups.length === 0) groups.push([normalizeHex(palette[1]) || "#00ff00"])
  return {
    head: normalizeHex(palette[0]) || "#ffffff",
    background: normalizeHex(String(background)) || "#000000",
    groups: groups,
    fade: Number(config.tailFade) || 0,
    shift: Number(config.tailHueShift) || 0
  }
}

function colorCount(draft) {
  var n = 0
  for (var i = 0; i < draft.groups.length; i++) n += draft.groups[i].length
  return n
}

function copy(draft) { return JSON.parse(JSON.stringify(draft)) }

// Slot addresses for the chooser: "head", "background", or "g<group>s<shade>".
function colorAt(draft, slot) {
  if (slot === "head") return draft.head
  if (slot === "background") return draft.background
  var m = /^g(\d+)s(\d+)$/.exec(String(slot))
  if (m && draft.groups[+m[1]] && draft.groups[+m[1]][+m[2]] !== undefined) return draft.groups[+m[1]][+m[2]]
  return ""
}

function withColor(draft, slot, hex) {
  var value = normalizeHex(hex)
  if (!value) return draft
  var next = copy(draft)
  if (slot === "head") next.head = value
  else if (slot === "background") next.background = value
  else {
    var m = /^g(\d+)s(\d+)$/.exec(String(slot))
    if (m && next.groups[+m[1]] && next.groups[+m[1]][+m[2]] !== undefined) next.groups[+m[1]][+m[2]] = value
  }
  return next
}

// A new shade in a group: a darker copy of its last shade.
function withShadeAdded(draft, group) {
  if (colorCount(draft) >= MAX_COLORS || !draft.groups[group]) return draft
  var next = copy(draft)
  var last = hexToHsv(next.groups[group][next.groups[group].length - 1])
  next.groups[group].push(hsvToHex(last.h, last.s, last.v * 0.7))
  return next
}

function withShadeRemoved(draft, group, shade) {
  if (!draft.groups[group] || colorCount(draft) <= 1) return draft
  var next = copy(draft)
  next.groups[group].splice(shade, 1)
  if (next.groups[group].length === 0) next.groups.splice(group, 1)
  return next
}

// A new group: one shade, a hue a little round the wheel from the last group.
function withGroupAdded(draft) {
  if (colorCount(draft) >= MAX_COLORS) return draft
  var next = copy(draft)
  var lastGroup = next.groups[next.groups.length - 1] || ["#00ff00"]
  var base = hexToHsv(lastGroup[0])
  next.groups.push([hsvToHex(base.h + 40, Math.max(0.5, base.s), Math.max(0.6, base.v))])
  return next
}

function round2(x) { return Math.round(Number(x) * 100) / 100 }

// The palette file for a draft: its colors. Any other settings already in
// the file (hand-written ones) are kept; its color keys and comments are
// replaced.
function serialize(draft, themeName, existingText) {
  var kept = []
  var lines = String(existingText || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#") continue
    var eq = line.indexOf("=")
    var key = eq > 0 ? line.substring(0, eq).trim() : ""
    if (key && COLOR_KEYS.indexOf(key) === -1) kept.push(line)
  }
  var groups = draft.groups.map(function (g) { return g.join(", ") }).join(" | ")
  var out = [
    "# Matrix Screens: your colors for " + themeName + " (saved by the color chooser).",
    "# This file wins over the theme's and the bundled palette. Delete it to go back.",
    "",
    "head_color = \"" + draft.head + "\"",
    "color = \"" + draft.groups[0][0] + "\"",
    "tail_colors = \"" + groups + "\"",
    "background_color = \"" + draft.background + "\""
  ]
  if (kept.length) out = out.concat(["", "# Other settings"], kept)
  return out.join("\n") + "\n"
}

// What the preview needs: the same shapes Settings.palette/tailGroups give.
function previewPalette(draft) {
  var out = [draft.head, draft.groups[0][0], draft.groups[0][0], draft.groups[0][0], draft.background,
    draft.groups[0][0], draft.groups[0][0], draft.groups[0][0]]
  for (var i = 0; i < draft.groups.length; i++) out = out.concat(draft.groups[i])
  return out
}

function previewTailGroups(draft) {
  var out = []
  var slot = 8
  for (var i = 0; i < draft.groups.length; i++) {
    var g = []
    for (var k = 0; k < draft.groups[i].length; k++) g.push(slot++)
    out.push(g)
  }
  return out
}

// ---- speed and typeface ------------------------------------------------------

// The rain steps every update_delay * 10 ms; the slider shows steps per
// second instead, so faster is to the right.
var MIN_RATE = 3.5
var MAX_RATE = 50

function rateFromDelay(delay) {
  var d = Number(delay)
  if (!(d > 0)) return MAX_RATE
  return clamp(100 / d, MIN_RATE, MAX_RATE)
}

function delayFromRate(rate) {
  return Math.round(100 / clamp(Number(rate) || MIN_RATE, MIN_RATE, MAX_RATE) * 1000) / 1000
}

// Font families from `fc-list :spacing=mono family`: the first name on each
// line, without duplicates, icon and emoji fonts, sorted.
function monoFamilies(fcText) {
  var seen = {}
  var out = []
  var lines = String(fcText || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var name = lines[i].split(",")[0].trim()
    if (!name || seen[name]) continue
    if (/emoji|signwriting/i.test(name) || name === "omarchy") continue
    seen[name] = true
    out.push(name)
  }
  out.sort(function (a, b) { return a.toLowerCase() < b.toLowerCase() ? -1 : a.toLowerCase() > b.toLowerCase() ? 1 : 0 })
  return out
}
