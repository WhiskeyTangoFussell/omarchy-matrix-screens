import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import qs.Commons
import "settings.js" as Settings

// What the rain looks like: your settings.json and the active theme's
// colors (ThemeSource.qml). It only reads and writes files, so the service
// (Rain.qml) and the bar panel each keep their own copy. The panel can't
// reach the service's: the manifest makes the service a lock screen, and
// Omarchy keeps lock services out of reach of other plugin code. A change
// either copy saves reaches the other through the file.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: theme.pluginDir
  readonly property string cli: pluginDir + "/bin/matrix-screens"

  // ------------------------------------------------------------- settings

  // Every setting lives in the plugin's own file; shell.json only holds the
  // plugin's bare { id } entry, which enables it.
  readonly property string settingsDir: home + "/.config/omarchy/matrix-screens"
  readonly property string settingsPath: settingsDir + "/settings.json"
  property var userSettings: ({})
  property bool settingsReadable: true
  // No settings.json yet: a migration from shell.json may still be due.
  property bool settingsMissing: false

  // Saves one setting (undefined removes it). The change applies at once;
  // the file is written behind it.
  function setSetting(key, value) {
    if (!root.settingsReadable) {
      console.warn("matrix-screens: " + root.settingsPath + " is not valid JSON; not overwriting it")
      return
    }
    root.userSettings = Settings.withSetting(root.userSettings, key, value)
    writeSettings()
  }

  function writeSettings() {
    if (settingsWriter.running) {
      settingsWriter.again = true
      return
    }
    settingsWriter.command = ["bash", "-c",
      "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"$2\" >\"$1.tmp\" && mv -f \"$1.tmp\" \"$1\"",
      "matrix-screens", root.settingsPath, JSON.stringify(root.userSettings, null, 2)]
    settingsWriter.running = true
  }

  Process {
    id: settingsWriter
    property bool again: false
    onExited: if (again) {
      again = false
      root.writeSettings()
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.userSettings = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({})
        root.settingsReadable = true
        root.settingsMissing = false
      } catch (e) {
        // Leave a hand-edited file with a typo alone until it's fixed.
        console.warn("matrix-screens: can't read " + root.settingsPath + ": " + e)
        root.settingsReadable = false
      }
    }
    onLoadFailed: {
      root.userSettings = ({})
      root.settingsReadable = true
      root.settingsMissing = true
    }
  }

  // A settings file that didn't exist yet isn't watched; notice it appear.
  FileView {
    path: root.settingsDir
    watchChanges: true
    printErrors: false
    onFileChanged: settingsFile.reload()
  }

  // --------------------------------------------------------------- theme

  ThemeSource {
    id: theme
    userSettings: root.userSettings
    fallbacks: ({
      foreground: String(Color.foreground),
      background: String(Color.background),
      accent: String(Color.accent),
      urgent: String(Color.urgent)
    })
    systemFontFamily: {
      var resolved = String(Style.font.resolvedFamily || "").trim()
      return resolved.length > 0 && resolved !== "monospace" ? resolved : Style.font.family
    }
    systemFontPixelSize: Style.font.baseSize
  }

  readonly property var themeSource: theme
  readonly property var config: theme.config
  readonly property string themeName: theme.themeName
  readonly property string paletteSource: theme.paletteSource
  readonly property string palettePath: theme.palettePath
  readonly property var palette: theme.palette
  readonly property var tailGroups: theme.tailGroups
  readonly property string fontFamily: theme.fontFamily
  readonly property string systemFontFamily: theme.systemFontFamily
  readonly property int systemFontPixelSize: theme.systemFontPixelSize
  readonly property int fontPixelSize: theme.fontPixelSize
  readonly property color backgroundColor: theme.backgroundColor
  readonly property var themeColors: theme.themeColors
  readonly property string customPalettePath: theme.customPath
  readonly property string customPaletteText: theme.customText

  function reloadPalette() { theme.reloadThemeFiles() }

  // ------------------------------------------------------------- battery

  readonly property bool onBattery: UPower.onBattery
  readonly property real effectiveUpdateDelay: onBattery && config.onBattery === "slow"
    ? Math.max(config.updateDelay, config.batteryUpdateDelay)
    : config.updateDelay
}
