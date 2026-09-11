# OmaSideCart

Use an Android tablet as a real second monitor on Hyprland, over the USB cable, with
nothing to click. Plug the cable in and the screen appears. Pull it out and your windows
come home. Plug it back in and they go back.

Built and tested on Omarchy (Arch + Hyprland 0.56) with a Galaxy Tab S11 Ultra.

## Why this exists

Plenty of tools can put a Linux desktop on a tablet. All of them need a human to start it:
a bar click, a tap in an app, a QR scan, a browser tab. None of them notice the cable.

OmaSideCart is the missing trigger, plus the plumbing that makes it a genuine second
desktop rather than a mirror of your laptop screen.

## What you get

- A real extra output, not a mirror. Windows live on it and can be dragged across.
- Its own set of desktops. Desktops 6 to 9 belong to the tablet by default.
- Unplug and those desktops walk back to the laptop, windows and layout intact, so nothing
  is ever stranded on a screen you cannot see.
- Plug back in and they walk back to the tablet.
- Nothing on the network. The stream goes through the USB cable over an adb tunnel, and
  the VNC server listens on loopback only. No firewall holes, no Wi-Fi, no USB tethering.
- Touch on the tablet moves the Linux cursor.

## Requirements

On the laptop:

- Hyprland 0.56 or newer (it needs `hyprctl output create headless`)
- `wayvnc`, `jq`, `adb`, `flock`, and systemd user services

On the tablet:

- Android, with USB debugging turned on
- A VNC client. [AVNC](https://github.com/gujjwal00/avnc) is free software and handles the
  `vnc://` deep link this uses.

On Arch, the laptop side is `wayvnc jq android-tools` from the official repos.

## Install

```sh
git clone https://github.com/<you>/OmaSideCart.git
cd OmaSideCart
./install.sh
```

That copies `bin/sidecar-display` into `~/.local/bin` and the unit into
`~/.config/systemd/user`. It enables nothing.

## Configure

Find your tablet's USB serial, with the cable plugged in:

```sh
adb devices          # the first column, for example R52Y80JPFFE
```

Find your laptop's output name:

```sh
hyprctl monitors | grep Monitor
```

Put both in `~/.config/sidecar-display/config`:

```sh
SIDECAR_SERIAL=R52Y80JPFFE        # required
SIDECAR_LAPTOP=eDP-1              # your built-in screen
SIDECAR_MODE=2960x1848@60         # your tablet's native resolution
SIDECAR_SCALE=2                   # 2 suits a high-density tablet
SIDECAR_WS_SET="6 7 8 9"          # desktops that belong to the tablet
```

Check it before trusting it:

```sh
sidecar-display selfcheck
```

Twelve assertions covering the output, the stream, the tunnel, and a full unplug and
replug cycle. Then turn it on:

```sh
systemctl --user enable --now sidecar-display.service
```

## Use

| Key | What it does |
|-----|--------------|
| `SUPER + SHIFT + 7` | send the focused window to tablet desktop 7 |
| `SUPER + 7` | look at tablet desktop 7 |

Plug the cable in and desktops 6 to 9 appear on the tablet. Pull it out and they come back
to the laptop, still reachable with `SUPER + 6` through `SUPER + 9`.

`sidecar-display status` shows what is running.

## How it works

1. A systemd user service watches `/sys/bus/usb/devices/*/serial` for your tablet. Matching
   the serial rather than an interface name means any USB port works.
2. On connect it creates a headless Hyprland output, sizes it to the tablet, and declares
   your chosen desktops as belonging to it with `hl.workspace_rule`. Hyprland owns the rest:
   it moves those desktops off when the output goes and back when it returns.
3. `wayvnc` captures that output on `127.0.0.1`, and `adb reverse` tunnels the port down the
   cable, so the tablet reaches it at `vnc://127.0.0.1:5900`.
4. On disconnect it stops the server, closes the tunnel, and removes the output.

## Things worth knowing

- **VNC has no hardware video encoding.** Text, terminals and documents are comfortable.
  Full screen video is heavier. On an Intel Iris Xe, a whole 2960x1848 screen changing ten
  times a second costs about 23% of one core.
- **Sunshine and Moonlight do not work for this.** Sunshine finds a Hyprland headless output
  and selects it, then fails to read its pixels (`EGL_BAD_MATCH`), because a virtual output
  has no GPU buffer to hand over. Upstream closed that as not planned
  ([#4197](https://github.com/LizardByte/Sunshine/issues/4197),
  [#2955](https://github.com/LizardByte/Sunshine/issues/2955)). `grim` and `wayvnc` work
  because they read through shared memory instead.
- **USB tethering is not used and not needed.** It does not survive a replug on Android.
- **Omarchy's lid handling counts a virtual output as an external monitor.** Closing the lid
  while the tablet is connected can therefore blank the laptop panel. An upstream fix is
  pending.

## Licence

MIT. See [LICENSE](LICENSE).
