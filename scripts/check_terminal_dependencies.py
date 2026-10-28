#!/usr/bin/env python3
"""Offline Swift terminal lock/notice verification. No shell, GUI, or network."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    inventory = json.loads((ROOT / "third_party/terminal-dependencies.json").read_text())
    pins = {item["identity"]: item for item in json.loads((ROOT / "Package.resolved").read_text())["pins"]}
    assert set(pins) == {item["identity"] for item in inventory["packages"]}, "Unrecorded Swift dependency"
    for item in inventory["packages"]:
        pin = pins[item["identity"]]
        assert pin["state"]["version"] == item["version"]
        assert pin["state"]["revision"] == item["revision"]
        assert pin["location"] == item["source"]
        for notice in item["notices"]:
            path = (ROOT / notice["path"]).resolve()
            path.relative_to(ROOT / "third_party/licenses")
            assert hashlib.sha256(path.read_bytes()).hexdigest() == notice["sha256"], notice["path"]
    print("PASS: pinned terminal Swift dependencies and original notices")


if __name__ == "__main__":
    main()
