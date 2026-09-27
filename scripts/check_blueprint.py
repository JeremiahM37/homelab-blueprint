#!/usr/bin/env python3
"""Validate local documentation links and the sanitized YAML examples."""
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit
import yaml

root = Path(__file__).resolve().parents[1]
errors = []
markdown = [root / 'README.md', *sorted((root / 'docs').glob('*.md')),
            root / 'terraform/README.md', root / 'ansible/README.md']
for path in markdown:
    for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', path.read_text()):
        target = target.split()[0].strip('<>')
        parsed = urlsplit(target)
        if parsed.scheme or not parsed.path:
            continue
        if not (path.parent / unquote(parsed.path)).exists():
            errors.append(f'{path.relative_to(root)}: missing {target}')
yaml_paths = [root / 'docker-compose.example.yml', *sorted((root / 'ansible').rglob('*.yml'))]
yaml_paths = [p for p in yaml_paths if p.name != 'inventory.yml']
for path in yaml_paths:
    try:
        yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        errors.append(f'{path.relative_to(root)}: {exc}')
if errors:
    raise SystemExit('\n'.join(errors))
print(f'PASS: local links in {len(markdown)} documents and {len(yaml_paths)} YAML examples')
