#!/bin/sh
# Inside the chroot as root: desktop user, KGSL-capable Mesa, GPU environment.
set -eux
# ALARM ships user alarm (uid 1000, password alarm) and root password root: remove and lock.
id alarm >/dev/null 2>&1 && userdel -r alarm
passwd -l root
getent group render >/dev/null || groupadd -r render
id s7 >/dev/null 2>&1 || useradd -m -u 1000 -G wheel,video,input,audio,render -s /bin/bash s7
passwd -l s7
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-wheel; chmod 440 /etc/sudoers.d/10-wheel
pacman -U --noconfirm /root/mesa-pkgs/*.pkg.tar.xz
grep -q '^IgnorePkg' /etc/pacman.conf || sed -i 's/^#IgnorePkg.*/IgnorePkg = mesa vulkan-freedreno vulkan-mesa-implicit-layers vulkan-mesa-layers/' /etc/pacman.conf
grep -q MESA_LOADER_DRIVER_OVERRIDE /etc/environment || echo 'MESA_LOADER_DRIVER_OVERRIDE=kgsl' >> /etc/environment
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen; locale-gen
echo STAGE2_OK
