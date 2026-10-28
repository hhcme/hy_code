#!/usr/bin/env python3
"""Prepare/check the pinned official CLI; never installs a global command or runs it.

setup is an explicit network preparation step. check and stage are offline.
Only four allowlisted files are distributed; voice resources are not included.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tools/codex-runtime/manifest.json"
RUNTIME = ROOT / ".build/codex-runtime"
FILES = {"bin/codex", "bin/codex-code-mode-host", "codex-path/rg", "codex-package.json"}


def digest(path: Path, algorithm: str = "sha256") -> bytes:
    result = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.digest()


def manifest() -> dict:
    value = json.loads(MANIFEST.read_text())
    if value["version"] != "0.164.0" or len(value["files"]) != 4 or {entry["path"] for entry in value["files"]} != FILES:
        raise ValueError("Unexpected runtime version or file list")
    if value["archive"] != "https://registry.npmjs.org/@openai/codex/-/codex-0.164.0-darwin-arm64.tgz":
        raise ValueError("Unexpected official archive URL")
    return value


def check(directory: Path, value: dict) -> None:
    for entry in value["files"]:
        path = directory / entry["path"]
        if path.is_symlink() or not path.is_file() or digest(path).hex() != entry["sha256"]:
            raise ValueError(f"Missing or invalid runtime file: {entry['path']}; run python3 scripts/codex_runtime.py setup")
        if entry["path"] != "codex-package.json" and not os.access(path, os.X_OK):
            raise ValueError(f"Runtime file is not executable: {entry['path']}")
    for entry in value["notices"]:
        source = ROOT / "third_party/licenses/codex-0.164.0" / entry["path"]
        if not source.is_file() or digest(source).hex() != entry["sha256"]:
            raise ValueError(f"Missing or changed upstream notice: {entry['path']}")


def setup(value: dict) -> None:
    try:
        check(RUNTIME, value)
        shutil.copyfile(MANIFEST, RUNTIME / "manifest.json")
        return
    except ValueError:
        pass
    cache = ROOT / ".build/codex-downloads"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / "codex-0.164.0-darwin-arm64.tgz"
    expected = value["integrity"].removeprefix("sha512-")
    if not archive.is_file() or base64.b64encode(digest(archive, "sha512")).decode() != expected:
        temporary = cache / ".download"
        try:
            print("Downloading pinned official Codex runtime (about 135 MiB compressed).", flush=True)
            with urllib.request.urlopen(value["archive"], timeout=30) as response, temporary.open("wb") as output:
                total = 0
                while chunk := response.read(1024 * 1024):
                    total += len(chunk)
                    if total > 160 * 1024 * 1024:
                        raise ValueError("Runtime archive exceeds download budget")
                    output.write(chunk)
            if base64.b64encode(digest(temporary, "sha512")).decode() != expected:
                raise ValueError("Official archive integrity mismatch")
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix="codex-stage-", dir=ROOT / ".build") as temporary:
        stage = Path(temporary)
        with tarfile.open(archive, "r:gz") as bundle:
            for name in FILES:
                member = bundle.getmember("package/vendor/aarch64-apple-darwin/" + name)
                if not member.isfile() or member.size > 300 * 1024 * 1024:
                    raise ValueError("Invalid runtime archive member")
                destination = stage / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                with bundle.extractfile(member) as source, destination.open("wb") as output:
                    shutil.copyfileobj(source, output, 1024 * 1024)
                destination.chmod(0o644 if name == "codex-package.json" else 0o755)
        shutil.copyfile(MANIFEST, stage / "manifest.json")
        check(stage, value)
        if RUNTIME.exists():
            shutil.rmtree(RUNTIME)
        shutil.copytree(stage, RUNTIME)


def main() -> None:
    value = manifest()
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    if command == "setup":
        setup(value)
    elif command == "stage" and len(sys.argv) == 3:
        check(RUNTIME, value)
        destination = Path(sys.argv[2]).resolve()
        if not destination.is_relative_to(ROOT / "build"):
            raise ValueError("Staging destination must be inside this repository's build directory")
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(RUNTIME, destination)
        shutil.copyfile(MANIFEST, destination / "manifest.json")
    elif command != "check":
        raise ValueError("Usage: codex_runtime.py [setup|check|stage build/path]")
    check(RUNTIME, value)
    print("PASS: pinned Codex 0.164.0, four official runtime files; no CLI execution, GUI or global installation")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
