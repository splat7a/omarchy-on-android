#!/system/bin/sh
# Install Omarchy Phone (the Android half of the phone bridge) and give it what it needs.
# Runs as root on the phone (KernelSU). Safe to run again.
#   install-android.sh /data/local/tmp/omarchy-phone.apk
set -e
APK=${1:-/data/local/tmp/omarchy-phone.apk}
PKG=com.s22.omarchyphone
R=/mnt/Droidspaces/omarchy

pm install -r -g "$APK" >/dev/null
for p in READ_PHONE_STATE READ_CONTACTS READ_CALL_LOG ANSWER_PHONE_CALLS SEND_SMS; do
    pm grant $PKG android.permission.$p 2>/dev/null || true
done
# Start activities on Omarchy's screen from the background (a brief invisible overlay window).
appops set $PKG SYSTEM_ALERT_WINDOW allow
# Bound by Telecom as a non-UI in-call service (as watch companion apps are): calls and controls.
appops set $PKG MANAGE_ONGOING_CALLS allow
# Not put to sleep by Doze or App Standby: notifications and calls must reach Omarchy at once.
dumpsys deviceidle whitelist +$PKG >/dev/null
cmd notification allow_listener $PKG/$PKG.BridgeListener

# The shared token: made once, kept in the container (s7 only) and in the app's private files.
TOK=$R/home/s7/.config/omarchy-phone/token
if [ ! -s "$TOK" ]; then
    mkdir -p "${TOK%/*}"
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TOK"
fi
chown -R 1000:1000 "${TOK%/*}"
chmod 700 "${TOK%/*}"
chmod 600 "$TOK"
D=/data/data/$PKG
uid=$(stat -c %u $D)
ctx=$(ls -Zd $D | awk '{print $1}')
mkdir -p $D/files
cp "$TOK" $D/files/token
chown -R $uid:$uid $D/files
chmod 700 $D/files
chmod 600 $D/files/token
chcon -R "$ctx" $D/files
echo "Omarchy Phone installed (uid $uid)"
