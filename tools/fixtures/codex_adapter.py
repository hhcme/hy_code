#!/usr/bin/env python3
"""Bounded stdio substitute. No network, project execution, GUI, or user data."""
import json
import os
import sys


def send(value):
    sys.stdout.write(json.dumps(value) + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    request_id = message.get("id")
    if method == "echo":
        result = message.get("params")
    elif method == "environment":
        result = {key: os.environ.get(key) for key in message["params"]}
    elif method == "broken":
        sys.stdout.write("invalid json\n")
        sys.stdout.flush()
        continue
    elif method == "oversized":
        sys.stdout.write("x" * (2 * 1024 * 1024 + 1))
        sys.stdout.flush()
        continue
    elif method == "wait":
        continue
    elif method == "reverse":
        send({"id": "approval-fixture", "method": "item/commandExecution/requestApproval", "params": {"command": "echo fixture"}})
        result = {"ready": True}
    else:
        result = {}
    if request_id is not None:
        send({"id": request_id, "result": result})
