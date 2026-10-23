#!/usr/bin/env python3
"""Owned stdio build-info fixture; no build, shell, app, plugin or network."""
import json
import pathlib
import sys

root, source, sdk, cache = map(pathlib.Path, sys.argv[1:5])
toolchain = pathlib.Path(sys.argv[5]) if len(sys.argv) > 5 else pathlib.Path("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain")
cache.mkdir(parents=True, exist_ok=True)
target = {"uri": "hycode-bsp-fixture:///library"}

def send(message):
    data = json.dumps(message, ensure_ascii=False).encode()
    sys.stdout.buffer.write(b"Content-Length: " + str(len(data)).encode() + b"\r\n\r\n" + data)
    sys.stdout.buffer.flush()

while True:
    header = sys.stdin.buffer.readline()
    if not header:
        break
    length = 0
    while header.strip():
        key, _, value = header.partition(b":")
        if key.lower() == b"content-length":
            length = int(value)
        header = sys.stdin.buffer.readline()
    if not 0 < length <= 4 * 1024 * 1024:
        break
    message = json.loads(sys.stdin.buffer.read(length))
    method = message.get("method", "")
    with (cache / "requests.log").open("a") as log:
        log.write(method[:200] + "\n")
    if method == "build/exit":
        break
    if "id" not in message:
        continue
    result = None
    if method == "build/initialize":
        result = {"displayName": "HyCode Owned Build-Info Fixture", "version": "1", "bspVersion": "2.2.0", "capabilities": {}, "dataKind": "sourceKit", "data": {"sourceKitOptionsProvider": True, "prepareProvider": False, "indexStorePath": str(cache / "index-store"), "indexDatabasePath": str(cache / "index-db")}}
    elif method == "workspace/buildTargets":
        result = {"targets": [{"id": target, "displayName": "OwnedLibrary", "baseDirectory": root.as_uri(), "tags": ["library"], "languageIds": ["swift"], "dependencies": [], "capabilities": {"canCompile": True, "canTest": False, "canRun": False, "canDebug": False}, "dataKind":"sourceKit", "data":{"toolchain":toolchain.as_uri()}}]}
    elif method == "buildTarget/sources":
        result = {"items": [{"target": target, "sources": [{"uri": source.as_uri(), "kind": 1, "generated": False}], "roots": [root.as_uri()]}]}
    elif method in ("textDocument/sourceKitOptions", "sourcekit/textDocument/sourceKitOptions"):
        result = {"compilerArguments": ["-module-name", "OwnedLibrary", "-parse-as-library", "-target", "arm64-apple-macosx14.0", "-sdk", str(sdk), "-DHYCODE_BSP_FIXTURE", str(source)], "workingDirectory": str(root)}
    send({"jsonrpc": "2.0", "id": message["id"], "result": result})
