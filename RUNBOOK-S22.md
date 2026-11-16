# Omarchy on the S22 Ultra — runbook

LineageOS 23.2 "S22 AI" stays the phone layer (calls, SMS,
camera, Android apps, lock screen). Omarchy 4.5 runs beside it in a Droidspaces container with real systemd and draws
through Anland on the Adreno 730. No VM.

## How it behaves

- **Boot:** KernelSU starts the container (Droidspaces `run_at_boot`), the container starts the Omarchy session
  (`omarchy-session.service`: uwsm → Hyprland with the Anland backend), and `omarchy-anlandd` (KernelSU `service.d`)
  shows it. About 40 s after power-on Omarchy is up without touching anything.
- **Docked (USB-C monitor):** Omarchy fills the monitor (desktop profile, scale 1); the phone screen stays Android.
- **Undocked:** Omarchy fills the phone screen with Omarchy Mobile's phone shell (phone profile, scale 4, touch keyboard).
- **Switching** is automatic: `omarchy-anlandd` moves the window when a monitor appears or goes; inside the container
  `omarchy-s22-display` picks the profile from the output's shape (portrait = phone).
- **Keep Omarchy on the phone screen while docked:** `echo 0 > /data/local/omarchy/force-display` (root); remove the
  file to go back to automatic.
- **Android apps:** in the Omarchy launcher (entries `android-*`), they open full screen over Omarchy on the screen
  Omarchy is on; Back (right-click, or Esc in most apps) returns to Omarchy. Links `tel:`, `sms:`, `market:` open in Android.
- **Locking** is Android's (Omarchy's own idle lock is off in both profiles).

## Phone bridge (`phone-bridge/`)

| Part | Where | Does |
|---|---|---|
| Omarchy Phone app | `com.s22.omarchyphone`, `packages/apk/omarchy-phone.apk` (source `phone-bridge/android`, built without Gradle by `build.sh` in the build host APK image) | Notification listener (always bound, so it needs no notification of its own), non-UI in-call service (app-op `MANAGE_ONGOING_CALLS`; call-state fallback with the caller number if Telecom does not bind it), phone/Wi-Fi state, starts apps and notification intents on Omarchy's display (brief 1 px overlay: Android 15+ background-start rule). Doze-exempt. |
| `omarchy-phone` | container `/usr/local/bin`, user unit `omarchy-phone.service` | Listens on the container's own address `172.28.79.5:47700` (reachable only from the phone); both ends prove the token `~/.config/omarchy-phone/token` (copy in the app's private files). Android notifications → Omarchy notifications (open, actions, reply prompt, dismiss both ways); `org.omamobile.Phone1` and `org.omamobile.Messages1` on the session bus (Omarchy Mobile's call card: answer, decline, hang up, mute, speaker, quick-reply SMS); calls ring as notifications when no call card is loaded (desktop); writes `$XDG_RUNTIME_DIR/omarchy-phone/{cell,wifi}.json`; Android apps → `~/.local/share/applications/android-*.desktop`, icons in `~/.local/share/icons/hicolor/128x128/apps/android-*.png`. CLI: `omarchy-phone status`, `launch PKG[/ACT]`, `open URI`, `sms NUMBER TEXT`, `settings [wifi|mobile|network|bluetooth|battery|sound|display|all]`, `incall`, `apps`, `test-call [NUMBER] [NAME]`. |
| `omamobile-cell-watch`, `omaphone` | container `/usr/local/bin` (shadow `/usr/bin`) | Mobile network for the phone bar from Android; "open Phone app" = Android's call screen. |
| Phone bar patch | `patch-bar.py` on `omamobile.bar/Bar.qml` (`.qml.orig` kept) | Wi-Fi icon from Android. |
| `s22.phone` bar widget | `~/.config/omarchy/plugins/s22.phone` | Desktop bar: Android Wi-Fi/mobile state in place of `omarchy.network` (NetworkManager can't see Android's radios; Quickshell ignores the container's veth link). Click: Android Wi-Fi settings; right-click: mobile settings. |
| Reply prompt | `omarchy-phone-reply` (GTK4), Hyprland rule in `~/.config/hypr/hyprland.lua` | Text for a notification's Reply action. |

Install or repair: `phone-bridge/install-android.sh APK` (root on the phone) and `phone-bridge/container/install-container.sh SRC`
(root in the container); both are idempotent. The call path was tested end to end with pretend calls
(`omarchy-phone test-call`, a self-managed Telecom call from the app's `TestCallService`): on the monitor the call rings as
a notification and Answer, Mute and Hang up work by touch; on the phone screen Omarchy Mobile's call card takes over (Answer,
then the green call chip; tapping the chip opens Android's own call screen). VoIP apps' calls (self-managed) reach Omarchy
the same way. Real cellular calls and SMS are untested: the phone has no SIM. The app is now built unsigned on the build host
and signed on the laptop with your own app keystore (never committed): keep it on tmpfs, `apksigner sign --ks-pass env:...`,
then shred it. The same key signs Anland; a different key would block updating either app in place.

## Layout

| Where | What |
|---|---|
| `images/stock-*.img` | Rollback: stock boot, vendor_boot, dtbo, vbmeta, vbmeta_system (16 Nov 2026). Stock boot sha256 `071c0eeb…ebfd`. |
| `images/efs-backup-20261116/` | EFS, sec_efs, modem state, persist, carrier partitions (0700/0600, `SHA256SUMS`) taken before any eSIM work. |
| `kernel/` | Stock config/modules/CRCs; `builds/{stock,a,b}`; `b` (container options + KernelSU v3.3.1, Knox UH/RKP/KDP/DEFEX/FIVE/PROCA off) is flashed. `make-boot.sh`, `flash-boot.sh`, `REBUILD.md`. |
| `scripts/` | `omarchy-anlandd.sh` (phone `/data/adb/service.d`), `omarchy-s22-display` (container), `uwsm-env`, stage scripts, `phone-run.sh` (push + run as root), `s22ui.py` (screen driver), `container-networkmanager.sh` (tried, reverted: see notes). |
| `phone-bridge/` | Android app source, container daemon, widget, installers. |
| `packages/` | `hyprland-anland 0.57.0`, `omamobile-*`, `apk/anland-v5-s22.apk` (patched Anland), `apk/omarchy-phone.apk`, (signing keystore never in the repo). |
| `build-kit/` | Build kit used on the build host (not included in this repo). |

## Phone side (root)

| Path | What |
|---|---|
| `/data/local/omarchy/rootfs.img` | Container root (ext4), mounted at `/mnt/Droidspaces/omarchy` while running. |
| `/data/local/Droidspaces/` | Droidspaces v7.2.0 daemon, container config `Containers/omarchy/container.config` (`net_mode=nat`, `static_nat_ip=172.28.79.5`, GPU, Anland, Android storage, 4.5 GiB). |
| `/data/adb/service.d/omarchy-anlandd.sh` | Placement daemon (log `/data/local/omarchy/anlandd.log`); re-enables Anland's key interceptor after each launch (Android drops a force-stopped app's accessibility service); writes the Android display id into the container (`/var/lib/omarchy-s22/android-display`). |
| `/data/local/omarchy/s7.sh 'cmd'` | Run a command as s7 in the live session (container `/usr/local/bin/s7-session` copies the session environment over D-Bus). |

## Container side

- `omarchy-session.service` (system, `User=s7`, `PAMName=login`): `uwsm start -e -D Hyprland hyprland.desktop`.
- `~/.config/uwsm/env`: KGSL Mesa and Anland variables (`scripts/uwsm-env`).
- `~/.config/omarchy/shell.{desktop,phone}.json`: the two profiles; `shell.json` is the active copy.
- `upower.service` drop-in `PrivateUsers=no` (no user namespaces for service sandboxes); `rtkit-daemon` masked (cannot
  set capabilities in the container; PipeWire runs without real-time priority).
- Audio: PipeWire's `anland-speaker` sink plays through the Anland app. Clipboard syncs both ways through Anland.
- pacman `IgnorePkg`: `hyprland hyprland-anland omamobile-* mesa vulkan-*` (patched Hyprland with the Anland backend,
  our Omarchy Mobile build, the KGSL Mesa). Stock Hyprland has no Anland backend: never let an update replace it.
- `/usr/local/bin/bwrap` = bubblewrap 0.10.0 (`scripts/build-bwrap.sh`): Arch's newer bubblewrap needs `mount_setattr`
  (Linux 5.12+), which this 5.10 kernel lacks; without a working bwrap, glycin (GTK's image loader) fails and GTK apps
  show no icons or images.
- On-screen keyboard: squeekboard (`mobi.phosh.OSK.service`), started by `omarchy-s22-display` in the phone profile and
  stopped on the monitor; Omarchy Mobile's layouts are linked into `~/.local/share/squeekboard/keyboards`.

## Kernel

- Source: Samsung S22 (Snapdragon) AVF1 drop, 5.10.81 (`googyanas/S22_S901E@931219a2`), clang r416183b, stock config,
  ThinLTO, `uname -r` unchanged (`5.10.81-android12-9-24854392-abS908EXXS2AVI7`).
- Added: SYSVIPC, POSIX_MQUEUE, IPC/PID/USER namespaces, DEVTMPFS, FHANDLE, UNIX_DIAG, PROC_CHILDREN (SYSVIPC/mqueue in
  reserved ABI slots, `build-kit/abi-patches.py`); all 4554 vendor-module symbol versions match.
- Flash: `kernel/flash-boot.sh kernel/builds/b/boot.img`. Rollback from Android: `kernel/flash-boot.sh images/stock-boot.img`.
  If Android does not come up: Vol Down + Power to restart, Vol Up + Power into recovery → fastbootd, USB to the laptop,
  `fastboot flash boot images/stock-boot.img`. Never flash Samsung firmware.

## Current ROM (16 Nov 2026)

S22 AI (LineageOS 23.2) rebuilt with in-display fingerprint support, installed 16 Nov 05:42 (image sha256
`f2bb937d…93a5`, build date 16 Nov 01:03 UTC, same platform key and security patch 2026-11-01 as before). On the phone:
fingerprint sensor type 2 (ultrasonic in-display), SystemUI sensor at (720, 2280), strong (class 3); nothing enrolled.
To use it: Settings → Security → set a screen lock (PIN), then Fingerprint unlock → enrol on the sensor near the
bottom-centre of the screen. The previous system is still in super as `system_old` (3.45 GB): once happy,
`su -c 'lptools remove system_old'`; to go back instead, `lptools replace system system_new_bad && lptools replace system_old system && reboot`.
Signing keys were shredded on the build host after the build: a rebuild needs them restored from your own secure storage
 into `src/vendor/lineage-priv/keys`.

## Updating the ROM (system image) in place

Built on the build host (the build kit, `rom-compile.sh` in the `s22-omarchy-rom` container; the recipe adds the
in-display fingerprint pieces via `build-kit/rom/s22-fresh-apply.py`). Run it with `BUILD_JOBS=32` and
`build-kit/rom/java-governor.sh 9` inside the container: R8 jobs take 1–2 GiB each, and at `-j46` they pushed the 44 GiB
container into the OOM killer; the governor freezes Java jobs beyond 9 so C++ work still runs 32-wide. Then:

1. the build kit on the build host: filesystem check, platform signing key must equal the installed
   one (otherwise Android rejects its shared system UIDs and boot-loops), fingerprint values and code present.
2. `omarchy/rom/ship-rom.sh` on the laptop: block delta against the phone's current system (index made on the phone
   with `blockdelta.py index`), sent in 8 MiB checked pieces, rebuilt on the phone as `/data/local/omarchy/new-system.img`
   and checked against the build's SHA-256.
3. On the phone as root: `rom-install.sh /data/local/omarchy/new-system.img SHA256`, then reboot. The previous system
   stays in super as `system_old`; `rom-watchdog.sh`/`rom-bootcount.sh` swap it back and reboot if the new one does not
   finish booting (5 system_server starts, 25 minutes, or 4 boots). Once the new system is known good:
   `lptools remove system_old`.
   (`lptools create` maps the new partition itself; `lptools replace A B` deletes B if present and renames A to B;
   both rehearsed on a dummy partition on 16 Nov.)

## Notes

- Anland v5's Android side asks for a frame every display refresh and the compositor must answer, so Omarchy renders
  continuously while it is on screen (60/s on the monitor, up to 120/s on the phone panel); it stops when Omarchy is
  not visible (Android home or another app in front).

- Arch Linux ARM's default `alarm` user and root password are removed/locked; pacman needs `DisableSandboxFilesystem`.
- EGL dma-buf import on KGSL needs buffer heights in multiples of 4: the Anland APK rounds its surface down (`anland-align.patch`).
- Android 16 desktop windowing gives Omarchy a caption bar and hides it behind freeform apps, so Omarchy's display is
  kept in full-screen mode and Anland requests full screen (`anland-fullscreen.patch`).
- NetworkManager on the container link was tried and reverted: Quickshell's network service ignores veth devices.
- The Omarchy shell caches icon lookups: an Android app's icon that arrives after the shell started may show as a letter
  until `omarchy-restart-shell`.
- The phone's own Claude keeps its undo list in `/root/phone/CLAUDE.md` (Debian proot); laptop changes are listed in
  `/root/phone/omarchy-laptop-changes.md`.
