.pragma library

// Matrix Screens engine (from omatrix) — a line-for-line port of the terminal model in cmatrix 2.0
// (https://github.com/abishekvashok/cmatrix, cmatrix.c: var_init() and the
// main `while (1)` loop). The screen is a grid of COLS x (LINES + 1) cells,
// only every second column is used (`j += 2`), row 0 is an off-screen staging
// row and rows 1..LINES are what the terminal shows. Every call to `tick()`
// is exactly one iteration of cmatrix's loop, which upstream follows with
// `napms(update * 10)` — 40 ms by default, i.e. a 25 Hz terminal refresh.
//
// This file has no QML dependencies so it can be unit-tested with node.

var EMPTY = -1      // upstream: val == -1
var SPACE = -2      // upstream: val == ' '
var HEAD_MARK = -3  // upstream (old style only): val == 0, drawn as a white '&'
var PIPE = -4       // upstream (old style only): val == 1, drawn as '|'

var NO_GLYPH = 255  // frame byte meaning "nothing to draw in this cell"

// Palette slots referenced by frame color bytes. Slot 1 is cmatrix's
// `mcolor` (-C, green by default); the rest are the ncurses pairs the
// rainbow mode cycles through.
var COLOR_HEAD = 0     // COLOR_WHITE
var COLOR_MATRIX = 1   // mcolor
var COLOR_GREEN = 2
var COLOR_BLUE = 3
var COLOR_BLACK = 4
var COLOR_YELLOW = 5
var COLOR_CYAN = 6
var COLOR_MAGENTA = 7
var RAINBOW_COLORS = [COLOR_GREEN, COLOR_BLUE, COLOR_BLACK, COLOR_YELLOW, COLOR_CYAN, COLOR_MAGENTA]

var SPECIAL_AMP = 0     // offset of '&' after the charset glyphs
var SPECIAL_PIPE = 1    // offset of '|'
var SPECIAL_LAMBDA = 2  // offset of 'λ'

function rangeGlyphs(from, to) {
  var out = []
  for (var code = from; code < to; code++) out.push(String.fromCharCode(code))
  return out
}

// cmatrix picks `rand() % randnum + randmin` with these ranges.
function charsetInfo(name) {
  switch (String(name || "ascii")) {
  case "katakana": // -c: half-width kana, U+FF66 .. U+FF9C
    return { randmin: 0xff66, glyphs: rangeGlyphs(0xff66, 0xff9d) }
  case "console":  // -l / -x: the mtx console font range 166 .. 216
    return { randmin: 166, glyphs: rangeGlyphs(166, 217) }
  default:         // plain terminal: printable ASCII '!' .. 'z'
    return { randmin: 33, glyphs: rangeGlyphs(33, 123) }
  }
}

// The atlas holds the charset plus the three glyphs cmatrix prints directly.
function glyphTable(charset) {
  var info = charsetInfo(charset)
  return {
    randmin: info.randmin,
    count: info.glyphs.length,
    glyphs: info.glyphs.concat(["&", "|", "λ"])
  }
}

function defaultRandom(n) {
  return n > 0 ? Math.floor(Math.random() * n) : 0
}

// Options are normalized once per change (see prepareOptions) rather than on
// every tick; a prepared object is passed straight through.
function normalizeOptions(opts) {
  opts = opts || {}
  if (opts.__prepared) return opts
  return {
    __prepared: true,
    asynch: !!opts.asynch,
    bold: opts.bold === 2 ? 2 : (opts.bold === 1 ? 1 : 0),
    changes: !!opts.changes,
    oldstyle: !!opts.oldstyle,
    rainbow: !!opts.rainbow,
    lambda: !!opts.lambda,
    charset: opts.charset || "ascii",
    tailGroups: Array.isArray(opts.tailGroups) ? opts.tailGroups.filter(function (g) { return g && g.length > 0 }) : [],
    tailFade: Math.max(0, Math.min(1, Number(opts.tailFade) || 0)),
    tailHueShift: Math.max(0, Math.min(12, Number(opts.tailHueShift) || 0)),
    fastIdle: opts.fastIdle !== false,
    random: typeof opts.random === "function" ? opts.random : defaultRandom
  }
}

function prepareOptions(opts) {
  return normalizeOptions(opts)
}

// var_init(): allocate the grid and seed every used column.
function create(cols, lines, opts) {
  var o = normalizeOptions(opts)
  cols = Math.max(1, cols | 0)
  lines = Math.max(4, lines | 0) // upstream needs LINES > 3 for `rand() % (LINES - 3)`

  var table = glyphTable(o.charset)
  var cells = new Int16Array((lines + 1) * cols)
  var heads = new Uint8Array((lines + 1) * cols)
  var length = new Int32Array(cols)
  var spaces = new Int32Array(cols)
  var updates = new Int32Array(cols)
  var groups = new Uint8Array(cols)      // tail color group of each column's newest stream

  for (var i = 0; i < cells.length; i++) cells[i] = EMPTY

  // Cells written since the last render, so drawing can be incremental like
  // a terminal instead of re-scanning the whole grid every tick.
  var dirty = new Int32Array(cells.length)
  var dirtyFlags = new Uint8Array(cells.length)

  // Glyph cells per column. A column with none that is still counting down
  // spaces[] has nothing for the per-tick walk to find, so it can be skipped.
  var occupied = new Int32Array(cols)

  // Tail fade bookkeeping: each column counts its own updates, and every cell
  // remembers the count it was written at, so a cell's age is its distance
  // behind its stream's head even after the head has left the screen.
  var colTick = new Int32Array(cols)
  var birth = new Int32Array(cells.length)
  var span = new Int32Array(cells.length)   // stream length the cell last fell under
  // Color group of the stream each cell belongs to. groups[j] only tracks a
  // column's newest stream, so an older stream still falling below it keeps
  // its own color when every cell is re-rendered.
  var cellGroup = new Uint8Array(cells.length)

  for (var j = 0; j < cols; j += 2) {
    spaces[j] = o.random(lines) + 1        // how many blank rows before the next stream
    length[j] = o.random(lines - 3) + 3    // stream length
    cells[cols + j] = SPACE                // matrix[1][j] = ' ' sentinel for creation
    updates[j] = o.random(3) + 1           // -a pacing class
    if (o.tailGroups.length > 0) groups[j] = o.random(o.tailGroups.length)
  }

  return {
    cols: cols,
    lines: lines,
    cells: cells,
    heads: heads,
    length: length,
    spaces: spaces,
    updates: updates,
    groups: groups,
    dirty: dirty,
    dirtyFlags: dirtyFlags,
    occupied: occupied,
    colTick: colTick,
    birth: birth,
    span: span,
    cellGroup: cellGroup,
    dirtyCount: 0,
    count: 0,
    glyphCount: table.count,
    randmin: table.randmin,
    glyphs: table.glyphs
  }
}

function markDirty(s, idx) {
  if (s.dirtyFlags[idx]) return
  s.dirtyFlags[idx] = 1
  s.dirty[s.dirtyCount++] = idx
}

function setCell(s, idx, value) {
  var old = s.cells[idx]
  if (old === value) return
  s.cells[idx] = value
  if ((old >= 0) !== (value >= 0)) s.occupied[idx % s.cols] += value >= 0 ? 1 : -1
  if (value >= 0 && old < 0) {
    var j = idx % s.cols
    s.birth[idx] = s.colTick[j]
    // A head advancing continues the stream above it; a cell with nothing
    // above starts a new stream in the column's current group.
    s.cellGroup[idx] = idx >= s.cols && s.cells[idx - s.cols] >= 0 ? s.cellGroup[idx - s.cols] : s.groups[j]
  }
  markDirty(s, idx)
}

function setHead(s, idx, value) {
  if (s.heads[idx] === value) return
  s.heads[idx] = value
  markDirty(s, idx)
}

function clearDirty(s) {
  for (var k = 0; k < s.dirtyCount; k++) s.dirtyFlags[s.dirty[k]] = 0
  s.dirtyCount = 0
}

function tickColumnOldStyle(s, j, o) {
  var cols = s.cols, lines = s.lines, cells = s.cells
  var i
  for (i = lines - 1; i >= 1; i--) setCell(s, i * cols + j, cells[(i - 1) * cols + j])

  var random = o.random(s.glyphCount + 8)
  var below = cells[cols + j]

  if (below === HEAD_MARK) {
    setCell(s, j, PIPE)
  } else if (below === SPACE || below === EMPTY) {
    if (s.spaces[j] > 0) {
      setCell(s, j, SPACE)
      s.spaces[j]--
    } else {
      // Random number to determine whether head of next column of chars has
      // a white 'head' on it.
      if (o.tailGroups.length > 0) s.groups[j] = o.random(o.tailGroups.length)
      if (o.random(3) === 1) setCell(s, j, HEAD_MARK)
      else setCell(s, j, o.random(s.glyphCount))
      s.spaces[j] = o.random(lines) + 1
    }
  } else if (random >= s.glyphCount && below !== PIPE) {
    setCell(s, j, SPACE)
  } else {
    setCell(s, j, o.random(s.glyphCount))
  }
}

function tickColumnNewStyle(s, j, o) {
  var cols = s.cols, lines = s.lines, cells = s.cells, heads = s.heads

  if (cells[j] === EMPTY && cells[cols + j] === SPACE && s.spaces[j] > 0) {
    s.spaces[j]--
    // Upstream walks the column anyway, finds only spaces and does nothing;
    // the walk consumes no randomness, so skipping it is unobservable.
    if (o.fastIdle && s.occupied[j] === 0) return
  } else if (cells[j] === EMPTY && cells[cols + j] === SPACE) {
    s.length[j] = o.random(lines - 3) + 3
    if (o.tailGroups.length > 0) s.groups[j] = o.random(o.tailGroups.length)
    setCell(s, j, o.random(s.glyphCount))
    s.spaces[j] = o.random(lines) + 1
  }

  var i = 0
  var y = 0
  var z = 0
  var firstcoldone = false

  while (i <= lines) {
    // Skip over spaces
    while (i <= lines && cells[i * cols + j] < 0) i++
    if (i > lines) break

    // Go to the head of this column
    z = i
    y = 0
    while (i <= lines && cells[i * cols + j] >= 0) {
      if (heads[i * cols + j]) setHead(s, i * cols + j, 0)
      if (o.changes && o.random(8) === 0) setCell(s, i * cols + j, o.random(s.glyphCount))
      i++
      y++
    }

    if (i > lines) {
      setCell(s, z * cols + j, SPACE)
      continue
    }

    setCell(s, i * cols + j, o.random(s.glyphCount))
    setHead(s, i * cols + j, 1)

    // If we're at the top of the column and it's reached its full length
    // (about to start moving down), we do this to get it moving. This is
    // also how we keep segments not already growing from growing
    // accidentally.
    if (y > s.length[j] || firstcoldone) {
      setCell(s, z * cols + j, SPACE)
      setCell(s, j, EMPTY)
    }
    firstcoldone = true
    i++
  }
}

// One iteration of cmatrix's main loop (minus keyboard handling and drawing).
function tick(s, opts) {
  var o = normalizeOptions(opts)

  s.count++
  if (s.count > 4) s.count = 1

  for (var j = 0; j < s.cols; j += 2) {
    if (s.count > s.updates[j] || !o.asynch) {
      s.colTick[j]++
      if (o.oldstyle) tickColumnOldStyle(s, j, o)
      else tickColumnNewStyle(s, j, o)
    }
  }
}

// The drawing pass. Produces the terminal's visible rows as a byte triple
// (glyph index, palette slot, bold flag) per cell in `frame`, which must be
// a Uint8Array of at least cols * lines * 3 bytes. Mirrors the attron /
// addch sequence that follows each column update upstream.
function renderCell(s, o, frame, row, j, t) {
  var cols = s.cols
  var out = (row * cols + j) * 3
  var idx = (row + (o.oldstyle ? 0 : 1)) * cols + j
  var val = s.cells[idx]

  if ((j & 1) === 1 || val === EMPTY || val === SPACE) {
    frame[out] = NO_GLYPH
    frame[out + 1] = 0
    frame[out + 2] = 0
    return
  }

  if (val === HEAD_MARK || (s.heads[idx] && !o.rainbow)) {
    frame[out] = val === HEAD_MARK ? s.glyphCount + SPECIAL_AMP : val
    frame[out + 1] = COLOR_HEAD
    frame[out + 2] = o.bold ? 1 : 0
    return
  }

  var color = COLOR_MATRIX
  if (o.rainbow) color = RAINBOW_COLORS[o.random(6)]
  else if (o.tailGroups.length > 0) {
    // A cell is rendered when written and again when the head moves on, so
    // the shade picked here stays put until the cell is erased.
    var group = o.tailGroups[(positional(o) ? s.cellGroup[idx] : s.groups[j]) % o.tailGroups.length]
    if (o.tailHueShift > 0) {
      // Hue sweep: from the stream's own color at the head, forward through
      // the flat tail color list (palette slots 8.., wrapping) by
      // tailHueShift colors at the tail end. The fractional part becomes a
      // blend toward the next slot in eighths, done by the shader.
      var n = tailColorCount(o)
      var pos = (group[0] - TAIL_SLOT) + (t || 0) * o.tailHueShift
      var step = Math.floor(pos)
      color = TAIL_SLOT + (step % n) | (Math.min(7, Math.floor((pos - step) * HUE_STEPS)) << 5)
    } else if (o.tailFade > 0) {
      // With a tail fade every cell is re-rendered each tick, so its shade
      // must be a pure function of the cell (position, glyph, write time),
      // not a fresh random pick, or the tails would flicker.
      color = group[(((Math.imul(idx, 0x9e3779b1) ^ Math.imul(val + 1, 0x85ebca6b) ^ s.birth[idx]) >>> 3) % group.length)]
    } else {
      color = group[o.random(group.length)]
    }
  }

  if (val === PIPE) {
    frame[out] = s.glyphCount + SPECIAL_PIPE
    frame[out + 1] = color
    frame[out + 2] = o.bold ? 1 : 0
    return
  }

  var codepoint = val + s.randmin
  var bold = o.bold === 2 || (o.bold === 1 && (codepoint % 2) === 0)
  frame[out] = o.lambda ? s.glyphCount + SPECIAL_LAMBDA : val
  frame[out + 1] = color
  // Bit 0: bold. Bits 1..5: tail fade level (0 = full brightness, FADE_LEVELS
  // = faded to the configured floor), decoded by the shader.
  var dim = o.tailFade > 0 && color !== COLOR_HEAD ? Math.round((t || 0) * o.tailFade * FADE_LEVELS) : 0
  frame[out + 2] = (bold ? 1 : 0) | (dim << 1)
}

var FADE_LEVELS = 31
// Color byte: bits 0..4 palette slot, bits 5..7 blend toward the next tail
// slot in eighths (hue sweep only).
var HUE_STEPS = 8
var TAIL_SLOT = 8

function tailColorCount(o) {
  if (o.__tailCount === undefined) {
    var n = 0
    for (var g = 0; g < o.tailGroups.length; g++) n += o.tailGroups[g].length
    o.__tailCount = Math.max(1, n)
  }
  return o.__tailCount
}

// Whether tails depend on their position in the stream (and so need every
// cell re-rendered each tick).
function positional(o) {
  return !o.oldstyle && !o.rainbow && o.tailGroups.length > 0 && (o.tailFade > 0 || o.tailHueShift > 0)
}

// Position of every visible cell in column j along its stream, written to
// pos[row]: 0 right behind the head, 1 at the stream's oldest cell. The tail
// fade and hue sweep are both functions of it.
function columnPositions(s, o, j, pos) {
  var cols = s.cols, lines = s.lines, cells = s.cells
  var tick = s.colTick[j]
  for (var r = 0; r < lines; r++) pos[r] = 0
  var i = 0
  while (i <= lines) {
    while (i <= lines && cells[i * cols + j] < 0) i++
    if (i > lines) break
    var z = i
    while (i <= lines && cells[i * cols + j] >= 0) i++
    var e = i - 1
    // While the head is on screen the stream's length is the age of its
    // oldest cell; remember it so the tail keeps its gradient once the head
    // has fallen off the bottom.
    var len = s.heads[e * cols + j] ? tick - s.birth[z * cols + j] : s.span[z * cols + j]
    if (len < 2) len = 2
    for (var c = z; c <= e; c++) {
      var idx = c * cols + j
      s.span[idx] = len
      if (c === 0) continue
      var age = tick - s.birth[idx]
      pos[c - 1] = Math.max(0, Math.min(1, (age - 1) / (len - 1)))
    }
  }
}

// Full redraw of every visible cell (a terminal `clear` + repaint).
function render(s, opts, frame) {
  var o = normalizeOptions(opts)
  var along = positional(o)
  var pos = along ? new Float32Array(s.lines) : null
  for (var j = 0; j < s.cols; j++) {
    if (along && (j & 1) === 0) columnPositions(s, o, j, pos)
    for (var row = 0; row < s.lines; row++) renderCell(s, o, frame, row, j, along ? pos[row] : 0)
  }
  clearDirty(s)
}

// Incremental redraw: only the cells the last ticks wrote. Appends the
// frame index (row * cols + col) of every re-rendered visible cell to
// `touched` (an Int32Array) starting at `touchedCount` and returns the new
// count. Rainbow mode recolors every cell per frame upstream, so it needs
// render() instead.
function renderDirty(s, opts, frame, touched, touchedCount) {
  var o = normalizeOptions(opts)
  var cols = s.cols, lines = s.lines
  var y0 = o.oldstyle ? 0 : 1
  for (var k = 0; k < s.dirtyCount; k++) {
    var idx = s.dirty[k]
    var j = idx % cols
    if ((j & 1) === 1) continue
    var row = ((idx - j) / cols) - y0
    if (row < 0 || row >= lines) continue
    renderCell(s, o, frame, row, j)
    touched[touchedCount++] = row * cols + j
  }
  clearDirty(s)
  return touchedCount
}

// cmatrix's -u delay maps to napms(update * 10); update 0 means "as fast as
// the terminal can go", which for a compositor is one frame.
function intervalMs(updateDelay) {
  var u = Math.max(0, Math.min(30, Number(updateDelay) || 0))
  return u === 0 ? 16 : Math.round(u * 10)
}

// ---------------------------------------------------------------- settings

// Minimal TOML reader for the flat `key = value` files themes ship.
function parseFlatToml(raw) {
  var out = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (!line || line.charAt(0) === "#" || line.charAt(0) === "[") continue
    var eq = line.indexOf("=")
    if (eq < 0) continue
    var key = line.substring(0, eq).replace(/^\s+|\s+$/g, "")
    var value = line.substring(eq + 1).replace(/^\s+|\s+$/g, "")
    var quoted = value.match(/^"((?:[^"\\]|\\.)*)"(\s*#.*)?$/)
    if (quoted) {
      out[key] = quoted[1].replace(/\\"/g, "\"")
      continue
    }
    value = value.replace(/\s+#.*$/, "")
    if (value === "true") out[key] = true
    else if (value === "false") out[key] = false
    else if (/^-?\d+(\.\d+)?$/.test(value)) out[key] = Number(value)
    else out[key] = value
  }
  return out
}
