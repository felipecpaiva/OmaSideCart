# Bug: the watcher kills any wayvnc on the machine, not just its own

Found 2026-09-18 while setting up LAN remote access to the X1C
(workspace `docs/remote-access-x1c.md` step 6).

## Symptom

With the tablet unplugged and `sidecar-display.service` running, a wayvnc started by
hand for anything else dies about a second after it starts:

```
$ ssh -L 5900:127.0.0.1:5900 x1c 'XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 wayvnc 127.0.0.1 5900'
Warning: ../wayvnc/src/ctl-server.c: 837: Deleting stale control socket path "/run/user/1000/wayvncctl"
✘ 255
```

Exit 255 from ssh, exit 143 from wayvnc itself, so SIGTERM. The debug log shows wayvnc
starts cleanly and reaches `Listening for connections on 127.0.0.1:5900` before it is
killed, which sends you looking at Hyprland, DPMS and the lock screen. None of those
are involved.

## Cause

`bin/sidecar-display` identifies "its" wayvnc by process name only.

```bash
streaming() { pgrep -x wayvnc >/dev/null; }    # line 60
```

```bash
down() {
  ...
  pkill -x wayvnc 2>/dev/null                  # line 198
}
```

The unplugged branch of `watch()` reads:

```bash
else
  # Not ready is not the same as nothing to tear down: a half up sidecar still
  # owns an output and a wayvnc.
  if has_out || streaming; then down; fi       # line 250
```

So with no tablet plugged in, any wayvnc anywhere on the machine reads as a half-up
sidecar, and the watcher tears it down on its next pass (at most 2 seconds).

The comment on line 249 is the giveaway: it assumes a running wayvnc can only be one
the sidecar started. Nothing enforces that.

## Suggested fix

Own the process by PID instead of by name. The start site is line 86.

1. On start, record the PID:
   `setsid wayvnc ... & echo $! > "$STATE/wayvnc.pid"`
2. `streaming()` checks that recorded PID is alive and is still wayvnc,
   rather than `pgrep -x wayvnc`.
3. `down()` kills that PID, and clears the file.

A stale PID file must read as not streaming, so a reboot or a crashed wayvnc does not
wedge the watcher. `pgrep -x wayvnc -F "$STATE/wayvnc.pid"` covers the "alive and still
wayvnc" test in one call, and returns non-zero on a missing or stale file.

A weaker alternative is to match on the port instead of the PID, but it breaks the
moment anything else picks the same port, and the sidecar's port is configurable.

## Workaround until fixed

Stop the watcher while using remote desktop, and start it again afterwards:

```bash
systemctl --user stop sidecar-display.service
# ... use wayvnc ...
systemctl --user start sidecar-display.service
```

Starting the service again with a foreign wayvnc running will kill it, which is the bug.

## Knock-on for the remote-access runbook

`docs/remote-access-x1c.md` step 6 cannot work on this machine while the sidecar service
is running. Either fix this bug, or the runbook needs the stop/start above written into
step 6 for the X1C.
