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

mkdir -p "$D/sys/dev1"; echo TESTSERIAL > "$D/sys/dev1/serial"
cat > "$D/config/sidecar-display/config" <<CFG
SIDECAR_SERIAL=TESTSERIAL
SIDECAR_SYSFS=$D/sys
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
  "reverse --list") [ -e $C/TUNNEL ] && echo "host tcp:5900 tcp:5900"; [ -e $C/ATUNNEL ] && echo "host tcp:5901 tcp:5901" ;;
  "reverse --remove tcp:5900") rm -f $C/TUNNEL ;;
  "reverse --remove tcp:5901") rm -f $C/ATUNNEL ;;
  "reverse tcp:5900") touch $C/TUNNEL ;;
  "reverse tcp:5901") touch $C/ATUNNEL ;;
  "shell am") case "\$3\$4" in
      start-foreground-service*) case "\$*" in *action.PLAY*) touch $C/APLAYING; echo play >> $C/PLAY_LOG ;; *action.STOP*) rm -f $C/APLAYING ;; esac ;;
      start*) [ "\$3" = start ] && echo show >> $C/SHOW_LOG ;;
    esac ;;
esac
exit 0
SH
printf '#!/usr/bin/env bash\n[ -e %s/WAYVNC ]\n' "$C" > "$D/bin/pgrep"
printf '#!/usr/bin/env bash\nrm -f %s/WAYVNC\n' "$C" > "$D/bin/pkill"
printf '#!/usr/bin/env bash\ntouch %s/WAYVNC\n' "$C" > "$D/bin/setsid"
cat > "$D/bin/ss" <<SH
#!/usr/bin/env bash
case "\$*" in
  *5900*) [ -e $C/VIEWING ] && echo "ESTAB 0 0 127.0.0.1:5900 127.0.0.1:44000" ;;
  *5901*) [ -e $C/APLAYING ] && echo "ESTAB 0 0 127.0.0.1:5901 127.0.0.1:44001" ;;
esac
exit 0
SH
SPK=alsa_output.HiFi__Speaker__sink
cat > "$D/bin/pactl" <<SH
#!/usr/bin/env bash
D=$C
case "\$*" in
  "get-default-sink") cat \$D/DEFAULT 2>/dev/null || echo $SPK ;;
  "set-default-sink "*) echo "\${@: -1}" > \$D/DEFAULT ;;
  "list short sinks") echo "1	$SPK	x"; [ -e \$D/SINK ] && echo "2	sidecar	x" ;;
  "list short modules") [ -e \$D/MOD ] && echo "10	module-simple-protocol-tcp	port=5901"; [ -e \$D/SINK ] && echo "20	module-null-sink	x" ;;
  "load-module module-null-sink"*) touch \$D/SINK ;;
  "load-module module-simple-protocol-tcp"*) touch \$D/MOD ;;
  "unload-module 10") rm -f \$D/MOD ;;
  "unload-module 20") rm -f \$D/SINK ;;
  "-f json list sinks") printf '[{"name":"$SPK","ports":[],"properties":{"priority.session":"600"}}]' ;;
esac
exit 0
SH
chmod +x "$D/bin"/*

shows() { [ -e "$C/SHOW_LOG" ] && wc -l < "$C/SHOW_LOG" || echo 0; }
rc=0
ok() { echo "PASS: $1"; }
no() { echo "FAIL: $1"; rc=1; }

export PATH="$D/bin:$PATH" XDG_STATE_HOME="$D/state" XDG_CONFIG_HOME="$D/config"
touch "$C/FAIL_ADB"                 # boot: the cable is in but adb is not up yet
timeout 170 bash "${1:-bin/sidecar-display}" watch >"$C/out" 2>"$C/err" &
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

# Sound should arrive with the picture, without anyone asking for it.
[ -e "$C/APLAYING" ] && ok "the tablet speakers came up with the screen" \
  || no "the screen came up but the tablet never got sound"
[ -e "$C/SINK" ] && ok "the desktop has a sidecar output to choose" || no "no audio sink was created"

# The nasty one. Unplugging while the tablet IS the chosen output must hand the desktop
# back to a real speaker BEFORE the sink disappears, or there is silence everywhere and
# nothing looks broken.
echo sidecar > "$C/DEFAULT"
rm -rf "$D/sys/dev1"
sleep 8
DEF=$(cat "$C/DEFAULT")
[ "$DEF" != sidecar ] && ok "unplugging handed the desktop back to a real output ($DEF)" \
  || no "unplugged with the tablet still set as the output, so nothing plays anywhere"
[ ! -e "$C/SINK" ] && ok "the sidecar output was removed on unplug" || no "sidecar output left behind"

kill $pid 2>/dev/null; wait $pid 2>/dev/null

# The key you press every day: sound to the tablet, sound back to the laptop.
echo sidecar > "$C/DEFAULT"
bash "${1:-bin/sidecar-display}" audio-toggle >/dev/null 2>&1
[ "$(cat "$C/DEFAULT")" != sidecar ] && ok "the toggle sends sound back to the laptop" \
  || no "the toggle left sound on the tablet"
bash "${1:-bin/sidecar-display}" audio-toggle >/dev/null 2>&1
[ "$(cat "$C/DEFAULT")" = sidecar ] && ok "the toggle sends it to the tablet again" \
  || no "the toggle would not go back to the tablet"

exit $rc
