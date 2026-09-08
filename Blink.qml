import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Every screen dims and comes back, once or a few times.
//
// Options: duration (seconds, 1), intensity (how dark, 0.6), speed
// (blinks per second, 2).
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property bool active: false
  property real level: 0
  property real darkness: 0.6
  property int pulseMs: 500

  function number(value, fallback, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return fallback
    return Math.max(min, Math.min(max, n))
  }

  function trigger(opts, notif, rule) {
    opts = opts || {}
    var duration = number(opts.duration, 1, 0.1, 30)
    var speed = number(opts.speed, 2, 0.2, 30)
    darkness = number(opts.intensity, 0.6, 0.01, 1)
    pulseMs = Math.round(1000 / speed)
    anim.stop()
    level = 0
    active = true
    anim.loops = Math.max(1, Math.round(duration * speed))
    anim.start()
  }

  SequentialAnimation {
    id: anim
    NumberAnimation { target: root; property: "level"; from: 0; to: 1; duration: root.pulseMs / 2; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "level"; from: 1; to: 0; duration: root.pulseMs / 2; easing.type: Easing.InQuad }
    onFinished: {
      root.level = 0
      root.active = false
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.active
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "attention-required-blink"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      Rectangle {
        anchors.fill: parent
        color: Color.background
        opacity: root.level * root.darkness
      }
    }
  }
}
