// Every effect the settings popup knows how to configure, in the order the
// chips are shown. `rows` are sliders (duration / intensity / speed and the
// odd extra), `options` are choices or free text. Scripts in effects/ and
// overlays in the shell read the same keys.
//
// Not a .pragma library: the shell caches those across plugin reloads.

var EFFECTS = [
  {
    type: "nudge", label: "Nudge", icon: "󰕦",
    subtitle: "Shakes the screen, like a phone buzzing",
    rows: [
      { key: "duration", label: "Duration", min: 0.1, max: 30, step: 0.1, fallback: 1, unit: " s" },
      { key: "intensity", label: "Intensity", min: 0.1, max: 100, step: 0.1, fallback: 1.5, unit: "" },
      { key: "speed", label: "Speed", min: 1, max: 1000, step: 1, fallback: 200, unit: " /s" }
    ],
    options: []
  },
  {
    type: "flash", label: "Flash", icon: "󰉁",
    subtitle: "A glow pulses in from the edges of the screen",
    rows: [
      { key: "duration", label: "Duration", min: 0.1, max: 60, step: 0.1, fallback: 1, unit: " s" },
      { key: "intensity", label: "Intensity", min: 0.01, max: 1, step: 0.01, fallback: 0.9, unit: "" },
      { key: "speed", label: "Pulses", min: 0.1, max: 30, step: 0.1, fallback: 3, unit: " /s" },
      { key: "thickness", label: "Thickness", min: 1, max: 2000, step: 1, fallback: 64, unit: " px" }
    ],
    options: [
      { key: "color", label: "Color", type: "enum", fallback: "accent",
        values: [{ value: "accent", label: "Accent" }, { value: "urgent", label: "Urgent" }, { value: "foreground", label: "Text" }] }
    ]
  },
  {
    type: "banner", label: "Banner", icon: "",
    subtitle: "The message drops in as a big card",
    rows: [
      { key: "duration", label: "Stays for", min: 0.1, max: 300, step: 0.1, fallback: 3, unit: " s" },
      { key: "intensity", label: "Size", min: 0.2, max: 6, step: 0.1, fallback: 1, unit: "×" },
      { key: "speed", label: "Slide", min: 0.2, max: 50, step: 0.1, fallback: 4, unit: " /s" }
    ],
    options: [
      { key: "position", label: "Position", type: "enum", fallback: "top",
        values: [{ value: "top", label: "Top" }, { value: "center", label: "Centre" }, { value: "bottom", label: "Bottom" }] },
      { key: "color", label: "Color", type: "enum", fallback: "accent",
        values: [{ value: "accent", label: "Accent" }, { value: "urgent", label: "Urgent" }, { value: "foreground", label: "Text" }] },
      { key: "text", label: "Text", type: "text", fallback: "", placeholder: "empty: {summary} and the body · also {app}, {rule}" }
    ]
  },
  {
    type: "airplane", label: "Airplane", icon: "󰀝",
    subtitle: "A plane tows the message across the screen",
    rows: [
      { key: "duration", label: "Flight", min: 0.5, max: 120, step: 0.1, fallback: 7, unit: " s" },
      { key: "intensity", label: "Size", min: 0.2, max: 10, step: 0.1, fallback: 1, unit: "×" },
      { key: "altitude", label: "Altitude", min: 0, max: 1, step: 0.01, fallback: 0.2, unit: "" }
    ],
    options: [
      { key: "direction", label: "Direction", type: "enum", fallback: "ltr",
        values: [{ value: "ltr", label: "Left to right" }, { value: "rtl", label: "Right to left" }] },
      { key: "text", label: "Text", type: "text", fallback: "", placeholder: "empty: {summary} · also {body}, {app}, {rule}" }
    ]
  },
  {
    type: "confetti", label: "Confetti", icon: "",
    subtitle: "Confetti pops up across the screen",
    rows: [
      { key: "duration", label: "Duration", min: 0.1, max: 60, step: 0.1, fallback: 1, unit: " s" },
      { key: "intensity", label: "Amount", min: 0.05, max: 20, step: 0.05, fallback: 1, unit: "×" },
      { key: "speed", label: "Power", min: 0.1, max: 10, step: 0.1, fallback: 1, unit: "×" }
    ],
    options: [
      { key: "style", label: "Comes from", type: "enum", fallback: "cannons",
        values: [{ value: "cannons", label: "Bottom corners, shot up" }, { value: "burst", label: "The centre, outwards" }, { value: "rain", label: "The top, falling" }] }
    ]
  },
  {
    type: "blink", label: "Blink", icon: "󰌵",
    subtitle: "The screen dims and comes back",
    rows: [
      { key: "duration", label: "Duration", min: 0.1, max: 30, step: 0.1, fallback: 1, unit: " s" },
      { key: "intensity", label: "Darkness", min: 0.01, max: 1, step: 0.01, fallback: 0.6, unit: "" },
      { key: "speed", label: "Blinks", min: 0.2, max: 30, step: 0.1, fallback: 2, unit: " /s" }
    ],
    options: []
  },
  {
    type: "sound", label: "Sound", icon: "󰕾",
    subtitle: "Plays a selected chime; Fit in 0 uses its natural speed",
    rows: [
      { key: "duration", label: "Fit in", min: 0, max: 30, step: 0.1, fallback: 0, unit: " s" },
      { key: "intensity", label: "Volume", min: 0, max: 2, step: 0.01, fallback: 1, unit: "" },
      { key: "repeat", label: "Times", min: 1, max: 50, step: 1, fallback: 1, unit: " ×" }
    ],
    options: [
      { key: "sound", label: "Sound", type: "enum", fallback: "message",
        values: [
          { value: "message", label: "Message" },
          { value: "bell", label: "Bell" },
          { value: "warning", label: "Warning" },
          { value: "complete", label: "Complete" },
          { value: "phone", label: "Phone" }
        ] }
    ]
  },
  {
    type: "focus", label: "Focus app", icon: "",
    subtitle: "Brings the app's window to the front",
    rows: [],
    options: [
      { key: "window", label: "Window", type: "text", fallback: "", placeholder: "empty: the app that sent it · or a window class or title" }
    ]
  },
  {
    type: "command", label: "Command", icon: "󰆍",
    subtitle: "Runs a command of yours",
    rows: [],
    options: [
      { key: "run", label: "Run", type: "text", fallback: "", placeholder: "empty: nothing runs · sees $AR_SUMMARY, $AR_BODY, $AR_APP, $AR_RULE" }
    ]
  }
]

function find(type) {
  for (var i = 0; i < EFFECTS.length; i++) if (EFFECTS[i].type === type) return EFFECTS[i]
  return null
}

function labelFor(type) {
  var e = find(type)
  return e ? e.label : String(type)
}

function fallbackFor(type, key) {
  var e = find(type)
  if (!e) return undefined
  for (var i = 0; i < e.rows.length; i++) if (e.rows[i].key === key) return e.rows[i].fallback
  for (var j = 0; j < e.options.length; j++) if (e.options[j].key === key) return e.options[j].fallback
  return undefined
}
