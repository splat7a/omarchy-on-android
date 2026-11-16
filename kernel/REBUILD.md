# Rebuilding the S22 kernel

1. Source: `git clone https://github.com/googyanas/S22_S901E` at commit `931219a21c771a4ef688ae3d113e27d87df5d08a`
   ("AVF1 source drop", Samsung 5.10.81 with toolchain prebuilts).
2. `python3 abi-patches.py <src>/kernel_platform/common` (SysV IPC / mqueue into reserved ABI slots).
3. KernelSU: clone https://github.com/tiann/KernelSU into `kernel_platform/common/KernelSU`, checkout `v3.3.1`
   (keep full history: the version number is 30000 + commit count = 32680), then
   `ln -s ../KernelSU/kernel drivers/kernelsu`, add `obj-$(CONFIG_KSU) += kernelsu/` to `drivers/Makefile` and
   `source "drivers/kernelsu/Kconfig"` before `endmenu` in `drivers/Kconfig`. (`s22-kernel-source.diff` = the full diff.)
4. `kbuild.sh b` in a Debian container with `/work/kernel/{src,stock-config.gz}` (stock config = `stock/config.gz`).
5. `make-boot.sh b`, then check `required-crcs.txt` against the new `Module.symvers` before flashing.
