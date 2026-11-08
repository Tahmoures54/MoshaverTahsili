#!/usr/bin/env python3
"""Surface Flutter analyzer locations in GitHub's check annotations."""
import re
import sys
from pathlib import Path

pattern = re.compile(r'^\s*(error|warning|info)\s+•\s+(.*?)\s+•\s+([^:]+):(\d+):(\d+)\s+•\s+(.*)$')
count = 0
for line in Path(sys.argv[1]).read_text().splitlines():
    match = pattern.match(line)
    if match and count < 40:
        level, message, file, line_no, column, code = match.groups()
        print(f'::{level} file={file},line={line_no},col={column}::{message} ({code})')
        count += 1

if count == 0:
    lines = [line.strip() for line in Path(sys.argv[1]).read_text().splitlines() if line.strip()]
    for line in lines[-40:]:
        print(f'::error file=.github/workflows/build-apk.yml,line=62::ANALYZE: {line[:900]}')
#!/usr/bin/env python3
"""Surface Flutter analyzer locations in GitHub's check annotations."""
import re
import sys
from pathlib import Path

pattern = re.compile(r'^\s*(error|warning|info)\s+•\s+(.*?)\s+•\s+([^:]+):(\d+):(\d+)\s+•\s+(.*)$')
count = 0
for line in Path(sys.argv[1]).read_text().splitlines():
    match = pattern.match(line)
    if match and count < 40:
        level, message, file, line_no, column, code = match.groups()
        print(f'::{level} file={file},line={line_no},col={column}::{message} ({code})')
        count += 1

if count == 0:
    lines = [line.strip() for line in Path(sys.argv[1]).read_text().splitlines() if line.strip()]
    for line in lines[-40:]:
        print(f'::error file=.github/workflows/build-apk.yml,line=62::ANALYZE: {line[:900]}')
