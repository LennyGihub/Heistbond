# Roblox rules for subagents (read this, not the big game-roblox-dev skill)

**Studio**
- Studio is the source of truth. No Rojo. Edit only through the `Roblox_Studio` MCP tools; get `studio_id` from `list_roblox_studios` first.
- Read with `script_read` + a line range, find with `script_grep`/`search_game_tree`, edit with `multi_edit`, run setup code with `execute_luau` (`datamodel_type` "Edit").
- Never edit files in `game/`: it's a read-only mirror. Find code via `graphify query` only when it beats a direct read (see CLAUDE.md).
- Before editing, stop any running playtest (`get_studio_state`, `start_stop_play`). Test: start a playtest, read `get_console_output`, stop it.
- Group new instances in a named Folder/ScreenGui/Model so they're easy to find or delete.

**Luau**
- Use `task.wait/spawn/delay` (never `wait`), `--!strict` in new modules, Attributes for config, `:Disconnect()` connections you create.
- Max 200 locals per function (a script's top level included): put new features in ModuleScripts, not in a giant script.
- Escapes: `\u{26a1}`, never `\u26a1` (no braces).

**Server, data and money**
- Never trust the client: validate every RemoteEvent/RemoteFunction argument (type, range, ownership, cooldown). Cash, damage and rewards are always decided by the server.
- DataStore: `pcall` + `UpdateAsync`, save on PlayerRemoving + `BindToClose`, autosave. Sets use string keys.
- Repeatable purchases = Developer Product; permanent perks = Game Pass. One `ProcessReceipt` per game; grant once per `PurchaseId`; return `NotProcessedYet` if the player's data isn't loaded. Product IDs in attributes (0 = not set up).

**UI**
- No emoji as icons or decoration (the user dislikes them). Make icons with `python3 tools/make_image.py <name> "<description>"` (prints the `rbxassetid://`), check the PNG, use it in an ImageLabel.
- Scale, not Offset; `UIAspectRatioConstraint`; `TextScaled` + `UITextSizeConstraint`; `UICorner`/`UIStroke`/`UIGradient`; touch targets >= 50 px; `ResetOnSpawn=false`.

**3D**
- Props: free Creator Store model (`search_asset` free + verified, `insert_asset`, then delete any scripts inside it) or `generate_mesh` (AI, set `size` + `maxTriangles`). Don't build detailed props from hundreds of parts in Luau code.

**Working as a subagent**
- Only one agent edits Studio at a time. If your brief says read-only, don't edit.
- Report back in <= 15 lines: what you did/found, the script paths + line numbers, what you tested and the result. No full script dumps.
- Reply in the language the user wrote in.
