"""Owned stdio DAP fixture. Never launches SDKs, programs, devices or windows."""
import json
import sys

sequence = 0
launch = None
configured = False
filters = None
reverse_denied = False


def send(value):
    global sequence
    sequence += 1
    value["seq"] = sequence
    body = json.dumps(value, ensure_ascii=False).encode("utf-8")
    frame = ("Content-Length: %d\r\n\r\n" % len(body)).encode("ascii") + body
    if "--fragment" in sys.argv:
        for byte in frame:
            sys.stdout.buffer.write(bytes([byte]))
            sys.stdout.buffer.flush()
    else:
        sys.stdout.buffer.write(frame)
        sys.stdout.buffer.flush()


def respond(request, body=None, success=True):
    send({"type": "response", "request_seq": request["seq"],
          "command": request["command"], "success": success,
          "body": body or {}, "message": "fixture failure" if not success else ""})


def event(name, body=None):
    send({"type": "event", "event": name, "body": body or {}})


while True:
    length = None
    while True:
        header = sys.stdin.buffer.readline()
        if not header:
            sys.exit(0)
        if header == b"\r\n":
            break
        if header.lower().startswith(b"content-length:"):
            length = int(header.split(b":", 1)[1])
    if length is None or not 0 < length <= 8 * 1024 * 1024:
        sys.exit(2)
    message = json.loads(sys.stdin.buffer.read(length))
    if message["type"] == "response":
        reverse_denied = message.get("success") is False
        continue
    name = message["command"]
    args = message.get("arguments", {})
    if name == "initialize":
        respond(message, {"supportsConfigurationDoneRequest": True,
                          "exceptionBreakpointFilters": [{"filter": "Unhandled", "default": True}]})
        event("initialized")  # Intentionally adjacent to the response, before launch.
        send({"type": "request", "command": "runInTerminal", "arguments": {}})
    elif name == "launch":
        launch = message
    elif name == "setBreakpoints":
        points = [{"id": 1000 + i, "line": b["line"], "verified": False} for i, b in enumerate(args["breakpoints"])]
        respond(message, {"breakpoints": points})
        for point in points:
            event("breakpoint", {"reason": "changed", "breakpoint": dict(point, verified=True)})
    elif name == "setExceptionBreakpoints":
        filters = args.get("filters")
        respond(message)
    elif name == "configurationDone":
        configured = True
        respond(message)
        if launch is not None:
            respond(launch, {"configured": filters == ["Unhandled"], "reverseDenied": reverse_denied})
            event("flutter.appStarted")
    elif name == "fixtureStatus":
        respond(message, {"configured": configured, "filters": filters, "reverseDenied": reverse_denied})
    elif name == "threads":
        respond(message, {"threads": [{"id": 1, "name": "main 中"}]})
    elif name == "stackTrace":
        respond(message, {"stackFrames": [{"id": 7, "name": "main", "line": 3, "column": 1,
                                          "source": {"path": "/tmp/hycode-fixture.dart"}}]})
    elif name == "scopes":
        respond(message, {"scopes": [{"name": "Locals", "variablesReference": 8}]})
    elif name == "variables":
        respond(message, {"variables": [{"name": "answer", "value": "42", "variablesReference": 0}]})
    elif name == "evaluate":
        respond(message, {"result": "42", "variablesReference": 0})
    elif name == "pause":
        respond(message)
        event("stopped", {"reason": "pause", "threadId": 1})
    elif name in ("continue", "next", "stepIn", "stepOut", "hotReload", "hotRestart"):
        respond(message)
    elif name == "fail":
        respond(message, success=False)
    elif name == "disconnect":
        respond(message)
        event("terminated")
        break
    else:
        respond(message)
