#!/usr/bin/env python3
"""Drive Studio through the bridge from the shell (works even when the MCP tools are not loaded).

  python3 tools/studio.py play | stop | state | console
  python3 tools/studio.py luau <Edit|Server|Client> <file.luau | ->   # run Luau, print the result
  python3 tools/studio.py shot <out.png>                             # screenshot, then Read the PNG
  add --studio "<name>" before the command when several Studios are open

Test recipe: stop -> deploy_luau.py -> play -> wait ~10 s -> luau Client <script that calls the
game's own remotes> -> shot -> console (filter out 'ContentId' noise) -> stop.
Code run with `luau` gets its own copy of ModuleScripts (separate VM): to steer the running client
(camera, panels, time of day) give it Studio-only attribute hooks and set those attributes instead.
"""
import base64, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export_studio as E  # noqa: E402

args = sys.argv[1:]
want = None
if args[:1] == ["--studio"]:
    want, args = args[1], args[2:]
if not args:
    sys.exit(__doc__)
b = E.Bridge()
studios = E.json_tail(b.call("list_roblox_studios", {}))["studios"]
pick = [s for s in studios if not want or want.lower() in s["name"].lower()]
if not pick:
    sys.exit("No matching Studio open (or the bridge is off).")
SID = pick[0]["id"]


def raw(name, a):
    b.n += 1
    _, d = b._post({"jsonrpc": "2.0", "id": b.n, "method": "tools/call",
                    "params": {"name": name, "arguments": dict(a, studio_id=SID)}})
    if not d or "result" not in d:
        sys.exit(f"{name} failed: {d}")
    return d["result"]["content"]


cmd = args[0]
if cmd == "luau":
    code = sys.stdin.read() if args[2] == "-" else open(args[2], encoding="utf-8").read()
    print("".join(c.get("text", "") for c in raw("execute_luau", {"datamodel_type": args[1], "code": code})))
elif cmd == "shot":
    for c in raw("screen_capture", {"capture_id": "Shot"}):
        if c.get("type") == "image":
            open(args[1], "wb").write(base64.b64decode(c["data"]))
            print("saved", args[1])
        elif c.get("text"):
            print(c["text"][:300])
elif cmd in ("play", "stop"):
    print(raw("start_stop_play", {"is_start": cmd == "play"})[0]["text"])
elif cmd == "state":
    print(raw("get_studio_state", {})[0]["text"])
elif cmd == "console":
    text = raw("get_console_output", {})[0]["text"]
    print("\n".join(l for l in text.splitlines() if "ContentId" not in l and "do_not_fallback" not in l)[-4000:])
else:
    sys.exit(__doc__)
