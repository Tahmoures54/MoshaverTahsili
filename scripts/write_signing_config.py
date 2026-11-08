#!/usr/bin/env python3
import os
from pathlib import Path

def escape(value: str) -> str:
    return value.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace('=', '\\=').replace(':', '\\:').replace(' ', '\\ ')

lines = [f'storePassword={escape(os.environ["RELEASE_KEYSTORE_PASSWORD"])}',
         f'keyPassword={escape(os.environ["RELEASE_KEY_PASSWORD"])}',
         f'keyAlias={escape(os.environ["RELEASE_KEY_ALIAS"])}', 'storeFile=upload-keystore.jks']
path = Path('android/key.properties')
path.write_text('\n'.join(lines) + '\n')
path.chmod(0o600)
print('Private signing configuration prepared; values are not logged.')
