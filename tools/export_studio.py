#!/usr/bin/env python3
"""Export every script of an open Roblox Studio place into game/ (read-only).

One-way mirror, Studio -> repo, so graphify can map the code and Claude can
search it without dumping scripts out of Studio each session. Studio stays the
source of truth: edit there (Studio MCP), then run this again.

Needs the Roblox Studio MCP bridge (roblox-mcp-bridge/) running on the PC; in
the Heistbond Game cloud environment the proxy adds the bridge key.

Usage:
  python3 tools/export_studio.py            # first open Studio
  python3 tools/export_studio.py --list     # just list open Studios
  python3 tools/export_studio.py --studio "NFL CARD"
The code graph (graphify) is rebuilt automatically, offline.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request

URL = os.environ.get("ROBLOX_MCP_URL", "https://skinny-wages-stopped.ngrok-free.dev/mcp")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game")
SERVICES = ["Workspace", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService",
            "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "Lighting",
            "SoundService", "Teams", "TextChatService", "Chat"]
EXT = {"Script": ".server.luau", "LocalScript": ".client.luau", "ModuleScript": ".luau"}
CHUNK = 60000


class Bridge:
    def __init__(self):
        self.sid, self.n = None, 10
        self.sid, _ = self._post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "export_studio", "version": "1"}}})
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _post(self, body):
        h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.sid:
            h["Mcp-Session-Id"] = self.sid
            h["MCP-Protocol-Version"] = "2025-06-18"
        req = urllib.request.Request(URL, json.dumps(body).encode(), h)
        with urllib.request.urlopen(req, timeout=300) as r:
            txt = r.read().decode("utf-8", "replace")
            data = [l[6:] for l in txt.splitlines() if l.startswith("data: ")]
            if not data and txt.strip().startswith(("{", "[")):
                data = [txt]  # plain JSON reply (mcp-gateway.js), not an SSE stream
            return r.headers.get("Mcp-Session-Id"), (json.loads(data[-1]) if data else None)

    def call(self, name, args):
        self.n += 1
        _, d = self._post({"jsonrpc": "2.0", "id": self.n, "method": "tools/call",
                           "params": {"name": name, "arguments": args}})
        if not d or "error" in d:
            raise RuntimeError(f"{name}: {d and d.get('error')}")
        text = "".join(c.get("text", "") for c in d["result"]["content"])
        if d["result"].get("isError"):
            raise RuntimeError(f"{name}: {text[:500]}")
        return text

    def luau(self, studio, code):
        return self.call("execute_luau", {"studio_id": studio, "datamodel_type": "Edit", "code": code})


def json_tail(text):
    """execute_luau may wrap the return value; take the JSON part."""
    i = min([p for p in (text.find("{"), text.find("[")) if p >= 0], default=-1)
    return json.loads(text[i:]) if i >= 0 else json.loads(text)


LIST_CODE = r'''
local HS = game:GetService("HttpService")
local SERVICES = %s
local out = {}
for _, sv in SERVICES do
  local ok, svc = pcall(function() return game:GetService(sv) end)
  if ok and svc then
    for _, s in svc:GetDescendants() do
      if s:IsA("LuaSourceContainer") then
        local parts, o = {}, s
        while o and o ~= game do table.insert(parts, 1, o.Name) o = o.Parent end
        local ok2, src = pcall(function() return s.Source end)
        table.insert(out, {path = parts, class = s.ClassName, len = ok2 and #src or -1,
          id = s:GetDebugId(0)})
      end
    end
  end
end
return HS:JSONEncode(out)
'''

READ_CODE = r'''
local HS = game:GetService("HttpService")
local want, first, limit = "%s", %d, %d
for _, s in game:GetDescendants() do
  if s:IsA("LuaSourceContainer") and s:GetDebugId(0) == want then
    local src = s.Source
    -- end the chunk on a newline so a UTF-8 character is never cut in half
    local last = first + limit - 1
    if last < #src then last = string.find(src, "\n", last, true) or #src else last = #src end
    return HS:JSONEncode({s = string.sub(src, first, last), nxt = last + 1, total = #src})
  end
end
return HS:JSONEncode({missing = true})
'''


def safe(name):
    name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", name).strip(" .")
    return name or "_"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--studio", help="part of the Studio name to export (default: the only/first one)")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()

    b = Bridge()
    studios = json_tail(b.call("list_roblox_studios", {}))["studios"]
    if a.list or not studios:
        for s in studios:
            print(s["name"])
        if not studios:
            sys.exit("No Studio open (or the bridge is off).")
        return
    pick = [s for s in studios if not a.studio or a.studio.lower() in s["name"].lower()]
    if not pick:
        sys.exit(f"No open Studio matches {a.studio!r}: " + ", ".join(s["name"] for s in studios))
    st = pick[0]
    print("Exporting", st["name"])

    scripts = json_tail(b.luau(st["id"], LIST_CODE % json.dumps(SERVICES).replace("[", "{").replace("]", "}")))
    shutil.rmtree(OUT, ignore_errors=True)
    used, manifest = set(), []
    for s in sorted(scripts, key=lambda x: x["path"]):
        src, first, total = "", 1, max(s["len"], 0)
        while first <= total:
            part = json_tail(b.luau(st["id"], READ_CODE % (s["id"], first, CHUNK)))
            if part.get("missing"):
                raise RuntimeError("script vanished during export: " + ".".join(s["path"]))
            src += part["s"]
            first, total = part["nxt"], part["total"]
        rel = os.path.join(*[safe(p) for p in s["path"][:-1]], safe(s["path"][-1])) + EXT.get(s["class"], ".luau")
        base, k = rel, 2
        while rel.lower() in used:
            rel = base.replace(EXT.get(s["class"], ".luau"), f"~{k}" + EXT.get(s["class"], ".luau"))
            k += 1
        used.add(rel.lower())
        path = os.path.join(OUT, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(src.replace("\r\n", "\n"))
        manifest.append({"file": rel.replace(os.sep, "/"), "instance": "game." + ".".join(s["path"]),
                         "class": s["class"], "bytes": len(src.encode()),
                         "sha1": hashlib.sha1(src.encode()).hexdigest()})
        print(f"  {s['class']:<12} {len(src):>7}  {'.'.join(s['path'])}")
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "_manifest.json"), "w") as f:
        json.dump({"place": st["name"], "scripts": manifest}, f, indent=1)
    print(f"{len(manifest)} scripts written to game/.")
    # Rebuild the code graph offline (AST only; GRAPHIFY_BACKEND=none = never call an LLM)
    if shutil.which("graphify"):
        env = dict(os.environ, GRAPHIFY_BACKEND="none")
        subprocess.run(["graphify", "update", "."], cwd=ROOT, env=env, check=False)
    else:
        print("graphify not installed: pip install graphifyy, then run: graphify update .")


if __name__ == "__main__":
    main()
