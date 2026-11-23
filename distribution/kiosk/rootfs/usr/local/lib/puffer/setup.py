#!/usr/bin/env python3
"""Applies the "system" section of the provisioning file at boot: host name, time zone, Wi-Fi and SSH keys when the section changed since the last boot, so a boot without changes costs a hash, and at every boot the rotation of the screen and the pointer, which the kiosk session reads from /etc/puffer/kiosk.env. Puffer itself reads the other sections."""

import hashlib
import json
import pathlib
import subprocess
import sys

STATE = pathlib.Path("/var/lib/puffer/system.sha256")
SESSION = pathlib.Path("/etc/puffer/kiosk.env")
ROTATIONS = {0: "normal", 90: "90", 180: "180", 270: "270"}
CURSORS = ("auto", "show", "hide")


def run(*args):
    subprocess.run(args, check=True)


def apply(system):
    if name := system.get("hostname"):
        run("hostnamectl", "set-hostname", name)
    if zone := system.get("timezone"):
        run("timedatectl", "set-timezone", zone)
    if wifi := system.get("wifi"):
        if country := wifi.get("country"):
            run("raspi-config", "nonint", "do_wifi_country", country)
        connection = "puffer-wifi"
        subprocess.run(["nmcli", "connection", "delete", connection], check=False, capture_output=True)
        args = ["nmcli", "connection", "add", "type", "wifi", "con-name", connection, "ifname", "wlan0", "ssid", wifi["ssid"], "connection.autoconnect", "yes"]
        if wifi.get("hidden"):
            args += ["wifi.hidden", "yes"]
        if password := wifi.get("password"):
            args += ["wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", password]
        run(*args)
        subprocess.run(["nmcli", "connection", "up", connection], check=False)
    if keys := system.get("sshAuthorizedKeys"):
        ssh = pathlib.Path("/home/puffer/.ssh")
        ssh.mkdir(mode=0o700, exist_ok=True)
        (ssh / "authorized_keys").write_text("\n".join(keys) + "\n")
        (ssh / "authorized_keys").chmod(0o600)
        run("chown", "-R", "puffer:puffer", str(ssh))
        run("systemctl", "enable", "--now", "ssh.service")
    # Earlier images turned the screen on the kernel command line, which the compositor ignores; the session turns it now.
    cmdline = pathlib.Path("/boot/firmware/cmdline.txt")
    words = cmdline.read_text().split()
    kept = [w for w in words if not (w.startswith("video=") and ":rotate=" in w)]
    if kept != words:
        cmdline.write_text(" ".join(kept) + "\n")


def session(system):
    """Writes what the kiosk session reads at every start: the transform of the screens for wlr-randr, and whether to hide the pointer ("auto" hides it when a touchscreen is connected)."""
    rotation = int(system.get("rotation") or 0)
    if rotation not in ROTATIONS:
        raise SystemExit(f"rotation must be one of {sorted(ROTATIONS)}, not {rotation}")
    cursor = system.get("cursor", "auto")
    if cursor not in CURSORS:
        raise SystemExit(f"cursor must be one of {CURSORS}, not {cursor}")
    text = f"PUFFER_ROTATION={ROTATIONS[rotation]}\nPUFFER_CURSOR={cursor}\n"
    if not SESSION.exists() or SESSION.read_text() != text:
        SESSION.parent.mkdir(parents=True, exist_ok=True)
        SESSION.write_text(text)


def main():
    config = json.loads(pathlib.Path(sys.argv[1]).read_text())
    system = config.get("system") or {}
    session(system)
    digest = hashlib.sha256(json.dumps(system, sort_keys=True).encode()).hexdigest()
    if STATE.exists() and STATE.read_text().strip() == digest:
        return
    apply(system)
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(digest)


if __name__ == "__main__":
    main()
