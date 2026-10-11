#!/usr/bin/env python3
"""Validate without mutating release files; emit the existing feed for merging."""
import pathlib
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
NS = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}

def validate(version, build, feed, output_root):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[1-9]\d*', build):
        raise ValueError('Invalid version/build')
    output_root = pathlib.Path(output_root)
    if (output_root / ('v' + version)).exists():
        raise ValueError('Release directory already exists; do not overwrite a prepared release')
    feeds = [ET.fromstring(feed)]
    feeds.extend(ET.parse(path).getroot() for path in output_root.glob('*/appcast.xml'))
    highest = 0
    for root in feeds:
        for item in root.findall('./channel/item'):
            existing = item.findtext('sparkle:version', namespaces=NS)
            if existing and existing.isdigit():
                highest = max(highest, int(existing))
            if item.findtext('sparkle:shortVersionString', namespaces=NS) == version:
                raise ValueError('This version is already published or prepared')
    if int(build) <= highest:
        raise ValueError(f'Build must exceed existing build {highest}')
    return feed

if __name__ == '__main__':
    try:
        with urllib.request.urlopen('https://raw.githubusercontent.com/pskishere/Snaplet/main/appcast.xml', timeout=20) as response:
            feed = response.read()
        sys.stdout.buffer.write(validate(sys.argv[1], sys.argv[2], feed, ROOT / 'dist/releases'))
    except Exception as error:
        print(f'Release validation failed: {error}', file=sys.stderr)
        sys.exit(1)
