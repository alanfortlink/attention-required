import QtQuick
import QtQuick.Particles
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Confetti on every screen, in the theme's colours.
//
// Options: duration (seconds it keeps coming, 1), intensity (amount, 1),
// speed (launch power, 1), style: "cannons" (shot up from the bottom
// corners, the default), "burst" (out from the centre), "rain" (falls
// from the top).
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property bool active: false
  property bool emitting: false
  property real amount: 1
  property real power: 1
  property string style: "cannons"
  readonly property int lifeMs: 4500

  function number(value, fallback, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return fallback
    return Math.max(min, Math.min(max, n))
  }

  function trigger(opts, notif, rule) {
    opts = opts || {}
    amount = number(opts.intensity, 1, 0.2, 3)
    power = number(opts.speed, 1, 0.3, 3)
    style = opts.style === "rain" || opts.style === "burst" ? String(opts.style) : "cannons"
    var seconds = number(opts.duration, 1, 0.5, 15)
    active = true
    emitting = true
    stopEmit.interval = Math.round(seconds * 1000)
    stopEmit.restart()
    off.interval = Math.round(seconds * 1000) + lifeMs
    off.restart()
  }

  Timer { id: stopEmit; onTriggered: root.emitting = false }
  Timer { id: off; onTriggered: root.active = false }

  readonly property var palette: [
    Color.accent, Qt.lighter(Color.accent, 1.4), Color.urgent, Qt.lighter(Color.urgent, 1.5),
    Color.foreground, Qt.darker(Color.accent, 1.4)
  ]

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
      WlrLayershell.namespace: "attention-required-confetti"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      // Launch speed for the cannons and the burst: enough to reach most of
      // the way up the screen against the gravity below.
      readonly property real launch: Math.sqrt(2 * gravity.magnitude * window.height * 0.8) * root.power
      readonly property bool cannons: root.style === "cannons"
      readonly property bool burst: root.style === "burst"
      readonly property bool rain: root.style === "rain"

      ParticleSystem {
        id: system
        anchors.fill: parent
        running: root.active

        // Cannon in the bottom-left corner, firing up and to the right.
        Emitter {
          x: 0
          y: window.height
          width: 1
          height: 1
          enabled: root.emitting && window.cannons
          emitRate: Math.round(70 * root.amount)
          lifeSpan: root.lifeMs
          lifeSpanVariation: 800
          size: Style.space(10)
          sizeVariation: Style.space(6)
          velocity: AngleDirection { angle: 295; angleVariation: 18; magnitude: window.launch; magnitudeVariation: window.launch * 0.25 }
        }
        // Cannon in the bottom-right corner, firing up and to the left.
        Emitter {
          x: window.width
          y: window.height
          width: 1
          height: 1
          enabled: root.emitting && window.cannons
          emitRate: Math.round(70 * root.amount)
          lifeSpan: root.lifeMs
          lifeSpanVariation: 800
          size: Style.space(10)
          sizeVariation: Style.space(6)
          velocity: AngleDirection { angle: 245; angleVariation: 18; magnitude: window.launch; magnitudeVariation: window.launch * 0.25 }
        }
        // Burst from the middle, in every direction.
        Emitter {
          x: window.width / 2
          y: window.height / 2
          width: 1
          height: 1
          enabled: root.emitting && window.burst
          emitRate: Math.round(160 * root.amount)
          lifeSpan: root.lifeMs
          lifeSpanVariation: 800
          size: Style.space(10)
          sizeVariation: Style.space(6)
          velocity: AngleDirection { angle: 270; angleVariation: 180; magnitude: window.launch * 0.6; magnitudeVariation: window.launch * 0.3 }
        }
        // Rain from the top edge.
        Emitter {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          enabled: root.emitting && window.rain
          emitRate: Math.round(90 * root.amount)
          lifeSpan: root.lifeMs
          lifeSpanVariation: 800
          size: Style.space(10)
          sizeVariation: Style.space(6)
          velocity: AngleDirection { angle: 90; angleVariation: 30; magnitude: Style.space(120) * root.power; magnitudeVariation: Style.space(80) }
        }

        Gravity {
          id: gravity
          anchors.fill: parent
          angle: 90
          magnitude: window.rain ? Style.space(90) : Style.space(900)
        }
        Wander {
          anchors.fill: parent
          xVariance: Style.space(140)
          pace: Style.space(120)
        }

        ItemParticle {
          delegate: Rectangle {
            width: Style.space(6) + Math.random() * Style.space(8)
            height: Style.space(4) + Math.random() * Style.space(5)
            radius: Style.space(1)
            color: root.palette[Math.floor(Math.random() * root.palette.length)]
            rotation: Math.random() * 360
            RotationAnimation on rotation {
              loops: Animation.Infinite
              from: 0
              to: 360
              duration: 700 + Math.random() * 900
            }
          }
        }
      }
    }
  }
}
