#!/bin/sh
# Run a local shell script on the S22 as root (KernelSU su): phone-run.sh SCRIPT [ARGS...]
set -eu
S=$1; shift
n=$(basename "$S")
timeout 60 adb -s ${S22_ADB:-s22:5555} push "$S" /data/local/tmp/"$n" >/dev/null
timeout ${PHONE_RUN_TIMEOUT:-300} adb -s ${S22_ADB:-s22:5555} shell su -c "\"sh /data/local/tmp/$n $*\""
