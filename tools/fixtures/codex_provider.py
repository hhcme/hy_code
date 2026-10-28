#!/usr/bin/env python3
"""Loopback-only Responses fixture. No external requests, tools or user projects."""
import http.server
import json
from pathlib import Path
import sys
import uuid

directory = Path(sys.argv[1])


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 1024 * 1024 or self.path != "/v1/responses":
            self.send_error(400)
            return
        request = json.loads(self.rfile.read(length))
        reply_policy = "Do not turn greetings into a catalog of abilities."
        policy_on_wire = reply_policy in str(request.get("instructions", "")) or any(
            entry.get("role") in ("system", "developer") and reply_policy in json.dumps(entry)
            for entry in request.get("input", [])
        )
        with (directory / "requests.jsonl").open("a") as stream:
            stream.write(json.dumps({"model": request.get("model"), "input": request.get("input"), "reasoning": request.get("reasoning"),
                                     "authorizationOK": self.headers.get("Authorization") == "Bearer hycode-fixture-only",
                                     "hycodeReplyPolicy": policy_on_wire}) + "\n")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Connection", "close")
        self.end_headers()
        item = {"id": "msg_" + uuid.uuid4().hex, "type": "message", "role": "assistant", "status": "completed",
                "content": [{"type": "output_text", "text": "HYCODE_CODEX_PROBE_OK", "annotations": []}]}
        inputs = request.get("input", [])
        last_user = next((entry for entry in reversed(inputs) if entry.get("role") == "user"), {})
        user_text = json.dumps(last_user)
        cancellation = "HYCODE_CANCEL_PROBE" in user_text
        tool_probe = "HYCODE_TOOL_PROBE" in user_text or cancellation
        call_id = "call_cancel_fixture" if cancellation else "call_tool_fixture"
        has_output = any(entry.get("type") == "function_call_output" and entry.get("call_id") == call_id for entry in inputs)
        if tool_probe and not has_output:
            project = directory / "project"
            command = ('if [ -n "${HYCODE_CODEX_API_KEY-}" ]; then printf ENV_LEAK; exit 1; fi; '
                       'printf HYCODE_ENV_OK; printf HYCODE_TOOL_PROBE; cat sample.txt; printf wrote > owned-by-agent.txt')
            if cancellation:
                command = "printf '%s' $$ > owned-shell.pid; sleep 12; printf LATE > late-marker"
            arguments = json.dumps({"cmd": command, "workdir": str(project), "yield_time_ms": 1000, "max_output_tokens": 1000})
            item = {"type": "function_call", "id": "fc_" + call_id, "call_id": call_id, "name": "exec_command",
                    "arguments": arguments, "status": "completed"}
        response = {"id": "resp_" + uuid.uuid4().hex, "object": "response", "status": "completed",
                    "model": request.get("model"), "output": [item],
                    "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2,
                              "input_tokens_details": {"cached_tokens": 0}, "output_tokens_details": {"reasoning_tokens": 0}}}
        if item["type"] == "function_call":
            events = [
                {"type": "response.created", "response": {**response, "status": "in_progress", "output": []}},
                {"type": "response.output_item.added", "output_index": 0, "item": {**item, "status": "in_progress", "arguments": ""}},
                {"type": "response.function_call_arguments.delta", "item_id": item["id"], "output_index": 0, "delta": item["arguments"]},
                {"type": "response.function_call_arguments.done", "item_id": item["id"], "output_index": 0, "arguments": item["arguments"]},
                {"type": "response.output_item.done", "output_index": 0, "item": item},
                {"type": "response.completed", "response": response},
            ]
        else:
            events = [
            {"type": "response.created", "response": {**response, "status": "in_progress", "output": []}},
            {"type": "response.output_item.added", "output_index": 0, "item": {**item, "status": "in_progress", "content": []}},
            {"type": "response.content_part.added", "item_id": item["id"], "output_index": 0, "content_index": 0,
             "part": {"type": "output_text", "text": "", "annotations": []}},
            {"type": "response.output_text.delta", "item_id": item["id"], "output_index": 0, "content_index": 0, "delta": "HYCODE_CODEX_PROBE_OK"},
            {"type": "response.output_text.done", "item_id": item["id"], "output_index": 0, "content_index": 0, "text": "HYCODE_CODEX_PROBE_OK"},
            {"type": "response.output_item.done", "output_index": 0, "item": item},
            {"type": "response.completed", "response": response},
            ]
        for event in events:
            self.wfile.write(("event: " + event["type"] + "\ndata: " + json.dumps(event) + "\n\n").encode())
            self.wfile.flush()


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
(directory / "port").write_text(str(server.server_port))
server.serve_forever()
