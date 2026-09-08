import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Rules.js" as Rules

// A big card with the message that slides in, stays, and slides out. On
// every screen, click-through, reserves no space.
//
// Options: duration (seconds it stays, 3), intensity (size, 1), speed
// (slide speed, 4), position (top | center | bottom), color (accent |
// urgent | foreground or any CSS color), text ("{summary}" template).
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property bool active: false
  property real progress: 0
  property string title: ""
  property string body: ""
  property string position: "top"
  property real size: 1
  property color glow: Color.accent
  property int slideMs: 250
  property int holdMs: 3000

  function number(value, fallback, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return fallback
    return Math.max(min, Math.min(max, n))
  }

  function resolveColor(value) {
    var v = String(value || "").trim().toLowerCase()
    if (!v || v === "accent") return Color.accent
    if (v === "urgent") return Color.urgent
    if (v === "foreground" || v === "text") return Color.foreground
    var c = Qt.color(value)
    return c.valid === false ? Color.accent : c
  }

  function trigger(opts, notif, rule) {
    opts = opts || {}
    var custom = String(opts.text || "").trim()
    title = Rules.renderTemplate(custom, notif, rule)
    body = custom ? "" : Rules.stripTags(notif ? notif.body : "")
    position = opts.position === "center" || opts.position === "bottom" ? String(opts.position) : "top"
    size = number(opts.intensity, 1, 0.5, 2.5)
    slideMs = Math.round(1000 / number(opts.speed, 4, 1, 10))
    holdMs = Math.round(number(opts.duration, 3, 0.5, 30) * 1000)
    glow = resolveColor(opts.color)
    off.stop()
    hide.stop()
    active = true
    progress = 1
    hide.interval = holdMs
    hide.restart()
  }

  Behavior on progress { NumberAnimation { duration: root.slideMs; easing.type: Easing.OutCubic } }

  Timer {
    id: hide
    onTriggered: {
      root.progress = 0
      off.interval = root.slideMs + 60
      off.restart()
    }
  }
  Timer {
    id: off
    onTriggered: root.active = false
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
      WlrLayershell.namespace: "attention-required-banner"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      readonly property int margin: Style.space(24)

      Rectangle {
        id: card
        readonly property int pad: Math.round(Style.space(18) * root.size)
        width: Math.min(window.width * 0.7, column.implicitWidth + pad * 2)
        height: column.implicitHeight + pad * 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.position === "top" ? Math.round(-height + root.progress * (height + window.margin))
         : root.position === "bottom" ? Math.round(window.height - root.progress * (height + window.margin))
         : Math.round((window.height - height) / 2)
        opacity: root.position === "center" ? root.progress : 1
        color: Color.popups.background
        radius: Style.cornerRadius
        border.width: Math.max(2, Style.space(2))
        border.color: root.glow

        Column {
          id: column
          anchors.centerIn: parent
          width: Math.min(window.width * 0.7 - card.pad * 2, Math.max(titleText.implicitWidth, bodyText.visible ? bodyText.implicitWidth : 0))
          spacing: Math.round(Style.space(6) * root.size)

          Text {
            id: titleText
            width: parent.width
            text: root.title
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.display * 1.4 * root.size)
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
          }
          Text {
            id: bodyText
            visible: root.body.length > 0
            width: parent.width
            text: root.body
            color: Color.popups.text
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.body * 1.2 * root.size)
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
