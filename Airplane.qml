import QtQuick
import QtQuick.Particles
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Rules.js" as Rules

// A little plane flies across every screen towing a flag with the message.
// The plane bobs and pitches on the air, leaves a trail, and the flag
// ripples behind it: it is drawn once, then shown as a row of thin slices
// each riding its own bit of a travelling wave.
//
// Options: duration (flight time in seconds, 7), intensity (size, 1),
// altitude (0..1 from the top, 0.2), direction (ltr | rtl), text
// ("{summary}" template).
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property bool active: false
  property real flight: 0        // 0 at take-off, 1 when gone
  property real phase: 0         // the wave running down the flag
  property string text: ""
  property string direction: "ltr"
  property real size: 1
  property real altitude: 0.2
  property int flightMs: 7000

  function number(value, fallback, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return fallback
    return Math.max(min, Math.min(max, n))
  }

  function trigger(opts, notif, rule) {
    opts = opts || {}
    text = Rules.renderTemplate(opts.text, notif, rule)
    direction = opts.direction === "rtl" ? "rtl" : "ltr"
    size = number(opts.intensity, 1, 0.5, 3)
    altitude = number(opts.altitude, 0.2, 0.05, 0.95)
    flightMs = Math.round(number(opts.duration, 7, 2, 20) * 1000)
    anim.stop()
    flight = 0
    active = true
    anim.duration = flightMs
    anim.start()
  }

  NumberAnimation {
    id: anim
    target: root
    property: "flight"
    from: 0
    to: 1
    onFinished: root.active = false
  }

  NumberAnimation on phase {
    running: root.active
    from: 0
    to: Math.PI * 2
    duration: 520
    loops: Animation.Infinite
  }

  // The bob is a slow sine over the flight; the pitch follows its slope so
  // the nose points where the plane is going.
  readonly property real bobCycles: 3.2
  readonly property real bob: Math.sin(root.flight * Math.PI * 2 * bobCycles)
  readonly property real slope: Math.cos(root.flight * Math.PI * 2 * bobCycles)

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
      WlrLayershell.namespace: "attention-required-airplane"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      readonly property bool ltr: root.direction === "ltr"
      readonly property real bobPx: Style.space(14) * root.size

      Item {
        id: convoy
        width: row.implicitWidth
        height: row.implicitHeight
        x: window.ltr ? Math.round(-width + root.flight * (window.width + width))
                      : Math.round(window.width - root.flight * (window.width + width))
        y: Math.round(root.altitude * window.height + root.bob * window.bobPx)

        Row {
          id: row
          spacing: 0
          layoutDirection: window.ltr ? Qt.RightToLeft : Qt.LeftToRight

          // ---- the plane ----
          Item {
            id: planeBox
            width: plane.implicitHeight
            height: plane.implicitHeight
            anchors.verticalCenter: parent.verticalCenter

            Text {
              id: plane
              anchors.centerIn: parent
              text: "󰀝"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Math.round(Style.font.display * 2.2 * root.size)
              // The glyph points north-east. Turn it 45° to fly east and pitch
              // it with the bob; a westbound plane is the same, mirrored, so
              // it stays the right way up.
              transform: [
                Rotation {
                  origin.x: plane.width / 2
                  origin.y: plane.height / 2
                  angle: 45 - root.slope * 9
                },
                Scale {
                  origin.x: plane.width / 2
                  origin.y: plane.height / 2
                  xScale: window.ltr ? 1 : -1
                }
              ]
            }

            // Exhaust: soft puffs that drift back and fade.
            ParticleSystem {
              id: exhaust
              anchors.fill: parent
              running: root.active
              Emitter {
                x: window.ltr ? 0 : planeBox.width
                y: planeBox.height * 0.55
                width: 1
                height: 1
                enabled: root.active && root.flight > 0.01 && root.flight < 0.99
                emitRate: 26
                lifeSpan: 900
                lifeSpanVariation: 300
                size: Math.round(Style.space(9) * root.size)
                sizeVariation: Math.round(Style.space(4) * root.size)
                endSize: Math.round(Style.space(18) * root.size)
                velocity: AngleDirection {
                  angle: window.ltr ? 180 : 0
                  angleVariation: 12
                  magnitude: Style.space(70) * root.size
                  magnitudeVariation: Style.space(30) * root.size
                }
              }
              ImageParticle {
                source: "qrc:///particleresources/fuzzydot.png"
                color: Color.foreground
                alpha: 0.35
                alphaVariation: 0.1
              }
            }
          }

          // ---- the rope ----
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(Style.space(36) * root.size)
            height: Math.max(2, Math.round(Style.space(2) * root.size))
            color: Color.foreground
            opacity: 0.7
            rotation: root.slope * 3
          }

          // ---- the flag, rippling ----
          Item {
            id: flag
            anchors.verticalCenter: parent.verticalCenter
            readonly property int slices: 28
            readonly property real amp: Style.space(5) * root.size
            readonly property real sliceW: Math.ceil(card.width / slices)
            width: card.width
            height: card.height + amp * 2

            // Drawn once, off to the side of what is shown.
            Rectangle {
              id: card
              visible: true
              opacity: 0
              width: label.implicitWidth + Math.round(Style.space(28) * root.size)
              height: label.implicitHeight + Math.round(Style.space(16) * root.size)
              color: Color.popups.background
              border.width: Math.max(2, Math.round(Style.space(2) * root.size))
              border.color: Color.accent
              radius: Math.round(Style.space(4) * root.size)
              Text {
                id: label
                anchors.centerIn: parent
                text: root.text
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Math.round(Style.font.display * root.size)
                font.weight: Font.DemiBold
              }
            }

            Repeater {
              model: flag.slices
              delegate: ShaderEffectSource {
                required property int index
                // The wave grows towards the free end of the flag, which is
                // the end away from the rope.
                readonly property real along: window.ltr ? (flag.slices - 1 - index) / (flag.slices - 1) : index / (flag.slices - 1)
                sourceItem: card
                sourceRect: Qt.rect(index * flag.sliceW, 0, flag.sliceW, card.height)
                width: flag.sliceW + 1
                height: card.height
                x: index * flag.sliceW
                y: flag.amp + Math.sin(root.phase + along * 7) * flag.amp * (0.15 + along)
                // Live, so a new message on the next flight is what shows.
                live: true
                smooth: true
              }
            }
          }
        }
      }
    }
  }
}
