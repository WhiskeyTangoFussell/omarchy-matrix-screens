import Quickshell
import QtQuick

// Development preview:  quickshell -p Preview.qml
// Runs the renderer in a plain window with the Osaka Jade terminal palette
// and shows live per-tick timings.
ShellRoot {
  FloatingWindow {
    visible: true
    implicitWidth: 1280
    implicitHeight: 720
    color: "#111c18"

    MatrixScreen {
      id: screen
      anchors.fill: parent
      fontFamily: "JetBrainsMono Nerd Font"
      fontPixelSize: 12
      boldLevel: 1
      profile: true
    }

    Rectangle {
      anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
      width: stats.implicitWidth + 16
      height: stats.implicitHeight + 8
      color: "#cc090f0d"
      border.color: "#509475"
      visible: screen.profiler.summary.length > 0

      Text {
        id: stats
        anchors.centerIn: parent
        color: "#C1C497"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
        text: screen.profiler.summary
      }
    }
  }
}
