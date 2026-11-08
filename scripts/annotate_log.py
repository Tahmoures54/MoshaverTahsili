#!/usr/bin/env python3
"""Expose CI failure tails as GitHub annotations and job summary (no secrets expected)."""
import os
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
    lines = path.read_text(errors='replace').splitlines()
    tail = lines[-80:]
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
