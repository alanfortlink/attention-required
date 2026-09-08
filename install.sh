#!/bin/bash
# Install the Attention Required plugin for the current user.
#   ./install.sh              link the plugin into ~/.config/omarchy/plugins (when run from a checkout elsewhere),
#                             put the `attention-required` CLI on PATH, enable the service
#   ./install.sh --uninstall
# `omarchy plugin add <git-url> --enable` alone is enough for normal use; this script only adds conveniences.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ID=alanfortlink.attention-required
PLUGIN=$HOME/.config/omarchy/plugins/$ID
BIN=$HOME/.local/bin
MODE=${1:-}

if [[ $MODE == --uninstall ]]; then
  omarchy plugin disable "$ID" >/dev/null 2>&1 || true
  rm -f "$BIN/attention-required"
  [[ -L $PLUGIN ]] && rm -f "$PLUGIN"
  echo "uninstalled (your rules in ~/.config/attention-required were left alone)"
  echo "If the plugin was added with 'omarchy plugin add', also run: omarchy plugin remove $ID"
  exit 0
fi

missing=()
for c in jq hyprctl; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if ((${#missing[@]})); then
  echo "error: missing commands: ${missing[*]}" >&2
  exit 1
fi
if ! command -v inotifywait >/dev/null 2>&1; then
  echo "note: inotifywait (inotify-tools) is not installed; notifications will be polled twice a second instead. 'omarchy pkg add inotify-tools' fixes that." >&2
fi

mkdir -p "$BIN" "$(dirname "$PLUGIN")"
chmod +x "$HERE"/bin/* "$HERE"/effects/*
ln -sfn "$HERE/bin/attention-required" "$BIN/attention-required"

if [[ $HERE != "$PLUGIN" ]]; then
  if [[ -e $PLUGIN && ! -L $PLUGIN ]]; then
    echo "error: $PLUGIN exists and is not a symlink; remove it first (omarchy plugin remove $ID)" >&2
    exit 1
  fi
  ln -sfn "$HERE" "$PLUGIN"
fi

case ":$PATH:" in *":$BIN:"*) ;; *) echo "note: $BIN is not on your PATH; run the CLI as $BIN/attention-required" >&2 ;; esac

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
# A plugin with both a service and a bar widget is enabled by its bar entry
# alone; the bell goes next to the notification-silencing indicator.
omarchy bar put "$ID" --after omarchy.indicators >/dev/null 2>&1 \
  || omarchy plugin enable "$ID" --section center >/dev/null 2>&1 \
  || omarchy plugin enable "$ID" >/dev/null 2>&1 || true
echo "installed. Rules: ~/.config/attention-required/rules.json (a deliveroo rule is there to start)."
echo "The bell in the bar pauses and resumes the effects. Try one: attention-required test nudge"
