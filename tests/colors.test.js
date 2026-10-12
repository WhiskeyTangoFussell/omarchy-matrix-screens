// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

function loadLibrary(name) {
  const source = fs.readFileSync(path.join(__dirname, "..", name), "utf8")
  const context = { Math, Number, String, RegExp, JSON, parseInt }
  vm.createContext(context)
  vm.runInContext(source.replace(/^\.pragma library\s*/, ""), context)
  return context
}
const plain = v => JSON.parse(JSON.stringify(v))
const C = loadLibrary("colors.js")
const S = loadLibrary("settings.js")
const E = loadLibrary("cmatrix.js")

test("hex and HSV round-trip", () => {
  for (const hex of ["#000000", "#ffffff", "#ff1f3d", "#3d4dff", "#9dff00", "#7d82d9"]) {
    const { h, s, v } = C.hexToHsv(hex)
    assert.equal(C.hsvToHex(h, s, v), hex)
  }
  assert.equal(C.normalizeHex("ABC"), "#aabbcc")
  assert.equal(C.normalizeHex("#11223344"), "#112233")
  assert.equal(C.normalizeHex("nope"), "")
})

test("draft comes from the palette in use; saving gives a file that resolves to the same colors", () => {
  const settings = E.parseFlatToml('head_color = "#ffffff"\ntail_colors = "#ff1f3d | #ff7a00 | #ffb000 | #ffee00 | #9dff00 | #00ff4c | #00ffb3 | #00e5ff | #0091ff | #3d4dff | #9b3dff | #ff2bd6"\n')
  const config = S.resolve({}, settings)
  const palette = S.palette(config, {}, { foreground: "#ffffff", background: "#000000", accent: "#00ff00", urgent: "#ff0000" })
  const draft = C.draftFrom(config, palette, "#0b0b12")
  assert.equal(draft.groups.length, 12)
  assert.equal(draft.fade, 0.5)
  assert.equal(draft.shift, 6)
  const text = C.serialize(draft, "spectrum", "font_size = 14\nhead_color = \"#123456\"\n# old comment\n")
  assert.match(text, /font_size = 14/)
  assert.doesNotMatch(text, /#123456|old comment/)
  const back = S.resolve({}, E.parseFlatToml(text), "custom")
  assert.deepEqual(plain(S.palette(back, {}, {})).slice(8), plain(palette).slice(8))
  assert.equal(back.tailFade, 0.5)
  assert.equal(S.backgroundColor(back, {}, {}), "#0b0b12")
})

test("editing: set colors, add and remove shades and groups within 12 colors", () => {
  let d = { head: "#ffffff", background: "#000000", groups: [["#ff0000"]], fade: 0, shift: 0 }
  d = C.withColor(d, "g0s0", "#00ff00")
  assert.equal(C.colorAt(d, "g0s0"), "#00ff00")
  d = C.withColor(d, "head", "nope")  // ignored
  assert.equal(d.head, "#ffffff")
  d = C.withShadeAdded(d, 0)
  assert.equal(d.groups[0].length, 2)
  d = C.withGroupAdded(d)
  assert.equal(d.groups.length, 2)
  for (let i = 0; i < 20; i++) d = C.withGroupAdded(d)
  assert.equal(C.colorCount(d), 12)
  d = C.withShadeRemoved(d, 1, 0)
  assert.equal(C.colorCount(d), 11)
  let one = { head: "#fff", background: "#000", groups: [["#ff0000"]], fade: 0, shift: 0 }
  assert.equal(C.colorCount(C.withShadeRemoved(one, 0, 0)), 1)  // the last color stays
  assert.deepEqual(plain(C.previewTailGroups(d)).flat().length, 11)
})

test("speed: steps per second and update_delay convert both ways, within the slider's range", () => {
  assert.equal(C.delayFromRate(C.rateFromDelay(9.375)), 9.375)
  assert.equal(C.delayFromRate(12), 8.333)            // the default speed
  assert.ok(Math.abs(C.rateFromDelay(9.375) - 10.667) < 0.001)
  assert.equal(C.delayFromRate(10), 10)
  assert.equal(C.rateFromDelay(0), C.MAX_RATE)
  assert.equal(C.delayFromRate(1000), 2)          // clamped to 50 steps/s
  assert.equal(C.delayFromRate(1), 28.571)        // clamped to 3.5 steps/s
})

test("typefaces: fc-list output becomes a clean, sorted family list", () => {
  const fc = "Liberation Mono\nCaskaydiaCove Nerd Font Mono,CaskaydiaCove NFM\nCaskaydiaCove Nerd Font Mono,CaskaydiaCove NFM,CaskaydiaCove NFM Light\nNoto Color Emoji\nomarchy\nadwaita Mono\n\n"
  assert.deepEqual(plain(C.monoFamilies(fc)), ["adwaita Mono", "CaskaydiaCove Nerd Font Mono", "Liberation Mono"])
})

test("a saved palette file holds colors only; hand-written settings in it are kept", () => {
  const d = { head: "#ffffff", background: "#000000", groups: [["#ff0000"]], fade: 0.9, shift: 2 }
  const text = C.serialize(d, "nord", "tail_fade = 0.3\nbold = \"none\"\n")
  assert.doesNotMatch(text, /tail_hue_shift/)
  assert.match(text, /tail_fade = 0\.3/)     // hand-written, kept as is
  assert.match(text, /bold = "none"/)
  assert.match(text, /head_color = "#ffffff"/)
})

test("slider values snap to their steps", () => {
  assert.equal(C.snap(0.49676513671875, 0.05), 0.5)
  assert.equal(C.snap(2.83, 0.5), 3)
  assert.equal(C.snap(11.96, 0.5), 12)
  assert.equal(C.delayFromRate(C.snap(11.96, 0.5)), 8.333)
})
