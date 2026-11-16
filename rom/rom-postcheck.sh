#!/system/bin/sh
# After rebooting into a newly installed system image (root on the phone): what booted, the
# in-display fingerprint setup, crashes, the rollback watchdog, and the Omarchy chain.
echo "== system"
getprop ro.system.build.date; getprop ro.build.version.security_patch; cat /proc/uptime
lpdump | grep -E 'Name: system(_old|_failed|_new)?$'
echo "== fingerprint"
getprop persist.sys.phh.ultrasonic_udfps; getprop persist.sys.s22.udfps_touch
dumpsys fingerprint | grep -i -E 'sensorType|sensor type|location|udfps|halControls|strength' | head -12
cmd overlay list android 2>/dev/null | grep -i -E 'auto_generated_rro_product|s22' | head -4
echo "== crashes since boot"
logcat -b crash -d 2>/dev/null | grep -E 'FATAL|Process:' | head -10
echo "== rollback watchdog"
ls /data/adb/s22-rom/; tail -4 /data/adb/s22-rom/watchdog.log 2>/dev/null
echo "== omarchy"
tail -2 /data/local/omarchy/anlandd.log
dumpsys accessibility | grep -c 'Bound services:{Service\[label=Anland'
/data/local/omarchy/s7.sh 'hyprctl monitors -j | jq -c ".[] | {name,width,height}"; systemctl --user is-active omarchy-phone; omarchy-phone status | grep -E "connected|state"'
