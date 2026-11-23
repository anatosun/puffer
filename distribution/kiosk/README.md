# Raspberry Pi kiosk

Each release attaches `puffer-X.Y.Z-raspberry-pi-arm64.img.xz`, a Raspberry Pi OS Lite image (64-bit, trixie) that starts Puffer full screen on the first screen at boot. It runs best on a Raspberry Pi 4, 400 or 5. The same image boots a Raspberry Pi 3 or Zero 2 W, which are slower and have not been tested; on a board with less than 1.5 GB of memory Puffer keeps fewer decoded covers in memory.

## Small screens and touchscreens

- A screen shorter than 600 points and wider than tall, such as an 800 × 480 panel, puts the tabs in a rail at the left and the controls of the player beside the artwork. A screen 900 points wide or more shows the sidebar of the desktop.
- Settings → Experience → Interface size scales text, icons and buttons together, from 80 % to 150 %; on a kiosk, set it with `experience.interfaceSize` (`smallest`, `smaller`, `standard`, `larger`, `large` or `largest`).
- A keyboard opens at the bottom of the screen when a text field is tapped, such as the search. Settings → Experience → On-screen keyboard (`experience.onScreenKeyboard`) turns it off; a USB keyboard works with or without it.
- The pointer hides when a touchscreen is connected at boot; `system.cursor` (`auto`, `show` or `hide`) overrides it.

## Install

1. Write the image to a card with Raspberry Pi Imager ("Use custom") or `xzcat puffer-*.img.xz | sudo dd of=/dev/sdX bs=4M`. Skip the OS customisation of Raspberry Pi Imager: the provisioning file holds those settings.
2. On the boot partition (`bootfs`), copy `puffer.json.example` to `puffer.json` and fill it in.
3. Put the card in the Raspberry Pi and start it.

## The provisioning file

Puffer reads `/boot/firmware/puffer.json` at every start, so a change to the file takes effect at the next boot. A section left out keeps what the kiosk has.

- `subsonic`: `url`, `username`, and `password` or `apiKey`; `localUrl` is an address of the same server on the home network.
- `musicAssistant`: `url` and `token`, a long-lived token that Music Assistant issues.
- `settings`: values of the preferences of Puffer by key, such as `sendspin.enabled` (the Raspberry Pi plays as a speaker of Music Assistant), `sendspin.name` and `ma.stayOnSpeaker`.
- `system`: `hostname`, `timezone`, `wifi` (`ssid`, `password`, `country`, `hidden`), `sshAuthorizedKeys` (turns SSH on for the user `puffer`), `rotation` of the screen in degrees (0, 90, 180 or 270, for HDMI and DSI screens alike, touch input included) and `cursor`, applied at the next boot.

The boot partition is FAT, so every account on the Raspberry Pi can read the file. Puffer keeps its secrets in `~puffer/.local/share/io.github.anatosun.puffer/secrets.json`, readable only by `puffer`, since a kiosk has no keychain to unlock.

## How it runs

- `puffer-setup.service` applies the `system` section when it changed since the last boot, and writes the rotation and the pointer to `/etc/puffer/kiosk.env` at every boot (`setup.py`).
- `puffer-kiosk.service` opens a login session for `puffer` on tty1 and runs Puffer in the Wayland compositor `cage` (`kiosk`). Inside it, `session` turns the screens with `wlr-randr` before it starts Puffer, and the cursor theme `puffer-hidden` (`hidden-cursor.py`) hides the pointer. Puffer restarts three seconds after it stops. Its log is in `journalctl -u puffer-kiosk`.
- PipeWire shares the sound card between the player and the Sendspin speaker.

Any Linux arm64 system with `cage` can run the kiosk the same way: unpack `puffer-X.Y.Z-linux-arm64.tar.gz` and set `PUFFER_CONFIG` to the path of the provisioning file.

## Build the image

On an arm64 Linux host with `parted`, `e2fsprogs` and `xz`:

```sh
sudo distribution/kiosk/build-image.sh puffer-X.Y.Z-linux-arm64.tar.gz puffer-X.Y.Z-raspberry-pi-arm64.img
```

`BASE_IMAGE` names another Raspberry Pi OS Lite arm64 image, as a URL or a path. The release workflow builds the image on a GitHub arm64 runner.
