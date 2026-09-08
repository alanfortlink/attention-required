import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// A glow that pulses in from the edges of every screen. Click-through, takes
// no keyboard focus, and reserves no space, so nothing under it moves.
//
// Options on the effect:
//   duration   seconds the glow keeps pulsing, default 1
//   intensity  0..1, how strong the glow gets, default 0.9
//   speed      pulses per second, default 3
//   thickness  px of glow from each edge, default 64
//   color      a theme role ("accent" | "urgent" | "foreground") or any CSS color
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property color glow: Color.accent
  property int pulses: 3
  property int thickness: 64
  property int pulseMs: 333
  property real intensity: 0.9
  property real level: 0
  property bool active: false

  function resolveColor(value) {
    var v = String(value || "").trim().toLowerCase()
    if (!v || v === "accent") return Color.accent
    if (v === "urgent") return Color.urgent
    if (v === "foreground" || v === "text") return Color.foreground
    if (v === "background") return Color.background
    var c = Qt.color(value)
    return c.valid === false ? Color.accent : c
  }

  function number(value, fallback, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return fallback
    return Math.max(min, Math.min(max, n))
  }

  function trigger(opts) {
    opts = opts || {}
    glow = resolveColor(opts.color)
    var duration = number(opts.duration, 1, 0.1, 60)
    var speed = number(opts.speed, 3, 0.1, 30)
    intensity = number(opts.intensity, 0.9, 0.01, 1)
    thickness = Math.round(number(opts.thickness, 64, 1, 2000))
    pulseMs = Math.round(1000 / speed)
    pulses = Math.max(1, Math.round(duration * speed))
    anim.stop()
    level = 0
    active = true
    anim.loops = pulses
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
      id: window
      required property var modelData
      screen: modelData
      visible: root.active
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "attention-required"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      readonly property color solid: Qt.rgba(root.glow.r, root.glow.g, root.glow.b, 0.9)
      readonly property color clear: Qt.rgba(root.glow.r, root.glow.g, root.glow.b, 0)

      Item {
        anchors.fill: parent
        opacity: root.level * root.intensity

        Rectangle {
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: root.thickness
          gradient: Gradient {
            GradientStop { position: 0; color: window.solid }
            GradientStop { position: 1; color: window.clear }
          }
        }
        Rectangle {
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
          height: root.thickness
          gradient: Gradient {
            GradientStop { position: 0; color: window.clear }
            GradientStop { position: 1; color: window.solid }
          }
        }
        Rectangle {
          anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
          width: root.thickness
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: window.solid }
            GradientStop { position: 1; color: window.clear }
          }
        }
        Rectangle {
          anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
          width: root.thickness
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: window.clear }
            GradientStop { position: 1; color: window.solid }
          }
        }
      }
    }
  }
}
