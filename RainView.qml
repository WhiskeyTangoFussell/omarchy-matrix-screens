import QtQuick

// The rain, dressed by the Rain service. The desktop background, the lock
// screen and the screensaver all draw this, inside the shell, so all three
// have the same font, cell size, speed and colors.
MatrixScreen {
  required property var rain

  updateDelay: rain.effectiveUpdateDelay
  asynchronous: rain.config.asynchronous
  boldLevel: rain.config.boldLevel
  charset: rain.config.charset
  lambda: rain.config.lambda
  changes: rain.config.changes
  oldstyle: rain.config.oldstyle
  rainbow: rain.config.rainbow
  justifyColumns: rain.config.justifyColumns
  tailGroups: rain.tailGroups
  tailFade: rain.config.tailFade
  tailHueShift: rain.config.tailHueShift
  start: rain.config.start
  rainOpacity: rain.config.opacity
  fontFamily: rain.fontFamily
  fontPixelSize: rain.fontPixelSize
  rainPalette: rain.palette
}
