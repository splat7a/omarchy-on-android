#!/bin/sh
# Runs inside the chroot as root: trim the rootfs for chroot use, full upgrade, base tools.
set -x
pacman -Rdd --noconfirm linux-aarch64 mkinitcpio mkinitcpio-busybox $(pacman -Qq | grep '^linux-firmware')
pacman -Syu --noconfirm
pacman -S --noconfirm --needed base-devel git sudo less vim htop wget glmark2 mesa-utils vulkan-tools wayland-utils foot ttf-dejavu
echo STAGE1_PACMAN_RC=$?
