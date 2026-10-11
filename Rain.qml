import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import QtQuick
import qs.Commons
import "settings.js" as Settings
import "cmatrix.js" as CMatrix

// The rain half of Matrix Screens: the desktop background, the screensaver,
// and what the lock screen (Service.qml) needs to draw it too. Each of the
// three switches on and off on its own.
//
// Background: a RainView on the Wayland `Bottom` layer of every monitor,
// above Omarchy's wallpaper and below every window. It shows while a rain
// tile (matrix-screens.png, or an older omatrix.png) is the selected
// background, so the background switcher turns it on and off. The plugin
// writes the active theme's tile itself, and after a theme switch reselects
// the new theme's tile if the rain was on.
//
// Screensaver: a RainView on the `Overlay` layer of every monitor. With
// `screensaver` on, it starts when Omarchy's idle service starts the
// screensaver, and a marker process makes omarchy-launch-screensaver see a
// screensaver running and step aside. It closes on any input, when the idle
// cycle ends, when the session locks, or when another screensaver's window
// appears.
//
// Colors: ThemeSource.qml picks the palette (your custom file, the theme's
// own, the bundled one, or the theme's colors).
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/current"
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.whiskeytangofussell.matrixscreens"
  readonly property string pluginDir: theme.pluginDir
  readonly property string cli: pluginDir + "/bin/matrix-screens"
  readonly property string screensaverClass: "org.omarchy.screensaver"

  property bool runtimeEnabled: true
  property int wakeSerial: 0

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
      root.migrateLegacySettings()
    }
  }

  // A settings file that didn't exist yet isn't watched; notice it appear.
  FileView {
    path: root.settingsDir
    watchChanges: true
    printErrors: false
    onFileChanged: settingsFile.reload()
  }

  // Versions before 0.3.0 kept settings in the plugin's shell.json entry:
  // move them into settings.json and strip the entry back to its id.
  function migrateLegacySettings() {
    var legacy = Settings.legacySettings(Settings.pluginEntry(shell ? shell.shellConfig : null, root.pluginId))
    if (!legacy) return
    root.settingsMissing = false
    var merged = legacy
    for (var k in root.userSettings) merged[k] = root.userSettings[k]
    root.userSettings = merged
    writeSettings()
    if (shell && typeof shell.mutateShellConfig === "function") {
      var id = root.pluginId
      shell.mutateShellConfig(function (config) { Settings.stripPluginEntry(config, id) })
    }
    console.log("matrix-screens: moved settings from shell.json to " + root.settingsPath)
  }

  // shell.json may load after the missing settings file is noticed.
  Connections {
    target: root.shell
    ignoreUnknownSignals: true
    function onShellConfigChanged() { if (root.settingsMissing) root.migrateLegacySettings() }
  }

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

  // ---------------------------------------------------------- color editor

  // Asks the bar panel to open with its Customize section expanded.
  signal customizeRequested()

  function reloadPalette() { theme.reloadThemeFiles() }

  function openColorChooser() { customizeRequested() }

  // --------------------------------------------------- background switch

  // Basenames that mean "the rain is the background".
  readonly property var tileNames: ["matrix-screens.png", "omatrix.png"]

  property string backgroundPath: ""
  readonly property bool tileSelected: isTile(backgroundPath)
  // The rain was on when things last settled; carried across theme switches.
  property bool rainWanted: false
  property string settledTheme: ""
  // The background to go back to when the rain is switched off.
  property string lastOtherBackground: ""

  readonly property bool backgroundOn: config.background === "always"
    || (config.background === "tile" && (tileSelected || holdingRain))

  // During a theme switch with the rain on, Omarchy briefly selects the new
  // theme's stock wallpaper before the plugin puts the rain tile back. Hold
  // the rain up across that gap instead of flashing the wallpaper.
  property bool holdingRain: false

  Timer {
    id: holdTimeout
    // Safety net: if the tile never gets selected, stop holding.
    interval: 10000
    onTriggered: root.holdingRain = false
  }

  function isTile(path) {
    return tileNames.indexOf(String(path || "").replace(/^.*\//, "")) !== -1
  }

  // On: select the theme's rain tile (drawing it first if need be). Off:
  // go back to the last other background, or the theme's first one.
  function setBackgroundOn(on) {
    if (on) {
      if (config.background === "off") setSetting("background", "tile")
      if (!tileSelected) runTile(true)
    } else {
      if (config.background === "always") setSetting("background", "tile")
      if (tileSelected) {
        var back = root.lastOtherBackground
        Quickshell.execDetached(["bash", "-c",
          "b=$1; [[ -f $b ]] || b=$(ls \"$HOME\"/.local/state/omarchy/current/theme/backgrounds/* 2>/dev/null | head -1); "
          + "[[ -n $b ]] && omarchy-theme-bg-set \"$b\"", "matrix-screens", back])
      }
    }
  }

  // omarchy theme set rewrites several files in current/ in a burst (theme,
  // theme.name, background). Wait for it to go quiet, then look.
  FileView {
    path: root.stateDir
    watchChanges: true
    printErrors: false
    onFileChanged: settleTimer.restart()
  }

  Timer {
    id: settleTimer
    interval: 1200
    repeat: false
    onTriggered: if (!readlinkProc.running) readlinkProc.running = true
  }

  Process {
    id: readlinkProc
    // "<1 if the file exists, else 0> <path>"
    command: ["bash", "-c", "p=$(readlink -f \"$1\"); [[ -e $p ]] && echo \"1 $p\" || echo \"0 $p\"",
      "matrix-screens", root.stateDir + "/background"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = text.trim()
        root.settle(line.substring(2), line.charAt(0) === "1")
      }
    }
  }

  // Safety net: look again now and then, in case a change slipped past the
  // directory watcher (it is cheap: one readlink).
  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: if (!readlinkProc.running) readlinkProc.running = true
  }

  function settle(path, exists) {
    var themeChanged = root.settledTheme !== "" && theme.themeName !== root.settledTheme
    var tile = isTile(path)
    // A selected rain tile that has since been deleted (Omarchy restores a
    // theme's last background even when the file is gone): draw a new one.
    var missingTile = tile && exists === false && config.background === "tile"
    var keepOn = missingTile
      || (!tile && themeChanged && root.rainWanted && config.keepOnThemeSwitch && config.background === "tile")

    // Set the hold before the new path, so the rain never reads as off for
    // even one binding pass (that would hide it and restart it empty).
    if (keepOn) {
      root.holdingRain = true
      holdTimeout.restart()
    }
    root.backgroundPath = path
    root.settledTheme = theme.themeName

    if (keepOn) {
      // Theme switches select the theme's first stock background; put the
      // rain back. The tile is written first if the theme has none yet.
      runTile(true)
      return
    }
    root.rainWanted = tile
    if (!tile && path) root.lastOtherBackground = path
    // The tile shows now (or the rain is meant to be off): stop holding.
    root.holdingRain = false
    holdTimeout.stop()
    tileTimer.restart()
  }

  // ---------------------------------------------------------------- tiles

  // Rewrite the theme's tile when its palette changes (the CLI skips the
  // work when the colors are unchanged, and never touches omatrix.png).
  readonly property var tileArgs: theme.tileArgs
  onTileArgsChanged: tileTimer.restart()

  Timer {
    id: tileTimer
    interval: 1500
    repeat: false
    onTriggered: root.runTile(false)
  }

  property bool tileSelectPending: false

  function runTile(select) {
    if (select) root.tileSelectPending = true
    if (!theme.themeName || !theme.colorsLoaded) return
    if (!config.backgroundTile && !root.tileSelectPending) return
    if (tileProc.running) {
      tileProc.again = true
      return
    }
    var args = [root.cli, "tile", theme.themeName].concat(root.tileArgs)
    if (root.tileSelectPending) args.push("--select")
    root.tileSelectPending = false
    tileProc.command = args
    tileProc.running = true
  }

  Process {
    id: tileProc
    property bool again: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim().length > 0) console.warn("matrix-screens tile: " + text.trim())
    }
    onExited: if (again) {
      again = false
      root.runTile(false)
    }
  }

  // --------------------------------------------------------- pause logic

  // Set by Service.qml, which is the lock.
  property bool lockedNow: false
  readonly property bool locked: config.pauseWhenLocked && lockedNow
  readonly property bool onBattery: UPower.onBattery
  readonly property bool batteryPaused: onBattery && config.onBattery === "pause"
  readonly property real effectiveUpdateDelay: onBattery && config.onBattery === "slow"
    ? Math.max(config.updateDelay, config.batteryUpdateDelay)
    : config.updateDelay

  readonly property bool active: runtimeEnabled && backgroundOn && !batteryPaused && !locked && !screensaverShowing

  // The lock screen draws the rain while this is true.
  readonly property bool lockRainVisible: config.lockScreen && runtimeEnabled && !batteryPaused

  // ----------------------------------------------------------- screensaver

  readonly property var idleService: shell && shell.serviceFor ? shell.serviceFor("omarchy.idle") : null

  property bool screensaverShowing: false
  // Bumped on every start, so the rain starts from an empty screen.
  property int screensaverSerial: 0
  property bool screensaverFromIdle: false
  // Omarchy's own on/off switch for the screensaver.
  property bool screensaverToggledOff: false

  function startScreensaver(fromIdle) {
    if (root.screensaverShowing || root.lockedNow) return
    root.screensaverFromIdle = fromIdle
    root.screensaverSerial++
    root.screensaverShowing = true
    // Omarchy's launcher checks `pgrep -f org.omarchy.screensaver` first and
    // steps aside when it matches; this process is what it finds.
    markerProc.running = true
    Quickshell.execDetached(["bash", "-c",
      "hyprctl eval 'hl.config({ cursor = { invisible = true } })' >/dev/null 2>&1 || hyprctl keyword cursor:invisible true >/dev/null 2>&1"])
  }

  function stopScreensaver() {
    if (!root.screensaverShowing) return
    root.screensaverShowing = false
    root.screensaverFromIdle = false
    markerProc.running = false
    root.cursorAt = ""
    Quickshell.execDetached(["bash", "-c",
      "hyprctl eval 'hl.config({ cursor = { invisible = false } })' >/dev/null 2>&1 || hyprctl keyword cursor:invisible false >/dev/null 2>&1"])
  }

  Process {
    id: markerProc
    command: ["bash", "-c", "while sleep 3600; do :; done", root.screensaverClass]
    // Killed from outside (omarchy-system-lock, omarchy-screensaver): the
    // screensaver is over.
    onExited: root.stopScreensaver()
  }

  Connections {
    target: root.idleService
    ignoreUnknownSignals: true
    function onScreensaverStartedThisCycleChanged() {
      if (root.idleService.screensaverStartedThisCycle) {
        if (root.config.screensaver && !root.screensaverToggledOff) root.startScreensaver(true)
      } else if (root.screensaverFromIdle) {
        // Activity ended the idle cycle.
        root.stopScreensaver()
      }
    }
  }

  onLockedNowChanged: if (lockedNow) stopScreensaver()

  // Another screensaver opened its window after all: it wins.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.screensaverShowing || String(event.name) !== "openwindow") return
      if (String(event.data || "").split(",")[2] === root.screensaverClass) root.stopScreensaver()
    }
  }

  // ~/.local/state/omarchy/toggles/screensaver-off (Omarchy's own switch).
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: toggleOffFile.reload()
  }

  FileView {
    id: toggleOffFile
    path: root.home + "/.local/state/omarchy/toggles/screensaver-off"
    printErrors: false
    onLoaded: root.screensaverToggledOff = true
    onLoadFailed: root.screensaverToggledOff = false
  }

  // Ignore input for the first second, while the layer maps and the pointer
  // settles; then any pointer move closes it (polled, so a move on any
  // monitor counts).
  property string cursorAt: ""

  Timer {
    id: armTimer
    interval: 1000
    running: root.screensaverShowing
  }

  Timer {
    interval: 250
    repeat: true
    running: root.screensaverShowing && !armTimer.running && root.config.screensaverDismissOnMouse
    onTriggered: if (!cursorProbe.running) cursorProbe.running = true
  }

  Process {
    id: cursorProbe
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var at = text.trim()
        if (root.cursorAt !== "" && at !== root.cursorAt) root.stopScreensaver()
        else root.cursorAt = at
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: saverWindow
      required property var modelData

      screen: modelData
      visible: root.screensaverShowing
      anchors { top: true; bottom: true; left: true; right: true }
      color: root.backgroundColor

      WlrLayershell.namespace: "matrix-screens-screensaver"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore

      Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function (event) {
          event.accepted = true
          root.stopScreensaver()
        }

        RainView {
          anchors.fill: parent
          rain: root
          running: saverWindow.visible
          wakeSerial: root.screensaverSerial
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          cursorShape: Qt.BlankCursor
          onPressed: if (!armTimer.running) root.stopScreensaver()
          onWheel: if (!armTimer.running) root.stopScreensaver()
        }
      }
    }
  }

  // ------------------------------------------------------------------ ipc
  //
  //   omarchy-shell matrixscreens status | pause | resume | toggle | wake | tile
  //   omarchy-shell matrixscreens screensaver | stopScreensaver
  //   omarchy-shell matrixscreens set <background|screensaver|lock> <on|off>

  function setFeature(name, on) {
    if (name === "background") setBackgroundOn(on)
    else if (name === "screensaver") setSetting("screensaver", on)
    else if (name === "lock" || name === "lockscreen" || name === "lock_screen") setSetting("lock_screen", on)
    else return false
    return true
  }

  IpcHandler {
    target: "matrixscreens"

    function status(): string {
      return JSON.stringify({
        active: root.active,
        backgroundMode: root.config.background,
        backgroundOn: root.backgroundOn,
        tileSelected: root.tileSelected,
        holdingRain: root.holdingRain,
        backgroundPath: root.backgroundPath,
        screensaver: root.config.screensaver,
        screensaverShowing: root.screensaverShowing,
        screensaverToggledOff: root.screensaverToggledOff,
        lockScreen: root.config.lockScreen,
        lockRainVisible: root.lockRainVisible,
        theme: theme.themeName,
        paletteSource: theme.paletteSource,
        palettePath: theme.palettePath,
        locked: root.locked,
        onBattery: root.onBattery,
        updateDelay: root.effectiveUpdateDelay,
        intervalMs: CMatrix.intervalMs(root.effectiveUpdateDelay),
        bold: root.config.boldLevel,
        charset: root.config.charset,
        fontFamily: theme.fontFamily,
        bundledFont: theme.bundledFontFamily,
        fontPixelSize: theme.fontPixelSize,
        background: String(theme.backgroundColor),
        palette: theme.palette,
        tailFade: root.config.tailFade,
        tailHueShift: root.config.tailHueShift,
        tileArgs: root.tileArgs,
        screens: screens.instances.map(function (w) {
          return { name: w.modelData.name, covered: w.covered, visible: w.visible }
        })
      })
    }

    function pause(): void { root.runtimeEnabled = false }
    function resume(): void { root.runtimeEnabled = true }
    function toggle(): void { root.runtimeEnabled = !root.runtimeEnabled }
    function wake(): void { root.wakeSerial++ }
    function tile(): void { root.runTile(false) }
    function screensaver(): void { root.startScreensaver(false) }
    function colors(): void { root.openColorChooser() }
    function reloadPalette(): void { root.reloadPalette() }
    function stopScreensaver(): void { root.stopScreensaver() }
    function set(name: string, value: string): string {
      return root.setFeature(name, value === "on" || value === "true") ? "ok" : "unknown: " + name
    }
  }

  Component.onCompleted: settleTimer.restart()
  Component.onDestruction: if (screensaverShowing) stopScreensaver()

  // ---------------------------------------------------------- background

  Variants {
    id: screens
    model: Quickshell.screens

    PanelWindow {
      id: window
      required property var modelData

      readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
      readonly property bool covered: root.config.pauseWhenCovered
        && !!(hyprMonitor && hyprMonitor.activeWorkspace && hyprMonitor.activeWorkspace.hasFullscreen)

      screen: modelData
      visible: root.active && !covered
      anchors { top: true; bottom: true; left: true; right: true }
      color: root.backgroundColor

      // Bottom sits above the wallpaper (Background layer) and below windows.
      WlrLayershell.namespace: "matrix-screens"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // Click-through: double-clicking the desktop still reaches Omarchy's
      // background picker.
      mask: Region {}

      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.config.backdropOpacity
        visible: root.config.backdropOpacity > 0
      }

      RainView {
        anchors.fill: parent
        rain: root
        running: window.visible
        wakeSerial: root.wakeSerial
      }
    }
  }
}
