# Graph Report - Heistbond  (2026-11-14)

## Corpus Check
- 17 files · ~21,550 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 3)

## Summary
- 123 nodes · 189 edges · 17 communities (11 shown, 6 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `98facb93`
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
- CoverClient.client.luau
- CoverPose.luau
- GunPose.luau
- NPCService.server.luau
- AimAssist.client.luau

## God Nodes (most connected - your core abstractions)
1. `fireOnce()` - 10 edges
2. `renderStep()` - 10 edges
3. `GunAnim.step()` - 7 edges
4. `playReload()` - 7 edges
5. `findWall()` - 7 edges
6. `takeHold()` - 6 edges
7. `GunAnim.stop()` - 6 edges
8. `Heistbond - Roblox dev workspace` - 6 edges
9. `buildHud()` - 5 edges
10. `unequip()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `fireOnce()` --calls--> `Fx.impact()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `fireOnce()` --calls--> `Fx.muzzle()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `fireOnce()` --calls--> `Fx.sound()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `fireOnce()` --calls--> `Fx.tracer()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `renderStep()` --calls--> `GunAnim.isReloading()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunAnim.luau

## Import Cycles
- None detected.

## Communities (17 total, 6 thin omitted)

### Community 0 - "GunClient.client.luau"
Cohesion: 0.15
Nodes (22): aimFar(), bar(), buildHud(), camRayParams(), cloneLimb(), corner(), destroyViewArms(), fireOnce() (+14 more)

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

### Community 5 - "HeavyMovement.client.luau"
Cohesion: 0.32
Nodes (4): angleDiff(), loadSneak(), loadTrack(), step()

### Community 9 - "CoverClient.client.luau"
Cohesion: 0.21
Nodes (8): edgeAlong(), findWall(), flat(), groundY(), isWall(), rayOrigin(), rayParams(), wallTop()

### Community 11 - "CoverPose.luau"
Cohesion: 0.33
Nodes (6): CoverPose.apply(), CoverPose.isR15(), lerp(), rig(), rotBetween(), solveArm()

### Community 13 - "GunPose.luau"
Cohesion: 0.47
Nodes (5): GunPose.anglesTo(), GunPose.handleAt(), GunPose.handleFrom(), GunPose.pivot(), GunPose.torsoFor()

### Community 14 - "NPCService.server.luau"
Cohesion: 0.48
Nodes (5): groundAt(), live(), loadTrack(), randomPoint(), walkTo()

### Community 15 - "AimAssist.client.luau"
Cohesion: 0.83
Nodes (3): acquire(), headOf(), visible()

## Knowledge Gaps
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `renderStep()` connect `GunClient.client.luau` to `GunAnim.luau`, `GunPose.luau`?**
  _High betweenness centrality (0.076) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `fireOnce()` (e.g. with `Fx.impact()` and `Fx.muzzle()`) actually correct?**
  _`fireOnce()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Why does `fireOnce()` connect `GunClient.client.luau` to `.mcp.json`?**
  _High betweenness centrality (0.067) - this node is a cross-community bridge._
- **Are the 5 inferred relationships involving `renderStep()` (e.g. with `GunAnim.isReloading()` and `GunAnim.step()`) actually correct?**
  _`renderStep()` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Why does `GunAnim.step()` connect `GunAnim.luau` to `GunClient.client.luau`?**
  _High betweenness centrality (0.026) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `GunAnim.step()` (e.g. with `renderStep()` and `playReload()`) actually correct?**
  _`GunAnim.step()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `playReload()` (e.g. with `GunAnim.isReloading()` and `GunAnim.startReload()`) actually correct?**
  _`playReload()` has 6 INFERRED edges - model-reasoned connections that need verification._