#!/usr/bin/env python3
"""Verify Native language additions against Cargo.lock and original notices. No I/O outside repo."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent


def main():
    inventory = json.loads((ROOT / "third_party/native-language-crates.json").read_text())
    locked = {}
    for block in (ROOT / "Cargo.lock").read_text().split("[[package]]")[1:]:
        fields = dict(re.findall(r'^([a-z_]+) = "([^"\n]+)"$', block, re.M))
        locked[(fields["name"], fields["version"])] = fields
    seen = set()
    for item in inventory["packages"]:
        key = (item["name"], item["version"])
        assert key not in seen, "Duplicate dependency inventory entry"
        seen.add(key)
        entry = locked[key]
        assert entry["checksum"] == item["checksum"] and entry["source"] == item["source"], key
        assert item["notices"], key
        for notice in item["notices"]:
            path = (ROOT / notice["path"]).resolve()
            path.relative_to(ROOT / "third_party/licenses")
            assert hashlib.sha256(path.read_bytes()).hexdigest() == notice["sha256"], notice["path"]
    assert {("sqlparser", "0.63.0"), ("tree-sitter-java", "0.23.5"), ("tree-sitter-swift", "0.7.4"), ("tree-sitter-sequel", "0.3.11")} <= seen
    print("PASS: {} pinned native-language crates and retained notices".format(len(seen)))


if __name__ == "__main__":
    main()
