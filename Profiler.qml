import QtQuick

// Per-tick timing for the renderer. Off by default; when enabled it folds
// every `window` ticks into `summary` and logs it (MatrixScreen's `profile`
// property), without touching the hot path when disabled.
QtObject {
  id: profiler

  property bool enabled: false
  property int window: 100
  property string summary: ""
  property string grid: ""

  property var _d: ({ ticks: 0, tickMs: 0, renderMs: 0, paintMs: 0, cells: 0, last: 0, gapMs: 0, gapMax: 0 })

  function now() {
    return enabled ? Date.now() : 0
  }

  // t0: before the engine tick, t1: after it, t2: after rendering the frame.
  function tick(t0, t1, t2) {
    if (!enabled) return
    var d = _d
    d.ticks++
    d.tickMs += t1 - t0
    d.renderMs += t2 - t1
    if (d.last > 0) {
      var gap = t0 - d.last
      d.gapMs += gap
      if (gap > d.gapMax) d.gapMax = gap
    }
    d.last = t0
  }

  // t0: before painting the state canvas; painted: cells written.
  function paint(t0, painted) {
    if (!enabled) return
    var d = _d
    d.paintMs += Date.now() - t0
    d.cells += painted
    if (d.ticks < window) return
    summary = "tick " + (d.tickMs / d.ticks).toFixed(2) + " ms"
      + " · render " + (d.renderMs / d.ticks).toFixed(2) + " ms"
      + " · paint " + (d.paintMs / d.ticks).toFixed(2) + " ms"
      + " · " + (d.cells / d.ticks).toFixed(0) + " cells"
      + " · interval " + (d.gapMs / Math.max(1, d.ticks - 1)).toFixed(1)
      + " ms (max " + d.gapMax + ")"
      + (grid ? " · " + grid : "")
    console.log("matrix-screens profile: " + summary)
    d.ticks = 0; d.tickMs = 0; d.renderMs = 0; d.paintMs = 0; d.cells = 0; d.gapMs = 0; d.gapMax = 0
  }
}
