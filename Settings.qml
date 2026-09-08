import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "EffectCatalog.js" as Catalog

// Bar widget + settings popup.
//
// In the bar: a bell, ringing while the effects are armed, asleep and dimmed
// while paused. Click opens the settings; right-click pauses or resumes
// without opening anything, like the notification-silencing bell.
//
// The popup is three pages deep: the list of rules; one rule (name, words,
// apps, which effects, cooldown); one effect of that rule (its sliders and
// choices). Turning an effect on for a rule opens its page right away.
// Everything is written to ~/.config/attention-required/rules.json through
// the service (Service.qml); the file stays the source of truth and can
// still be edited by hand.
Panel {
  id: root
  moduleName: "alanfortlink.attention-required"
  ipcTarget: "alanfortlink.attention-required"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("alanfortlink.attention-required") : null
  readonly property bool paused: svc ? !svc.enabled : false
  readonly property var cfg: svc ? svc.rawConfig : ({})
  readonly property var rules: svc ? svc.rawRules : []
  readonly property bool whileDnd: cfg && cfg.whileDnd !== false
  readonly property bool letThrough: cfg && cfg.letThrough !== false
  readonly property var appSuggestions: svc ? svc.appSuggestions : []

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int trailInset: Style.space(6)
  readonly property int labelW: Style.space(96)
  readonly property var catalog: Catalog.EFFECTS

  // ---------- navigation ----------
  property string page: "list"        // list | rule | effect
  property int current: -1            // the rule the deeper pages are about
  property string currentEffect: ""   // the effect page's type
  property int confirmDeleteIndex: -1
  readonly property var rule: current >= 0 && current < rules.length ? rules[current] : null
  readonly property var effectDef: Catalog.find(currentEffect)

  function openRule(i) { current = i; page = "rule" }
  function openEffect(type) { currentEffect = type; page = "effect" }
  function back() {
    if (page === "effect") page = "rule"
    else if (page === "rule") page = "list"
    keyCatcher.forceActiveFocus()
  }

  onOpenedChanged: {
    if (opened && svc) svc.refreshApps()
    if (!opened) { confirmDeleteIndex = -1; page = "list" }
  }
  onRulesChanged: {
    if (current >= rules.length) { current = -1; page = "list" }
    if (confirmDeleteIndex >= rules.length) confirmDeleteIndex = -1
  }

  // ---------- helpers over a raw rule ----------
  function strList(v) {
    if (Array.isArray(v)) return v.map(function(x) { return String(x) }).filter(function(x) { return x.length > 0 })
    if (v === undefined || v === null || v === "") return []
    return [String(v)]
  }
  function ruleName(r, index) {
    return r && r.name ? String(r.name) : ("rule-" + (index + 1))
  }
  function effectNames(index) {
    if (!svc) return []
    return svc.ruleEffectList(index).map(svc.effectTypeOf).filter(function(n) { return n.length > 0 })
  }
  function ruleSummary(r, index) {
    var words = strList(r ? r.words : [])
    var apps = strList(r ? r.apps : [])
    var effects = effectNames(index).map(Catalog.labelFor)
    return [words.length ? words.join(", ") : "any notification",
            apps.length ? apps.join(", ") : "any app",
            effects.length ? effects.join(", ") : "no effect"].join("  ·  ")
  }
  function armedLabel() {
    var n = rules.length
    return (paused ? "Paused" : "Armed") + " · " + n + (n === 1 ? " rule" : " rules")
  }
  function fmt(v, step, unit) {
    var n = Number(v)
    var text = step >= 1 ? String(Math.round(n)) : (step >= 0.1 ? n.toFixed(1) : n.toFixed(2))
    return text + (unit || "")
  }

  // Drives the popup from a terminal, for screenshots and tests:
  //   omarchy-shell alanfortlink.attention-required.ui show list
  //   omarchy-shell alanfortlink.attention-required.ui show rule 0
  //   omarchy-shell alanfortlink.attention-required.ui show effect 0 banner
  IpcHandler {
    target: "alanfortlink.attention-required.ui"
    function show(what: string, index: string, type: string): string {
      var i = Number(index)
      if (what === "rule" && i >= 0) root.openRule(i)
      else if (what === "effect" && i >= 0) { root.current = i; root.openEffect(type) }
      else root.page = "list"
      root.open()
      return root.page
    }
  }

  // ---------- bar ----------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.paused ? "󰂜" : "󰂞"
    dimmed: root.paused
    tooltipText: (root.paused ? "Attention effects paused" : "Attention effects armed") + " · click: settings · right-click: " + (root.paused ? "resume" : "pause")
    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.svc) root.svc.setEnabled(root.paused) }
      else root.toggle()
    }
  }

  // ---------- popup ----------
  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(topBlock.implicitHeight + Style.space(10) + Math.min(body.implicitHeight, Style.space(640)) + Style.space(4))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.confirmDeleteIndex !== -1
      onCloseRequested: root.page === "list" ? root.close() : root.back()
      onTabRequested: function(direction) {
        var n = keyCatcher.activeFocus ? null : keyCatcher.nextItemInFocusChain(direction > 0)
        if (n && n !== keyCatcher) n.forceActiveFocus(Qt.TabFocusReason)
        else if (root.page === "list") root.switchPanel(direction)
      }
      Keys.onPressed: function(event) {
        if (deleteDialog.handleKey(event)) event.accepted = true
      }

      ConfirmDialog {
        id: deleteDialog
        anchors.fill: parent
        z: 10
        opened: root.confirmDeleteIndex !== -1
        message: "Delete the rule “" + root.ruleName(root.rules[root.confirmDeleteIndex], root.confirmDeleteIndex) + "”?"
        confirmText: "Delete"
        selectedIndex: 0
        foreground: root.fg
        fontFamily: root.fontFamily
        onCanceled: root.confirmDeleteIndex = -1
        onConfirmed: {
          var i = root.confirmDeleteIndex
          root.confirmDeleteIndex = -1
          root.page = "list"
          root.current = -1
          if (root.svc) root.svc.removeRule(i)
          keyCatcher.forceActiveFocus()
        }
      }
      Connections {
        target: root
        function onConfirmDeleteIndexChanged() { if (root.confirmDeleteIndex !== -1) { deleteDialog.selectedIndex = 0; keyCatcher.forceActiveFocus() } }
      }

      // ---------- fixed top: hero, then the page's own header ----------
      Column {
        id: topBlock
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: "Attention Required"
          meta: root.armedLabel()
          detail: root.svc && root.svc.configError !== "" ? root.svc.configError : ""
          foreground: root.fg
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: root.paused ? "󰂜" : "󰂞"
              color: root.fg
              opacity: root.paused ? 0.5 : 1
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              checked: !root.paused
              foreground: root.fg
              cursorPad: root.trailInset
              onToggled: if (root.svc) root.svc.setEnabled(root.paused)
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.fg }

        // Breadcrumb: where you are, and the way back.
        Item {
          width: parent.width
          height: Style.spacing.controlHeight
          Button {
            id: backButton
            visible: root.page !== "list"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰅁"
            text: root.page === "effect" ? root.ruleName(root.rule, root.current) : "Rules"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            tooltipText: "Back (Esc)"
            onClicked: root.back()
          }
          PanelSectionHeader {
            visible: root.page === "list"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Rules"
            foreground: root.fg
            fontFamily: root.fontFamily
          }
          Text {
            visible: root.page !== "list"
            anchors.left: backButton.right
            anchors.leftMargin: Style.space(10)
            anchors.right: headerTrailing.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.page === "effect" ? (root.effectDef ? root.effectDef.label : root.currentEffect) : root.ruleName(root.rule, root.current)
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Row {
            id: headerTrailing
            anchors.right: parent.right
            anchors.rightMargin: root.trailInset
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            PanelActionButton {
              visible: root.page === "list"
              iconText: "󰐕"
              tooltipText: "Add a rule"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: if (root.svc) root.openRule(root.svc.addRule())
            }
            Button {
              visible: root.page !== "list"
              text: "Try"
              iconText: "󰐊"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              tooltipText: root.page === "effect" ? "Run this effect as this rule would" : "Run this rule's effects now"
              onClicked: {
                if (!root.svc) return
                if (root.page === "effect") root.svc.tryRuleEffect(root.current, root.currentEffect)
                else root.svc.tryRule(root.current)
              }
            }
          }
        }
      }

      // ---------- scrolling body: the page ----------
      Flickable {
        id: scroller
        anchors.top: topBlock.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: body
          width: scroller.width - (scroller.interactive ? Style.space(8) : 0)
          Loader {
            width: parent.width
            sourceComponent: root.page === "rule" ? ruleView : (root.page === "effect" ? effectView : listView)
          }
        }
      }
    }
  }

  // ======================= page 1: the rules =======================
  Component {
    id: listView
    Column {
      spacing: Style.space(4)

      Column {
        visible: root.rules.length === 0
        width: parent.width
        spacing: Style.space(2)
        Text {
          text: "No rules yet"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Note { text: "Add one with the plus button, then give it the words to watch for and an effect." }
      }

      Repeater {
        model: root.rules.length
        delegate: RuleLine {
          width: parent.width
          ruleIndex: index
          rule: root.rules[index]
        }
      }

      Section { title: "While notifications are silenced" }
      SwitchRow {
        label: "Rules still fire"
        checked: root.whileDnd
        onToggled: if (root.svc) root.svc.setWhileDnd(!root.whileDnd)
      }
      SwitchRow {
        label: "Matched notifications are shown anyway"
        checked: root.whileDnd && root.letThrough
        enabled: root.whileDnd
        opacity: root.whileDnd ? 1 : 0.5
        onToggled: if (root.svc && root.whileDnd) root.svc.setLetThrough(!root.letThrough)
      }
      Note { text: "Silence everything with the bell in the bar and only what a rule matches gets through: its effects run and its toast is posted again so you see it." }
      Item { width: 1; height: Style.space(2) }
    }
  }

  component RuleLine: Item {
    id: line
    property int ruleIndex: -1
    property var rule: ({})
    readonly property bool ruleOn: rule && rule.enabled !== false
    readonly property bool idle: root.effectNames(ruleIndex).length === 0
    height: Style.space(38)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(6)
      color: lineArea.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent"
    }
    ToggleSwitch {
      id: onSwitch
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      checked: line.ruleOn
      foreground: root.fg
      onToggled: if (root.svc) root.svc.updateRule(line.ruleIndex, { enabled: line.ruleOn ? false : undefined })
    }
    Text {
      id: nameText
      anchors.left: onSwitch.right
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: root.ruleName(line.rule, line.ruleIndex)
      color: root.fg
      opacity: line.ruleOn ? 1 : 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
      elide: Text.ElideRight
      width: Math.min(implicitWidth, Style.space(170))
    }
    Text {
      anchors.left: nameText.right
      anchors.leftMargin: Style.space(10)
      anchors.right: chevron.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: root.ruleSummary(line.rule, line.ruleIndex)
      color: line.idle ? Color.urgent : root.dim
      opacity: line.ruleOn ? 1 : 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
    Text {
      id: chevron
      anchors.right: parent.right
      anchors.rightMargin: root.trailInset + Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: "󰅂"
      color: lineArea.containsMouse ? root.fg : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    MouseArea {
      id: lineArea
      anchors.fill: parent
      anchors.leftMargin: onSwitch.width + Style.space(6)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openRule(line.ruleIndex)
    }
  }

  // ======================= page 2: one rule =======================
  // Controls sit in the order Tab walks them: name, words, match, apps,
  // effects, cooldown, delete.
  Component {
    id: ruleView
    Column {
      id: editor
      spacing: Style.space(10)

      EditorRow {
        label: "Name"
        ConfigField {
          id: nameField
          width: parent.width - root.trailInset
          placeholderText: "empty: rule-" + (root.current + 1)
          current: root.rule && root.rule.name ? String(root.rule.name) : ""
          commit: function(t) { if (root.svc) root.svc.updateRule(root.current, { name: t.trim() || undefined }) }
        }
      }
      EditorRow {
        label: "Words"
        ChipField {
          width: parent.width
          values: root.strList(root.rule ? root.rule.words : [])
          placeholder: "add a word or /regex/"
          emptyText: "empty: any notification"
          allowRegex: true
          onCommitted: function(v) { if (root.svc) root.svc.updateRule(root.current, { words: v }) }
        }
      }
      EditorRow {
        label: "Match"
        Row {
          spacing: Style.space(10)
          ButtonGroup {
            anchors.verticalCenter: parent.verticalCenter
            options: [{ value: "any", label: "Any word" }, { value: "all", label: "All words" }]
            value: root.rule && String(root.rule.match || "").toLowerCase() === "all" ? "all" : "any"
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onChanged: function(v) { if (root.svc) root.svc.updateRule(root.current, { match: v === "all" ? "all" : undefined }) }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.rule && String(root.rule.match || "").toLowerCase() === "all" ? "every word must appear" : "one word is enough"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
      EditorRow {
        label: "Apps"
        ChipField {
          width: parent.width
          values: root.strList(root.rule ? root.rule.apps : [])
          placeholder: "add an app"
          emptyText: "empty: any app"
          suggestions: root.appSuggestions
          onCommitted: function(v) { if (root.svc) root.svc.updateRule(root.current, { apps: v }) }
        }
      }
      // The rule's effects, one row each with its settings at a glance, a
      // button to open it and one to drop it; then a button that unfolds
      // the effects not yet on the rule.
      EditorRow {
        label: "Effects"
        Column {
          id: effectsBox
          width: parent.width - root.trailInset
          spacing: Style.space(6)
          property bool adding: false
          readonly property var active: root.effectNames(root.current)
          readonly property var available: root.catalog.filter(function(e) { return effectsBox.active.indexOf(e.type) === -1 })

          Repeater {
            model: effectsBox.active
            delegate: EffectLine {
              required property string modelData
              width: effectsBox.width
              type: modelData
            }
          }

          Note {
            visible: effectsBox.active.length === 0
            text: "empty: the rule matches but nothing happens yet"
          }

          Button {
            text: effectsBox.adding ? "Pick an effect below" : "Add effect"
            iconText: effectsBox.adding ? "󰅀" : "󰐕"
            bordered: true
            focusable: true
            enabled: effectsBox.available.length > 0
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: effectsBox.adding = !effectsBox.adding
          }

          Flow {
            visible: effectsBox.adding
            width: parent.width
            spacing: Style.spacing.md
            Repeater {
              model: effectsBox.available
              delegate: Button {
                required property var modelData
                text: modelData.label
                iconText: modelData.icon || ""
                bordered: true
                focusable: true
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                tooltipText: modelData.subtitle
                onClicked: {
                  if (!root.svc) return
                  effectsBox.adding = false
                  root.svc.addRuleEffect(root.current, modelData.type)
                  root.openEffect(modelData.type)
                }
              }
            }
          }
        }
      }
      EditorRow {
        label: "Cooldown"
        Row {
          spacing: Style.space(8)
          NumberField {
            anchors.verticalCenter: parent.verticalCenter
            label: ""
            from: 0
            to: 3600
            stepSize: 1
            value: root.rule && isFinite(Number(root.rule.cooldown)) ? Math.round(Number(root.rule.cooldown)) : 3
            foreground: root.fg
            fontFamily: root.fontFamily
            onModified: function(v) { if (root.svc) root.svc.updateRule(root.current, { cooldown: v }) }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "seconds before this rule can fire again"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Item { width: 1; height: Style.space(4) }
      Item {
        width: parent.width
        height: Style.spacing.controlHeight
        Button {
          anchors.right: parent.right
          anchors.rightMargin: root.trailInset
          anchors.verticalCenter: parent.verticalCenter
          text: "Delete rule"
          iconText: "󰆴"
          bordered: true
          focusable: true
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.confirmDeleteIndex = root.current
        }
      }
      Item { width: 1; height: Style.space(2) }
    }
  }

  // ======================= page 3: one effect of that rule =======================
  Component {
    id: effectView
    Column {
      spacing: Style.space(10)
      readonly property var def: root.effectDef

      Note { text: def ? def.subtitle : "" }

      Repeater {
        model: def ? def.rows : []
        delegate: Item {
          id: sliderRow
          required property var modelData
          readonly property real stored: root.svc ? Number(root.svc.ruleEffectOption(root.current, root.currentEffect, modelData.key, modelData.fallback)) : modelData.fallback
          property real shown: stored
          onStoredChanged: if (!slider.dragging) shown = stored
          width: parent.width
          height: Style.spacing.controlHeight

          RowLabel { anchors.left: parent.left; text: sliderRow.modelData.label }
          PanelSlider {
            id: slider
            bar: root.bar
            anchors.left: parent.left
            anchors.leftMargin: root.labelW
            anchors.right: valueText.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            minimum: sliderRow.modelData.min
            maximum: sliderRow.modelData.max
            step: sliderRow.modelData.step
            integer: sliderRow.modelData.step >= 1
            value: isFinite(sliderRow.stored) ? sliderRow.stored : sliderRow.modelData.fallback
            onMoved: function(v) { sliderRow.shown = v }
            onReleased: function(v) {
              sliderRow.shown = v
              var rounded = sliderRow.modelData.step >= 1 ? Math.round(v) : Math.round(v * 100) / 100
              if (root.svc) root.svc.setRuleEffectOption(root.current, root.currentEffect, sliderRow.modelData.key, rounded)
            }
          }
          Text {
            id: valueText
            anchors.right: parent.right
            anchors.rightMargin: root.trailInset
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(52)
            horizontalAlignment: Text.AlignRight
            text: root.fmt(sliderRow.shown, sliderRow.modelData.step, sliderRow.modelData.unit)
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Repeater {
        model: def ? def.options : []
        delegate: EditorRow {
          id: optionRow
          required property var modelData
          readonly property var stored: root.svc ? root.svc.ruleEffectOption(root.current, root.currentEffect, modelData.key, modelData.fallback) : modelData.fallback
          label: modelData.label
          Loader {
            width: parent.width
            sourceComponent: optionRow.modelData.type === "enum" ? enumOption : textOption
            property var option: optionRow.modelData
            property var stored: optionRow.stored
          }
        }
      }

      Note {
        visible: def && def.rows.length === 0 && def.options.length === 0
        text: "Nothing to set up for this effect."
      }

      Item { width: 1; height: Style.space(4) }
      Item {
        width: parent.width
        height: Style.spacing.controlHeight
        Button {
          anchors.right: parent.right
          anchors.rightMargin: root.trailInset
          anchors.verticalCenter: parent.verticalCenter
          text: "Remove from this rule"
          iconText: "󰅖"
          bordered: true
          focusable: true
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: {
            if (root.svc) root.svc.removeRuleEffect(root.current, root.currentEffect)
            root.back()
          }
        }
      }
      Item { width: 1; height: Style.space(2) }
    }
  }

  Component {
    id: enumOption
    ButtonGroup {
      options: option.values
      value: String(stored === undefined || stored === null ? option.fallback : stored)
      foreground: root.fg
      accent: Color.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onChanged: function(v) {
        if (root.svc) root.svc.setRuleEffectOption(root.current, root.currentEffect, option.key, v === option.fallback ? undefined : v)
      }
    }
  }

  Component {
    id: textOption
    ConfigField {
      width: parent.width - root.trailInset
      placeholderText: option.placeholder || ""
      current: stored === undefined || stored === null ? "" : String(stored)
      commit: function(t) {
        if (root.svc) root.svc.setRuleEffectOption(root.current, root.currentEffect, option.key, t.trim() || undefined)
      }
    }
  }

  // ======================= pieces =======================

  component Section: Column {
    property string title: ""
    width: parent ? parent.width : 200
    spacing: Style.space(10)
    Item { width: 1; height: Style.space(6) }
    PanelSeparator { width: parent.width; foreground: root.fg }
    PanelSectionHeader { text: parent.title; foreground: root.fg; fontFamily: root.fontFamily }
  }

  component Note: Text {
    width: parent ? parent.width - root.trailInset : 200
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
  }

  component RowLabel: Text {
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    width: root.labelW
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  component SwitchRow: Item {
    id: sw
    property string label: ""
    property bool checked: false
    signal toggled()
    width: parent ? parent.width : 200
    height: Style.spacing.controlHeight
    Text {
      anchors.left: parent.left
      anchors.right: swToggle.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: sw.label
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
    ToggleSwitch {
      id: swToggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      cursorPad: root.trailInset
      checked: sw.checked
      foreground: root.fg
      onToggled: sw.toggled()
    }
    MouseArea {
      anchors.fill: parent
      anchors.rightMargin: swToggle.width
      onClicked: sw.toggled()
    }
  }

  // A text field that follows a value but never overwrites what is being
  // typed: it re-reads only while unfocused, commits on Enter or focus loss,
  // Esc puts the old value back, Tab moves on to the next control.
  component ConfigField: TextField {
    id: cf
    property string current: ""
    property var commit: null
    foreground: root.fg
    font.family: root.fontFamily
    onCurrentChanged: if (!activeFocus) text = current
    Component.onCompleted: text = current
    function revert() { text = current }
    onEditingFinished: {
      if (text === current) return
      if (commit) commit(text)
    }
    Keys.onEscapePressed: function(e) { revert(); keyCatcher.forceActiveFocus(); e.accepted = true }
    Keys.onTabPressed: function(e) { var n = cf.nextItemInFocusChain(true); if (n) n.forceActiveFocus(Qt.TabFocusReason); e.accepted = true }
    Keys.onBacktabPressed: function(e) { var n = cf.nextItemInFocusChain(false); if (n) n.forceActiveFocus(Qt.BacktabFocusReason); e.accepted = true }
  }

  // Chips with a text entry after them. Enter or comma adds what was typed,
  // Backspace on an empty entry takes the last chip back, Esc drops the
  // typing, Tab commits and moves on. With `suggestions`, a short list of
  // matches sits under the field: arrows pick, Enter takes the pick, and a
  // name not in the list is still added as typed.
  component ChipField: Column {
    id: chip
    property var values: []
    property string placeholder: ""
    property string emptyText: ""
    property var suggestions: []
    property bool allowRegex: false
    signal committed(var values)
    width: parent ? parent.width : 200
    spacing: Style.space(4)

    property int highlight: 0
    readonly property string query: entry.text.trim()
    readonly property var filtered: {
      if (!suggestions || !suggestions.length || !entry.activeFocus) return []
      var q = query.toLowerCase()
      var out = []
      for (var i = 0; i < suggestions.length; i++) {
        var s = suggestions[i]
        if (values.indexOf(s.name) !== -1) continue
        if (q && String(s.name).toLowerCase().indexOf(q) === -1) continue
        out.push(s)
        if (out.length >= 6) break
      }
      return out
    }
    onFilteredChanged: if (highlight >= filtered.length) highlight = 0

    function add(text) {
      var t = String(text || "").trim()
      if (t.length && values.indexOf(t) === -1) {
        var next = values.slice()
        next.push(t)
        chip.committed(next)
      }
      entry.text = ""
    }
    function removeAt(i) {
      var next = values.slice()
      next.splice(i, 1)
      chip.committed(next)
    }
    // Enter takes the highlighted suggestion, unless what was typed is
    // already exactly one of them, in which case it is taken as typed.
    function accept() {
      var exact = false
      for (var i = 0; i < filtered.length; i++)
        if (String(filtered[i].name).toLowerCase() === query.toLowerCase()) exact = true
      if (filtered.length && !exact && highlight >= 0 && highlight < filtered.length) return add(filtered[highlight].name)
      add(entry.text)
    }

    Rectangle {
      id: box
      width: parent.width - root.trailInset
      height: flow.implicitHeight + Style.space(8)
      color: "transparent"
      radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(6)) : 0
      border.width: Math.max(1, Style.normalBorderWidth)
      border.color: entry.activeFocus ? Color.accent : Util.alpha(root.fg, 0.3)

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: entry.forceActiveFocus()
      }

      Flow {
        id: flow
        anchors.fill: parent
        anchors.margins: Style.space(4)
        spacing: Style.space(4)

        Repeater {
          model: chip.values
          delegate: Rectangle {
            id: tag
            required property var modelData
            required property int index
            height: Style.space(22)
            width: tagText.implicitWidth + tagClose.width + Style.space(14)
            radius: height / 2
            color: Util.alpha(root.fg, 0.12)
            Text {
              id: tagText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: String(tag.modelData)
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              id: tagClose
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(14)
              horizontalAlignment: Text.AlignHCenter
              text: "󰅖"
              color: closeArea.containsMouse ? Color.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              MouseArea {
                id: closeArea
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: chip.removeAt(tag.index)
              }
            }
          }
        }

        TextInput {
          id: entry
          width: Math.min(flow.width, Math.max(Style.space(230), implicitWidth + Style.space(12)))
          height: Style.space(22)
          activeFocusOnTab: true
          verticalAlignment: TextInput.AlignVCenter
          leftPadding: Style.space(4)
          color: root.fg
          selectionColor: Util.alpha(Color.accent, 0.4)
          selectedTextColor: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          clip: true
          Text {
            anchors.fill: parent
            anchors.leftMargin: parent.leftPadding
            verticalAlignment: Text.AlignVCenter
            visible: !entry.text.length
            text: chip.values.length ? chip.placeholder : (chip.emptyText || chip.placeholder)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          onActiveFocusChanged: if (!activeFocus && text.trim().length) chip.add(text)
          Keys.onPressed: function(e) {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { chip.accept(); e.accepted = true; return }
            if (e.key === Qt.Key_Comma && !(chip.allowRegex && text.trim().charAt(0) === "/")) { chip.add(text); e.accepted = true; return }
            if (e.key === Qt.Key_Backspace && text.length === 0 && chip.values.length) { chip.removeAt(chip.values.length - 1); e.accepted = true; return }
            if (e.key === Qt.Key_Down && chip.filtered.length) { chip.highlight = (chip.highlight + 1) % chip.filtered.length; e.accepted = true; return }
            if (e.key === Qt.Key_Up && chip.filtered.length) { chip.highlight = (chip.highlight - 1 + chip.filtered.length) % chip.filtered.length; e.accepted = true; return }
            if (e.key === Qt.Key_Escape) { text = ""; keyCatcher.forceActiveFocus(); e.accepted = true; return }
            if (e.key === Qt.Key_Tab) { if (text.trim().length) chip.add(text); var n = entry.nextItemInFocusChain(true); if (n) n.forceActiveFocus(Qt.TabFocusReason); e.accepted = true; return }
            if (e.key === Qt.Key_Backtab) { var p = entry.nextItemInFocusChain(false); if (p) p.forceActiveFocus(Qt.BacktabFocusReason); e.accepted = true; return }
          }
        }
      }
    }

    Rectangle {
      visible: chip.filtered.length > 0
      width: parent.width - root.trailInset
      height: suggestionCol.implicitHeight + Style.space(6)
      color: Color.popups.background
      radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(6)) : 0
      border.width: Math.max(1, Style.normalBorderWidth)
      border.color: Util.alpha(root.fg, 0.2)
      Column {
        id: suggestionCol
        anchors.fill: parent
        anchors.margins: Style.space(3)
        Repeater {
          model: chip.filtered
          delegate: Rectangle {
            id: srow
            required property var modelData
            required property int index
            width: suggestionCol.width
            height: Style.space(26)
            radius: Style.space(4)
            color: (srow.index === chip.highlight || srowArea.containsMouse) ? Util.alpha(root.fg, 0.08) : "transparent"
            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: srcText.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: String(srow.modelData.name)
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Text {
              id: srcText
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: srow.modelData.source === "notified" ? "seen in notifications" : (srow.modelData.source === "running" ? "running" : "installed")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              id: srowArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { chip.add(srow.modelData.name); entry.forceActiveFocus() }
            }
          }
        }
      }
    }
  }

  // One effect on the rule: name, its settings in a line, open and remove.
  component EffectLine: Rectangle {
    id: line
    property string type: ""
    readonly property var def: Catalog.find(type)
    height: Style.space(34)
    radius: Style.space(6)
    color: lineArea.containsMouse ? Util.alpha(root.fg, 0.08) : Util.alpha(root.fg, 0.04)

    function summary() {
      if (!def || !root.svc) return ""
      var parts = []
      for (var i = 0; i < def.rows.length && parts.length < 3; i++) {
        var r = def.rows[i]
        parts.push(root.fmt(root.svc.ruleEffectOption(root.current, line.type, r.key, r.fallback), r.step, r.unit))
      }
      return parts.join(" · ")
    }

    MouseArea {
      id: lineArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openEffect(line.type)
    }
    Text {
      id: lineIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: line.def && line.def.icon ? line.def.icon : "󰄬"
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      width: Style.space(18)
    }
    Text {
      id: lineName
      anchors.left: lineIcon.right
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: line.def ? line.def.label : line.type
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
    }
    Text {
      anchors.left: lineName.right
      anchors.leftMargin: Style.space(10)
      anchors.right: openButton.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: line.summary()
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
    PanelActionButton {
      id: openButton
      anchors.right: removeButton.left
      anchors.rightMargin: Style.space(2)
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰒓"
      tooltipText: "Set up"
      focusable: true
      foreground: root.fg
      fontFamily: root.fontFamily
      onClicked: root.openEffect(line.type)
    }
    PanelActionButton {
      id: removeButton
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅖"
      tooltipText: "Remove from this rule"
      focusable: true
      foreground: root.fg
      hoverColor: Color.urgent
      fontFamily: root.fontFamily
      onClicked: if (root.svc) root.svc.removeRuleEffect(root.current, line.type)
    }
  }

  component EditorRow: Item {
    property string label: ""
    default property alias content: slot.data
    width: parent ? parent.width : 200
    height: Math.max(slot.childrenRect.height, Style.spacing.controlHeight)
    RowLabel { anchors.left: parent.left; text: parent.label }
    Item {
      id: slot
      anchors.left: parent.left
      anchors.leftMargin: root.labelW
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: childrenRect.height
    }
  }
}
