import QtQuick
import Quickshell
import Quickshell.Wayland

// Keeps the compositor drawing a frame every refresh while a screen shader
// runs. Hyprland renders only when something on screen changed; a shader
// driven by time changes nothing by itself, so a nudge would move only when
// the cursor did. A 2px window per screen that repaints every frame is
// enough damage to keep the frames coming.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property bool active: false
  property real tick: 0

  function run(seconds) {
    var ms = Math.round((Number(seconds) > 0 ? Number(seconds) : 1) * 1000) + 150
    stop.interval = Math.max(200, ms)
    active = true
    stop.restart()
  }

  Timer {
    id: stop
    onTriggered: root.active = false
  }

  NumberAnimation on tick {
    running: root.active
    from: 0
    to: 1
    duration: 1000
    loops: Animation.Infinite
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.active
      color: "transparent"
      implicitWidth: 2
      implicitHeight: 2
      anchors { top: true; left: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "attention-required-ticker"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.02 + 0.03 * root.tick)
      }
    }
  }
}
