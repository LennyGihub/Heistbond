# Graph Report - Heistbond  (2026-11-15)

## Corpus Check
- 44 files · ~84,003 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 3 file(s) not represented in the graph (top: (none) 3)

## Summary
- 364 nodes · 737 edges · 27 communities (16 shown, 11 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 76 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `8ee91494`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- GunClient.client.luau
- Data.luau
- GunAnim.luau
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
- NpcLife.luau
- Data.luau
- spawnOne

## God Nodes (most connected - your core abstractions)
1. `P()` - 22 edges
2. `customerLoop()` - 15 edges
3. `startDrill()` - 14 edges
4. `explode()` - 13 edges
5. `guardLoop()` - 11 edges
6. `fireOnce()` - 11 edges
7. `fireOnce()` - 11 edges
8. `free()` - 10 edges
9. `B.new()` - 10 edges
10. `folder()` - 10 edges

## Surprising Connections (you probably didn't know these)
- `converse()` --calls--> `Nav.stop()`  [INFERRED]
  game/ServerScriptService/Heist/NpcLife.luau → game/ServerScriptService/Heist/NpcNav.luau
- `customerLoop()` --calls--> `Lines.pick()`  [INFERRED]
  game/ServerScriptService/Heist/NpcLife.luau → game/ServerScriptService/Heist/NpcLines.luau
- `looseBag()` --calls--> `Vehicles.load()`  [INFERRED]
  game/ServerScriptService/Heist/Run.luau → game/ServerScriptService/Heist/Vehicles.luau
- `placeC4()` --calls--> `Tools.use()`  [INFERRED]
  game/ServerScriptService/Heist/Run.luau → game/ServerScriptService/Heist/Tools.luau
- `startDrill()` --calls--> `Data.count()`  [INFERRED]
  game/ServerScriptService/Heist/Run.luau → game/ServerScriptService/Heist/Data.luau

## Import Cycles
- None detected.

## Communities (27 total, 11 thin omitted)

### Community 0 - "GunClient.client.luau"
Cohesion: 0.13
Nodes (23): aimFar(), aimTarget(), bar(), buildHud(), cloneLimb(), corner(), destroyViewArms(), fireOnce() (+15 more)

### Community 1 - "Data.luau"
Cohesion: 0.12
Nodes (15): Data.count(), buildTemplates(), makeWeapon(), part(), simple(), Tools.equip(), Tools.find(), Tools.give() (+7 more)

### Community 2 - "GunAnim.luau"
Cohesion: 0.40
Nodes (10): GunAnim.isReloading(), GunAnim.remember(), GunAnim.startReload(), GunAnim.step(), GunAnim.stop(), parts(), restOf(), setMagHidden() (+2 more)

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
Cohesion: 0.10
Nodes (30): emitterFor(), folder(), Fx.impact(), Fx.muzzle(), Fx.sound(), Fx.tracer(), playSound(), aimFar() (+22 more)

### Community 14 - "Run.luau"
Cohesion: 0.14
Nodes (34): folder(), Sfx.confetti(), Sfx.debris(), Sfx.loop(), Sfx.play(), Sfx.popText(), Sfx.puff(), bagModel() (+26 more)

### Community 15 - "AimAssist.client.luau"
Cohesion: 0.83
Nodes (3): acquire(), headOf(), visible()

### Community 17 - "GuardService.server.luau"
Cohesion: 0.09
Nodes (20): GunPose.anglesTo(), GunPose.cframe(), GunPose.handleAt(), GunPose.handleFrom(), GunPose.pivot(), GunPose.torsoFor(), arm(), brain() (+12 more)

### Community 18 - "Blocky.luau"
Cohesion: 0.22
Nodes (24): B.button(), B.click(), B.icon(), B.label(), B.money(), B.new(), B.panel(), B.pop() (+16 more)

### Community 23 - "NpcLife.luau"
Cohesion: 0.13
Nodes (31): alive(), buildWindows(), calm(), chat(), converse(), customerLoop(), dist(), free() (+23 more)

### Community 24 - "Data.luau"
Cohesion: 0.16
Nodes (13): get(), Net.event(), Net.request(), Data.add(), Data.addCash(), Data.init(), Data.learn(), Data.push() (+5 more)

### Community 25 - "spawnOne"
Cohesion: 0.31
Nodes (9): loadTrack(), NPCCommon.animate(), NPCCommon.build(), NPCCommon.groundAt(), NPCCommon.onDeath(), describe(), randomPoint(), spawnOne() (+1 more)

## Knowledge Gaps
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GunPose.cframe()` connect `GuardService.server.luau` to `GunAnim.luau`?**
  _High betweenness centrality (0.192) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `customerLoop()` (e.g. with `Lines.pick()` and `Lines.solo_()`) actually correct?**
  _`customerLoop()` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Should `GunClient.client.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.13105413105413105 - nodes in this community are weakly interconnected._
- **Why does `playReload()` connect `GunAnim.luau` to `GuardService.server.luau`?**
  _High betweenness centrality (0.107) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `startDrill()` (e.g. with `Sfx.loop()` and `Sfx.play()`) actually correct?**
  _`startDrill()` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Should `Data.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.12 - nodes in this community are weakly interconnected._
- **Are the 4 inferred relationships involving `explode()` (e.g. with `Sfx.confetti()` and `Sfx.debris()`) actually correct?**
  _`explode()` has 4 INFERRED edges - model-reasoned connections that need verification._