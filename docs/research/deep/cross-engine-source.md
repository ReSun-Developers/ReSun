# Cross-Engine Source Architecture — Tiberian Sun / Firestorm / Red Alert 2 / Yuri's Revenge

Deep-research reference for the unified ReSun RTS engine. **Engine architecture only** —
no content rosters, no tuning. Every claim is sourced from released/leaked official engine code,
open-source engine reconstructions, the official map-editor source, or community engine-extension
documentation. No source code is quoted in this document; class, function, and enum names are
referenced as architecture facts only.

## Provenance and source-quality note (read first)

| Source | What it is | Trust |
|--------|-----------|-------|
| `electronicarts/CnC_Tiberian_Dawn`, `electronicarts/CnC_Remastered_Collection` | **Official EA-released** TD + RA1 (first-generation) engine source | High (authoritative) |
| `TheAssemblyArmada/Vanilla-Conquer` | Port of that EA-released first-gen source | High |
| `OpenTS-Developers/TibSun` | Community **reconstruction** of the Tiberian Sun engine, partly derived from EA's RA source | Medium-High for TS |
| `Vinifera-Developers/TSpp`, `Ares-Developers/YRpp` | Community C++ headers that map the shipped TS / YR binaries (class layouts, vtables, globals) | Medium (binary-mapped) |
| `electronicarts/CNC_TS_and_RA2_Mission_Editor` | **Official EA-released** FinalSun + FinalAlert2 editor source | High for map/scenario data model |
| `Vinifera`, `Ares`, `Phobos` docs | Open engine extensions; document hardcoded engine behaviour and limits | Medium-High |
| `OpenRA` | Independent clean-room reimplementation of the **first-gen** engine (TD/RA1). Used for cross-check and generic-architecture confirmation, **not** as evidence for TS/RA2 internals | Medium (lineage only) |
| ModEnc pages | Community reverse-engineering wiki | Medium (cross-checked) |

**Critical provenance fact:** EA's 2020 and 2025 source releases cover **Tiberian Dawn, Red Alert,
Remastered, Renegade, Generals, Zero Hour — not Tiberian Sun, Firestorm, Red Alert 2, or Yuri's
Revenge** (`electronicarts` GitHub org; confirmed by the OpenRA maintainers in issue #21767).
TS/RA2/YR architecture below therefore rests on (a) EA's first-gen RA/TD source, which TS was
forked from, (b) the OpenTS reconstruction, (c) FA2/FinalSun's official map code, and (d) binary
mappings and extension DLLs. Where a fact is reconstruction-only it is marked lower confidence.

---

### X-ENG-001 Simulation Loop, Tick Model, Frame Rate, Determinism

**What.** The fixed-step game clock. Everything gameplay-relevant advances in discrete "logic
ticks" (a.k.a. frames); rendering and input run on a separate, faster loop.

**Architecture/logic.** Tiberian Sun defines a hard constant of **15 logic ticks per second**
(`TICKS_PER_SECOND = 15`, with `TICKS_PER_MINUTE` and `TICKS_PER_HOUR` derived from it). The main
application loop is a render/input loop; a separate logic accumulator (`FrameTimer`, `NetFrameTimer`)
consumes elapsed wall-clock time and calls the logic subsystem once per accumulated tick. Each
logic tick executes a fixed, ordered pipeline:

1. **Global/timer trigger pass** — the `LogicClass` walks its list of "logic tags" (global,
   time-based and map-wide triggers) and evaluates events such as elapsed time, random time,
   mission-timer expiry, global/local flag changes, crate pickup, ambient-light change.
2. **Environmental pass** — shroud regrowth, fog-of-war spread, ice growth/solidification, terrain
   deformation, veinhole and Tiberium growth/spread, ambient-light fade, ion storm and EMP updates.
3. **Team AI pass** — every live `TeamClass` instance runs `AI()`.
4. **Transient systems** — spotlights, laser draws, ion storms, light sources, EMPulse, then a
   **terrain-deformation pass**.
5. **Object AI pass** — a layer/list of every "sentient" object (`ObjectClass` subclass) is walked;
   each `obj->AI()` runs. This is where a `TechnoClass` scans for threats and fires, and where a
   `FootClass` (after its Techno base) drives its **locomotor**: `Locomotion->Process()` is called
   inside the foot-object AI, not in a separate global pass.
6. **Map logic**, then the tactical/display `AI()`, then **factory AI** (each `FactoryClass`'s
   production timer), then **house AI** (each `HouseClass::AI()`, including the computer
   opponent's production and strategy).

The tick counter is a global `Frame` integer. Mission delay constants are expressed in ticks via
`TICKS_PER_MINUTE * rate`. The multiplayer model uses the same `Frame` as the authoritative clock
(see X-ENG-012).

**Determinism.** The simulation is deterministic lockstep. The only randomness source is a single
seeded pseudo-random generator (`RandomClass`, a 15-bit LCG-like generator; a faster 32-bit variant
also exists). The seed is shared/synchronised across clients. Simulation-relevant state is
periodically hashed with `Compute_CRC` on objects, houses and scenario state, and a mismatch flags
`OutOfSync`. Anything that would break ordering (iteration over unordered containers, frame-rate-
dependent physics) is avoided; object updates iterate stable layer lists and factories/houses in
fixed index order.

**Mapping to a unified engine.** Keep a two-rate architecture: a **fixed logic tick** (choose a
single canonical rate, e.g. 15 or 30 Hz, and never let rendering influence it) and a decoupled
render/input loop. Implement the tick as an explicit ordered phase pipeline (triggers → environment
→ teams → objects → production → house AI) so ordering is a documented contract, not an accident.
Use one seeded, serialisable RNG owned by the simulation; never call wall-clock or OS entropy from
simulation code. Add a periodic state-hash/desync detector for multiplayer from day one — it is far
cheaper to build than to retrofit. Prefer integer/fixed-point simulation math over float where it
matches the original's step semantics.

**Sources.**
- OpenTS reconstructed TS: `https://github.com/OpenTS-Developers/TibSun` (`code/logic.cpp`, `code/mainloop.cpp`, `code/stimer.h`, `code/random.h`, `code/foot.cpp`)
- EA/Red-Alert first-gen source: `https://github.com/TheAssemblyArmada/Vanilla-Conquer` (`common/timer.*`, `redalert/` logic)
- CnC Remastered source: `https://github.com/electronicarts/CnC_Remastered_Collection`
- OpenRA deterministic lockstep (lineage cross-check): `https://deepwiki.com/OpenRA/OpenRA/3-game-engine-core`

**Confidence.** High for the 15-tick fixed step, the ordered pass list, and deterministic lockstep;
Medium for the *exact original* ordering (the OpenTS tree splits a "logic AI" and an "environment
AI" helper, which may be a reconstruction artifact rather than the shipped pass structure).

---

### X-ENG-002 Object/Type Class Model, Allocation, Ownership, Lifecycle

**What.** The object model: a deep "object instance" hierarchy for things in the world, a parallel
"type" hierarchy for immutable definitions, plus COM-based class registration and a limbo-based
lifecycle.

**Architecture/logic.**

*Instance hierarchy* (world objects):

- `AbstractClass` (base; implements persistence and RTTI)
  - `ObjectClass` (has a coordinate, a type pointer, and is submitted to a render/logic layer)
    - `MissionClass` → `RadioClass` → `TechnoClass` (armed/owned mobile or structure) →
      **`FootClass`** → `UnitClass`, `InfantryClass`, `AircraftClass` (and `VesselClass` in RA2)
      and **`BuildingClass`** (off `TechnoClass` directly)
    - `AnimClass`, `BulletClass`, `OverlayClass`, `SmudgeClass`, `TerrainClass`,
      `ParticleClass`, `ParticleSystemClass`, `VoxelAnimClass`, `WaveClass`,
      `IsometricTileClass`, `BuildingLightClass`, `VeinholeMonsterClass`, `FoggedObjectClass`
  - `HouseClass`, `TeamClass`, `TriggerClass`, `TActionClass`, `TEventClass`, `ScriptClass`,
    `SuperClass`, `FactoryClass`, `LightSourceClass`, `WaypointPathClass`, `BrainClass`/`NeuronClass`

*Type hierarchy* (singletons, one definition per type):

- `AbstractTypeClass` → `ObjectTypeClass` → `TechnoTypeClass` → `UnitTypeClass`,
  `InfantryTypeClass`, `AircraftTypeClass`, `BuildingTypeClass`; siblings `AnimTypeClass`,
  `BulletTypeClass`, `OverlayTypeClass`, `SmudgeTypeClass`, `TerrainTypeClass`,
  `ParticleTypeClass`, `ParticleSystemTypeClass`, `VoxelAnimTypeClass`, `IsometricTileTypeClass`
- `WarheadTypeClass`, `WeaponTypeClass`, `SuperWeaponTypeClass` (off `AbstractTypeClass`)
- `HouseTypeClass`, `SideClass`, `TeamTypeClass`, `TaskForceClass`, `ScriptTypeClass`,
  `TriggerTypeClass`, `AITriggerTypeClass`, `TiberiumClass`, `CampaignClass`, `TagTypeClass`

**Key split:** instances are created and destroyed; **types are immutable singletons created once
from INI at load** and referenced by index ("type number"). A target/ID value in the engine is a
packed word that encodes both the RTTI category and the type index, so a weapon reference or a
`Prerequisite` entry is just a type number.

**Allocation.** Types are held in global dynamic vectors (e.g. a `UnitTypes` list, `InfantryTypes`,
`BuildingTypes`, `Weapons`, `Warheads`). A `Find_Or_Make` static per class returns an existing type
by name or constructs a new one and appends it, assigning its index. Instance classes override
`operator new`/`operator delete` to allocate from **fixed-size memory pools** (pools whose maximum
is set by a `Heap_Maximums` rules pass before the rule file is processed). This makes allocation
deterministic and avoids fragmentation.

**Registration.** Type and instance classes are registered with COM-style class IDs at startup.
A startup table maps C++ class ↔ `CLSID_*`; a class factory instantiates by CLSID. This is the
foundation of pluggable subsystems (notably locomotors, X-ENG-004). Objects expose `GetClassID`,
`QueryInterface`, `Save`/`Load` (IPersistStream), `Compute_CRC`, and `Fetch_RTTI`.

**Ownership.** A `TechnoClass` holds a `House` pointer. The `HouseClass` maintains per-house lists
of its objects, base nodes, factories and superweapons. Ownership can change at runtime
(`TACTION_CHANGE_HOUSE`, `TACTION_ALL_CHANGE_HOUSE`) and through capture/infiltration; TS also has
mind-control implemented as a `BrainClass`/`NeuronClass` graph that owns target objects' orders
(a "neuron" is linked to a brain; a captured unit's neuron is added to the controller's brain).

**Lifecycle.** `new` → construct → **`Unlimbo`** (place in the world and submit to the render/logic
layer) → active; **`Limbo`** removes it from display/simulation while it still exists (in a
transport, a factory, under construction, or hidden). Destruction calls `Mark_To_Delete` and later
`delete`. "Underground/subterranean" is a movement state of a foot object, not a separate object.
Buildings under construction are limboed and inactive. This limbo concept is the load-bearing part:
sub-objects (passengers, production, deployed states) are real objects in a dormant state, not
separate data structures.

**Mapping to a unified engine.** Split **data (type/definition)** from **runtime (instance)** hard,
and make definitions immutable and shared. Give every type a stable numeric ID and reference types
by ID everywhere (weapons, warheads, prerequisites, spawns) rather than by pointer/string at
runtime. Use a component-composition model at the instance layer (Redot nodes + components) while
keeping the *type* side as pure data resources. Implement an explicit **limbo/active state
machine** for instances (world-active, limboed, under-construction, carried) rather than ad-hoc
`visible`/`queued` booleans. Reserve object-type IDs at load in a deterministic order and expose a
"create-or-get by name" registry. Preallocate/pool hot object categories if profiling demands it.
Model mind-control/passenger/transport as ownership/containment relationships between instances,
not as special-case fields.

**Sources.**
- OpenTS class hierarchy and `Find_Or_Make`/pool/registration patterns: `https://github.com/OpenTS-Developers/TibSun` (`code/abstract.*`, `object.*`, `techno.*`, `foot.*`, `objtype.*`, `techtype.*`, `startup.cpp`, `brain.*`, `classfactory.h`)
- First-gen equivalent (EA source, confirms shared lineage): `https://github.com/TheAssemblyArmada/Vanilla-Conquer` (`redalert/object.*`, `techno.*`, `type.h`)
- YR binary class layout headers: `https://github.com/Ares-Developers/YRpp` (`GameClasses.h`), `https://github.com/Vinifera-Developers/TSpp`

**Confidence.** High for the hierarchy, type-singleton model, registration, and limbo lifecycle
(consistent across EA source, reconstruction and binary maps). Medium for exact pool sizing and
the precise set of instance classes per add-on.

---

### X-ENG-003 INI Loader Architecture, Type-List Registration, Overrides, `Image=` Resolution

**What.** The text configuration system that defines all game data: `rules.ini`, `art.ini`,
`ai.ini`, `sound.ini`, `theme.ini`, `eva.ini`, plus per-map overrides.

**Architecture/logic.** Two layers:

1. **Generic parser (`INIClass`)** — parses `[Section]` / `Key=Value` text into an ordered
   section list, each section an ordered entry list. Sections and keys are **case-sensitive**. Typed
   accessors (`Get_Int`, `Get_Bool`, `Get_String`, `Get_Fixed`, `Get_Hex`, `Get_TextBlock`,
   `Get_UUBlock`, `Get_PKey`) parse values on demand. An extended subclass (`CCINIClass`) adds
   game-typed getters (`Get_Lepton`, `Get_HousesType`, `Get_ThemeType`, `Get_CLSID`,
   `Get_BuildingType_List`, `Get_ArmorType`, etc.) and can carry a digest for verification. The
   parser is line-oriented and has known quirks: a trailing section needs a dummy line to be read
   in RA2, values beyond a length cap can be lost, and a missing/duplicate numbered entry changes
   interpretation.

2. **Rule loading (`RulesClass::Initialize` / `Addition`)** — the loader deletes all existing types,
   loads `art.ini` (and `artfs.ini`), then calls an **ordered set of `Do_*` registration methods**,
   then reads the behavioural sections. The registration order is fixed and matters:
   colors → houses → sides → overlays → superweapons → warheads → smudges → terrain → buildings →
   vehicles → aircraft → infantry → anims → voxel anims → particles → particle systems →
   global/AI/IQ/difficulty rules → tiberium.

   Each `Do_*` method reads an **indexed type list** (e.g. `[VehicleTypes]` with entries
   `0=...`, `1=...`), counts entries, and for each name calls that type class's `Find_Or_Make`.
   **The type's constructor then reads its own section** by its INI name. So "index order in the
   type list" *is* the runtime type index, and a mod that reorders the list shifts every index.

**Overrides and layering.** Later INI loads merge into the already-built database by name
(`Find_Or_Make` returns the existing type, whose `Read_INI` re-reads and overwrites fields):
`LANGRULE.INI`, `ARTFS.INI`, `FSRULE.INI`, `LANGFS.INI` for Firestorm, and per-map files loaded
after the rules. A repeated name updates in place; a new name appends. This is how add-ons patch
the base game without a separate database.

**Per-map overrides.** A map/scenario file is itself an INI that can redefine object sections,
house data and global flags; the scenario layer is read after the rules, so map-local values win.
The official FinalSun/FinalAlert2 editor writes and re-reads these files and can embed rules
overrides directly in the map (`Basic` and object sections).

**`Image=` resolution.** `TechnoTypeClass`/`ObjectTypeClass` hold both an `IniName` (rules section)
and an `Image` name (art section) plus an alternate image file. Resolution walks `art.ini` for the
art section named by `Image` (defaulting to the rules section name) and then picks the concrete
asset: if `Voxel=yes`, load `<image>.vxl` + `<image>.hva`; otherwise load `<image>.shp` (with an
optional `.shp` alternate). Extras: a body plus a barrel/turret voxel (`<image>barl`,
`<image>tur`); TS hardcodes a water image (name + `w`) for amphibious vehicles; harvesters swap to
an unloading class while docking; `UnloadingClass` (RA2) and `WaterImage`/`AlternateTheaterArt`
(Ares) generalise this. Per-theater art and per-side art select different files at load.

**Mapping to a unified engine.** A single, well-specified INI/`ConfigFile` parser with typed
accessors is the right shape; keep case-sensitive keys for migration fidelity but consider
case-insensitive-with-warning as an option. Preserve the **explicit ordered type registration**
model: load type lists in a documented order, assign dense stable IDs, then let each type read its
own section. Make "create-or-get by name then re-read" the single override mechanism — this
replaces a whole class of special-case patch loaders. Treat `Image=`/art as a **separate visual
lookup layer** keyed by name, decoupled from rules, and design the resolver as: rules name → art
section → per-theater/per-side/per-state asset, with a default fallback. Version the parser and
reject/fix known traps (missing trailing section). Support per-map override files explicitly, and
make the map format embed overrides the same way the official editor does.

**Sources.**
- OpenTS `CCINIClass`, `RulesClass::Addition`, ordered `Do_*` registration, `Image=` fetch, `Find_Or_Make`: `https://github.com/OpenTS-Developers/TibSun` (`code/ccini.*`, `rules.cpp`, `unittype.cpp`, `techtype.cpp`, `objtype.*`)
- EA first-gen `INIClass` and rules: `https://github.com/TheAssemblyArmada/Vanilla-Conquer` (`common/ini.h`, `redalert/rules.cpp`, `redalert/ccini.*`)
- ModEnc: `https://modenc.renegadeprojects.com/Rules.ini`, `.../Art.ini`, `.../Image`, `.../INI-Editing`
- Official map editor source: `https://github.com/electronicarts/CNC_TS_and_RA2_Mission_Editor`

**Confidence.** High for parser shape, registration order, override-by-name and `Image=` resolution.
Medium for the exact original list of `Do_*` calls (reconstruction gives a complete, plausible
order) and for debug-vs-release parser differences.

---

### X-ENG-004 Movement Architecture: Locomotors, Movement Zones, Pathfinding, Occupancy

**What.** How units move: pluggable motion behaviours, terrain-passability zoning, a two-tier
pathfinder, and cell/sub-cell occupancy with collision resolution.

**Architecture/logic.**

*Locomotors.* Movement behaviour is **COM-pluggable**. `TechnoTypeClass` stores a `Locomotor`
CLSID, chosen from the INI `Locomotor=` string; a name→CLSID table maps aliases to class IDs. Known
locomotors: **Drive** (wheeled/tracked ground), **Walk** (infantry legs), **Fly**, **Hover**,
**Jumpjet**, **Mech** (walker legs), **Tunnel** (subterranean dig), **DropPod/Ballistic**,
**Teleport** (chrono), **Levitate**, **Ship** (naval), **Rocket** (RA2). An invalid/absent value
defaults to **Teleport**. Each locomotor implements the `ILocomotion` interface and is registered
at startup like any other class: query `Is_Moving`, `Destination`, `Head_To_Coord`,
`Can_Enter_Cell`, `Is_To_Have_Shadow`, `Draw_Matrix`/`Draw_Point` (where to render), `Process`
(per-tick step), `Move_To`/`Stop_Moving`/`Do_Turn`, `Unlimbo`, `Tilt_Pitch_AI`, `Power_On/Off`,
`Is_Powered`, `Is_Ion_Sensitive` (EMP/ion-storm interaction), `Push`/`Shove`/`In_Which_Layer`,
`Apparent_Speed`, `Can_Fire`, `Mark_All_Occupation_Bits`, etc. The per-tick `Process()` is the
actual motion integration: drive has turn rate + acceleration + facing, walk has leg-phase frames,
fly has waypoint turning and banking, jumpjet has takeoff/landing, tunnel digs and resurfaces,
teleport has a cooldown and map-wide hop.

*Movement zones.* `MovementZone` selects the pathfinding passability profile and implicit
capabilities: `Normal`, `Crusher`, `Destroyer`, `AmphibiousDestroyer`, `AmphibiousCrusher`,
`Amphibious`, `Subterranean`, `Infantry`, `InfantryDestroyer`, `Flyer` (TS enum; RA2/ModEnc adds
`Water`, `WaterBeach`, `CrusherAll`). A zone controls whether the unit treats ground/water as
passable, whether it assumes it can crush infantry/vehicles, whether it can destroy terrain
obstacles, and whether it digs or swims. Separately, **`SpeedType`** governs the actual speed on a
given terrain — MovementZone decides *where*, SpeedType decides *how fast*. The engine evaluates
`Can_Enter_Cell` against the cell's land type, occupancy, bridge state, zone, and locomotor rules.

*Pathfinding.* `FootClass::Find_Path` delegates to a global `AStarClass`. It is **two-tier**:

- **Hierarchical A\***: the map is partitioned into subzones at three coarseness levels
  (`SUBZONE_FINE`, `SUBZONE_ROUGH`, `SUBZONE_COARSE`). A coarse-to-fine A\* search over subzone
  adjacency produces a "corridor" (stamped subzones) between start and goal.
- **Cell-level A\***: an 8-neighbour (facing-8) A\* then searches the real cell grid, optionally
  **confined to the corridor**; if the corridor proves unwalkable the flag flips and the search
  retries unrestricted. The search uses fixed node pools (a large node pool and a smaller open-set
  pool), an open set ordered by score, **unique-ID stamping** of visited/cost tables (so searches
  need no full clear), and separate cost/visited tables for ground and bridge elevation (a cell can
  be occupied twice, once on the deck, once beneath).

Costs incorporate terrain, locomotor entry legality, object speed, and **obstacle avoidance**:
moving blockers are priced up, with `AVOIDANCE_NONE` / `SOFT` (≈4×) / `HARD` (≈1000×); an
optional path-collision-avoidance mode prices cells that slower units are about to cross so fast
units route around queues. Bridges can be penalised. Post-processing cuts corners, plots straight
lines where clear, and splices/optimises move sequences before returning a compact facing list.
Subzone edges can be temporarily "banned" (e.g. blocked by objects) and the zone graph rebuilt.

*Occupancy and collision.* This is **not a physics engine**. Each cell carries an 8-bit occupancy
mask: five **sub-positions** (`Center`, `NW`, `NE`, `SW`, `SE`) plus `Vehicle`, `Monolith`
(immovable blocker) and `Building` bits. Vehicles claim the whole cell (the `Vehicle` bit);
infantry claim a single sub-position. A **bridge deck has its own parallel occupancy mask** for the
same cell, so ground and deck are independent surfaces. `Closest_Free_Spot` picks the nearest free
sub-position using a precomputed nearest-first sequence (with a mix-up table when the centre is
taken). Blocking resolution is by `Can_Enter_Cell` / `Blocking_Object` checks and by **scattering**:
a moving unit that overlaps a blocked peer triggers `Scatter`, and a blocked unit scatters to a
nearby free sub-position; infantry hold sub-position slots so several can share a cell. Units are
"shoved"/pushed out of illegal overlaps rather than physically repelled.

**Mapping to a unified engine.** Model movement as a **strategy/plugin** (a Redot component or
resource-defined locomotor) behind one interface (`process_tick`, `can_enter_cell`, `move_to`,
`stop`, `draw_transform`). Keep `MovementZone` (legal space + crushing + layer) and `SpeedType`
(speed per terrain) as orthogonal data. Build a **hierarchical pathfinder** from the start: zone/
region graph for long routes, grid A\* confined to a corridor for the last stretch; use integer
costs and stable tie-breaks for determinism. Implement occupancy as a **cell + sub-slot reservation
map** (exactly what Redot's `CellReservation` models): N sub-slots per cell, a separate deck/bridge
layer, vehicles taking the whole cell, infantry taking a slot. Resolve conflicts by reservation +
scatter/retry, not physics. Expose obstacle-avoidance as a per-order setting. Keep bridge/under-
bridge as two logical surfaces.

**Sources.**
- OpenTS: `ILocomotion` interface (`code/iloco.h`, `ilocos.h`), locomotor registration (`startup.cpp`, `drive.cpp`, `walk.cpp`, `fly.cpp`, `jumpjet.cpp`, `mech.cpp`, `hover.cpp`, `tunnel.cpp`, `teleport.cpp`), `MZoneType` (`code/mzone.hh`), hierarchical + cell A\* (`code/astar.h`, `astar.cpp`), occupancy/sub-positions (`code/cell.h`, `cell.cpp`), scatter/blocking (`code/foot.cpp`, `unit.cpp`)
- ModEnc: `https://modenc.renegadeprojects.com/Locomotor` (CLSID table and behaviour), `.../MovementZone`
- OpenRA hierarchical pathfinder (cross-check of the two-tier idea): `https://deepwiki.com/OpenRA/OpenRA/3.2-actor-trait-activity-system`, `OpenRA.Mods.Common/Pathfinder/HierarchicalPathFinder.cs`

**Confidence.** High for the COM-locomotor model, the CLSID aliases, MovementZone/SpeedType split,
the two-tier pathfinder, and the 5-sub-position + bridge occupancy model. Medium for exact A\* cost
constants, subzone construction algorithm, and shove/scatter edge behaviour (reconstruction).

---

### X-ENG-005 Weapon / Warhead Resolution, Targeting Hierarchy, Projectiles, Splash

**What.** The firing chain and damage model: weapon type → projectile → warhead → per-armour
modifier → target damage, plus target acquisition.

**Architecture/logic.**

*Weapon data.* `WeaponTypeClass` (indexed, named in `[Weapons]`, read from its own section) holds
attack, rate-of-fire, range, burst/ammo/charge, projectile type (`BulletTypeClass`), warhead type
(`WarheadTypeClass`), firing sounds, and flags (laser, sonic, railgun, ambient damage, etc.). A
`TechnoTypeClass` provides **primary and secondary weapon slots** (and passengers/occupants may
have their own). Weapon type numbers are the unit of reference everywhere.

*Targeting.* A `TechnoClass` maintains a target (`TarCom`) and a navigation/order state. Each tick
its AI decides whether to acquire, retain or drop a target: explicit player orders first, then
guard/attack-move scans, then **passive auto-acquisition** (gated by `CanPassiveAcquire` and by
threat type), then retaliation to attackers. Target scanning is range- and threat-driven
(`WeaponTypeClass::Allowed_Threats`, `ThreatRange`). `TechnoClass::AI` also handles firing
cadence.

*Weapon choice.* `What_Weapon_Should_I_Use(target)` scores the primary vs secondary weapon by the
warhead's damage **multiplier against the target's armour class** (`Warhead->Modifier[armor]`
× 1000), doubling a weapon's score when the target is in range, and accounting for special cases
(e.g. web weapons vs web-capable targets). The chosen slot goes through `Can_Fire(target, which)`
which returns a `FireErrorType` (cannot fire, illegal, rearming, etc.).

*Firing chain.* `Fire_At(target, which)`:
1. Resolve the chosen weapon and its projectile type; early-out for special "particle/railgun/
   sonic" weapons that are drawn rather than spawned.
2. Compute the destination coordinate (object's target coordinate or the abstract's coordinate).
3. Compute firepower = `Attack` × house `FirepowerBias` × veterancy bonuses; some weapon kinds
   (sonic, fire-particle) deal zero direct bullet damage.
4. Create a `BulletClass` (`Create_Bullet`) with the projectile type, owner, warhead, speed,
   range, and a target. The bullet is briefly limboed and positioned at the turret coord.
5. Moving platforms mark the projectile inaccurate; arcing/inaccurate projectiles apply random
   ballistic scatter. Homing/dropping projectiles launch along the turret facing rather than at
   the target.

*Projectile motion.* `BulletTypeClass` parameters govern flight: turn rate (ROT), whether it arcs,
drops, homes, is invisible, is anti-ground/anti-air, etc. The bullet integrates toward the target
(or a predicted lead point) each tick and detonates on arrival/proximity/expiry, then applies its
warhead.

*Damage resolution.* `Modify_Damage(damage, warhead, armor, distance)`:
- Return 0 if inert/zero/no warhead.
- Negative damage is healing, applied only within a close range.
- `modified = damage × Warhead->Modifier[armor]` (the **Verses** table: one multiplier per armour
  class; `WarheadTypeClass::Modifier[]` is indexed by armour type).
- Distance fall-off: divide by `distance / (SpreadFactor × cell/3)` (or `distance / (cell/4)` if no
  spread factor), clamp the divisor to 0–16, and enforce a minimum damage when very close; cap at
  the global max damage. The result is then applied through the target's damage path (armour,
  shields, special warhead flags such as wall/wood destruction, limpet, web, EMP, locomotor
  assignment).

*Splash.* Blast area is defined by `CellSpread` on the warhead. Despite the name, it is computed as
a **3D lepton sphere**, not a square of cells: the engine rounds `CellSpread` up, looks up an
affected-cell table, also consults a separate 20×20 **air grid** to find flying units
(fly/jumpjet/rocket), halves the effective distance for high-airborne objects, and damages every
object whose 3D lepton distance ≤ `CellSpread × 256`. Overlay interactions are handled per cell
(chain-reactive Tiberium, walls, `Explodes=yes` overlays). Warheads also carry cell-spread-relative
effects such as `PercentAtMax` fall-off. Effect animations/sounds are spawned from the warhead's
behaviour.

**Mapping to a unified engine.** Define weapons/warheads/projectiles as immutable data resources
with stable IDs; keep the **Verses matrix** (warhead × armour) as first-class data. Implement
targeting as an explicit priority chain (player order → script → scan → retaliation) with a threat
model, and expose passive acquisition as a per-type flag. Route all damage through **one**
`apply_damage` funnel that does armour-multiplier → distance fall-off → caps → special-effect
dispatch; never let individual weapons special-case damage. Model splash as **radius in world
units** (a sphere), with a separate aerial lookup and an overlay/terrain interaction pass. Pipeline
the shot as weapon → projectile spawn → flight → detonation → warhead effect so beam/instant/
particle weapons are just projectile types with different behaviour.

**Sources.**
- OpenTS: `WeaponTypeClass`, `WarheadTypeClass`, `Modify_Damage`, `What_Weapon_Should_I_Use`, `Can_Fire`, `Fire_At`, bullet detonation: `https://github.com/OpenTS-Developers/TibSun` (`code/weapon.cpp`, `warhead.cpp`, `combat.cpp`, `techno.cpp`, `bullet.cpp`, `weapon.h`, `warhead.h`)
- ModEnc: `https://modenc.renegadeprojects.com/Verses`, `.../CellSpread`
- Ares/Phobos warhead extensions (confirming hardcoded limits): `https://ares-developers.github.io/Ares-docs/new/index.html` (Additional ArmorTypes and Verses), `https://phobos.readthedocs.io/en/latest/`

**Confidence.** High for the chain, weapon-choice scoring, verses-matrix damage, and 3D-sphere
splash. Medium for exact splash table contents and projectile-type special cases.

---

### X-ENG-006 Power, Production/Queue, Prerequisite Resolution

**What.** The economy of power, the production pipelines, and the tech tree gate.

**Architecture/logic.**

*Power.* `BuildingTypeClass::Power` is signed: positive supplies, negative consumes
(`Powered=yes` structures can be switched off/toggled). A `HouseClass` aggregates total output and
drain and exposes a `Power_Fraction()` (supply/demand, ≥1 = healthy). Low power halves production
speed and disables radar and superweapons. Buildings implement a COM `IPowerEvents` callback so the
house can notify them (`Power_Lost`/`Power_Activated`) when the grid crosses the threshold,
letting them shed load (e.g. turn off optional weapons) or come online. A `PowerClass` UI
component renders the sidebar power bar. EMP and ion storms suppress powered mobility/defences.

*Production.* Each producer (war factory, barracks, helipad, shipyard) owns a `FactoryClass`,
which carries the object under construction, a stage/progress counter (a `StageClass`), and a
build rate. `Cost_Per_Tick` spreads the total cost across the build time; each tick `AI()` advances
progress; `Suspend`/`Start`/`Abandon` (with refund) control the pipeline; `Has_Completed` signals
readiness; the finished object is placed/limboed until placement. A `HouseClass` owns **per-
category queues** (infantry, vehicle, aircraft, building, plus special/defensive categories) and
provides `Begin_Production`, `Suspend_Production`, `Abandon_Production`, `Place_Production`, and
`Suggest_New_Object`. The sidebar (`SidebarClass`/`TabClass`) is the UI over those queues. Multiple
producers of a category grant a speed bonus, and power modifies rate.

*Prerequisites.* `TechnoTypeClass::Prerequisite` is a list of building-type numbers. The build
check (`HouseClass::Can_Build`) evaluates, in order:
- `TechLevel` within the allowed range;
- `ForbiddenHouses` / `RequiredHouses` / `Owner`;
- all `Prerequisite` buildings owned (upgrades on those buildings count as satisfying them);
- stolen-tech requirements (`RequiresStolen*Tech`) if any.
Then actual buildability requires an appropriate `Factory` for the object's category (and for
vehicles, the factory's naval flag must match the vehicle's). **Prerequisite groups** are named
rule lists (POWER, PROC, BARRACKS, FACTORY, RADAR, TECH, and in Firestorm GDIFACTORY/NODFACTORY)
where owning any member satisfies the group. `PrerequisiteOverride` and `SecretLab=yes` bypass the
normal list. The **AI deliberately ignores most prerequisites** and builds by `AIBuildThis` and
the order in `ai.ini`.

**Mapping to a unified engine.** Represent power as a per-player **supply/demand sum with a
fraction** and a threshold event bus (buildings react to under/over-power). Model production as a
**queue per category with a producer capability**, where progress is time/cost based and multiple
producers give diminishing speed bonuses. Represent the tech tree as a **data-driven prerequisite
expression** evaluated against a per-player capability set (owned building types, upgrades, stolen
tech, houses), with named groups for alternatives. Keep AI build rules separate from the human
prerequisite check — the original intentionally decouples them, and it is a useful separation.

**Sources.**
- OpenTS: `HouseClass::Power_Fraction`/`Can_Build`/`Begin_Production`, `FactoryClass` (`Cost_Per_Tick`, `Suspend`, `Start`, `Abandon`, `Completion`), `TechnoTypeClass::Prerequisite`, prerequisite groups, `IPowerEvents`: `https://github.com/OpenTS-Developers/TibSun` (`code/house.cpp`, `factory.cpp`, `power.cpp`, `techtype.cpp`, `rules.cpp`)
- ModEnc: `https://modenc.renegadeprojects.com/Power`, `.../Prerequisite`, `.../The_Prerequisite_System`
- Ares prerequisite extensions: `https://ares-developers.github.io/Ares-docs/new/prerequisites.html`

**Confidence.** High for power semantics, production pipeline shape, and prerequisite evaluation
order. Medium for exact per-category factory rules and the precise AI build heuristic.

---

### X-ENG-007 Vision, Shroud/Fog, Radar

**What.** Per-player visibility and the minimap.

**Architecture/logic.** Visibility is stored as **bitfields on each map cell**:
`IsMapped` (shroud permanently cleared), `IsVisible` (inside current sight), `IsFogVisible` /
`IsFogMapped` (fog-of-war states). Crucially, in TS/RA2 the engine maintains this only **for the
local player**: `MapClass::Sight_From` computes the visible radius from a source coordinate and
returns early if the observing house is not `PlayerPtr`. Ally reveal and `RadarSpied` can transfer
sight to the local player. Sight uses precomputed radius/occlusion offset tables, scans full or
incremental rings, clamps sight range, and respects **height occlusion** (isometric terrain
occludes by comparing cell height along the view line when `IsRevealByHeight`). Shroud regrows
(`Encroach_Shadow`) and fog spreads (`Encroach_Fog`) at rule-driven rates. Special reveal effects
(spotlights, gap generators, radar-spy, map-wide reveal actions) call the same mapping functions.
A `FoggedObjectClass` records "last seen" overlay/building snapshots so fog shows a frozen image
of what was there rather than empty ground.

*Radar.* `RadarClass` (part of the sidebar hierarchy) maintains a per-player minimap render target
built from mapped cells: terrain/overlay/objects are plotted cell by cell (`Radar_Pixel`,
`Render_Terrain`, `Render_Overlay`, `Render_Infantry`), one pixel per cell. Radar availability
requires a building with `Radar=yes` and sufficient power; `RadarJammed` (jammers) blacks it out
for the affected player(s); ion storms can disable it. `RadarEventClass` handles attention pings,
and radar supports zoom and player-name overlays.

**Mapping to a unified engine.** Store visibility as a **per-player grid** (bitmask per cell) —
generalise the original's local-only model so AI/allies and replays can query any player's view.
Keep shroud and fog as separate bits and allow explicit "remembered" snapshots per cell so fog
shows last-seen terrain/objects. Compute sight with a radius-plus-height-occlusion pass and support
incremental updates for moving sources. Build the radar as a CPU-side per-player cell buffer with a
dirty-cell update path rather than redrawing the world. Expose reveal/jam as capability effects
that modify the grid.

**Sources.**
- OpenTS: `CellClass` visibility bits, `MapClass::Sight_From`/`Is_Shrouded`/`Is_Fogged`/`Encroach_*`, `FoggedObjectClass`, `RadarClass`: `https://github.com/OpenTS-Developers/TibSun` (`code/cell.h`, `map.cpp`, `fog.cpp`, `radar.cpp`, `logic.cpp`)
- OpenRA per-player visibility (clean-room cross-check): `https://deepwiki.com/OpenRA/OpenRA/3-game-engine-core`
- ModEnc / engine docs: `https://modenc.renegadeprojects.com/`

**Confidence.** High for the cell-bitfield model, radius/height occlusion, local-player-only
maintenance in the original, and radar requirements. Medium for exact radius tables and fog
encroachment timing.

---

### X-ENG-008 AI Architecture: House AI, Team/TaskForce, AITriggers, Difficulty

**What.** Three layers of AI: strategic house AI, operational team/script AI, and conditional
AITrigger spawning, plus difficulty gating.

**Architecture/logic.**

*House AI (strategic).* Each tick `HouseClass::AI()` runs the computer opponent. It:
- checks money and power and may sell structures (`AI_Raise_Money`, `AI_Raise_Power`,
  `AI_Fire_Sale`);
- chooses what to build (`AI_Building`, `AI_Unit`, `AI_Infantry`, `AI_Aircraft`) by scoring
  candidate types against `AIBuildThis`, current needs and available prerequisites;
- manages base layout via a **base planning graph** (`BaseClass`/`BaseNodeClass`): candidate cells
  are weighted (distance, defence coverage) and a defensive structure is placed
  (`AI_Build_Defense`);
- reacts to attacks (`AI_Attack`, `AI_Base_Defense`) and coordinates house-level `Expert_AI`
  behaviour.

*Teams (operational).* `TeamTypeClass` is a template: a `TaskForceClass` (list of type+count
members), a `ScriptTypeClass` (ordered mission commands), owning house, and flags (recruitable,
autocreate, priority). `TeamClass` is the live instance: it **recruits** members (required mission
state, recruitability), tracks a leader, and executes the script one `TMISSION_*` command at a
time. Team missions include ATTACK, ATT_WAYPOINT, MOVE, MOVECELL, GUARD, LOOP, WIN/LOSE,
UNLOAD, DEPLOY, LOAD, SPY, PATROL, SET_GLOBAL/CLEAR_GLOBAL, SELF_DESTRUCT, RESHROUD/REVEAL,
PLAY_SPEECH/SOUND/MOVIE/MUSIC, BEGIN_PRODUCTION, FIRE_SALE, and house changes. Team AI also handles
regrouping, lagging-unit catch-up, coordinated attacks, and low-priority suspension.

*AITriggers.* `AITriggerTypeClass` (from `ai.ini` / `[AITriggerTypes]`) is a condition → action
rule evaluated for a computer house. Conditions include enemy/house ownership of specific types,
enemy yellow/red power, enemy money thresholds, and similar checks; the action is typically
"create a TeamType" (optionally with weighting and a max instance count). AITriggers can be
global or local-scope and enabled/disabled per side, and are the primary way campaign/mission AI
reinforcement waves are authored.

*Difficulty/IQ.* Global `[General]`/`[IQ]`/`[Difficulty]` rules set production speed, firepower,
credits, and behaviour rates per difficulty; an "IQ" value gates which AI tactics are available.
Ares/Phobos/Vinifera add per-type AI flags and additional trigger conditions.

**Mapping to a unified engine.** Keep the three layers distinct: **strategy** (per-player economy/
build/base-planning policy), **operations** (team/group with a scripted task list), and
**reactive spawning** (conditional triggers). Make team scripts a data-driven command list
(serialisable, loopable, global/local-variable aware) rather than code. Make AITriggers a small
data-driven rules engine over a per-player fact/condition set. Keep difficulty as multipliers and
capability gates, and keep AI build rules separate from player prerequisite rules (as the original
does). The house AI should be an inspectable, testable policy object, not scattered conditionals.

**Sources.**
- OpenTS: `HouseClass::AI`/`AI_*`/`Expert_AI`/base planning, `TeamClass`, `TeamTypeClass`,
  `TaskForceClass`, `ScriptTypeClass`, `TMISSION_*`, `AITriggerTypeClass::Process` and conditions,
  `RulesClass::AI`/`IQ`/`Difficulty`: `https://github.com/OpenTS-Developers/TibSun` (`code/house.cpp`, `team.cpp`, `teamtype.cpp`, `taskforc.*`, `script.*`, `tmission.hh`, `aitrig.*`, `rules.cpp`)
- Official map editor (AITrigger authoring UI): `https://github.com/electronicarts/CNC_TS_and_RA2_Mission_Editor`
- ModEnc AI pages / Ares script actions: `https://modenc.renegadeprojects.com/`, `https://ares-developers.github.io/Ares-docs/new/index.html` (Script Actions)

**Confidence.** High for the three-layer structure and team-mission scripting. Medium for exact
house-AI scoring heuristics and AITrigger condition lists (reconstruction + editor).

---

### X-ENG-009 Trigger / Mission Script Runtime and Map Data Model

**What.** The map/script runtime: scenario state, waypoints, tags, triggers (event→action), cell
tags, and the on-disk map format.

**Architecture/logic.**

*Scenario state.* A `ScenarioClass` singleton owns all mutable scenario data: scenario name/
description, `GlobalFlags[]` and `LocalFlags[]` (boolean script variables, addressed by index or by
`[VariableNames]`), waypoints, the mission timer, ambient-light target/current, shroud/fog timers,
ion-storm state, special flags (fog of war, ion storms, inert), carry-over and win/lose state. It
serialises itself and contributes to the desync CRC.

*Triggers.* A `TriggerTypeClass` is a definition combining one **event** and one **action** plus
flags (persistent/one-shot, linked-to-global/local, disabled, attached-to-type). Events are an enum
of ~60 conditions (player entered, spied, destroyed, all destroyed, credits above/below, elapsed
time, mission-timer expired, building built, unit built, enters zone, crosses horizontal/vertical
line, global/local set/clear, low power, bridge destroyed, selected, near waypoint, enemy in
spotlight, first damaged, yellow/red health, ambient light, crate pickup, random time, paralyzed,
limped, …). Actions are a large enum (~90) including WIN/LOSE, BEGIN_PRODUCTION, CREATE_TEAM,
DESTROY_TEAM, REINFORCEMENTS, FIRE_SALE, PLAY_MOVIE/SOUND/MUSIC/SPEECH, TEXT, REVEAL_ALL/SOME/ZONE,
FORCE_TRIGGER, timer control, SET/CLEAR_GLOBAL/LOCAL, BASE_BUILDING, CHANGE_HOUSE, MAKE_ALLY/
ENEMY, PLAY_ANIM, DO_EXPLOSION, METEOR_IMPACT/SHOWER, ION_STORM_START/STOP, LOCK/UNLOCK_INPUT,
CENTER_VIEWPOINT, ZOOM, RESHROUD, ENABLE/DISABLE_TRIGGER, RADAR_EVENT, DAMAGE, light flashes,
announce win/lose, force end, ambient light changes, begin/stop AI triggers, team ratios, wake-up
commands, tiberium/vein growth control, etc.

A `TriggerClass` is a live instance that wraps a trigger type; `Spring(event, object, …)` evaluates
a fired event against the definition and, if satisfied, executes the attached action. Triggers are
attached to the map (cell/waypoint triggers, tracked as map tags) or to objects via a `Tag`
reference on the object; global timer triggers live in a separate "logic tags" list that the logic
loop scans every tick (`LogicClass::AI`). Globals/locals give campaigns persistent cross-object
state; linked triggers reset/retrigger on variable change. Tags can be destroyed
(`TACTION_DESTROY_TAG`).

*Map data model.* A scenario/map file is an INI with these major sections (names as written by the
official FinalSun/FinalAlert2 editor): `[Basic]` (name, next/alt scenario, multiplayer/official
flags, tiberium/vein/ice growth, carry-over, free radar, etc.), `[Map]`/terrain packing,
`[Waypoints]`, `[Celltags]`, `[Terrain]`, `[Overlay]` (Tiberium/overlays), `[Smudge]`,
`[Structures]`, `[Infantry]`, `[Units]`, `[Aircraft]`, `[Houses]`, `[Sides]`/`[Colors]`,
`[Triggers]`, `[Events]`, `[Actions]`, `[TeamTypes]`, `[TaskForces]`, `[ScriptTypes]`,
`[AITriggerTypes]`, `[AITriggerTypesEnable]`, `[VariableNames]`, plus object-rule override
sections. The map grid stores, per cell: iso-tile type + sub-tile, height/ramp, land type, overlay
+ overlay data, smudge, terrain object, occupancy, and a cell trigger/tag reference. The binary
map file wraps this in a compressed "pack" format with a map-format version and a pack version, and
can carry an appended INI; the editor's `MissionEditorPackLib` and the bundled XCC library handle
MIX/SHP/pack parsing.

*Waypoints.* Numbered points (0–N) addressed by name letter or cell, used by scripts, triggers,
reinforcements and AI (drop zones, attack routes, spawn points).

**Mapping to a unified engine.** Model scenario/map data as a **single serialisable document**
(JSON/Resource) with distinct domains: grid/cells, entities, houses, waypoints, variables,
triggers/events/actions, teams/taskforces/scripts, AI triggers. Keep triggers data-driven
(event ID + parameters → action ID + parameters) evaluated by a runtime with globals/locals and
enable/disable/persistence semantics. Represent every trigger attachment uniformly (to an object,
a cell, a waypoint, or the world) and drive global timer triggers from the logic tick. Make
waypoints and variable names first-class and referencable by name. The map editor must round-trip
the same document and embed rule overrides.

**Sources.**
- OpenTS: `ScenarioClass`, `TriggerClass::Spring`, `TriggerTypeClass`, `TEventType`/`TActionType`
  enums, `TagClass`, waypoints, scenario INI read/write: `https://github.com/OpenTS-Developers/TibSun` (`code/scenario.*`, `trigger.cpp`, `trigtype.cpp`, `taction.cpp`, `tevent.hh`, `taction.hh`, `tmission.hh`, `logic.cpp`, `waypoint.*`)
- Official map editor source and map sections: `https://github.com/electronicarts/CNC_TS_and_RA2_Mission_Editor` (`MissionEditor/Triggers.*`, `TeamTypes.*`, `data/FinalSun/StdMapTS.ini`)
- ModEnc trigger/event/action pages: `https://modenc.renegadeprojects.com/`

**Confidence.** High for the trigger event/action model, scenario state and waypoints; High for the
editor's map sections (official source). Medium for exact on-disk packing/version bytes.

---

### X-ENG-010 Rendering Pipeline (Voxel/SHP Blit, Sorting, Animations) — Architecture Only

**What.** How the 2D/2.5D presentation is assembled each frame.

**Architecture/logic.**

*Sorting.* Renderable `ObjectClass` instances are held in **layers** and drawn in depth order.
`LayerClass` supports `Submit`, `Sorted_Add`, and an incremental single-pass bubble `Sort` that
orders objects by `Sort_Y()` (screen-Y/depth key). The tactical renderer runs a fixed **pass
order**: depth buffer wipe → shroud → iso tiles → fogged (last-seen) objects → cell overlays →
terrain objects → tile shadows → buildings → remaining (sorted) objects and effects. Objects
provide their own draw transform (position, facing matrix, Z adjust) and, for locomotor-driven
units, ask the locomotor for `Draw_Matrix`/`Draw_Point`. Draw passes allow height-correct
interleaving and Z-buffered occlusion. Dirty-rectangle / partial redraw limits work per frame.

*Sprite (SHP) blitting.* 2D art is a frame bank (`.shp`) of paletted, RLE-compressed shapes plus
shadow frames; remap colours supply house/team tinting. A family of `Blitter`/`RLEBlitter`
variants handles plain, translucent, shadow, remap and alpha combinations; a `ConvertClass`/
`LightConvertClass` applies palette conversion and house remapping. Buildings, infantry, effects,
cameos and UI all use this path.

*Voxel blitting.* Vehicles/structures with `Voxel=yes` use `.vxl` models plus `.hva` animation
transforms. A software voxel rasterizer (`VoxelLibrary::Render_Object` / `Render_Shadow`) projects
voxels with per-face normal lighting and a palette, producing a drawable image; bounding boxes and
layer info are precomputed. Turrets/barrels are separate voxel layers with their own facing.

*Animations.* `AnimClass` (built on a `StageClass`) runs frame sequences with loop styles
(loop, back-and-forth, random), rate, sound/particle triggers per stage, and can be attached to
objects, cells or effects. Buildings play active/animation states, and dedicated `VoxelAnimClass`
objects animate voxels (with bounce physics). Terrain/theater tiles (`.tmp`) come in per-theater
sets with palette variants.

*Radar rendering* is a separate per-player cell-buffer render target (X-ENG-007).

**Mapping to a unified engine.** In a 3D Redot engine, treat sorting as a **render-order key**
(depth/layer/height/Y) and keep an explicit layer + pass contract rather than relying on draw order
implicitly. Keep art resolution (name → per-theater/per-side/per-state asset, X-ENG-003) separate
from the mesh/material layer. Voxel models become ordinary 3D meshes; SHP becomes a texture-atlas
sprite/quad path. Animation is a data-driven state machine (loop styles, stage events) shared
between 2D and 3D. Keep the "last-seen fogged object" concept as a cached render proxy. A
dirty-region/partial-update policy matters more for the CPU-side radar/minimap buffer than for the
GPU scene.

**Sources.**
- OpenTS: `LayerClass::Sort`/`Sorted_Add`, `Tactical::Render` pass order, `VoxelLibrary`,
  `AnimClass`/`StageClass`, `Blitter`/`ConvertClass`: `https://github.com/OpenTS-Developers/TibSun` (`code/layer.cpp`, `tactical.cpp`, `voxlib.cpp`, `voxel.*`, `anim.*`, `blit*.*`, `convert.*`, `isotile.*`)
- First-gen equivalent: `https://github.com/TheAssemblyArmada/Vanilla-Conquer`
- XCC utilities (SHP/VXL/MIX format tooling, used by the official editor too):
  `https://github.com/electronicarts/CNC_TS_and_RA2_Mission_Editor` (`3rdParty/xcc`)

**Confidence.** High for layer sorting and pass order and for the SHP/voxel split. Medium for
exact voxel lighting math and Z-buffer details (reconstruction).

---

### X-ENG-011 Save/Load Format and Serialised State

**What.** How a running game is persisted and restored, including ownership and status.

**Architecture/logic.**

*Persistence model.* Game object and type classes implement a COM **IPersistStream**-style
`Save`/`Load` (`GetClassID`, `QueryInterface`, `GetSizeMax`, `Compute_CRC`). A save file has a
header (`SaveVersionInfo`) carrying an internal game version (base, Firestorm, etc.) and a file
version, plus a description and metadata. The loader uses the version to read **older object
layouts**: each class knows its current object size and a "size delta" versus older saves, so a
new field appended over time can be read into the tail of an old record. This is how one binary
loads multiple patch versions.

*What is written.* `Save_Game` writes the version header, then per-house data, the scenario, the
map, and every persistent object through its owner; `Save_Misc_Values` captures the local player
pointer, the current frame number, the current selection list, the global/Ground state, the ion
storm, the global ("logic") trigger list, the map trigger list, crate state, the mission control
table, and the speech/EVA state. Object classes serialise their full runtime state: house/owner,
mission and order state, target (`TarCom`/`NavCom`), health/armour/veterancy, active/inactive and
limbo flags, cloaking/detection, passenger/containment links, mind-control neuron links, factory
progress, team membership, trigger references, etc. Scenario globals/locals, waypoints and timers
are serialised with the scenario.

*Pointer reconstruction.* Cross-object references are saved as **swizzle IDs**, not raw pointers:
the `SwizzleManagerClass` assigns each referenced pointer an ID on save and resolves IDs back to
objects on load (`Swizzle`), and objects can register themselves (`Here_I_Am`). This is what makes
references such as a team's members, a trigger's attached object, or a target pointer survive a
round-trip. `Post_Load_Game` then re-links pointers and restores derived state.

*Multiplayer and extensions.* Save/load is disabled in multiplayer. Ares/Phobos implement **save
game filtering**: a save records the extension build/version, and a mismatched extension build
refuses (or filters) the save, because extension classes are appended to the serialised layout and
must match. This is direct evidence that persisting to a versioned, ID-referenced object graph is
the intended model.

**Mapping to a unified engine.** Design serialisation as a **versioned object graph with stable
numeric IDs** from day one; never serialise raw pointers. Write a per-class version tag so newer
fields can be appended and old saves migrated. Capture *all* mutable simulation state (ownership,
orders/targets, status flags, timers, variables, queues) so a save is a true snapshot — and make
the same data feed the desync CRC. Keep a "save is simulation state, not UI state" boundary.
Allow extension/plugin classes to register their own stable save IDs and add save-version
filtering so mismatched builds fail cleanly.

**Sources.**
- OpenTS: `Save_Game`/`Load_Game`, `SaveVersionInfo`, `Save_Misc_Values`, `SwizzleManagerClass`,
  per-class `Save`/`Load`/`Get_Object_Size_Delta`: `https://github.com/OpenTS-Developers/TibSun` (`code/saveload.cpp`, `savever.h`, `swizzle.*`, `iswizzle.*`, `abstract.cpp`)
- Phobos save filtering: `https://phobos.readthedocs.io/en/latest/General-Info.html`
- Ares save filtering (via Phobos docs and Ares docs): `https://ares-developers.github.io/Ares-docs/`

**Confidence.** High for the versioned, swizzle-ID IPersistStream model and the content of a save.
Medium for exact binary layout/field order (reconstruction) and RA2/YR-specific divergence.

---

### X-ENG-012 Multiplayer / Netcode, Sync, Determinism

**What.** The lockstep networking model.

**Architecture/logic.** Deterministic **command lockstep**. Every client runs the identical
simulation at the fixed logic rate. Player commands are encoded as `EventClass` records: a Type
(the big command switch — move, attack, deploy, produce, stop, garrison, ally, power on/off, etc.),
a house ID, and a small data union, tagged with the **frame on which it must execute** (`Frame` =
current frame + an added delay). Events are broadcast over the transport; each client queues and
executes them at the exact same frame (`Execute_DoList`), so no unit positions are ever synced —
only commands.

Session state holds the negotiated `DesiredFrameRate`, `MaxAhead` (maximum command latency in
frames), `FrameSendRate` (how many frames between state packets), per-player latency, and
`ProcessTime`. Clients stall waiting for slower peers (`FrameSyncStalls`); the maximum-ahead value
only ever grows during a match. `OutOfSync` is set when the periodic state CRC (`Compute_CRC` over
objects/houses/scenario) disagrees between clients. The same command stream, recorded per frame,
is used for replays and playback (`Session.Play` runs as fast as possible). Transports are IPX
(legacy), UDP/Winsock (a protocol layer plus a UDP socket layer), serial/modem and null; the
CnCNet "spawner" replaces the transport with its own while keeping the lockstep model. Save/load is
disabled in multiplayer.

**Mapping to a unified engine.** Build deterministic lockstep around a **single simulation frame
counter** and a **command queue**; broadcast commands tagged with an execution frame, never state.
Keep the frame counter, RNG seed, and all mutable sim state free of rendering/OS timing. Implement
periodic CRC/state-hash checks and desync reporting. Make the transport an interface (local, UDP,
relay) so a community transport can replace it. Reserve a replay format that is just the recorded
command stream plus the initial seed. Design for added input latency (`max_ahead`) as an input
buffer, not a physics change.

**Sources.**
- OpenTS: `SessionClass` (`DesiredFrameRate`, `MaxAhead`, `FrameSendRate`, `OutOfSync`,
  `FrameSyncStalls`), `EventClass::Execute`, network/packet layers, `Compute_CRC`:
  `https://github.com/OpenTS-Developers/TibSun` (`code/session.h`, `event.*`, `wspudp.*`, `wsproto.*`, `ipxconn.*`, `saveload.cpp`)
- OpenRA deterministic lockstep (clean-room cross-check): `https://deepwiki.com/OpenRA/OpenRA/3-game-engine-core`
- CnCNet (community transport context): `https://cncnet.org/`

**Confidence.** High for the command-lockstep model, frame tagging, max-ahead/frame-send-rate and
CRC desync detection. Medium for exact packet layouts and the post-1.001 spawner protocol (closed).

---

### X-ENG-013 Audio / EVA Event Dispatch

**What.** How sound effects, music and EVA voice lines are triggered and mixed.

**Architecture/logic.** Audio is organised as three data-driven databases:

- **Sound effects (`SOUND.INI`)** define a `VocType` database: entries are indexed in `[SoundList]`
  and each has a section controlling file(s), simultaneous-instance `Limit`, audible `Range`,
  `Priority`, volume, pitch/volume variation, loop behaviour and playback control flags
  (positional/global/local, shroud-visibility-gated, loop/random/sequential/all, predelay, queue,
  interrupt, attack/decay envelopes). Positional volume is computed from the source cell relative
  to the tactical screen. Multiple sample files per sound give variation/sequence.
- **Themes (`THEME.INI`)** define music tracks for the jukebox and scripted playback: file, display
  name/artist/length, allowed side/scenario/add-on, repeat, volume, and fade/cross-fade settings.
- **EVA/speech (`EVA.INI`)** define the announcement database: a sound per entry, optional subtitle
  text, a category (System/Scenario), a priority (LOW/NORMAL/IMPORTANT/CRITICAL) and a playback
  policy (STANDARD single-replaceable slot / QUEUE / INTERRUPT / QUEUED_INTERRUPT). Speech runs
  through a **dedicated scheduler** with a standard slot plus a normal queue and an interrupt
  queue; queued lines drain by priority then FIFO, and the interrupt queue drains before the normal
  queue.

*Dispatch.* Game events call `Sound_Effect(VocType)` for effects and `Speak(VoxType)` for EVA.
Sources include weapon fire/impact, unit voice responses (per-type response tables), building
ambient sounds, UI, and explicit script actions (`TACTION_PLAY_SPEECH`, `TMISSION_PLAY_SPEECH`)
and house/AI announcements (low power, unit lost, building destroyed, etc.). In vanilla TS the EVA
list is built in; Vinifera replaces the audio backend (miniaudio) and makes `SOUND.INI`/`THEME.INI`/
`EVA.INI` fully data-driven, including per-type sound overrides, subtitles and per-side speeches.
Movies have a separate audio path (`VQAClass`).

**Mapping to a unified engine.** Make audio a **data-driven event bus**: callers dispatch by
logical sound/EVA ID, and a singleton resolves ID → asset + playback policy (limit, range,
priority, loop, queue/interrupt). Separate three buses (SFX, music, voice/EVA) with independent
scheduling; give EVA a priority queue with replace/interrupt semantics. Gate positional audio by
visibility (shroud/fog) where appropriate. Keep per-unit/per-building voice response tables as
data. In Redot this maps naturally to audio buses + a manager autoload with an event-dispatch API.

**Sources.**
- OpenTS: `VoxClass`/`Speak`, sound-effect dispatch: `https://github.com/OpenTS-Developers/TibSun` (`code/vox.*`, `sound.*`, `audio.h`)
- Vinifera audio system (documents the original databases and Vinifera's replacement):
  `https://vinifera.readthedocs.io/en/master/New-Features-and-Enhancements.html` (Audio System)

**Confidence.** High for the three databases, playback policies and positional/visibility gating;
Medium for the exact vanilla TS speech scheduler internals (best documented through Vinifera).

---

### X-ENG-014 Mod / Open-Engine Deltas That Reveal Intended Behaviour

**What.** What the ecosystem's extension DLLs tell us about the original engine's design limits and
intended seams.

**Architecture/logic.**

- **Ares** (YR extension DLL, injected via Syringe) generalises hardcoded tables: additional
  `ArmorTypes` and `Verses` entries (including special 0%/1% semantics), richer and alternative
  prerequisite groups and negative/required-factory prerequisites, `AttachEffect` (general aura/
  status attachment), custom missiles, restored TS logic removed from RA2 (EMP, Firestorm wall,
  laser fences, spotlights, vehicle thief, multi-engineer), per-type build time, custom cursors/
  cameos/palettes, and much more. Its existence proves the original limits are the **hardcoded
  armour/warhead tables, fixed weapon/type slots, and fixed prerequisite groups**, and that the
  intended seam is data tables plus a per-object status/effect model.
- **Phobos** (Ares-compatible, YRpp-based, SyringeEx) adds more traits and, crucially, documents
  **save-game filtering and extension versioning**: extension classes are appended to the
  serialised object layout and must match between save and load; nightly builds skip version
  filtering. This confirms the versioned-ID object-graph save model.
- **Vinifera** (open TS extension) adds per-type overrides of what were global settings (e.g.
  aircraft shuffle/reload), new armour types, prerequisite groups, an entirely replaced audio
  engine with per-type sound/EVA configuration, extra graphic facings, and locomotor improvements.
  This reveals TS's **global-vs-per-type split** and the COM locomotor seam as intended
  extensibility points.
- **TSpp / YRpp** are community C++ headers that map the shipped binaries' class layouts and
  vtables; they are strong independent evidence for the object/type hierarchy, COM registration,
  and field-level state described above.
- **OpenRA** is an independent clean-room reimplementation (TD/RA1 only) that chose a different but
  instructive architecture: Actors + Traits + Activities, a deterministic tick with a synchronised
  MersenneTwister seed, command-lockstep networking, and a two-tier hierarchical pathfinder. It
  validates the generic shape (component composition, fixed tick, command sync, hierarchical
  pathing) but is **not** evidence about TS/RA2 internals.

**Confidence conflicts worth flagging.**
- **Shroud storage:** TS source shows per-cell visibility bits maintained only for the local
  player; some community descriptions imply per-house shroud. Treat "per-player computed, locally
  maintained" as correct for the original; a unified engine should generalise to true per-player
  grids.
- **`CellSpread`:** community shorthand "radius in cells" is wrong; it is a 3D lepton sphere.
- **Sub-cell:** TS/RA2 use 5 sub-positions per cell; RA1/TD and OpenRA differ.

**Mapping to a unified engine.** Turn the extension DLLs' work into first-class engine features
rather than patches: **fully data-driven armour/warhead tables, unlimited weapon/type slots,
general prerequisite expressions, a generic status/effect (aura) system, and a versioned plugin/
extension save format.** Reading the extension docs as a requirements list for the unified engine
is the single highest-value use of this material.

**Sources.**
- Ares: `https://ares-developers.github.io/Ares-docs/index.html`, `.../new/index.html`,
  `.../restored/index.html`, `.../new/prerequisites.html`
- Phobos: `https://phobos.readthedocs.io/en/latest/General-Info.html`, `.../New-or-Enhanced-Logics.html`
- Vinifera: `https://vinifera.readthedocs.io/en/master/New-Features-and-Enhancements.html`
- YRpp / TSpp: `https://github.com/Ares-Developers/YRpp`, `https://github.com/Vinifera-Developers/TSpp`
- OpenRA: `https://github.com/OpenRA/OpenRA`, `https://deepwiki.com/OpenRA/OpenRA/3-game-engine-core`

**Confidence.** High for what the extensions add and imply about limits; Medium for attributing
each limit to a specific original code path.

---

## Engine concern → original-engine approach → unified-engine recommendation

| # | Engine concern | How the original engine does it | Unified-engine recommendation |
|---|----------------|---------------------------------|-------------------------------|
| 1 | Simulation loop | Fixed 15 Hz logic tick in an ordered phase pipeline (triggers → environment → teams → objects → production → houses); render/input decoupled | Fixed logic tick + explicit documented phase contract; render decoupled; single seeded RNG; desync hash |
| 2 | Determinism | Seeded shared RNG, stable iteration order, periodic CRC desync check | Integer/fixed-point sim math, seeded RNG owned by sim, periodic state hash |
| 3 | Object vs type | Deep instance hierarchy + parallel immutable type singletons referenced by index; COM registration; limbo lifecycle | Instance = components/nodes; type = immutable data resources with stable IDs; explicit limbo state machine |
| 4 | Allocation | Type vectors via `Find_Or_Make`; instances from fixed memory pools sized by `Heap_Maximums` | Registry with deterministic ID assignment; pool only hot categories if profiled |
| 5 | INI loader | Case-sensitive generic parser + typed getters; ordered `Do_*` type-list registration; each type reads its own section | Same shape: parser + typed accessors + documented ordered registration + create-or-get override |
| 6 | `Image=` resolution | Rules name → art section → `.vxl`/`.hva` or `.shp`, per-theater/side/state, water/unload substitutions | Separate visual lookup layer; resolver with per-theater/per-side/per-state fallbacks |
| 7 | Movement | COM-pluggable locomotors behind `ILocomotion`; per-tick `Process` | Movement strategy/plugin behind one interface; data-defined locomotor |
| 8 | Movement zones | `MovementZone` (legal space/crush/layer) + `SpeedType` (terrain speed) | Keep both orthogonal as data; zone drives pathing, speed type drives rate |
| 9 | Pathfinding | Two-tier: hierarchical A\* over 3 subzone levels → corridor-confined cell A\*; avoidance, corner-cut, splice | Hierarchical region graph + corridor-confined grid A\*; integer costs, stable ties |
| 10 | Occupancy | Cell 8-bit mask: 5 sub-positions + vehicle/monolith/building; separate bridge mask; scatter/shove | Cell + sub-slot reservation map with bridge layer; reservation + scatter, not physics |
| 11 | Weapon chain | Weapon → projectile (`BulletClass`) → warhead → `Modify_Damage` → target | Pipeline weapon→projectile→warhead→single `apply_damage` funnel |
| 12 | Verses / armour | `Warhead->Modifier[armor]` matrix; distance fall-off; caps | First-class Verses matrix data; one damage funnel with fall-off and caps |
| 13 | Splash | `CellSpread` = 3D lepton sphere + air grid; overlay interactions | Radius-in-world-units sphere + aerial lookup + overlay pass |
| 14 | Targeting | Player order → guard/scan → passive acquire → retaliation; threat types; primary/secondary scored by verses | Explicit priority chain + threat model; passive acquire flag; score weapon slots by verses |
| 15 | Power | Signed per-building power; house supply/drain fraction; `IPowerEvents` callbacks; low power penalties | Per-player supply/demand + threshold event bus; buildings react |
| 16 | Production | Per-producer `FactoryClass` with per-tick `Cost_Per_Tick`; per-house category queues; multi-producer bonus | Queue per category + producer capability; time/cost progress; diminishing multi-producer bonus |
| 17 | Prerequisites | Type list + TechLevel/Owner/RequiredHouses + named groups; AI ignores most | Data-driven prerequisite expression over per-player capabilities; named alternative groups; AI rules separate |
| 18 | Vision | Per-cell shroud/fog bits, local player only; radius + height occlusion; regrow/spread; last-seen snapshots | True per-player visibility grid; height-occluded radius; remembered snapshots; reveal/jam effects |
| 19 | Radar | Per-player cell-buffer minimap; needs radar building + power; jamming; events | CPU cell buffer with dirty-cell updates; capability-gated; pings |
| 20 | House AI | Per-tick score-based build, base-planning graph, defence placement, economy reactions | Inspectable policy object per player; separate strategy/operations/spawn layers |
| 21 | Teams | `TeamType` template + `TaskForce` + `Script`; live `TeamClass` executes `TMISSION_*` commands | Data-driven team script command list; group/leader/regroup logic |
| 22 | AITriggers | Condition (ownership/power/money) → create team; global/local; per-side enable | Small data-driven rules engine over per-player facts |
| 23 | Triggers/missions | `TriggerType` = Event + Action + flags; live `TriggerClass::Spring`; tags; globals/locals; scenario state | Uniform data-driven event→action runtime with variables, persistence, enable/disable |
| 24 | Map format | INI scenario + packed cell grid + entity/trigger/team sections + embedded overrides; editor round-trips | Single serialisable map document with all domains; editor round-trip; embed overrides |
| 25 | Rendering | Layer sort by depth key; fixed pass order; SHP blit + software voxel rasterizer; stage-based anims | Explicit render-order keys/layers; meshes for voxels, sprites for SHP; data-driven animation state machine |
| 26 | Save/load | Versioned IPersistStream object graph; swizzle IDs for pointers; per-class size deltas; extension filtering | Versioned object graph with stable IDs; no raw pointers; migration tags; plugin save IDs + version filter |
| 27 | Multiplayer | Command lockstep; events tagged with execution frame; max-ahead/frame-send-rate; CRC desync; replays = command stream | Frame counter + command queue tagged by frame; transport interface; desync hash; replay = commands + seed |
| 28 | Audio/EVA | Three INI databases (SOUND/THEME/EVA); playback policies and priority queues; positional + visibility gating | Data-driven audio event bus: ID → asset + policy; separate SFX/music/voice buses; visibility gating |
| 29 | Extension seams | Ares/Phobos/Vinifera patch hardcoded tables, weapon/type slots, prerequisite groups, save layout | Make those tables/slots/expressions/plugin save IDs first-class, not patch points |

---

## Coverage checklist

- [x] 1. Simulation loop / tick model, frame rate, determinism — X-ENG-001
- [x] 2. Object/type class model, allocation, ownership, lifecycle (limbo/underground) — X-ENG-002
- [x] 3. INI loader: sections, ordered type-list registration, indexed tables, overrides, per-map overrides, `Image=` — X-ENG-003
- [x] 4. Movement: locomotors, movement zones, pathfinder (A\*/hierarchical), repulsion, cell/sub-cell occupancy — X-ENG-004
- [x] 5. Weapon/warhead: firing chain, targeting hierarchy, verses, projectile dispatch, splash — X-ENG-005
- [x] 6. Power, production/queue, prerequisite resolution — X-ENG-006
- [x] 7. Vision/shroud/fog; radar — X-ENG-007
- [x] 8. AI: house AI, team/taskforce runtime, triggers/events/actions, difficulty/IQ — X-ENG-008, X-ENG-009
- [x] 9. Trigger/mission runtime and map data model — X-ENG-009
- [x] 10. Rendering pipeline (voxel/SHP blit, sorting, animations), architecture only — X-ENG-010
- [x] 11. Save/load format and serialised state (ownership/mind-control/status) — X-ENG-011
- [x] 12. Multiplayer/netcode, sync, determinism — X-ENG-012
- [x] 13. Audio/EVA event dispatch — X-ENG-013
- [x] 14. Mod/open-engine deltas (Ares/Phobos/Vinifera/TSpp/YRpp/OpenRA) — X-ENG-014
- [x] All 14 scope items mapped to a recommended generic subsystem
- [x] ≥2 sources per claim (EA source, OpenTS, FA2/FinalSun, ModEnc, extension docs, OpenRA)
- [x] Conflicts and confidence noted

---

## Open questions / top uncertainties

1. **Official TS/RA2/YR source does not exist publicly.** TS architecture is reconstructed
   (OpenTS) plus binary-mapped (TSpp); RA2/YR is binary-mapped (YRpp). Exact original code paths,
   comments and constants for TS/RA2 are not verifiable against EA source.
2. **Exact original phase ordering.** The reconstruction separates "logic AI" and an
   "environment AI" helper; whether the shipped engine interleaved localomotor processing exactly
   as reconstructed (foot AI → `Locomotion->Process`) is unconfirmed at the instruction level.
3. **Original A\* internals.** Subzone construction, cost constants, avoidance multipliers, corner-
   cut and splice rules are reconstruction-level; exact vanilla behaviour (and its bugs) is not
   fully pinned down.
4. **Netcode packet layouts and the post-1.001/CnCNet spawner protocol** are closed; the lockstep
   model is documented but wire details and latency handling are community-observed.
5. **Save-file binary layout** (field order, compression/pack versions, RA2/YR divergence) is
   reconstructed; only behavior and versioning model are high-confidence.
6. **Mind-control (BrainClass/NeuronClass) details** — neuron selection/sharing, save semantics,
   and interaction with capture/ownership changes need more corroboration.
7. **`CellSpread` internal table contents and air-grid exact range rules** are partially
   reverse-engineered and partly still "being determined" per ModEnc.
8. **Rendering specifics** — voxel normal/lighting math, palette/remap precision, Z-buffer vs
   painter's-algorithm boundaries by object type — are reconstruction-level.
9. **Where the exact boundary between the fixed 15 Hz logic and any sub-tick interpolation sits**
   for smooth movement (if any) in the shipped game is not settled.
10. **Per-map rule-override precedence vs. add-on rule files** (which wins when both redefine the
    same type) is inferred from load order but not exhaustively tested across TS/FS/RA2/YR
    versions.
