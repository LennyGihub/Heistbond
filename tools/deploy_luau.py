#!/usr/bin/env python3
"""Push local Luau files into Studio (the fast way to write game code).

Work on a copy of game/ (same layout: <Service>/<Folder...>/<Name>.server.luau | .client.luau | .luau),
edit with normal file tools, then:

  python3 tools/deploy_luau.py --root <workdir> <file> [<file> ...]   # check + push those files
  python3 tools/deploy_luau.py --root <workdir>                       # check + push every .luau under root
  python3 tools/deploy_luau.py --root <workdir> --check <files>       # syntax check only, Studio untouched
  add --studio "<name>" when several Studios are open

Every file is syntax-checked with luau-compile first (downloaded once to ~/.cache/luau); nothing is
pushed if any file fails. Missing Folders are created; a script whose class changed is replaced.
Studio must be in Edit mode (stop a playtest first: tools/studio.py stop).
"""
import argparse, json, os, subprocess, sys, urllib.request, zipfile, io
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export_studio as E  # noqa: E402

LUAU_DIR = os.path.expanduser("~/.cache/luau")
LUAU = os.path.join(LUAU_DIR, "luau-compile")


def ensure_luau():
    if os.path.exists(LUAU):
        return
    os.makedirs(LUAU_DIR, exist_ok=True)
    url = "https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip"
    data = urllib.request.urlopen(url, timeout=120).read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        z.extractall(LUAU_DIR)
    for f in os.listdir(LUAU_DIR):
        os.chmod(os.path.join(LUAU_DIR, f), 0o755)


def target(root, f):
    rel = os.path.relpath(os.path.abspath(f), os.path.abspath(root)).split(os.sep)
    name, cls = rel[-1], "ModuleScript"
    if "~" in name:
        sys.exit(f"{f}: '~N' files are exported duplicates; rename the script in Studio instead.")
    if name.endswith(".server.luau"):
        cls, name = "Script", name[:-12]
    elif name.endswith(".client.luau"):
        cls, name = "LocalScript", name[:-12]
    else:
        name = name[:-5]
    return rel[:-1], name, cls


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--root", required=True, help="folder laid out like game/")
    ap.add_argument("--studio", help="part of the Studio name (default: first open Studio)")
    ap.add_argument("--check", action="store_true", help="syntax check only")
    a = ap.parse_args()
    files = a.files or [os.path.join(dp, f) for dp, _, fs in os.walk(a.root) for f in fs if f.endswith(".luau")]
    ensure_luau()
    bad = False
    for f in files:
        r = subprocess.run([LUAU, "--null", f], capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout + r.stderr)
            bad = True
    if bad:
        sys.exit("Syntax errors: nothing pushed.")
    if a.check:
        print(f"{len(files)} file(s) OK")
        return
    b = E.Bridge()
    studios = E.json_tail(b.call("list_roblox_studios", {}))["studios"]
    pick = [s for s in studios if not a.studio or a.studio.lower() in s["name"].lower()]
    if not pick:
        sys.exit("No matching Studio open (or the bridge is off).")
    sid = pick[0]["id"]
    eq = "=" * 12
    for f in files:
        path, name, cls = target(a.root, f)
        src = open(f, encoding="utf-8").read()
        if "]" + eq + "]" in src:
            sys.exit(f"{f}: contains the long-bracket terminator, can't push")
        code = f'''
local path = {{{", ".join(json.dumps(x) for x in path)}}}
local cur = game:GetService(path[1])
for i = 2, #path do
  local c = cur:FindFirstChild(path[i])
  if not c then c = Instance.new("Folder"); c.Name = path[i]; c.Parent = cur end
  cur = c
end
local s = cur:FindFirstChild({json.dumps(name)})
if s and s.ClassName ~= "{cls}" then s:Destroy(); s = nil end
if not s then s = Instance.new("{cls}"); s.Name = {json.dumps(name)}; s.Parent = cur end
s.Source = [{eq}[{src}]{eq}]
return s:GetFullName() .. " " .. #s.Source
'''
        print(b.luau(sid, code).strip()[-120:])


if __name__ == "__main__":
    main()
