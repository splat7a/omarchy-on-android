#!/bin/bash
# Inside s22-omarchy/apk-builder (build host): build Omarchy Phone without Gradle (aapt2, javac, d8,
# zipalign, apksigner), signed with the same key as our Anland build. Output: /work/out/omarchy-phone.apk
set -euo pipefail
SDK=/opt/android-sdk
BT=$SDK/build-tools/35.0.0
JAR=$SDK/platforms/android-36/android.jar
cd /work/phoneapp
rm -rf build && mkdir -p build/classes build/dex build/gen
"$BT/aapt2" compile --dir res -o build/res.zip
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -o build/base.apk build/res.zip \
    --java build/gen --min-sdk-version 33 --target-sdk-version 36 --version-code 1 --version-name 1.0
javac -nowarn --release 11 -classpath "$JAR" -d build/classes \
    $(find src build/gen -name '*.java')
"$BT/d8" --release --min-api 33 --lib "$JAR" --output build/dex $(find build/classes -name '*.class')
python3 - <<'EOF'
import zipfile
with zipfile.ZipFile('build/base.apk', 'a', zipfile.ZIP_DEFLATED) as z:
    z.write('build/dex/classes.dex', 'classes.dex')
EOF
"$BT/zipalign" -f -p 4 build/base.apk build/aligned.apk
mkdir -p /work/out
# The signing keystore lives on the laptop (packages/apk/s22-omarchy-apps.jks); without it here, hand back the
# aligned unsigned APK for signing there.
if [ ! -f /work/keys/s22-omarchy-apps.jks ]; then
    cp build/aligned.apk /work/out/omarchy-phone-unsigned.apk
    sha256sum /work/out/omarchy-phone-unsigned.apk
    echo BUILD_PHONEAPP_UNSIGNED_OK
    exit 0
fi
"$BT/apksigner" sign --ks /work/keys/s22-omarchy-apps.jks --ks-pass pass:s22omarchy --key-pass pass:s22omarchy \
    --ks-key-alias s22omarchy --out /work/out/omarchy-phone.apk build/aligned.apk
"$BT/apksigner" verify /work/out/omarchy-phone.apk
sha256sum /work/out/omarchy-phone.apk
echo BUILD_PHONEAPP_OK
