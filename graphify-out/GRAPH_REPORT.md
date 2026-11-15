# Graph Report - Heistbond  (2026-11-15)

## Corpus Check
- 38 files · ~72,811 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 3)

## Summary
- 321 nodes · 628 edges · 23 communities (13 shown, 10 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 62 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `4b70cb13`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- GunClient.client.luau
- Data.luau
- WeaponServer.server.luau
- HeistMapBuilder.luau
- Heistbond - Roblox dev workspace
- HeavyMovement.client.luau
- .mcp.json
- README.md
- CoverClient.client.luau
- CoverPose.luau
- Sniper/GunClient.client.luau
- Run.luau
- AimAssist.client.luau
- GuardService.server.luau
- Blocky.luau

## God Nodes (most connected - your core abstractions)
1. `P()` - 22 edges
2. `startDrill()` - 14 edges
3. `explode()` - 13 edges
4. `fireOnce()` - 11 edges
5. `fireOnce()` - 11 edges
6. `B.new()` - 10 edges
7. `folder()` - 10 edges
8. `bank()` - 9 edges
9. `bankAlert()` - 9 edges
10. `consult()` - 9 edges

## Surprising Connections (you probably didn't know these)
- `render()` --calls--> `B.money()`  [INFERRED]
  game/StarterPlayer/StarterPlayerScripts/Heist/InventoryUI.luau → game/ReplicatedStorage/Heist/Blocky.luau
- `fireOnce()` --calls--> `Fx.sound()`  [INFERRED]
  game/StarterPack/Sniper/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `fireOnce()` --calls--> `Fx.muzzle()`  [INFERRED]
  game/StarterPack/Sniper/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `fireOnce()` --calls--> `Fx.tracer()`  [INFERRED]
  game/StarterPack/Sniper/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau
- `fireOnce()` --calls--> `Fx.impact()`  [INFERRED]
  game/StarterPack/Sniper/GunClient.client.luau → game/ReplicatedStorage/Weapons/WeaponFx.luau

## Import Cycles
- None detected.

## Communities (23 total, 10 thin omitted)

### Community 0 - "GunClient.client.luau"
Cohesion: 0.10
Nodes (30): emitterFor(), folder(), Fx.impact(), Fx.muzzle(), Fx.sound(), Fx.tracer(), playSound(), aimFar() (+22 more)

### Community 1 - "Data.luau"
Cohesion: 0.07
Nodes (26): get(), Net.event(), Net.request(), Data.add(), Data.addCash(), Data.count(), Data.init(), Data.learn() (+18 more)

### Community 2 - "WeaponServer.server.luau"
Cohesion: 0.13
Nodes (18): GunAnim.isReloading(), GunAnim.remember(), GunAnim.startReload(), GunAnim.step(), GunAnim.stop(), parts(), restOf(), setMagHidden() (+10 more)

### Community 3 - "HeistMapBuilder.luau"
Cohesion: 0.14
Nodes (39): at(), ball(), breakPanel(), c4spot(), cabinet(), camera(), cashStack(), ceilingLight() (+31 more)

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

### Community 14 - "Run.luau"
Cohesion: 0.14
Nodes (34): folder(), Sfx.confetti(), Sfx.debris(), Sfx.loop(), Sfx.play(), Sfx.popText(), Sfx.puff(), bagModel() (+26 more)

### Community 15 - "AimAssist.client.luau"
Cohesion: 0.83
Nodes (3): acquire(), headOf(), visible()

### Community 17 - "GuardService.server.luau"
Cohesion: 0.12
Nodes (21): GunPose.anglesTo(), GunPose.cframe(), GunPose.handleAt(), GunPose.handleFrom(), GunPose.pivot(), arm(), brain(), eyeParams() (+13 more)

### Community 18 - "Blocky.luau"
Cohesion: 0.22
Nodes (24): B.button(), B.click(), B.icon(), B.label(), B.money(), B.new(), B.panel(), B.pop() (+16 more)

## Knowledge Gaps
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GunPose.cframe()` connect `GuardService.server.luau` to `WeaponServer.server.luau`?**
  _High betweenness centrality (0.243) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `startDrill()` (e.g. with `Sfx.loop()` and `Sfx.play()`) actually correct?**
  _`startDrill()` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Should `GunClient.client.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.09841269841269841 - nodes in this community are weakly interconnected._
- **Why does `playReload()` connect `WeaponServer.server.luau` to `GuardService.server.luau`?**
  _High betweenness centrality (0.135) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `explode()` (e.g. with `Sfx.confetti()` and `Sfx.debris()`) actually correct?**
  _`explode()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Should `Data.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.07308970099667775 - nodes in this community are weakly interconnected._
- **Are the 4 inferred relationships involving `fireOnce()` (e.g. with `Fx.impact()` and `Fx.muzzle()`) actually correct?**
  _`fireOnce()` has 4 INFERRED edges - model-reasoned connections that need verification._