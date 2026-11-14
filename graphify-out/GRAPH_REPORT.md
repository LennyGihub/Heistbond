# Graph Report - Heistbond  (2026-11-14)

## Corpus Check
- 10 files · ~10,401 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 3)

## Summary
- 80 nodes · 131 edges · 9 communities (6 shown, 3 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 17 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `b38d836d`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- GunClient.client.luau
- .mcp.json
- README.md
- GunAnim.luau
- Heistbond - Roblox dev workspace
- HeavyMovement.client.luau
- .mcp.json
- README.md

## God Nodes (most connected - your core abstractions)
1. `fireOnce()` - 10 edges
2. `renderStep()` - 10 edges
3. `GunAnim.step()` - 7 edges
4. `playReload()` - 7 edges
5. `takeHold()` - 6 edges
6. `GunAnim.stop()` - 6 edges
7. `Heistbond - Roblox dev workspace` - 6 edges
8. `buildHud()` - 5 edges
9. `unequip()` - 5 edges
10. `updateHud()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `renderStep()` --calls--> `GunAnim.isReloading()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunAnim.luau
- `renderStep()` --calls--> `GunAnim.step()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunAnim.luau
- `renderStep()` --calls--> `GunPose.anglesTo()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunPose.luau
- `renderStep()` --calls--> `GunPose.cframe()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunPose.luau
- `unequip()` --calls--> `GunAnim.stop()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunAnim.luau

## Import Cycles
- None detected.

## Communities (9 total, 3 thin omitted)

### Community 0 - "GunClient.client.luau"
Cohesion: 0.18
Nodes (18): bar(), buildHud(), camRayParams(), cloneLimb(), corner(), destroyViewArms(), label(), onAimAction() (+10 more)

### Community 1 - ".mcp.json"
Cohesion: 0.27
Nodes (10): emitterFor(), folder(), Fx.impact(), Fx.muzzle(), Fx.sound(), Fx.tracer(), playSound(), aimTarget() (+2 more)

### Community 2 - "README.md"
Cohesion: 0.20
Nodes (9): GunPose.anglesTo(), GunPose.cframe(), GunPose.pivot(), GunPose.torsoFor(), armIK(), onCharacter(), onPlayer(), releaseHold() (+1 more)

### Community 3 - "GunAnim.luau"
Cohesion: 0.31
Nodes (10): GunAnim.isReloading(), GunAnim.remember(), GunAnim.startReload(), GunAnim.step(), GunAnim.stop(), parts(), restOf(), setMagHidden() (+2 more)

### Community 4 - "Heistbond - Roblox dev workspace"
Cohesion: 0.29
Nodes (6): 3D models (free, low-token), graphify (only when it saves tokens), Heistbond - Roblox dev workspace, How to work (user's choice: this replaces the old "always delegate to subagents" rule), Images (icons, UI art) — no emoji, Saving the game's code (user's standing instruction)

### Community 5 - "HeavyMovement.client.luau"
Cohesion: 0.32
Nodes (4): angleDiff(), loadSneak(), loadTrack(), step()

## Knowledge Gaps
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `renderStep()` connect `GunClient.client.luau` to `.mcp.json`, `README.md`, `GunAnim.luau`?**
  _High betweenness centrality (0.151) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `fireOnce()` (e.g. with `Fx.impact()` and `Fx.muzzle()`) actually correct?**
  _`fireOnce()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Why does `fireOnce()` connect `.mcp.json` to `GunClient.client.luau`?**
  _High betweenness centrality (0.148) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `renderStep()` (e.g. with `GunAnim.isReloading()` and `GunAnim.step()`) actually correct?**
  _`renderStep()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Why does `GunAnim.step()` connect `GunAnim.luau` to `GunClient.client.luau`?**
  _High betweenness centrality (0.060) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `GunAnim.step()` (e.g. with `renderStep()` and `playReload()`) actually correct?**
  _`GunAnim.step()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `playReload()` (e.g. with `GunAnim.isReloading()` and `GunAnim.startReload()`) actually correct?**
  _`playReload()` has 6 INFERRED edges - model-reasoned connections that need verification._