# Heistbond - Roblox dev workspace

- Roblox Studio is the source of truth (no Rojo). Cloud sessions reach Studio through `roblox-mcp-bridge/` (Lenny starts it on his PC), either with the `Roblox_Studio` MCP tools or with `tools/studio.py` / `tools/deploy_luau.py`, which call the same bridge from the shell. How to write code: see "How to work" below.
- `game/` is a read-only mirror of the place's scripts, exported with `python3 tools/export_studio.py` (`--list`, `--studio "<name>"`). Never edit files in `game/` itself; edit a copy (see "How to work"), push it to Studio, then `tools/save_game.sh` re-exports.
- Save tokens: use `graphify query/path/explain` (rules below) to find code, then read only the needed lines (`script_read` with a line range in Studio, or `game/` files with offset/limit). Don't dump whole scripts.
- Roblox API reference offline: `/opt/creator-docs/content/en-us/reference/engine/` (classes/*.yaml, enums, datatypes); Luau docs in `/opt/creator-docs/content/en-us/luau/`.

## Images (icons, UI art) — no emoji

- The user dislikes emoji in UI: use generated image icons instead.
- One command makes an image and returns its Roblox id: `python3 tools/make_image.py <name> "<what it is>"` (`--kind art --size 1024x576` for backgrounds/art; `--no-upload` to look at it first). It uses Pollinations' free model, cuts the white background for icons, stores the PNG in the public `game-art` repo and uploads it through Studio. The last printed line is `rbxassetid://...`.
- Needs the `game-art` repo at `/home/user/game-art` with push access: if missing, attach `lennygihub/game-art` (add_repo, push) and clone it there. Needs the bridge's "Image relay" window running on the PC.
- Look at the image (Read the PNG) before using it in the game; regenerate with another `--seed` if it's off. Never put text in generated images; add text with TextLabels.

## 3D models (free, low-token)

Studio's own tools do 3D for free and answer with a few lines, so prefer them over building big models from Luau code:
1. **Free Creator Store model** for common props: `search_asset` (`scope` "creator_store", `priceFilter` "free", `assetType` "Model", `verifiedCreatorsOnly` true, `maxResults` 3-5) then `insert_asset`. Free models can hide malicious scripts: right after inserting, list every Script/LocalScript/ModuleScript inside it and delete them unless the model needs them and you've read them.
2. **AI mesh** (`generate_mesh`, ~1-2 min, textured, split into parts, e.g. a chest's body + lid) for unique props in the game's style; give `size` in studs and `maxTriangles` (2000-5000 for props). Several at once: `async` true, then `wait_job_finished`. The result is tagged in CollectionService with the returned `tag`.
3. **Procedural model** (`generate_procedural_model`) for blocky objects built from parts with tunable attributes (buildings, vehicles, characters).
4. Hand-built parts via `execute_luau` only for simple or large layout pieces (floors, walls, paths), not detailed props.
- Check the result once with `screen_capture` (needs the Studio window visible on the PC; a black image means it's minimized). Put props in named Folders/Models, anchor them, set `CanCollide/CanQuery/CanTouch` false on decoration.

## Saving the game's code (user's standing instruction)

- `main` is the one branch for this game. The user asked that every session push there directly; do it even though the session works on its own `claude/...` branch.
- At the end of every request that changed scripts in Studio, run `tools/save_game.sh "game: <short summary>"`. It exports Studio's scripts to `game/`, rebuilds the graphify map offline and pushes both to `main` (through a temporary worktree, so the session branch is untouched). Don't read the exported code back; the script's last lines say if it worked.
- If several Studios are open, pass the place: `EXPORT_ARGS='--studio "<name>"' tools/save_game.sh "..."`. If the bridge is off, say the save was skipped.
- Also remind the user to save the place in Studio itself (File > Save / publish): GitHub holds a copy, Studio holds the game.

## How to work (user's choice: this replaces the old "always delegate to subagents" rule)

The user wants sessions to work the way the first city-builder session did: **the main conversation writes the game code itself**, as whole coherent modules, and tests it in Studio. Subagents are the exception, not the default.

1. **Check Studio first**: `python3 tools/studio.py state` (or the MCP `list_roblox_studios` + `get_studio_state`). If the bridge is off, tell the user and stop.
2. **Make a work copy** of the code in your scratchpad: `cp -r game <scratchpad>/src` (same layout as `game/`; `git fetch origin main` first so `game/` is current). Edit there with Read/Edit/Write. Write new features as complete ModuleScripts (one job each, `--!strict`) rather than many tiny MCP edits.
3. **Check and push**: `python3 tools/deploy_luau.py --root <scratchpad>/src <changed files>`. It syntax-checks every file with `luau-compile` and pushes nothing if one fails. Studio must be in Edit mode (`tools/studio.py stop`).
4. **Test it for real in a playtest**: `tools/studio.py play`, wait ~10 s, then drive the game with `tools/studio.py luau Client <file>` scripts that call the game's own remotes (create a city, place buildings, build roads...) and return numbers to check. Then take `tools/studio.py shot <png>` screenshots and Read them, read `tools/studio.py console` for errors, and `stop`. Look at every visual change; fix what looks wrong and test again.
   - A `luau` call runs in its own VM (its own copy of ModuleScripts). To steer the running client (camera, open a panel, time of day), add Studio-only attribute hooks in the client (`if RunService:IsStudio()`) and set those attributes from the test script.
   - Keep each `luau` call under ~30 s of waiting; split long scenarios into several calls.
5. **Save**: `tools/save_game.sh "game: <summary>"` at the end of the request (see above), and remind the user to save the place in Studio.

**Subagents** (`.claude/agents/`): use one only for a separate, parallel chore that would flood this conversation, e.g. generating a batch of icons with `tools/make_image.py` or searching audio, run in the background with a precise brief (read `.claude/roblox-rules.md`, don't edit Studio, write results to a file, report in a few lines). Never hand the main game code to a subagent.

**Keep the user posted**: a short line before each big step (what you're building, what a test showed), and screenshots of results. Be honest about what was tested and what wasn't.

## graphify (only when it saves tokens)

`graphify-out/graph.json` maps the Luau code in `game/` and the Markdown docs (headings, links), built offline with `graphify update .` (AST only, no LLM, no images). Never run the `/graphify` LLM/semantic extraction: it costs tokens.

Use the graph only when it is cheaper than the alternative:
- Use `graphify query "<question>"` (capped at ~1000 tokens), `graphify path "<A>" "<B>"` or `graphify explain "<X>"` when you don't know where something lives, or when the answer spans several files or scripts over ~150 lines. Then read only the lines it points to.
- Skip it when you already know the file and lines, the file is small (< ~150 lines), or a single exact `grep -n` will find it.
- Don't read `graphify-out/GRAPH_REPORT.md` or `graph.json` directly (large); only for a full architecture review.
- After re-exporting from Studio, `tools/export_studio.py` rebuilds the graph itself; after editing docs run `graphify update .`.
