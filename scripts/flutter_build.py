#!/usr/bin/env python3
"""Run a Flutter Android build with redacted, uploadable diagnostics."""
import os
import re
import subprocess
import sys
from pathlib import Path

args = sys.argv[1:]
secrets = [os.environ.get(name, '') for name in ['AI_API_KEY', 'DEEPSEEK_API_KEY', 'AI_API_ENDPOINT', 'DEEPSEEK_API_ENDPOINT',
    'AI_MODEL', 'DEEPSEEK_MODEL', 'BAZAAR_RSA_PUBLIC_KEY', 'RELEASE_KEYSTORE_BASE64',
    'RELEASE_KEYSTORE_PASSWORD', 'RELEASE_KEY_ALIAS', 'RELEASE_KEY_PASSWORD']]
secrets = sorted((value for value in secrets if value), key=len, reverse=True)
def redact(line: str) -> str:
    for value in secrets:
        line = line.replace(value, '[REDACTED]')
    return re.sub(r'Bearer\s+[A-Za-z0-9._~+/-]+', 'Bearer [REDACTED]', line)

directory = Path('build/reports/android')
directory.mkdir(parents=True, exist_ok=True)
label = args[0] + ('-split' if '--split-per-abi' in args else '-universal' if args[0] == 'apk' else '')
log = directory / f'build-{label}.txt'
print('Running Flutter Android build:', ' '.join(arg.split('=')[0] + '=...' if arg.startswith('--dart-define-from-file=') else arg for arg in args))
with log.open('w') as output:
    process = subprocess.Popen(['flutter', 'build', *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    assert process.stdout is not None
    for raw in process.stdout:
        line = redact(raw.rstrip('\n'))
        print(line, flush=True)
        output.write(line + '\n')
    result = process.wait()
if result:
    count = 0
    for line in log.read_text().splitlines():
        if count < 30 and re.search(r'^e:|error:|FAILURE:|What went wrong|Could not|Execution failed|Gradle task .* failed|Exception:', line, re.I):
            print(f'::error::{line[:900]}')
            count += 1
raise SystemExit(result)
