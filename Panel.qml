import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "colors.js" as Colors

// Bar entry for Matrix Screens: a matrix glyph and a panel with a live
// preview, one switch each for the background, the screensaver and the lock
// screen, and a Customize section (collapsed by default) with the color
// editor. Left click opens the panel, right click starts the screensaver
// now. All state and actions live in Rain.qml (the service's `rain`).
Panel {
  id: root

  readonly property string pluginId: "io.github.whiskeytangofussell.matrixscreens"
  moduleName: pluginId
  ipcTarget: pluginId

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor(pluginId) : null
  readonly property var rain: service ? service.rain : null

  readonly property bool backgroundOn: !!rain && rain.backgroundOn
  readonly property bool screensaverOn: !!rain && rain.config.screensaver
  readonly property bool lockOn: !!rain && rain.config.lockScreen
  readonly property bool anyOn: backgroundOn || screensaverOn || lockOn

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)

  // Keyboard cursor over the rows below.
  readonly property var rows: ["background", "screensaver", "lock", "text", "palette"]
  property int cursor: -1

  // Either editor section is open: the preview shows the unsaved draft.
  readonly property bool customizing: editor.anyOpen

  function activate(name) {
    if (!rain) return
    if (name === "background") rain.setBackgroundOn(!backgroundOn)
    else if (name === "screensaver") rain.setSetting("screensaver", !screensaverOn)
    else if (name === "lock") rain.setSetting("lock_screen", !lockOn)
    else if (name === "text") editor.textOpen = !editor.textOpen
    else if (name === "palette") editor.paletteOpen = !editor.paletteOpen
  }

  function startScreensaver() {
    if (!rain) return
    root.close()
    // Let the panel close first, so it isn't under the screensaver.
    startTimer.restart()
  }

  function editColors() {
    if (!rain) return
    root.close()
    Quickshell.execDetached(["bash", "-c", "f=$(\"$1\" customize) && omarchy-launch-editor \"$f\"", "matrix-screens", rain.cli])
  }

  function paletteLabel() {
    if (!rain) return ""
    var source = rain.paletteSource
    var name = rain.themeName
    if (source === "custom") return name + " · your colors"
    if (source === "theme") return name + " · the theme's rain colors"
    if (source === "bundled") return name + " · bundled colors"
    return name + " · theme colors"
  }

  Timer {
    id: startTimer
    interval: 400
    onTriggered: if (root.rain) root.rain.startScreensaver(false)
  }

  onOpenedChanged: {
    if (opened) {
      cursor = -1
    } else {
      // Unsaved edits are dropped when the panel closes.
      if (customizing) editor.revert()
      editor.textOpen = false
      editor.paletteOpen = false
    }
  }

  // `matrix-screens colors` / `omarchy-shell matrixscreens colors`.
  Connections {
    target: root.rain
    ignoreUnknownSignals: true
    function onCustomizeRequested() {
      editor.paletteOpen = true
      root.open()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-matrix
    text: "\u{F0628}"
    opacity: root.anyOn ? 1.0 : 0.5
    tooltipText: ""
    onPressed: function (b) {
      if (b === Qt.RightButton) root.startScreensaver()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(header.implicitHeight + Style.space(10) + column.implicitHeight, Style.space(1400))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: editor.hexFocused || editor.dropdownOpen
      onMoveRequested: function (dx, dy) {
        var step = dy !== 0 ? dy : dx
        if (root.cursor < 0) root.cursor = 0
        else root.cursor = (root.cursor + step + root.rows.length) % root.rows.length
      }
      onActivateRequested: if (root.cursor >= 0) root.activate(root.rows[root.cursor])
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (t === "s" || t === "S") root.startScreensaver()
      }

      // The title and the live preview stay put; everything below scrolls.
      Column {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: "Matrix Screens"
          meta: root.paletteLabel()
          foreground: root.fg
          fontFamily: root.fontFamily
          iconOpacity: root.anyOn ? 1.0 : 0.5
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: "\u{F0628}"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)

          // Live preview: the same rain the background, screensaver and lock
          // screen draw, in the current colors. Click it to start the
          // screensaver.
          Rectangle {
            id: preview
            width: parent.width
            height: Math.round(width * 9 / 16)
            color: root.customizing ? editor.draft.background : (root.rain ? root.rain.backgroundColor : "black")
            radius: Style.cornerRadius
            clip: true
            border.width: 1
            border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)

            Loader {
              anchors.fill: parent
              anchors.margins: 1
              active: root.opened && !!root.rain
              sourceComponent: Component {
                // While customizing, the unsaved draft's colors.
                RainView {
                  rain: root.rain
                  running: root.opened
                  start: "full"
                  rainPalette: root.customizing ? Colors.previewPalette(editor.draft) : root.rain.palette
                  tailGroups: root.customizing ? Colors.previewTailGroups(editor.draft) : root.rain.tailGroups
                  tailFade: root.customizing ? editor.draft.fade : root.rain.config.tailFade
                  tailHueShift: root.customizing ? editor.draft.shift : root.rain.config.tailHueShift
                  updateDelay: root.customizing ? editor.draftDelay : root.rain.effectiveUpdateDelay
                  fontFamily: root.customizing ? editor.previewFont : root.rain.fontFamily
                  fontPixelSize: root.customizing ? editor.previewSize : root.rain.fontPixelSize
                }
              }
            }

            MouseArea {
              id: previewMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.startScreensaver()
            }

          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "Click to preview full screen"
            color: previewMouse.containsMouse ? root.fg : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      ScrollView {
        id: scrollArea
        anchors.top: header.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

      Column {
        id: column
        width: scrollArea.availableWidth
        spacing: Style.space(10)

        PanelSeparator { foreground: root.fg }

        Toggle {
          width: parent.width
          label: "Background"
          description: root.backgroundOn ? "Rain behind your windows" : "Your normal wallpaper"
          checked: root.backgroundOn
          hasCursor: root.cursor === 0
          foreground: root.fg
          fontFamily: root.fontFamily
          onClicked: root.activate("background")
          onHovered: function (isHovered) { if (isHovered) root.cursor = 0 }
        }

        Toggle {
          width: parent.width
          label: "Screensaver"
          description: !root.screensaverOn ? "Omarchy's screensaver runs when idle"
            : (root.rain && root.rain.screensaverToggledOff ? "On, but Omarchy's screensaver switch is off" : "Rain when the computer is idle")
          checked: root.screensaverOn
          hasCursor: root.cursor === 1
          foreground: root.fg
          fontFamily: root.fontFamily
          onClicked: root.activate("screensaver")
          onHovered: function (isHovered) { if (isHovered) root.cursor = 1 }
        }

        Toggle {
          width: parent.width
          label: "Lock Screen"
          description: root.lockOn ? "Rain behind the password box" : "Blurred wallpaper, like Omarchy's"
          checked: root.lockOn
          hasCursor: root.cursor === 2
          foreground: root.fg
          fontFamily: root.fontFamily
          onClicked: root.activate("lock")
          onHovered: function (isHovered) { if (isHovered) root.cursor = 2 }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Customize Text & Display, Modify Color Palette ----------
        // (both collapsed by default; their headers live in ColorEditor)
        ColorEditor {
          id: editor
          width: parent.width
          rain: root.rain
          textCursor: root.cursor === 3
          paletteCursor: root.cursor === 4
          onHeaderHovered: function (which) { root.cursor = 3 + which }
          scrollTarget: scrollArea.contentItem
          foreground: root.fg
          fontFamily: root.fontFamily
          onEditManually: root.editColors()
        }
      }
      }
    }
  }
}
