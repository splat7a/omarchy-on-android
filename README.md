# Omarchy on a rooted Android phone

Runs [Omarchy](https://omarchy.org) (Arch Linux ARM + Hyprland + Quickshell) in a systemd container beside Android on a rooted
phone, drawn on the GPU through the Anland app, with a bridge for notifications, calls, SMS and Android apps.
Built and tested on a Galaxy S22 Ultra (SM-S908E, Snapdragon 8 Gen 1, Adreno 730) on LineageOS 23.2.
`RUNBOOK-S22.md` is the full write-up of that phone. No SIM was available, so real cellular calls/SMS are untested.

## Pieces

| Piece | Where | Phone-specific? |
|---|---|---|
| Container runtime: [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) on KernelSU | RUNBOOK | no |
| Display: Anland (Android app + patched Hyprland backend) | `scripts/omarchy-anlandd.sh`, `omarchy-s22-display` | mostly no |
| Rootfs build (Arch Linux ARM → Omarchy) | `scripts/stage1..5-*.sh` | no (aarch64) |
| GPU: Mesa with KGSL (Adreno) | `scripts/stage2-user-mesa.sh` | **Adreno only** |
| Phone bridge (notifications, calls, apps) | `phone-bridge/` | no, plain Android APIs |
| Kernel with container options + KernelSU | `kernel/` | **yes, per device/kernel** |
| ROM / in-place update tooling | `rom/` | yes (LineageOS A/B-free dynamic partitions) |

## Applying it to another rooted phone

You need (1) root, (2) an aarch64 phone, (3) a kernel with the container features, (4) a GPU path.

1. **Check the kernel first.** Containers need namespaces (IPC, PID, USER, UTS, NET), `DEVTMPFS`, `CGROUPS`,
   `SYSVIPC`, `POSIX_MQUEUE`, `FHANDLE`. Run Droidspaces' check on your phone. Many stock kernels lack SYSVIPC/USER_NS.
   If features are missing you must rebuild the kernel (see `kernel/REBUILD.md`, `kernel/abi-patches.py`) and flash a patched boot
   image; vendor modules must still load (keep `uname -r` and symbol CRCs identical).
2. **Unlocked bootloader + root** (KernelSU or Magisk). On Samsung, Knox/RKP/DEFEX must be dealt with in the kernel;
   other brands (Pixel, OnePlus, Xiaomi) are usually easier because their kernels are open and GKI.
3. **GPU.** Adreno phones can use the KGSL Mesa build here. Mali/PowerVR phones would need a different Mesa driver
   (Panfrost on supported Mali) or software rendering (slow); this is the largest unknown.
4. **Android version.** The bridge uses `NotificationListener`, in-call service and `MANAGE_ONGOING_CALLS`; Android 13–16 tested
   behaviour is in the RUNBOOK notes (background-start rule, desktop windowing caption bar).
5. Replace S22 specifics: serial/device IDs, display size and scale in `omarchy-s22-display`, the 172.28.79.5 container
   address, package paths. Do not copy `kernel/stock-config-s22.gz` or the diff onto a different SoC.

Realistic effort for another Snapdragon phone with an open kernel: a few days. For a non-Adreno or locked-kernel phone it is
a research project. Nothing here is a one-click installer yet.

## Not included

Prebuilt packages and APKs (checksums only: `packages-SHA256SUMS`), vendor firmware/modules, disk images, signing keys
(never in the repo; the app keystore is private), and build logs.

## Warnings

- Flashing kernels/ROMs can brick a phone and may void warranty (on Samsung, trip Knox permanently). Back up EFS/modem/persist
  partitions first and keep the stock boot image. Everything here is provided as is, with no warranty.
- The phone bridge forwards notification text and call state to the container over a private link authenticated with a shared
  token (created at install, never committed). Treat the container as having access to your notifications.
- Never commit signing keystores, the bridge token or partition backups.

## License

Original files: MIT (see `LICENSE`). Third-party pieces keep their own licenses: Omarchy and Hyprland, Droidspaces, Anland,
KernelSU and the Linux kernel (GPL-2.0), Mesa, bubblewrap. `kernel/s22-kernel-source.diff` is a derivative of the Linux kernel (GPL-2.0).
