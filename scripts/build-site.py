#!/usr/bin/env python3
"""Build the GitHub Pages site from the shared wireframe source. No dependencies."""
from pathlib import Path
from html.parser import HTMLParser
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "dist"
template = (ROOT / "site/index.html").read_text()
fragment = (ROOT / "wireframes/disk-map-ui.html").read_text()
marker = "<!-- DISK_MAP_WIREFRAME -->"
assert template.count(marker) == 1, "Expected a single preview placeholder"
fragment = re.sub(r'<meta charset="utf-8">\s*', '', fragment, count=1)
document = template.replace(marker, fragment)
assert 'window.openai' not in document, "Public preview must not require host APIs"

# Validate every inline script before publishing.
for script in re.findall(r'<script>(.*?)</script>', document, re.S):
    with tempfile.NamedTemporaryFile(mode="w", suffix=".js") as f:
        f.write(script)
        f.flush()
        subprocess.run(["node", "--check", f.name], check=True)

OUTPUT.mkdir(exist_ok=True)
(OUTPUT / "index.html").write_text(document)
for name in ("styles.css", "favicon.svg"):
    shutil.copyfile(ROOT / "site" / name, OUTPUT / name)
(OUTPUT / ".nojekyll").write_text("")
(OUTPUT / "404.html").write_text('''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Page not found — Disk Map</title></head>
<body style="font:18px/1.6 system-ui;padding:48px"><h1>Page not found</h1><p><a href="/disk-map/">Return to Disk Map</a></p></body></html>''')

class AssetCheck(HTMLParser):
    def handle_starttag(self, tag, attributes):
        for name, value in attributes:
            if name not in ("href", "src") or not value:
                continue
            if value.startswith(("https:", "http:", "#", "data:")):
                continue
            assert (OUTPUT / value).exists(), f"Missing local asset: {value}"

AssetCheck().feed(document)
print("Built dist/: entrypoint, local assets, and JavaScript validated.")
