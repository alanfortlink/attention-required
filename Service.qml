import QtQuick
import Quickshell
import Quickshell.Io
import "Rules.js" as Rules

// Headless service: streams every notification the shell puts on screen,
// runs it past the rules in ~/.config/attention-required/rules.json, and
// fires the effects of the rules that match.
//
// Notifications are read from the files Omarchy's notification service
// writes (one JSON per popup under ~/.local/state/omarchy/notifications/),
// which is the same contract the notification-center plugin relies on. It
// means no second notification daemon and no D-Bus eavesdropping.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/attention-required"
  readonly property string rulesPath: configDir + "/rules.json"

  property var config: Rules.normalizeConfig(null)
  property string configError: ""
  property bool configLoaded: false

  // notification key -> { ruleName: true }. A popup file is written again
  // when its sender updates it (Chromium fills the body in late), so the same
  // notification is evaluated more than once but a rule fires once per key.
  property var fired: ({})
  property var firedKeys: []
  property var lastFired: ({})   // rule name -> ms of last firing
  property var recent: []        // last matches, newest first
  property int seen: 0
  property int matched: 0

  // Paused or armed. Kept as a flag file so it survives a shell restart, the
  // way the notification service keeps Do Not Disturb.
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/attention-required"
  readonly property string pausedFile: stateDir + "/paused"
  property bool enabled: true

  function setEnabled(value) {
    var on = value === true || value === "true" || value === "on" || value === "1"
    root.enabled = on
    Quickshell.execDetached(["bash", "-c",
      "mkdir -p \"$1\"; if [ \"$2\" = on ]; then rm -f \"$3\"; else touch \"$3\"; fi", "--",
      root.stateDir, on ? "on" : "off", root.pausedFile])
    root.log(on ? "armed" : "paused")
  }

  Process {
    id: readPaused
    command: ["test", "-e", root.pausedFile]
    running: true
    onExited: function(code) { root.enabled = code !== 0 }
  }

  function log(msg) { console.log("[attention-required] " + msg) }

  // Effects the shell draws itself. Everything else is a script in effects/.
  Flash { id: flash }
  Banner { id: banner }
  Airplane { id: airplane }
  Confetti { id: confetti }
  Blink { id: blink }
  FrameTicker { id: ticker }
  readonly property var overlays: ({ flash: flash, banner: banner, airplane: airplane, confetti: confetti, blink: blink })

  // ---------------------------------------------------------------- config

  Process {
    id: ensureConfig
    command: ["bash", "-c",
      "mkdir -p \"$1/effects\"; [ -e \"$2\" ] || cp \"$3\" \"$2\"", "--",
      root.configDir, root.rulesPath, root.pluginDir + "/rules.example.json"]
    running: true
    onExited: rulesFile.reload()
  }

  FileView {
    id: rulesFile
    path: root.rulesPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
    onLoadFailed: function(error) {
      root.configError = "cannot read " + root.rulesPath
    }
  }

  // A save is often seen twice: once truncated, once complete. The first read
  // fails to parse; rather than trust a second change event to arrive, read
  // again shortly after. A file that is really broken just logs once more.
  Timer {
    id: rereadConfig
    interval: 400
    onTriggered: rulesFile.reload()
  }

  function applyConfig(text) {
    var raw
    try {
      raw = JSON.parse(text)
    } catch (e) {
      var wasError = root.configError !== ""
      root.configError = "rules.json is not valid JSON: " + e.message
      if (!wasError) rereadConfig.restart()
      root.log(root.configError)
      return
    }
    root.configError = ""
    // A write of ours is on its way to disk: what is in memory is newer than
    // what was just read, so keep it.
    if (saveTimer.running) return
    root.rawConfig = raw
    root.config = Rules.normalizeConfig(raw)
    root.configLoaded = true
    root.log("loaded " + root.config.rules.length + " rule(s) from " + root.rulesPath)
  }

  // ---------------------------------------------------------------- editing
  //
  // The settings popup edits rules.json through these. rawConfig is the file
  // as parsed, unknown fields included, so nothing a person wrote by hand is
  // lost; every change replaces it (a fresh object, so bindings notice) and
  // writes it back shortly after.

  property var rawConfig: ({ version: 1, rules: [] })
  readonly property var rawRules: Array.isArray(rawConfig.rules) ? rawConfig.rules : []

  function cloneConfig() {
    var c = JSON.parse(JSON.stringify(rawConfig || {}))
    if (typeof c !== "object" || c === null || Array.isArray(c)) c = {}
    if (!c.version) c.version = 1
    if (!Array.isArray(c.rules)) c.rules = []
    return c
  }

  function commitConfig(next) {
    root.rawConfig = next
    root.config = Rules.normalizeConfig(next)
    root.configError = ""
    saveTimer.restart()
  }

  function saveConfig() {
    Quickshell.execDetached(["bash", "-c",
      "mkdir -p \"$(dirname \"$2\")\" && printf '%s\\n' \"$1\" > \"$2\"", "--",
      JSON.stringify(root.rawConfig, null, 2), root.rulesPath])
  }

  Timer {
    id: saveTimer
    interval: 300
    onTriggered: root.saveConfig()
  }

  function setWhileDnd(value) {
    var c = cloneConfig()
    c.whileDnd = !!value
    commitConfig(c)
  }

  function setLetThrough(value) {
    var c = cloneConfig()
    c.letThrough = !!value
    commitConfig(c)
  }

  function defaultFor(type, key, fallback) {
    var d = rawConfig && rawConfig.defaults ? rawConfig.defaults[type] : null
    var v = d ? d[key] : undefined
    return v === undefined || v === null || !isFinite(Number(v)) ? fallback : Number(v)
  }

  function setDefault(type, key, value) {
    var c = cloneConfig()
    if (!c.defaults || typeof c.defaults !== "object" || Array.isArray(c.defaults)) c.defaults = {}
    if (!c.defaults[type] || typeof c.defaults[type] !== "object") c.defaults[type] = {}
    c.defaults[type][key] = value
    commitConfig(c)
  }

  function updateRule(index, patch) {
    var c = cloneConfig()
    if (!c.rules[index] || typeof c.rules[index] !== "object") return false
    for (var k in patch) {
      if (patch[k] === undefined) delete c.rules[index][k]
      else c.rules[index][k] = patch[k]
    }
    commitConfig(c)
    return true
  }

  function addRule() {
    var c = cloneConfig()
    var n = c.rules.length + 1
    var name = "rule-" + n
    while (c.rules.some(function(r) { return r && r.name === name })) name = "rule-" + (++n)
    // No effects yet: the rule is set up in the popup, effect by effect.
    c.rules.push({ name: name, words: [], apps: [], effects: [], cooldown: 3 })
    commitConfig(c)
    return c.rules.length - 1
  }

  // ---- a rule's effects, each with its own options ----

  function effectTypeOf(e) {
    return typeof e === "string" ? e.trim().toLowerCase() : (e && e.type ? String(e.type).trim().toLowerCase() : "")
  }

  function ruleEffectList(index) {
    var rule = rawRules[index]
    if (!rule) return []
    var raw = rule.effects
    if (raw === undefined || raw === null) return ["nudge"]
    return Array.isArray(raw) ? raw : [raw]
  }

  function ruleHasEffect(index, type) {
    var list = ruleEffectList(index)
    for (var i = 0; i < list.length; i++) if (effectTypeOf(list[i]) === type) return true
    return false
  }

  function addRuleEffect(index, type) {
    if (ruleHasEffect(index, type)) return
    var list = ruleEffectList(index).slice()
    list.push(String(type))
    updateRule(index, { effects: list })
  }

  function removeRuleEffect(index, type) {
    var list = ruleEffectList(index).filter(function(e) { return effectTypeOf(e) !== type })
    updateRule(index, { effects: list })
  }

  // The option as it will run: set on the rule's effect, else the top-level
  // defaults for that effect, else what the caller falls back to.
  function ruleEffectOption(index, type, key, fallback) {
    var list = ruleEffectList(index)
    for (var i = 0; i < list.length; i++) {
      var e = list[i]
      if (effectTypeOf(e) !== type) continue
      if (e && typeof e === "object" && e[key] !== undefined && e[key] !== null) return e[key]
    }
    var d = rawConfig && rawConfig.defaults ? rawConfig.defaults[type] : null
    if (d && d[key] !== undefined && d[key] !== null) return d[key]
    return fallback
  }

  function setRuleEffectOption(index, type, key, value) {
    var list = ruleEffectList(index).slice()
    var found = false
    for (var i = 0; i < list.length; i++) {
      if (effectTypeOf(list[i]) !== type) continue
      var obj = typeof list[i] === "object" && list[i] ? JSON.parse(JSON.stringify(list[i])) : { type: type }
      obj.type = type
      if (value === undefined || value === null || value === "") delete obj[key]
      else obj[key] = value
      // Back to the short form when nothing but the type is left.
      var keys = Object.keys(obj)
      list[i] = keys.length === 1 ? type : obj
      found = true
    }
    if (!found) {
      var fresh = { type: type }
      if (value !== undefined && value !== null && value !== "") fresh[key] = value
      list.push(Object.keys(fresh).length === 1 ? type : fresh)
    }
    updateRule(index, { effects: list })
  }

  function tryRuleEffect(index, type) {
    var rule = root.config.rules[index]
    if (!rule) return
    var notif = { key: "test", source: "test", app: "attention-required", summary: "Test of " + rule.name, body: "A notification matched the rule “" + rule.name + "”.", urgency: 1 }
    for (var i = 0; i < rule.effects.length; i++)
      if (rule.effects[i].type === type) runEffect(rule.effects[i], notif, rule)
  }

  function removeRule(index) {
    var c = cloneConfig()
    if (index < 0 || index >= c.rules.length) return false
    c.rules.splice(index, 1)
    commitConfig(c)
    return true
  }

  // ------------------------------------------------------------ app names
  //
  // Suggestions for a rule's apps, best first: names that actually arrived
  // on notifications (that is the string a rule is matched against), then
  // the apps running right now, then everything installed.

  property var notifiedApps: ({})     // app name -> count
  property var runningApps: []
  property var appSuggestions: []

  function noteApp(app) {
    var name = Rules.str(app).trim()
    if (!name || name === "notify-send" || name === "omarchy-action") return
    var next = {}
    for (var k in notifiedApps) next[k] = notifiedApps[k]
    next[name] = (next[name] || 0) + 1
    notifiedApps = next
    rebuildAppSuggestions()
  }

  function entryName(desktopId) {
    try {
      var entry = DesktopEntries.heuristicLookup(desktopId)
      if (entry && entry.name) return String(entry.name)
    } catch (e) {
    }
    return ""
  }

  function rebuildAppSuggestions() {
    var seen = {}
    var out = []
    function add(name, source) {
      var key = String(name || "").trim()
      if (!key || seen[key.toLowerCase()]) return
      seen[key.toLowerCase()] = true
      out.push({ name: key, source: source })
    }
    var notified = Object.keys(notifiedApps).sort(function(a, b) { return notifiedApps[b] - notifiedApps[a] })
    for (var i = 0; i < notified.length; i++) add(notified[i], "notified")
    for (var r = 0; r < runningApps.length; r++) add(runningApps[r], "running")
    try {
      var apps = DesktopEntries.applications.values
      for (var a = 0; a < apps.length; a++) {
        if (apps[a].noDisplay) continue
        add(apps[a].name, "installed")
      }
    } catch (e) {
    }
    appSuggestions = out
  }

  // Runs when the settings open: the running windows and the notifications
  // already on disk.
  function refreshApps() {
    if (!appsProc.running) appsProc.running = true
  }

  Process {
    id: appsProc
    command: ["bash", "-c",
      "hyprctl -j clients 2>/dev/null | jq -r '.[].class' | sort -u | sed 's/^/class\\t/';" +
      "d=\"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/notifications\";" +
      "cat \"$d\"/*.json \"$d\"/history/*.json 2>/dev/null | jq -r '.app // empty' | sort -u | sed 's/^/app\\t/'"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.split("\n")
        var running = []
        var notified = {}
        for (var k in root.notifiedApps) notified[k] = root.notifiedApps[k]
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length < 2) continue
          var value = parts.slice(1).join("\t").trim()
          if (!value) continue
          if (parts[0] === "class") {
            var name = root.entryName(value)
            if (!name) {
              // A Chromium web app ("chrome-web.whatsapp.com__-Default") sends
              // its notifications under the browser's name, so that is the
              // name worth suggesting.
              var pwa = /^(chrome|chromium|brave|msedge)-(.+?)__-/.exec(value)
              if (pwa) {
                var browsers = { chrome: "google-chrome", chromium: "chromium", brave: "brave-browser", msedge: "microsoft-edge" }
                name = root.entryName(browsers[pwa[1]]) || pwa[2]
              } else {
                name = value
              }
            }
            if (running.indexOf(name) === -1) running.push(name)
          } else if (parts[0] === "app") {
            if (value === "notify-send" || value === "omarchy-action") continue
            if (!notified[value]) notified[value] = 1
          }
        }
        root.runningApps = running
        root.notifiedApps = notified
        root.rebuildAppSuggestions()
      }
    }
  }

  Component.onCompleted: refreshApps()

  // Runs a rule's effects as if it had matched, for the settings popup.
  function tryRule(index) {
    var rule = root.config.rules[index]
    if (!rule) return
    var notif = { key: "test", source: "test", app: "attention-required", summary: "Test of " + rule.name, body: "A notification matched the rule “" + rule.name + "”.", urgency: 1 }
    for (var i = 0; i < rule.effects.length; i++) runEffect(rule.effects[i], notif, rule)
  }

  function testNotification(type) {
    return { key: "test", source: "test", app: "attention-required", summary: "Attention required",
             body: "This is what the " + String(type) + " effect looks like.", urgency: 1 }
  }

  function tryEffect(type) {
    runEffect({ type: String(type) }, testNotification(type), { name: "test" })
  }

  // --------------------------------------------------------------- watching

  Process {
    id: watchProc
    command: [root.pluginDir + "/bin/ar-watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.absorb(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { root.log("watch: " + line) }
    }
    onExited: function(code) { root.log("watcher exited with " + code) }
  }

  // A watcher that died, or never started (the script missing for a moment
  // while the plugin is updated), is brought back. Quickshell fires no
  // `exited` for a process that failed to start, so this polls rather than
  // reacting.
  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: if (!watchProc.running) watchProc.running = true
  }

  function absorb(line) {
    var n
    try {
      n = JSON.parse(line)
    } catch (e) {
      return
    }
    if (!n || !n.key) return
    // A toast we posted ourselves to get a silenced match through: not a
    // new notification, so it must not run the rules again.
    if (root.isRepost(n)) return
    root.seen++
    if (!root.enabled) return
    if (n.source === "silenced" && !root.config.whileDnd) return

    var notif = {
      key: String(n.key),
      source: String(n.source || "popup"),
      app: Rules.str(n.app),
      summary: Rules.str(n.summary),
      body: Rules.str(n.body),
      urgency: n.urgency === undefined ? 1 : n.urgency
    }
    root.noteApp(notif.app)
    var rules = Rules.matchingRules(root.config, notif)
    if (!rules.length) return

    var now = Date.now()
    var already = root.fired[notif.key] || {}
    var isNew = !root.fired[notif.key]
    for (var i = 0; i < rules.length; i++) {
      var rule = rules[i]
      if (already[rule.name]) continue
      already[rule.name] = true
      var last = root.lastFired[rule.name] || 0
      if (rule.cooldown > 0 && now - last < rule.cooldown * 1000) {
        root.log("rule '" + rule.name + "' matched but is cooling down")
        continue
      }
      root.lastFired[rule.name] = now
      root.trigger(rule, notif)
      if (notif.source === "silenced" && root.config.letThrough) root.repost(n)
    }
    root.fired[notif.key] = already
    if (isNew) {
      root.firedKeys.push(notif.key)
      while (root.firedKeys.length > 200) delete root.fired[root.firedKeys.shift()]
    }
  }

  // ------------------------------------------------- letting matches through
  //
  // Do Not Disturb hides every toast. A notification a rule matched is the
  // one you asked to see, so it is posted again the one way the shell shows
  // while silenced: as a critical notification from notify-send. The copy is
  // remembered so its own arrival is not taken for a new notification.

  property var reposted: ({})   // "summary\nbody" -> ms it was posted

  function repostKey(n) {
    return Rules.str(n.summary) + "\n" + Rules.str(n.body)
  }

  function isRepost(n) {
    if (Rules.str(n.app) !== "notify-send" || Number(n.urgency) !== 2) return false
    var stamp = root.reposted[repostKey(n)]
    return !!stamp && Date.now() - stamp < 20000
  }

  function repost(n) {
    var key = repostKey(n)
    if (root.reposted[key] && Date.now() - root.reposted[key] < 5000) return
    root.reposted[key] = Date.now()
    var command = ["notify-send", "-u", "critical", "-t", "8000"]
    var icon = Rules.str(n.appIcon).replace(/^file:\/\//, "")
    if (icon.charAt(0) === "/") command.push("-i", icon)
    var summary = Rules.str(n.summary) || Rules.str(n.app) || "Attention required"
    command.push("--", summary, Rules.str(n.body))
    Quickshell.execDetached(command)
    root.log("let through while silenced: " + summary)
  }

  function trigger(rule, notif) {
    root.matched++
    root.log("rule '" + rule.name + "' matched " + notif.app + ": " + notif.summary)
    var entry = { time: Date.now(), rule: rule.name, app: notif.app, summary: notif.summary }
    root.recent = [entry].concat(root.recent).slice(0, 20)
    for (var i = 0; i < rule.effects.length; i++)
      root.runEffect(rule.effects[i], notif, rule)
  }

  // -------------------------------------------------------------- effects

  // `flash` is drawn by the shell itself (Flash.qml). Everything else is a
  // script: ~/.config/attention-required/effects/<type> if you wrote one,
  // otherwise effects/<type> shipped with the plugin.
  function runEffect(effect, notif, rule) {
    var type = String(effect.type || "")
    if (!type) return
    effect = Rules.withDefaults(root.config, effect)
    if (root.overlays[type]) {
      root.overlays[type].trigger(effect, notif, rule)
      return
    }
    // The shake is a time-driven screen shader; keep frames coming while it runs.
    if (type === "nudge") ticker.run(Number(effect.duration) > 0 ? Number(effect.duration) : 1)
    var payload = {
      effect: effect,
      notification: {
        key: notif.key, app: notif.app, summary: notif.summary,
        body: Rules.stripTags(notif.body), urgency: notif.urgency
      },
      rule: { name: rule.name }
    }
    Quickshell.execDetached([root.pluginDir + "/bin/ar-effect", type, JSON.stringify(payload)])
  }

  function parseEffect(spec) {
    var text = String(spec || "").trim()
    if (!text) return null
    if (text.charAt(0) === "{") {
      try {
        return Rules.normalizeEffect(JSON.parse(text))
      } catch (e) {
        return null
      }
    }
    return Rules.normalizeEffect(text)
  }

  // ------------------------------------------------------------------- ipc

  IpcHandler {
    target: "attention-required"

    // attention-required test nudge
    // attention-required test '{"type":"flash","color":"#ff0000"}'
    function test(effect: string): string {
      var e = root.parseEffect(effect)
      if (!e) return "unknown effect: " + effect
      root.runEffect(e, root.testNotification(e.type), { name: "test" })
      return "ran " + e.type
    }

    // Runs a made-up notification past the rules, effects included.
    function simulate(app: string, summary: string, body: string): string {
      var key = "simulated-" + Date.now()
      var notif = { key: key, app: app, summary: summary, body: body }
      var names = Rules.matchingRules(root.config, notif).map(function(r) { return r.name })
      root.absorb(JSON.stringify({ key: key, source: "popup", app: app, summary: summary, body: body, urgency: 1 }))
      if (!names.length) return "no rule matched"
      return "matched: " + names.join(", ") + (root.enabled ? "" : " (paused, nothing ran)")
    }

    function reload(): string {
      rulesFile.reload()
      return "reloading " + root.rulesPath
    }

    // attention-required toggle | on | off
    function toggle(): string {
      root.setEnabled(!root.enabled)
      return root.enabled ? "armed" : "paused"
    }

    function setEnabled(value: string): string {
      root.setEnabled(value)
      return root.enabled ? "armed" : "paused"
    }

    function isEnabled(): string {
      return root.enabled ? "true" : "false"
    }

    // attention-required set nudge intensity 6
    function setDefault(type: string, key: string, value: string): string {
      var t = String(type).trim().toLowerCase(), k = String(key).trim()
      if (!t || !k) return "usage: set <effect> <option> <value>"
      var n = Number(value)
      root.setDefault(t, k, isFinite(n) && String(value).trim() !== "" ? n : String(value))
      return t + "." + k + " = " + String(value)
    }

    function rules(): string {
      return JSON.stringify({
        path: root.rulesPath,
        error: root.configError,
        whileDnd: root.config.whileDnd,
        defaults: root.config.defaults,
        rules: root.config.rules.map(Rules.describeRule)
      })
    }

    function state(): string {
      return JSON.stringify({
        enabled: root.enabled,
        rulesPath: root.rulesPath,
        configLoaded: root.configLoaded,
        configError: root.configError,
        rules: root.config.rules.length,
        watching: watchProc.running,
        seen: root.seen,
        matched: root.matched,
        recent: root.recent,
        appSuggestions: root.appSuggestions.length,
        topApps: root.appSuggestions.slice(0, 8).map(function(s) { return s.name + " (" + s.source + ")" })
      })
    }

    function ping(): string { return "ok" }
  }
}
