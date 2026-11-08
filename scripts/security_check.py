#!/usr/bin/env python3
"""Fail on tracked secret material and unsafe Android defaults (no values logged)."""
import re
import subprocess
from pathlib import Path

files = subprocess.check_output(['git', 'ls-files'], text=True).splitlines()
errors = []
for name in files:
    path = Path(name)
    if name.startswith('.env') and name != '.env.example':
        errors.append(f'Tracked environment file: {name}')
    if path.suffix in {'.jks', '.keystore', '.p12', '.pfx'}:
        errors.append(f'Tracked signing material: {name}')
    if path.suffix in {'.ttf', '.jar', '.png', '.jpg', '.webp'} or not path.exists():
        continue
    text = path.read_text(errors='replace')
    if re.search(r'\bsk-[A-Za-z0-9_-]{20,}\b', text) or re.search(r'-----BEGIN (?:RSA |EC )?PRIVATE KEY-----', text):
        errors.append(f'Potential secret material in {name}; inspect privately, do not print it')
manifest = Path('android/app/src/main/AndroidManifest.xml').read_text()
if 'android.permission.INTERNET' not in manifest:
    errors.append('AI/billing require INTERNET permission')
for permission in ['READ_CONTACTS', 'READ_SMS', 'ACCESS_FINE_LOCATION', 'READ_EXTERNAL_STORAGE', 'CAMERA', 'RECORD_AUDIO']:
    if 'android.permission.' + permission in manifest:
        errors.append('Unnecessary permission: ' + permission)
if 'android:usesCleartextTraffic="false"' not in manifest or 'android:allowBackup="false"' not in manifest:
    errors.append('Android cleartext/backup hardening is missing')
if errors:
    raise SystemExit('\n'.join(errors))
print('Tracked-source secret and Android permission checks passed. This is not a guarantee against all secret formats.')
