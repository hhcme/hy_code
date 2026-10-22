#!/usr/bin/env python3
"""Check repository-local Markdown links and immutable history snapshots.

Requires Python 3.9+ and its standard library. No network or application launch.
Only inline Markdown links are checked; fenced and inline code are ignored.
URL fragments and external URLs are not validated.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
IGNORED_PARTS = {".git", ".v2c", "__pycache__", "build", "target", ".build", "node_modules"}
LINK = re.compile(r"!?\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|([^\s)\n]+))(?:\s+[\"'][^\n]*?[\"'])?\s*\)")
INLINE_CODE = re.compile(r"(`+).*?\1")
FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")


def prose_lines(text: str):
    """Yield source line numbers and prose without fenced/inline code."""
    fence_char = None
    fence_length = 0
    for number, line in enumerate(text.splitlines(), 1):
        marker = FENCE.match(line)
        if fence_char is not None:
            if marker:
                token = marker.group(1)
                if token[0] == fence_char and len(token) >= fence_length and not line[marker.end():].strip():
                    fence_char = None
            continue
        if marker:
            token = marker.group(1)
            fence_char, fence_length = token[0], len(token)
            continue
        yield number, INLINE_CODE.sub("", line)


def check_links(path: Path, text: str) -> tuple[list[str], int]:
    errors = []
    checked = 0
    for number, line in prose_lines(text):
        for match in LINK.finditer(line):
            destination = match.group(1) or match.group(2)
            url = urlsplit(destination)
            if url.scheme or url.netloc or not url.path:
                continue
            checked += 1
            local_path = unquote(url.path)
            target = (ROOT / local_path.lstrip("/") if local_path.startswith("/") else path.parent / local_path).resolve()
            try:
                target.relative_to(ROOT)
            except ValueError:
                errors.append(f"{path.relative_to(ROOT)}:{number}: link escapes repository: {destination}")
                continue
            if not target.exists():
                errors.append(f"{path.relative_to(ROOT)}:{number}: missing link target: {destination}")
    return errors, checked


def check_history() -> tuple[list[str], int]:
    manifest_path = ROOT / "docs/history/2026-10-21-file-viewer/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    errors = []
    documents = manifest["documents"]
    for entry in documents:
        path = (ROOT / entry["archivedPath"]).resolve()
        path.relative_to(manifest_path.parent)
        content = path.read_bytes()
        if hashlib.sha256(content).hexdigest() != entry["archivedSHA256"]:
            errors.append(f"{entry['archivedPath']}: archived SHA-256 mismatch")
        banner, separator, original = content.partition(b"\n\n")
        if not separator or not banner.startswith("> 历史快照：".encode("utf-8")):
            errors.append(f"{entry['archivedPath']}: missing history banner")
        elif hashlib.sha256(original).hexdigest() != entry["originalSHA256"]:
            errors.append(f"{entry['archivedPath']}: original SHA-256 mismatch")
    return errors, len(documents)


def main() -> int:
    errors = []
    link_count = 0
    files = sorted(path for path in ROOT.rglob("*.md") if not IGNORED_PARTS.intersection(path.relative_to(ROOT).parts))
    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
            found, count = check_links(path, text)
            errors.extend(found)
            link_count += count
        except (OSError, UnicodeError, ValueError) as error:
            errors.append(f"{path.relative_to(ROOT)}: {error}")
    history_count = 0
    try:
        found, history_count = check_history()
        errors.extend(found)
    except (OSError, UnicodeError, ValueError, KeyError, TypeError) as error:
        errors.append(f"history manifest: {error}")
    if errors:
        print("Documentation checks failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"PASS: {len(files)} Markdown files, {link_count} local links, {history_count} original/archive SHA-256 pairs")
    print("No application build, GUI, network or external-link validation performed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
