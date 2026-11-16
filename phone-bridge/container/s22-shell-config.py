#!/usr/bin/env python3
"""Omarchy shell settings for the S22 (runs as s7; idempotent):
- the desktop bar shows the phone's network (s22.phone) instead of NetworkManager's (omarchy.network),
  which cannot see Android's Wi-Fi or modem from the container;
- Omarchy's own idle lock is off in both profiles: Android owns locking (keyguard, fingerprint), and a
  second lock inside the container would ask for a Linux password that is not used anywhere else.
The live shell.json is refreshed from the active profile."""
import json
from pathlib import Path

cfg = Path.home() / ".config/omarchy"
state = Path.home() / ".local/state/omarchy-s22/profile"


def edit(name, fn):
    p = cfg / name
    d = json.loads(p.read_text())
    before = json.dumps(d, sort_keys=True)
    fn(d)
    if json.dumps(d, sort_keys=True) != before:
        p.write_text(json.dumps(d, indent=2) + "\n")
        print(f"{name}: updated")


def desktop(d):
    right = d.setdefault("bar", {}).setdefault("layout", {}).setdefault("right", [])
    for i, w in enumerate(right):
        if w.get("id") == "omarchy.network":
            right[i] = {"id": "s22.phone"}
    if not any(w.get("id") == "s22.phone" for w in right):
        right.insert(max(0, len(right) - 3), {"id": "s22.phone"})
    plugins = d.setdefault("plugins", [])
    if not any(p.get("id") == "s22.phone" for p in plugins):
        plugins.append({"id": "s22.phone"})
    d.setdefault("idle", {})["lock"] = 0


def phone(d):
    d.setdefault("idle", {})["lock"] = 0


edit("shell.desktop.json", desktop)
edit("shell.phone.json", phone)
profile = state.read_text().strip() if state.exists() else "desktop"
src = cfg / f"shell.{profile}.json"
if src.exists() and (cfg / "shell.json").read_text() != src.read_text():
    (cfg / "shell.json").write_text(src.read_text())
    print(f"shell.json: refreshed from the {profile} profile")
