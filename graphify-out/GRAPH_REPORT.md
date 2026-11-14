# Graph Report - Heistbond  (2026-11-14)

## Corpus Check
- 14 files · ~17,733 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 3)

## Summary
- 105 nodes · 165 edges · 13 communities (8 shown, 5 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 17 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `253dfc56`
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

## God Nodes (most connected - your core abstractions)
1. `fireOnce()` - 10 edges
2. `renderStep()` - 10 edges
3. `findWall()` - 7 edges
4. `GunAnim.step()` - 7 edges
5. `playReload()` - 7 edges
6. `takeHold()` - 6 edges
7. `GunAnim.stop()` - 6 edges
8. `Heistbond - Roblox dev workspace` - 6 edges
9. `CoverPose.apply()` - 5 edges
10. `buildHud()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `renderStep()` --calls--> `GunPose.handleAt()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunPose.luau
- `playReload()` --calls--> `GunPose.torsoFor()`  [INFERRED]
  game/StarterPlayer/StarterPlayerScripts/WeaponFxListener.client.luau → game/ReplicatedStorage/Weapons/GunPose.luau
- `renderStep()` --calls--> `GunPose.anglesTo()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunPose.luau
- `playReload()` --calls--> `GunPose.cframe()`  [INFERRED]
  game/StarterPlayer/StarterPlayerScripts/WeaponFxListener.client.luau → game/ReplicatedStorage/Weapons/GunPose.luau
- `fireOnce()` --calls--> `Fx.impact()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau

## Import Cycles
- None detected.

## Communities (13 total, 5 thin omitted)

### Community 0 - "GunClient.client.luau"
Cohesion: 0.17
Nodes (21): aimTarget(), bar(), buildHud(), camRayParams(), cloneLimb(), corner(), destroyViewArms(), fireOnce() (+13 more)

### Community 1 - ".mcp.json"
Cohesion: 0.33
Nodes (7): emitterFor(), folder(), Fx.impact(), Fx.muzzle(), Fx.sound(), Fx.tracer(), playSound()

### Community 2 - "README.md"
Cohesion: 0.18
Nodes (10): GunPose.anglesTo(), GunPose.cframe(), GunPose.handleAt(), GunPose.pivot(), GunPose.torsoFor(), armIK(), onCharacter(), onPlayer() (+2 more)

### Community 3 - "GunAnim.luau"
Cohesion: 0.31
Nodes (10): GunAnim.isReloading(), GunAnim.remember(), GunAnim.startReload(), GunAnim.step(), GunAnim.stop(), parts(), restOf(), setMagHidden() (+2 more)

### Community 4 - "Heistbond - Roblox dev workspace"
Cohesion: 0.29
Nodes (6): 3D models (free, low-token), graphify (only when it saves tokens), Heistbond - Roblox dev workspace, How to work (user's choice: this replaces the old "always delegate to subagents" rule), Images (icons, UI art) — no emoji, Saving the game's code (user's standing instruction)

### Community 5 - "HeavyMovement.client.luau"
Cohesion: 0.32
Nodes (4): angleDiff(), loadSneak(), loadTrack(), step()

### Community 9 - "CoverClient.client.luau"
Cohesion: 0.27
Nodes (7): findWall(), flat(), groundY(), isWall(), rayOrigin(), rayParams(), wallTop()

### Community 11 - "CoverPose.luau"
Cohesion: 0.33
Nodes (6): CoverPose.apply(), CoverPose.isR15(), lerp(), rig(), rotBetween(), solveArm()

## Knowledge Gaps
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `fireOnce()` connect `GunClient.client.luau` to `.mcp.json`?**
  _High betweenness centrality (0.087) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `fireOnce()` (e.g. with `Fx.impact()` and `Fx.muzzle()`) actually correct?**
  _`fireOnce()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Why does `renderStep()` connect `GunClient.client.luau` to `README.md`, `GunAnim.luau`?**
  _High betweenness centrality (0.084) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `renderStep()` (e.g. with `GunAnim.isReloading()` and `GunAnim.step()`) actually correct?**
  _`renderStep()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Why does `playReload()` connect `GunAnim.luau` to `README.md`?**
  _High betweenness centrality (0.038) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `GunAnim.step()` (e.g. with `renderStep()` and `playReload()`) actually correct?**
  _`GunAnim.step()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `playReload()` (e.g. with `GunAnim.isReloading()` and `GunAnim.startReload()`) actually correct?**
  _`playReload()` has 6 INFERRED edges - model-reasoned connections that need verification._