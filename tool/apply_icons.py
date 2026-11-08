#!/usr/bin/env python3
"""Apply pre-generated launcher icons into android/app/src/main/res.

Usage:
  python3 tool/apply_icons.py

Or (preferred if Flutter SDK is available):
  flutter pub get && dart run flutter_launcher_icons
"""
import json
import base64
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tool = Path(__file__).parent
payload = {}
for f in sorted(tool.glob("icons_*.json")):
    if f.name == "icons_payload.json":
        continue
    payload.update(json.loads(f.read_text()))

combined = tool / "icons_payload.json"
if combined.exists() and not payload:
    payload = json.loads(combined.read_text())

if not payload:
    print("No icon payload found. Run: dart run flutter_launcher_icons")
    raise SystemExit(1)

for rel, b64 in payload.items():
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(base64.b64decode(b64))
    print("wrote", rel, path.stat().st_size)
print("Done. Icons applied.")
