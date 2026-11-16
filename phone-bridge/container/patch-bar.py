#!/usr/bin/env python3
"""Teach Omarchy Mobile's status bar (omamobile.bar/Bar.qml) to show Android's Wi-Fi, which
omarchy-phone writes to $XDG_RUNTIME_DIR/omarchy-phone/wifi.json. Idempotent; fails loudly if
the anchors moved."""
import sys
from pathlib import Path

path = Path(sys.argv[1] if len(sys.argv) > 1 else "/usr/share/omamobile/shell/plugins/omamobile.bar/Bar.qml")
s = path.read_text()
MARK = "S22: Android owns Wi-Fi"
if MARK in s:
    print("Bar.qml: already patched")
    sys.exit(0)

OLD1 = """  readonly property string networkIcon: StatusModel.networkIcon(networkKind,
    wifiNetwork ? Math.round((wifiNetwork.signalStrength || 0) * 100) : -1)"""
NEW1 = """  // S22: Android owns Wi-Fi; omarchy-phone reports it (no NetworkManager in the container).
  // {"bridge": false} while the phone isn't connected: then the usual NetworkManager view.
  property var phoneWifi: null
  readonly property bool phoneWifiActive: phoneWifi !== null && phoneWifi.bridge === true
  FileView {
    id: phoneWifiFile
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/omarchy-phone/wifi.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.phoneWifi = JSON.parse(text()) } catch (e) {} }
    onLoadFailed: root.phoneWifi = null
  }
  Timer {
    interval: 5000
    repeat: true
    running: root.phoneWifi === null
    onTriggered: phoneWifiFile.reload()
  }
  readonly property string networkIcon: phoneWifiActive
    ? (phoneWifi.connected ? StatusModel.wifiIcon(phoneWifi.strength >= 0 ? phoneWifi.strength : 100) : "")
    : StatusModel.networkIcon(networkKind,
      wifiNetwork ? Math.round((wifiNetwork.signalStrength || 0) * 100) : -1)"""
OLD2 = 'opacity: root.networkKind === "off" || root.networkKind === "disconnected" ? 0.55 : 1'
NEW2 = ('opacity: root.phoneWifiActive ? (root.phoneWifi.validated === false ? 0.55 : 1)'
        ' : (root.networkKind === "off" || root.networkKind === "disconnected" ? 0.55 : 1)')
for old in (OLD1, OLD2):
    if s.count(old) != 1:
        sys.exit(f"Bar.qml: anchor found {s.count(old)} times: {old[:60]!r}")
s = s.replace(OLD1, NEW1).replace(OLD2, NEW2)
path.with_suffix(".qml.orig").write_text(path.read_text())
path.write_text(s)
print("Bar.qml: patched")
