# Command & Conquer: Tiberian Sun (1999) + Firestorm (2000) — Feature & Architecture Inventory

Research target: re-implementing TS/FS data-driven in a unified RTS engine.
Scope: complete core feature/architecture set, not stat tables. Grounded in the real
games' `rules.ini` / `art.ini` / `ai.ini` conventions and the released Westwood engine
(custom 2D isometric, "lepton" coordinate system). Terminology cross-checked against the
local `games/ts` data model (`docs/research/_raw` is intentionally raw).

Legend: **[TS]** base-game feature · **[FS]** Firestorm addition/change · **[uncertain]** flagged.

---

## 1. Core engine & simulation

- **Isometric diamond grid** — World is a square cell grid rendered as 2:1 diamond tiles
  (classic Westwood iso). Ground layer is height-mapped; units address cells, not pixels.
  Sim coordinate unit is the "lepton" (fine sub-cell unit) with a fixed cell↔lepton ratio.
- **Tile size & cell raster** — One iso tile = one cell; buildings occupy integer
  `foundation` (X×Y cells); infantry occupy sub-cell slots so several can share a cell.
  Repo models this as `foundation` (data) vs derived `footprint` (runtime) and
  `shared_slots_per_cell`.
- **Sub-cell / slot occupancy** — Vehicle/tracked units occupy a whole cell; foot units
  take sub-slots (blocking logic differs per locomotor). Building "bibs" block pathing but
  allow slow pass-through.
- **Height / terrain** — Cells carry an elevation grade plus slope/ramp tiles and cliffs;
  height gates passability (tracked can climb some ramps, wheeled less), vision (units on
  high ground see farther, cf. `LeptonsPerSightIncrease`), and firing. Cliffs can collapse
  (`CollapseChance`).
- **Land types / terrain rules** — Surface classes drive locomotor speed & passability:
  Clear, Rough, Road, Water, Beach/Sand, Cliff, Pavement, Green, Tiberium, Veins, Ice, Wall,
  Tunnel. Per-locomotor speed multipliers; a unit's `SpeedType`/locomotor picks the table.
- **Theaters / tilesets** — Visual+palette variants (Temperate, Snow; urban tiles in places).
  TS allows mixed-tileset maps. Theater is look-only, never passability. **[uncertain]**
  exact TS tileset suffixes (`.tem`, `.sno`, `.urb`).
- **Shroud & fog model** — Two layers: undiscovered **shroud** (black) and **fog of war**
  (explored-but-unseen, dimmed). `FogOfWar=no` default in rules; `ShroudGrow` and
  `ShroudRate` control shroud creep; `BlendedFog` blends vs dithers. Sight radius per unit;
  radar reveals explored areas.
- **Damage & armor class matrix** — 5 armor classes: `none, wood, light, heavy, concrete`.
  Each `Warhead` defines a `Verses` percentage per armor class (and per special states,
  e.g. prone). Final damage = `Damage × Verses[armor]` clamped by `MaxDamage`/`MinDamage`.
  Warhead list (base): SA, AP, HE, Super, Fire, Gas, Mechanical, HollowPoint, SonicWarhead,
  RailShot/RailShot2, PlasmaWH, Organic, ORCAHE, ORCAAP, ARTYHE, Slimer, Shard, SAMWH, RPG,
  EMPuls, TankOGas. **[FS]** adds WebMass, LIMPY, CoreDefPlasmaWH, Super2, MobileEMPulse,
  WeakGass, Stinger, MeteorWH, ARTYHEX, Gas2. Damage types gate targeting: 0% verses = not a
  valid target for that warhead (unless secondary).
- **Projectile types** — Instant/invisible hitscan (bullets), `Cannon` (fast shell),
  `Ballistic` (arcing, gravity, scatter, `BallisticScatter`), `Lobbed` (artillery arc),
  `HeatSeeker`/homing missiles (`MissileSpeedVar`, `MissileROTVar`), `LLine` (laser/energy
  line), `PulsPr` (EMP pulse), cluster/multi-warhead, torpedoes. Per-projectile: speed, ROT,
  `Arcing`, `Homing`, `Inaccurate`, `Cluster`, `Airburst`.
- **ROT / turn rate** — Units and turrets have `ROT` (rate of turn); turrets can traverse
  independently (`Turret=yes`, `TurretAnim`). Aircraft/missiles have both speed and ROT.
- **Flight & altitude** — Aircraft at fixed `FlightLevel` above ground; jumpjets use a
  separate `[JumpjetControls]` block (TurnRate, Speed, Climb, CruiseHeight, Wobbles).
  Higher altitude extends sight/fire (`LeptonsPerFireIncrease`).
- **Power** — Per-house supply/demand grid. `Power=-N` drains, plants supply. Low power
  slows/limits production (`MinProductionSpeed`, `Worst/BestLowPowerBuildRateCoefficient`),
  disables powered defenses and superweapon charging, and causes trivial structure damage
  over time (`DamageDelay`).
- **Veterancy** — Two levels beyond rookie (`VeteranCap=2`: veteran, elite), earned by
  kill-value ratio (`VeteranRatio`). Bonuses: `VeteranCombat`, `VeteranSpeed`,
  `VeteranSight`, `VeteranArmor`, `VeteranROF`. Per-unit `EliteAbilities` (e.g. `SENSORS`,
  `SELF_HEAL`, `CRUSHER`, `VEIN_PROOF`, `EXPLODES`, `TAKE_DAMAGE`?? no). Pip display
  (`PipScale`, `PipScale=Charge` for EMP).
- **Crates & pickups (sim)** — Crates are overlays carrying powerups (money, heal, unit,
  armor, speed?) with `CrateMaximum/Minimum/Regen`, `CrateRadius`; solo vs multiplayer
  rewards (`SilverCrate`, `WoodCrate`, `SoloCrateMoney`).
- **Object limits / maximums** — `Maximums` caps object types (8 players); `MaxDebris`,
  `MaximumQueuedObjects`.

## 2. Economy

- **Tiberium types** — Green (**Riparius**, standard) and Blue (**Vinifera**, richer value)
  are the harvestable resources; Red tiberium is rare/map-set. **Veins** (organically
  growing tendrils around a `Veinhole`) are a separate resource/hazard, not normal harvest.
  **[FS]** expands tiberium/mutation terrain and the Veinhole creature rules
  (`VeinholeGrowthRate`, `MaxVeinholeGrowth`, `VeinDamage`). Repo models
  `tiberium_green/blue/red` and `vein` resource types.
- **Harvester behavior** — Harvester autonomously seeks nearest tiberium (`TiberiumNearScan`
  / `TiberiumFarScan` AI helpers), fills at `HarvesterFillRate`/`BailCount`, returns to
  nearest refinery, plays unload anim (`UnloadingHarvester=HORV`). `HarvesterImmune` toggles
  combat immunity; `HarvesterUnit=HARV` AI hint.
- **Refinery unload** — Refinery = dock + unload animation; free harvester spawned on
  placement (`free_unit`; `[General]` refinery yields harvester). Docked harvester variant
  exists. Multiple refineries shorten round-trip; docking pathing uses dock slots.
- **Silo storage** — `GASILO`/`NASILO` (Nod "Tiberium Silo") stores overflow above a
  per-house visible credit buffer; excess beyond cap is lost. **[uncertain]** exact TS
  storage cap values.
- **Income & credit cap** — Credits per house, `[MultiplayerDefaults] Money=10000`,
  `MaxMoney=10000` (skirmish); campaign maps override. Tiberium value per bail, blue > green.
- **Crate pickups** — Money/heal/unit crates; `FreeMCV=yes` gives free MCV in multiplayer
  when broke but still has funds.
- **Resource regrowth** — `TiberiumGrows`, `TiberiumSpreads`, `GrowthRate` (minutes per
  growth), `SpreadAmount`; trees regrow (`TreeGrowthRate`); veinhole growth/shrink. **[FS]**
  adds mutation ecology tiles and adjusted veinhole tuning.

## 3. Construction & base

- **MCV deploy** — `BaseUnit=MCV`; MCV undeploys from / deploys into the Construction Yard
  (`GACNST`/`NACNST`). Deploy/undeploy is a `DeploysInto`/`UndeploysInto` pair with anims and
  `DeployTime`. FS adds deploy-capable combat/support vehicles (Juggernaut, Tick Tank, EMP,
  stealth gen, mobile war factory).
- **Building placement adjacency/rules** — New structures must be within `Adjacent=N`
  cells (Chebyshev) of a friendly footprint; ground must be clear, flat enough, and on legal
  land type. Blocked by units standing on footprint (placement delay retry,
  `PlacementDelay`). Foundation size drives footprint; some structures `PlaceAnywhere`.
- **Construction Yard** — Root builder; providing build space, prerequisite for base
  structures. Capture/sell/repair all apply. **[FS]** CABAL has its own.
- **Walls** — `GAWALL`/`NAWALL` wall segments, cheap and fast (`WallBuildSpeedCoefficient`),
  with wall-tower/gate linkage via `[General]` hacks (`WallTower=GACTWR`,
  `GDIGateOne/Two`, `NodGateOne/Two`). Walls are overlays in map data.
- **Gates** — Directional gates (`GAGATE_A/B`, `NAGATE_A/B`) that open for friendly units;
  Nod also has **Laser Fence Post + Section** (`NAPOST`/`NAFNCE`, powered, `GuardRange`
  sets max inter-post span).
- **Bibs** — Non-foundation apron cells around a building that block placement but permit
  slow unit pathing (`bib_cost_penalty` in repo). Some buildings `Bib=yes`.
- **Sell / repair** — Sell refunds `RefundPercent=50%`, spawns crew/survivors
  (`SurvivorRate`, `SurvivorDivisor`). Repair costs `RepairPercent`, ticks at `RepairRate`
  (`RepairStep` HP), unit repair `URepairRate`, infantry `IRepairRate/Step`; `RepairBay`
  (GADEPT) auto-repairs. Tiberium-healing units use `TiberiumHeal`.
- **Building capture (engineers)** — Engineer enters building → immediate ownership flip;
  `EngineerCaptureLevel=1.0`, `EngineerDamage=0.0` (**[FS]** values). `Capturable` flag per
  building; `MissionRepair`/sell. Nod also has `CHAMSPY` (disguise spy).
- **Prebuilt structures** — Campaign maps place pre-existing neutral/owned structures;
  civilian cities (`CITY01..`, `CAHOSP`, `CTDAM`), lamps, boards, wrecked buildings
  (`ABAN01..`, `GAOLDCC*`).
- **Special structures** — Power plants (+Nod `NAAPWR`, GDI turbine upgrade `GAPOWRUP`
  powering up `GAPOWR`), refineries, repair depot, radar, tech center, helipad, superweapon
  hosts, firestorm generator.

## 4. Production & tech

- **Queues** — Parallel category queues: **Building**, **Defense**, **Infantry**,
  **Vehicle** (War Factory), **Aircraft** (Helipad). Each factory maintains a queue;
  `MaximumQueuedObjects=25`. Building a queue item reserves credits then consumes them.
- **Prerequisites & tech levels** — `Prerequisite=` lists building ids (or `[General]`
  category aliases like `GDIFACTORY`, `RADAR`, `POWER`, `BARRACKS`, `TECH`). `TechLevel`
  gates by level; production building required for each category. `PrerequisitePower`,
  `PrerequisiteFactory`, `PrerequisiteBarracks`, `PrerequisiteRadar`, `PrerequisiteTech`
  map friendly aliases to concrete buildings.
- **Multiple factories** — Extra same-type factories speed production via
  `MultipleFactory` bonus (def `.5`); `[General] MultipleFactory` (FS `rules` shows .5).
- **Factory exits / rally** — Produced units exit at factory's `ExitCoord`/`NumberImpassableRows`,
  then head to the factory rally point. `ProductionExit` handles blocked exits, bails out
  to nearby cell. Aircraft land at pad (`PadAircraft=ORCA,ORCAB`); `SeparateAircraft=yes`
  means first aircraft built separately from helipad.
- **Upgrades / improvements** — `PowersUpBuilding=` / `PowersUpToLevel=` let one structure
  visually+functionally upgrade another (e.g. Nod Advanced Power Plant `NAAPWR` upgrades
  `NAPOWR`; GDI `GAPOWRUP` turbine upgrades `GAPOWR`). `PowersUpToLevel=-1` = terminal.
  Upgrades tied to `[General]` hack ids (`NodAdvancedPower`, `GDIPowerTurbine`).
- **Deploy-to-produce** — **[FS]** Mobile War Factory (`MOBWARG`/`MOBWARN`) deploys to
  `DGWEAP`/`DNWEAP` with `Factory=UnitType` and `WeaponsFactory=yes`; `BuildLimit=1`.
- **Queued-object UX & cameos** — `Cameo=` icon, `CrateGoodie`, `BuildLimit`,
  `AllowedToStartInMultiplayer`, `AIBasePlanningSide`.

## 5. Units & combat

- **Infantry categories** — Light/rocket infantry (`E1`,`E2`), grenadiers/disk throwers
  (`E3`, `DISC`), engineers, medics, jumpjet infantry (`JUMPJET`), snipers, spies
  (`CHAMSPY`), commandos (`GHOST`), named heroes (Umagon `UMAGON`, Oxanna, Slavik, Tratos,
  McNeil/`MWMN`). **Cyborgs/cybernetics:** `CYBORG`, `CYC2` (Cyborg Commando), and **[FS]**
  `REAPER` (Cyborg Reaper, spider-legged, webs). Mutants (`MUTANT`, `MUTANT3`) and
  civilian/mutant fauna (visceroids, tiberian fiends).
- **Vehicles** — Tanks (Titan `MMCH`, Grizzly? no; Predator? no — TS GDI Titan is the
  MBT, Wolverine walker `SMECH`), Mammoth Mk.II `HMEC` (giant walker, railgun + tusk),
  Nod Tick Tank `TTNK` (deploys to `GATICK` emplacement), Nod Attack Cycle `BIKE`, Attack
  Buggy `BGGY`, Artillery `ART2`, Subterranean APC `SAPC`, Devil's Tongue `SUBTANK`
  (subterranean flamer), Mobile Sensor Array `LPST`, Disruptor `SONIC` (GDI sonic),
  Hover MLRS `HVR`, Amphibious APC `APC`, MCV, Harvester. **[FS]** adds Juggernaut `JUGG`
  (deploys `DJUGG`, triple 90 mm), Mobile EMP `MOBILEMP` (charge `PipScale=Charge`),
  Limpet Drone `LIMPET` (deploys `DLIMPET` mine, attaches to vehicles), Mobile Stealth
  Generator `SGEN` (deploys `MSTL`).
- **Aircraft** — GDI Orca Fighter `ORCA`, Orca Bomber `ORCAB`, Orca Carryall `ORCATRAN`
  (transport), Orca Transport, Dropship `DSHP`; Nod Harpy `APACHE`? (Apache = Nod gunship),
  Banshee `SCRIN`? (Banshee = Nod fighter in TS). Drop Pod `DPOD`. Aircraft are
  `PadAircraft`, land to rearm (`ReloadRate`, ammo). `Pilot`/parachute on death.
- **Turrets / ROT** — Independent turret rotation with `ROT`, `TurretAnim`, `BarrelAnim`;
  some units have `IsTilter`, `TargetLaser`. Deployed structures can add turrets
  (`TurretAnim`, `TurretAnimIsVoxel`, voxel barrel offsets).
- **Weapon types** — Primary/secondary/tertiary; projectile + warhead + `ROF`, `Range`,
  `Burst`, `BurstDelay`, `Charges`, `Ammo`, `Reload`. `TurboBoost` anti-air bonus; `Incoming`
  threat-avoid; `NoMovingFire`; `FireAngle`; `Artillary`.
- **Deploy units** — MCV→ConYard, Juggernaut→gun platform, Tick Tank→emplacement, Limpet
  →mine, sensor array→repaired sensor, EMP/stealth/War Factory deploy. Deploy/undeploy
  state machine with anims and `DeployToFire`.
- **Special units** — Mammoth Mk.II (GDI, `Trainable=no`, `SelfHealing`), Juggernaut (FS,
  `DeployToFire=yes`), Hunter-Seeker droids (both, skirmish), Limpet Drone (FS), Core
  Defender (FS/CABAL, `IsCoreDefender`), Cyborg Reaper (FS).
- **EMP** — Disables mechanical units/structures for a duration; `EMPulseSparkles` overlay;
  warhead `EMPuls` / `[FS] MobileEMPulse`; delivered by EMP superweapon and FS Mobile EMP.
- **Cloaking / stealth** — `Cloakable` units (Nod stealth tank, Chameleon spy, submarine),
  `CloakingSpeed`, `CloakingStages`; **[FS]** Mobile Stealth Generator (`CloakGenerator`,
  `CloakRadiusInCells`), Limpet drone cloaked mine.
- **Subterranean (Nod)** — `Locomotor=Subterranean`, burrow/emerge via `DIG` anim
  (`DigSound`), invisible while underground; cannot be attacked except by sensors/sonic;
  `AllowShroudedSubteranneanMoves`. Subterranean APC + Devil's Tongue; tunnel entrance
  overlays (`TRACKTUNNEL01..04`, `TUNTOP01..04`).
- **Jumpjets** — GDI jumpjet infantry; `[JumpjetControls]` governs flight; airborne jumpjet
  vehicles are immune to most damage (only ambient like railguns); `CloakDetectionRadius`.

## 6. Movement

- **Locomotion types** — `Foot`, `Track`, `Wheel`, `Hover`, `Amphibious`, `Fly`,
  `Jumpjet`, `Subterranean`, `Ship` (repo locomotor catalog). Movement speed = base speed ×
  terrain multiplier × uphill/downhill coefficients (`TrackedUphill/Downhill`,
  `WheeledUphill/Downhill`).
- **Terrain passability** — Per-locomotor legal land types and speed multipliers; water is
  0 for ground, hover gets boosted straight-line speed (`HoverBoost`), amphibious crosses
  both. Cliffs/impassable cells excluded from pathing.
- **Crushing** — `Crusher=yes` + `Weight` lets vehicles run over infantry/crushable objects
  (`Crush` distance, `PlayerAutoCrush`, `AutoCrush` IQ). Mammoth/titans crush; `TiltsWhenCrushes`.
- **Ice** — Frozen water overlay; units above `IceCrackingWeight` crack, above
  `IceBreakingWeight` fall through/drown (`ice-drowning`); `IceGrowthRate`,
  `IceSolidifyFrameTime`.
- **Bridges / land** — Bridges are destructible overlays (`DestroyableBridges`,
  `BridgeStrength`, `BridgeExplosions`, `BridgeVoxelMax`); land-to-water bridging; rail
  bridges; low bridges.
- **Tunnel network (Nod)** — Subterranean units surface at tunnel entrances/overlays;
  `SpeedType`/`MovementZone` gated. **[uncertain]** exact tunnel-entrance link rules.
- **Movement zones** — `MovementZone=Normal/Destroyer/Crusher/AmphibiousDestroyer` controls
  what terrain a mover may enter and what it may crush; `NoMovingFire`, `Accelerates`,
  `AccelerationFactor`.
- **FS additions** — Limpet drone hover+attach slows victims; Mobile War Factory, EMP,
  stealth gen all get mobile locomotor behavior.

## 7. Vision & fog

- **Shroud vs fog** — Unexplored shroud (solid) vs explored fog (dim). `ShroudGrow`,
  `ShroudRate`, `FogRate`, `BlendedFog`; units/buildings reveal radius; `AircraftFogReveal`,
  `AttackingAircraftSightRange`.
- **Radar** — Requires a radar structure (`GARADR`/`NARADR`); `RadarOn/Off` sounds; radar
  shows explored map + unit blips; radar events (`RadarEvent*`) mark combat, harvester
  attack, drop zones; `RadarEventColorSpeed`, suppression distances.
- **Reveal mechanics** — `RevealTriggerRadius`, drop-zone beam reveals (`DropZoneRadius`,
  `DropZoneAnim=BEACON`), spy camera reveal (`CameraRange`), map reveal triggers, Ion Storm
  reveals? Allies auto-share (`AllyReveal=yes`).
- **Sensors vs jammers/stealth** — `Sensors=yes` units/structures (Mobile Sensor Array
  `LPST`, Nod `NASTLH`?) detect cloaked/subterranean; `CloakDetectionRadius` on jumpjet
  controls; stealth generators hide friendlies in radius; Hunter-Seeker ambush pop-out.
  **Radar jammer** — Nod `NASTLH` (Mobile Stealth Generator / Stealth Generator) and
  Radar-Jammer-like effects obscure enemy radar. **[uncertain]** whether TS has a distinct
  radar-jammer building vs the stealth generator.
- **FS** — Mobile Stealth Generator (`MSTL`, `CloakRadiusInCells=6`, `Sensors=yes`) extends
  the interplay; Web immobilizes revealed infantry (`WEBGUY`).

## 8. Special systems

- **Ion Cannon (GDI)** — Superweapon from GDI Tech Center (`SuperWeapon=IonCannonSpecial`),
  `IonCannonDamage=751`, `IonCannonWarhead`, beam anims (`IonBlast=RING1`, `IonBeam=IONBEAM`).
  AI target weighting via `AIIonCannon*` values.
- **Multi Missile (Nod)** — Cluster missile from Missile Silo (`MultiSpecial`), splits into
  submunitions over target.
- **Chemical Missile (Nod)** — From Missile Silo, requires Tiberium Waste Facility fuel
  (`WeedCapacity=56`, harvested by Weed Eater `WEED`); leaves toxic tiberium gas clouds
  (lethal to infantry). `[FS]` gas/weak-gas warheads.
- **Hunter-Seeker (both, skirmish)** — Stealth kamikaze droid ambushing from `GAPLUG`/
  `NATMPL` (`HSBuilding`); flight controls `HunterSeeker*`.
- **Drop Pods (GDI)** — `DropPodSpecial`; drop pod (`DPOD`) descends (`DropPodHeight/Speed/
  Angle`), `DropPodWeapon=DropGun`, `AtmosphereEntry`, `DropPodPuff`; **[FS]** raises
  `DropPodInfantryMinimum/Maximum` from 3/5 to 12/15.
- **EMP superweapon** — `EMPulseSpecial` (`EMPulseWarhead=EMPuls`,
  `EMPulseProjectile=PulsPr`); disables mechanical targets. Host building **[uncertain]**.
- **Firestorm Generator (GDI, FS)** — `GAFIRE`, `SuperWeapon=FirestormSpecial`; projects a
  defensive energy barrier (`ChargeToDrainRatio`, `DamageToFirestormDamageCoefficient`,
  `FirestormWarhead`); FSAIR/FSGRND/FSIDLE anims. **[FS]**
- **Mobile EMP (GDI, FS)** — `MOBILEMP`, charge meter, area EMP pulse. **[FS]**
- **Mobile Stealth Generator (Nod, FS)** — `SGEN`→`MSTL`, cloaks allies in radius. **[FS]**
- **Laser fence (Nod)** — `NAPOST` posts + `NAFNCE` sections, powered barrier. **[TS]**
- **Ion storms (weather)** — Dynamic global weather; lightning damages (`IonLightning*`,
  `IonStormDuration/Warning`, `IonStormWarhead`), disables radar/superweapons while active,
  reveals map. Toggle `IonStorms`. **[TS]**
- **Meteorites / terrain-altering** — `Meteorites` toggle; meteor impacts crater terrain
  (`CraterLevel`, `METEOR01/02` voxel anims, `MeteorWH` FS). **[FS]** `CraterLevel` tuning.
- **Engineers / capture** — Instant capture; `Engineer=` survivor type from ConYard.
- **CABAL faction (FS)** — AI-controlled enemy with Core Defender (`DEFENDER`/`DDEFD`),
  CABAL Obelisk (`CROB`), `CORE` (Cabal Core). **[FS]**
- **Veinhole monster** — Living vein node (`VEINTREE`, `VeinholeTypeClass`), attacks
  (`VeinAttack`), growth/shrink; repelled by chemical/EMP? **[uncertain]**.
- **Visceroids / mutants** — Tiberium-induced life; small visceroids merge into large
  (`LargeVisceroid`/`SmallVisceroid`), infantry transmogrify (`TiberiumTransmogrify`).

## 9. UI/UX & controls

- **Sidebar layout** — Right-hand tabbed sidebar: building tabs (Structures, Defenses,
  Infantry, Vehicles, Aircraft), cameo grid, credit counter, power bar, minimap. Cameos with
  cost and ready/clocking state; `MaximumQueuedObjects` queue pips.
- **Radar / minimap** — Toggleable radar (hotkey), unit blips, radar events, shroud on map,
  click-to-move camera; requires radar structure.
- **Health / pips / condition** — Health bar colors (`ConditionYellow=50%`,
  `ConditionRed=25%`), `EnemyHealth` shows enemy bars; veteran pips (`VeteranCap=2`);
  charge pips (`PipScale=Charge`) for EMP.
- **Control groups** — Numeric hotkey groups; double-tap focuses.
- **Action cursors** — Context cursor per `OrderSystem` (move, attack, force-attack, deploy,
  capture, repair, sell, guard, waypoint, no-entry). Right-click = deselect/cancel/clear;
  left-click = select/act (repo convention mirrors TS).
- **Stances / orders** — Guard, Guard Area (`GuardArea` IQ), Hold, Stop, Scatter
  (`Scatter`), Deploy, Capture, Repair, Sell, Waypoint (`MaxWaypointPathLength=15`).
- **Rally / production UX** — Set factory rally point; new units route there; `SeparateAircraft`
  first-aircraft flow; MCV deploy prompt.
- **Tech tree presentation** — Prerequisite gating grays out unavailable cameos; tech level
  progression; building-first UX (build power→refinery→barracks/factory).
- **FS UI** — New tabs/cameos for FS units; charge bars; mobile deploy prompts. **[uncertain]**
  any pure-UI FS changes beyond roster.

## 10. Presentation & audio

- **Voxels / 2.5D** — TS is 2D isometric with voxel-rendered vehicles/structures (voxel
  turrets/barrels via `VoxelBarrelFile`, `VoxelBarrelOffset*`), infantry/FX as sprites.
  Voxel debris (`VoxelAnims`: PIECE, TIRE, GASTANK, METEOR01/02). Lighting/spotlights
  (`Spotlight*`), ambient light cycling (`AmbientChangeRate/Step`).
- **Animations** — Rich `[Animations]` table: explosions (`EXPLOSML/MED/LRG`), smudges,
  craters, building build-up (`GACNST_A..`, `*_A/_AD/_B...`), death anims (`DEATH_A..F`),
  infantry death (`INFDIE`, `S_BANG*`), fire (`FIRE1..4`), ion beam rings, drop pod rings,
  EMP sparkles, web.
- **Smudges / overlays** — Scorch marks (`Scorches`), craters (`Craters`), tiberium
  overlays, tracks, bridges, veins, crates. These persist and affect/represent state.
- **Particles** — `[Particles]`/`[ParticleSystems]`: gas clouds, smoke, fire, sparks,
  railgun parts, repair welder, firestorm, web, smoke stacks.
- **EVA voice set** — GDI/Nod EVA announces ("Construction complete", "Our base is under
  attack", "Insufficient funds", "Unit lost", superweapon warnings). `SpeakDelay` throttles
  repeats; `IncomingMessage`/`SystemError` sounds.
- **Unit acknowledgements** — Per-unit `VoiceSelect`/`VoiceMove`/`VoiceAttack`/`VoiceFeedback`
  (e.g. Titan `25-I000`, Cyborg Reaper `60-N1xx`); `ScoldSound`; idle actions
  (`IdleActionFrequency`).
- **Music** — Westwood dynamic score (menu + per-faction in-game tracks). **[uncertain]**
  in-engine track-switching rules.
- **Explosions / death anims** — Unit `Explosion=` composite lists; buildings crumble
  (`CrumbleSound`); bridge explosions; screen shake (`ShakeScreen`); `CrewEscape` crew spawn.

## 11. Campaign & mission scripting

- **Mission structure** — Linear per-faction campaigns (GDI ~12, Nod ~12 missions);
  each map is `.map` with a sibling `.ini` for triggers; briefing FMV + text. FS has full
  FMV briefings for both campaigns.
- **Triggers / events / actions** — Map INI defines triggers: event conditions (cell entry,
  time, destroyed, global set) → actions (reinforce, reveal, message, win/lose, create team,
  change house). `ai.ini` defines TeamTypes, TaskForces, ScriptTypes, AITriggerTypes, and
  weights (`AITriggerSuccessWeightDelta`, etc.).
- **Objectives** — Primary/secondary objectives surfaced in mission UI; `TimerWarning`
  mission timer turns red near expiry.
- **Houses / taskforces / teamtypes** — `[Houses]`, `[Sides]`, `[Countries]`; AI teams
  built from `TaskForces` (member groups), `TeamTypes` (behavior flags), `ScriptTypes`
  (action lists); difficulty via `TeamDelays`, `AIHateDelays`, `MultiplayerAICM`.
- **Waypoints** — Named map waypoints for spawns, patrols, reinforcement entry,
  `RevealTriggerRadius` reveal-around-waypoint.
- **Reinforcements** — Land/sea/air entry; drop pods (`DropPodSpecial`), paratroopers
  (`Paratrooper`), transport drops; `Pilot`/`Crew` survivors.
- **Cinematic camera** — Scripted camera moves + letterbox for FMV/briefing transitions;
  `SavourDelay` before end movie; waypoint animation (`WaypointAnimationSpeed`).
- **Win/lose** — Trigger-driven; `SavourDelay`; score screen (`StatisticTimeInterval`).

## 12. Skirmish / multiplayer & meta

- **Skirmish AI** — `[AI]` block: base composition ratios (`RefineryRatio`, `BarracksRatio`,
  `WarRatio`, `DefenseRatio`, `AARatio`, `HelipadRatio`), limits, power surplus
  (`PowerSurplus`), credits reserve, build order (`BuildConst/Power/Refinery/...`); `[IQ]`
  gates autonomy by level (SuperWeapons, Production, GuardArea, RepairSell, AutoCrush,
  Scatter, Aircraft, Harvester, SellBack). Threat evaluation `[General]` coefficients.
- **Difficulty** — 3 levels by default (TeamDelays etc.); `FineDiffControl=yes` enables 5.
  `CompEasyBonus`, `Paranoid` (AIs ally when losing).
- **Map selection** — Skirmish map list (`.mpr`), random start positions, player colors,
  `AllowedToStartInMultiplayer`.
- **Multiplayer modes** — Up to 8 players (`[Maximums] Players=8`); team / free-for-all;
  `CaptureTheFlag` option; `MultiplayerDefaults` (Money, Bases, TiberiumGrows, Crates,
  ShadowGrow); `Multiplay=yes`/`MultiplayPassive` houses; `MultiplayerAICM`.
- **Meta options** — Crates on/off, shadow grow, bases on/off, starting credits, fog.
- **FS** — CABAL House as a playable/enemy faction and FS-specific skirmish maps.

## 13. Modding / data architecture

- **rules.ini** — Core data: `[General]`, `[CombatDamage]`, `[InfantryTypes]`,
  `[VehicleTypes]`, `[AircraftTypes]`, `[BuildingTypes]`, `[TerrainTypes]`, `[SmudgeTypes]`,
  `[OverlayTypes]`, `[Animations]`, `[VoxelAnims]`, `[Particles]`, `[ParticleSystems]`,
  `[Warheads]`, `[SuperWeaponTypes]`, `[Houses]`, `[Sides]`, `[Countries]`, `[AI]`, `[IQ]`,
  `[MultiplayerDefaults]`, `[CrateRules]`, `[Maximums]`, `[SpecialWeapons]`,
  `[JumpjetControls]`, `[AudioVisual]`. Per-object sections (`[MMCH]`, `[GACNST]`, …) hold
  stats. Values accept float or percent, distances in cells, times in minutes.
- **Object-list registration** — New object needs a section **and** an entry in the matching
  list; list order matters for indexed internal tables (esp. `[Animations]`). "Cloning" =
  copy a section + add to list + reuse `Image=` art.
- **art.ini** — Per-variant art: `Cameo`, `Image`, `Voxel=yes`, turret/barrel voxel refs,
  build-up anims, `Remapable`, `TerrainPalette`, `Sequence`, weapon fire anims.
- **ai.ini** — TaskForces/TeamTypes/ScriptTypes/AITriggerTypes and global AI weighting.
- **INI inheritance** — TS-era engine does **not** have general template inheritance like
  later RA2/YR `#include`/logic; reuse is via `Image=`, shared sections, and orphaned
  sections. FS ships `rules.ini`/`art.ini`/`ai.ini` merged over base.
- **Maps** — `.map` (single-player), `.mpr` (multiplayer), `.mmx` (map/expansion container
  — actually a MIX-style pack?); **[uncertain]**. Per-map sibling `.ini` holds local rules
  overrides + triggers + house/team data. Maps may override nearly any rules value.
- **Tilesets / theaters** — Per-theater tile sets + palettes; `.tem`/`.sno` (and urban)
  variants; terrain objects (trees, rocks, tiberium, ice, boxes) drawn from tileset art.
- **MIX archives** — Assets packed in `.mix`; loose files override packed.
- **FS campaign deltas** — FS maps ship as `Firestorm` scenario condition (`Firestorm=yes`
  map flag) gating FS units/structures; merged rules.

---

## TS → FS deltas

**New GDI**
- Juggernaut `JUGG` → deployed `DJUGG` (triple 90 mm, `DeployToFire`, radar prereq).
- Mobile EMP `MOBILEMP` (+ precharged `CMOBILEMP`) — charge-meter area EMP.
- Mobile War Factory `MOBWARG` → deployed `DGWEAP` (mobile War Factory, `BuildLimit=1`).
- Firestorm Generator `GAFIRE` — `FirestormSpecial` defensive barrier.
- Limpet Drone `LIMPET` → deployed `DLIMPET` mine (attach/scout/slow vehicle).

**New Nod**
- Cyborg Reaper `REAPER` — cybernetic spider walker, QuadLauncher + WebLauncher.
- Mobile Stealth Generator `SGEN` → deployed `MSTL` (cloak radius, sensors).
- Mobile War Factory / "Fist of Nod" `MOBWARN` → `DNWEAP`.
- `NAOBEL`/Obelisk of Darkness `AAOB`, Laser Fence `NAPOST`/`NAFNCE` (base TS? fence is TS; AA Obelisk FS).
- Limpet Drone (shared).

**New CABAL**
- Core Defender `DEFENDER` → `DDEFD` (super-heavy, `Immune=yes`, `IsCoreDefender`).
- CABAL Obelisk `CROB`, Cabal Core `CORE`. CABAL as a distinct house/faction.

**Rules/general changes**
- Drop pods: `DropPodInfantryMinimum/Maximum` 3/5 → 12/15.
- `BallisticScatter` 1.5 → 2.0.
- `EngineerCaptureLevel=1.0`, `EngineerDamage=0.0`.
- New warheads (WebMass, LIMPY, CoreDefPlasmaWH, Super2, MobileEMPulse, WeakGass, Stinger,
  MeteorWH, ARTYHEX, Gas2); new particles/particle systems (Web, WeakGasCloud, SmokeStackPuff).
- New animations (sections 801+); new superweapon types enabled (Firestorm, DropPod).
- New "mutated" theater/ecology tiles; veinhole tuning (`VeinholeGrowthRate/ShrinkRate`).
- `ChargeToDrainRatio`, `DamageToFirestormDamageCoefficient` for firestorm defense.
- New units are `TechLevel=-1` when deployed forms; FS roster added to `[VehicleTypes] 61..`.
- Meteor/terrain crater controls (`CraterLevel`) surface.

**Reused/upgraded TS content in FS**
- Limpet deploys`LIMPET` uses both GDI+Nod; CABAL reuses Obelisk/Core assets.
- Several TS units retuned (costs/strength) and marked FS-only via scenario flag.

---

## Unified-engine implications

**Generic RTS systems (engine-level, reusable)**
- Isometric/heightmap grid, cell + sub-slot occupancy, foundation/footprint.
- Land-type → locomotor speed/passability table; movement zones; crushing/weight.
- Damage = Warhead × Verses[armor-class] matrix; projectile archetypes
  (hitscan/ballistic/homing/lobbed/laser/pulse).
- Production queues, prerequisites/tech-level gating, multiple-factory bonus, factory
  exit + rally, upgrades that power-up a target building.
- Power grid (supply/demand + low-power penalties), veterancy (XP ratio + stat bonuses),
  sell/repair, build placement adjacency + block.
- Shroud/fog two-layer vision, radar, reveal triggers, sensor/cloak detection interplay.
- Superweapon/support-power framework (charge, target, fire, cooldown) — Ion, cluster,
  gas, EMP, shield, drop-pod, kamikaze drone are all data.
- Crate/pickup system; resource growth/spread; harvester AI + dock/unload; silo overflow.
- Trigger/event/action mission scripting; House/TaskForce/TeamType/ScriptType AI meta;
  waypoints/reinforcements/cinematic camera.
- INI-style data layers with list registration and overrides; map-local rules overrides.

**TS-specific data / systems (game content, not engine)**
- Exact armor classes `none/wood/light/heavy/concrete` and the TS warhead roster (data).
- Tiberium Riparius/Vinifera + veins/veinholes as resource+hazard model.
- Concrete faction rosters, prerequisites, `[General]` hack ids (gate/wall/power link).
- Subterranean + jumpjet + hover + ice + ion-storm + drop-pod specifics as locomotor/weather
  data.
- Cyborg/Reaper, CABAL faction, Firestorm barrier, Limpet attach, Web immobilize.
- Building-specific quirks (bib, adjacent radii, deploy/undeploy pair, voxel turret offsets).

**Design cautions for a unified engine**
- Keep damage/armor/verses and warhead effects fully data-driven — TS's matrix is the core
  balance surface and mods rewrite it.
- Model shroud vs fog as two separate grids; TS treats them differently (regrow, blend).
- Distinguish `foundation` (authored) from `footprint` (derived) and keep bibs a pathing
  cost, not a hard block.
- Treat deploy/undeploy as a first-class reversible state (MCV, Juggernaut, Tick Tank,
  Limpet, EMP, stealth, mobile war factory) — one component covers all.
- Support-weapon framework must allow both global (Ion) and deployed-local (Firestorm,
  Mobile EMP) delivery, plus attached-effect weapons (Limpet attach, Web).
- Scenario/map flags (e.g. FS `Firestorm=yes`) should gate roster availability without
  duplicating data sets.

---

## Sources

- TS/FS `Rules.ini` (Firestorm-merged) — retrieved from the Mistweaver `tiberian-sun-mod`
  repository (`Rules.ini`): `[General]`, type lists, object sections, warheads, superweapons,
  AI/IQ, crate/audio-visual sections. Primary grounding for numbers and section names.
- ModEnc (modenc.renegadeprojects.com) — `Rules.ini`, `Verses`/`Armor types`, `JumpJet`,
  `JumpjetControls`, `INI`.
- C&C Fandom / CNC Central wikis — TS & Firestorm overview, Limpet drone, Reaper, Multi
  missile, Chemical missile, Hunter-Seeker, Missile silo, Juggernaut/Mobile EMP lists.
- CNCNZ.com — Firestorm new GDI/Nod weapons descriptions.
- Local repo `games/ts/` data model (armor types, warheads, projectiles, land types,
  locomotors, resource types, `global_rules.tres`) and `openspec/specs/` for canonical
  ReSun terminology (foundation/footprint/bib/locomotor/land-type).
- Items marked **[uncertain]** were not verifiable via the sources reached (Fandom blocked
  403 for direct reads) and are flagged rather than asserted.
