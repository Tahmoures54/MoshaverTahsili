#!/usr/bin/env python3
import os
import sys
from pathlib import Path

report = Path(sys.argv[1]).read_text()
if 'Verifies' not in report:
    raise SystemExit('APK signature verification did not succeed')
debug = 'CN=Android Debug' in report
if os.environ.get('PRODUCTION_READY') == 'true' and debug:
    raise SystemExit('A production build must not use the Android debug certificate')
print('APK signature verifies. Certificate type:', 'DEBUG TEST BUILD' if debug else 'private release certificate')
