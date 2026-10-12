// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

function loadLibrary(name) {
  const source = fs.readFileSync(path.join(__dirname, "..", name), "utf8")
  const context = { Math, Number, String, RegExp }
  vm.createContext(context)
  vm.runInContext(source.replace(/^\.pragma library\s*/, ""), context)
  return context
}

function plain(value) { return JSON.parse(JSON.stringify(value)) }

const S = loadLibrary("settings.js")

const osakaJade = {
  background: "#111c18", foreground: "#C1C497", accent: "#509475",
  green: "#549e6a", blue: "#509475", yellow: "#459451", cyan: "#2DD5B7", magenta: "#D2689C", red: "#FF5345"
}
const shellFallbacks = { foreground: "#ffffff", background: "#000000", accent: "#00ff00", urgent: "#ff0000" }

test("shell.json entry beats the theme file, which beats defaults, in either key style", () => {
  const merged = S.merge({ updateDelay: 2, bold: "all" }, { update_delay: 8, bold: "partial", asynchronous: true }, "custom")
  assert.equal(merged.update_delay, 2)
  assert.equal(merged.bold, "all")
  assert.equal(merged.asynchronous, true)
  assert.equal(merged.charset, "ascii")
  assert.equal(S.merge({}, {}).on_battery, "slow")
})

test("a palette that isn't your saved one would supply colors only; the defaults apply to everything else", () => {
  const themeFile = { update_delay: 4, tail_fade: 0.85, tail_hue_shift: 3, font_family: "X", head_color: "#123456" }
  const r = S.resolve({}, themeFile, "theme")
  assert.equal(r.updateDelay, 8.333)       // 12 steps a second
  assert.equal(r.tailFade, 0.5)
  assert.equal(r.tailHueShift, 6)
  assert.equal(r.fontFamily, "CaskaydiaCove Nerd Font Mono")
  assert.equal(r.headColor, "#123456")
  // Your own custom file can set them.
  const own = S.resolve({}, themeFile, "custom")
  assert.equal(own.tailFade, 0.85)
  assert.equal(own.updateDelay, 4)
  // shell.json beats both.
  assert.equal(S.resolve({ tail_fade: 0.2 }, themeFile, "custom").tailFade, 0.2)
})

test("resolve types and clamps every knob", () => {
  const r = S.resolve({ update_delay: "99", opacity: 4, charset: "klingon", on_battery: "PAUSE" }, { start: "full" }, "custom")
  assert.equal(r.updateDelay, 30)   // clamped to the slowest (300 ms a step)
  assert.equal(r.opacity, 1)
  assert.equal(r.charset, "ascii")
  assert.equal(r.onBattery, "pause")
  assert.equal(r.start, "full")
  assert.equal(r.boldLevel, 2)   // default "all"
  assert.equal(S.resolve({ bold: "none" }, {}).boldLevel, 0)
  assert.equal(S.resolve({ bold: "partial" }, {}).boldLevel, 1)
  assert.equal(S.resolve({ bold: "B" }, {}).boldLevel, 2)
  assert.equal(S.resolve({ start: "sideways" }, {}).start, "wake")
  assert.equal(S.resolve({ pause_when_covered: "false" }, {}).pauseWhenCovered, false)
})

test("ncurses pairs map to the terminal's ANSI slots from colors.toml", () => {
  const p = plain(S.palette(S.resolve({}, {}), osakaJade, shellFallbacks))
  assert.deepEqual(p, ["#C1C497", "#549e6a", "#549e6a", "#509475", "#111c18", "#459451", "#2DD5B7", "#D2689C"])
})

test("-C accepts ANSI names and hex literals, and falls back sanely", () => {
  assert.equal(S.palette(S.resolve({ color: "cyan" }, {}), osakaJade, shellFallbacks)[1], "#2DD5B7")
  assert.equal(S.palette(S.resolve({ color: "#123456" }, {}), osakaJade, shellFallbacks)[1], "#123456")
  assert.equal(S.palette(S.resolve({ color: "chartreuse" }, {}), osakaJade, shellFallbacks)[1], "#549e6a")
  assert.equal(S.palette(S.resolve({ head_color: "#F7E8B2" }, {}), osakaJade, shellFallbacks)[0], "#F7E8B2")
  // No colors.toml at all: use what the shell's Color singleton knows.
  const p = plain(S.palette(S.resolve({}, {}), {}, shellFallbacks))
  assert.equal(p[0], "#ffffff")
  assert.equal(p[1], "#00ff00")
  assert.equal(p[4], "#000000")
  assert.equal(S.ansi(osakaJade, "black", shellFallbacks), "#111c18")
})

// ---- Matrix Screens additions ------------------------------------------------

const tokyo = {
  background: "#1a1b26", foreground: "#a9b1d6", accent: "#7aa2f7",
  green: "#9ece6a", bright_green: "#73daca", cyan: "#7dcfff", blue: "#7aa2f7",
  yellow: "#e0af68", magenta: "#bb9af7", red: "#f7768e"
}

test("no palette file: the theme's own colors (accent, green, cyan tails; foreground heads)", () => {
  const r = S.resolve({}, null)
  const p = plain(S.palette(r, tokyo, shellFallbacks))
  assert.equal(p[0], "#a9b1d6")
  assert.equal(p[1], "#7aa2f7")
  // accent | bright_green, green | bright_cyan (missing, falls back to cyan), cyan
  assert.deepEqual(p.slice(8), ["#7aa2f7", "#73daca", "#9ece6a", "#7dcfff", "#7dcfff"])
  assert.deepEqual(plain(S.tailGroups(r.tailColors)), [[8], [9, 10], [11, 12]])
  assert.equal(r.tailFade, 0.5)
  assert.equal(r.tailHueShift, 6)
  assert.equal(S.backgroundColor(r, tokyo, shellFallbacks), "#1a1b26")
})

test("a palette file replaces every color; its unset keys are plain cmatrix", () => {
  const r = S.resolve({}, { head_color: "#ffffff" })
  const p = plain(S.palette(r, tokyo, shellFallbacks))
  assert.equal(p[0], "#ffffff")
  assert.equal(p[1], "#9ece6a")        // color = green
  assert.equal(p.length, 8)            // no tail colors
  assert.equal(r.tailFade, 0.5)        // the global default
})

test("shell.json still beats a palette file, for colors too", () => {
  const r = S.resolve({ tail_colors: "#010101" }, { tail_colors: "#020202 | #030303" })
  assert.deepEqual(plain(r.tailColors), [["#010101"]])
})

test("palette candidates: only your saved palette for the theme", () => {
  const c = plain(S.paletteCandidates("/h", "retro-82"))
  assert.deepEqual(c, [{ source: "custom", path: "/h/.config/omarchy/matrix-screens/retro-82.toml" }])
  assert.equal(S.paletteCandidates("/h", "")[0].path, "")
})

test("tile arguments follow the resolved palette", () => {
  const r = S.resolve({}, { head_color: "#ffffff", tail_colors: "#aa0000, #bb0000 | #00cc00", tail_fade: 0.5 })
  const p = S.palette(r, tokyo, shellFallbacks)
  assert.deepEqual(plain(S.tileArgs(r, p, "#1a1b26")), ["#1a1b26", "#aa0000 #bb0000|#00cc00", "#ffffff", "0.5", "6"])
  const plainR = S.resolve({}, {})
  assert.equal(S.tileArgs(plainR, S.palette(plainR, tokyo, shellFallbacks), "#000000")[1], "#9ece6a")
})

test("plugin entry is found in plugins[] or in the bar layout, and settings are written there", () => {
  const id = "io.github.whiskeytangofussell.matrixscreens"
  assert.deepEqual(plain(S.pluginEntry({ plugins: [{ id, screensaver: true }] }, id)), { id, screensaver: true })
  const config = { plugins: [{ id: "other" }], bar: { layout: { left: [], center: [], right: ["omarchy.clock", id] } } }
  assert.deepEqual(plain(S.pluginEntry(config, id)), {})
  assert.equal(S.setPluginSetting(config, id, "lock_screen", false), true)
  assert.deepEqual(plain(config.bar.layout.right[1]), { id, lock_screen: false })
  assert.equal(S.pluginEntry(config, id).lock_screen, false)
  assert.equal(S.setPluginSetting({ plugins: [] }, id, "x", 1), false)
  assert.equal(S.resolve({}, null).lockScreen, true)
})

test("setting a key to undefined removes it from the entry", () => {
  const id = "io.github.whiskeytangofussell.matrixscreens"
  const config = { bar: { layout: { right: [{ id, update_delay: 5, font_family: "" }] } } }
  S.setPluginSetting(config, id, "update_delay", undefined)
  assert.deepEqual(Object.keys(config.bar.layout.right[0]).sort(), ["font_family", "id"])
})

test("settings.json helpers: set/remove keys, migrate a legacy shell.json entry", () => {
  const id = "io.github.whiskeytangofussell.matrixscreens"
  const a = { screensaver: true }
  const b = S.withSetting(a, "font_size", 18)
  assert.deepEqual(plain(a), { screensaver: true })        // not mutated
  assert.deepEqual(plain(b), { screensaver: true, font_size: 18 })
  assert.deepEqual(plain(S.withSetting(b, "screensaver", undefined)), { font_size: 18 })
  const config = { bar: { layout: { right: [{ id, screensaver: true, lock_screen: false }] } } }
  assert.deepEqual(plain(S.legacySettings(S.pluginEntry(config, id))), { screensaver: true, lock_screen: false })
  S.stripPluginEntry(config, id)
  assert.deepEqual(plain(config.bar.layout.right[0]), { id })
  assert.equal(S.legacySettings(S.pluginEntry(config, id)), null)
})

test("a theme's matrix_* keys in colors.toml are its rain defaults; your palette and settings still win", () => {
  const colors = { background: "#0b0b12", foreground: "#e0e0ff", accent: "#ff2bd6",
    matrix_head_color: "#ffffff", matrix_tail_colors: "#ff1f3d | #00ff4c", matrix_tail_fade: 0.85, matrix_tail_hue_shift: 3 }
  const rain = S.themeRainDefaults(colors)
  assert.deepEqual(plain(rain), { head_color: "#ffffff", tail_colors: "#ff1f3d | #00ff4c", tail_fade: 0.85, tail_hue_shift: 3 })
  assert.equal(S.themeRainDefaults({ accent: "#fff" }), null)
  // Theme default
  let r = S.resolve({}, null, "theme", rain)
  assert.deepEqual(plain(S.palette(r, colors, {})).slice(8), ["#ff1f3d", "#00ff4c"])
  assert.equal(r.tailFade, 0.85)
  assert.equal(r.tailHueShift, 3)
  assert.equal(S.palette(r, colors, {})[0], "#ffffff")
  // Your saved palette replaces the colors; the theme's fade still applies unless the file sets one
  r = S.resolve({}, { tail_colors: "#123456" }, "custom", rain)
  assert.deepEqual(plain(S.palette(r, colors, {})).slice(8), ["#123456"])
  assert.equal(r.tailFade, 0.85)
  // Your settings beat everything
  assert.equal(S.resolve({ tail_fade: 0.2 }, null, "theme", rain).tailFade, 0.2)
})
