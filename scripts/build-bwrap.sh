#!/bin/bash
# Inside the Omarchy container (root): bubblewrap 0.10.0 in /usr/local/bin. Arch's bubblewrap (0.11+) needs the
# mount_setattr syscall (Linux 5.12+); Samsung's 5.10 kernel lacks it, so every bwrap sandbox failed, and with it
# glycin, gdk-pixbuf's image loader: GTK apps showed no icons or images. glycin finds bwrap through PATH.
set -euo pipefail
mkdir -p /var/tmp/bwrap-src && cd /var/tmp/bwrap-src
[ -f bubblewrap-0.10.0.tar.xz ] || curl -fsSL -o bubblewrap-0.10.0.tar.xz \
    https://github.com/containers/bubblewrap/releases/download/v0.10.0/bubblewrap-0.10.0.tar.xz
echo "65d92cf44a63a51e1b7771f70c05013dce5bd6b0b2841c4b4be54b0c45565471  bubblewrap-0.10.0.tar.xz" | sha256sum -c -
rm -rf bubblewrap-0.10.0 && tar xf bubblewrap-0.10.0.tar.xz && cd bubblewrap-0.10.0
CFLAGS=-std=gnu17 meson setup build --buildtype=release --prefix=/usr/local -Dman=disabled -Dselinux=disabled \
    -Dtests=false -Dbash_completion=disabled -Dzsh_completion=disabled >/dev/null
ninja -C build >/dev/null
install -m 755 build/bwrap /usr/local/bin/bwrap
/usr/local/bin/bwrap --version
