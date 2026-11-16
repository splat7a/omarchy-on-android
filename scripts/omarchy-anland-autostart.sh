#!/system/bin/sh
# KernelSU boot script (/data/adb/service.d): once Android is unlocked and the Droidspaces container
# "omarchy" is up, open its Omarchy desktop in the Anland app.
LOG=/data/local/omarchy/autostart.log
exec >> "$LOG" 2>&1
echo "$(date) start"
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
SOCKFILE=/data/local/Droidspaces/Pids/omarchy.asock
i=0; while [ ! -s "$SOCKFILE" ] && [ $i -lt 180 ]; do sleep 2; i=$((i+1)); done
[ -s "$SOCKFILE" ] || { echo "no container socket"; exit 1; }
# Apps cannot start before the first unlock (credential-encrypted storage).
until dumpsys window 2>/dev/null | grep -q "mDreamingLockscreen=false" && [ "$(getprop sys.user.0.ce_available)" = true ]; do sleep 3; done
sleep 3
am start -n com.anland.consumer/.SecondaryActivity --es socket_path "$(cat "$SOCKFILE")" --es window_name Omarchy \
  -f 0x18000000
echo "$(date) Anland window opened for $(cat "$SOCKFILE")"
