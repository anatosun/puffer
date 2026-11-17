#!/usr/bin/env python3
"""Applies the "system" section of the provisioning file at boot: host name, time zone, Wi-Fi, SSH keys and screen rotation. It applies a section only when it changed since the last boot, so a boot without changes costs a hash. Puffer itself reads the other sections."""

import hashlib
import json
import pathlib
import subprocess
import sys

STATE = pathlib.Path("/var/lib/puffer/system.sha256")


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
    if (rotation := system.get("rotation")) is not None:
        # The KMS driver reads the rotation of the screen from the kernel command line.
        cmdline = pathlib.Path("/boot/firmware/cmdline.txt")
        words = [w for w in cmdline.read_text().split() if not w.startswith("video=")]
        if rotation:
            words.append(f"video=HDMI-A-1:rotate={int(rotation)}")
        cmdline.write_text(" ".join(words) + "\n")


def main():
    config = json.loads(pathlib.Path(sys.argv[1]).read_text())
    system = config.get("system") or {}
    digest = hashlib.sha256(json.dumps(system, sort_keys=True).encode()).hexdigest()
    if STATE.exists() and STATE.read_text().strip() == digest:
        return
    apply(system)
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(digest)


if __name__ == "__main__":
    main()
