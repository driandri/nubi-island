import json
import os
import pathlib
import sys
import time
import uuid


def first_string(payload, *keys):
    for key in keys:
        value = payload.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def main():
    if len(sys.argv) != 3:
        return
    provider, event = sys.argv[1:]
    if provider not in {"claude", "codex", "gemini"}:
        return
    try:
        payload = json.loads(sys.stdin.read(1048576))
    except (ValueError, OSError):
        return
    if not isinstance(payload, dict):
        return

    raw_name = payload.get("tool_name") or payload.get("toolName")
    name = raw_name[:80] if isinstance(raw_name, str) else ""
    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
    response = payload.get("tool_response") or payload.get("toolResponse")
    if event in {"PostToolUse", "AfterTool"} and isinstance(response, dict):
        if response.get("isError") is True or response.get("error"):
            event += "Failure"
    filename = ""
    if isinstance(tool_input, dict):
        path = tool_input.get("file_path") or tool_input.get("path") or ""
        if isinstance(path, str):
            candidate = pathlib.Path(path).name[:80]
            if candidate and not candidate.startswith("."):
                filename = candidate
    detail = " · ".join(part for part in (name, filename) if part)
    record = {
        "provider": provider,
        "event": event,
        "session": first_string(payload, "session_id", "sessionId", "thread_id")[:100],
        "cwd": first_string(payload, "cwd")[:1024],
        "detail": detail,
        "time": time.time(),
    }
    folder = pathlib.Path.home() / "Library" / "Application Support" / "Notch" / "agent-events"
    try:
        folder.mkdir(mode=0o700, parents=True, exist_ok=True)
        identifier = uuid.uuid4().hex
        temporary = folder / ("." + identifier + ".tmp")
        target = folder / (str(time.time_ns()) + "-" + identifier + ".json")
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(record, stream, separators=(",", ":"))
        os.replace(temporary, target)
    except OSError:
        if "temporary" in locals():
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass


if __name__ == "__main__":
    main()
