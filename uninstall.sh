#!/usr/bin/env bash
# Stop the service and remove what install.sh put in place.
# Leaves ~/.config/sidecar-display/config alone: it holds your serial and screen,
# and deleting settings nobody asked about is how a reinstall becomes a setup.
set -uo pipefail

BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/sidecar-display/config"

# Tear the output down before the script that knows how to do it is gone.
if [ -x "$BIN/sidecar-display" ]; then
  "$BIN/sidecar-display" down >/dev/null 2>&1 || true
fi

systemctl --user disable --now sidecar-display.service >/dev/null 2>&1 || true
rm -f "$UNITS/sidecar-display.service"
rm -f "$BIN/sidecar-display"
systemctl --user daemon-reload 2>/dev/null || true

echo "removed:"
echo "  $BIN/sidecar-display"
echo "  $UNITS/sidecar-display.service"

if [ -e "$CONFIG" ]; then
  echo
  echo "kept your settings at $CONFIG"
  echo "delete it yourself if you want them gone."
fi
