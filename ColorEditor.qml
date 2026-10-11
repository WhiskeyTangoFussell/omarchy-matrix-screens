import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "colors.js" as Colors

// The color editor in the bar panel's Customize section. It edits a draft of
// the active theme's rain colors; the panel's preview shows the draft while
// the section is open. Save writes your custom palette file
// (~/.config/omarchy/matrix-screens/<theme>.toml), which wins over every
// other palette.
//
// Click a swatch to pick it, then choose its color in the picker, type a hex
// value or click one of the theme's colors. Right-click a tail swatch to
// remove it.
Column {
  id: root

  required property var rain
  // The panel's scrolling Flickable; the sliders hand wheel scrolls to it.
  property var scrollTarget: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  property var draft: ({ head: "#ffffff", background: "#000000", groups: [["#00ff00"]], fade: 0, shift: 0 })
  property var savedDraft: draft
  property string selectedSlot: "g0s0"
  // The picker's position; kept apart from the hex so a grey keeps its hue.
  property real hue: 0
  property real sat: 0
  property real val: 1

  // Speed and typeface: shared by every theme, saved in the plugin's
  // settings.json. update_delay is ms per step / 10; "" = Omarchy's font.
  property real draftDelay: 9.375
  property real savedDelay: 9.375
  property string draftFont: ""
  property string savedFont: ""
  // Glyph size in px; 0 = Omarchy's base size.
  property int draftSize: 0
  property int savedSize: 0
  readonly property int minSize: 8
  readonly property int maxSize: 32
  readonly property int previewSize: draftSize > 0 ? draftSize : (rain ? rain.systemFontPixelSize : 14)
  readonly property string bundledFont: "CaskaydiaCove Nerd Font Mono"
  property var monoFamilies: []

  readonly property bool settingsDirty: draftDelay !== savedDelay || draftFont !== savedFont || draftSize !== savedSize
  readonly property bool dirty: textDirty || paletteDirty

  // The two collapsible sections; both start collapsed.
  property bool textOpen: false
  property bool paletteOpen: false
  readonly property bool anyOpen: textOpen || paletteOpen
  // Keyboard cursor on a section header (set by the panel).
  property bool textCursor: false
  property bool paletteCursor: false
  signal headerHovered(int which)
  // Which section has unsaved edits: fade and hue shift are shown with text
  // and display, though they are saved with the colors.
  readonly property bool textDirty: settingsDirty || draft.fade !== savedDraft.fade || draft.shift !== savedDraft.shift
  readonly property bool paletteDirty: JSON.stringify([draft.head, draft.background, draft.groups])
    !== JSON.stringify([savedDraft.head, savedDraft.background, savedDraft.groups])
  // What the preview draws while customizing.
  readonly property string previewFont: draftFont.length > 0 ? draftFont : (rain ? rain.systemFontFamily : "monospace")
  readonly property bool hexFocused: hexField.activeFocus
  readonly property string selectedHex: Colors.colorAt(draft, selectedSlot)
  readonly property int colorCount: Colors.colorCount(draft)
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color line: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.35)
  readonly property int swatch: 28
  readonly property color unsavedRed: "#ff3b30"

  signal editManually()

  spacing: Style.space(10)

  // The theme's own colors, as quick picks.
  readonly property var themeSwatches: {
    var c = rain ? rain.themeColors || {} : {}
    var order = ["foreground", "accent", "red", "orange", "yellow", "green", "cyan", "blue", "magenta",
      "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta",
      "bright_foreground", "muted", "background"]
    var out = []
    for (var i = 0; i < order.length; i++) {
      var hex = Colors.normalizeHex(c[order[i]])
      if (hex && out.indexOf(hex) === -1) out.push(hex)
    }
    return out
  }

  // Reload from what the rain draws now, unless there are unsaved edits.
  readonly property string sourceKey: rain
    ? JSON.stringify([rain.palette, String(rain.backgroundColor), rain.config.tailFade, rain.config.tailHueShift])
    : ""
  onSourceKeyChanged: load()

  readonly property string settingsKey: rain ? JSON.stringify([rain.config.updateDelay, rain.config.fontFamily, rain.config.fontSize]) : ""
  onSettingsKeyChanged: if (!settingsDirty) loadSettings()

  function loadSettings() {
    if (!rain) return
    savedDelay = Number(rain.config.updateDelay)
    draftDelay = savedDelay
    savedFont = String(rain.config.fontFamily || "")
    draftFont = savedFont
    savedSize = Number(rain.config.fontSize) || 0
    draftSize = savedSize
  }

  // Bundled font, Omarchy's font, then every installed monospace family.
  readonly property var fontOptions: {
    var out = [
      { value: bundledFont, label: "Caskaydia Cove (bundled)" },
      { value: "", label: "Omarchy font" + (rain && rain.systemFontFamily ? " (" + rain.systemFontFamily + ")" : "") }
    ]
    for (var i = 0; i < monoFamilies.length; i++) {
      if (monoFamilies[i] !== bundledFont) out.push({ value: monoFamilies[i], label: monoFamilies[i] })
    }
    // A configured font that isn't installed still shows as selected.
    var known = draftFont === "" || draftFont === bundledFont || monoFamilies.indexOf(draftFont) !== -1
    if (!known) out.push({ value: draftFont, label: draftFont + " (not installed)" })
    return out
  }

  Process {
    running: true
    command: ["fc-list", ":spacing=mono", "family"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.monoFamilies = Colors.monoFamilies(text)
    }
  }

  // What the rain draws now becomes the saved state; the draft follows it,
  // except for a section with unsaved edits, which keeps them.
  function load() {
    if (!rain) return
    var d = Colors.draftFrom(rain.config, rain.palette, rain.backgroundColor)
    var next = Colors.copy(draft)
    if (!paletteDirty) {
      next.head = d.head
      next.background = d.background
      next.groups = d.groups
    }
    if (!textDirty) {
      next.fade = d.fade
      next.shift = d.shift
    }
    savedDraft = d
    draft = next
    select(Colors.colorAt(draft, selectedSlot) ? selectedSlot : "g0s0")
  }

  function select(slot) {
    selectedSlot = slot
    var hsv = Colors.hexToHsv(Colors.colorAt(draft, slot))
    if (hsv.s > 0 && hsv.v > 0) hue = hsv.h
    sat = hsv.s
    val = hsv.v
    hexField.text = Colors.colorAt(draft, slot)
  }

  function setSelected(hex, fromPicker) {
    var value = Colors.normalizeHex(hex)
    if (!value) return
    draft = Colors.withColor(draft, selectedSlot, value)
    if (!fromPicker) select(selectedSlot)
    else hexField.text = value
  }

  function pick() { setSelected(Colors.hsvToHex(hue, sat, val), true) }

  function addShade(group) {
    draft = Colors.withShadeAdded(draft, group)
    select("g" + group + "s" + (draft.groups[group].length - 1))
  }

  function removeShade(group, shade) {
    draft = Colors.withShadeRemoved(draft, group, shade)
    if (!Colors.colorAt(draft, selectedSlot)) select("g0s0")
  }

  function addGroup() {
    draft = Colors.withGroupAdded(draft)
    select("g" + (draft.groups.length - 1) + "s0")
  }

  // Colors go to this theme's palette file (only when they changed, so a
  // speed or font change doesn't freeze the theme's colors); speed and font
  // to the plugin's settings.json, for every theme. The same speed on
  // battery, so the rain doesn't change pace when unplugged.
  // ---- per section --------------------------------------------------------
  //
  // Text & display (typeface, size, fade, hue shift, speed) is saved in the
  // plugin's settings.json and applies to every theme. The color palette
  // is saved in this theme's custom palette file.

  function writeColors(d) {
    var text = Colors.serialize(d, rain.themeName, rain.customPaletteText)
    writer.command = ["bash", "-c",
      "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" >\"$1.tmp\" && mv -f \"$1.tmp\" \"$1\"",
      "matrix-screens", rain.customPalettePath, text]
    writer.running = true
  }

  function saveText() {
    if (!rain || !textDirty) return
    savedDelay = draftDelay
    savedFont = draftFont
    savedSize = draftSize
    var saved = Colors.copy(savedDraft)
    saved.fade = draft.fade
    saved.shift = draft.shift
    savedDraft = saved
    // The same speed on battery, so the rain doesn't change pace unplugged.
    rain.setSetting("update_delay", draftDelay)
    rain.setSetting("battery_update_delay", draftDelay)
    rain.setSetting("font_family", draftFont)
    rain.setSetting("font_size", draftSize)
    rain.setSetting("tail_fade", draft.fade)
    rain.setSetting("tail_hue_shift", draft.shift)
  }

  function undoText() {
    draftDelay = savedDelay
    draftFont = savedFont
    draftSize = savedSize
    var d = Colors.copy(draft)
    d.fade = savedDraft.fade
    d.shift = savedDraft.shift
    draft = d
  }

  // Back to the plugin defaults: removed keys fall back to them.
  function resetText() {
    if (!rain) return
    undoText()
    if (!hasCustomSettings) return
    var keys = ["update_delay", "battery_update_delay", "font_family", "font_size", "tail_fade", "tail_hue_shift"]
    for (var i = 0; i < keys.length; i++) rain.setSetting(keys[i], undefined)
  }

  function savePalette() {
    if (!rain || !paletteDirty) return
    var saved = Colors.copy(draft)
    saved.fade = savedDraft.fade
    saved.shift = savedDraft.shift
    savedDraft = saved
    writeColors(draft)
  }

  function undoPalette() {
    var d = Colors.copy(savedDraft)
    d.fade = draft.fade
    d.shift = draft.shift
    draft = d
    select(Colors.colorAt(draft, selectedSlot) ? selectedSlot : "g0s0")
  }

  // Back to the applied theme's own rain colors: delete your custom palette
  // file; the editor reloads from what applies instead (the theme's rain
  // file, the bundled palette, or the theme's colors).
  function resetPalette() {
    if (!rain) return
    undoPalette()
    if (!hasCustom) return
    writer.command = ["rm", "-f", rain.customPalettePath]
    writer.running = true
  }

  // ---- both sections (dropping unsaved edits when the panel closes) ---------

  function revert() {
    undoText()
    undoPalette()
  }

  readonly property bool hasCustom: !!rain && rain.paletteSource === "custom"
  // Speed or font set in settings.json (the defaults live in the plugin).
  readonly property bool hasCustomSettings: !!rain && !!rain.userSettings
    && (rain.userSettings.update_delay !== undefined || rain.userSettings.battery_update_delay !== undefined
      || rain.userSettings.font_family !== undefined || rain.userSettings.font_size !== undefined
      || rain.userSettings.tail_fade !== undefined || rain.userSettings.tail_hue_shift !== undefined)

  // A file that didn't exist before isn't being watched yet, so look again
  // once it's written (or removed).
  Process {
    id: writer
    onExited: if (root.rain) root.rain.reloadPalette()
  }

  component Swatch: Rectangle {
    id: sw
    property string slot: ""
    property string hex: Colors.colorAt(root.draft, slot)
    signal removeRequested()
    width: root.swatch
    height: root.swatch
    radius: Style.cornerRadius > 0 ? 4 : 0
    color: hex || "transparent"
    border.width: root.selectedSlot === slot ? 3 : 1
    border.color: root.selectedSlot === slot ? Color.accent : root.line
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function (mouse) {
        if (mouse.button === Qt.RightButton) sw.removeRequested()
        else root.select(sw.slot)
      }
    }
  }

  // A collapsible section header: chevron and title on the left; save, undo
  // and reset icons for just that section on the right, bright red while
  // the section has unsaved edits, faded when they would do nothing.
  component SectionHeader: CursorSurface {
    id: header
    property string title: ""
    property bool expanded: false
    property bool unsaved: false
    property bool canReset: false
    property string resetTip: "Reset to defaults"
    signal toggled()
    signal hoveredHeader()
    signal saveClicked()
    signal undoClicked()
    signal resetClicked()
    width: root.width
    implicitHeight: Math.max(headerText.implicitHeight, icons.implicitHeight) + Style.spacing.lg
    foreground: root.foreground

    Text {
      id: headerText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.right: icons.left
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: (header.expanded ? "\u{F0140}" : "\u{F0142}") + "  " + header.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    // Below the icons, so clicking an icon doesn't fold the section.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) header.hoveredHeader()
      onClicked: header.toggled()
    }

    Row {
      id: icons
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      HeaderIcon {
        glyph: "\u{F0193}"          // content-save
        tip: "Save " + header.title.toLowerCase()
        active: header.unsaved
        onClicked: header.saveClicked()
      }
      HeaderIcon {
        glyph: "\u{F054C}"          // undo
        tip: "Undo unsaved changes"
        active: header.unsaved
        onClicked: header.undoClicked()
      }
      HeaderIcon {
        glyph: "\u{F099B}"          // restore
        tip: header.resetTip
        active: header.unsaved || header.canReset
        alert: header.unsaved
        onClicked: header.resetClicked()
      }
    }
  }

  component HeaderIcon: Text {
    id: icon
    property string glyph: ""
    property string tip: ""
    property bool active: false
    // Red while there are unsaved edits (save and undo are only active then).
    property bool alert: active
    signal clicked()
    textFormat: Text.PlainText
    text: glyph
    color: alert ? root.unsavedRed : root.foreground
    opacity: active ? (iconMouse.containsMouse ? 1 : 0.9) : 0.3
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle

    MouseArea {
      id: iconMouse
      anchors.fill: parent
      anchors.margins: -4
      hoverEnabled: true
      cursorShape: icon.active ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (icon.active) icon.clicked()
    }

    PanelToolTip {
      visible: iconMouse.containsMouse && icon.tip !== ""
      text: icon.tip
      fontFamily: root.fontFamily
    }
  }

  component Label: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    textFormat: Text.PlainText
  }

  SectionHeader {
    title: "Customize Text & Display"
    expanded: root.textOpen
    hasCursor: root.textCursor
    unsaved: root.textDirty
    canReset: root.hasCustomSettings
    resetTip: "Reset text & display to the defaults"
    onToggled: root.textOpen = !root.textOpen
    onHoveredHeader: root.headerHovered(0)
    onSaveClicked: root.saveText()
    onUndoClicked: root.undoText()
    onResetClicked: root.resetText()
  }

  Column {
    id: textSection
    width: parent.width
    spacing: root.spacing
    visible: root.textOpen

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Text settings are saved globally"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // ---------- typeface and size (every theme) ----------
    Label { text: "TYPEFACE" }
    SearchableDropdown {
      id: fontDropdown
      width: parent.width
      showLabel: false
      value: root.draftFont
      options: root.fontOptions
      placeholderText: "Search fonts..."
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: function (v) { root.draftFont = v }
    }

    Label {
      text: "SIZE  " + root.previewSize + " px" + (root.draftSize === 0 ? "  (Omarchy's size)" : "")
    }
    NoWheelSlider {
      scrollTarget: root.scrollTarget
      width: parent.width
      minimum: root.minSize
      maximum: root.maxSize
      step: 1
      integer: true
      value: root.previewSize
      trackColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
      fillColor: root.foreground
      knobColor: root.foreground
      onMoved: function (v) { root.draftSize = Math.round(v) }
    }

    // ---------- fade, hue shift and speed ----------
    Label { text: "TAIL FADE  " + root.draft.fade.toFixed(2) }
    NoWheelSlider {
      scrollTarget: root.scrollTarget
      width: parent.width
      minimum: 0
      maximum: 1
      step: 0.05
      value: root.draft.fade
      trackColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
      fillColor: root.foreground
      knobColor: root.foreground
      onMoved: function (v) { var d = Colors.copy(root.draft); d.fade = v; root.draft = d }
    }

    Label { text: "HUE SHIFT  " + root.draft.shift.toFixed(1) }
    NoWheelSlider {
      scrollTarget: root.scrollTarget
      width: parent.width
      minimum: 0
      maximum: 12
      step: 0.5
      value: root.draft.shift
      trackColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
      fillColor: root.foreground
      knobColor: root.foreground
      onMoved: function (v) { var d = Colors.copy(root.draft); d.shift = v; root.draft = d }
    }

    Label { text: "SPEED  " + Colors.rateFromDelay(root.draftDelay).toFixed(1) + " steps/s" }
    NoWheelSlider {
      scrollTarget: root.scrollTarget
      width: parent.width
      minimum: Colors.MIN_RATE
      maximum: Colors.MAX_RATE
      step: 0.5
      value: Colors.rateFromDelay(root.draftDelay)
      trackColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
      fillColor: root.foreground
      knobColor: root.foreground
      onMoved: function (v) { root.draftDelay = Colors.delayFromRate(v) }
    }
  }

  SectionHeader {
    title: "Modify Color Palette"
    expanded: root.paletteOpen
    hasCursor: root.paletteCursor
    unsaved: root.paletteDirty
    canReset: root.hasCustom
    resetTip: "Reset colors to the theme's defaults"
    onToggled: root.paletteOpen = !root.paletteOpen
    onHoveredHeader: root.headerHovered(1)
    onSaveClicked: root.savePalette()
    onUndoClicked: root.undoPalette()
    onResetClicked: root.resetPalette()
  }

  Column {
    id: paletteSection
    width: parent.width
    spacing: root.spacing
    visible: root.paletteOpen

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Color settings are saved for this theme only"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // ---------- head and background ----------
    Row {
      spacing: Style.space(18)
      Column {
        spacing: 4
        Label { text: "HEAD" }
        Swatch { slot: "head" }
      }
      Column {
        spacing: 4
        Label { text: "BACKGROUND" }
        Swatch { slot: "background" }
      }
    }

    // ---------- tails ----------
    Column {
      width: parent.width
      spacing: 6

      Label { text: "TAILS  " + root.colorCount + "/12" }

      // One chip per hue group, wrapping across the width.
      Flow {
        width: parent.width
        spacing: 8

      Repeater {
        model: root.draft.groups.length

        Rectangle {
          id: groupChip
          required property int index
          width: groupRow.implicitWidth + 10
          height: groupRow.implicitHeight + 8
          color: "transparent"
          radius: Style.cornerRadius > 0 ? 6 : 0
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

        Row {
          id: groupRow
          readonly property int index: groupChip.index
          anchors.centerIn: parent
          spacing: 4
          Text {
            width: 12
            anchors.verticalCenter: parent.verticalCenter
            text: String(groupRow.index + 1)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Repeater {
            model: root.draft.groups[groupRow.index] ? root.draft.groups[groupRow.index].length : 0
            Swatch {
              required property int index
              slot: "g" + groupRow.index + "s" + index
              onRemoveRequested: root.removeShade(groupRow.index, index)
            }
          }
          Button {
            anchors.verticalCenter: parent.verticalCenter
            text: "+"
            visible: root.colorCount < 12
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.addShade(groupRow.index)
          }
        }
        }
      }
      }

      Row {
        spacing: Style.space(10)
        Button {
          text: "Add group"
          iconText: "\u{F0415}"
          visible: root.colorCount < 12
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.addGroup()
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Right-click a color to remove it"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // ---------- picker ----------
    Row {
      width: parent.width
      spacing: 10

      // Saturation left to right, brightness bottom to top.
      Rectangle {
        id: svSquare
        width: parent.width - hueBar.width - parent.spacing
        height: 130
        color: Colors.hsvToHex(root.hue, 1, 1)
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#ffffffff" }
            GradientStop { position: 1; color: "#00ffffff" }
          }
        }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0; color: "#00000000" }
            GradientStop { position: 1; color: "#ff000000" }
          }
        }
        Rectangle {
          x: root.sat * svSquare.width - 7
          y: (1 - root.val) * svSquare.height - 7
          width: 14
          height: 14
          radius: 7
          color: "transparent"
          border.width: 2
          border.color: root.val > 0.5 ? "black" : "white"
        }
        MouseArea {
          anchors.fill: parent
          function at(mouse) {
            root.sat = Math.max(0, Math.min(1, mouse.x / width))
            root.val = Math.max(0, Math.min(1, 1 - mouse.y / height))
            root.pick()
          }
          onPressed: function (mouse) { at(mouse) }
          onPositionChanged: function (mouse) { if (pressed) at(mouse) }
        }
      }

      Rectangle {
        id: hueBar
        width: 20
        height: svSquare.height
        gradient: Gradient {
          GradientStop { position: 0.000; color: "#ff0000" }
          GradientStop { position: 0.167; color: "#ffff00" }
          GradientStop { position: 0.333; color: "#00ff00" }
          GradientStop { position: 0.500; color: "#00ffff" }
          GradientStop { position: 0.667; color: "#0000ff" }
          GradientStop { position: 0.833; color: "#ff00ff" }
          GradientStop { position: 1.000; color: "#ff0000" }
        }
        Rectangle {
          y: root.hue / 360 * hueBar.height - 2
          width: parent.width
          height: 4
          color: "white"
          border.width: 1
          border.color: "black"
        }
        MouseArea {
          anchors.fill: parent
          function at(mouse) {
            root.hue = Math.max(0, Math.min(359.9, mouse.y / height * 360))
            root.pick()
          }
          onPressed: function (mouse) { at(mouse) }
          onPositionChanged: function (mouse) { if (pressed) at(mouse) }
        }
      }
    }

    Row {
      spacing: 10
      Rectangle {
        width: 36
        height: hexField.height
        color: root.selectedHex || "transparent"
        border.width: 1
        border.color: root.line
      }
      TextField {
        id: hexField
        width: 130
        foreground: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        onAccepted: root.setSelected(text, false)
        onTextEdited: if (Colors.normalizeHex(text) && text.length >= 7) root.setSelected(text, true)
      }
    }

    Label { text: "THEME COLORS" }
    Flow {
      width: parent.width
      spacing: 4
      Repeater {
        model: root.themeSwatches
        Rectangle {
          required property string modelData
          width: 24
          height: 24
          color: modelData
          border.width: 1
          border.color: root.line
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setSelected(parent.modelData, false)
          }
        }
      }
    }
  }

  PanelSeparator {
    visible: root.paletteOpen
    foreground: root.foreground
  }

  Button {
    visible: root.paletteOpen
    text: "Manually Edit Color Configuration"
    iconText: "\u{F03EB}"
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    onClicked: root.editManually()
  }

  readonly property bool dropdownOpen: fontDropdown.popupOpen

  Component.onCompleted: {
    load()
    loadSettings()
  }
}
