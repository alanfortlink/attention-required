#!/usr/bin/env bash
#
# A guided tour of every effect, one after the other, driven by real
# notifications. Each step sends a notification whose text matches a
# "<effect>-test" rule if you have one (attention-required add nudge-test
# --words nudge --effects nudge), and otherwise runs the effect directly.
#
#   ./demo.sh            every effect, then the "let through while silenced" trick
#   ./demo.sh nudge banner airplane   only these
#   ./demo.sh --quick    shorter pauses
set -uo pipefail

cli=$(command -v attention-required || echo "$(cd "$(dirname "$0")" && pwd)/bin/attention-required")
quick=0
picked=()
for arg in "$@"; do
  case $arg in
    --quick|-q) quick=1 ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) picked+=("$arg") ;;
  esac
done

"$cli" status >/dev/null 2>&1 || { echo "the attention-required service is not running (is the plugin enabled?)" >&2; exit 1; }

# effect | seconds it takes | what to expect | message sent with it
steps=(
  "nudge|2|the whole screen shakes for a second|Someone wants you. Now."
  "flash|2|a glow pulses in from the edges|Look at the edges of the screen."
  "blink|2|the screen dims and comes back|Lights out, and back."
  "sound|2|a chime plays|That was the chime."
  "banner|4|a big card with the message drops in from the top|Big enough to read from across the room."
  "confetti|5|confetti is shot up from the bottom corners|Something to celebrate."
  "airplane|9|a plane flies across, towing the message on a flag|Towed across the sky, just for you."
  "focus|3|the window of the app that sent it comes to the front|Brings the app to the front (this one from the terminal)."
)

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
pause() { sleep "$( (( quick )) && echo 1 || echo "$1")"; }
countdown() {
  local n=$1
  (( quick )) && n=1
  while (( n > 0 )); do printf '  in %d…\r' "$n"; sleep 1; (( n-- )); done
  printf '            \r'
}
wait_for() {
  local n=$1
  (( quick )) && n=1
  note "waiting ${n}s for it to finish"
  sleep "$n"
}

has_rule_for() {
  "$cli" export 2>/dev/null | jq -e --arg w "$1" '.rules[] | select((.enabled // true) and ((.words // []) | map(ascii_downcase) | index($w)))' >/dev/null 2>&1
}

run_step() {
  local effect=$1 hold=$2 expect=$3 message=$4
  say "Next: $effect"
  note "what to expect: $expect"
  countdown 2
  if has_rule_for "$effect"; then
    note "sending: notify-send \"$effect\" \"$message\""
    notify-send "$effect" "$message"
    note "the rule with the word '$effect' picks it up"
  else
    note "no rule has the word '$effect', so running the effect directly: attention-required test $effect"
    "$cli" test "$effect" >/dev/null
  fi
  wait_for "$hold"
}

wanted() {
  (( ${#picked[@]} == 0 )) && return 0
  local p
  for p in "${picked[@]}"; do [[ $p == "$1" ]] && return 0; done
  return 1
}

say "Attention Required: the tour"
echo "Every step is a plain notification; the rules do the rest. Ctrl+C stops."
pause 2

for step in "${steps[@]}"; do
  IFS='|' read -r effect hold expect message <<<"$step"
  wanted "$effect" && run_step "$effect" "$hold" "$expect" "$message"
done

if (( ${#picked[@]} == 0 )) && has_rule_for deliver; then
  say "Next: silenced, but the rule gets through"
  note "what to expect: one notification stays hidden, the next one shows anyway and runs its effects"
  was=$(omarchy-shell notifications isDnd 2>/dev/null || echo off)
  countdown 2
  note "silencing notifications (the bell in the bar)"
  omarchy-shell notifications setDnd true >/dev/null 2>&1
  pause 1
  note "sending: notify-send \"Silence\" \"nothing to see here\""
  notify-send "Silence" "nothing to see here"
  note "no rule matches it: nothing shows"
  wait_for 3
  note "sending: notify-send \"Rider update\" \"your order will deliver soon\""
  notify-send "Rider update" "your order will deliver soon"
  note "the rule with the word 'deliver' matches: its effects run and the toast is shown anyway"
  wait_for 4
  [[ $was == on ]] || omarchy-shell notifications setDnd false >/dev/null 2>&1
  note "notifications back to how they were (silencing was $was)"
fi

say "That's the tour."
echo "Click the bell in the bar to change any of it: attention-required settings"
