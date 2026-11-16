#!/system/bin/sh
# In-place install of a new S22 AI system image (root on the phone, Android running).
#   rom-install.sh IMAGE SHA256
# Writes the image into a new logical partition in super, keeps the running system as "system_old",
# swaps the names, and arms a one-boot watchdog (rom-watchdog.sh) that puts system_old back and
# reboots if the new system does not finish booting. Nothing changes until the next reboot.
IMG=$1
SHA=$2
D=/data/adb/s22-rom
mkdir -p $D
log() { echo "$(date '+%F %T') $*" | tee -a $D/install.log; }

[ -f "$IMG" ] && [ -n "$SHA" ] || { echo "usage: $0 IMAGE SHA256"; exit 2; }
if lpdump | grep -q 'Name: system_old$'; then
    log "system_old already exists: remove it (lptools remove system_old) once the current system is known good"
    exit 1
fi
[ "$(sha256sum "$IMG" | cut -d' ' -f1)" = "$SHA" ] || { log "image checksum mismatch"; exit 1; }
size=$(stat -c %s "$IMG")
free=$(lptools free | sed -n 's/^Free space: //p')
[ "$size" -lt "$free" ] || { log "not enough room in super: need $size, free $free"; exit 1; }

lpdump | grep -q 'Name: system_new$' && lptools remove system_new >/dev/null
lptools create system_new "$size" || { log "create failed"; exit 1; }
# lptools create maps the new partition itself; map only if it did not.
dev=/dev/block/mapper/system_new
[ -b $dev ] || lptools map system_new >/dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do [ -b $dev ] && break; sleep 1; done
[ -b $dev ] || { log "system_new is not mapped"; lptools remove system_new; exit 1; }
log "writing $size bytes to $dev"
dd if="$IMG" of=$dev bs=4194304 conv=fsync 2>>$D/install.log
if [ "$(head -c "$size" $dev | sha256sum | cut -d' ' -f1)" != "$SHA" ]; then
    log "read-back does not match: nothing switched"
    lptools unmap system_new; lptools remove system_new
    exit 1
fi
lptools unmap system_new >/dev/null
log "written and verified"

# The safety net for the first boot, then the switch (two renames; undone if the second fails).
mkdir -p /data/adb/service.d /data/adb/post-fs-data.d
cp /data/local/tmp/rom-watchdog.sh /data/adb/service.d/s22-rom-watchdog.sh
cp /data/local/tmp/rom-bootcount.sh /data/adb/post-fs-data.d/s22-rom-bootcount.sh
chmod 755 /data/adb/service.d/s22-rom-watchdog.sh /data/adb/post-fs-data.d/s22-rom-bootcount.sh
echo 0 > $D/boots
rm -f $D/passed $D/rolled-back
touch $D/armed
if ! lptools replace system system_old; then
    log "could not rename the running system: nothing switched"
    rm -f $D/armed; lptools remove system_new
    exit 1
fi
if ! lptools replace system_new system; then
    log "could not rename the new system: restoring the old name"
    lptools replace system_old system
    rm -f $D/armed
    exit 1
fi
log "switched: system = new image, system_old = previous system; reboot to start it"
lpdump | grep -E 'Name: system(_old)?$'
