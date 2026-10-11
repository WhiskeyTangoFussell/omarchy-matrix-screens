import QtQuick
import qs.Ui

// Omarchy's PanelSlider, but the mouse wheel and trackpad scroll the panel
// instead of nudging the value, so scrolling past a slider can't change it.
// Clicking and dragging work as usual.
PanelSlider {
  id: slider

  // The Flickable to scroll instead (a ScrollView's contentItem).
  property var scrollTarget: null

  // On top of the slider's own mouse area; takes no buttons, so presses and
  // drags fall through to it, but it catches the wheel first.
  MouseArea {
    anchors.fill: parent
    z: 10
    acceptedButtons: Qt.NoButton
    onWheel: function (wheel) {
      var f = slider.scrollTarget
      if (f && f.contentHeight > f.height) {
        // Trackpads report pixels; mouse wheels report 120 per notch.
        var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * 60
        f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY - dy))
      }
      wheel.accepted = true
    }
  }
}
