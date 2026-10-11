.pragma library

// Matrix Screens settings: how the plugin's settings.json, the active
// palette file and the built-in defaults combine, and how color names map
// onto the active theme's colors.toml. Pure JS so `node --test` covers it.
//
// Derived from omatrix's settings.js (© 0x1ocean, GPL-3.0-or-later).

// Everything except colors. Tuned for a desktop background: 12 steps a
// second, bold glyphs in the bundled Caskaydia Cove font at Omarchy's size,
// columns spread edge to edge, tails fading halfway toward the background
// while drifting through the next six tail colors.
//
// Only your own settings change these: the plugin's settings.json and
// your custom palette file. Theme and bundled palettes supply colors only.
var DEFAULTS = {
  update_delay: 8.333,
  asynchronous: false,
  bold: "all",
  charset: "ascii",
  lambda: false,
  changes: false,
  oldstyle: false,
  rainbow: false,
  justify_columns: true,
  opacity: 1.0,
  backdrop_opacity: 0.0,
  start: "wake",
  font_family: "CaskaydiaCove Nerd Font Mono",
  font_size: 0,
  pause_when_covered: true,
  pause_when_locked: true,
  on_battery: "slow",
  battery_update_delay: 8.333,
  tail_fade: 0.5,
  tail_hue_shift: 6,

  // When the rain is the desktop background: "tile" while a rain tile is the
  // selected background, "always" under every background, "off" never.
  background: "tile",
  // Write a rain tile for the active theme into the background switcher.
  background_tile: true,
  // Reselect the new theme's rain tile after a theme switch.
  keep_on_theme_switch: true,
  // Start the rain as the screensaver when the computer goes idle.
  screensaver: false,
  // Draw the rain behind the lock screen's password box.
  lock_screen: true,
  // Close the screensaver when the mouse moves, not just on a key press.
  screensaver_dismiss_on_mouse: true
}

// The color keys. They come from one place only: the palette file when the
// theme has one, otherwise the theme defaults below. A palette file that sets
// only some of them gets plain cmatrix values for the rest.
var COLOR_KEYS = ["color", "tail_colors", "head_color", "background_color"]

// No palette file: the theme's own colors. Heads in the foreground color,
// tails in its accent, green and cyan (bright and normal shades).
var THEME_COLORS = {
  color: "accent",
  tail_colors: "accent | bright_green, green | bright_cyan, cyan",
  head_color: "foreground",
  background_color: "background"
}

// A palette file's unset color keys: what cmatrix itself would draw.
var PLAIN_COLORS = {
  color: "green",
  tail_colors: "",
  head_color: "white",
  background_color: "background"
}

function camel(key) {
  return key.replace(/_([a-z])/g, function (_, c) { return c.toUpperCase() })
}

function lookup(source, key) {
  if (!source) return undefined
  if (source[key] !== undefined && source[key] !== null) return source[key]
  var alt = camel(key)
  if (source[alt] !== undefined && source[alt] !== null) return source[alt]
  return undefined
}

// Precedence: settings.json > palette file > defaults (THEME_COLORS
// for colors when there is no palette file, PLAIN_COLORS when there is).
// A palette file supplies only colors, unless it is your own custom file
// (paletteSource "custom"), which can set anything. Both sources accept
// snake_case (TOML style) and camelCase (JSON style). paletteSettings is null
// when no palette file applies.
function merge(userSettings, paletteSettings, paletteSource) {
  var colorDefaults = paletteSettings ? PLAIN_COLORS : THEME_COLORS
  var ownFile = paletteSource === "custom" ? paletteSettings : null
  var out = {}
  var key
  for (key in DEFAULTS) out[key] = pick(userSettings, ownFile, key, DEFAULTS[key])
  for (key in colorDefaults) out[key] = pick(userSettings, paletteSettings, key, colorDefaults[key])
  return out
}

function pick(userSettings, paletteSettings, key, fallback) {
  var value = lookup(userSettings, key)
  if (value === undefined) value = lookup(paletteSettings, key)
  return value === undefined ? fallback : value
}

function number(value, fallback, minimum, maximum) {
  var n = Number(value)
  if (!isFinite(n)) n = fallback
  return Math.max(minimum, Math.min(maximum, n))
}

function bool(value, fallback) {
  if (typeof value === "boolean") return value
  if (value === "true" || value === 1) return true
  if (value === "false" || value === 0) return false
  return fallback
}

function oneOf(value, allowed, fallback) {
  var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return allowed.indexOf(text) !== -1 ? text : fallback
}

// The 16-color mapping Omarchy's terminal templates use, so cmatrix's
// COLOR_GREEN is the theme's `green` and COLOR_WHITE its `foreground`. Any
// other colors.toml key (accent, bright_cyan, orange, ...) works by name too.
function ansi(themeColors, name, fallbacks) {
  var c = themeColors || {}
  var f = fallbacks || {}
  var key = String(name || "").trim().toLowerCase()
  switch (key) {
  case "white": return c.foreground || f.foreground
  case "black": return c.background || f.background
  case "green": return c.green || f.accent
  case "red": return c.red || f.urgent
  case "blue": return c.blue || f.accent
  case "yellow": return c.yellow || f.accent
  case "cyan": return c.cyan || f.accent
  case "magenta": return c.magenta || f.accent
  }
  if (key && HEX.test(String(c[key] || ""))) return c[key]
  if (key && HEX.test(String(f[key] || ""))) return f[key]
  if (key.indexOf("bright_") === 0) return ansi(themeColors, key.substring(7), fallbacks)
  return undefined
}

var HEX = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/

function resolveColor(themeColors, value, fallbackName, fallbacks) {
  var text = String(value === undefined || value === null ? "" : value).trim()
  if (HEX.test(text)) return text
  return ansi(themeColors, text, fallbacks) || ansi(themeColors, fallbackName, fallbacks)
}

// Palette slots as cmatrix.js numbers them: COLOR_HEAD, COLOR_MATRIX, then
// the rainbow pairs green, blue, black, yellow, cyan, magenta, then from
// slot 8 the tail colors.
function palette(settings, themeColors, fallbacks) {
  // Accepts either a merged (snake_case) or a resolved (camelCase) object.
  var head = settings.headColor !== undefined ? settings.headColor : settings.head_color
  var tails = settings.tailColors !== undefined ? settings.tailColors : tailColors(settings.tail_colors)
  var out = [
    resolveColor(themeColors, head, "white", fallbacks),
    resolveColor(themeColors, settings.color, "green", fallbacks),
    ansi(themeColors, "green", fallbacks),
    ansi(themeColors, "blue", fallbacks),
    ansi(themeColors, "black", fallbacks),
    ansi(themeColors, "yellow", fallbacks),
    ansi(themeColors, "cyan", fallbacks),
    ansi(themeColors, "magenta", fallbacks)
  ]
  for (var i = 0; i < tails.length; i++) {
    for (var k = 0; k < tails[i].length; k++) out.push(resolveColor(themeColors, tails[i][k], "green", fallbacks))
  }
  return out
}

function backgroundColor(settings, themeColors, fallbacks) {
  var value = settings.backgroundColor !== undefined ? settings.backgroundColor : settings.background_color
  return resolveColor(themeColors, value, "black", fallbacks)
}

function boldLevel(value) {
  if (value === 2 || value === "all" || value === "B") return 2
  if (value === 1 || value === true || value === "partial" || value === "b") return 1
  return 0
}

// Palette slots 8.. hold the tail colors; the shader has 20 slots in all.
var TAIL_SLOT = 8
var MAX_TAIL_COLORS = 12

// tail_colors: hue groups separated by "|", shades within a group by ",".
// Each stream picks one group and each of its glyphs a random shade from it,
// e.g. "#f8d,#f2b,#b07 | #d9f,#b4f,#70d". Empty means the single `color`.
function tailColors(value) {
  var groups = []
  var total = 0
  var parts = String(value === undefined || value === null ? "" : value).split("|")
  for (var i = 0; i < parts.length; i++) {
    var group = []
    var shades = parts[i].split(",")
    for (var k = 0; k < shades.length && total < MAX_TAIL_COLORS; k++) {
      var shade = shades[k].trim()
      if (!shade) continue
      group.push(shade)
      total++
    }
    if (group.length > 0) groups.push(group)
  }
  return groups
}

// The engine's view of tailColors: the same groups as palette slot numbers.
function tailGroups(groups) {
  var out = []
  var slot = TAIL_SLOT
  for (var i = 0; i < (groups || []).length; i++) {
    var group = []
    for (var k = 0; k < groups[i].length; k++) group.push(slot++)
    out.push(group)
  }
  return out
}

// Everything the renderer needs, typed and clamped.
function resolve(userSettings, paletteSettings, paletteSource) {
  var s = merge(userSettings, paletteSettings, paletteSource)
  return {
    updateDelay: number(s.update_delay, DEFAULTS.update_delay, 0, 30),
    asynchronous: bool(s.asynchronous, false),
    boldLevel: boldLevel(s.bold),
    charset: oneOf(s.charset, ["ascii", "katakana", "console"], "ascii"),
    lambda: bool(s.lambda, false),
    changes: bool(s.changes, false),
    oldstyle: bool(s.oldstyle, false),
    rainbow: bool(s.rainbow, false),
    justifyColumns: bool(s.justify_columns, true),
    color: s.color,
    tailColors: tailColors(s.tail_colors),
    tailFade: number(s.tail_fade, DEFAULTS.tail_fade, 0, 1),
    tailHueShift: number(s.tail_hue_shift, DEFAULTS.tail_hue_shift, 0, 12),
    headColor: s.head_color,
    backgroundColor: s.background_color,
    opacity: number(s.opacity, 1, 0, 1),
    backdropOpacity: number(s.backdrop_opacity, 0, 0, 1),
    start: oneOf(s.start, ["wake", "full"], "wake"),
    fontFamily: String(s.font_family === undefined || s.font_family === null ? "" : s.font_family).trim(),
    fontSize: Math.round(number(s.font_size, 0, 0, 72)),
    pauseWhenCovered: bool(s.pause_when_covered, true),
    pauseWhenLocked: bool(s.pause_when_locked, true),
    onBattery: oneOf(s.on_battery, ["slow", "pause", "ignore"], "slow"),
    batteryUpdateDelay: number(s.battery_update_delay, DEFAULTS.battery_update_delay, 0, 30),
    background: oneOf(s.background, ["tile", "always", "off"], "tile"),
    backgroundTile: bool(s.background_tile, true),
    keepOnThemeSwitch: bool(s.keep_on_theme_switch, true),
    screensaver: bool(s.screensaver, false),
    lockScreen: bool(s.lock_screen, true),
    screensaverDismissOnMouse: bool(s.screensaver_dismiss_on_mouse, true),
    raw: s
  }
}

// Where a theme's palette can come from, best first. The first file that
// exists wins outright; with none, the theme's own colors are used.
//   1. ~/.config/omarchy/matrix-screens/<theme>.toml   your custom colors
//   2. <current theme>/matrix-screens.toml              shipped by the theme
//   3. <current theme>/omatrix.toml                     omatrix-style themes
//   4. <plugin>/palettes/<theme>.toml                   bundled with the plugin
function paletteCandidates(home, themeName, pluginDir) {
  var theme = home + "/.local/state/omarchy/current/theme"
  // Always four entries, so their positions stay put; "" never loads.
  return [
    { source: "custom", path: themeName ? home + "/.config/omarchy/matrix-screens/" + themeName + ".toml" : "" },
    { source: "theme", path: theme + "/matrix-screens.toml" },
    { source: "theme", path: theme + "/omatrix.toml" },
    { source: "bundled", path: themeName ? pluginDir + "/palettes/" + themeName + ".toml" : "" }
  ]
}

// The arguments bin/matrix-screens tile takes for this palette: background,
// tail groups as "a b c|d e", head color, fade and hue shift.
function tileArgs(config, palette, background) {
  var groups = []
  var slot = TAIL_SLOT
  var tails = config.tailColors || []
  for (var i = 0; i < tails.length; i++) {
    var shades = []
    for (var k = 0; k < tails[i].length; k++) shades.push(palette[slot++])
    groups.push(shades.join(" "))
  }
  if (groups.length === 0) groups.push(palette[1])
  return [String(background), groups.join("|"), String(palette[0]), String(config.tailFade), String(config.tailHueShift)]
}

// The plugin's entry in shell.json. A service sits in plugins[]; a plugin
// with a bar widget is enabled by its place in bar.layout instead, as a bare
// id string or an object. Returns {} when there is none.
function pluginEntry(config, id) {
  if (!config || typeof config !== "object") return {}
  var i
  var plugins = Array.isArray(config.plugins) ? config.plugins : []
  for (i = 0; i < plugins.length; i++) {
    if (plugins[i] && typeof plugins[i] === "object" && String(plugins[i].id || "") === id) return plugins[i]
  }
  var layout = config.bar && config.bar.layout ? config.bar.layout : null
  var sections = ["left", "center", "right"]
  for (var k = 0; layout && k < sections.length; k++) {
    var entries = Array.isArray(layout[sections[k]]) ? layout[sections[k]] : []
    for (i = 0; i < entries.length; i++) {
      if (entries[i] && typeof entries[i] === "object" && String(entries[i].id || "") === id) return entries[i]
    }
  }
  return {}
}

// Writes one setting into the plugin's entry, in place (for
// shell.mutateShellConfig); undefined removes it. A bare id string in the
// bar becomes an object. Returns false when the plugin has no entry.
function setPluginSetting(config, id, key, value) {
  if (!config || typeof config !== "object") return false
  var i
  var plugins = Array.isArray(config.plugins) ? config.plugins : []
  for (i = 0; i < plugins.length; i++) {
    if (plugins[i] && typeof plugins[i] === "object" && String(plugins[i].id || "") === id) {
      if (value === undefined) delete plugins[i][key]
      else plugins[i][key] = value
      return true
    }
  }
  var layout = config.bar && config.bar.layout ? config.bar.layout : null
  var sections = ["left", "center", "right"]
  for (var k = 0; layout && k < sections.length; k++) {
    var entries = Array.isArray(layout[sections[k]]) ? layout[sections[k]] : []
    for (i = 0; i < entries.length; i++) {
      if (entries[i] === id) entries[i] = { id: id }
      if (entries[i] && typeof entries[i] === "object" && String(entries[i].id || "") === id) {
        if (value === undefined) delete entries[i][key]
        else entries[i][key] = value
        return true
      }
    }
  }
  return false
}

// ---- the plugin's own settings file ------------------------------------------
//
// ~/.config/omarchy/matrix-screens/settings.json holds every setting; the
// plugin's shell.json entry is only its bare { id } (which enables it).

// A copy of the settings object with one key set; undefined removes it.
function withSetting(settings, key, value) {
  var out = {}
  for (var k in settings || {}) out[k] = settings[k]
  if (value === undefined) delete out[key]
  else out[key] = value
  return out
}

// Settings left in a shell.json plugin entry by older versions (everything
// but the id), to move into settings.json.
function legacySettings(entry) {
  var out = {}
  var any = false
  for (var k in entry || {}) {
    if (k === "id") continue
    out[k] = entry[k]
    any = true
  }
  return any ? out : null
}

// Strips the plugin's shell.json entry back to its id, in place (for
// shell.mutateShellConfig).
function stripPluginEntry(config, id) {
  var entry = pluginEntry(config, id)
  for (var k in entry) if (k !== "id") delete entry[k]
}
