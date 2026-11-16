#!/bin/sh
# Repack the stock boot image with a rebuilt kernel. Everything else (header v4, OS version,
# patch level, ramdisk, empty cmdline) is taken unchanged from the stock image.
#   make-boot.sh VARIANT   ->  builds/VARIANT/boot.img
set -eu
V=${1:?variant}
HERE=$(cd "$(dirname "$0")" && pwd)
STOCK=$HERE/../images/stock-boot.img
OUT=$HERE/builds/$V
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
unpack_bootimg --boot_img "$STOCK" --out "$TMP/u" >/dev/null
mkbootimg --header_version 4 --os_version 12.0.0 --os_patch_level 2022-10 \
  --kernel "$OUT/Image" --ramdisk "$TMP/u/ramdisk" --cmdline '' --output "$OUT/boot.img"
# Same AVB footer layout as stock (unsigned; vbmeta verification is disabled on this phone).
avbtool add_hash_footer --image "$OUT/boot.img" --partition_name boot --partition_size 100663296
# Sanity: the repacked image must hold exactly our kernel and the stock ramdisk.
unpack_bootimg --boot_img "$OUT/boot.img" --out "$TMP/v" >/dev/null
cmp "$TMP/v/kernel" "$OUT/Image"
cmp "$TMP/v/ramdisk" "$TMP/u/ramdisk"
strings "$OUT/Image" | grep -m1 'Linux version 5.10'
sha256sum "$OUT/boot.img"
