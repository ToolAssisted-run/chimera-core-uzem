#!/usr/bin/env python3
"""Checks that every key the package's default bindings name is a key
Chimera knows, so that none ships unbound by a misspelling. Chimera's names
are read from its source: the keyboard's (source/gui/Chimera.Input/
KeyMouseInput/DistinctKey.cs, with the names DistinctKeyNameOverrides.cs
gives some of them) and the mouse's.

usage: check-key-names.py <chimera checkout> <default_keybinds.json>"""
import json
import re
import sys

chimera, binds = sys.argv[1], sys.argv[2]
gui = chimera + "/source/gui"
enum = open(gui + "/Chimera.Input/KeyMouseInput/DistinctKey.cs").read()
enum = re.sub(r"///.*", "", enum)
body = enum[enum.index("enum DistinctKey"):]
body = body[body.index("{") + 1:body.index("}")]
members = [m.split("=")[0].strip() for m in body.split(",") if m.strip()]
over = open(gui + "/Chimera.Client.Common/input/DistinctKeyNameOverrides.cs").read()
renamed = dict(re.findall(r"DistinctKey\.(\w+)\s*=>\s*\"([^\"]+)\"", over))
known = {renamed.get(m, m) for m in members}
known |= {"WMouse L", "WMouse R", "WMouse M", "WMouse 1", "WMouse 2", "WMouse X", "WMouse Y", "RMouse X", "RMouse Y"}
cfg = json.load(open(binds))
bad = []
for panel in cfg.get("AllTrollers", {}).values():
    for control, value in panel.items():
        for key in filter(None, (v.strip() for v in value.split(","))):
            # a chord is keys joined by +
            for part in key.split("+"):
                if part not in known:
                    bad.append(f"{control}: {part}")
for panel in cfg.get("AllTrollersAnalog", {}).values():
    for control, value in panel.items():
        if value.get("Value") and value["Value"] not in known:
            bad.append(f"{control}: {value['Value']}")
if bad:
    sys.exit("keys Chimera does not know: " + ", ".join(bad))
print(f"every key the bindings name is one of Chimera's ({len(known)} names)")
