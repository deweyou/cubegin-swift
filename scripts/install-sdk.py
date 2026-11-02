#!/usr/bin/env python3
"""Install an extracted, versioned Cubegin SDK package into this repository."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile

source = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else None
if source is None:
    raise SystemExit('Usage: python3 scripts/install-sdk.py /path/to/CubeginSDK-0.1.0')
metadata = json.loads((source / 'SDK.json').read_text())
if metadata['schemaVersion'] != 1:
    raise SystemExit('Unsupported SDK metadata version')
for name, expected in metadata['files'].items():
    path = (source / name).resolve()
    if not path.is_relative_to(source) or not path.is_file():
        raise SystemExit(f'Invalid SDK file: {name}')
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit(f'SDK checksum mismatch: {name}')
root = Path(__file__).resolve().parents[1]
vendor = root / 'Vendor'
vendor.mkdir(exist_ok=True)
destination = vendor / 'CubeginSDK'
with tempfile.TemporaryDirectory(dir=vendor) as temporary:
    staged = Path(temporary) / 'CubeginSDK'
    staged.mkdir()
    # Install only files listed in the verified manifest, plus the manifest itself.
    for name in [*metadata['files'], 'SDK.json']:
        target = staged / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, target)
    if destination.exists():
        backup = Path(temporary) / 'previous'
        destination.rename(backup)
        try:
            staged.rename(destination)
        except BaseException:
            backup.rename(destination)
            raise
    else:
        staged.rename(destination)
print(f'Installed Cubegin SDK {metadata["version"]} from {metadata["sourceCommit"]} (dirty={metadata["sourceDirty"]})')
