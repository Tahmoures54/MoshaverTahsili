#!/usr/bin/env python3
"""Convert Flutter analyzer output into accurate GitHub annotations."""
import re
import sys
from pathlib import Path

location_pattern = re.compile(r"^(.*):(\d+):(\d+)$")
path = Path(sys.argv[1])
annotations = 0

for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
    parts = [part.strip() for part in raw_line.split(" • ")]
    if len(parts) < 4 or parts[0] not in {"error", "warning", "info"}:
        continue
    location = location_pattern.match(parts[-2])
    if not location:
        continue
    file_name, line_number, column = location.groups()
    level = {"error": "error", "warning": "warning", "info": "notice"}[parts[0]]
    message = parts[1].replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    code = parts[-1]
    print(
        f"::{level} file={file_name},line={line_number},col={column}::"
        f"{message} ({code})"
    )
    annotations += 1

if annotations == 0:
    print("::notice::Flutter analyzer produced no parseable diagnostic lines.")
