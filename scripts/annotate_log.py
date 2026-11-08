#!/usr/bin/env python3
"""Expose CI failure tails as GitHub annotations and job summary (no secrets expected)."""
import os
import re
import sys
from pathlib import Path

summary_path = os.environ.get('GITHUB_STEP_SUMMARY')
summary = open(summary_path, 'a') if summary_path else None
if summary:
    summary.write('\n## Failure diagnostics\n')
for name in sys.argv[1:]:
    path = Path(name)
    if not path.exists():
        continue
    raw = path.read_text(errors='replace')
    raw = re.sub(r'\x1b\[[0-9;]*m', '', raw)
    lines = raw.splitlines()
    pattern = re.compile(r'The following|Exception|Error|FAILED|Expected|Actual|Which|test description|was thrown|assertion|Bad state|Looking up|setState|dispose|timeout|Failed to', re.I)
    selected = []
    for index, line in enumerate(lines):
        if pattern.search(line):
            selected.extend(lines[max(0, index - 2):index + 8])
    deduped = []
    seen = set()
    for line in selected + lines[-20:]:
        if line not in seen:
            seen.add(line)
            deduped.append(line)
    tail = deduped[:160]
    if summary:
        summary.write(f'\n### {path.name}\n\n```text\n')
        summary.write('\n'.join(tail))
        summary.write('\n```\n')
    for line in tail:
        if not line.strip():
            continue
        safe = line.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print(f'::error file=integration_test/app_test.dart,line=1::{safe[:900]}')
if summary:
    summary.close()
