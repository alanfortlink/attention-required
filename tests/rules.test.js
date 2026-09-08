// node tests/rules.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "Rules.js"), "utf8").replace(/\/\/ Not a .pragma library[^\n]*/, "")
const R = {}
new Function("exports", src + "\n" + ["normalizeConfig", "matchingRules", "stripTags", "describeRule", "normalizeEffect", "withDefaults", "renderTemplate"].map(n => `exports.${n} = ${n}`).join("\n"))(R)

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

console.log("rules: all tests passed")
