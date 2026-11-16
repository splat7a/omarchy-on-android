#!/bin/sh
# Write a boot image to the S22's boot partition from running Android (root adb), then verify it.
# Does NOT reboot. Only the boot partition is touched.
#   flash-boot.sh IMAGE            e.g. builds/b/boot.img, or ../images/stock-boot.img to roll back
set -eu
IMG=${1:?boot image}
T=${S22_ADB:-s22:5555}
STOCK_SHA=071c0eeba8c416f463a437cbef8cf83261dd250eb8ac24706701cd7896f5ebfd
[ "$(stat -c %s "$IMG")" = 100663296 ] || { echo "image must be exactly the partition size (100663296)"; exit 1; }
want=$(sha256sum "$IMG" | cut -d' ' -f1)
a() { timeout 600 adb -s "$T" "$@"; }
a root >/dev/null 2>&1 || true; sleep 3; adb connect "$T" >/dev/null 2>&1 || true
# Identity gate: this exact phone only.
id=$(a shell 'echo "$(getprop ro.boot.serialno) $(getprop ro.product.vendor.model) $(getprop ro.product.vendor.device)"' | tr -d '\r')
[ "$id" = "YOUR_SERIAL YOUR_MODEL YOUR_CODENAME" ] || { echo "unexpected device: $id"; exit 1; }
[ "$(a shell id -u | tr -d '\r')" = 0 ] || { echo "no root adb"; exit 1; }
cur=$(a shell 'sha256sum /dev/block/by-name/boot' | cut -d' ' -f1)
echo "current boot: $cur $([ "$cur" = "$STOCK_SHA" ] && echo '(stock)')"
[ "$cur" = "$want" ] && { echo "already flashed"; exit 0; }
a push "$IMG" /data/local/omarchy/boot-next.img >/dev/null
[ "$(a shell 'sha256sum /data/local/omarchy/boot-next.img' | cut -d' ' -f1)" = "$want" ] || { echo "push corrupted"; exit 1; }
a shell 'dd if=/data/local/omarchy/boot-next.img of=/dev/block/by-name/boot bs=4M conv=fsync 2>&1 && sync'
got=$(a shell 'sha256sum /dev/block/by-name/boot' | cut -d' ' -f1)
[ "$got" = "$want" ] || { echo "VERIFY FAILED: partition $got != $want. Re-run with the stock image before rebooting."; exit 1; }
echo "boot partition now $got (verified). Reboot when ready: adb -s $T reboot"
