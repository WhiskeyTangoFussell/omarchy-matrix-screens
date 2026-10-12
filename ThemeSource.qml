import Quickshell
import Quickshell.Io
import QtQuick
import "settings.js" as Settings
import "cmatrix.js" as CMatrix

// Reads the active Omarchy theme and works out what the rain should look
// like: its name, its colors.toml, your saved palette for it if there is one
// (see Settings.paletteCandidates) and the bundled font. Used by the desktop
// background (Service.qml) and the screensaver, so it needs nothing from the
// Omarchy shell itself.
Item {
  id: root

  // The plugin's shell.json entry; overrides everything else.
  property var userSettings: ({})
  // Used when colors.toml lacks a color (hex strings).
  property var fallbacks: ({ foreground: "#ffffff", background: "#000000", accent: "#00ff00", urgent: "#ff0000" })
  // Monospace face for font_family = "" (the bundled face is the default).
  property string systemFontFamily: "monospace"
  property int systemFontPixelSize: 12

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/current"
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))

  property string themeName: ""
  property var themeColors: ({})
  property bool colorsLoaded: false

  // ------------------------------------------------------------ palette

  readonly property var candidates: Settings.paletteCandidates(home, themeName)
  property var candidateTexts: [null]

  readonly property int paletteIndex: {
    for (var i = 0; i < candidates.length; i++) if (candidateTexts[i] !== null && candidateTexts[i] !== undefined) return i
    return -1
  }
  readonly property string paletteSource: paletteIndex >= 0 ? candidates[paletteIndex].source : (themeRain ? "theme" : "theme-colors")
  readonly property string palettePath: paletteIndex < 0 ? "" : candidates[paletteIndex].path
  // Your custom palette file for this theme, and its text ("" when absent).
  readonly property string customPath: candidates[0].path
  readonly property string customText: candidateTexts[0] || ""
  readonly property var paletteSettings: paletteIndex < 0 ? null : CMatrix.parseFlatToml(candidateTexts[paletteIndex])

  // The theme's own rain defaults, from matrix_* keys in its colors.toml.
  readonly property var themeRain: Settings.themeRainDefaults(themeColors)
  readonly property var config: Settings.resolve(userSettings, paletteSettings, paletteSource, themeRain)
  readonly property var palette: Settings.palette(config, themeColors, fallbacks)
  readonly property var tailGroups: Settings.tailGroups(config.tailColors)
  readonly property color backgroundColor: Settings.backgroundColor(config, themeColors, fallbacks)
  readonly property var tileArgs: Settings.tileArgs(config, palette, backgroundColor)

  function setCandidate(index, text) {
    var next = candidateTexts.slice()
    next[index] = text
    candidateTexts = next
  }

  function reloadThemeFiles() {
    colorsFile.reload()
    for (var i = 0; i < candidateViews.count; i++) candidateViews.itemAt(i).reload()
  }

  // ---------------------------------------------------------------- font

  FontLoader { id: regularFont; source: "fonts/CaskaydiaCoveNerdFontMono-Regular.ttf" }
  FontLoader { id: boldFont; source: "fonts/CaskaydiaCoveNerdFontMono-Bold.ttf" }

  readonly property string bundledFontFamily: regularFont.status === FontLoader.Ready ? regularFont.name : ""
  readonly property string fontFamily: config.fontFamily.length > 0 ? config.fontFamily : systemFontFamily
  readonly property int fontPixelSize: config.fontSize > 0 ? Math.max(6, config.fontSize) : systemFontPixelSize

  // ---------------------------------------------------------- watchers

  // theme.name is rewritten in place by omarchy-theme-set after the theme
  // directory has been swapped, so it is the reliable trigger; the files
  // under current/theme/ live on a fresh inode after every switch.
  FileView {
    path: root.stateDir + "/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.themeName = String(text() || "").trim()
      root.reloadThemeFiles()
    }
    onLoadFailed: root.themeName = ""
  }

  FileView {
    id: colorsFile
    path: root.stateDir + "/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.themeColors = CMatrix.parseFlatToml(text())
      root.colorsLoaded = true
    }
    onLoadFailed: root.themeColors = ({})
  }

  Repeater {
    id: candidateViews
    model: root.candidates.length

    Item {
      required property int index
      function reload() { view.reload() }

      FileView {
        id: view
        path: root.candidates[index] ? root.candidates[index].path : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.setCandidate(index, text())
        onLoadFailed: root.setCandidate(index, null)
        onPathChanged: root.setCandidate(index, null)
      }
    }
  }
}
