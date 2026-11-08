#!/usr/bin/env python3
"""Measure actual release containers, not source-tree guesses."""
import hashlib
import json
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

source, destination = map(Path, sys.argv[1:3])
destination.mkdir(parents=True, exist_ok=True)
results = []
for path in sorted(source.iterdir()):
    if path.suffix not in {'.apk', '.aab'}:
        continue
    groups = defaultdict(lambda: {'compressed_bytes': 0, 'uncompressed_bytes': 0, 'entries': 0})
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = entry.filename
            if name.startswith('lib/'):
                group = 'native/' + name.split('/')[1]
            elif name.endswith('.dex'):
                group = 'dex'
            elif name.startswith(('assets/', 'res/', 'resources.arsc')) or name.startswith('base/assets/'):
                group = 'assets_resources'
            elif name.startswith('META-INF/') or name.endswith(('.RSA', '.SF', '.MF')):
                group = 'signing_metadata'
            else:
                group = 'other'
            item = groups[group]
            item['compressed_bytes'] += entry.compress_size
            item['uncompressed_bytes'] += entry.file_size
            item['entries'] += 1
    results.append({'file': path.name, 'file_bytes': path.stat().st_size,
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'sections': dict(groups)})
if not results:
    raise SystemExit('No APK/AAB files found')
(destination / 'sizes.json').write_text(json.dumps(results, indent=2))
lines = ['## Actual Android artifact sizes', '', '| File | MiB | Largest section (compressed KiB) |', '|---|---:|---|']
for item in results:
    largest = max(item['sections'].items(), key=lambda pair: pair[1]['compressed_bytes'])
    lines.append(f'| `{item["file"]}` | {item["file_bytes"] / 1048576:.2f} | `{largest[0]}`: {largest[1]["compressed_bytes"] / 1024:.1f} |')
lines += ['', 'Native Flutter/Bazaar libraries usually dominate. Split APKs reduce installed download size; an AAB lets a store deliver the device architecture. Full per-entry measurements and SHA-256 hashes are in `sizes.json`.', '', 'These are build measurements, not a claim of installation or payment testing.']
(destination / 'summary.md').write_text('\n'.join(lines) + '\n')
print('\n'.join(lines))
