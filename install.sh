#!/usr/bin/env bash
# Copy the script and the unit into place. Enables nothing, configures nothing.
set -euo pipefail

BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$BIN" "$UNITS"
install -m 755 "$HERE/bin/sidecar-display" "$BIN/sidecar-display"
install -m 644 "$HERE/systemd/sidecar-display.service" "$UNITS/sidecar-display.service"
systemctl --user daemon-reload 2>/dev/null || true

echo "installed:"
echo "  $BIN/sidecar-display"
echo "  $UNITS/sidecar-display.service"
echo
echo "next: write ~/.config/sidecar-display/config (see README), then"
echo "  sidecar-display selfcheck"
echo "  systemctl --user enable --now sidecar-display.service"
