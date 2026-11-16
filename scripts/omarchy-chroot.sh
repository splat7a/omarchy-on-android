#!/system/bin/sh
# Omarchy chroot on the S22 Ultra (stage 1: stock kernel, plain chroot, no systemd).
# Runs in an Android root shell (adb root now; KernelSU su later).
# Safety: the chroot gets a private minimal /dev (no block devices, no partitions),
# a read-only /sys, and its own devpts. Nothing here writes outside /data/local/omarchy
# except the display-daemon socket in /data/local/tmp.
#
#   omarchy-chroot.sh create TARBALL   make the ext4 image and unpack the Arch Linux ARM rootfs
#   omarchy-chroot.sh mount            mount the image and the runtime filesystems (idempotent)
#   omarchy-chroot.sh daemon           (re)start the Anland display daemon
#   omarchy-chroot.sh run CMD...       run CMD inside the chroot as root
#   omarchy-chroot.sh user CMD...      run CMD inside the chroot as the desktop user (s7)
#   omarchy-chroot.sh status           show mounts, daemon and image usage
#   omarchy-chroot.sh umount           stop chroot processes and unmount everything
set -e
umask 022
BASE=/data/local/omarchy
IMG=$BASE/rootfs.img
R=$BASE/root
SIZE=48G
SOCKDIR=/data/local/tmp/anland
SOCK=$SOCKDIR/display.sock
DAEMON=$BASE/anland/display_daemon
USER_NAME=s7

die() { echo "omarchy-chroot: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "must run as root"

is_mnt() { grep -q " $1 " /proc/mounts; }

make_node() { # recreate one Android device node in the private /dev (toybox mount cannot bind device files)
    src=$1; dst=$R/dev/${2:-${1#/dev/}}; mode=${3:-666}
    [ -c "$src" ] || return 0
    [ -c "$dst" ] && return 0
    rm -f "$dst"
    mkdir -p "${dst%/*}"
    set -- $(stat -c '%t %T' "$src")
    mknod -m "$mode" "$dst" c "$(printf %d 0x$1)" "$(printf %d 0x$2)"
}

do_mount() {
    [ -f "$IMG" ] || die "no image at $IMG (run create first)"
    mkdir -p "$R"
    is_mnt "$R" || mount -t ext4 -o loop,noatime "$IMG" "$R"
    # Private /dev: only what a desktop needs. Deliberately no /dev/block.
    is_mnt "$R/dev" || mount -t tmpfs -o mode=755,size=16m,nosuid tmpfs "$R/dev"
    for n in null zero full random urandom tty fuse kgsl-3d0; do make_node /dev/$n; done
    make_node /dev/uinput uinput 660
    # Render node only: card0 is Android's display (SurfaceFlinger holds it); never expose it.
    make_node /dev/dri/renderD128
    make_node /dev/dma_heap/system dma_heap/system 444
    make_node /dev/tun net/tun
    mkdir -p "$R/dev/pts" "$R/dev/shm"
    is_mnt "$R/dev/pts" || mount -t devpts -o newinstance,gid=5,mode=620,ptmxmode=666 devpts "$R/dev/pts"
    [ -e "$R/dev/ptmx" ] || ln -s pts/ptmx "$R/dev/ptmx"
    is_mnt "$R/dev/shm" || mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs "$R/dev/shm"
    for l in fd:/proc/self/fd stdin:/proc/self/fd/0 stdout:/proc/self/fd/1 stderr:/proc/self/fd/2; do
        [ -e "$R/dev/${l%%:*}" ] || ln -s "${l#*:}" "$R/dev/${l%%:*}"
    done
    is_mnt "$R/proc" || mount -t proc -o nosuid,nodev,noexec proc "$R/proc"
    is_mnt "$R/sys" || mount -t sysfs -o ro,nosuid,nodev,noexec sysfs "$R/sys"
    is_mnt "$R/tmp" || mount -t tmpfs -o mode=1777,nosuid,nodev,size=2g tmpfs "$R/tmp"
    is_mnt "$R/run" || mount -t tmpfs -o mode=755,nosuid,nodev,size=256m tmpfs "$R/run"
    uid=$(grep "^$USER_NAME:" "$R/etc/passwd" 2>/dev/null | cut -d: -f3)
    if [ -n "$uid" ]; then
        mkdir -p "$R/run/user/$uid"; chown "$uid:$uid" "$R/run/user/$uid"; chmod 700 "$R/run/user/$uid"
    fi
    mkdir -p "$SOCKDIR" "$R/run/anland"; chmod 711 "$SOCKDIR"
    is_mnt "$R/run/anland" || mount -o bind "$SOCKDIR" "$R/run/anland"
    echo "mounted at $R"
}

do_umount() {
    # Stop anything still running from inside the chroot, then unmount deepest first.
    for p in /proc/[0-9]*; do
        root=$(readlink "$p/root" 2>/dev/null) || continue
        case "$root" in "$R"|"$R"/*) kill -TERM "${p#/proc/}" 2>/dev/null || true ;; esac
    done
    sleep 1
    grep " $R" /proc/mounts | cut -d' ' -f2 | sort -r | while read -r m; do umount "$m" 2>/dev/null || umount -l "$m"; done
    echo "unmounted"
}

do_daemon() {
    [ -x "$DAEMON" ] || die "daemon missing: $DAEMON"
    pkill -f "$DAEMON" 2>/dev/null || true
    mkdir -p "$SOCKDIR"; chmod 711 "$SOCKDIR"; rm -f "$SOCK"
    (umask 0; setsid "$DAEMON" "$SOCK" > "$BASE/anland/daemon.log" 2>&1 < /dev/null &)
    i=0; while [ ! -S "$SOCK" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
    [ -S "$SOCK" ] || die "daemon did not create $SOCK (see $BASE/anland/daemon.log)"
    chmod 0666 "$SOCK"
    echo "daemon running: $(pgrep -f "$DAEMON")"
}

in_chroot() { # env -i keeps Android's environment out of the chroot
    is_mnt "$R/proc" || do_mount >/dev/null
    exec chroot "$R" /usr/bin/env -i HOME=/root TERM="${TERM:-xterm-256color}" LANG=C.UTF-8 \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/bin "$@"
}

case "$1" in
    create)
        [ -n "$2" ] && [ -f "$2" ] || die "usage: create TARBALL"
        [ -e "$IMG" ] && die "$IMG already exists"
        mkdir -p "$BASE"
        truncate -s "$SIZE" "$IMG"
        mke2fs -t ext4 -L omarchy -m 0 -q "$IMG"
        mkdir -p "$R"; mount -t ext4 -o loop,noatime "$IMG" "$R"
        tar -xpzf "$2" -C "$R"
        rm -f "$R/etc/resolv.conf"
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$R/etc/resolv.conf"
        echo "created $IMG"
        ;;
    mount) do_mount ;;
    umount) do_umount ;;
    daemon) do_daemon ;;
    run) shift; in_chroot "$@" ;;
    user) shift; uid=$(grep "^$USER_NAME:" "$R/etc/passwd" | cut -d: -f3)
          is_mnt "$R/proc" || do_mount >/dev/null
          exec chroot "$R" /usr/bin/env -i HOME=/home/$USER_NAME USER=$USER_NAME LOGNAME=$USER_NAME \
              TERM="${TERM:-xterm-256color}" LANG=C.UTF-8 PATH=/usr/local/bin:/usr/bin \
              XDG_RUNTIME_DIR=/run/user/$uid /usr/bin/runuser -u "$USER_NAME" -- "$@" ;;
    status)
        grep " $R" /proc/mounts | cut -d' ' -f2,3
        echo "daemon: $(pgrep -f "$DAEMON" || echo stopped)  socket: $([ -S "$SOCK" ] && echo yes || echo no)"
        du -h "$IMG" 2>/dev/null; df -h "$R" 2>/dev/null | tail -1
        ;;
    *) sed -n '2,15p' "$0"; exit 1 ;;
esac
