# Graph Report - Heistbond  (2026-11-14)

## Corpus Check
- 9 files · ~8,363 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 3)

## Summary
- 73 nodes · 124 edges · 13 communities (10 shown, 3 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 17 edges (avg confidence: 0.85)
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
- renderStep
- .mcp.json
- README.md
- unequip
- fireOnce
- renderStep
- updateViewArms

## God Nodes (most connected - your core abstractions)
1. `renderStep()` - 11 edges
2. `fireOnce()` - 10 edges
3. `GunAnim.step()` - 7 edges
4. `playReload()` - 7 edges
5. `takeHold()` - 6 edges
6. `GunAnim.stop()` - 6 edges
7. `Heistbond - Roblox dev workspace` - 6 edges
8. `buildHud()` - 5 edges
9. `unequip()` - 5 edges
10. `GunPose.cframe()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `takeHold()` --calls--> `GunPose.torsoFor()`  [INFERRED]
  game/ServerScriptService/Weapons/WeaponServer.server.luau → game/ReplicatedStorage/Weapons/GunPose.luau
- `renderStep()` --calls--> `GunPose.anglesTo()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunPose.luau
- `takeHold()` --calls--> `GunPose.cframe()`  [INFERRED]
  game/ServerScriptService/Weapons/WeaponServer.server.luau → game/ReplicatedStorage/Weapons/GunPose.luau
- `renderStep()` --calls--> `GunPose.cframe()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunPose.luau
- `playReload()` --calls--> `GunPose.cframe()`  [INFERRED]
  game/StarterPlayer/StarterPlayerScripts/WeaponFxListener.client.luau → game/ReplicatedStorage/Weapons/GunPose.luau

## Import Cycles
- None detected.

## Communities (13 total, 3 thin omitted)

### Community 0 - "GunClient.client.luau"
Cohesion: 0.53
Nodes (4): bar(), buildHud(), corner(), label()

### Community 1 - ".mcp.json"
Cohesion: 0.33
Nodes (7): emitterFor(), folder(), Fx.impact(), Fx.muzzle(), Fx.sound(), Fx.tracer(), playSound()

### Community 2 - "README.md"
Cohesion: 0.24
Nodes (5): armIK(), onCharacter(), onPlayer(), releaseHold(), takeHold()

### Community 3 - "GunAnim.luau"
Cohesion: 0.35
Nodes (11): GunAnim.isReloading(), GunAnim.remember(), GunAnim.startReload(), GunAnim.step(), GunAnim.stop(), parts(), restOf(), setMagHidden() (+3 more)

### Community 4 - "Heistbond - Roblox dev workspace"
Cohesion: 0.29
Nodes (6): 3D models (free, low-token), graphify (only when it saves tokens), Heistbond - Roblox dev workspace, How to work (user's choice: this replaces the old "always delegate to subagents" rule), Images (icons, UI art) — no emoji, Saving the game's code (user's standing instruction)

### Community 5 - "renderStep"
Cohesion: 0.67
Nodes (3): GunPose.anglesTo(), GunPose.cframe(), GunPose.pivot()

### Community 9 - "unequip"
Cohesion: 0.33
Nodes (6): destroyViewArms(), onAimAction(), onViewAction(), setAiming(), toggleView(), unequip()

### Community 10 - "fireOnce"
Cohesion: 0.50
Nodes (5): fireOnce(), flashHitmarker(), rayParams(), startFiring(), updateHud()

### Community 11 - "renderStep"
Cohesion: 0.50
Nodes (4): aimTarget(), camRayParams(), faceYaw(), renderStep()

### Community 12 - "updateViewArms"
Cohesion: 0.67
Nodes (3): cloneLimb(), updateViewArms(), vmPart()

## Knowledge Gaps
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `renderStep()` connect `renderStep` to `GunClient.client.luau`, `GunAnim.luau`, `renderStep`, `unequip`, `fireOnce`, `updateViewArms`?**
  _High betweenness centrality (0.190) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `renderStep()` (e.g. with `GunAnim.isReloading()` and `GunAnim.step()`) actually correct?**
  _`renderStep()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Why does `fireOnce()` connect `fireOnce` to `GunClient.client.luau`, `.mcp.json`, `renderStep`?**
  _High betweenness centrality (0.182) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `fireOnce()` (e.g. with `Fx.impact()` and `Fx.muzzle()`) actually correct?**
  _`fireOnce()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Why does `GunAnim.step()` connect `GunAnim.luau` to `renderStep`?**
  _High betweenness centrality (0.075) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `GunAnim.step()` (e.g. with `renderStep()` and `playReload()`) actually correct?**
  _`GunAnim.step()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `playReload()` (e.g. with `GunAnim.isReloading()` and `GunAnim.startReload()`) actually correct?**
  _`playReload()` has 6 INFERRED edges - model-reasoned connections that need verification._