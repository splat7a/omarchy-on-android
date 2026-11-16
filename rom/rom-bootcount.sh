#!/system/bin/sh
# KernelSU post-fs-data.d: with the one-boot watchdog armed, count boots; on the fourth boot that
# never got as far as being disarmed (a reboot loop), put the previous system back and reboot.
D=/data/adb/s22-rom
[ -f $D/armed ] || exit 0
n=$(( $(cat $D/boots 2>/dev/null || echo 0) + 1 ))
echo $n > $D/boots
if [ $n -ge 4 ]; then
    echo "$(date '+%F %T') boot $n without finishing: rolling back" >> $D/watchdog.log
    mv $D/armed $D/rolled-back
    lptools replace system system_failed >> $D/watchdog.log 2>&1 &&
        lptools replace system_old system >> $D/watchdog.log 2>&1 && reboot
fi
