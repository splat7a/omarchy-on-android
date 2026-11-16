import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The S22's network in Omarchy's bar. Android owns Wi-Fi and the modem; omarchy-phone writes their
// state to $XDG_RUNTIME_DIR/omarchy-phone (wifi.json, cell.json). Click: Android's Wi-Fi settings;
// right-click: mobile network settings (both open on the screen Omarchy is on).
BarWidget {
  id: root
  moduleName: "s22.phone"

  readonly property string stateDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/omarchy-phone"
  property var phoneWifi: null
  property var phoneCell: null

  FileView {
    id: wifiFile
    path: root.stateDir + "/wifi.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.phoneWifi = JSON.parse(text()) } catch (e) {} }
    onLoadFailed: root.phoneWifi = null
  }

  FileView {
    id: cellFile
    path: root.stateDir + "/cell.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.phoneCell = JSON.parse(text()) } catch (e) {} }
    onLoadFailed: root.phoneCell = null
  }

  // The files appear when omarchy-phone starts; until then look again now and then.
  Timer {
    interval: 5000
    repeat: true
    running: true
    // Quick while the files are missing, then a slow safety net for a missed change.
    onTriggered: { wifiFile.reload(); cellFile.reload(); interval = (root.phoneWifi === null || root.phoneCell === null) ? 5000 : 30000 }
  }

  readonly property bool bridged: phoneWifi !== null && phoneWifi.bridge === true
  readonly property bool onWifi: bridged && phoneWifi.connected === true
  readonly property bool onMobile: phoneCell !== null && phoneCell.modem === true && phoneCell.state === "connected"

  function wifiGlyph(strength) {
    var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    var s = strength >= 0 ? strength : 100
    return icons[Math.max(0, Math.min(4, Math.ceil(s / 20) - 1))]
  }

  function cellGlyph(strength) {
    if (strength < 0) return String.fromCodePoint(0xF08BF)
    var icons = ["󰢿", "󰢼", "󰢽", "󰢾"]
    return icons[Math.max(0, Math.min(3, Math.floor(strength / 25.01)))]
  }

  readonly property string label: {
    if (onWifi) return wifiGlyph(phoneWifi.strength)
    if (onMobile) return cellGlyph(phoneCell.strength)
    return "󰤮"
  }

  readonly property string tip: {
    if (!bridged) return "Phone not connected to Omarchy"
    var parts = []
    parts.push(onWifi ? "Wi-Fi connected" + (phoneWifi.validated === false ? " (no internet)" : "")
                      : (phoneWifi.enabled === false ? "Wi-Fi off" : "Wi-Fi not connected"))
    if (phoneCell && phoneCell.modem) {
      if (phoneCell.state === "no-sim") parts.push("No SIM")
      else if (phoneCell.state === "off") parts.push("Mobile radio off")
      else if (phoneCell.state === "registered" || phoneCell.state === "connected")
        parts.push((phoneCell.tech || "Mobile") + (phoneCell.state === "connected" ? " data" : "") + (phoneCell.roaming ? " (roaming)" : ""))
      else parts.push("Searching for a network")
    }
    return parts.join(" · ")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    slotSize: Style.bar.statusSlot
    tooltipText: root.tip
    opacity: root.onWifi || root.onMobile ? (root.onWifi && root.phoneWifi.validated === false ? 0.55 : 1) : 0.55
    onPressed: function(b) {
      if (!root.bar) return
      root.bar.run(b === Qt.RightButton ? "omarchy-phone settings mobile" : "omarchy-phone settings wifi")
    }
  }
}
