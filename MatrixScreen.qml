import Quickshell
import QtQuick
import "cmatrix.js" as CMatrix

// One terminal's worth of cmatrix, rendered on the GPU.
//
//   cmatrix.js   — the ported engine: a COLS x LINES grid of glyph codes that
//                  advances once per 40 ms terminal tick.
//   stateCanvas  — one small square per cell: R = glyph index, G = palette
//                  slot, B = bold. Only cells whose value changed since the
//                  last tick are repainted, which is exactly what ncurses
//                  does to a terminal. A Canvas allocates its image at item
//                  size x the window's device pixel ratio and antialiases
//                  fills, so a square's edges smear into its neighbours on a
//                  scaled monitor. Each square is therefore stateCellSize
//                  logical pixels (at least two texels at any scale), and the
//                  shader works out texels per cell from the image's real size
//                  and reads the texel at each square's center, which no edge
//                  touches. Nothing depends on knowing the ratio, which some
//                  surfaces (the session lock) don't report.
//   atlasCanvas  — every glyph of the charset drawn once with the system
//                  monospace font, regular on top, bold underneath.
//   effect       — a fragment shader that maps each screen pixel to a cell,
//                  reads its state and samples the atlas. The full-screen
//                  draw costs the same whether one cell changed or all did.
//
// Nothing here depends on the Omarchy shell; RainView.qml binds it to the
// plugin's settings.
Item {
  id: root

  // cmatrix flags
  property real updateDelay: 4         // -u
  property bool asynchronous: false    // -a
  property int boldLevel: 0            // -n 0, -b 1, -B 2
  property string charset: "ascii"     // "ascii", "katakana" (-c), "console" (-l)
  property bool lambda: false          // -m
  property bool changes: false         // -k
  property bool oldstyle: false        // -o
  property bool rainbow: false         // -r

  // Spread the drawn columns so the first is flush with the left edge of the
  // screen and the last flush with the right, instead of the terminal's fixed
  // two-cell pitch that leaves a ragged right edge.
  property bool justifyColumns: false

  // Tail color groups as palette slot numbers (settings.tailGroups); empty
  // for cmatrix's single -C color.
  property var tailGroups: []
  // 0..1: how far each tail dims from just behind the head to its oldest
  // cell (0 = off, every glyph at full color).
  property real tailFade: 0
  // How many tail colors (in tail_colors order, wrapping) each stream
  // sweeps through from its head to its oldest cell, blended smoothly.
  // 0 = off. Works best with one shade per group, listed in hue order.
  property real tailHueShift: 0
  readonly property int tailColorCount: {
    var n = 0
    for (var g = 0; g < tailGroups.length; g++) n += tailGroups[g].length
    return Math.max(1, n)
  }

  // "wake": every time the screen becomes visible it starts as an empty
  // terminal that fills up, like launching cmatrix. "full": start mid-run.
  property string start: "wake"
  // Bump to replay the wake from outside (IPC).
  property int wakeSerial: 0

  property bool running: true
  property real rainOpacity: 1.0
  property bool profile: false

  // Typography: the terminal grid is measured from this face, like a terminal
  // emulator measures its cell from the font's advance and line metrics.
  property string fontFamily: "monospace"
  property int fontPixelSize: 12

  // Palette slots (see cmatrix.js): 0 COLOR_WHITE head, 1 mcolor, then the
  // rainbow set green, blue, black, yellow, cyan, magenta.
  property var rainPalette: ["#C1C497", "#549e6a", "#549e6a", "#509475", "#111c18", "#459451", "#2DD5B7", "#D2689C"]

  // Side of each cell's square in the state canvas, in logical pixels.
  readonly property int stateCellSize: 2

  readonly property int ticksPerSecond: Math.round(1000 / CMatrix.intervalMs(updateDelay))
  readonly property int cols: Math.max(2, Math.floor(width / cellWidth))
  // Rows rounded up and the grid aligned to the bottom edge, so the bottom
  // row is always whole and flush with the screen; the leftover part-row
  // sits at the top (under the bar, on the desktop) instead of a blank strip
  // at the bottom.
  readonly property int lines: Math.max(4, Math.ceil(height / cellHeight))
  readonly property real gridTop: height - lines * cellHeight
  readonly property real columnStride: {
    var drawnColumns = Math.ceil(cols / 2)
    if (!justifyColumns || drawnColumns < 2) return 2 * cellWidth
    return (width - cellWidth) / (drawnColumns - 1)
  }
  readonly property Profiler profiler: Profiler {
    enabled: root.profile
    grid: root.cols + "x" + root.lines + " cells " + root.cellWidth + "x" + root.cellHeight
  }

  FontMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: root.fontPixelSize
  }

  // advanceWidth() is a method, so the binding must read metrics.font itself
  // to be re-evaluated once the family and size are applied.
  readonly property real advance: {
    var applied = metrics.font
    var m = metrics.advanceWidth("M")
    return m > 0 ? m : metrics.averageCharacterWidth
  }
  readonly property int cellWidth: Math.max(1, Math.round(advance))
  readonly property int cellHeight: Math.max(1, Math.round(metrics.ascent + metrics.descent))
  readonly property int glyphBaseline: Math.round(metrics.ascent)

  readonly property var glyphTable: CMatrix.glyphTable(charset)
  readonly property int atlasColumns: 16
  readonly property int atlasRows: Math.max(1, Math.ceil(glyphTable.glyphs.length / atlasColumns))

  // Normalized once per change; the engine passes prepared options through.
  readonly property var engineOptions: CMatrix.prepareOptions({
    asynch: asynchronous,
    bold: boldLevel,
    changes: changes,
    oldstyle: oldstyle,
    rainbow: rainbow,
    lambda: lambda,
    charset: charset,
    tailGroups: tailGroups,
    tailFade: tailFade,
    tailHueShift: tailHueShift
  })

  property var engine: null
  property var frame: null
  property var drawn: null
  property var touched: null
  property int touchedCount: 0
  property bool fullRepaint: true
  property bool fullRender: true
  property var styleCache: []

  // ---------------------------------------------------------------- engine

  function rebuild() {
    if (width <= 0 || height <= 0) return
    var options = engineOptions
    var state = CMatrix.create(cols, lines, options)
    if (start === "full") {
      for (var i = 0; i < lines * 2; i++) CMatrix.tick(state, options)
    }
    frame = new Uint8Array(state.cols * state.lines * 3)
    drawn = new Uint8Array(state.cols * state.lines * 3)
    touched = new Int32Array(state.cols * state.lines)
    touchedCount = 0
    fullRepaint = true
    fullRender = true
    engine = state
    CMatrix.render(state, options, frame)
    stateCanvas.requestPaint()
  }

  function step() {
    if (!engine) return
    var options = engineOptions
    var t0 = profiler.now()
    CMatrix.tick(engine, options)
    var t1 = profiler.now()

    // Rainbow recolors every cell each frame, old-style scrolling moves
    // every cell and a tail fade re-dims every tail as its head advances, so
    // those take the full path (paintCell still skips unchanged cells);
    // otherwise only the handful of cells cmatrix wrote are re-rendered,
    // like ncurses updating a terminal.
    if (options.rainbow || options.oldstyle || options.tailFade > 0 || options.tailHueShift > 0 || fullRender
        || touchedCount + engine.dirtyCount > touched.length) {
      CMatrix.render(engine, options, frame)
      fullRender = true
    } else {
      touchedCount = CMatrix.renderDirty(engine, options, frame, touched, touchedCount)
    }

    profiler.tick(t0, t1, profiler.now())
    stateCanvas.requestPaint()
  }

  // Re-render without advancing, for option changes that only affect drawing.
  function refresh() {
    if (!engine) return
    CMatrix.render(engine, engineOptions, frame)
    fullRender = true
    stateCanvas.requestPaint()
  }

  function cellStyle(glyph, slot, bold) {
    var key = (glyph * 256 + slot) * 256 + bold
    var style = styleCache[key]
    if (style === undefined) {
      style = "#" + (glyph < 16 ? "0" : "") + glyph.toString(16)
        + (slot < 16 ? "0" : "") + slot.toString(16)
        + (bold < 16 ? "0" : "") + bold.toString(16)
      styleCache[key] = style
    }
    return style
  }

  function paintCell(ctx, k, col, row, s) {
    var glyph = frame[k]
    var slot = frame[k + 1]
    var bold = frame[k + 2]
    if (glyph === drawn[k] && slot === drawn[k + 1] && bold === drawn[k + 2]) return 0
    ctx.fillStyle = cellStyle(glyph, slot, bold)
    ctx.fillRect(col * s, row * s, s, s)
    drawn[k] = glyph
    drawn[k + 1] = slot
    drawn[k + 2] = bold
    return 1
  }

  function paintState(ctx) {
    if (!engine || !frame) return
    var cols = engine.cols
    var lines = engine.lines
    if (cols !== root.cols || lines !== root.lines) return
    var t0 = profiler.now()
    var painted = 0
    var s = stateCellSize

    if (fullRepaint) {
      ctx.fillStyle = "#ff0000"
      ctx.fillRect(0, 0, cols * s, lines * s)
      for (var i = 0; i < drawn.length; i += 3) {
        drawn[i] = CMatrix.NO_GLYPH
        drawn[i + 1] = 0
        drawn[i + 2] = 0
      }
      fullRepaint = false
      fullRender = true
    }

    if (fullRender) {
      // cmatrix only ever writes even columns.
      for (var row = 0; row < lines; row++) {
        var base = row * cols * 3
        for (var col = 0; col < cols; col += 2) painted += paintCell(ctx, base + col * 3, col, row, s)
      }
      fullRender = false
    } else {
      for (var t = 0; t < touchedCount; t++) {
        var cell = touched[t]
        var c = cell % cols
        painted += paintCell(ctx, cell * 3, c, (cell - c) / cols, s)
      }
    }
    touchedCount = 0
    profiler.paint(t0, painted)
  }

  function paintAtlas(ctx) {
    var glyphs = glyphTable.glyphs
    ctx.clearRect(0, 0, atlasCanvas.width, atlasCanvas.height)
    ctx.fillStyle = "#ffffff"
    ctx.textAlign = "left"
    ctx.textBaseline = "alphabetic"
    for (var weight = 0; weight < 2; weight++) {
      ctx.font = (weight ? "bold " : "") + fontPixelSize + "px \"" + fontFamily + "\""
      for (var i = 0; i < glyphs.length; i++) {
        var x = (i % atlasColumns) * cellWidth
        var y = (Math.floor(i / atlasColumns) + weight * atlasRows) * cellHeight
        // Clip to the cell so a wide glyph can never bleed into a neighbour's slot.
        ctx.save()
        ctx.beginPath()
        ctx.rect(x, y, cellWidth, cellHeight)
        ctx.clip()
        ctx.fillText(glyphs[i], x, y + glyphBaseline)
        ctx.restore()
      }
    }
  }

  function paletteMatrix(offset) {
    var c = []
    for (var i = 0; i < 4; i++) {
      var value = rainPalette && rainPalette[offset + i] !== undefined ? rainPalette[offset + i] : "#000000"
      c.push(Qt.color(value))
    }
    // Qt.matrix4x4 takes rows; GLSL reads columns, so column i is color i.
    return Qt.matrix4x4(
      c[0].r, c[1].r, c[2].r, c[3].r,
      c[0].g, c[1].g, c[2].g, c[3].g,
      c[0].b, c[1].b, c[2].b, c[3].b,
      c[0].a, c[1].a, c[2].a, c[3].a)
  }

  onColsChanged: rebuildTimer.restart()
  onLinesChanged: rebuildTimer.restart()
  onCharsetChanged: rebuildTimer.restart()
  onOldstyleChanged: rebuildTimer.restart()
  onWakeSerialChanged: rebuildTimer.restart()
  onVisibleChanged: if (visible && start === "wake") rebuildTimer.restart()
  onEngineOptionsChanged: refresh()
  onCellWidthChanged: atlasCanvas.requestPaint()
  onCellHeightChanged: atlasCanvas.requestPaint()
  onFontFamilyChanged: atlasCanvas.requestPaint()
  onFontPixelSizeChanged: atlasCanvas.requestPaint()
  onGlyphTableChanged: atlasCanvas.requestPaint()
  Component.onCompleted: rebuildTimer.restart()

  Timer {
    id: rebuildTimer
    interval: 30
    repeat: false
    onTriggered: root.rebuild()
  }

  // cmatrix: `napms(update * 10)` after every screen update.
  Timer {
    id: clock
    interval: CMatrix.intervalMs(root.updateDelay)
    repeat: true
    running: root.running && root.visible && root.engine !== null
    onTriggered: root.step()
  }

  // ------------------------------------------------------------- textures
  //
  // Both canvases are hidden; the shader samples them directly as texture
  // providers, so there is no intermediate offscreen pass.

  Canvas {
    id: stateCanvas
    width: root.cols * root.stateCellSize
    height: root.lines * root.stateCellSize
    visible: false
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image
    smooth: false
    onPaint: root.paintState(getContext("2d"))
    onWidthChanged: root.fullRepaint = true
    onHeightChanged: root.fullRepaint = true
  }

  Canvas {
    id: atlasCanvas
    width: root.atlasColumns * root.cellWidth
    height: root.atlasRows * 2 * root.cellHeight
    visible: false
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image
    onPaint: root.paintAtlas(getContext("2d"))
    onAvailableChanged: if (available) requestPaint()
  }

  // --------------------------------------------------------------- screen

  ShaderEffect {
    id: effect
    x: 0
    y: root.gridTop
    width: root.width
    height: root.lines * root.cellHeight
    visible: root.engine !== null
    opacity: root.rainOpacity
    blending: true

    property vector2d itemSize: Qt.vector2d(width, height)
    property vector2d cellSize: Qt.vector2d(root.cellWidth, root.cellHeight)
    property vector2d gridSize: Qt.vector2d(root.cols, root.lines)
    property vector2d atlasSize: Qt.vector2d(atlasCanvas.width, atlasCanvas.height)
    property real atlasColumns: root.atlasColumns
    property real atlasRows: root.atlasRows
    property real glyphCount: root.glyphTable.glyphs.length
    property real columnStride: root.columnStride
    property matrix4x4 paletteA: root.paletteMatrix(0)
    property matrix4x4 paletteB: root.paletteMatrix(4)
    property matrix4x4 paletteC: root.paletteMatrix(8)
    property matrix4x4 paletteD: root.paletteMatrix(12)
    property matrix4x4 paletteE: root.paletteMatrix(16)
    property real tailCount: root.tailColorCount
    property var stateTex: stateCanvas
    property var atlasTex: atlasCanvas

    fragmentShader: Qt.resolvedUrl("shaders/matrix.frag.qsb")
  }
}
