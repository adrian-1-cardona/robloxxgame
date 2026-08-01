# Organic island silhouettes replace the disc-and-dome terrain generator

Islands are no longer stacks of `FillCylinder` / `FillBall` primitives. A pure-Luau silhouette generator (`IslandShape`) decides the coastline, an off-centre lagoon with a mouth to the sea, a landmark, a meandering river and a settlement clearing; `IslandRaster` samples that height field on a 12-16 stud grid and merges the cells into ~2,200 axis-aligned boxes; `IslandTerrain` writes them as voxel Terrain. `IslandService` was cut from 4,082 to 3,137 lines: the three bespoke terrain generators and the twin-peaks / terraced styles are gone, and prop, dock, lighthouse, trail, raft-collision and village placement all query the shape instead of guessing with polar radii. The arrival hub's hand-pinned lagoon, volcano and settlement overrides were removed from `Config` so it goes through the same generator. The geometry is verified headlessly: 286 silhouette assertions, 31 source guards, a compile pass and a PNG preview renderer, all green on this branch.

**Watch for:** the arrival hub's raft spawn is no longer inside a protected lagoon — crew slots 3 and 4 spawn on dry sculpted land (**confirmed**), and slot 1's 64-stud raft footprint already clips land at one corner (**confirmed**). `RiverWidth` is silently clamped from 440 to 127 studs, narrower than the raft's own collision envelope, so no channel on any island is navigable (**confirmed**). The whole `ScenicPath` trail network is still drawn at a flat `topY + 0.2` against a height field that now rises to 40+ studs, so trails are buried inland and float over the lagoon (**confirmed**). The mountain waterfall and the volcano lava lake are anchored to constants that no longer match the sculpted terrain (**confirmed**). And `MAX_WATER_FRACTION` is measured before the river and lake exist, so it never fires (**confirmed**).

## High-level view

The silhouette generator itself holds up: deterministic, Roblox-free, and its lagoon-fitting pass does keep a walkable land band at every bearing on all 13 catalog islands. The weak seam is everything downstream that was not migrated with it.

The old generator guaranteed a flat plateau — `landColumn(cx, cz, half * 0.52, topY + 2, grass)` plus a village cap at `topY + 0.5`. A family of props was written against that guarantee and still hard-codes `topY + <constant>` for its Y. The new height field has no plateau, so trails, trail-side shrubs, the beached shipwreck, the waterfall and the crater lava are placed at heights the terrain no longer has. Nothing in the diff surfaces this because the geometry suites assert properties of `IslandShape` and never the world positions the decoration pass computes from it.

The arrival hub is the sharpest instance. Unpinning `LagoonOffset = Vector3.new(0, 0, 0)` / `LagoonWidth = 780` was correct for the silhouette — a centred bay is the bullseye the generator exists to avoid — but the island centre is also `Config.StarterBase.Origin`, where every crew's raft spawns, 160 studs apart along +X. The old pinned lagoon was a 780x610 pool covering slots 1-3. The generated bay sits 196 studs off centre, leaving the island centre as a 127-stud river channel and slots 3 and 4 ashore.

The river clamp is a second dropped contract. `Config` still labels `RiverWidth = 440` as "the boarding/raft contract marker"; `IslandShape` stores the requested width and then discards it for `min(size * 0.085, ...)`. At 93-127 studs, and with `collideRaft` deliberately carrying no river exception, a 64-stud raft with a 52-stud collision pad can never enter one.

The submerged repaint is faithful in intent but not in resolution: `submergedPlan` rasterises at 48 studs against a sculpt at 12-16, so each repaint bulldozes 70-140 fine cells of underwater lagoon and river bank into sand and leaves 50-120 fine cells of sculpted shoreline unrestored. The chunk scoping added to `OceanTerrainService` is correct but does not reach the endless-island path, which still calls `paintTerrain()` unscoped on every build.

Sea piers now pick their bearing through `shoreAngleNear` and land correctly. The lagoon and lake piers still use the fixed `radius + 20` / `max(radius * 0.58, 124)` span that used to run only on the hand-authored hub; now that every island has a lagoon it runs 13 times and misplaces 2 of them.

<details>
<summary>Issues (16)</summary>

1. **Arrival hub raft spawn on land** — crew slots 3 and 4 (`StarterBase.Origin + 320 / +480` on X) sample `land` at `topY + 2.1` / `topY + 0.9`. Either re-pin the hub's lagoon near the island centre, add a guaranteed spawn basin to the shape, or move the hub off the raft origin.
2. **Slot 1 raft footprint clips land** — `sample(+16, +32)` and `sample(+32, +32)` are land, so the 64-stud deck overlaps the channel bank at spawn. Widen the spawn basin or offset the hub.
3. **RiverWidth silently clamped** — `IslandShape.luau:237` clamps 440 to 127 (hub) and 260-300 to 93.5 (others); `requestedWidth` is stored and never read. Rafts need >168 studs to enter. Either drop the "navigable" claim from the docs and `Config`, or raise the clamp and give `collideRaft` a channel exception.
4. **Trail network drawn at a flat `topY + 0.2`** — `IslandService.luau:1798`, `1808`. Measured on the hub's village-to-landmark trail: buried 0.7-41 studs on land, floating 3 studs over the lagoon for half its length. Sample the shape (or raycast) per segment.
5. **`addTarget` only validates trail endpoints** — `IslandService.luau:1835` checks the target is land but not the path; the hub's landmark trail crosses the lagoon and the river. Reject or reroute paths whose midpoints are water.
6. **Waterfall floats 20.8 studs above the beach** — `IslandService.luau:2067` uses a constant `topY + 22` at `coastRadius - beachWidth * 0.5`, where the terrain is `topY + 1.3`. Anchor the top to `shape:landHeight` at a point on the landmark's flank.
7. **Crater lava floats 18-30 studs above the crater floor** — `IslandService.luau:2055` puts the lava at `rimY - 3.5` while `craterDepth = height * 0.13` (21-34 studs). Derive the lava Y from `landmark.craterDepth`.
8. **`MAX_WATER_FRACTION` never fires** — `_fitLagoon` (`IslandShape.luau:226`) runs before `self.river` (`:238`) and `self.lake` (`:287`) are assigned, so the cap sees 14-18% while the finished islands reach 24-30%. Move the fit after the river and lake, or re-run it.
9. **Submerged repaint is 3-4x coarser than the sculpt** — `IslandTerrain.luau:91` / `IslandRaster.luau:213` use step 48 against a 12-16 stud sculpt: 70-140 fine water cells bulldozed to sand, 50-120 fine land/shelf cells left unrestored per island, all at the waterline. Match the sculpt step or clip the coarse plan to the fine classification.
10. **Endless islands repaint every island** — `IslandService.luau:2514` calls `paintTerrain()` with no argument, replaying every island's submerged plan (non-yielding) on each endless build. Pass the new island's centre.
11. **Beached shipwreck ignores the sampled height** — `IslandService.luau:2168-2171` discards the third return of `randomLandPoint` and places the hull at `topY + 0.6` on a point allowed up to `maxHeight = 6`. Use the returned height.
12. **Loose loot does not compensate for vertical quantisation** — `IslandService.luau:1117` places props at the analytic height, but the raster snaps terrain tops with `quantize(v, 2)`, which can raise the surface 1 stud. Planks at `+0.35` can end up under the sand. Add a stud of clearance or quantise the placement the same way.
13. **Lagoon / lake pier span is not validated against the organic rim** — `IslandService.luau:2095`'s `radius + 20` / `max(radius * 0.58, 124)`. Measured: mistwood's land end lands in water, raid_cove's T-head and moored rowboat land on dry ground, and both lake piers reach to 124 studs from a lake whose rim is 42-76. Solve the span against `lagoonRadius` / `lakeRadius` at the chosen bearing.
14. **`shoreAngleNear` fails silently** — `IslandShape.luau:840` returns the requested bearing unchanged when no candidate within +/-0.78 rad is beach; 7.5% of bearings on quiet_sand fail that way. Return a nil / success flag so docks and lighthouses can skip instead of building over water.
15. **`clampRaftPosition` still uses a bounding circle** — `IslandService.luau:2761` keeps `isle.size * 0.5 + ApproachPadStuds` while `collideRaft` and `pointOnIsland` migrated to `shoreClearance`. On a 1100-stud isle that is a 970-stud exclusion ring around a 540-stud coast. Route it through `shoreClearance` too.
16. **`segmentHitsCircle` is now dead** — `IslandService.luau:2637` has no callers after `collideRaft` switched to `segmentHitsShore`. Remove it.

</details>

<details>
<summary>Details</summary>

### The arrival hub's raft spawn basin

`worldCenterForOffset` (`IslandService.luau:160-163`) places an island at `Config.StarterBase.Origin + entry.Offset`, and `arrival_hub.Offset` is `Vector3.new(0, 0, 0)`. `StarterBaseService.getBaseCenter` (`:74-78`) spawns crew *n*'s raft at `Origin + Vector3.new((n - 1) * SpacingX, 0, 0)` with `SpacingX = 160`. So the hub's island centre is crew 1's raft, and crews 2, 3, 4 spawn 160, 320 and 480 studs along +X from it.

The old `generateLagoonHubTerrain` carved the pinned `LagoonWidth = 780` x `LagoonDepth = 610` basin at `LagoonOffset = Vector3.new(0, 0, 0)` and refilled it to sea level, covering x in [-390, 390] — slots 1 through 3. Removing those overrides moved the bay 196 studs off centre; what is left at the island centre is the river channel:

```
slot 1  dx=  0  water  h=-14.0   (river bed, channelBed = seaOffset - 11)
slot 2  dx=160  water  h=-14.0
slot 3  dx=320  land   h=  2.1   <-- deck spawns inside terrain
slot 4  dx=480  land   h=  0.9   <-- deck spawns inside terrain
slot 5  dx=640  ocean
```

Slot 1's own footprint is not clean either. Sampling the 64-stud deck on a 16-stud lattice, the +X/+Z corner is already ashore:

```
        dz=-32  -16    0    +16   +32
dx=-32   w      w      w     w     w
dx=  0   w      w      w     w     w
dx=+32   w      w      w     w     l(+1)
```

`collideRaft` skips `isle.safeHarbor`, so nothing stops the raft driving further into the bank — it just intersects terrain.

### The river is not navigable

`IslandShape.luau:236-237`:

```lua
local requested = (river.width :: number?) or (size * 0.07)
local width = math.clamp(requested, 70, size * 0.085)
```

The hub's requested 440 becomes 127.5; the six 260-300 stud requests all become 93.5. `requestedWidth` is retained on the river table and never read again. The raft is 64 studs wide and `collideRaft` inflates every shoreline test by `RaftCollisionPad = 52`, so it needs 168 studs of clear water, and `segmentHitsShore` has no channel exception by design ("without river/channel exceptions that can be abused to cut through land at high speed").

The clamp is deliberate and its in-code justification is sound — a 440-stud trench does split an island in two. What is left inconsistent is `Config.luau` still calling `RiverWidth = 440` "the boarding/raft contract marker" and `IslandShape`'s header still advertising a "navigable sea-to-sea channel".

### Props anchored to a plateau that no longer exists

The old generator laid down flat ground on purpose: `landColumn(cx, cz, half * 0.52, topY + 2, grassMat)` for the inner half of the island and a village cap at `topY + 0.2` .. `topY + 0.5`. The new height field is `2.25 + smoothstep(...) * hillCrest * (0.35 + 1.25 * n)` with `hillCrest` between 17 and 28, so inland ground routinely sits 10-40 studs above `topY` and the landmark reaches 260.

`buildScenicTrail` still writes every slab and every trail-side bush and flower at a constant Y (`IslandService.luau:1798`, `1808`). Walking the hub's village-to-landmark trail:

```
t=0.0  land   terrain topY+ 1.1    slab buried  0.9
t=0.2  land   terrain topY+ 0.9    slab buried  0.7
t=0.3  water  lagoon bed -10.5     slab floats 3.2 above the water surface
t=0.7  water  river bed  -14.0     slab floats 3.2 above the water surface
t=1.0  land   terrain topY+41.4    slab buried 41.2
```

`addTarget` (`:1835`) checks only that the trail's *endpoint* is land, and its comment claims this stops trails "running out across the lagoon toward a landmark on the far shore". On the hub the landmark is on the far side of the bay from the village, so the trail crosses it anyway: five of eleven sampled points are open water, carrying 9-stud cobble slabs, bushes and flowers over the lagoon.

Three more places share the pattern. The abandoned-isle shipwreck (`:2168-2171`) throws away the height `randomLandPoint` returns and hard-codes `topY + 0.6` on a point allowed up to `topY + 6`. The mountain waterfall (`:2067`) uses `topY + 22` at `coastRadius - beachWidth * 0.5`, where the terrain is `topY + 1.3` on both mountain isles — 20.8 studs of air under the sheet with no cliff behind it, while the comment claims it is "anchored to the real coast radius on that bearing so it lands in the sea". The crater lava (`:2055`) sits at `rimY - 3.5`, which was correct when the old code hollowed a 14-stud crater with `FillCylinder(..., Air)`; the shape's crater is `height * 0.13` deep, so the lava disc, its `Fire` and its `PointLight` hang 17.9 studs (the three 165-stud cones) to 30.3 studs (the hub) above the bowl floor.

Loose loot (`:1117`) uses the sampled height but not the raster's vertical snap. `IslandRaster` writes tops as `quantize(topY + height, 2)`, i.e. `floor(v / 2 + 0.5) * 2`, which can raise the surface a full stud above the analytic value. Planks are placed at `+0.35` and crates at `+1.2`, so planks can end up beneath the sand.

### `MAX_WATER_FRACTION` is measured against an incomplete island

`IslandShape.new` calls `self:_fitLagoon()` at line 226. `self.river` is assigned at 238 and `self.lake` at 287. `_fitLagoon`'s second pass (`:353`) shrinks the bay while `self:waterFraction() > MAX_WATER_FRACTION`, and `waterFraction` walks `sample`, which reads `self.river` and `self.lake` — both still nil. The comment above the loop states the opposite: "Measured on the real height field, so it accounts for the mouth, the river and the lake all contributing inland water on the same island."

Measured on the catalog:

```
                   fit-time   final
quiet_sand           17.3%    30.0%   <-- at the cap
mistwood             18.5%    29.0%
riverlands           17.0%    27.8%
arrival_hub          18.4%    26.6%
tide_flat            15.9%    26.5%
```

The shrink loop never triggers on any island. The geometric clamp in the first pass still runs, so the land band survives — but the area ceiling is not enforced, and a wider river or a second water body would push an island past it undetected.

`applyOverrides` has the mirror-image gap. `LagoonWidth` (`IslandShape.luau:906`) re-clamps `lagoon.baseR` up to `half * 0.62` — nearly double `_fitLagoon`'s own `half * 0.34` ceiling — without re-running the fit, so a catalog override can breach the coastal land band that `_fitLagoon` exists to protect. `VolcanoOffset` and `VolcanoBaseRadius` likewise move or grow the landmark after `_placeShelf` has already measured the clearing around it; only `SettlementOffset` triggers a re-fit. No catalog entry sets any of these now that the hub's are gone, so this is latent rather than live (**likely**).

### Submerged replay versus the sculpt

`IslandTerrain.submergedPlan` rasterises at step 48 (`IslandTerrain.luau:91`) while `IslandTerrain.stepFor` sculpts at `clamp(size / 90, 8, 16)`. `submergedBoxes` classifies each 48-stud cell from a single centre sample and merges on `math.floor(top * 4)` alone, so land cells all share one key and collapse into large rectangles filled with sand to `seaY - 1.5`.

Comparing the coarse classification against the fine one, cell for cell:

```
arrival_hub    142 fine water cells bulldozed to sand,  122 fine land/shelf cells left unrestored
tide_flat      135                                       96
mistwood       116                                       78
kings_hold      87                                       85
```

Both directions matter. Bulldozed cells fill the below-waterline part of the lagoon mouth and the river banks with sand up to 1.5 studs under the surface — the exact failure the docstring says this pass was written to avoid ("It used to be a single `FillCylinder` per island ... which also flooded the lagoon with sand"). Unrestored cells are worse to look at: the ocean streamer's `FillBlock` wipes everything from `SurfaceY - 56` to `SurfaceY`, so a coarse cell whose centre reads `ocean` leaves the sculpted beach's underwater base gone, undercutting the shoreline where the water meets the sand. It is deterministic rather than cumulative, so the discrepancy is a fixed band roughly one coarse cell wide, not drift.

The chunk scoping checks out: chunk centres are within 181 studs (half-diagonal) of any point in the chunk, and `paintTerrain`'s `maxCoast + 200` reach covers that, so no flooded island is missed. `buildQueuedEndlessIsland` (`IslandService.luau:2514`) is the hole — it calls `paintTerrain()` with no argument, so every endless island build replays the submerged plan of every island in the world. `repaintSubmerged` passes `mayYield = false`, so that is 13 islands x 50-100 boxes today and grows with each endless island generated, which is the unscoped churn the `OceanTerrainService` hunk removed.

### Yield policy, ordering and build cost

`IslandTerrain.sculpt` yields via `task.wait()` every 450 boxes and runs inside `pcall(buildFlatIsland, entry, folder)` (`IslandService.luau:3045`). Roblox's Luau VM permits yielding across a `pcall` boundary, so this does not raise "attempt to yield across a C-call boundary". `ensure()` is only reached through the `_starting`-guarded `IslandService.start`, and `buildQueuedEndlessIsland` is serialised by `_endlessBuildActive`, so the yields do not open a re-entrancy window. Both build paths end with an unscoped `paintTerrain()`, so a stream cycle that Air-fills a chunk over a half-sculpted, not-yet-registered island self-heals before the build path returns.

No forward-reference hazards: every `local function` in `IslandService`, `IslandShape`, `IslandRaster`, `IslandTerrain` and `VillageBuilder` is defined before its first call site, checked mechanically across all five files. Every `shape:` method and `shape.` field the server reads exists on `IslandShape`. No caller of the deleted `generateIslandTerrain` / `generateLagoonHubTerrain` / `generateTwinPeaksTerrain` / `fillFacetedRidge` survives. Every `while` in `IslandShape` advances by a positive step whose floor is either an explicit `math.max(..., 10)` or derived from `self.half`; the one exception is `_fitLagoon`'s `t += self.half * 0.02` (`:343`), which has no floor and would spin forever on `SizeStuds = 0` — the catalog and `Config.Islands.Endless` never produce that, so it is a robustness note rather than a live hang (**possible**).

What does not yield is shape construction and rasterisation: 4.2-8.5 ms to build a shape (the `_placeShelf` grid sweep dominates, ~38k `sample` calls) plus 7.6-9.5 ms to rasterise, per island, in one uninterrupted burst before the first `task.wait()`. `BOXES_PER_YIELD = 450` paces the ~2,000-2,300 `FillBlock` calls per island (~27,800 across the catalog); the 13-19 ms of pure Luau ahead of them is unpaced.

### Village clamping and pier spans

`villageRadius = math.min(villageRadius, buildable / 1.3)` holds: streets reach `1.2 * villageRadius` at most, and measured across the catalog `buildableRadius` lands between 115.5 and 165 with `_shelfFit`'s raw result equal to it on every island. The `math.max(best.radius, self.half * 0.07)` floor at `IslandShape.luau:456` is never reached — but when it is, `_placeShelf` leaves `best.x, best.z` at `0, 0`, so the fallback drops the village at the island centre with a 38-52 stud radius that was never validated as land. Wild-themed islands skip `VillageBuilder`, which keeps the endless islands out of range of this (**possible**).

Reproducing `planIslandFeatures`' bearing choice for all 13 islands, every sea pier's land end samples `land` and its water end `ocean`, with `shoreAngleNear` shifting the requested bearing by at most 0.13 rad.

The lagoon and lake piers were not migrated. `IslandService.luau:2095` keeps `startR = water.radius + 20`, `endR = max(water.radius * 0.58, 124)`, where `water.radius` is now `lagoon.baseR` — the *base* radius of a rim that varies between 0.5x and 1.55x of it. Before this change `features.lagoon` existed only on the hand-authored hub, so the formula ran once against a pinned circular basin. Now every island has a lagoon:

```
mistwood      startR=187.0 -> water    (land end, its barrels and its crate sit over the bay mouth)
raid_cove     endR =124.0 -> land      (T-head and moored rowboat embedded in the far bank)
```

The two mountain isles get a lake pier, where `endR = 124` is a constant sized for the starter raft (`SizeStuds * 0.5 + RaftCollisionPad + 40`) applied to a lake whose rim is 42-76 studs, so the pier runs outward past its own lake. That formula is unchanged from `origin/main`, but the lake shrank from `half * 0.17` to `half * 0.115` in this change, so the overshoot roughly doubled.

</details>

<details>
<summary>Files changed</summary>

- `src/shared/IslandShape.luau` (new, 1041) — pure-Luau silhouette generator: harmonic coast, fitted off-centre lagoon with a flared mouth, meandering river, faceted landmark, settlement clearing, placement helpers, catalog overrides.
- `src/shared/IslandRaster.luau` (new, 274) — samples the shape on a grid, greedy maximal-rectangle merge, full and submerged terrain plans.
- `src/server/IslandTerrain.luau` (new, 100) — writes the plans as `FillBlock` Terrain, maps material strings to `Enum.Material`, yields every 450 boxes on the full build and never on the repaint.
- `src/server/IslandService.luau` (-1,508 / +~500) — three terrain generators and two island styles deleted; features, props, docks, lighthouse, trails, raft collision, `pointOnIsland` and the submerged repaint rewired onto the shape.
- `src/server/VillageBuilder.luau` — settlement radius and castle footprint capped by `deps.buildableRadius`.
- `src/server/OceanTerrainService.luau` — records the chunks filled each cycle and scopes `paintTerrain` to them.
- `src/shared/Config.luau` — arrival hub's lagoon, volcano offset and settlement overrides removed; `Volcano` / `VolcanoHeight` / `VillageRadiusFactor` kept.
- `tests/IslandShape.spec.luau` (new, 587), `tests/IslandPreview.luau` (new, 269), `tests/helpers/Catalog.luau` (new, 142), `tests/Syntax.spec.luau` (new, 53), `tests/IslandWorld.spec.luau` — 286 + 31 assertions plus a compile pass and PNG previews; all green on this branch.
- `.github/workflows/island-geometry.yml` (new) — runs the four suites on every push and PR, uploads the previews.

Full diff: `git diff origin/main` (merge base `f6c7cf1`, commits `7096737..1b67c2e`).

</details>
