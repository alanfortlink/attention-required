// node tests/rules.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "Rules.js"), "utf8").replace(/\/\/ Not a .pragma library[^\n]*/, "")
const R = {}
new Function("exports", src + "\n" + ["normalizeConfig", "matchingRules", "stripTags", "describeRule", "normalizeEffect", "withDefaults", "renderTemplate", "commandSenderTrusted"].map(n => `exports.${n} = ${n}`).join("\n"))(R)
const catalogSrc = fs.readFileSync(path.join(__dirname, "..", "EffectCatalog.js"), "utf8")
const C = {}
new Function("exports", catalogSrc + "\nexports.effects = EFFECTS")(C)
const settingsSrc = fs.readFileSync(path.join(__dirname, "..", "Settings.qml"), "utf8")
const serviceSrc = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
const watchSrc = fs.readFileSync(path.join(__dirname, "..", "bin", "ar-watch"), "utf8")
const commandSrc = fs.readFileSync(path.join(__dirname, "..", "effects", "command"), "utf8")

const cfg = R.normalizeConfig({
  rules: [
    { name: "deliveroo", words: ["deliveroo"] },
    { name: "boss", words: ["urgent", "asap"], apps: ["Slack"], effects: ["flash", { type: "nudge", duration: 2 }] },
    { name: "both", words: ["build", "failed"], match: "all" },
    { name: "re", words: ["/order #\\d+/"] },
    { name: "chrome-all", apps: ["chrome"] },
    { name: "everything", enabled: false },
    { name: "off", words: ["deliveroo"], enabled: false },
    { name: "app-field", words: ["telegram"], fields: ["app"] }
  ]
})

const names = n => R.matchingRules(cfg, n).map(r => r.name)

// The real one: Chrome, brand only in the body as a link.
assert.deepStrictEqual(names({ app: "Google Chrome", summary: "Your rider has arrived ✅", body: '<a href="https://deliveroo.co.uk/">deliveroo.co.uk</a>\n\nMeet your rider.' }), ["deliveroo", "chrome-all"])
assert.deepStrictEqual(names({ app: "Slack", summary: "URGENT: prod", body: "" }), ["boss"])
assert.deepStrictEqual(names({ app: "Discord", summary: "urgent", body: "" }), [])
assert.deepStrictEqual(names({ app: "CI", summary: "build failed", body: "" }), ["both"])
assert.deepStrictEqual(names({ app: "CI", summary: "build passed", body: "" }), [])
assert.deepStrictEqual(names({ app: "Mail", summary: "Order #1234 shipped", body: "" }), ["re"])
assert.deepStrictEqual(names({ app: "Telegram Desktop", summary: "hi", body: "" }), ["app-field"])
assert.deepStrictEqual(names({ app: "Mail", summary: "Deliveroo", body: "" }), ["deliveroo"])

assert.strictEqual(R.stripTags("<b>a</b>&amp;<img src=x>b"), "a & b")
assert.deepStrictEqual(cfg.rules[1].effects, [{ type: "flash" }, { type: "nudge", duration: 2 }])
assert.deepStrictEqual(cfg.rules[0].effects, [{ type: "nudge" }])
assert.strictEqual(cfg.rules[0].cooldown, 3)
assert.strictEqual(R.normalizeConfig({ rules: [{ name: "x", words: "one" }] }).rules[0].words[0].text, "one")
assert.deepStrictEqual(R.normalizeConfig(null).rules, [])
assert.ok(JSON.stringify(R.describeRule(cfg.rules[3])).includes("order #"))

const withD = R.normalizeConfig({ defaults: { Nudge: { intensity: 12, speed: 20 }, flash: { color: "urgent" } }, rules: [] })
assert.deepStrictEqual(R.withDefaults(withD, { type: "nudge", speed: 5 }), { type: "nudge", intensity: 12, speed: 5 })
assert.deepStrictEqual(R.withDefaults(withD, { type: "flash" }), { type: "flash", color: "urgent" })
assert.deepStrictEqual(R.withDefaults(withD, { type: "sound" }), { type: "sound" })
assert.deepStrictEqual(R.normalizeConfig({ defaults: "nope" }).defaults, {})

assert.strictEqual(R.normalizeConfig({}).whileDnd, true)
assert.strictEqual(R.normalizeConfig({ whileDnd: false }).whileDnd, false)
assert.strictEqual(R.normalizeConfig({}).letThrough, true)
assert.strictEqual(R.normalizeConfig({ letThrough: false }).letThrough, false)

const all = R.normalizeConfig({ rules: [{ name: "all" }, { name: "none", effects: [] }] })
assert.deepStrictEqual(R.matchingRules(all, { app: "X", summary: "y", body: "" }).map(r => r.name), ["all", "none"])
assert.deepStrictEqual(all.rules[0].effects, [{ type: "nudge" }])
assert.deepStrictEqual(all.rules[1].effects, [])
assert.strictEqual(R.renderTemplate("", { summary: "Hi", body: "<b>x</b>" }, { name: "r" }), "Hi")
assert.strictEqual(R.renderTemplate("{rule}: {summary} / {body} ({app})", { app: "A", summary: "Hi", body: "<b>x</b>" }, { name: "r" }), "r: Hi / x (A)")
assert.strictEqual(R.commandSenderTrusted({ trustedExecutable: "/usr/bin/app" }, { source: "popup", senderExe: "/usr/bin/app", senderPortal: false }), true)
assert.strictEqual(R.commandSenderTrusted({ trustedExecutable: "/usr/bin/app" }, { source: "popup", senderExe: "/usr/bin/other", senderPortal: false }), false)
assert.strictEqual(R.commandSenderTrusted({ trustedExecutable: "/usr/bin/app" }, { source: "popup", senderExe: "/usr/bin/app", senderPortal: true }), false)
assert.strictEqual(R.commandSenderTrusted({ run: "printf test" }, { source: "test", senderExe: "", senderPortal: false }), true)

const sound = C.effects.find(effect => effect.type === "sound")
assert.ok(sound.rows.some(row => row.key === "duration" && row.min === 0 && row.max === 30 && row.fallback === 0))
assert.ok(sound.rows.some(row => row.key === "repeat" && row.min === 1 && row.max === 50))
assert.strictEqual(sound.options.length, 1)
assert.deepStrictEqual(sound.options[0].values.map(value => value.value), ["message", "bell", "warning", "complete", "phone"])
const command = C.effects.find(effect => effect.type === "command")
assert.ok(command.options.some(option => option.key === "trustedExecutable"))
assert.ok(serviceSrc.includes("Rules.commandSenderTrusted(effect, notif)"))
assert.ok(watchSrc.includes("GetConnectionUnixProcessID"))
assert.ok(watchSrc.includes("senderExe: $senderExe"))
assert.ok(watchSrc.includes("senderPortal: ($senderPortal == \"true\")"))
assert.ok(commandSrc.includes("AR_SENDER_EXE"))
assert.ok(commandSrc.includes("AR_SENDER_PORTAL"))
const effectSrc = fs.readFileSync(path.join(__dirname, "..", "bin", "ar-effect"), "utf8")
assert.ok(effectSrc.includes("export AR_SENDER_EXE"))
assert.ok(effectSrc.includes("export AR_OPT_TRUSTED_EXECUTABLE"))
assert.ok(commandSrc.includes("AR_OPT_TRUSTED_EXECUTABLE"))
assert.ok(settingsSrc.includes("function bindService()"))
assert.ok(settingsSrc.includes("running: root.svc === null"))
assert.ok(settingsSrc.includes("onToggled: hero.toggleAttention()"))

console.log("rules: all tests passed")
