#!/usr/bin/env bash
# Does the watcher recover on its own after a start that half worked?
#
# This is the reboot bug: the cable was already plugged in, one step of up() failed
# because Hyprland or adb was not ready yet, and the old loop recorded the plug as
# handled and never tried again. Only a physical replug brought the screen back.
#
# Everything here is faked. It never touches Hyprland, adb, or the tablet, so it is
# safe to run on the live machine. Run it from the repo root.
set -uo pipefail
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
C=$D/ctl; mkdir -p "$D/bin" "$C" "$D/state" "$D/config/sidecar-display"

cat > "$D/config/sidecar-display/config" <<CFG
SIDECAR_SERIAL=$(for f in /sys/bus/usb/devices/*/serial; do [ -r "$f" ] && cat "$f" && break; done)
ADB=$D/bin/adb
CFG

cat > "$D/bin/hyprctl" <<SH
#!/usr/bin/env bash
[ -e $C/FAIL_HYPR ] && exit 1
case "\$1 \$2" in
  "monitors -j") [ -e $C/OUT_UP ] && echo '[{"name":"sidecar","width":2960}]' || echo '[]' ;;
  "workspaces -j") echo '[]' ;;
  "output create") touch $C/OUT_UP ;;
  "output remove") rm -f $C/OUT_UP ;;
esac
exit 0
SH
cat > "$D/bin/adb" <<SH
#!/usr/bin/env bash
[ -e $C/FAIL_ADB ] && exit 1
case "\$1 \$2" in
  "reverse --list") [ -e $C/TUNNEL ] && echo "host tcp:5900 tcp:5900" ;;
  "reverse --remove") rm -f $C/TUNNEL ;;
  "reverse tcp:5900") touch $C/TUNNEL ;;
  "shell am") echo show >> $C/SHOW_LOG ;;
esac
exit 0
SH
printf '#!/usr/bin/env bash\n[ -e %s/WAYVNC ]\n' "$C" > "$D/bin/pgrep"
printf '#!/usr/bin/env bash\nrm -f %s/WAYVNC\n' "$C" > "$D/bin/pkill"
printf '#!/usr/bin/env bash\ntouch %s/WAYVNC\n' "$C" > "$D/bin/setsid"
printf '#!/usr/bin/env bash\n[ -e %s/VIEWING ] && echo "ESTAB 0 0 127.0.0.1:5900 127.0.0.1:44000"\nexit 0\n' "$C" > "$D/bin/ss"
chmod +x "$D/bin"/*

shows() { [ -e "$C/SHOW_LOG" ] && wc -l < "$C/SHOW_LOG" || echo 0; }
rc=0
ok() { echo "PASS: $1"; }
no() { echo "FAIL: $1"; rc=1; }

export PATH="$D/bin:$PATH" XDG_STATE_HOME="$D/state" XDG_CONFIG_HOME="$D/config"
touch "$C/FAIL_ADB"                 # boot: the cable is in but adb is not up yet
timeout 140 bash "${1:-bin/sidecar-display}" watch >"$C/out" 2>"$C/err" &
pid=$!

sleep 10
[ "$(grep -c 'tunnel did not open' "$C/err")" -gt 1 ] \
  && ok "it keeps retrying a start that failed" || no "it gave up after one try"
[ "$(shows)" -eq 0 ] && ok "it does not poke the tablet before the stream is up" \
  || no "it poked the tablet with nothing to show"

rm -f "$C/FAIL_ADB"                 # adb comes up, the cable never moved
sleep 22
[ -e "$C/WAYVNC" ] && [ -e "$C/TUNNEL" ] && ok "it came up on its own, no replug" \
  || no "still down after adb recovered, a replug would be needed"
n=$(shows)
[ "$n" -ge 1 ] && ok "it pointed the tablet at the stream ($n times)" \
  || no "the stream is up but the tablet was never told"
[ "$n" -le 3 ] && ok "it spaced the attempts out ($n in 22s)" \
  || no "$n attempts in 22s restarts the viewer under itself"

touch "$C/VIEWING"; sleep 13; seen=$(shows)
rm -f "$C/VIEWING"; sleep 24
[ "$(shows)" -eq "$seen" ] && ok "a viewer the user closed is left closed" \
  || no "it dragged the tablet back after the user closed the viewer"

# wayvnc crashing is not the user closing the viewer. The stream comes back under
# the tablet, so it has to be pointed at it again or it sits blank until the cable moves.
before=$(shows)
rm -f "$C/WAYVNC"; sleep 26
[ "$(shows)" -gt "$before" ] && ok "it reconnects the tablet after the stream came back" \
  || no "the stream came back but the tablet was left blank"

kill $pid 2>/dev/null; wait $pid 2>/dev/null
exit $rc
