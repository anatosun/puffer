#!/bin/sh
# Shows a QR code for Android wireless debugging and pairs with the phone that scans it. Needs qrencode and avahi-tools.
set -eu
command -v qrencode >/dev/null || { echo "Install qrencode: sudo dnf install qrencode" >&2; exit 1; }
command -v avahi-browse >/dev/null || { echo "Install avahi-tools: sudo dnf install avahi-tools" >&2; exit 1; }
name="adb-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
pass="$(head -c4 /dev/urandom | od -An -tu4 | tr -d ' \n')"
code="WIFI:T:ADB;S:$name;P:$pass;;"
# The terminal's white is often a light grey, which some phones fail to read; 256-colour output uses pure white. On a desktop, the code also opens as an image.
qrencode -t ansi256utf8 -m 2 "$code"
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v xdg-open >/dev/null; then
  image="$(mktemp --suffix=.png)"
  trap 'rm -f "$image"' EXIT
  qrencode -s 12 -m 4 -o "$image" "$code"
  xdg-open "$image" >/dev/null 2>&1 &
fi
echo "On the phone: Developer options → Wireless debugging → Pair device with QR code"
# The phone announces the pairing service under the name in the code once it has scanned it.
while :; do
  line=$(avahi-browse -rpt _adb-tls-pairing._tcp 2>/dev/null | grep '^=' | grep ';IPv4;' | grep "$name" | head -1 || true)
  [ -n "$line" ] && break
  sleep 1
done
ip=$(echo "$line" | cut -d';' -f8)
port=$(echo "$line" | cut -d';' -f9)
adb pair "$ip:$port" "$pass"
echo "Paired. Connect with: make connect ADDR=<ip:port shown under Wireless debugging>"
