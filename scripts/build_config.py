#!/usr/bin/env python3
"""Report configuration presence only; never print secret values."""
import os
import re
import sys
from pathlib import Path

SIGNING = ['RELEASE_KEYSTORE_BASE64', 'RELEASE_KEYSTORE_PASSWORD', 'RELEASE_KEY_ALIAS', 'RELEASE_KEY_PASSWORD']
REQUIRED = SIGNING + ['AI_API_KEY', 'BAZAAR_RSA_PUBLIC_KEY']
version = re.search(r'^version:\s*([^\s+]+)\+(\d+)', Path('pubspec.yaml').read_text(), re.M)
if not version:
    raise SystemExit('Invalid pubspec version')
ready = all(os.environ.get(name, '').strip() for name in REQUIRED) and os.environ.get('BAZAAR_CATALOG_CONFIRMED') == 'true'
if '--summary' in sys.argv:
    print('## Build configuration (presence only)\n')
    print(f'- Version: `{version[1]}`; build: `{version[2]}`')
    print(f'- Production inputs complete: **{str(ready).lower()}**')
    for name in REQUIRED:
        print(f'- `{name}`: {"present" if os.environ.get(name, "").strip() else "MISSING"}')
    print(f'- `BAZAAR_CATALOG_CONFIRMED`: {str(os.environ.get("BAZAAR_CATALOG_CONFIRMED") == "true").lower()}')
    print('\nNo secret values are included in this report. A test build is not a production release.')
else:
    print(f'version={version[1]}')
    print(f'build_number={version[2]}')
    print(f'production_ready={str(ready).lower()}')
