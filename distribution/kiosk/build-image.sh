#!/usr/bin/env bash
# Builds a Raspberry Pi OS Lite image that starts Puffer full screen at boot, from the arm64 Linux bundle of a release.
#
#   sudo distribution/kiosk/build-image.sh puffer-X.Y.Z-linux-arm64.tar.gz puffer-X.Y.Z-raspberry-pi-arm64.img
#
# It runs on an arm64 Linux host with parted, e2fsprogs and xz, since it installs packages inside the image with chroot. BASE_IMAGE names another Raspberry Pi OS Lite arm64 image (.img.xz, a URL or a path); the default is the latest one.
set -euo pipefail

bundle=$(realpath "$1")
out=$2
here=$(dirname "$(realpath "$0")")
base=${BASE_IMAGE:-https://downloads.raspberrypi.com/raspios_lite_arm64_latest}

[ "$(id -u)" = 0 ] || { echo "Run as root." >&2; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "Run on an arm64 host." >&2; exit 1; }

root=$(mktemp -d)
loop=
cleanup() {
  for m in boot/firmware dev/pts dev proc sys; do
    mountpoint -q "$root/$m" && umount "$root/$m"
  done
  mountpoint -q "$root" && umount "$root"
  [ -n "$loop" ] && losetup -d "$loop"
  rmdir "$root"
}
trap cleanup EXIT

if [[ $base == http* ]]; then
  echo "Downloading $base"
  curl -fL --retry 3 -o "$out.xz" "$base"
  xz -dc "$out.xz" > "$out"
  rm "$out.xz"
else
  xz -dc "$base" > "$out"
fi

# Room for the packages and the app; the root partition fills the card at first boot.
truncate -s +1536M "$out"
parted -s "$out" resizepart 2 100%
loop=$(losetup -fP --show "$out")
e2fsck -fy "${loop}p2" || [ $? -le 1 ]
resize2fs "${loop}p2"

mount "${loop}p2" "$root"
mount "${loop}p1" "$root/boot/firmware"
mount --bind /dev "$root/dev"
mount --bind /dev/pts "$root/dev/pts"
mount -t proc proc "$root/proc"
mount -t sysfs sys "$root/sys"

resolv=$(readlink "$root/etc/resolv.conf" || true)
cp --remove-destination /etc/resolv.conf "$root/etc/resolv.conf"

chroot "$root" /bin/bash -euo pipefail <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update
# cage is the Wayland compositor that shows one app full screen; PipeWire lets the player and the Sendspin speaker share the sound card.
apt-get install -y --no-install-recommends \
  cage libgtk-3-0t64 libmpv2 libsecret-1-0 libegl1 libgles2 libgl1-mesa-dri \
  dbus-user-session pipewire pipewire-alsa pipewire-pulse wireplumber python3
apt-get clean
rm -rf /var/lib/apt/lists/*
useradd --create-home --groups audio,video,render,input puffer
EOF

mkdir -p "$root/opt/puffer"
tar -xzf "$bundle" -C "$root/opt/puffer"
cp -r "$here/rootfs/." "$root/"
chmod 755 "$root/usr/local/lib/puffer/setup.py"
cp "$here/puffer.json.example" "$root/boot/firmware/puffer.json.example"

chroot "$root" /bin/bash -euo pipefail <<'EOF'
systemctl enable puffer-setup.service puffer-kiosk.service
systemctl set-default graphical.target
# The kiosk takes the first console; the others keep their login prompt.
systemctl mask getty@tty1.service
# The account comes from the image, so the first boot asks for none.
systemctl disable userconfig.service 2>/dev/null || true
EOF

if [ -n "$resolv" ]; then ln -sf "$resolv" "$root/etc/resolv.conf"; else rm -f "$root/etc/resolv.conf"; fi

cleanup
trap - EXIT
loop=
xz -T0 -6 "$out"
echo "Built $out.xz"
