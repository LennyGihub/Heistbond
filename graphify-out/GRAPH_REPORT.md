# Graph Report - Heistbond  (2026-11-14)

## Corpus Check
- 13 files · ~14,638 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 3)

## Summary
- 101 nodes · 173 edges · 12 communities (8 shown, 4 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 17 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `afb75720`
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
3. `step()` - 9 edges
4. `GunAnim.step()` - 7 edges
5. `playReload()` - 7 edges
6. `findWall()` - 6 edges
7. `enter()` - 6 edges
8. `takeHold()` - 6 edges
9. `GunAnim.stop()` - 6 edges
10. `Heistbond - Roblox dev workspace` - 6 edges

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

## Communities (12 total, 4 thin omitted)

### Community 0 - "GunClient.client.luau"
Cohesion: 0.17
Nodes (21): aimTarget(), bar(), buildHud(), camRayParams(), cloneLimb(), corner(), destroyViewArms(), fireOnce() (+13 more)

### Community 1 - ".mcp.json"
Cohesion: 0.33
Nodes (7): emitterFor(), folder(), Fx.impact(), Fx.muzzle(), Fx.sound(), Fx.tracer(), playSound()

### Community 2 - "README.md"
Cohesion: 0.24
Nodes (5): armIK(), onCharacter(), onPlayer(), releaseHold(), takeHold()

### Community 3 - "GunAnim.luau"
Cohesion: 0.24
Nodes (14): GunAnim.isReloading(), GunAnim.remember(), GunAnim.startReload(), GunAnim.step(), GunAnim.stop(), parts(), restOf(), setMagHidden() (+6 more)

### Community 4 - "Heistbond - Roblox dev workspace"
Cohesion: 0.29
Nodes (6): 3D models (free, low-token), graphify (only when it saves tokens), Heistbond - Roblox dev workspace, How to work (user's choice: this replaces the old "always delegate to subagents" rule), Images (icons, UI art) — no emoji, Saving the game's code (user's standing instruction)

### Community 5 - "HeavyMovement.client.luau"
Cohesion: 0.32
Nodes (4): angleDiff(), loadSneak(), loadTrack(), step()

### Community 9 - "CoverClient.client.luau"
Cohesion: 0.40
Nodes (11): backDepth(), enter(), findWall(), flat(), isWall(), leave(), rayParams(), send() (+3 more)

### Community 11 - "CoverPose.luau"
Cohesion: 0.52
Nodes (5): CoverPose.apply(), CoverPose.isR15(), rig(), rotBetween(), solveArm()

## Knowledge Gaps
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `renderStep()` connect `GunClient.client.luau` to `GunAnim.luau`?**
  _High betweenness centrality (0.094) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `fireOnce()` (e.g. with `Fx.impact()` and `Fx.muzzle()`) actually correct?**
  _`fireOnce()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Why does `fireOnce()` connect `GunClient.client.luau` to `.mcp.json`?**
  _High betweenness centrality (0.092) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `renderStep()` (e.g. with `GunAnim.isReloading()` and `GunAnim.step()`) actually correct?**
  _`renderStep()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Why does `GunAnim.step()` connect `GunAnim.luau` to `GunClient.client.luau`?**
  _High betweenness centrality (0.038) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `GunAnim.step()` (e.g. with `renderStep()` and `playReload()`) actually correct?**
  _`GunAnim.step()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `playReload()` (e.g. with `GunAnim.isReloading()` and `GunAnim.startReload()`) actually correct?**
  _`playReload()` has 6 INFERRED edges - model-reasoned connections that need verification._