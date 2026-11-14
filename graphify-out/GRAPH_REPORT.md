# Graph Report - Heistbond  (2026-11-14)

## Corpus Check
- 22 files · ~43,464 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 3)

## Summary
- 205 nodes · 361 edges · 20 communities (13 shown, 7 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 28 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `4abc63c1`
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
- Sniper/GunClient.client.luau
- spawnOne
- AimAssist.client.luau
- GuardService.server.luau
- AtlasBankBuilder.luau

## God Nodes (most connected - your core abstractions)
1. `P()` - 17 edges
2. `fireOnce()` - 11 edges
3. `fireOnce()` - 11 edges
4. `folder()` - 10 edges
5. `consult()` - 9 edges
6. `spawnOne()` - 8 edges
7. `monitor()` - 7 edges
8. `GunAnim.stop()` - 7 edges
9. `playReload()` - 7 edges
10. `findWall()` - 7 edges

## Surprising Connections (you probably didn't know these)
- `fireOnce()` --calls--> `Fx.impact()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `fireOnce()` --calls--> `Fx.muzzle()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `fireOnce()` --calls--> `Fx.sound()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `fireOnce()` --calls--> `Fx.tracer()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `unequip()` --calls--> `GunAnim.stop()`  [INFERRED]
  game/StarterPack/M4A1/GunClient.client.luau → game/ReplicatedStorage/Weapons/GunAnim.luau

## Import Cycles
- None detected.

## Communities (20 total, 7 thin omitted)

### Community 0 - "GunClient.client.luau"
Cohesion: 0.13
Nodes (23): aimFar(), aimTarget(), bar(), buildHud(), cloneLimb(), corner(), destroyViewArms(), fireOnce() (+15 more)

### Community 1 - ".mcp.json"
Cohesion: 0.33
Nodes (7): emitterFor(), folder(), Fx.impact(), Fx.muzzle(), Fx.sound(), Fx.tracer(), playSound()

### Community 2 - "README.md"
Cohesion: 0.24
Nodes (5): armIK(), onCharacter(), onPlayer(), releaseHold(), takeHold()

### Community 3 - "GunAnim.luau"
Cohesion: 0.40
Nodes (10): GunAnim.isReloading(), GunAnim.remember(), GunAnim.startReload(), GunAnim.step(), GunAnim.stop(), parts(), restOf(), setMagHidden() (+2 more)

### Community 4 - "Heistbond - Roblox dev workspace"
Cohesion: 0.29
Nodes (6): 3D models (free, low-token), graphify (only when it saves tokens), Heistbond - Roblox dev workspace, How to work (user's choice: this replaces the old "always delegate to subagents" rule), Images (icons, UI art) — no emoji, Saving the game's code (user's standing instruction)

### Community 5 - "HeavyMovement.client.luau"
Cohesion: 0.32
Nodes (4): angleDiff(), loadSneak(), loadTrack(), step()

### Community 9 - "CoverClient.client.luau"
Cohesion: 0.23
Nodes (8): edgeAlong(), findWall(), flat(), groundY(), isWall(), rayOrigin(), rayParams(), wallTop()

### Community 11 - "CoverPose.luau"
Cohesion: 0.33
Nodes (6): CoverPose.apply(), CoverPose.isR15(), lerp(), rig(), rotBetween(), solveArm()

### Community 13 - "Sniper/GunClient.client.luau"
Cohesion: 0.13
Nodes (23): aimFar(), aimTarget(), bar(), buildHud(), cloneLimb(), corner(), destroyViewArms(), fireOnce() (+15 more)

### Community 14 - "spawnOne"
Cohesion: 0.27
Nodes (10): randomInZone(), loadTrack(), NPCCommon.animate(), NPCCommon.build(), NPCCommon.groundAt(), NPCCommon.onDeath(), describe(), randomPoint() (+2 more)

### Community 15 - "AimAssist.client.luau"
Cohesion: 0.83
Nodes (3): acquire(), headOf(), visible()

### Community 17 - "GuardService.server.luau"
Cohesion: 0.14
Nodes (14): GunPose.anglesTo(), GunPose.cframe(), GunPose.handleAt(), GunPose.handleFrom(), GunPose.pivot(), GunPose.torsoFor(), arm(), brain() (+6 more)

### Community 18 - "AtlasBankBuilder.luau"
Cohesion: 0.17
Nodes (32): at(), ball(), boxes(), cabinet(), camera(), cashStack(), ceilingLight(), consult() (+24 more)

## Knowledge Gaps
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GunPose.cframe()` connect `GuardService.server.luau` to `README.md`, `GunAnim.luau`?**
  _High betweenness centrality (0.161) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `fireOnce()` (e.g. with `Fx.impact()` and `Fx.muzzle()`) actually correct?**
  _`fireOnce()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Should `GunClient.client.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.13105413105413105 - nodes in this community are weakly interconnected._
- **Why does `brain()` connect `GuardService.server.luau` to `spawnOne`?**
  _High betweenness centrality (0.115) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `fireOnce()` (e.g. with `Fx.impact()` and `Fx.muzzle()`) actually correct?**
  _`fireOnce()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Should `Sniper/GunClient.client.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.13105413105413105 - nodes in this community are weakly interconnected._
- **Why does `playReload()` connect `GunAnim.luau` to `GuardService.server.luau`, `README.md`?**
  _High betweenness centrality (0.100) - this node is a cross-community bridge._