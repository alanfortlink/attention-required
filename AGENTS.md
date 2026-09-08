# Attention Required: guide for agents

This file is for an AI agent (or a script) asked to change how this machine
reacts to notifications, for example "shake the screen and play a sound when
the build fails", "let only messages from my boss through while I am in a
meeting", or "make the deliveroo nudge stronger". Everything below is exact;
nothing needs a GUI.

## Where things are

| What | Where |
|---|---|
| The configuration, the only thing to edit | `~/.config/attention-required/rules.json` |
| Command line | `attention-required` (on PATH after `./install.sh`, else `~/.config/omarchy/plugins/alanfortlink.attention-required/bin/attention-required`) |
| User-written effects | `~/.config/attention-required/effects/<name>` (executable) |
| Machine-readable effect catalog with ranges | `attention-required effects` (JSON) |
| Paused flag | `~/.local/state/attention-required/paused` (exists = paused) |

The file is watched: a saved change is live within a second, no restart. Run
`attention-required status` afterwards and check `configError` is empty.

## The rules file

```json
{
  "version": 1,
  "whileDnd": true,
  "letThrough": true,
  "defaults": { "nudge": { "intensity": 6 } },
  "rules": [
    {
      "name": "deliveries",
      "enabled": true,
      "words": ["deliveroo", "/order #\\d+/"],
      "match": "any",
      "fields": ["summary", "body"],
      "apps": ["Google Chrome"],
      "effects": ["nudge", { "type": "banner", "duration": 6, "position": "center" }],
      "cooldown": 5
    }
  ]
}
```

Top level:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `version` | 1 | required | Only 1 exists. |
| `whileDnd` | bool | true | Rules still fire while notifications are silenced (Do Not Disturb). |
| `letThrough` | bool | true | A notification a rule matched while silenced is posted again so its toast shows. |
| `defaults` | object | {} | Per effect type, options applied to every rule that does not set them: `{"nudge": {"speed": 15}}`. |
| `rules` | array | [] | Evaluated in order; every matching rule fires (no first-match stop). |

A rule:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | `rule-N` | Unique; used by the CLI and in logs. |
| `enabled` | bool | true | `false` keeps the rule without using it. |
| `words` | string[] | [] | Case-insensitive substrings looked for in the notification. A string of the form `/pattern/flags` is a JavaScript regular expression (flags default to `i`). **Empty means every notification.** |
| `match` | `"any"` \| `"all"` | any | One word is enough, or every word must be present. |
| `fields` | string[] | ["summary","body"] | Where words are looked for: `summary` (title), `body` (markup stripped), `app`. |
| `apps` | string[] | [] | Case-insensitive substrings of the sending app's name as it arrives on D-Bus (`"chrome"` matches `Google Chrome`). **Empty means any app.** Web apps in Chromium browsers send under the browser's name. `attention-required status` lists names actually seen (`topApps`). |
| `effects` | (string \| object)[] | `["nudge"]` if the key is absent | What runs, in order. A string is an effect with default options; an object is `{"type": ..., option: value, ...}`. An explicit `[]` matches but does nothing. |
| `cooldown` | number ≥ 0 | 3 | Seconds during which the rule will not fire again. |

Matching: the rule must pass `apps` (if any) and `words` (if any). A rule with
neither matches every notification. Silenced notifications are matched too
unless `whileDnd` is false. A notification updated in place by its sender
(same replaces-id) is re-evaluated but a rule fires once per notification.

## Effects

`attention-required effects` prints the catalog as JSON: for every effect its
`type`, `rows` (numeric options: `key`, `min`, `max`, `step`, `fallback`,
`unit`) and `options` (`type: "enum"` with `values`, or `type: "text"`).
Values outside a range are clamped when the effect runs. Every effect has
`duration`, `intensity` and `speed` where they make sense. Summary:

| type | duration | intensity | speed | other options |
|---|---|---|---|---|
| `nudge` | seconds, 0.1..30 (1) | how far the picture moves, 0.1..100 (1.5) | new positions per second, 1..1000 (200) | |
| `flash` | seconds, 0.1..60 (1) | glow opacity 0.01..1 (0.9) | pulses per second 0.1..30 (3) | `thickness` px 1..2000 (64); `color`: `accent`, `urgent`, `foreground` or any CSS color |
| `banner` | seconds it stays 0.1..300 (3) | size 0.2..6 (1) | slide speed 0.2..50 (4) | `position`: `top`, `center`, `bottom`; `color`; `text` template |
| `airplane` | flight seconds 0.5..120 (7) | size 0.2..10 (1) | | `altitude` 0..1 from the top (0.2); `direction`: `ltr`, `rtl`; `text` template |
| `confetti` | seconds it keeps coming 0.1..60 (1) | amount 0.05..20 (1) | launch power 0.1..10 (1) | `style`: `cannons` (bottom corners, up), `burst` (centre), `rain` (top) |
| `blink` | seconds 0.1..30 (1) | darkness 0.01..1 (0.6) | blinks per second 0.2..30 (2) | |
| `sound` | | volume 0..2 (1) | times played 1..50 (1) | `file`: path to a sound file (default: freedesktop's new-message chime) |
| `focus` | | | | `window`: a window class or title to focus instead of the sending app |
| `command` | | | | `run`: a shell command, run as the user with `AR_APP`, `AR_SUMMARY`, `AR_BODY`, `AR_RULE`, `AR_KEY`, `AR_URGENCY` and every effect option as `AR_OPT_<NAME>` in the environment |

Text templates (`banner`, `airplane`) take `{summary}`, `{body}`, `{app}`,
`{rule}`; empty means the summary (the banner also shows the body then).

Custom effects: an executable at `~/.config/attention-required/effects/<name>`
is used for effect type `<name>`, with the same environment as `command`.
Options given on the effect object arrive as `AR_OPT_<KEY>` (upper-cased).

## Changing things

Prefer the CLI for single changes; edit the file for anything larger.

```bash
attention-required list                                   # table of rules
attention-required export                                 # the file, to stdout
attention-required add NAME --words a,b --apps Slack --effects nudge,flash --cooldown 10 [--all]
attention-required patch NAME '{"effects":[{"type":"banner","duration":10}],"cooldown":0}'   # merge keys into a rule
attention-required remove NAME | enable NAME | disable NAME
attention-required set nudge intensity 6                  # top-level defaults for an effect
attention-required import FILE                            # replace the whole file (old one kept as .bak)
attention-required toggle | on | off                      # pause or resume every effect
```

Editing the file directly: read it, change it, write it back whole and valid.
Keep keys you do not understand; the popup and other tools may have added
them. `jq` is the safe way:

```bash
f=~/.config/attention-required/rules.json
jq '.rules += [{"name":"build","words":["build failed"],"apps":["Ghostty"],"effects":[{"type":"flash","color":"urgent"},"sound"]}]' "$f" > "$f.new" && mv "$f.new" "$f"
```

## Checking the result

```bash
attention-required status          # configError, rules count, what fired last, app names seen
attention-required simulate "Slack" "boss: are you there?" "need the numbers asap"   # runs a made-up notification through the rules, effects included
attention-required test '{"type":"nudge","intensity":6,"speed":15}'                # runs one effect with these options
notify-send -a "Slack" "boss" "asap"   # a real notification (with Do Not Disturb on, use -a: a bare notify-send is dropped by the desktop)
```

`simulate` returns `matched: <rule names>` or `no rule matched`.

## Scenarios

**Build failures get a red flash and a chime, everything else stays quiet**
```bash
attention-required add build --words "build failed,tests failed,error:" --apps Ghostty --effects flash,sound
attention-required patch build '{"effects":[{"type":"flash","color":"urgent","duration":2},"sound"],"cooldown":10}'
```

**Meeting mode: silence everything, let only the boss on Slack through**
```bash
omarchy toggle notification silencing        # Do Not Disturb on (the bell in the bar does the same)
attention-required add boss --words "Alice" --apps Slack --effects banner,focus
```
With `whileDnd` and `letThrough` on (the defaults), Alice's messages fire the
rule, are shown as a toast, and everything else stays hidden.

**Deliveries: nudge harder, show a big card, bring the browser forward**
```bash
attention-required patch deliveries '{"words":["deliveroo","rider","your order"],"apps":["Google Chrome"],"effects":[{"type":"nudge","intensity":6,"speed":15,"duration":1.5},{"type":"banner","position":"center","duration":8},"focus"]}'
```

**Say it out loud with your own effect**
```bash
mkdir -p ~/.config/attention-required/effects
cat > ~/.config/attention-required/effects/speak <<'EOF'
#!/usr/bin/env bash
exec spd-say -- "$AR_SUMMARY"
EOF
chmod +x ~/.config/attention-required/effects/speak
attention-required patch boss '{"effects":["banner","speak"]}'
```

**Pause during a screen share, resume after**
```bash
attention-required off
attention-required on
```

## Limits worth knowing

- Words are matched against the notification's title and body only (add
  `"app"` to `fields` to match the app name too). Bodies have markup stripped.
- The nudge changes two Hyprland options for the duration of the shake and
  restores them. It needs the Lua-configured Hyprland that Omarchy 4 ships.
- Notification fields are clipped (summary 2000, body 8000 characters) before
  matching; bus messages over 256 KB are ignored.
- A `command` effect runs whatever `run` says. Do not write one from untrusted
  input.
