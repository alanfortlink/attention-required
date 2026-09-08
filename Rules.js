// Rule parsing and matching. Pure functions, no QML, so the whole thing can
// be exercised from a terminal: `qmltestrunner` is not needed, `node` is
// enough (see tests/rules.test.js).
// Not a .pragma library: the shell caches those across plugin reloads.

var DEFAULT_COOLDOWN = 3
var DEFAULT_FIELDS = ["summary", "body"]
var DEFAULT_EFFECTS = [{ type: "nudge" }]

function str(v) {
  return v === undefined || v === null ? "" : String(v)
}

function list(v) {
  if (Array.isArray(v)) return v.map(str).filter(function(x) { return x.length > 0 })
  if (typeof v === "string" && v.length) return [v]
  return []
}

// Notification bodies arrive as markup ("<a href=...>deliveroo.co.uk</a>").
// Matching is done on the words a person would read, not the tags.
function stripTags(s) {
  return str(s)
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim()
}

// A word is a case-insensitive substring. Written as /.../ it is a regular
// expression instead, case-insensitive unless flags are given.
function compileWord(w) {
  var m = /^\/(.+)\/([a-z]*)$/.exec(w)
  if (m) {
    var flags = m[2] || "i"
    try {
      return { regex: new RegExp(m[1], flags), source: w }
    } catch (e) {
      return { text: w.toLowerCase(), source: w, error: String(e) }
    }
  }
  return { text: w.toLowerCase(), source: w }
}

function normalizeEffect(e) {
  if (typeof e === "string") {
    var name = e.trim().toLowerCase()
    return name ? { type: name } : null
  }
  if (e && typeof e === "object" && e.type) {
    var out = {}
    for (var k in e) out[k] = e[k]
    out.type = str(e.type).trim().toLowerCase()
    return out.type ? out : null
  }
  return null
}

// No `effects` key at all means the nudge; an explicit empty list means
// the rule matches but nothing happens (a rule still being set up).
function normalizeEffects(raw) {
  if (raw === undefined || raw === null) return DEFAULT_EFFECTS.map(function(d) { return { type: d.type } })
  var items = Array.isArray(raw) ? raw : [raw]
  var out = []
  for (var i = 0; i < items.length; i++) {
    var e = normalizeEffect(items[i])
    if (e) out.push(e)
  }
  return out
}

function normalizeRule(raw, index) {
  if (!raw || typeof raw !== "object") return null
  var fields = list(raw.fields).map(function(f) { return f.toLowerCase() })
  var cooldown = Number(raw.cooldown)
  return {
    name: str(raw.name).trim() || ("rule-" + (index + 1)),
    enabled: raw.enabled !== false,
    words: list(raw.words).map(compileWord),
    match: str(raw.match).toLowerCase() === "all" ? "all" : "any",
    apps: list(raw.apps).map(function(a) { return a.toLowerCase() }),
    fields: fields.length ? fields : DEFAULT_FIELDS.slice(),
    effects: normalizeEffects(raw.effects),
    cooldown: isFinite(cooldown) && cooldown >= 0 ? cooldown : DEFAULT_COOLDOWN
  }
}

// Top-level "defaults": options applied to every effect of that type unless
// the rule's own effect sets them. {"defaults": {"nudge": {"intensity": 10}}}
function normalizeDefaults(raw) {
  var out = {}
  if (!raw || typeof raw !== "object") return out
  for (var type in raw) {
    var opts = raw[type]
    if (!opts || typeof opts !== "object") continue
    var copy = {}
    for (var k in opts) if (k !== "type") copy[k] = opts[k]
    out[String(type).trim().toLowerCase()] = copy
  }
  return out
}

// The effect as it will run: the defaults for its type under the options set
// on the rule.
function withDefaults(cfg, effect) {
  if (!effect || !effect.type) return effect
  var base = cfg && cfg.defaults ? cfg.defaults[effect.type] : null
  if (!base) return effect
  var out = {}
  for (var d in base) out[d] = base[d]
  for (var k in effect) out[k] = effect[k]
  return out
}

function normalizeConfig(raw) {
  var cfg = { whileDnd: true, letThrough: true, defaults: {}, rules: [] }
  if (!raw || typeof raw !== "object") return cfg
  cfg.whileDnd = raw.whileDnd !== false
  // While silenced, a notification a rule matched is posted again so its
  // toast shows: silence everything, let the rules through.
  cfg.letThrough = raw.letThrough !== false
  cfg.defaults = normalizeDefaults(raw.defaults)
  var rules = Array.isArray(raw.rules) ? raw.rules : []
  for (var i = 0; i < rules.length; i++) {
    var r = normalizeRule(rules[i], i)
    if (r) cfg.rules.push(r)
  }
  return cfg
}

function textFor(rule, n) {
  var parts = []
  for (var i = 0; i < rule.fields.length; i++) {
    var f = rule.fields[i]
    if (f === "summary" || f === "title") parts.push(str(n.summary))
    else if (f === "body") parts.push(stripTags(n.body))
    else if (f === "app") parts.push(str(n.app))
  }
  return parts.join("\n")
}

function appMatches(rule, app) {
  if (!rule.apps.length) return true
  var a = str(app).toLowerCase()
  for (var i = 0; i < rule.apps.length; i++)
    if (a.indexOf(rule.apps[i]) !== -1) return true
  return false
}

function wordMatches(w, text, lower) {
  return w.regex ? w.regex.test(text) : lower.indexOf(w.text) !== -1
}

// Empty means anything: no words matches every notification (from the apps
// given, or from every app when those are empty too).
function ruleMatches(rule, n) {
  if (!rule.enabled) return false
  if (!appMatches(rule, n.app)) return false
  if (!rule.words.length) return true
  var text = textFor(rule, n)
  var lower = text.toLowerCase()
  for (var i = 0; i < rule.words.length; i++) {
    var hit = wordMatches(rule.words[i], text, lower)
    if (hit && rule.match === "any") return true
    if (!hit && rule.match === "all") return false
  }
  return rule.match === "all"
}

function matchingRules(cfg, n) {
  var out = []
  for (var i = 0; i < cfg.rules.length; i++)
    if (ruleMatches(cfg.rules[i], n)) out.push(cfg.rules[i])
  return out
}

// What `state` and `rules` report over IPC: the compiled rule without the
// RegExp objects, which do not survive JSON.stringify.
function describeRule(rule) {
  return {
    name: rule.name,
    enabled: rule.enabled,
    words: rule.words.map(function(w) { return w.source }),
    match: rule.match,
    apps: rule.apps,
    fields: rule.fields,
    effects: rule.effects,
    cooldown: rule.cooldown
  }
}

// "{summary}" style templates for effects that show text. An empty template
// is the summary.
function renderTemplate(tpl, notif, rule) {
  var t = str(tpl).trim()
  if (!t) t = "{summary}"
  var map = {
    app: str(notif ? notif.app : ""),
    summary: str(notif ? notif.summary : ""),
    body: stripTags(notif ? notif.body : ""),
    rule: str(rule ? rule.name : "")
  }
  return t.replace(/\{(app|summary|body|rule)\}/g, function(m, k) { return map[k] })
}
