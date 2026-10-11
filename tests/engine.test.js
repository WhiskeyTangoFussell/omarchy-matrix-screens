// Run with: node --test tests/
// Exercises the cmatrix port outside Quickshell. The engine is a `.pragma
// library` QML script, so it is loaded through vm with that line stripped.

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

function loadEngine() {
  const source = fs.readFileSync(path.join(__dirname, "..", "cmatrix.js"), "utf8")
  const context = { Math, Number, String, Int16Array, Int32Array, Uint8Array, Float32Array }
  vm.createContext(context)
  vm.runInContext(source.replace(/^\.pragma library\s*/, ""), context)
  return context
}

// Deterministic LCG so runs are reproducible.
function seededRandom(seed) {
  let state = seed >>> 0
  return function (n) {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0
    return n > 0 ? state % n : 0
  }
}

// Objects created inside the vm realm have foreign prototypes; normalise for deepEqual.
function plain(value) { return JSON.parse(JSON.stringify(value)) }

const M = loadEngine()

function segmentsOf(s, j) {
  const segments = []
  let i = 1
  while (i <= s.lines) {
    while (i <= s.lines && s.cells[i * s.cols + j] < 0) i++
    if (i > s.lines) break
    const start = i
    while (i <= s.lines && s.cells[i * s.cols + j] >= 0) i++
    segments.push({ start, end: i - 1 })
  }
  return segments
}

test("var_init seeds only even columns with the sentinel", () => {
  const s = M.create(10, 20, { random: seededRandom(1) })
  for (let j = 0; j < s.cols; j++) {
    const sentinel = s.cells[s.cols + j]
    if (j % 2 === 0) {
      assert.equal(sentinel, M.SPACE)
      assert.ok(s.spaces[j] >= 1 && s.spaces[j] <= s.lines)
      assert.ok(s.length[j] >= 3 && s.length[j] <= s.lines - 1)
      assert.ok(s.updates[j] >= 1 && s.updates[j] <= 3)
    } else {
      assert.equal(sentinel, M.EMPTY)
    }
  }
})

test("glyph tables follow cmatrix's rand ranges", () => {
  assert.equal(M.glyphTable("ascii").count, 90)          // 33 .. 122
  assert.equal(M.glyphTable("ascii").glyphs[0], "!")
  assert.equal(M.glyphTable("ascii").glyphs[89], "z")
  assert.equal(M.glyphTable("katakana").count, 0xff9d - 0xff66)
  assert.equal(M.glyphTable("console").count, 217 - 166)
  assert.deepEqual(plain(M.glyphTable("ascii").glyphs.slice(90)), ["&", "|", "λ"])
})

test("new-style streams stay bounded by their length and never overlap", () => {
  const opts = { random: seededRandom(7) }
  const s = M.create(80, 24, opts)
  for (let step = 0; step < 2000; step++) {
    M.tick(s, opts)
    for (let j = 0; j < s.cols; j += 2) {
      const segments = segmentsOf(s, j)
      // A stream grows until it exceeds length[j], then the tail is dropped
      // every tick, so it can never be more than length + 1 cells long.
      for (const seg of segments) assert.ok(seg.end - seg.start + 1 <= s.length[j] + 1 + s.lines, "segment bounded")
      // Every visible stream that is still on screen has at most one head.
      let heads = 0
      for (let i = 1; i <= s.lines; i++) heads += s.heads[i * s.cols + j] && s.cells[i * s.cols + j] >= 0 ? 1 : 0
      assert.ok(heads <= segments.length, "at most one head per segment")
    }
    for (let j = 1; j < s.cols; j += 2) {
      for (let i = 0; i <= s.lines; i++) assert.equal(s.cells[i * s.cols + j], M.EMPTY, "odd columns untouched")
    }
  }
})

test("synchronous mode advances every column each tick, -a paces by updates[]", () => {
  const sync = M.create(6, 12, { random: seededRandom(3) })
  const before = Array.from(sync.cells)
  // Force a stream to exist so a tick is observable in every even column.
  for (let j = 0; j < sync.cols; j += 2) { sync.spaces[j] = 0 }
  M.tick(sync, { random: seededRandom(3) })
  for (let j = 0; j < sync.cols; j += 2) {
    assert.notDeepEqual(Array.from(sync.cells).filter((_, k) => k % sync.cols === j), before.filter((_, k) => k % sync.cols === j))
  }

  const async = M.create(6, 12, { random: seededRandom(3) })
  async.updates[0] = 3 // only moves when count > 3, i.e. every 4th tick
  async.spaces[0] = 0
  const column0 = () => Array.from(async.cells).filter((_, k) => k % async.cols === 0)
  const start = column0()
  M.tick(async, { asynch: true, random: seededRandom(9) }) // count 1
  M.tick(async, { asynch: true, random: seededRandom(9) }) // count 2
  M.tick(async, { asynch: true, random: seededRandom(9) }) // count 3
  assert.deepEqual(column0(), start)
  M.tick(async, { asynch: true, random: seededRandom(9) }) // count 4 > 3
  assert.notDeepEqual(column0(), start)
})

test("old-style scrolling shifts columns down and only emits known codes", () => {
  const opts = { oldstyle: true, random: seededRandom(11) }
  const s = M.create(20, 15, opts)
  for (let step = 0; step < 500; step++) {
    const prev = Array.from(s.cells)
    M.tick(s, opts)
    for (let j = 0; j < s.cols; j += 2) {
      for (let i = 1; i < s.lines; i++) assert.equal(s.cells[i * s.cols + j], prev[(i - 1) * s.cols + j])
      for (let i = 0; i <= s.lines; i++) {
        const v = s.cells[i * s.cols + j]
        assert.ok(v >= -4 && v < s.glyphCount, `cell code ${v} in range`)
      }
    }
  }
})

test("render emits glyph/color/bold triples and blank odd columns", () => {
  const opts = { random: seededRandom(5), bold: 1 }
  const s = M.create(40, 20, opts)
  for (let step = 0; step < 60; step++) M.tick(s, opts)
  const frame = new Uint8Array(s.cols * s.lines * 3)
  M.render(s, opts, frame)

  let drawn = 0
  let heads = 0
  for (let row = 0; row < s.lines; row++) {
    for (let j = 0; j < s.cols; j++) {
      const k = (row * s.cols + j) * 3
      if (j % 2 === 1) { assert.equal(frame[k], M.NO_GLYPH); continue }
      if (frame[k] === M.NO_GLYPH) continue
      drawn++
      assert.ok(frame[k] < s.glyphCount + 3)
      assert.ok(frame[k + 1] >= 0 && frame[k + 1] <= 7)
      assert.ok(frame[k + 2] === 0 || frame[k + 2] === 1)
      if (frame[k + 1] === M.COLOR_HEAD) {
        heads++
        assert.equal(frame[k + 2], 1, "heads are bold with -b")
      } else {
        // -b: bold when the ASCII code is even
        const code = frame[k] + s.randmin
        assert.equal(frame[k + 2], code % 2 === 0 ? 1 : 0)
      }
    }
  }
  assert.ok(drawn > 0, "something is on screen after 60 ticks")
  assert.ok(heads > 0, "streams have white heads")
})

test("lambda and rainbow modes change what non-head cells draw", () => {
  const opts = { random: seededRandom(21) }
  const s = M.create(40, 20, opts)
  for (let step = 0; step < 80; step++) M.tick(s, opts)
  const frame = new Uint8Array(s.cols * s.lines * 3)

  M.render(s, { lambda: true, random: seededRandom(1) }, frame)
  const lambdaIndex = s.glyphCount + M.SPECIAL_LAMBDA
  let tails = 0
  for (let k = 0; k < frame.length; k += 3) {
    if (frame[k] === M.NO_GLYPH || frame[k + 1] === M.COLOR_HEAD) continue
    assert.equal(frame[k], lambdaIndex)
    tails++
  }
  assert.ok(tails > 0)

  M.render(s, { rainbow: true, random: seededRandom(2) }, frame)
  const colors = new Set()
  for (let k = 0; k < frame.length; k += 3) {
    if (frame[k] === M.NO_GLYPH) continue
    assert.notEqual(frame[k + 1], M.COLOR_HEAD, "rainbow never paints heads white")
    colors.add(frame[k + 1])
  }
  assert.ok(colors.size > 1)
})

test("incremental rendering reproduces the full frame exactly", () => {
  for (const variant of [{}, { changes: true, bold: 1 }, { asynch: true, lambda: true }]) {
    const opts = Object.assign({ random: seededRandom(77) }, variant)
    const s = M.create(60, 30, opts)
    const incremental = new Uint8Array(s.cols * s.lines * 3)
    const touched = new Int32Array(s.cols * s.lines)
    M.render(s, opts, incremental)
    let totalDirty = 0
    for (let step = 0; step < 400; step++) {
      M.tick(s, opts)
      const dirty = s.dirtyCount
      totalDirty += dirty
      // Per column and tick cmatrix writes at most a new head, the old head's
      // flag, a cleared tail, the staging cell and a few -k mutations.
      assert.ok(dirty < s.cols * 6, `a tick touches few cells (${dirty})`)
      const n = M.renderDirty(s, opts, incremental, touched, 0)
      assert.ok(n <= dirty)
      assert.equal(s.dirtyCount, 0)
      const full = new Uint8Array(s.cols * s.lines * 3)
      M.render(s, opts, full)
      assert.deepEqual(Array.from(incremental), Array.from(full))
    }
    assert.ok(totalDirty > 0)
  }
})

test("skipping idle columns is unobservable: same cells, heads and randomness", () => {
  const a = M.create(80, 30, { random: seededRandom(5) })
  const b = M.create(80, 30, { random: seededRandom(5) })
  const optsA = M.prepareOptions({ random: seededRandom(6), fastIdle: true })
  const optsB = M.prepareOptions({ random: seededRandom(6), fastIdle: false })
  for (let step = 0; step < 1500; step++) {
    M.tick(a, optsA)
    M.tick(b, optsB)
    assert.deepEqual(Array.from(a.cells), Array.from(b.cells))
    assert.deepEqual(Array.from(a.heads), Array.from(b.heads))
    for (let j = 0; j < a.cols; j++) {
      let glyphs = 0
      for (let i = 0; i <= a.lines; i++) if (a.cells[i * a.cols + j] >= 0) glyphs++
      assert.equal(a.occupied[j], glyphs, "occupied count tracks glyph cells")
    }
  }
})

test("update delay maps to cmatrix's napms(update * 10)", () => {
  assert.equal(M.intervalMs(4), 40)
  assert.equal(M.intervalMs(10), 100)
  assert.equal(M.intervalMs(0), 16)
  assert.equal(M.intervalMs(30), 300)
  assert.equal(M.intervalMs(99), 300)
})

test("flat toml reader handles the value shapes a theme file uses", () => {
  const parsed = M.parseFlatToml([
    "# comment",
    "[section]",
    'bold = "partial"',
    "update_delay = 4",
    "asynchronous = true # trailing",
    'color = "#549e6a"',
    "opacity = 0.9",
  ].join("\n"))
  assert.deepEqual(plain(parsed), { bold: "partial", update_delay: 4, asynchronous: true, color: "#549e6a", opacity: 0.9 })
})

test("tail fade: heads at full brightness, tails dim away from the head", () => {
  const groups = [[8, 9], [10, 11]]
  const opts = M.prepareOptions({ random: seededRandom(11), tailGroups: groups, tailFade: 0.8 })
  const s = M.create(60, 30, opts)
  const frame = new Uint8Array(s.cols * s.lines * 3)
  const maxDim = Math.round(0.8 * 31)
  let checkedRuns = 0
  for (let step = 0; step < 400; step++) {
    M.tick(s, opts)
    M.render(s, opts, frame)
    for (let j = 0; j < s.cols; j += 2) {
      for (const seg of segmentsOf(s, j)) {
        let below = -1
        // Walk from the bottom (head end) up: the fade level never decreases.
        for (let r = seg.end; r >= seg.start; r--) {
          const k = ((r - 1) * s.cols + j) * 3
          const dim = frame[k + 2] >> 1
          assert.ok(dim <= maxDim, "dim within configured floor")
          if (frame[k + 1] === 0) assert.equal(dim, 0, "heads are never faded")
          if (below >= 0) assert.ok(dim >= below, "dims away from the head")
          below = dim
        }
        if (seg.end - seg.start >= 4) checkedRuns++
      }
    }
  }
  assert.ok(checkedRuns > 100, "exercised real streams")
})

test("tail fade: shades are stable between renders and fade 0 leaves frames unchanged", () => {
  const groups = [[8, 9, 10]]
  const fadeOpts = M.prepareOptions({ random: seededRandom(5), tailGroups: groups, tailFade: 0.5 })
  const s = M.create(40, 20, fadeOpts)
  for (let step = 0; step < 60; step++) M.tick(s, fadeOpts)
  const a = new Uint8Array(s.cols * s.lines * 3)
  const b = new Uint8Array(s.cols * s.lines * 3)
  M.render(s, fadeOpts, a)
  M.render(s, fadeOpts, b)
  assert.deepEqual(Array.from(a), Array.from(b))

  const plainOpts = M.prepareOptions({ random: seededRandom(5), tailGroups: groups })
  const p = M.create(40, 20, plainOpts)
  for (let step = 0; step < 60; step++) M.tick(p, plainOpts)
  const f = new Uint8Array(p.cols * p.lines * 3)
  M.render(p, plainOpts, f)
  for (let k = 2; k < f.length; k += 3) assert.ok(f[k] <= 1, "no fade bits without tail_fade")
})

test("tail hue shift: color sweeps forward from the stream's own hue toward the tail end", () => {
  const groups = [[8], [9], [10], [11], [12], [13]]
  const shift = 2
  const opts = M.prepareOptions({ random: seededRandom(3), tailGroups: groups, tailHueShift: shift, tailFade: 0.5 })
  const s = M.create(60, 30, opts)
  const frame = new Uint8Array(s.cols * s.lines * 3)
  const n = 6
  let checked = 0
  for (let step = 0; step < 400; step++) {
    M.tick(s, opts)
    M.render(s, opts, frame)
    for (let j = 0; j < s.cols; j += 2) {
      for (const seg of segmentsOf(s, j)) {
        const base = groups[s.cellGroup[seg.end * s.cols + j] % groups.length][0] - 8
        let prev = -1
        for (let r = seg.end - 1; r >= seg.start; r--) {
          const k = ((r - 1) * s.cols + j) * 3
          const byte = frame[k + 1]
          const slot = byte & 31, sub = byte >> 5
          assert.ok(slot >= 8 && slot < 8 + n, "tail slot in range")
          // Unwrap relative to the stream's own color; must stay within [0, shift].
          const v = ((slot - 8 - base + n) % n) + sub / 8
          assert.ok(v >= 0 && v <= shift + 1e-9, "within sweep " + v)
          if (prev >= 0) assert.ok(v >= prev - 1e-9, "sweeps forward away from the head")
          prev = v
          checked++
        }
      }
    }
  }
  assert.ok(checked > 200, "exercised real streams")
})

test("positional tails: an older stream keeps its color when a newer one starts above it", () => {
  const groups = [[8], [9], [10], [11], [12], [13], [14], [15]]
  const opts = M.prepareOptions({ random: seededRandom(21), tailGroups: groups, tailFade: 0.6 })
  const s = M.create(40, 40, opts)
  const frame = new Uint8Array(s.cols * s.lines * 3)
  const seen = new Map()   // cell idx + birth -> palette slot
  let compared = 0
  for (let step = 0; step < 600; step++) {
    M.tick(s, opts)
    M.render(s, opts, frame)
    for (let j = 0; j < s.cols; j += 2) {
      for (let r = 1; r <= s.lines; r++) {
        const idx = r * s.cols + j
        const k = ((r - 1) * s.cols + j) * 3
        if (s.cells[idx] < 0 || frame[k + 1] === 0) continue
        const key = idx + ":" + s.birth[idx]
        const slot = frame[k + 1] & 31
        if (seen.has(key)) { assert.equal(slot, seen.get(key), "cell kept its stream color"); compared++ }
        else seen.set(key, slot)
      }
    }
  }
  assert.ok(compared > 1000, "exercised re-rendered cells")
})
