#!/usr/bin/env bash
# Verifies that the repeat setting reaches the player, including when a saved
# legacy speed value is present alongside it.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
log=$(mktemp)
trap 'rm -f -- "$log"' EXIT

pw-play() { printf '%s\n' "$*" >> "$AR_SOUND_LOG"; }
export -f pw-play

# Every UI choice must reach a different system sound through ar-effect.
sounds=(message bell warning complete phone)
files=(message-new-instant.oga bell.oga dialog-warning.oga complete.oga phone-incoming-call.oga)
for i in "${!sounds[@]}"; do
  : > "$log"
  payload="{\"effect\":{\"type\":\"sound\",\"sound\":\"${sounds[i]}\",\"repeat\":1,\"duration\":0},\"notification\":{},\"rule\":{\"name\":\"test\"}}"
  AR_SOUND_LOG="$log" bash "$repo/bin/ar-effect" sound "$payload"
  grep -Fqx -- "--volume=1 /usr/share/sounds/freedesktop/stereo/${files[i]}" "$log"
done

# An explicit repeat count wins over a saved legacy speed value.
: > "$log"
payload='{"effect":{"type":"sound","sound":"phone","repeat":3,"speed":1,"duration":0},"notification":{},"rule":{"name":"test"}}'
AR_SOUND_LOG="$log" bash "$repo/bin/ar-effect" sound "$payload"

[[ $(wc -l < "$log") -eq 3 ]]
[[ $(grep -Fxc -- "--volume=1 /usr/share/sounds/freedesktop/stereo/phone-incoming-call.oga" "$log") -eq 3 ]]

# Each repeat is separately tempo-adjusted when a duration is selected.
ffprobe() { printf '1\n'; }
ffmpeg() {
  printf 'ffmpeg %s\n' "$*" >> "$AR_SOUND_LOG"
  printf 'wav'
}
pw-play() {
  cat >/dev/null
  printf 'pw-play %s\n' "$*" >> "$AR_SOUND_LOG"
}
export -f ffprobe ffmpeg pw-play
: > "$log"
AR_OPT_SOUND=bell \
AR_OPT_DURATION=1 \
AR_OPT_REPEAT=3 \
AR_SOUND_LOG="$log" \
bash "$repo/effects/sound"

[[ $(grep -Fc -- 'ffmpeg -nostdin -v error -i /usr/share/sounds/freedesktop/stereo/bell.oga -filter:a atempo=2,atempo=1.50000000 -f wav -' "$log") -eq 3 ]]
[[ $(grep -Fxc -- 'pw-play --volume=1 -' "$log") -eq 3 ]]

# A longer target duration slows each repetition by the corresponding factor.
: > "$log"
AR_OPT_SOUND=warning \
AR_OPT_DURATION=4 \
AR_OPT_REPEAT=1 \
AR_SOUND_LOG="$log" \
bash "$repo/effects/sound"

grep -Fq -- '-filter:a atempo=0.5,atempo=0.50000000 -f wav -' "$log"
grep -Fqx -- 'pw-play --volume=1 -' "$log"

echo "sound: all tests passed"
