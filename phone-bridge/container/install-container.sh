#!/bin/bash
# Install the container half of the phone bridge. Runs as root inside the Omarchy container.
#   install-container.sh /var/tmp/omarchy-phone-src
set -euo pipefail
SRC=${1:-/var/tmp/omarchy-phone-src}
install -m 755 "$SRC"/omarchy-phone "$SRC"/omarchy-phone-reply "$SRC"/omamobile-cell-watch "$SRC"/omaphone /usr/local/bin/
install -m 644 "$SRC"/omarchy-phone.service /etc/systemd/user/omarchy-phone.service
systemctl --global enable omarchy-phone.service
install -d -o s7 -g s7 /home/s7/.local/share/applications
install -m 644 -o s7 -g s7 "$SRC"/omarchy-phone-links.desktop /home/s7/.local/share/applications/
python3 "$SRC"/patch-bar.py /usr/share/omamobile/shell/plugins/omamobile.bar/Bar.qml
install -d -o s7 -g s7 /home/s7/.config/omarchy/plugins/s22.phone
install -m 644 -o s7 -g s7 "$SRC"/s22.phone/manifest.json "$SRC"/s22.phone/BarWidget.qml /home/s7/.config/omarchy/plugins/s22.phone/
runuser -u s7 -- python3 "$SRC"/s22-shell-config.py
runuser -u s7 -- /usr/local/bin/s7-session bash -c '
    for m in x-scheme-handler/tel x-scheme-handler/sms x-scheme-handler/smsto x-scheme-handler/mms x-scheme-handler/market; do
        xdg-mime default omarchy-phone-links.desktop "$m"
    done
    systemctl --user daemon-reload
    systemctl --user restart omarchy-phone
    sleep 2
    systemctl --user is-active omarchy-phone
    journalctl --user -u omarchy-phone -n 5 --no-pager -o cat'
