#!/bin/bash
# Inside s22-omarchy-kbuild: build the S22 GKI kernel Image from Samsung's 5.10.81 source with the
# phone's exact stock config plus a variant's options. Usage: kbuild.sh VARIANT (a = containers only).
set -euo pipefail
V=${1:?variant}
K=/work/kernel
SRC=$K/src/kernel_platform/common
OUT=$K/out-$V
TC=$K/src/kernel_platform/prebuilts
export PATH=$K/src/kernel_platform/prebuilts-master/clang/host/linux-x86/clang-r416183b/bin:$TC/gas/linux-x86:$TC/kernel-build-tools/linux-x86/bin:$PATH
export LOCALVERSION=   # defined-but-empty: no "+" suffix from a dirty tree
M=(make -C "$SRC" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- KBUILD_BUILD_USER=s22 KBUILD_BUILD_HOST=omarchy)
mkdir -p "$OUT"
git config --global --add safe.directory "*"
zcat $K/stock-config.gz > "$OUT/.config"
C="$SRC/scripts/config --file $OUT/.config"
$C --set-str LOCALVERSION "-android12-9-24854392-abS908EXXS2AVI7" -d LOCALVERSION_AUTO \
   -d TRIM_UNUSED_KSYMS --set-str UNUSED_KSYMS_WHITELIST "" \
   -d LTO_CLANG_FULL -e LTO_CLANG_THIN -d DEBUG_INFO
CONTAINERS="-e SYSVIPC -e POSIX_MQUEUE -e IPC_NS -e PID_NS -e USER_NS -e DEVTMPFS -d DEVTMPFS_MOUNT -e FHANDLE -e UNIX_DIAG -e PROC_CHILDREN"
# Samsung hypervisor/Knox protections that block kernel root (same set the S22 ReSukiSU kernel turns off).
NOKNOX="-d SECURITY_DEFEX -d SECURITY_DSMS -d UH -d UH_RKP -d UH_LKMAUTH -d UH_LKM_BLOCK -d RKP -d RKP_CFP -d RKP_CFP_JOPP -d RKP_CFP_ROPP -d KDP -d KDP_CRED -d KDP_NS -d RKP_TEST -d KDP_TEST -d FIVE -d PROCA"
case $V in
  stock) $C -d KSU ;;   # rebuild of the stock config: proves the toolchain reproduces the stock ABI
  a) $C $CONTAINERS -d KSU ;;
  b) $C $CONTAINERS $NOKNOX -e KSU -d KSU_DEBUG ;;
  *) echo "unknown variant $V"; exit 2 ;;
esac
"${M[@]}" olddefconfig > "$OUT/olddefconfig.log" 2>&1
"${M[@]}" -s kernelrelease
"${M[@]}" -j"${JOBS:-46}" Image modules > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }
ls -la "$OUT/arch/arm64/boot/Image" "$OUT/Module.symvers"
echo "KBUILD_${V}_OK"
