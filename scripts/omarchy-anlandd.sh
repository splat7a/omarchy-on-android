#!/system/bin/sh
# Omarchy display placement on the S22 (KernelSU service.d, runs as root from boot).
# Puts the Omarchy desktop (the Anland window of the Droidspaces container "omarchy") on the
# external monitor whenever one is connected, and on the phone screen otherwise. It only moves the
# window when the target screen changes (dock/undock) or at first start, so closing Omarchy on the
# phone to use Android apps is respected until the next dock/undock or reboot.
LOG=/data/local/omarchy/anlandd.log
SOCKFILE=/data/local/Droidspaces/Pids/omarchy.asock
exec >> "$LOG" 2>&1
echo "$(date '+%F %T') start pid $$"

until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done

external_display() {
    # First physical (uniqueId local:) display that is not the built-in panel -> its logical id.
    d=$(dumpsys display 2>/dev/null)
    echo "$d" | grep -o 'DisplayDeviceInfo{"[^"]*": uniqueId="local:' | sed 's/^DisplayDeviceInfo{"//; s/": uniqueId="local:$//' |
    while read -r name; do
        [ "$name" = "Built-in Screen" ] && continue
        echo "$d" | grep -o "mBaseDisplayInfo=DisplayInfo{\"$name\", displayId [0-9]*" | head -1 | grep -o '[0-9]*$'
        break
    done
}

launch() {
    am force-stop com.anland.consumer
    sleep 1
    # Omarchy takes its screen full-screen (no Android caption or taskbar); when docked, the phone screen
    # goes back to the freeform desktop windowing the owner enabled on 15 Nov.
    cmd window set-display-windowing-mode -d "$1" 1 2>/dev/null
    [ "$1" != 0 ] && cmd window set-display-windowing-mode -d 0 5 2>/dev/null
    am start --display "$1" --windowingMode 1 -n com.anland.consumer/.SecondaryActivity \
        --es socket_path "$2" --es window_name Omarchy -f 0x18000000 >/dev/null 2>&1
    keys_on
    # Tell the container which Android display Omarchy is on (omarchy-phone opens apps there).
    mkdir -p /mnt/Droidspaces/omarchy/var/lib/omarchy-s22 2>/dev/null &&
        echo "$1" > /mnt/Droidspaces/omarchy/var/lib/omarchy-s22/android-display
    echo "$(date '+%F %T') Omarchy shown on display $1"
}

# Android drops a force-stopped app's accessibility service, so turn Anland's key interceptor
# (Super and other desktop keys from a hardware keyboard) back on after every launch.
keys_on() {
    svc=com.anland.consumer/com.anland.consumer.KeyInterceptor
    cur=$(settings get secure enabled_accessibility_services)
    case "$cur" in
        *com.anland.consumer/*) ;;
        null|"") settings put secure enabled_accessibility_services "$svc" ;;
        *) settings put secure enabled_accessibility_services "$cur:$svc" ;;
    esac
    settings put secure accessibility_enabled 1
}

placed=""; placed_sock=""
while true; do
    sock=$(cat "$SOCKFILE" 2>/dev/null)
    if [ -n "$sock" ] && [ -S "$sock" ] && [ "$(getprop sys.user.0.ce_available)" = true ]; then
        target=$(external_display)
        [ -n "$target" ] || target=0
        # Manual override: echo 0 > /data/local/omarchy/force-display keeps Omarchy on the phone screen.
        [ -s /data/local/omarchy/force-display ] && target=$(cat /data/local/omarchy/force-display)
        if [ "$target" != "$placed" ] || [ "$sock" != "$placed_sock" ]; then
            launch "$target" "$sock"
            placed=$target; placed_sock=$sock
        fi
    fi
    sleep 3
done
