#!/bin/sh
# Inside the chroot as root, before the first systemd boot under Droidspaces.
set -ux
echo omarchy > /etc/hostname
# Android owns time, SSH exposure and the network link; the container must not fight it.
systemctl disable sshd.service systemd-timesyncd.service 2>/dev/null
systemctl mask systemd-timesyncd.service systemd-networkd-wait-online.service 2>/dev/null
# journald: RAM only, small.
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=64M\n' > /etc/systemd/journald.conf.d/10-android.conf
# Locale/time zone like the laptop.
ln -sf /usr/share/zoneinfo/Asia/Dubai /etc/localtime
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
systemctl is-enabled sshd systemd-networkd systemd-resolved 2>/dev/null
ls /etc/systemd/network/ 2>/dev/null
echo PREP_OK
