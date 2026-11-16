#!/bin/bash
# Inside the Droidspaces container as root, after stage 4 (Omarchy) and with the Anland Hyprland packages
# in /root/anland-pkgs: install them and make Omarchy start on its own as user s7 through uwsm.
set -u
exec > /root/stage5-session.log 2>&1
set -x
U=s7; H=/home/$U
# Hyprland with the Anland backend (provides hyprland), its plugin manager, patched Xwayland.
pacman -U --noconfirm /root/anland-pkgs/*.pkg.tar.*
pacman -Q hyprland-anland hyprpm-anland xorg-xwayland
# Omarchy's per-user defaults (the user existed before Omarchy was installed).
cp -rn /etc/skel/. "$H"/
# Anland display path for every compositor uwsm starts.
mkdir -p "$H/.config/uwsm"
cat > "$H/.config/uwsm/env" <<'E'
export ANLAND=1
export ANLAND_SOCKET=/run/display.sock
export ANLAND_DRM_DEVICE=/dev/dri/renderD128
export MESA_LOADER_DRIVER_OVERRIDE=kgsl
E
# Android owns locking and screen-off: keep Omarchy's own idle lock out of the way.
mkdir -p "$H/.local/state/omarchy/indicators" && touch "$H/.local/state/omarchy/indicators/stay-awake"
chown -R $U:$U "$H"
# The session: a PAM login session for s7 (logind gives it XDG_RUNTIME_DIR and a user manager),
# then uwsm starts Hyprland exactly like Omarchy does on a laptop.
cat > /etc/systemd/system/omarchy-session.service <<'E'
[Unit]
Description=Omarchy desktop (Hyprland on Anland)
After=systemd-user-sessions.service dbus.service network-online.target
Wants=network-online.target

[Service]
User=s7
PAMName=login
WorkingDirectory=~
Environment=XDG_SESSION_TYPE=wayland XDG_SESSION_CLASS=user XDG_SEAT=seat0
ExecStart=/usr/bin/uwsm start -e -D Hyprland hyprland.desktop
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
E
systemctl daemon-reload
systemctl enable omarchy-session.service
echo STAGE5_OK
