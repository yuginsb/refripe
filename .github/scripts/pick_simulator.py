#!/usr/bin/env python3
"""Pick an available iPhone simulator on the newest iOS runtime.

Prints `udid=…` and `name=…` lines (append them to $GITHUB_OUTPUT).
Preference: plain "iPhone NN" with the highest number, then "iPhone NN Pro", then any iPhone.
"""
import json
import re
import subprocess
import sys

raw = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                     check=True, capture_output=True, text=True).stdout
devices = json.loads(raw)["devices"]


def runtime_version(key):
    m = re.search(r"iOS-(\d+)-(\d+)(?:-(\d+))?$", key)
    return tuple(int(x or 0) for x in m.groups()) if m else None


def score(name):
    m = re.fullmatch(r"iPhone (\d+)( Pro)?", name)
    if m:
        return (2 if not m.group(2) else 1, int(m.group(1)))
    if name.startswith("iPhone") and "SE" not in name:
        return (0, 0)
    return None


candidates = []
for key, items in devices.items():
    version = runtime_version(key)
    if version is None:
        continue
    for d in items:
        if not d.get("isAvailable", True):
            continue
        s = score(d["name"])
        if s is not None:
            candidates.append((version, s, d["name"], d["udid"]))

if not candidates:
    sys.exit("No available iPhone simulator found:\n" + raw[:4000])

candidates.sort(reverse=True)
version, _, name, udid = candidates[0]
print(f"udid={udid}")
print(f"name={name} (iOS {'.'.join(map(str, version))})")
