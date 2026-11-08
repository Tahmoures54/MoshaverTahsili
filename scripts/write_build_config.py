#!/usr/bin/env python3
"""Write compiler inputs outside the repository; never log their contents."""
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
config = {
    'AI_API_KEY': os.environ.get('AI_API_KEY', '') or os.environ.get('DEEPSEEK_API_KEY', ''),
    'AI_API_ENDPOINT': os.environ.get('AI_API_ENDPOINT', '') or os.environ.get('DEEPSEEK_API_ENDPOINT', '') or 'https://api.avalai.ir/v1',
    'AI_MODEL': os.environ.get('AI_MODEL', '') or os.environ.get('DEEPSEEK_MODEL', '') or 'deepseek-chat',
    'BAZAAR_RSA_PUBLIC_KEY': os.environ.get('BAZAAR_RSA_PUBLIC_KEY', ''),
    'BAZAAR_CATALOG_CONFIRMED': os.environ.get('BAZAAR_CATALOG_CONFIRMED') == 'true',
}
path.write_text(json.dumps(config))
path.chmod(0o600)
print('Build configuration prepared outside the source tree.')
