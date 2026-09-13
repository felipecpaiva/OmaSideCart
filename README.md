# OmaSideCart

Use an Android tablet as a real second monitor on Hyprland, over the USB cable, with
nothing to click. Plug the cable in and the screen appears. Pull it out and your windows
come home. Plug it back in and they go back.

Built and tested on Omarchy (Arch + Hyprland 0.56.2) with a Galaxy Tab S11 Ultra.

## Why this exists

Plenty of tools can put a Linux desktop on a tablet. All of them need a human to start it:
a bar click, a tap in an app, a QR scan, a browser tab. None of them notice the cable.

OmaSideCart is the missing trigger, plus the plumbing that makes the result a genuine
second desktop rather than a mirror of your laptop screen.

## What you get

- **A real extra output, not a mirror.** Windows live on it and can be dragged across.
- **Its own set of desktops.** The laptop keeps 1 to 5, the tablet gets 6 to 10.
- **Nothing is ever stranded.** Unplug and the tablet's desktops walk back to the laptop
  with their windows and layout intact. Plug back in and they walk back.
- **Nothing on the network.** The stream goes down the USB cable through an `adb` tunnel,
  and the VNC server listens on loopback only. No firewall holes, no Wi-Fi, no USB
  tethering.
- **Touch works.** Touching the tablet moves the Linux cursor.

## Requirements

**On the laptop**

| | |
|---|---|
| Hyprland | 0.56 or newer. It needs `hyprctl output create headless`. |
| Packages | `wayvnc`, `jq`, `adb` (in `android-tools`), `flock` (in `util-linux`) |
| Session | systemd **user** services, and a graphical session |

On Arch, `wayvnc jq android-tools` are all in the official repos.

**On the tablet**

| | |
|---|---|
| Android | any version with USB debugging |
| App | a VNC client. [AVNC](https://github.com/gujjwal00/avnc) is free software and handles the `vnc://` deep link this uses, so the viewer opens by itself. |
| Cable | a data cable. A charge-only cable will not work. |

## Install

There are two halves, and you can take one or both.

- **The service** is the part that does the work. Nothing on the bar is required.
- **The bar widget** is optional. It shows whether the tablet is streaming and toggles it.

### The service


```sh
git clone https://github.com/felipecpaiva/OmaSideCart.git
cd OmaSideCart
./install.sh
```

That copies `bin/sidecar-display` into `~/.local/bin` and the unit into
`~/.config/systemd/user`. It enables nothing and configures nothing.

### The bar widget (optional)

```sh
omarchy plugin add https://github.com/felipecpaiva/OmaSideCart.git --enable
omarchy-restart-shell
```

![The widget on the bar](preview.png)

The icon is **hidden** when no tablet is plugged in, **dim** when one is connected but not
streaming, and **bright** while it streams. Clicking it starts or stops the stream.

It reads `sidecar-display state`, so it needs the service installed above. Remove it with
`omarchy plugin remove io.github.felipecpaiva.omasidecart`.

## Set up, step by step

### 1. Turn on USB debugging on the tablet

Settings → About tablet → Software information → tap **Build number** seven times → back
→ Developer options → **USB debugging** → on.

Plug the cable in. The tablet shows a dialog asking to trust this computer. Accept it and
tick "always allow".

### 2. Find your two values

```sh
adb devices                      # the first column is your serial, e.g. R5XT0AB1CDE
hyprctl monitors | grep Monitor  # your built-in screen, usually eDP-1
```

If `adb devices` is empty, USB debugging is not on yet, or the trust dialog on the tablet
was never accepted.

### 3. Write the config

Copy `config.example` to `~/.config/sidecar-display/config` and fill it in:

```sh
SIDECAR_SERIAL=R5XT0AB1CDE        # required, from `adb devices`
SIDECAR_LAPTOP=eDP-1              # your built-in screen
SIDECAR_MODE=2960x1848@60         # your tablet's native resolution
SIDECAR_SCALE=2                   # 2 suits a high-density tablet, 1 a low-density one
SIDECAR_WS_SET="6 7 8 9 10"       # desktops that belong to the tablet
SIDECAR_LAPTOP_WS_SET="1 2 3 4 5" # desktops pinned to the laptop
SIDECAR_FPS=60                    # see the note on frame rate below
SIDECAR_VIEWER=com.gaurav.avnc    # the tablet app, restarted to force a reconnect
SIDECAR_AUDIO=1                   # 0 leaves the tablet speakers out of it entirely
SIDECAR_AUDIO_PORT=5901
SIDECAR_AUDIO_BUFFER_MS=250       # see Sound, this is what lines audio up with the picture
SIDECAR_AUDIO_PLAYER=com.kaytat.simpleprotocolplayer
```

`adb` has to be reachable. If it is not on `PATH` for systemd user services, give its full
path with `ADB=/usr/bin/adb`.

### 4. Check it before trusting it

```sh
sidecar-display selfcheck
```

Twelve assertions covering the output, the stream, the tunnel, and a full unplug and
replug cycle. Each one has been mutation tested, so a pass means something.

### 5. Turn it on

```sh
systemctl --user enable --now sidecar-display.service
```

### 6. Two settings on the tablet

In AVNC:

- **Settings → Input → Mouse → Hide local pointer: on**
- **Settings → Input → Mouse → Hide remote pointer: on**

`wayvnc` runs with `--render-cursor`, so the real cursor is already painted into the
picture. Left on, AVNC draws its own pointers on top, which sit in a corner until you
touch the screen and then trail your finger around.

If the screen dims after a while, that is the tablet and not this. AVNC's **Keep screen
ON** is already on by default, so it is not a timeout. It is adaptive brightness reacting
to a mostly dark desktop. Turn adaptive brightness off in the tablet's display settings.

## Use

| Key | What it does |
|-----|--------------|
| `SUPER + SHIFT + 7` | send the focused window to tablet desktop 7 |
| `SUPER + 7` | look at tablet desktop 7 |

Think of the tablet's desktops as a box. Whatever you put in the box shows on the tablet.
Unplug and the box comes back to the laptop, still reachable with `SUPER + 6` through
`SUPER + 0`. Plug in and it goes back out.

```sh
sidecar-display status      # plugged, output, stream, tunnel, desktops
sidecar-display selfcheck   # the twelve assertions, needs the tablet
./test-reconcile.sh         # does it recover on its own? all faked, safe anywhere
sidecar-display up          # do it by hand
sidecar-display down
```

## How it works

1. A systemd user service watches `/sys/bus/usb/devices/*/serial` for your tablet. Matching
   the serial rather than an interface name means any USB port works.
2. While it is plugged in, every couple of seconds the watcher compares what should be
   true against what is actually true, and closes the gap. It creates a headless Hyprland
   output, sizes it to the tablet, and splits the desktops between the screens with
   `hl.workspace_rule`. Hyprland owns the rest: it moves those desktops off when the output
   goes and back when it returns. Nothing is remembered as done, so a step that failed
   because Hyprland or adb was not up yet is simply retried on the next pass.
3. `wayvnc` captures that output on `127.0.0.1`, and `adb reverse` tunnels the port down the
   cable, so the tablet reaches it at `vnc://127.0.0.1:5900`.
4. On disconnect it stops the server, closes the tunnel, and removes the output.

There is no state file. The compositor is the only thing that remembers where a desktop
lives, so there is nothing that can drift out of step with it. The watcher remembers nothing
either, which is why booting with the cable already in behaves the same as plugging it in.

## Sound

The tablet's speakers are usually better than a laptop's, so the tablet can be an output
device as well as a screen. It shows up in the desktop's output list as **Sidecar**, next
to your speakers, and you pick it the same way you would pick a monitor's speakers.

It needs one app installed on the tablet: [Simple Protocol
Player](https://github.com/kaytat/SimpleProtocolPlayer), which plays uncompressed PCM off a
socket. Android will not act as a USB speaker on its own without root, so something has to
receive the audio. Install it and nothing else: the watcher starts it, points it at the
stream and stops it again, all without bringing it to the front, so the tablet carries on
showing your desktop while it plays.

How it fits together. A null sink named `sidecar` collects whatever the desktop sends to
it. `module-simple-protocol-tcp` serves that sink's monitor as raw PCM on loopback only,
and a second `adb reverse` tunnel carries it down the same cable as the picture. Raw PCM
costs 1.5 Mbps, which is nothing beside the 82 Mbps the screen uses, so there is no codec
and no encoding delay to pay for.

Three things are less obvious than they look.

- **Audio arrives early, so it is deliberately held back.** The picture goes through
  capture, encode, a socket and a decode; sound goes almost straight down the wire. Left
  alone the sound runs ahead of the video. `SIDECAR_AUDIO_BUFFER_MS` delays the audio to
  meet it, and 250ms is what matched here. Raise it if sound still leads, lower it if sound
  now lags. This is the only dial worth touching.
- **The server is reloaded before the player is started.** The player opens a new socket
  and abandons the old one without closing it, and every socket left behind quietly fills
  with audio nobody reads. Reloading is the only end of that we control.
- **Unplugging hands the desktop back before the sink disappears.** Remove the output while
  it is still the chosen one and the desktop is left pointing at a device that no longer
  exists, which is silence everywhere with nothing visibly wrong.

## When something is wrong

| What you see | What it is |
|---|---|
| "Disconnected, server is not running" on the tablet | The adb tunnel dropped, which happens when the adb server restarts. The watcher re-asserts it every two seconds, so give it a moment. `sidecar-display status` shows whether the tunnel is open. |
| `adb devices` empty with the cable in | USB debugging is off, or the trust dialog was never accepted. A charge-only cable does this too. |
| Nothing happens on plug-in | `systemctl --user status sidecar-display.service`. It is a **user** unit and needs the graphical session, so it will not work as a system unit. |
| A second pointer in the corner | AVNC's own pointers. See step 6. |
| The screen dims | Adaptive brightness on the tablet. See step 6. |
| Closing the lid blanks the laptop screen | Omarchy counts a virtual output as an external monitor. Upstream fix pending. Unplug before closing the lid. |
| The bar shows the other screen's desktops | An Omarchy bug, not this. Fixed by any of omarchy PRs [#8435](https://github.com/omacom/omarchy/pull/8435), [#10639](https://github.com/omacom/omarchy/pull/10639), [#7243](https://github.com/omacom/omarchy/pull/7243), [#10190](https://github.com/omacom/omarchy/pull/10190), none merged yet. |

## Things worth knowing

- **Every frame is a full frame.** A headless output reports 100% damage on every frame, so
  VNC's usual trick of sending only what changed buys nothing here. The cost is simply
  resolution times frame rate. Measured on an Intel Iris Xe under constant full-screen
  change:

  | Output | Pixels/frame | wayvnc CPU |
  |---|---|---|
  | 2960x1848 @ 60fps | 5.47 Mpx | 71% of one core |
  | 2960x1848 @ 30fps | 5.47 Mpx | 55% of one core |
  | 1480x924 @ 60fps | 1.36 Mpx | 19% of one core |

  A **still** screen costs nothing at all: zero frames, zero CPU. Only motion is expensive.
  Halving the resolution is the biggest lever left, at the cost of the tablet upscaling,
  which looks noticeably soft.
- **The frame cap should be 60, and going past it is not worth it.** What you see is
  governed by the content: a 30fps video looks like 30fps whatever the cap is set to, which
  is what made an earlier reading of "30 is free" look true when it was only true of the
  clip being watched at the time. Measured on a 1080p60 video played full screen:

  | Cap | Load | Throughput | wayvnc CPU |
  |---|---|---|---|
  | 60 | video | 82 Mbps | 22% of one core |
  | 120 | video | 102 Mbps | 62% of one core |
  | 120 | scrolling and dragging | 83 Mbps | 71% of one core |

  Hyprland will happily give a headless output 120Hz, and the tablet panel is 120Hz, so the
  ceiling is real rather than imposed. It is still not worth taking. Tripling the CPU bought
  24% more data and nothing anyone could see, because above the content's own frame rate
  most of the work is rescanning frames that did not change. On a thin laptop that is
  sustained heat for no gain.
- **`wayvnc --gpu` does nothing here.** wayvnc can do H.264 and is linked for it, but the
  *client* picks the encoding and AVNC negotiates `tight` (JPEG on the CPU). A server flag
  cannot override a client that never asks.
- **The USB link is usually not the bottleneck.** Measured 121 Mbps against roughly 300
  Mbps of practical USB 2 capacity. Check before blaming the cable:
  `ss -tinp | grep -A1 'users:(("wayvnc"'` and sample `bytes_sent` twice.
- **Sunshine and Moonlight do not work for this**, which is a shame, because they do have
  hardware encoding. Sunshine finds a Hyprland headless output and selects it correctly,
  then fails to read its pixels (`EGL_BAD_MATCH`), because a virtual output has no GPU
  buffer to hand over. Upstream closed that as not planned
  ([#4197](https://github.com/LizardByte/Sunshine/issues/4197),
  [#2955](https://github.com/LizardByte/Sunshine/issues/2955)). `grim` and `wayvnc` work on
  the same output because they read through shared memory instead.
- **USB tethering is deliberately unused.** Android drops it on every replug, which makes
  anything built on it fail silently.
- **The service does the work, the widget only reports it.** Removing the widget changes
  nothing about how the second screen behaves.

## Uninstall

```sh
./uninstall.sh
```

Stops and disables the service and removes both installed files. It leaves
`~/.config/sidecar-display/config` alone, so delete that yourself if you want it gone.

## Licence

MIT. See [LICENSE](LICENSE).
