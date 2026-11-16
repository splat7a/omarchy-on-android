#!/bin/bash
# Inside the Droidspaces container as root: Omarchy 4.5 from Omarchy's own aarch64 repo on top of Arch Linux ARM.
# Hardware/system pieces that Android owns (Bluetooth, printing, firewall, docker, power, zram, boot splash
# services, network management) are left out or disabled.
set -u
exec > /root/stage4-omarchy.log 2>&1
set -x
KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
pacman-key --add /root/omarchy-repo-key.asc && pacman-key --lsign-key $KEY
# [omarchy] goes LAST: Arch Linux ARM's newer Hyprland stack (needed by the Anland build) must win over the
# older pins in Omarchy's repo; Omarchy-only packages still come from [omarchy].
python3 - <<'PY'
import re
c=open('/etc/pacman.conf').read()
c=re.sub(r'\n\[omarchy\]\nServer = [^\n]*\n','\n',c)
c=c.rstrip('\n')+'\n\n[omarchy]\nServer = https://pkgs.omarchy.org/stable/$arch\n'
open('/etc/pacman.conf','w').write(c)
PY
grep -n -A1 '^\[' /etc/pacman.conf
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 6/' /etc/pacman.conf
for try in 1 2 3; do pacman -Syu --noconfirm && break; sleep 20; done
WANT="omarchy omarchy-settings aether alsa-utils base-devel bash-completion bat btop chromium cliamp dosfstools disktree-bin
 evince exfatprogs expac eza fakeroot fastfetch fcitx5 fcitx5-gtk fcitx5-qt fd ffmpeg ffmpegthumbnailer fontconfig foot fzf
 git gliff gnome-keyring gnome-themes-extra grim gum gvfs-mtp gvfs-nfs gvfs-smb herdr hype hyprland-guiutils
 hyprland-preview-share-picker hyprpicker imagemagick imv inetutils inotify-tools inxi jq lazygit less libsecret libvips
 libyaml libreoffice-fresh localsend lua51 luarocks man-db mariadb-libs mise-bin monologue moonlight-qt mpv mpv-mpris
 nautilus nautilus-python noto-fonts noto-fonts-cjk noto-fonts-emoji nvim obsidian omacalc omacut omawrite omarchy-nvim
  omasnap owe pacman-contrib pamixer pinta plocate postgresql-libs python-gobject
 python-poetry-core qt6-base qt6-declarative qt6-multimedia qt6-svg qt6-wayland ttfx qrencode qt6-imageformats quickshell
 ripgrep ruby signed slurp socat starship superwhisper-bin sushi tesseract tesseract-data-eng tldr tree-sitter-cli tmux
 tobi-try ttf-ia-writer ttf-jetbrains-mono-nerd-basic unzip usage uwsm vi whois wireplumber pipewire pipewire-pulse
 pipewire-alsa wl-clipboard wtype woff2-font-awesome xdg-desktop-portal-gtk xdg-desktop-portal-hyprland
 xdg-terminal-exec xorg-xsetroot yaru-icon-theme yay yt-dlp zbar zoxide rtkit squeekboard"
AVAIL=""; MISSING=""
for p in $WANT; do if pacman -Si "$p" >/dev/null 2>&1; then AVAIL="$AVAIL $p"; else MISSING="$MISSING $p"; fi; done
echo "MISSING:$MISSING"
# hyprland itself comes from the Anland build (provides hyprland); until it is installed, pretend it is there.
for try in 1 2 3 4 5; do
  pacman -S --noconfirm --needed --assume-installed hyprland=0.57.0 --assume-installed hyprpm=0.57.0 $AVAIL && { rc=0; break; }
  rc=$?; sleep 20
done
# Omarchy's shell is tested against its own Quickshell snapshot.
pacman -S --noconfirm --assume-installed hyprland=0.57.0 omarchy/quickshell
# Android owns these; keep the packages (dependencies) but never run them in the container.
systemctl mask NetworkManager.service NetworkManager-wait-online.service sddm.service plymouth-start.service \
  plymouth-quit.service plymouth-quit-wait.service bluetooth.service 2>/dev/null
echo "STAGE4_RC=$rc"
