#!/system/bin/sh
# KernelSU service.d: one-time safety net after rom-install.sh. While /data/adb/s22-rom/armed exists:
# if Android finishes booting and stays up for 3 minutes, disarm; if system_server keeps crashing
# (5 starts) or the boot has not finished after 25 minutes, put the previous system back
# (system_old) and reboot into it.
D=/data/adb/s22-rom
[ -f $D/armed ] || exit 0
LOG=$D/watchdog.log
echo "$(date '+%F %T') watching boot $(cat $D/boots 2>/dev/null)" >> $LOG

rollback() {
    echo "$(date '+%F %T') rolling back: $1" >> $LOG
    mv $D/armed $D/rolled-back
    if lptools replace system system_failed >> $LOG 2>&1 && lptools replace system_old system >> $LOG 2>&1; then
        sync
        reboot
    else
        echo "$(date '+%F %T') rollback rename failed; system/system_old/system_failed left as they are" >> $LOG
    fi
}

start=$(date +%s)
seen=""
starts=0
while :; do
    if [ "$(getprop sys.boot_completed)" = 1 ]; then
        sleep 180
        if [ "$(getprop sys.boot_completed)" = 1 ] && pidof system_server >/dev/null; then
            mv $D/armed $D/passed
            echo "$(date '+%F %T') booted and stable: disarmed (system_old kept until removed by hand)" >> $LOG
            exit 0
        fi
    fi
    p=$(pidof system_server)
    case " $seen " in *" $p "*) ;; *) [ -n "$p" ] && { seen="$seen $p"; starts=$((starts + 1)); } ;; esac
    [ $starts -ge 5 ] && { rollback "system_server started $starts times"; exit 0; }
    [ $(($(date +%s) - start)) -ge 1500 ] && { rollback "boot not finished after 25 minutes"; exit 0; }
    sleep 5
done
