# Tiberian Sun — Gameplay Systems & Content Rosters (Web-Research Reference)

Exhaustive, web-sourced reference for the whole Tiberian Sun (TS) + Firestorm (FS) gameplay model,
intended as a data model for the unified ReSun engine. **Web-only research**; the primary
authority is the shipped `RULES.INI` (recovered via the Vinifera INI archive) cross-checked against
ModEnc, the Command & Conquer Wiki (cnc.fandom), Project Perfect Mod, CnCNet forums, and released
engine sources (EA `CNC_TS_and_RA2_Mission_Editor`, OpenTS).

**Scope note on the primary source.** The `RULES.INI` recovered is
`Name=Tiberian Sun - Firestorm` — i.e. it is the *Firestorm-updated* ruleset (it already contains
Firestorm units and the FinalSun-era `MultiFactory`/`MaximumQueuedObjects=25` changes). Where the
original 1999 TS rules differed, this is flagged. Numbers below are taken verbatim from that file;
behavioral claims that are not expressible as INI values come from guides and are marked by
confidence.

## Sources

| Tag | Source | URL |
|-----|--------|-----|
| S1 | TS/Firestorm `RULES.INI` (Vinifera INI archive) | https://raw.githubusercontent.com/Vinifera-Developers/Tiberian-Sun-INIs/master/RULES.INI |
| S2 | `RULES.INI` alternate mirror (Mistweaver) | https://github.com/Mistweaver/tiberian-sun-mod/blob/master/Rules.ini |
| S3 | Tebrey's Guide to Editing Tiberian Sun | http://tiberian.iwarp.com/editingguidetots.htm |
| S4 | ModEnc — Rules.ini | https://modenc.renegadeprojects.com/Rules.ini |
| S5 | ModEnc — MovementZone | https://modenc.renegadeprojects.com/MovementZone |
| S6 | ModEnc — Harvester | https://modenc.renegadeprojects.com/Harvester |
| S7 | ModEnc — AITriggerTypes | https://modenc.renegadeprojects.com/AITriggerTypes |
| S8 | ModEnc — Theaters | https://modenc.renegadeprojects.com/Theaters |
| S9 | ModEnc — Theater | https://modenc.renegadeprojects.com/Theater |
| S10 | ModEnc — Warhead | https://modenc.renegadeprojects.com/Warhead |
| S11 | C&C Wiki — Crate | https://cnc.fandom.com/wiki/Crate |
| S12 | C&C Wiki — Multi missile | https://cnc.fandom.com/wiki/Multi_missile |
| S13 | C&C Wiki — Ion cannon | https://cnc.fandom.com/wiki/Ion_cannon |
| S14 | C&C Wiki — TS units/arsenal categories | https://cnc.fandom.com/wiki/Category:Tiberian_Sun_units |
| S15 | C&C Wiki — Missile silo (TS) | https://cnc.fandom.com/wiki/Missile_silo_(Tiberian_Sun) |
| S16 | CnCNet — How to make/edit AI behaviour (ai.ini) | https://forums.cncnet.org/topic/1642-how-to-make-or-edit-an-ais-behavior-in-tiberian-sun-and-in-red-alert-2 |
| S17 | CnCNet — TS Settings and Options (skirmish options) | https://forums.cncnet.org/topic/5841-tiberian-sun-settings-and-options |
| S18 | TiberiumWeb — Tiberian Sun `.MIX` Guide | https://www.tiberiumweb.org/forums/index.php?showtopic=31 |
| S19 | Tiberian Sun Strategy Guide — Economy | https://tiberiansunguide.wixsite.com/tiberiansunguide/economy |
| S20 | ModDB — TSE GDI / Nod Superweapons | https://www.moddb.com/mods/tiberian-sun-evolved/features/gdi-superweapons , /nod-superweapons |
| S21 | PPM — TS AI Trigger Types / Script Types / Team Types | https://sun.projectperfectmod.com/aitriggertypes |
| S22 | EA released source — CNC_TS_and_RA2_Mission_Editor | https://github.com/electronicarts/CNC_TS_and_RA2_Mission_Editor |
| S23 | PPM — TS Newbie Guide in Modding | https://sun.projectperfectmod.com/tsnewbieguide |
| S24 | OpenTS source reconstruction | https://github.com/OpenTS-Developers/OpenTS |
| S25 | Vanilla Conquer (open reimplementation) | https://github.com/TheAssemblyArmada/Vanilla-Conquer |

Confidence legend: **high** = value read directly from shipped `RULES.INI` or a documented engine
flag; **med** = consistent across ≥2 secondary sources or one authoritative guide; **low** = single
source, community folklore, or known-conflicting.

---

## 1. ECONOMY

### TS-GP-001 Tiberium Types & Values
**What.** TS has two harvestable Tiberium resources rendered as overlays. Green = *Riparius*
(overlays `TIB01`–`TIB20`, ids 105–124; "ripe" variants `TIB2_01`–`TIB2_20`, ids 130–149; "blue"
variants `TIB3_01`–`TIB3_20`, ids 150–169). Blue = *Vinifera*, worth more credits per bail. The
engine treats them as overlay cells with a density stage per index; each cell also has a "ripe"
alternate. `[CombatDamage] TiberiumExplosive=yes`, `TiberiumStrength=20`, `TiberiumExplosionDamage=100`.
**Data keys.** `[OverlayTypes]` (105–169), `GrowthRate`, `TiberiumGrows`, `TiberiumSpreads`,
`TiberiumHeal`, `TiberiumTransmogrify`, `TiberiumExplosive`, `TiberiumStrength`,
`TiberiumExplosionDamage`, `[CombatDamage] TiberiumExplosive`.
**Numbers.** Community-measured (med/low): 1 full green harvester load = **$700**; 1 full blue load =
**$1120** (difference $420). Full green Refinery = **$2000**, full blue Refinery = **$3200**. Full
green Silo = **$1500**, full blue Silo = **$2400**. Green cell = ~6–7 harvest "ticks" at ~$125 each;
blue cell = ~10–11 ticks at ~$200 each. `TiberiumHeal=.010` min between Tiberium heal ticks.
**Edge cases.** Mixed green/blue inside one Ref/Silo yields an interpolated value; money is stored
inside Ref/Silo and is *lost* if they are destroyed. `TiberiumTransmogrify=40` = 40% of infantry
killed on Tiberium become Visceroids. Guide numbers are internally inconsistent ($125×6=$750 vs
$700 load); treat the load value as authoritative.
**Kind.** resource / data.
**Sources.** S1, S4, S19, S11.
**Confidence.** high (types/keys), med (credit values).

### TS-GP-002 Tiberium Growth, Spread, Overgrowth
**What.** Tiberium densifies and creeps to adjacent cells over time; a cell may "regrow" if a
Tiberium tree is present.
**Data keys.** `[General] GrowthRate=5`, `TiberiumGrows=yes`, `TiberiumSpreads=yes`.
**Numbers.** `GrowthRate=5` = one growth step every **5 minutes** (per cell density stage);
guide recommends never below 3. `TiberiumGrows=yes` densification; `TiberiumSpreads=yes` lateral
spread.
**Edge cases.** The 8 cells immediately around a Tiberium Tree regenerate (community, med); a
harvester parked on them can farm indefinitely. Ice/snow maps grow less Tiberium (`GrowthRate` is
global but snow tissue has fewer spawn cells). Tiberium can also be released by the "Tiberium" crate.
**Kind.** world simulation.
**Sources.** S1, S3, S19.
**Confidence.** high (values), med (tree-regrowth rule).

### TS-GP-003 Harvester Logic
**What.** `HARV` (GDI/Nod, `Harvester=yes` implicit via category) is the miner: scans for Tiberium,
drives cell-to-cell, extracts bails into an internal buffer (`Storage=28` bails), auto-returns to the
nearest/owning `PROC` Refinery to unload.
**Data keys.** `[HARV] Storage=28`, `Dock=PROC`, `MovementZone=Crusher`, `SelfHealing=yes`,
`ImmuneToVeins=yes`, `PipScale=Tiberium`; `[AI] TiberiumNearScan=6`, `TiberiumFarScan=48`,
`HarvesterUnit=HARV`, `[IQ] Harvester=2`.
**Numbers.** `Storage=28` bails; `TiberiumNearScan=6` cells (re-scan same patch), `TiberiumFarScan=48`
cells (seek new patch). `[General] TiberiumHeal=.010`, `WeedCapacity=56` (weed bails per chem missile).
Guide timings (med): green cell ~2–3 s to drain, blue ~2–3 s; ~3 dumps fill a Ref/Silo; blue and green
unload at the same rate.
**Edge cases.** Harvester AI is known-poor: may seek a *farther* patch when a nearer one exists
(S19); harvesters creep north over time; they can get stuck on shorelines (GDI can lift with Carryall,
Nod cannot); a Harvester destroyed while unloading can destroy the Refinery and vice-versa. Newly
built harvesters auto-seek Tiberium in the patched game; in the original they had to be manually
ordered. `HarvesterImmune=no` by default. Losing all Refineries stops harvesting entirely (a Harvester
cannot unload without an owner Ref/Silo, though it may unload into an ally's).
**Kind.** unit AI / data.
**Sources.** S1, S3, S6, S19, S24.
**Confidence.** high (values), med (timings), low (exact scan-to-move algorithm).

### TS-GP-004 Refinery Dock / Unload
**What.** Refinery acts as a dock and storage unit; the Harvester drives onto the pad and unloads
bails into the owning player's credit pool, subject to storage caps.
**Data keys.** `[PROC] Refinery=yes`, `DockUnload` (implicit), `Storage=80`, `FreeUnit` (harvester),
`Power=-30`, `Bib=yes`, `Prerequisite=POWER`, `Capturable=true`, `PipScale=Tiberium`,
`[General] UnloadingHarvester=HORV` (audio-visual empty-hull image).
**Numbers.** Refinery `Storage=80` (credits value $2000 green / $3200 blue per S19). Free Harvester on
completion. Unload time ≈ 0.96 s/bail community figure (med); a full 28-bail load ≈ 27 s (conflicts
with S19's 9.6 s claim for 10 bails — see open questions).
**Edge cases.** Only one Ref/Silo fills at a time; money is drawn from one at a time. Selling a Ref
transfers its stored credits to remaining Ref/Silos; if none remain the credits are kept as cash.
Multiple refineries queue harvesters for a single dock.
**Kind.** building logic / data.
**Sources.** S1, S19, S3.
**Confidence.** high (storage), med (unload timing), low (exact credit-per-bail mapping).

### TS-GP-005 Silo Storage & Credit Cap
**What.** Tiberium Silo extends the player's on-map storage so a surplus can be banked. Credits exist
both as free cash and as "stored" Tiberium inside Ref/Silo.
**Data keys.** `[GASILO] Storage=60`, `Power=-10`, `Prerequisite=PROC`, `Capturable=true`;
`[MultiplayerDefaults] Money=10000`, `MaxMoney=10000`; `[AI] CreditReserve=100`,
`AIAlternateProductionCreditCutoff=3000`, `RefineryRatio=.16`, `RefineryLimit=4`.
**Numbers.** Silo = 60 storage ($1500 green / $2400 blue). MP start money 10000, max 10000. AI reserves
100 credits before repairing; below 3000 AI spends conservatively.
**Edge cases.** Destroyed/sold Ref/Silo loses the credits inside unless transferred. `MaxMoney=10000`
caps MP starting money only (in-game credit pool has no explicit cap; storage caps banked Tiberium).
**Kind.** economy / data.
**Sources.** S1, S4, S19.
**Confidence.** high (values), med (practical cap semantics).

### TS-GP-006 Crates
**What.** Random powerup crates spawn in skirmish/MP when enabled; can help or hinder.
**Data keys.** `[CrateRules] CrateMaximum=255`, `CrateMinimum=1`, `CrateRadius=3.0`, `CrateRegen=3`,
`SilverCrate=HealBase`, `SoloCrateMoney=2000`, `UnitCrateType=none`, `WoodCrate=Money`,
`HealCrateSound=HEALER1`, `WoodCrateImg=CRATE`, `CrateImg=CRATE`, `FreeMCV=yes`;
`[MultiplayerDefaults] Crates=yes`; `[CombatDamage] AmmoCrateDamage=200`.
**Numbers.** `CrateRadius=3.0` cells AoE; `CrateRegen=3` min average respawn; `SoloCrateMoney=2000`;
`AmmoCrateDamage=200`; max 255 crates, minimum 1. Crate contents (TS, S11): credits (no storage
occupancy), veterancy (star), armour upgrade, firepower upgrade, speed upgrade, full heal, reveal map,
**cover/reshroud** map, one superweapon strike, a random unit (even an enemy MCV), light bomb,
explosive (kills picker + neighbours, may crater), chemical explosive (kills picker + 9×9 toxic gas),
Tiberium (spawns green/blue), cloak (permanent for nearby units). `FreeMCV=yes` gives a free MCV from a
crate if a player has money but no buildings.
**Edge cases.** Armour/speed/firepower bonuses do not stack (S11 RA2 note; TS behaviour similar, low).
Crates can be pre-placed as mission objectives.
**Kind.** scenario / data.
**Sources.** S1, S3, S11.
**Confidence.** high (keys), med (contents list).

### TS-GP-007 Veins / Veinhole Monster
**What.** Tiberium veins creep from a Veinhole and damage ground vehicles; Nod harvests the veins via
Weed Eater for the Chemical Missile.
**Data keys.** `[General] VeinholeGrowthRate=300`, `VeinholeShrinkRate=100`, `MaxVeinholeGrowth=2000`,
`VeinDamage=5`, `VeinholeTypeClass=VEINTREE`, `VeinholeWarhead=VeinholeWH`;
`[TerrainTypes] 44=VEINTREE`; `[OverlayTypes] 129=VEINS`, `170=VEINHOLE`, `181=VEINHOLEDUMMY`.
**Numbers.** Growth step 300 (higher = slower; was 3000 pre-patch), shrink 100 (was 500), max 2000
vein cells, `VeinDamage=5` damage per crossing tick. Veinhole Monster strength = `[VEINTREE]` entry
(no longer in `[General]`).
**Edge cases.** Destroying the veinhole causes the veins to recede (shrink). Units with
`ImmuneToVeins=yes` (most infantry, harvesters, walkers) ignore veins.
**Kind.** world hazard / resource.
**Sources.** S1, S3.
**Confidence.** high (values).

### TS-GP-008 Weed / Chemical Economy
**What.** Nod's secondary economy: harvest veins with the Weed Eater into the Tiberium Waste Facility,
which charges the Chemical Missile.
**Data keys.** `[General] WeedCapacity=56`; `[WEED] Dock=NAWAST`, `Storage=7`, `PipScale=Tiberium`;
`[NAWAST] Prerequisite=NAMISL`, `PipScale=Tiberium`, `Bib=yes`.
**Numbers.** `WeedCapacity=56` weed bails must be harvested by a house to build the Chem missile;
charge rate "determined in the Super Weapon section" (not exposed). Weed Eater `Storage=7`.
**Edge cases.** Requires a Veinhole in range; only Nod. Chemical missile is launched from the Missile
Silo (`NAMISL`), which is prerequisite for the Waste Facility — the reverse of a normal chain.
**Kind.** economy / superweapon input.
**Sources.** S1, S3, S15.
**Confidence.** high (keys), low (charge rate).

### TS-GP-009 Harvester Bombs
**What.** A full (ideally blue) Harvester driven next to enemy structures then destroyed produces a
large volatile explosion via the standard vehicle explosion rule; blue Tiberium is more explosive.
**Data keys.** `[CombatDamage] Explodes=` (per-unit), `TiberiumExplosive=yes`, `ExpSpread=.7`,
`TiberiumExplosionDamage=100`.
**Numbers.** `Explodes`-flagged unit + `ExpSpread=.7` cells per 100 damage; `TiberiumExplosive=yes`
amplifies. Guide: blue-loaded harvester bombs are strongest.
**Edge cases.** Works for both factions; a stolen enemy Ref full of blue Tiberium becomes a bomb too.
**Kind.** emergent tactic.
**Sources.** S19, S1.
**Confidence.** med.

### TS-GP-010 Credits, Refund, Repair Costs
**What.** Selling refunds a fraction of cost; repairing costs a fraction of cost over time.
**Data keys.** `[General] RefundPercent=50%`, `RepairPercent=20%`, `RepairRate=.016`, `RepairStep=8`,
`URepairRate=.016`, `IRepairRate=.001`, `IRepairStep=1`, `[AI] CreditReserve=100`.
**Numbers.** Sell refund 50%. Full repair costs 20% of original cost. Building repair 8 HP/tick every
.016 min; unit repair .016 min; infantry 1 HP/.001 min. `[MultiplayerDefaults] Money=10000`.
**Edge cases.** Repair does not begin if cash < CreditReserve (AI) / insufficient funds. Damaged
buildings can be sold for survivors.
**Kind.** economy.
**Sources.** S1, S3.
**Confidence.** high.

---

## 2. CONSTRUCTION & BASE

### TS-GP-011 MCV Deploy / Construction Yard
**What.** The Mobile Construction Vehicle deploys into a Construction Yard, the root of the building
queue; the Yard can redeploy back into an MCV.
**Data keys.** `[MCV] DeploysInto=GACNST`, `Prerequisite=FACTORY,TECH`, `Cost=2500`, `TechLevel=10`;
`[GACNST] Factory=BuildingType`, `UndeploysInto=MCV`, `ConstructionYard=yes`, `Adjacent=2`,
`Capturable=true`, `Cost=2500`, `DeployTime` via MCV.
**Numbers.** MCV cost 2500, strength 1000, speed 3. Yard strength 1000, `Adjacent=2`. `DeployTime`
for MCV/packing; `[General] PlacementDelay=.05`.
**Edge cases.** Losing all Yards with no MCV in production = loss (unless crate `FreeMCV`). Multiple
Yards stack/queue build speed (see TS-GP-019).
**Kind.** building.
**Sources.** S1, S3, S4.
**Confidence.** high.

### TS-GP-012 Placement Adjacency & Bibs
**What.** Buildings must be placed within `Adjacent` cells of an existing `BaseNormal=yes` building;
bibs extend the effective footprint; some structures ignore adjacency.
**Data keys.** `Adjacent` (per building; Yard/Ref/Factory/Tech/Power = 2, walls/pavement = 3–4),
`BaseNormal=no` for defenses/walls/pavement/gates, `Bib=yes` for `PROC`,`GAWEAP`,`NAWEAP`,`NAWAST`,
`DGWEAP`,`DNWEAP`.
**Numbers.** `Adjacent=2` typical; `GAPAVE`/`GAGREEN` `Adjacent=3`; `GASAND`/`GAWALL`/`NAWALL`/gates
`Adjacent=4`; `CABHUT` `Adjacent=0`.
**Edge cases.** Placing on a blocked cell triggers `PlacementDelay=.05` retry. Bib is walkable base
terrain but not a separate object. Enemy buildings block adjacency (cannot build through).
**Kind.** building placement.
**Sources.** S1, S4.
**Confidence.** high.

### TS-GP-013 Walls, Gates, Laser Fence, Firestorm Wall
**What.** Four perimeter systems: cheap `GASAND` Sandbags (light, non-selectable), `GAWALL`/`NAWALL`
concrete walls, faction Gates (`GAGATE_A/B`, `NAGATE_A/B`) that open for own units, Nod Laser Fence
(`NAPOST` posts + auto-spanned `NAFNCE` sections), and GDI Firestorm Wall (`GAFSDF` sections powered
by `GAFIRE`).
**Data keys.** `[GASAND] Strength=250`, `Armor=light`, `Cost=5`, `Repairable=false`;
`[GAWALL] Strength=225`, `Armor=concrete`, `Cost=10`, `Selectable=no`, `GuardRange=5`;
`[GAGATE_A/B] Strength=350`, `Cost=250`, `Gate`; `[NAPOST] Strength=300`, `GuardRange=10`
(max intra-post distance), `Power=-25`; `[NAFNCE] Strength=800`, `Cost=0`, `LegalTarget=false`;
`[GAFSDF] Strength=200`, `Prerequisite=GAFIRE`, `Power=-2`, `Cost=50`;
`[General] WallBuildSpeedCoefficient=.5`, `WallOwner` / `Wall=yes`.
**Numbers.** Sandbags 250 HP, walls 225, gates 350, fence post 300, fence section 800, firestorm
section 200. Wall build speed = 0.5× normal (`WallBuildSpeedCoefficient=.5`). Gate open/close via
`Gate` + `GateCloseDelay`. `GDIGateOne=GAGATE_A`, `GDIGateTwo=GAGATE_B`, `NodGateOne=NAGATE_A`,
`NodGateTwo=NAGATE_B`, `WallTower=GACTWR`.
**Edge cases.** Walls are `Selectable=no`, `Repairable=false`, and cannot be built in some patch
configs; `NodAIBuildsWalls=no`/`AIBuildsWalls=no` by default. Laser fence segments materialise
between posts within `GuardRange=10`. Firestorm wall blocks projectiles while charged
(`ChargeToDrainRatio=.333`).
**Kind.** defense / terrain.
**Sources.** S1, S3, S4.
**Confidence.** high.

### TS-GP-014 Sell, Repair, Refund, Survivors
**What.** Selling a structure refunds 50% and spawns "survivor" infantry based on a fraction of its
cost; selling at the exact moment of destruction spawns more. `CrewEscape` governs vehicle crews.
**Data keys.** `[General] RefundPercent=50%`, `SurvivorRate=.1`, `SurvivorDivisor=100`, `Crew=`,
`CrewEscape=50%`, `Technician=CTECH`, `Engineer=ENGINEER`, `Pilot=E1`; `[IQ] RepairSell=1`,
`SellBack=2`.
**Numbers.** `SurvivorRate=.1`, `SurvivorDivisor=100` → number of survivors scales with building cost.
`CrewEscape=50%`. Per-building survivor counts are listed in S19 (e.g. GDI Refinery sell → 5 Light
Infantry, sell-on-death → 10; Nod Temple → 5 / 10–14).
**Edge cases.** Sell-on-death yields more/stronger survivors than a normal sell. Some buildings yield
none (walls, silos, component tower). `CrewEscape` chance applies to `Crewed=yes` vehicles.
**Kind.** economy / building.
**Sources.** S1, S3, S19.
**Confidence.** high (keys), med (per-building counts).

### TS-GP-015 Engineer Capture
**What.** Engineers enter enemy/civilian `Capturable=true` buildings to capture (or repair friendly)
them.
**Data keys.** `[ENGINEER] Engineer=yes`, `Primary=none`, `Prerequisite=BARRACKS`, `Cost=500`,
`GuardRange=9`; `[General] EngineerCaptureLevel=1.0`, `EngineerDamage=0.0`;
`Capturable=true` on target buildings.
**Numbers.** Engineer cost 500. `EngineerCaptureLevel=1.0` (100% capture in one engineer by default;
CnCNet "Multi Engineer" option raises to 3). `EngineerDamage=0.0` (no damage on capture).
**Edge cases.** Non-capturable buildings (`Capturable=false`): Obelisk of Light, SAM, laser turret,
laser fence, firestorm wall, walls, gates, Core Defender, etc. Capturing an MCV/ConYard gives the
whole tech tree. Engineer can also repair a friendly building to full instantly.
**Kind.** infantry ability.
**Sources.** S1, S3, S17.
**Confidence.** high.

### TS-GP-016 Capturable / Prebuilt / Civilian Structures
**What.** Many map-placed civilian, abandoned, and neutral structures are capturable or provide
services; a few provide bonuses (hospital heals infantry, armory, etc.).
**Data keys.** `Capturable`, `Civilian`, `Hospital`, `Armory`, `Neutral`, `RadarInvisible`,
`LegalTarget`, `Selectable`; `[Houses] 2=Neutral`, `3=Special`; `[Sides] Civilian=Neutral`,
`Mutant=Special`; `[TerrainTypes]` / `[BuildingTypes]` civilian ids 85–148, CA0001–CA0021, ABAN01–18.
**Numbers.** Examples: `CAHOSP` Civilian Hospital 800 HP `concrete`, `PipScale=Ammo`, GDI-owned;
`CAARMR` Armory 800 HP; `CTDAM` Dam 1000 HP `Power=200`; `GASPOT` Light Tower 400 HP `Power=-10`
`Primary=ALARM` `Sensors=yes`; `GAOLDCC3` Old Weapons Factory capturable (800, `Cost=800`);
gap-filler "old" buildings `GAOLDCC1/2/4/5/6` are non-capturable, `Repairable=false`.
**Edge cases.** Civilian/abandoned buildings are `RadarInvisible=yes` and mostly `TechLevel=-1`
(not buildable). `NamedCivilians=no` by default. Neutral house is passive (`MultiplayPassive=true`).
**Kind.** map content / building.
**Sources.** S1, S3, S11.
**Confidence.** high.

---

## 3. PRODUCTION & TECH

### TS-GP-017 Category Queues
**What.** Each factory `Factory=` type owns one queue: `BuildingType` (ConYard), `InfantryType`
(Barracks/Hand), `UnitType` (War Factory), `AircraftType` (Helipad). Sidebar tabs separate
structures/infantry/vehicles/aircraft and (Firestorm) support powers.
**Data keys.** `Factory=BuildingType|InfantryType|UnitType|AircraftType`; `[General] BuildSpeed=.8`,
`BuildupTime=.06`, `[General] MaximumQueuedObjects=25` (FS; original comment says `4`+1 —
see edge cases), `[AI] MultipleFactory` semantics.
**Numbers.** `BuildSpeed=.8` min to produce a 1000-credit item; `BuildupTime=.06` min; queue depth
`MaximumQueuedObjects=25` in the FS rules (original was 4).
**Edge cases.** A unit cannot leave a factory faster than the factory animation (`BuildSpeed` too low
refunds/queues oddly). Parallel factories shorten build time (below).
**Kind.** production.
**Sources.** S1, S3, S4.
**Confidence.** high (keys), med (queue-depth version difference).

### TS-GP-018 Prerequisite System & Category Aliases
**What.** A building/unit lists capitalised building ids OR category aliases; the alias resolves to
*any* building in the alias list. Aliases are declared once in `[General]`.
**Data keys.**
`PrerequisitePower=GAPOWR,NAPOWR,NAAPWR`;
`PrerequisiteFactory=GAWEAP,NAWEAP,DGWEAP,DNWEAP`;
`PrerequisiteGDIFactory=GAWEAP,DGWEAP`;
`PrerequisiteNodFactory=NAWEAP,DNWEAP`;
`PrerequisiteBarracks=NAHAND,GAPILE`;
`PrerequisiteRadar=GARADR,NARADR`;
`PrerequisiteTech=GATECH,NATECH`.
Also `Prerequisite=BARRACKS` (E1/Engineer/etc.), `FACTORY`, `RADAR`, `TECH`, `POWER`.
`NTPYRA` uses its own `Prerequisite=NATECH, NATMPL`.
**Numbers.** No numeric values; resolution is set-based.
**Edge cases.** `Prerequisite=` with an empty value = buildable from the start (some campaign units).
Category aliases must not be deleted or the game can crash (S3/S23). Prerequisite checks are satisfied
by *ownership of the building type*, including captured buildings. `TechLevel` is a second gate
(`-1` = not player-buildable).
**Kind.** tech tree.
**Sources.** S1, S3, S23, S4.
**Confidence.** high.

### TS-GP-019 Multiple-Factory Bonus
**What.** Additional factories of a type speed production of items from that queue; multiple ConYards
speed base building.
**Data keys.** `[General] MultipleFactory=.5`.
**Numbers.** `.5` = half the Red-Alert-style full bonus (`1`=full bonus, `0`=none). Community rule:
two factories speed build; benefit accumulates up to roughly 14 structures, then caps (S17).
**Edge cases.** The CnCNet "Multiple Factory" game option toggles the behaviour; when off, extra
factories still exist but do not contribute speed. `MaximumQueuedObjects=25` limits total parallel
items globally.
**Kind.** production.
**Sources.** S1, S3, S17.
**Confidence.** high (value), low (exact cap count 14).

### TS-GP-020 Factory Exit / Rally
**What.** Produced objects emerge at the factory exit and can be given a rally point.
**Data keys.** `Factory=...`, `DeployTime=.044` (War Factory), `.022` (transports), `RallyPoint`
component (`GATECH`-granted? no — RallyPoint is a component on all factories), `[General]
PlacementDelay=.05`.
**Numbers.** War Factory `DeployTime=.044` min; transports `.022` min.
**Edge cases.** Blocked exit retries per `PlacementDelay`; may refund. Rally points are per-factory.
**Kind.** production.
**Sources.** S1, S4.
**Confidence.** med.

### TS-GP-021 PowersUpBuilding Upgrades
**What.** Add-on structures attach to a host and upgrade it; used for GDI Component Tower weapons,
GDI Power Turbine, GDI Upgrade Center modules, and Nod laser fence posts.
**Data keys.** `PowersUpBuilding=<host id>`, `PowersUpToLevel` (`-1` incremental, positive fixed),
`Upgrades=<n>` on host.
**Numbers / examples.**
`GAVULC` Vulcan Cannon → `gactwr` (150, `Power=-20`);
`GAROCK` RPG Upgrade → `gactwr` (600, `Power=-20`, `TechLevel=9`);
`GACSAM` SAM Upgrade → `gactwr` (300, `Power=-30`, `TechLevel=5`);
`GAPOWRUP` Power Turbine → `gapowr` (100, `Power=+50`, `TechLevel=7`);
`GAPLUG1` Ion Cannon Power Boost → `gaplug` (2500, `Power=-60`);
`GAPLUG2` Seeker Control → `gaplug` (1000, `Power=-50`, `SuperWeapon=HuntSeekSpecial`);
`GAPLUG3` Ion Cannon Uplink → `gaplug` (1500, `Power=-100`, `SuperWeapon=IonCannonSpecial`);
`GAPLUG4` Drop Pod Node → `gaplug` (1000, `Power=-20`, `SuperWeapon=DropPodSpecial`).
**Edge cases.** Component Tower starts empty and must receive a weapon before it can shoot. Upgrade
Center must be built before its four modules. `ThreatPosed` must be 0 for add-ons.
**Kind.** building upgrade.
**Sources.** S1, S3.
**Confidence.** high.

### TS-GP-022 Deploy-to-Produce
**What.** Deployable vehicles (`MCV`, `LPST`, `ICBM`, `TTNK`, `ART2`, `SGEN`, `LIMPET`, `MOBWARG`,
`MOBWARN`, `JUGG`) transform into a building/emplacement (`DeploysInto`), and some transform back
(`UndeploysInto`). Represents the "deployed" state as a separate `BuildingTypes` entry.
**Data keys.** `DeploysInto`, `UndeploysInto`, `DeployTime`, `UndeploysInto`.
**Numbers / pairs.**
`MCV→GACNST`, `LPST→GADPSA`, `ICBM→GAICBM`, `TTNK→GATICK`, `ART2→GAARTY`, `LIMPET→DLIMPET`,
`SGEN→MSTL`, `MOBWARG→DGWEAP`, `MOBWARN→DNWEAP`, `JUGG→DJUGG`; deploy times `.022`–`.044` min.
**Edge cases.** Deployed artillery/tick tank gain armour/HP (`GATICK` 350 `concrete` vs `TTNK` 350
`light`); deployed Juggernaut has longer range; `DeploysInto` buildings are `BaseNormal=no`
(no adjacency). `MOBWARG`/`MOBWARN` have `BuildLimit=1`.
**Kind.** unit↔building.
**Sources.** S1, S3.
**Confidence.** high.

### TS-GP-023 Build Limits, AllowedToStartInMultiplayer, Cameos
**What.** A few unique units have `BuildLimit`; `AllowedToStartInMultiplayer` controls MCV-style
spawn-in; cameo images are defined in `ART.INI` (`Cameo=`/`AltCameo=`) with per-theater variants.
**Data keys.** `BuildLimit=1` (`MHIJACK`, `DGWEAP`, `DNWEAP`, `MOBWARG`, `MOBWARN`),
`AllowedToStartInMultiplayer=no` (`4TNK`, `TRUCKA/B`, `LPST`, `ICBM`, `WEEDGUY`, `MEDIC`, etc.),
`Disableable`, `CrateGoodie`.
**Numbers.** `BuildLimit=1` on the listed uniques; `-1` = unlimited (default).
**Edge cases.** `AllowedToStartInMultiplayer=no` does not prevent building, only pre-placed spawns.
`Disableable=yes` (default) lets MP options remove a unit from the menu.
**Kind.** production metadata.
**Sources.** S1, S4.
**Confidence.** high.

---

## 4. FULL ROSTERS

All values from S1 (`RULES.INI`, Firestorm). Column meanings: Cost in credits; Armor one of
`none < wood < light < heavy < concrete`; Prereq as written (aliases resolved in §3); Weapon/Warhead
from the `[Weapons]` table below; Role from `Category=` + flags. FS = Firestorm-only.
Weapon damage/ROF/range are in §4.7.

### 4.1 Infantry — GDI

| Name | Internal id | Cost | Armor | Prereq | Weapon(s) / Warhead | Role | Notable logic |
|------|-------------|------|-------|--------|--------------------|------|---------------|
| Light Infantry | E1 | 50 | none | BARRACKS | Minigun / SA | Soldier | `Elite=M1Carbine`, `EliteAbilities=SCATTER`, `ImmuneToVeins` |
| Disc Thrower | E2 | 150 | none | GAPILE | Grenade / HE | Soldier | `MovementZone=InfantryDestroyer`, `CollateralDamageCoefficient=.33` |
| Field Medic | MEDIC | 300 | none | GAPILE | Heal / Organic | Support | `SelfHealing=yes`, `GuardRange=8`, `HealScanRadius=10` |
| Jumpjet Infantry | JUMPJET | 400 | light | GAPILE,GARADR | JumpCannon / SA | Soldier/Air | `MovementZone=Fly`, jumpjet locomotor, `EliteAbilities=RADAR_INVISIBLE` |
| Ghost Stalker | GHOST | 1200 | light | GAPILE,GATECH | LtRail / RailShot2 | Elite | `TechLevel=10`, railgun `AmbientDamage=150`, `TiberiumProof` |
| Umagon | UMAGON | 600 | light | GAPILE,GATECH | Sniper / HollowPoint | Elite | campaign character, `TechLevel=8`, `TiberiumProof` |
| GDI Sniper | SLAV | 400 | none | GARADR | Sniper / HollowPoint | Soldier | `EliteAbilities=RADAR_INVISIBLE` |
| Mutant Hijacker | MHIJACK | 1850 | none | NAHAND,NATMPL | none (VehicleThief) | Elite | `BuildLimit=1`, `TechLevel=10`, `GuardRange=6` |
| Engineer | ENGINEER | 500 | none | BARRACKS | none | Support | `Engineer=yes`, capture/repair |

### 4.2 Infantry — Nod

| Name | Internal id | Cost | Armor | Prereq | Weapon(s) / Warhead | Role | Notable logic |
|------|-------------|------|-------|--------|--------------------|------|---------------|
| Light Infantry | E1 | 50 | none | BARRACKS | Minigun / SA | Soldier | shared with GDI |
| Rocket Infantry | E3 | 150 | none | NAHAND | BAZOOKA / AP | Soldier | `MovementZone=InfantryDestroyer` |
| Cyborg | CYBORG | 350 | light | NAHAND | Vulcan3 / SA | Soldier | `TiberiumProof`, `EliteAbilities=STRONGER`, `BerzerkAllowed` (general) |
| Cyborg Commando | CYC2 | 2500 | heavy | NAHAND,NATMPL | CyCannon / PlasmaWH | Elite | `TechLevel=10`, `TiberiumProof`, `ImmuneToVeins` |
| Chameleon Spy | CHAMSPY | 1000 | none | GATECH | none (Disguised/Infiltrate) | Spy | `Sight=14`, `EliteAbilities=SIGHT` |
| Elite Cadre | ELCAD | 300 | light | NAHAND | Vulcan3 / SA | Soldier | campaign, `TiberiumProof` |
| Chem Spray Infantry | CHEMINFANTRY | 400 | none | NAHAND | CHEMBAZOOKA / Gas | Soldier | `Storage=7`, `TiberiumProof`, `TechLevel=5` |
| Chem Spray Infantry (hack) | WEEDGUY | 300 | none | BARRACKS | MultiCluster / HE + DualRockets / AP | Soldier | `Storage=7`, `Elite=MobileEMPulseWeapon`, exists to make Chem/MobileEMP work |
| Mutant Hijacker | MHIJACK | 1850 | none | NAHAND,NATMPL | none (VehicleThief) | Elite | `BuildLimit=1` |
| Engineer | ENGINEER | 500 | none | BARRACKS | none | Support | shared |

### 4.3 Infantry — Special / Mutant / Civilian

| Name | Internal id | Cost | Armor | Owner | Weapon/Warhead | Notable logic |
|------|-------------|------|-------|-------|----------------|---------------|
| Mutant | MUTANT | 100 | none | GDI,Nod | Vulcan / SA | `TiberiumProof`, `TechLevel=-1` |
| Mutant Soldier | MWMN | 100 | none | GDI,Nod | Vulcan / SA | `TechLevel=-1` |
| Mutant Sergeant | MUTANT3 | 100 | none | GDI,Nod | Vulcan / SA | `TechLevel=-1` |
| Tratos | TRATOS | 100 | none | GDI,Nod | none | VIP, `TiberiumProof` |
| Oxanna | OXANNA | 100 | none | GDI,Nod | Vulcan / SA | VIP |
| Tiberian Fiend | DOGGIE | 100 | light | GDI,Nod | FiendShard / Shard | `IsCanine`, `Speed=8`, `TiberiumProof` |
| Technician | CTECH | 10 | none | GDI,Nod | Pistola / SA | `[General] Technician`, 10-round pistol |
| Civilians | CIV1–CIV6 | 10 | none | GDI,Nod | none | `[General] Disguise=E1` |
| Huey (infected cyborg) | HUEY | 650 | light | (none) | Vulcan3 / SA | campaign only |
| Visceroid Baby | VISC_SML | 1 | light | Civilian | none | 200 HP, spawns from Tiberium death |
| Visceroid Adult | VISC_LRG | 1 | heavy | Civilian | SlimeAttack / Slimer | 500 HP, `GuardRange=5` |

### 4.4 Vehicles — GDI

| Name | Internal id | Cost | Armor | Prereq | Weapon(s) / Warhead | Role | Notable logic |
|------|-------------|------|-------|--------|--------------------|------|---------------|
| Harvester | HARV | 1400 | heavy | FACTORY,PROC | none | Support | `Storage=28`, `Dock=PROC`, `SelfHealing` |
| Harvester (unload art) | HORV | 1400 | heavy | — | none | Support | `[General] UnloadingHarvester`, speed 8 |
| MCV | MCV | 2500 | heavy | FACTORY,TECH | none | Support | `DeploysInto=GACNST`, `TechLevel=10` |
| Amphibious APC | APC | 700 | heavy | GDIFACTORY,GAPILE | none | Transport | `Passengers=5`, `SpeedType=Amphibious`, `MovementZone=AmphibiousCrusher` |
| Wolverine | SMECH | 400 | light | GDIFACTORY | AssaultCannon / SA | AFV | walker, `EliteAbilities=VEIN_PROOF`, `ImmuneToVeins` |
| Titan | MMCH | 650 | heavy | GDIFACTORY | 120mm / AP | AFV | walker, `EliteAbilities=SENSORS` |
| Mammoth Mk.II | HMEC | 4000 | heavy | GDIFACTORY,GATECH | MammothTusk / HE + MechRailgun / RailShot | AFV | walker, `SelfHealing`, `TechLevel=10`, passes under bridges issue |
| Mammoth Tank | 4TNK | 1500 | heavy | GAWEAP,GATECH | 120mmx / AP + MammothTusk / HE | AFV | `Passengers=2`, `SelfHealing`, `Crusher=yes`, `AllowedToStartInMultiplayer=no` |
| Hover MLRS | HVR | 700 | wood | GDIFACTORY,GARADR | HoverMissile / AP | AFV | `SpeedType=Hover`, `MovementZone=AmphibiousDestroyer` |
| Disruptor | SONIC | 1400 | heavy | GDIFACTORY,GATECH | SonicZap / SonicWarhead | AFV | `TechLevel=9`, `EliteAbilities=FASTER` |
| Juggernaut (FS) | JUGG | 1000 | light | GDIFACTORY,GARADR | Jugg90mm / ARTYHEX | LRFS | `DeploysInto=DJUGG`, `TechLevel=6` |
| Mobile Sensor Array | LPST | 950 | wood | FACTORY,RADAR | none | Support | `DeploysInto=GADPSA`, `RadarInvisible` |
| Mobile Repair Vehicle | REPAIR | 1000 | light | NODFACTORY | RepairBullet / Mechanical | Support | `GuardRange=8`, `Damage=-50` heal |
| Mobile EMP (FS) | MOBILEMP | 750 | heavy | GDIFACTORY,NAPULS | none | Support | `PipScale=Charge`, morphs to `CMOBILEMP` |
| Mobile EMP charged (FS) | CMOBILEMP | 750 | heavy | — | (EMPulse on deploy) | Support | internal charged form |
| Mobile War Factory (FS) | MOBWARG | 1800 | heavy | GAWEAP,GAPLUG | none | Support | `BuildLimit=1`, `DeploysInto=DGWEAP` |
| Limpet Drone | LIMPET | 550 | none | FACTORY,RADAR | LIMP / LIMPY | AFV | `DeploysInto=DLIMPET`, `SpeedType=Hover` |
| Disruptor / juggernaut deployed forms | GATICK/GAARTY/… | — | — | — | — | — | see structures |
| Carryall-hitched/civilian | BUS, LOCOMOTIVE, TRAINCAR, CARGOCAR, PICK, CAR, WINI | 800 | light | — | none | Transport | map/campaign, `Passengers` 2–25 |

### 4.5 Vehicles — Nod

| Name | Internal id | Cost | Armor | Prereq | Weapon(s) / Warhead | Role | Notable logic |
|------|-------------|------|-------|--------|--------------------|------|---------------|
| Harvester | HARV | 1400 | heavy | FACTORY,PROC | none | Support | shared |
| MCV | MCV | 2500 | heavy | FACTORY,TECH | none | Support | shared |
| Attack Buggy | BGGY | 400 | light | NODFACTORY | RaiderCannon / SA | Recon | `EliteAbilities=CRUSHER`, `ImmuneToVeins` |
| Attack Cycle | BIKE | 500 | wood | NODFACTORY | BikeMissile / AP | Recon | `Speed=12`, `EliteAbilities=VEIN_PROOF` |
| Tick Tank | TTNK | 600 | light | NODFACTORY | 90mm / AP | AFV | `DeploysInto=GATICK`, `EliteAbilities=SENSORS` |
| Subterranean APC | SAPC | 800 | heavy | NODFACTORY,NATECH | none | Transport | `Passengers=5`, `MovementZone=Subterannean` |
| Devil's Tongue | SUBTANK | 850 | light | NODFACTORY,NATECH | FireballLauncher / Fire | AFV | subterranean, `EliteAbilities=SELF_HEAL` |
| Stealth Tank | STNK | 800 | light | NODFACTORY,NATECH | Dragon / AP | AFV | `Cloakable=yes`, `EliteAbilities=EXPLODES`, `Speed=6` |
| Cyborg Reaper (FS) | REAPER | 1200 | light | NATECH,NODFACTORY | QuadLauncher / SA + WebLauncher / WebMass | AFV | `SpeedType=Creep`, `TiberiumProof`, `ImmuneToVeins` |
| Artillery | ART2 | 1000 | light | NODFACTORY,NARADR | 155mm / ARTYHEX | LRFS | `DeploysInto=GAARTY`, `ROT=2`, `EliteAbilities=SELF_HEAL` |
| Nod Heavy Artillery (FS) | ARTY3 | 1000 | light | NODFACTORY | 140mm / AP2 | LRFS | `TechLevel=3`, `Weapon=140mm` |
| Weed Eater | WEED | 1400 | heavy | NODFACTORY,NAWAST | none (harvests weed) | Support | `Dock=NAWAST`, `Storage=7`, `ImmuneToVeins` |
| Mobile Stealth Generator (FS) | SGEN | 1300 | light | NODFACTORY,NASTLH | none | AFV | `DeploysInto=MSTL`, `EliteAbilities=EXPLODES` |
| Fist of Nod (FS) | MOBWARN | 1800 | heavy | NAWEAP,NATMPL | none | Support | `BuildLimit=1`, `DeploysInto=DNWEAP` |
| Mobile Sensor Array / Repair | LPST / REPAIR | — | — | — | — | — | shared (REPAIR is Nod-only) |
| Hunter-Seeker / civilian | GHUNTER/NHUNTER, BUS etc. | — | — | — | — | — | see specials |

### 4.6 Aircraft

| Name | Internal id | Cost | Armor | Prereq | Weapon(s) / Warhead | Role | Notable logic |
|------|-------------|------|-------|--------|--------------------|------|---------------|
| Orca Fighter | ORCA | 1000 | light | GAHPAD | Hellfire / ORCAAP (Burst 2) | AirPower | `Dock=GAHPAD,NAHPAD`, `PipScale=Ammo`, `Speed=20`, `GuardRange=30` |
| Orca Bomber | ORCAB | 1600 | light | GAHPAD,GATECH | Bomb / ORCAHE | AirPower | `EliteAbilities=RADAR_INVISIBLE`, slow |
| Banshee | SCRIN | 1200 | light | NAHPAD,NATECH | Proton / AP | AirPower | `ROT=3`, `EliteAbilities=RADAR_INVISIBLE` |
| Harpy | APACHE | 800 | light | NAHPAD | HarpyClaw / SA | AirPower | `RadarInvisible=yes` |
| Orca Transport | ORCATRAN | 850 | light | GAHPAD | none | Transport | `Passengers=10`, `RadarInvisible=yes` |
| Carryall | TRNSPORT | 750 | light | GAHPAD,GADEPT | none | AirLift | `Carryall` tows vehicles |
| Dropship | DSHP | 3000 | heavy | GAWEAP,GAHPAD,GATECH | none | AirLift | `Passengers=25`, `TechLevel=8` |
| Drop Pod | DPOD | 10 | light | afld | Vulcan2 / SA | AirPower | `Passengers=5`, `Selectable=no` |

### 4.7 Structures — GDI

| Name | Internal id | Cost | HP | Armor | Power | Prereq | Role / Notable logic |
|------|-------------|------|----|-------|-------|--------|---------------------|
| Construction Yard | GACNST | 2500 | 1000 | heavy | 0 | — | `ConstructionYard=yes`, `Factory=BuildingType`, `UndeploysInto=MCV`, capturable |
| Power Plant | GAPOWR | 300 | 750 | wood | +100 | — | `TogglePower=no` |
| Power Turbine | GAPOWRUP | 100 | — | wood | +50 | GAPOWR | `PowersUpBuilding=gapowr`, TechLevel 7 |
| Tiberium Refinery | PROC | 2000 | 900 | heavy | −30 | POWER | `Refinery=yes`, `Storage=80`, `Bib`, free Harvester, capturable |
| Barracks | GAPILE | 300 | 800 | wood | −20 | POWER | `Factory=InfantryType`, capturable |
| War Factory | GAWEAP | 2000 | 1000 | heavy | −30 | PROC,GAPILE | `WeaponsFactory=yes`, `Factory=UnitType`, Bib, capturable |
| Tech Center | GATECH | 1500 | 500 | wood | −200 | GAWEAP,GARADR | unlocks tier-10 tech, `TogglePower=no` |
| Radar | GARADR | 1000 | 1000 | wood | −40 | PROC | `Sensors=yes`, radar minimap |
| Helipad | GAHPAD | 500 | 600 | wood | −10 | GARADR | `Helipad=yes`, `Factory=AircraftType`, `UnitReload=yes` |
| Service Depot | GADEPT | 1200 | 1100 | wood | −30 | FACTORY | `UnitReload=yes`, repairs vehicles, GDI-only |
| Tiberium Silo | GASILO | 150 | 300 | wood | −10 | PROC | `Storage=60`, capturable |
| Component Tower | GACTWR | 200 | 500 | light | −10 | GAPILE | `Sensors=yes`; accepts Vulcan/RPG/SAM upgrades |
| Vulcan Cannon | GAVULC | 150 | — | wood | −20 | GACTWR,GAPILE | `PowersUpBuilding=gactwr`, Primary+Secondary VulcanTower |
| RPG Upgrade | GAROCK | 600 | — | wood | −20 | GACTWR,GAPILE | `PowersUpBuilding=gactwr`, TechLevel 9 |
| SAM Upgrade | GACSAM | 300 | — | wood | −30 | GACTWR,GARADR | `PowersUpBuilding=gactwr`, RedEye2 |
| Upgrade Center | GAPLUG | 1000 | 1000 | wood | −150 | PROC,GATECH | `Sensors=yes`, hosts 4 modules |
| Ion Cannon Power Boost | GAPLUG1 | 2500 | — | wood | −60 | GAPLUG | `PowersUpBuilding=gaplug` |
| Seeker Control | GAPLUG2 | 1000 | — | wood | −50 | GAPLUG,GATECH,GAWEAP | `SuperWeapon=HuntSeekSpecial` |
| Ion Cannon Uplink | GAPLUG3 | 1500 | — | wood | −100 | GAPLUG,GATECH | `SuperWeapon=IonCannonSpecial` |
| Drop Pod Node | GAPLUG4 | 1000 | — | wood | −20 | GAPLUG | `SuperWeapon=DropPodSpecial` |
| Firestorm Generator | GAFIRE | 2000 | 800 | heavy | −200 | GATECH | `SuperWeapon=FirestormSpecial`, TechLevel 9 |
| Firestorm Wall Section | GAFSDF | 50 | 200 | concrete | −2 | GAFIRE | blocks projectiles, `Selectable=no` |
| Concrete Wall | GAWALL | 10 | 225 | concrete | 0 | GAPILE | `Selectable=no`, `Repairable=false` |
| Gate | GAGATE_A/B | 250 | 350 | heavy | 0 | GAPILE | opens for own units |
| Pavement | GAPAVE | 75 | 150 | concrete | 0 | BARRACKS | speeds vehicles, `Selectable=no` |
| Deployed Sensor Array | GADPSA | 950 | 600 | wood | 0 | (LPST) | `SensorArray=yes`, `CloakRadiusInCells=25`, undeploys to LPST |
| Deployed Tick Tank | GATICK | 800 | 350 | concrete | 0 | (TTNK) | `Primary=90mm`, `EliteAbilities=SENSORS` |
| Deployed Artillery | GAARTY | 975 | 300 | light | 0 | (ART2) | `Primary=155mm`, `EliteAbilities=SELF_HEAL` |
| Deployed Juggernaut (FS) | DJUGG | 975 | 400 | light | 0 | (JUGG) | `Primary=Jugg90mm` |
| Deployed ICBM | GAICBM | 2000 | 350 | light | 0 | (ICBM) | `Primary=ICBMChemLauncher` (Nod tech) |
| Mobile War Factory (FS) | DGWEAP | 2000 | 800 | heavy | 0 | (MOBWARG) | `WeaponsFactory=yes`, `BuildLimit=1`, undeploys |
| GDI Kodiak | GAKODK | 1000 | 1500 | heavy | 0 | campaign | `Sensors=yes` |

### 4.8 Structures — Nod

| Name | Internal id | Cost | HP | Armor | Power | Prereq | Role / Notable logic |
|------|-------------|------|----|-------|-------|--------|---------------------|
| Construction Yard | GACNST | 2500 | 1000 | heavy | 0 | — | shared |
| Power Plant | NAPOWR | 300 | 750 | wood | +100 | — | `TogglePower=no` |
| Advanced Power Plant | NAAPWR | 500 | 750 | wood | +200 | NAWEAP | TechLevel 7 |
| Tiberium Refinery | PROC | 2000 | 900 | heavy | −30 | POWER | shared |
| Hand of Nod | NAHAND | 300 | 800 | wood | −20 | POWER | `Factory=InfantryType` |
| War Factory | NAWEAP | 2000 | 1000 | heavy | −30 | PROC,NAHAND | `WeaponsFactory=yes`, Bib |
| Tech Center | NATECH | 1500 | 500 | wood | −100 | NAWEAP,NARADR | tier-10 tech |
| Radar | NARADR | 1000 | 1000 | wood | −40 | PROC | `Sensors=yes` |
| Helipad | NAHPAD | 500 | 600 | wood | −10 | NARADR | `Factory=AircraftType`, `UnitReload` |
| Tiberium Silo | GASILO | 150 | 300 | wood | −10 | PROC | shared |
| Laser Turret | NALASR | 300 | 500 | wood | −40 | NAHAND | `Primary=LaserFire2`, `Turret=yes`, `BaseNormal=no` |
| Sam | NASAM | 500 | 600 | wood | −30 | NARADR | `Primary=RedEye2`, `Turret=yes` |
| Obelisk of Light | NAOBEL | 1500 | 725 | wood | −150 | NATECH | `Primary=LaserFire` (250 dmg), `Capturable=false` |
| Temple of Nod | NATMPL | 2000 | 1000 | wood | −200 | NATECH | `SuperWeapon=HuntSeekSpecial`, `Sensors=yes` |
| Missile Silo | NAMISL | 1300 | 1000 | wood | −50 | NATECH | `SuperWeapon=MultiSpecial`; hosts Chemical missile |
| Tiberium Waste Facility | NAWAST | 1600 | 400 | wood | −40 | NAMISL | `PipScale=Tiberium`, `Bib`, charges chem missile |
| Stealth Generator | NASTLH | 2500 | 600 | wood | −350 | PROC,NATECH | `CloakGenerator=yes`, `CloakRadiusInCells=12`, `Sensors` |
| EMP Cannon | NAPULS | 1000 | 500 | heavy | −150 | Radar | `SuperWeapon=EMPulseSpecial`, `Primary=EMPulseWeapon`, `Owner=Nod,GDI` |
| Laser Fence Post | NAPOST | 200 | 300 | concrete | −25 | NAAPWR | `GuardRange=10` sets fence span, `BaseNormal=no` |
| Laser Fence Section | NAFNCE | 0 | 800 | concrete | 0 | — | auto-spawned, `Selectable=no`, `LegalTarget=false` |
| Concrete Wall | NAWALL | 10 | 225 | concrete | 0 | NAHAND | `Selectable=no` |
| Gate | NAGATE_A/B | 250 | 350 | heavy | 0 | NAHAND | opens for own units |
| Obelisk of Darkness (FS) | AAOB | 1500 | 1000 | concrete | −200 | NTPYRA | `Primary=AALaserFire` (anti-air), campaign |
| Nod Pyramid (FS) | NTPYRA | 1500 | 1500 | heavy | −40 | NATECH,NATMPL | `Prerequisite` for AAOB/ICBM/DEFENDER, campaign |
| Mobile Stealth Generator | MSTL | 1600 | 200 | wood | 0 | (SGEN) | `CloakGenerator=yes`, `CloakRadiusInCells=6`, `UndeploysInto=SGEN` |
| Fist of Nod | DNWEAP | 2000 | 800 | heavy | 0 | (MOBWARN) | `WeaponsFactory=yes`, `BuildLimit=1` |
| ICBM Launcher | ICBM | 1600 | 500 | light | 0 | NTPYRA,NATECH,NAWEAP | `DeploysInto=GAICBM`, campaign |
| NOD Montauk | NAMNTK | 1000 | 1500 | heavy | 0 | — | campaign `Sensors=yes` |
| Core Defender (FS) | DEFENDER | 10000 | 2000 | heavy | 0 | NTPYRA | `Primary=DEFOB` (350×2 dmg), `SelfHealing`, `TiberiumProof` |
| Core Defender deployed (FS) | DDEFD | 10000 | 9999 | concrete | 0 | — | `UndeploysInto=DEFENDER`, `Power=0` |
| CABAL Obelisk (FS) | CROB | 1500 | 1000 | concrete | 0 | — | `Owner=Civilian` (CABAL), `Primary=CABLaser` |

### 4.9 Structures — Shared / Civilian / Map

| Name | Internal id | Cost | HP | Armor | Notes |
|------|-------------|------|----|-------|-------|
| Civilian Hospital | CAHOSP | 800 | 800 | concrete | GDI-owned, `PipScale=Ammo`, heals infantry |
| Armory | CAARMR | 1000 | 800 | concrete | `PipScale=Ammo`, GDI/Nod |
| Bridge repair hut | CABHUT | — | 2000 | — | `RadarInvisible`, `LegalTarget=no`, repairs bridges |
| Radio/broadcast towers | GASPOT | 150 | 400 | wood | `Primary=ALARM`, `Sensors=yes`, `Power=-10` |
| Dam | CTDAM | — | 1000 | heavy | `Power=200`, map objective |
| Scrin Ship | UFO | — | 1000 | heavy | `RadarInvisible`, map prop |
| Ammo Crates | AMMOCRAT | — | 1 | none | explodes for 200 (`AmmoCrateDamage`) |
| Civilian city buildings | CITY01–CITY22 | — | 100–700 | wood/heavy/concrete | `RadarInvisible=yes`, `TechLevel=-1` |
| Abandoned buildings | ABAN01–ABAN18 | — | 300–600 | wood/heavy | `RadarInvisible`; `GAOLDCC3` capturable |
| Billboards | BBOARD01–BBOARD16 | — | 400 | heavy | `Selectable=no` |
| Civilian villas / props | CA0001–CA0021 | — | 100–400 | light/heavy/concrete | `RadarInvisible`, some capturable |
| Crash / pyramid props | CAPYR01–03, CACRSH01–05, CAARAY, CTVEGA | — | 100–400 | concrete | map décor |
| Old structures | GAOLDCC1–6 | — | 400 | heavy | `GAOLDCC3` (Old War Factory) capturable/buildable (800) |
| Terrain overlays | TIB01–20, TIB2_*, TIB3_*, VEINS, VEINHOLE, bridges, crates | — | — | — | `[OverlayTypes]` 1–182 |
| Terrain objects | BOXES, ICE, TREE, TIBTRE, VEINTREE, FONA, rocks | — | — | — | `[TerrainTypes]` |

### 4.10 Defenses & Superweapon Hosts (quick index)

| Faction | Defense / Host | Superweapon / Weapon |
|---------|----------------|----------------------|
| GDI | GAPLUG3 Ion Cannon Uplink | `IonCannonSpecial` |
| GDI | GAPLUG4 Drop Pod Node | `DropPodSpecial` |
| GDI | GAPLUG2 Seeker Control | `HuntSeekSpecial` |
| GDI | GAFIRE Firestorm Generator | `FirestormSpecial` (+GAFSDF walls) |
| Nod | NAMISL Missile Silo | `MultiSpecial` + Chemical missile |
| Nod | NATMPL Temple of Nod | `HuntSeekSpecial` |
| Nod | NAPULS EMP Cannon | `EMPulseSpecial` |
| Nod | NAOBEL / AAOB Obelisk(s) | LaserFire / AALaserFire |
| Nod | NASTLH / MSTL Stealth Generator | cloak field |
| Both | GACTWR Component Tower | Vulcan/RPG/SAM upgrades |
| Both | NALASR / NASAM / NAPOST+NAFNCE | laser / SAM / laser fence |

---

## 5. MOVEMENT

### TS-GP-024 Locomotion Table
**What.** Each `VehicleTypes`/`InfantryTypes` entry binds a `Locomotor` CLSID that selects the motion
engine (tracked, wheeled, walker, hover, subterranean, infantry, jumpjet, aircraft, drop pod, floater).
**Data keys.** `Locomotor={GUID}`, `Speed=`, `ROT=`, `SpeedType=` (`Hover`,`Amphibious`,`Creep`,
`Tracked`/`Wheeled` implied), `MovementZone=`, `Weight=`, `Crusher=`.
**Numbers / CLSID map.**

| Locomotor GUID | Used by | Motion |
|----------------|---------|--------|
| `{4A582741-9839-11d1-B709-00A024DDAFD1}` | most tracked/wheeled vehicles (MCV, HARV, APC, 4TNK, BIKE, STNK, ART2, HMEC? no) | ground (tracked/wheeled) |
| `{4A582742-9839-11d1-B709-00A024DDAFD1}` | HVR, LIMPET | hover |
| `{4A582743-9839-11d1-B709-00A024DDAFD1}` | SAPC, SUBTANK | subterranean |
| `{4A582744-9839-11d1-B709-00A024DDAFD1}` | all infantry | infantry |
| `{4A582745-9839-11d1-B709-00A024DDAFD1}` | DPOD | drop pod |
| `{4A582746-9839-11d1-B709-00A024DDAFD1}` | ORCA, ORCAB, SCRIN, APACHE, TRNSPORT, DSHP, GHUNTER, NHUNTER | aircraft |
| `{55D141B8-DB94-11d1-AC98-006008055BB5}` | MMCH, HMEC, SMECH, JUGG, DEFENDER | walker/mech |
| `{92612C46-F71F-11d1-AC9F-006008055BB5}` | JUMPJET | jumpjet |
| `{3DC0B295-6546-11D3-80B0-00902792494C}` | JFISH | floater |
| `{4A582740-...}` (implied statue) | buildings | static |

**Edge cases.** Giving a jumpjet locomotor to a mech/ground unit crashes the game (S3).
`SpeedType` is what actually gates terrain passability (`LandTypes`).
**Kind.** data / movement.
**Sources.** S1, S3, S5.
**Confidence.** high (guid usage), med (semantic labels).

### TS-GP-025 Movement Zones
**What.** `MovementZone` constrains pathfinding passability and obstacle-crushing.
**Data keys.** `MovementZone` on all TechnoTypes; default `Normal`.
**Numbers / model (S5).**

| MovementZone | Passable | Crushes | Notes |
|--------------|----------|---------|-------|
| None | none | — | stationary |
| Normal | clear ground | infantry | can destroy terrain obstacles (trees) |
| Crusher | clear ground | infantry (unarmed) | used by harvester/repair/artillery |
| Destroyer | ground | infantry + terrain | tanks |
| AmphibiousDestroyer | ground+water | infantry + terrain | HVR, LIMPET, JFISH |
| AmphibiousCrusher | ground+water | infantry | APC |
| Amphibious | ground+water | no | only zone that docks both naval & land repair |
| Subterannean (sic) | clear ground + digs | per sub | SAPC, SUBTANK; needs `AllowBurrowing` tiles |
| Infantry | clear ground | no | all infantry |
| InfantryDestroyer | clear ground | terrain (trees) | Disc/Rocket infantry |
| Fly | everything | — | aircraft & jumpjets |
| Water / WaterBeach | water (+beach) | — | RA2 mostly |
| CrusherAll (YR) | clear ground | all mobile + walls | RA2/YR only |

**Edge cases.** Misspelling `Subterannean` is canonical. `MovementZone=Fly` prevents manual entry into
buildings. Subterranean units only dig if origin and target allow `AllowBurrowing` (tileset flag);
`Crusher` zone + sub locomotor needs ≥11 clear tiles between start and destination.
**Kind.** movement.
**Sources.** S5, S1, S9.
**Confidence.** high (TS-relevant rows), med (details).

### TS-GP-026 Tunnel Network / Subterranean
**What.** Nod subterranean units (`SAPC`, `SUBTANK`) dig under the map, emerging at the target.
**Data keys.** `MovementZone=Subterannean`, `Locomotor={4A582743-...}`,
`[General] TunnelSpeed=1`, `AllowShroudedSubteranneanMoves=true`, `CloakDelay=.02`,
`[TileSets] AllowBurrowing=`.
**Numbers.** `TunnelSpeed=1`; `AllowShroudedSubteranneanMoves=true` allows digging to shrouded cells.
**Edge cases.** Cannot dig where the tileset disallows burrowing; surfaced subs must wait `CloakDelay`.
Veins damage surface units but sub units are `ImmuneToVeins`.
**Kind.** movement.
**Sources.** S1, S5, S3.
**Confidence.** high (keys), med (tile constraint).

### TS-GP-027 Amphibious / Hover
**What.** Amphibious and hover units cross water. `SpeedType=Hover`/`Amphibious` selects the terrain
class; `MovementZone=Amphibious*` allows water in pathfinding. Hover units bob and get a straight-line
speed boost.
**Data keys.** `[General] HoverHeight=120`, `HoverDampen=40%`, `HoverBob=.04`, `HoverBoost=150%`,
`HoverAcceleration=.02`, `HoverBrake=.03`.
**Numbers.** Hover height 120 lepton; boost +150% on straights; bob every .04 s.
**Edge cases.** Hover cannot be crushed by tanks normally; `TooBigToFitUnderBridge=true` on HVR.
**Kind.** movement.
**Sources.** S1, S3.
**Confidence.** high.

### TS-GP-028 Aircraft Behaviour
**What.** Aircraft fly at a fixed flight level, must return to a Helipad to rearm/refuel (ammo pips),
and can be given guard ranges. Carryall can pick up vehicles; Dropship is a large transport.
**Data keys.** `[General] FlightLevel=600`, `PitchSpeed`, `PitchAngle`, `RollAngle`,
`AttackingAircraftSightRange=6`, `AircraftFogReveal=6`, `CurleyShuffle=yes`, `PadAircraft=ORCA,ORCAB`,
`ReloadRate=.5`, `SeparateAircraft=yes` (unused), `GuardRange=30`, `PipScale=Ammo`, `Dock=GAHPAD,...`.
**Numbers.** Flight level 600 (bridges 300–500); `ReloadRate=.5` min per ammo point; aircraft fog
reveal 6; guard range 30.
**Edge cases.** `CurleyShuffle` helis reposition between shots; if off, shots can hit terrain.
`MovementZone=Fly` aircraft cannot be ordered into buildings. Aircraft do not reveal fog beyond
`AircraftFogReveal` even though they can see/shoot further.
**Kind.** movement / combat.
**Sources.** S1, S3.
**Confidence.** high.

### TS-GP-029 Jumpjet Flight
**What.** `JUMPJET` infantry use a dedicated jumpjet control block, flying at cruise height and
wobbling.
**Data keys.** `[JumpjetControls] TurnRate=4`, `Speed=14`, `Climb=5`, `CruiseHeight=500`,
`Acceleration=2`, `WobblesPerSecond=.15`, `WobbleDeviation=40`, `CloakDetectionRadius=3`.
**Numbers.** Cruise height 500, speed 14, climb 5, wobble 40.
**Edge cases.** Set cruise height above bridges or the jump cannon may lack range to hit.
`MovementZone=Fly` but not treated as aircraft.
**Kind.** movement.
**Sources.** S1, S3.
**Confidence.** high.

---

## 6. VISION / FOG

### TS-GP-030 Radar & Minimap
**What.** Radar is granted by a Radar structure (`Sensors=yes`); the minimap shows terrain, unit blips,
and radar events. Losing the radar building disables it (unless a ConYard/other provider exists).
**Data keys.** `Sensors=yes` (on GARADR/NARADR/NASTLH/GAPLUG/NAPULS/NATMPL/GASPOT/GADPSA...),
`RadarVisible`/`RadarInvisible` (per object), `[AudioVisual] RadarOn=COMMUP1`, `RadarOff=RADARDN1`.
**Numbers.** None (boolean).
**Edge cases.** `RadarInvisible=yes` objects never show on minimap (civilian buildings, MCV? no —
MCV shows). Infantry are `RadarVisible=no` by default (S1 comment).
**Kind.** vision / UI.
**Sources.** S1, S4.
**Confidence.** high.

### TS-GP-031 Radar Events
**What.** Six event types drive minimap flashes: (1) Generic Combat, (2) Generic Noncombat,
(3) Dropzone, (4) Base Under Attack, (5) Harvester Under Attack, (6) Enemy Object Sensed.
**Data keys.** `RadarEventSuppressionDistances=8,8,8,8,8,6`,
`RadarEventVisibilityDurations=200,200,200,200,200,200`,
`RadarEventDurations=400,400,400,400,400,400`, `FlashFrameTime=7`, `RadarCombatFlashTime=49`,
`RadarEventMinRadius=8`, `RadarEventSpeed=1.2`, `RadarEventRotationSpeed=.05`,
`RadarEventColorSpeed=.1`, `RevealTriggerRadius=9`.
**Numbers.** Visibility 200 frames, duration 400 frames, suppression 8 cells (6 for sensed), flash
frame time 7, combat flash 49 (must be an odd multiple of 7).
**Edge cases.** `RadarCombatFlashTime` must be an odd multiple of `FlashFrameTime` or visuals desync.
**Kind.** vision / UI.
**Sources.** S1, S3.
**Confidence.** high.

### TS-GP-032 Cloak / Stealth Generator / Sensors
**What.** Units with `Cloakable=yes` (Stealth Tank) cloak; buildings with `CloakGenerator=yes`
(NASTLH/MSTL) cloak nearby friendlies within a radius; `Sensors=yes` units/buildings detect cloaked
objects; sensor arrays reveal a radius.
**Data keys.** `Cloakable`, `CloakStop`, `CloakGenerator`, `CloakRadiusInCells`, `Sensors`,
`SensorArray`, `RadarInvisible`, `[General] CloakingStages=9`, `CloakDelay=.02`,
`[JumpjetControls] CloakDetectionRadius=3`.
**Numbers.** `NASTLH CloakRadiusInCells=12`; `MSTL CloakRadiusInCells=6`; `GADPSA` sensor
`CloakRadiusInCells=25`; `CloakingStages=9`.
**Edge cases.** Mobile Sensor Array (`LPST`) is `RadarInvisible` itself. Sensors detect but do not
necessarily let the detector target. Enemy cloaked units still trigger "Enemy Object Sensed" radar
event at 6-cell suppression.
**Kind.** vision / stealth.
**Sources.** S1, S3, S4.
**Confidence.** high.

### TS-GP-033 Reveal Mechanics
**What.** Shroud (never-seen) and fog (seen-but-not-currently-visible) are per-player; units reveal
sight radius; triggers can reveal around waypoints; aircraft reveal a fixed radius.
**Data keys.** `[General] FogOfWar=no` (default), `ShroudGrow=no`, `ShroudRate=4`, `FogRate=.5`,
`AttackingAircraftSightRange=6`, `AircraftFogReveal=6`, `RevealTriggerRadius=9`,
`[AudioVisual] AllyReveal=yes`, `[MultiplayerDefaults] ShadowGrow=no`.
**Numbers.** Aircraft fog reveal 6; reveal-trigger radius 9 (10 max); shroud creep 4 min; fog creep
.5 min; `AllyReveal=yes` shares radar with allies.
**Edge cases.** Fog is a menu/multiplayer option (`FogOfWar`), shroud is always present. "Cover
entire map" crate resets shroud. `ShroudGrow=no` by default (shroud does not regrow).
**Kind.** vision.
**Sources.** S1, S4, S11.
**Confidence.** high.

---

## 7. SPECIAL SYSTEMS

### TS-GP-034 Superweapons & Support Powers
**What.** Seven superweapon types exist (`[SuperWeaponTypes]`); hosted by specific buildings and
charged over time or by resource. `[SpecialWeapons]` defines cross-references.
**Data keys.** `[SuperWeaponTypes] 1=MultiSpecial 2=EMPulseSpecial 3=FirestormSpecial 4=IonCannonSpecial
5=HuntSeekSpecial 6=ChemicalSpecial 7=DropPodSpecial`; `SuperWeapon=` on hosts;
`[SpecialWeapons] HSBuilding=GAPLUG,NATMPL; NukeWarhead=Nuke; NukeDown=NukeDown; NukeProjectile=NukeUp;
EMPulseWarhead=EMPuls; EMPulseProjectile=PulsPr`.
**Numbers / table.**

| Power | Host | Internal id | Effect / weapon | Charge | Notes |
|-------|------|-------------|-----------------|--------|-------|
| Ion Cannon | GAPLUG3 | IonCannonSpecial | `[CombatDamage] IonCannonDamage=751`, `IonCannonWarhead=IonCannonWH` | 9 min (commented `IonCannon=9`); S13/S20 quote 10:00 | full damage to all armour; splash halves per 40 px; deforms terrain |
| Multi Missile | NAMISL | MultiSpecial | `MultiLauncher` Damage 130 HE, Range 30 | ~10:00 (S12) | silo stores up to 3, up to 2 usable; one launch at a time |
| Chemical Missile | NAMISL (+NAWAST) | ChemicalSpecial | `ChemLauncher` Damage 100 / Gas, Range 6 | resource: `WeedCapacity=56` weed bails | requires Weed Eater + Waste Facility + Veinhole |
| Hunter-Seeker | NATMPL / GAPLUG2 | HuntSeekSpecial | spawns `GHUNTER`/`NHUNTER` | — | `SuicideBomb` 11000 SUPER; seek params in §TS-GP-035 |
| Firestorm | GAFIRE | FirestormSpecial | `FirestormWarhead=FirestormWH`; `ChargeToDrainRatio=.333`; `DamageToFirestormDamageCoefficient=.1` | charge via building | blocks projectiles; maps use `GAFSDF` sections |
| EMP | NAPULS | EMPulseSpecial | `EMPulseWeapon` Damage 1200 (duration), Range 40, `EMPuls` | — | lobbed; also Mobile EMP |
| Drop Pod | GAPLUG4 | DropPodSpecial | `DropPodWeapon=DropGun`, infantry 12–15 | 6:00 (S20) | `DropPodHeight=2000`, `DropPodSpeed=75`, `DropPodAngle=0.79` |

**Edge cases.** Building multiple hosts does not charge faster in vanilla (S20/PPM); only one charge
instance per superweapon. AI targeting values exist (`AIIonCannon*Value`). Superweapons require power.
Nuke (`NukeWarhead=Nuke`) exists in `[SpecialWeapons]` but is not part of the TS skirmish superweapon
set (it is a Temple/nuke legacy; low confidence for TS use).
**Kind.** superweapon.
**Sources.** S1, S3, S12, S13, S15, S20.
**Confidence.** high (ids/values), med (charge times), low (Nuke in TS).

### TS-GP-035 Hunter-Seeker Controls
**Data keys.** `HunterSeekerDetonateProximity=150`, `HunterSeekerDescendProximity=700`,
`HunterSeekerAscentSpeed=40`, `HunterSeekerDescentSpeed=50`, `HunterSeekerEmergeSpeed=6`.
**Numbers.** as listed. GHUNTER/NHUNTER Speed 25, Strength 500, `Selectable=false`, `SuicideBomb`
Damage 11000 / SUPER.
**Kind.** superweapon.
**Sources.** S1, S3.
**Confidence.** high.

### TS-GP-036 Engineers
Covered in TS-GP-015. Captures `Capturable=true` structures; `EngineerCaptureLevel=1.0`,
`EngineerDamage=0.0`; CnCNet "Multi Engineer" makes it 3.
**Sources.** S1, S17. **Confidence.** high.

### TS-GP-037 CABAL
**What.** CABAL is the Firestorm antagonist faction; it reuses Nod assets plus unique structures/units
(CABAL Core `CORE`, CABAL Obelisk `CROB`, Obelisk of Darkness `AAOB`, Core Defender `DEFENDER`/`DDEFD`,
Cyborg Reaper `REAPER`). CABAL cannot be played in skirmish without modding.
**Data keys.** `[Houses]` has no CABAL entry — CABAL is implemented via special houses/map triggers;
`[BuildingTypes] CORE`, `CROB` (`Owner=Civilian`), `AAOB`, `DEFENDER`, `DDEFD`;
`[VehicleTypes] REAPER`.
**Numbers.** CORE 3000 HP concrete; CROB 1000 HP; AAOB 1000 HP (−200 power); DEFENDER 2000 HP
`Primary=DEFOB` 350×2; DDEFD 9999 HP.
**Edge cases.** CABAL AI voices exist (`e01vox02.mix`), `SmartAI`. Campaign only.
**Kind.** faction / campaign.
**Sources.** S1, S18, S14.
**Confidence.** high (entities), med (house implementation).

### TS-GP-038 Veinhole Monster
Covered in TS-GP-007. `VeinholeTypeClass=VEINTREE`; strength in `[VEINTREE]`; veins damage 5 per
crossing; growth 300 / shrink 100 / max 2000; Nod can weaponise veins into the Chemical Missile.
**Sources.** S1, S3. **Confidence.** high.

### TS-GP-039 Visceroids / Mutants
**What.** Visceroids spawn when infantry die on Tiberium (`TiberiumTransmogrify=40`), or randomly if
`Visceroids=yes`; two small visceroids merge into a large one.
**Data keys.** `[General] Visceroids=no`, `TiberiumTransmogrify=40`, `SmallVisceroid=VISC_SML`,
`LargeVisceroid=VISC_LRG`.
**Numbers.** Transmogrify chance 40%. `VISC_SML` 200 HP light; `VISC_LRG` 500 HP heavy,
`Primary=SlimeAttack` (100 / Slimer), `GuardRange=5`.
**Edge cases.** `Special` house (Mutant) owns mutants; neutral visceroids attack anyone.
`Attack Neutral Units` CnCNet option auto-attacks them.
**Kind.** world creature.
**Sources.** S1, S3, S17.
**Confidence.** high.

### TS-GP-040 Ion Storms
**What.** Map/global weather event: lightning strikes random cells/objects, darkens map, disables some
aircraft and radar-like effects.
**Data keys.** `IonLightningFrequency=10`, `IonLightningRandomness=90`, `IonLightningDamage=500`,
`IonStormDuration=120`, `IonStormWarning=31`, `IonStorms=no`, `IonStormWarhead=IonWH`.
**Numbers.** Lightning frequency 10%/frame, randomness 90%, damage 500, duration 120 s, warning 31 s.
**Edge cases.** Must also be enabled on the map (`IonStorms` in `[Basic]`) to occur. LightningSound was
disabled as "too annoying".
**Kind.** world event / superweapon.
**Sources.** S1, S3.
**Confidence.** high.

### TS-GP-041 Meteorites
**What.** Random Tiberium meteor strikes that crater terrain and seed Tiberium.
**Data keys.** `[General] Meteorites=no`, `CraterLevel=1` (0–4), `[CombatDamage] MeteorWH`,
`Craters=CR1..CR6`, `Crater01..12` smudges.
**Numbers.** `CraterLevel=1` default; must also be enabled on map.
**Edge cases.** Map-only in practice.
**Kind.** world event.
**Sources.** S1, S3.
**Confidence.** med.

### TS-GP-042 Combat & Damage Rules
**What.** Global damage resolution constants and per-actor explosion behaviour.
**Data keys.** `[CombatDamage] IonCannonDamage=751`, `AtomDamage=1000`, `BallisticScatter=2.0`,
`BridgeStrength=1500`, `C4Delay=.03`, `C4Warhead=HE`, `FirestormWarhead=FirestormWH`,
`IonCannonWarhead=IonCannonWH`, `VeinholeWarhead=VeinholeWH`, `Crush=1.8`, `ExpSpread=.7`,
`FireSupress=1`, `FlameDamage=Fire`, `HomingScatter=2.0`, `MaxDamage=1000`, `MinDamage=1`,
`PlayerAutoCrush=no`, `PlayerReturnFire=no`, `PlayerScatter=no`, `ProneDamage` (disabled),
`TreeTargeting=no`, `TurboBoost=1.5`, `Incoming=10`, `CollapseChance=100`, `BerzerkAllowed=no`,
`HarvesterImmune=no`, `DestroyableBridges=yes`, `TiberiumExplosive=yes`.
**Numbers.** see above; `MaxDamage=1000` cap after modifiers, `MinDamage=1`; `TurboBoost=1.5` AA.
**Edge cases.** `[Armor]`/warhead `Verses` table is hardcoded in TS (unlike RA2) — not ini-exposed.
**Kind.** combat.
**Sources.** S1, S3, S10.
**Confidence.** high (keys), low (hardcoded verses).

---

## 8. SKIRMISH AI

### TS-GP-043 `[AI]` Build-Ratio Model
**What.** Legacy RA-derived base composition model. Ratios are of the AI base's building count; the
ratio totals exceed 100% so the AI keeps trying to grow.
**Data keys / numbers (S1).**

| Key | Value | Meaning |
|-----|-------|---------|
| BuildConst | GACNST | construction yard |
| BuildPower | NAPOWR,GAPOWR,NAAPWR | power providers |
| BuildRefinery | PROC | refinery ratio base |
| BuildBarracks | NAHAND,GAPILE | barracks base |
| BuildTech | NATECH,GATECH | tech base |
| BuildWeapons | GAWEAP,NAWEAP | war factory base |
| BuildDefense / BuildPDefense | NAOBEL | defenses |
| BuildAA | NASAM | anti-air |
| BuildHelipad / BuildRadar | GAHPAD,NAHPAD / GARADR,NARADR | air / radar |
| ConcreteWalls / NSGates / EWGates | GAWALL,NAWALL / NAGATE_B,GAGATE_B / NAGATE_A,GAGATE_A | walls/gates |
| GDIWallDefense / GDIWallDefenseCoefficient | 6 / 3 | GDI wall weighting |
| NodBaseDefenseCoefficient / GDIBaseDefenseCoefficient | 1.2 / 1.5 | defense multipliers |
| MaximumBaseDefenseValue | 60 | cap |
| ComputerBaseDefenseResponse | 3 | over-response to base attack |
| AttackInterval / AttackDelay | 3 / 5 | min between attacks / before first attack |
| PatrolScan | .016 | scan interval |
| CreditReserve | 100 | repair floor |
| TiberiumNearScan / TiberiumFarScan | 6 / 48 | harvester scans |
| AutocreateTime | 5 | min between autocreate teams |
| InfantryReserve / InfantryBaseMult | 3000 / 1 | infantry spam floor |
| PowerSurplus | 50 | target surplus |
| BaseSizeAdd | 3 | base size vs largest human |
| RefineryRatio / RefineryLimit | .16 / 4 | |
| BarracksRatio / BarracksLimit | .16 / 2 | |
| WarRatio / WarLimit | .1 / 2 | |
| DefenseRatio / DefenseLimit | .4 / 40 | |
| AARatio / AALimit | .14 / 10 | |
| TeslaRatio / TeslaLimit | .16 / 10 | (unused in TS) |
| HelipadRatio / HelipadLimit | .12 / 5 | |
| AirstripRatio / AirstripLimit | .12 / 5 | (unused in TS) |
| CompEasyBonus | no | AI drops to easy with >1 human |
| Paranoid | yes | AI allies when losing |
| PowerEmergency | 75% | sell buildings below this power |
| AIBaseSpacing | 1 | base building spacing |

Other global AI constants: `TeamDelays=2250,2700,3600`, `AIHateDelays=5400,4500,4050`,
`AIAlternateProductionCreditCutoff=3000`, `MultiplayerAICM=250,200,100`,
`FillEarliestTeamProbability=100,80,60`, `MinimumAIDefensiveTeams=4,3,2`,
`MaximumAIDefensiveTeams=6,5,4`, `TotalAITeamCap=14,12,10`, `UseMinDefenseRule=yes`,
`DissolveUnfilledTeamDelay=9000`, `MinProductionSpeed=.5`, `BaseBias=2`, `BaseDefenseDelay=.25`,
`Stray=2.0`, `SuspendDelay=2`, `SuspendPriority=1`, `AITriggerSuccessWeightDelta=5`,
`AITriggerFailureWeightDelta=-5`, `AITriggerTrackRecordCoefficient=1`,
`MyEffectivenessCoefficientDefault=200`, `TargetEffectivenessCoefficientDefault=-200`,
`TargetSpecialThreatCoefficientDefault=200`, `TargetStrengthCoefficientDefault=-200`,
`TargetDistanceCoefficientDefault=-10`, `Dumb*Coefficient` set, `EnemyHouseThreatBonus=400`.
**Kind.** AI.
**Sources.** S1, S3.
**Confidence.** high.

### TS-GP-044 `[IQ]` Autonomy Model
**What.** Each house has an IQ (0 for human, 1+ for AI; max in skirmish/MP). Each subsystem has a
minimum IQ at which the AI performs it autonomously.
**Data keys / numbers.** `MaxIQLevels=5`, `SuperWeapons=4`, `Production=5`, `GuardArea=2`,
`RepairSell=1`, `AutoCrush=2`, `Scatter=2`, `ContentScan=3`, `Aircraft=3`, `Harvester=2`, `SellBack=2`.
**Edge cases.** A human given a non-zero IQ will "do its own thing" (auto-build/sell/fire), so do not
raise human IQ. AI IQs are capped at max in skirmish.
**Kind.** AI.
**Sources.** S1.
**Confidence.** high.

### TS-GP-045 Difficulty Settings
**What.** Three difficulties (`[Easy]`, `[Normal]`, `[Difficult]`) apply global multipliers; Firestorm
also exposes 5-step "FineDiffControl" (no gameplay effect).
**Data keys / numbers.**

| Key | Easy | Normal | Difficult |
|-----|------|--------|-----------|
| Groundspeed | 1.0 | 1.0 | 1.0 |
| Airspeed | 1.0 | 1.0 | 1.0 |
| BuildTime | .8 | 1 | 1.0 |
| Armor | 1.2 | 1.0 | .8 |
| ROF | .8 | 1.0 | 1.2 |
| Cost | 1.0 | 1.0 | 1.0 |
| RepairDelay | .02 | .02 | .05 |
| BuildDelay | — | .03 | .1 |
| BuildSlowdown | — | yes | yes |
| DestroyWalls | yes | yes | no |
| ContentScan | yes | yes | (default) |

**Edge cases.** `CompEasyBonus=no` means the AI does not auto-demote when a second human joins.
Team/hate delays are ordered hardest→easiest (`TeamDelays=2250,2700,3600` = first value hardest).
**Kind.** AI / meta.
**Sources.** S1, S3.
**Confidence.** high.

### TS-GP-046 AI Scripting (`AI.INI`)
**What.** The scripted AI is defined in `ai.ini` (called `aifs.ini` when Firestorm is installed,
per S16). Four coupled sections:
`[TaskForces]` (group of unit types + counts),
`[ScriptTypes]` (ordered `ScriptActions` with arguments; `ScriptTypes/ScriptActions` doc lists
ops like Attack Quarry, Guard, Move, Load/Unload, Deploy, Capture, etc.),
`[TeamTypes]` (TaskForce + Script + flags: house, sides, priority, max, group, reinforce,
veteran, waypoint, transport, etc.),
`[AITriggerTypes]` (condition → TeamType, with weights and difficulty gating).
**Data keys.** `[AITriggerTypes]` row format (S7):
`ID=Name,Team1,OwnerHouse,TechLevel,ConditionType,ConditionObject,Comparator,StartingWeight,MinimumWeight,MaximumWeight,IsForSkirmish,unused,Side,IsBaseDefense,Team2,EnabledInE,EnabledInM,EnabledInH`.
Condition types: -1 none; 0 enemy owns ?; 1 owner owns ?; 2 enemy low power (yellow); 3 enemy low
power (red); 4 enemy credits; 5/6 RA2 minor super ready; 7 neutral owns ?. Comparator is a 64-hex
string: octet 0 = value, octet 1 = operator (0 `<`, 1 `<=`, 2 `=`, 3 `>=`, 4 `>`, 5 `!=`),
remaining octets unused. `Side` in TS = `ActsLike`+1.
**Numbers.** Example comparators: `0400000003000000` = enemy has ≥4 refineries;
`0300000001000000` = own shock troopers ≤3; `8813000003000000` = enemy ≥5000 credits.
Weight 0 disables a trigger; weight 5000 (RA2) is fire-immediately.
**Edge cases.** Attack triggers rarely "succeed" because `0 Attack...` only completes when *all*
matching targets die, so trigger weights decay to minimum — a known Westwood design flaw. Global
triggers (`-G` suffix) live in ai.ini; map-local triggers need `[AITriggerTypesEnable]`.
`[Basic] IgnoreGlobalAITriggers=` cancels all global triggers.
**Kind.** AI data.
**Sources.** S7, S16, S21, S23, S1.
**Confidence.** high (format), med (ops list, since S21 is a partial index).

---

## 9. MULTIPLAYER / META

### TS-GP-047 `[MultiplayerDefaults]`
**Data keys / numbers (S1).** `Money=10000`, `MaxMoney=10000`, `ShadowGrow=no`, `Bases=yes`,
`TiberiumGrows=yes`, `Crates=yes`, `CaptureTheFlag=no` (crash-prone, unused),
`ThreatEvaluation=no`, `ThreatAssessment=no`.
**Edge cases.** `CaptureTheFlag=yes` is documented to crash when entering an enemy base. `Bases=no`
disables base building entirely. AI threat evaluation toggles are exposed here.
**Kind.** meta.
**Sources.** S1, S3.
**Confidence.** high.

### TS-GP-048 Multiplayer Options & Modes (CnCNet patched client)
**What.** The community client exposes options beyond the vanilla `[MultiplayerDefaults]`.
**Options (S17).** Firestorm Game; Multiple Factory; Short Game (units self-destruct when a player
loses all buildings); Multi Engineer (3 engineers to capture); Aimable SAMs (manual AA targeting);
Integrate Mumble (voice); Attack Neutral Units (auto-attack mutants/visceroids). Video/rendering
options: Default, DxWnd, DirectDraw emulation, IE-DDraw, TS-DDraw; Game Options: Drag Distance,
Disable Edge Scrolling.
**Kind.** meta / client.
**Sources.** S17.
**Confidence.** med (community client, not vanilla).

### TS-GP-049 Player Count, Colors, Houses
**Data keys / numbers.** `[Maximums] Players=8` (IPX layer limits to 8);
`[Houses] 0=GDI 1=Nod 2=Neutral 3=Special`; `[Sides] GDI=GDI Nod=Nod Civilian=Neutral Mutant=Special`;
`[GDI] Color=Gold Suffix=GDI Prefix=G`, `[Nod] Color=DarkRed Prefix=B`;
`[Colors]` ~50 named H/S/V triples (LightGold=34,128,255 … Black=0,100,0).
**Edge cases.** New houses must be appended after GDI/Nod; removing prerequisite aliases or core
houses can crash the game (S3). `SmartAI=yes` on Nod/Special/Neutral.
**Kind.** meta / data.
**Sources.** S1, S3.
**Confidence.** high.

---

## 10. DATA ARCHITECTURE

### TS-GP-050 INI Files
**What.** TS is entirely INI-driven. Core files: `rules.ini` (gameplay), `art.ini` (visuals/anim),
`ai.ini` (scripted AI; `aifs.ini` with Firestorm per S16), and language files `langrule.ini` /
`langfs.ini` (S4). The shipped rules are compiled into `tibsun.mix > local.mix`; mods drop
`rules.ini`/`art.ini`/`ai.ini` next to the exe to override (S23).
**Data keys.** See §1–§9 for the full section catalogue.
**Edge cases.** Editors that "compile" INIs strip comments, breaking hand-editing (S3). `[General]
Name=` identifies the active ruleset when multiple are present.
**Kind.** architecture.
**Sources.** S1, S4, S23.
**Confidence.** high.

### TS-GP-051 `rules.ini` Section Catalogue
`[General]`, `[JumpjetControls]`, `[SpecialWeapons]`, `[AudioVisual]`, `[CrateRules]`,
`[CombatDamage]`, `[Houses]`, `[Sides]`, `[InfantryTypes]`, `[BuildingTypes]`, `[AircraftTypes]`,
`[VehicleTypes]`, `[TerrainTypes]`, `[SmudgeTypes]`, `[OverlayTypes]`, `[Animations]`,
`[VoxelAnims]`, `[Particles]`, `[ParticleSystems]`, `[SuperWeaponTypes]`, `[Warheads]`,
`[MultiplayerDefaults]`, `[Maximums]`, `[AI]`, `[AIGenerals]`, `[IQ]`, `[GDI]`, `[Nod]`,
`[Special]`, `[Neutral]`, `[Colors]`, `[Easy]`, `[Normal]`, `[Difficult]`, then per-object sections
(buildings/vehicles/infantry/aircraft) and per-weapon sections.
**Confidence.** high (S1).

### TS-GP-052 Type Lists & Registration
**What.** Every object must be registered in a type list with a unique integer id; the game indexes
by that id. Adding objects requires appending new ids (do not reuse).
**Data keys / counts (S1).**
`[InfantryTypes]` 36 entries (1–36, incl. FS 31–36);
`[BuildingTypes]` ~150 entries (1–273 incl. FS/campaign/civilian);
`[AircraftTypes]` 8 (ORCAB, DSHP, DPOD, SCRIN, APACHE, ORCATRAN, TRNSPORT, ORCA);
`[VehicleTypes]` ~50 (1–50, FS 61–79);
`[TerrainTypes]`, `[SmudgeTypes]` (46), `[OverlayTypes]` (182), `[Animations]`, `[VoxelAnims]`,
`[Particles]`, `[ParticleSystems]`, `[SuperWeaponTypes]` (7), `[Warheads]` (~40).
**Edge cases.** Inf/veh/building ids have recommended start points when adding (e.g. infantry from
100, buildings from 500, aircraft from 20, vehicles from 200). Reusing an id or a missing section
crashes the game.
**Kind.** architecture.
**Sources.** S1, S3, S23.
**Confidence.** high.

### TS-GP-053 Object Section Schema
**What.** Each `[ID]` section is a bag of typed keys. Documented BuildingTypes flags include:
`Adjacent`, `BaseNormal`, `Bib`, `Capturable`, `ConstructionYard`, `DockUnload`, `Factory`, `Fake`,
`FreeUnit`, `Hospital`, `Armory`, `Power`, `Powered`, `Radar`, `Refinery`, `Repairable`, `SAM`,
`ShipYard`, `UnitReload`, `UnitRepair`, `Unsellable`, `Upgrades`, `Wall`, `WaterBound`,
`WeaponsFactory`, `CloakGenerator`, `LaserFencePost`, `PlaceAnywhere`, `Weeder`, `TogglePower`,
`PowersUpBuilding`, `PowersUpToLevel`, `LightIntensity/Visibility/…Tint`, `InvisibleInGame`.
Unit flags (per S1 §Unit Statistics comments) include: `Ammo`, `Armor`, `BuildLimit`, `Cloakable`,
`CloakStop`, `Cost`, `Category`, `Crewed`, `Crusher`, `Crushable`, `DeployToFire`, `DeploysInto`,
`Dock`, `Explodes`, `Explosion`, `Fake`, `FireAngle`, `Gate`, `GateCloseDelay`, `GuardRange`,
`Image`, `Immune`, `ImmuneToVeins`, `Invisible`, `LegalTarget`, `Nominal`, `Owner`, `Passengers`,
`PipScale`, `Points`, `Prerequisite`, `Primary/Secondary/Elite`, `RadarVisible/Invisible`, `ROT`,
`Reload`, `SelfHealing`, `Selectable`, `Sensors`, `Sight`, `Speed`, `Storage`, `Strength`,
`TargetLaser`, `Trainable`, `Turret`, `TurretSpins`, `TechLevel`, `ToProtect`, `TypeImmune`,
`DeathWeapon`, `VoiceSelect/Move/Attack/Die/Feedback`, `Locomotor`, `MovementZone`, `SpeedType`,
`Weight`, `VeteranAbilities`/`EliteAbilities` (FASTER, STRONGER, FIREPOWER, SCATTER, ROF, SIGHT,
CLOAK, TIBERIUM_PROOF, VEIN_PROOF, SELF_HEAL, EXPLODES, RADAR_INVISIBLE, SENSORS, FEARLESS, C4,
TIBERIUM_HEAL, GUARD_AREA, CRUSHER), infantry-only flags (`Agent`, `C4`, `Cyborg`, `Disguised`,
`Engineer`, `Fearless`, `FemaleVoice`, `Infiltrate`, `IsCanine`, `Pip`, `Thief`, `TiberiumProof`,
`VehicleThief`), aircraft flags (`Carryall`, `Landable`, `PitchSpeed`, `PitchAngle`, `RollAngle`).
**Kind.** architecture.
**Sources.** S1, S4.
**Confidence.** high.

### TS-GP-054 `art.ini` Schema
**What.** Visual/animation mapping separate from gameplay. Each object section defines `Image`,
`Cameo`, `AltCameo`, `Theater=yes` (per-theater image), `NewTheater=`, animation state keys
(`ActiveAnim`, `IdleAnim`, `Damaged/Die/Deploy/Buildup` anims), weapon `Anim`s, voxel `HVA`, etc.
**Data keys.** `Theater` / `NewTheater` select the per-theater file (second filename letter =
T/A/U/G per S8/S9). `Cameo=` maps the sidebar icon; `AltCameo` for the alternate (e.g. GDI vs Nod)
cameo.
**Edge cases.** `Theater=yes` disables most other art flags and can make an object behave as
terrain; it does not work on InfantryTypes (S9). Missing cameo/anim → internal error.
**Kind.** architecture.
**Sources.** S1, S4, S9.
**Confidence.** high.

### TS-GP-055 Maps & Per-Map Overrides
**What.** `.MAP`/`.MPR` files can redefine almost any rules section and add map-specific sections.
The engine merges map INIs over global `rules.ini`.
**Sections (S7/S4).** `[Basic]`, `[Briefing]`, `[Digest]`, `[Houses]`, `[Map]`, `[Preview]`,
`[PreviewPack]`, `[SpecialFlags]`, `[IsoMapPack5]`, `[Lighting]`, `[OverlayDataPack]`,
`[OverlayPack]`, `[Smudge]`, `[Terrain]`, `[Tubes]`, `[Waypoints]`, `[Infantry]`, `[Units]`,
`[Aircraft]`, `[Structures]`, `[Tags]`, `[CellTags]`, `[Triggers]`, `[Events]`, `[Actions]`,
`[VariableNames]`, `[AITriggerTypes]`, `[AITriggerTypesEnable]`, `[TaskForces]`, `[ScriptTypes]`,
`[TeamTypes]`.
**Edge cases.** Map theater is chosen in `[Map] Theater=`; map-local AI triggers must be enabled;
`[Basic] IgnoreGlobalAITriggers=` disables global ones. `IonStorms`/`Meteorites` must be enabled in
`[Basic]` in addition to rules.
**Kind.** architecture.
**Sources.** S4, S7, S1.
**Confidence.** high.

### TS-GP-056 MIX Archives
**What.** Westwood `.MIX` containers hold the shipped data. Key archives (S18):
`tibsun.mix` (nearly all TS data) containing nested `local.mix` (voxels/inis/hvas/menus),
`conquer.mix` (cameos, infantry/mech anims, crate anims), `sounds.mix`, `speech01/02.mix`,
`temperat.mix`/`snow.mix`/`isotemp.mix`/`isosnow.mix` (theater tiles/structures), `cache.mix`
(palettes/fonts), `sidec01/02.mix`, `sidenc01/02.mix`, `multi.mix` (skirmish maps),
`scores.mix`/`scores01.mix` (music), `expand01.mix` (all Firestorm add-ons, with nested
`e01sc01/02`, `e01vox01/02`, `ecache01`, `gmenu`, `isotemp`, `snow`, `sounds01`, `temperat`),
`wdtvox.mix` (World Domination voices), `movies01/02.mix` (cutscenes). Patched `rules.ini` lives in
`patch.mix` (S24/S1).
**Edge cases.** To mod, extract `rules.ini`/`art.ini` and place them beside the exe; loose files
override MIX contents.
**Kind.** architecture / packaging.
**Sources.** S18, S23.
**Confidence.** high.

### TS-GP-057 Tilesets / Theaters
**What.** TS ships three theaters; the theater picks the tileset and the per-theater art file.
**Data (S8).**

| Theater | TS | `NewTheater` char | Tile filetype | TS MIX (ISOTEMP/ISOSNOW/ISOURB style) |
|---------|----|-------------------|---------------|----------------------------------------|
| Temperate | yes | T | TEM | `TEMPERAT.MIX`, `ISOTEMP.MIX` |
| Snow (arctic) | yes | A | SNO | `SNOW.MIX`, `ISOSNOW.MIX` |
| Urban | yes | U | URB | `URB.MIX`, `ISOURB.MIX` |

Theaters are hardcoded; new tiles must be added to existing theaters. Tile passability, height,
ramp, and `AllowBurrowing` live in the `.TMP`/tileset INI (S5/S9).
**Edge cases.** Changing a map's theater can cause visual glitches where equivalent tiles do not
exist (S9). Generic theater = `G` (`GENERIC.MIX`/`ISOGEN.MIX`).
**Kind.** architecture / terrain.
**Sources.** S8, S9, S18.
**Confidence.** high.

### TS-GP-058 Weapons Table (reference)
**What.** Weapon sections define Damage, ROF, Range, Projectile, Warhead, Burst, etc. ROF is in
frames; Range in cells; Damage is pre-warhead.

| Weapon | Damage | ROF | Range | Proj | Warhead | Notes |
|--------|-------:|----:|------:|------|---------|-------|
| Minigun | 8 | 21 | 4 | Invisible | SA | E1 |
| BAZOOKA | 25 | 60 | 6 | AAHeatSeeker2 | AP | E3 |
| JumpCannon | 15 | 40 | 5 | Invisible3 | SA | Burst 2 |
| AssaultCannon | 40 | 50 | 5 | Invisible | SA | Wolverine |
| CyCannon | 120 | 50 | 7 | ProtonBlast | PlasmaWH | CYC2 |
| HarpyClaw | 60 | 36 | 5 | Invisible2 | SA | Harpy |
| RaiderCannon | 40 | 55 | 4 | Invisible | SA | Buggy |
| VulcanTower | 18 | 26 | 6 | Invisible | SA | Component Tower |
| RPGTower | 110 | 80 | 8 | Lobbed2 | RPG | MinRange 2 |
| BikeMissile | 40 | 60 | 5 | HeatSeeker | AP | Cycle |
| RedEye2 | 33 | 55 | 15 | AAHeatSeeker | SAMWH | SAM |
| HoverMissile | 30 | 68 | 8 | AAHeatSeeker2 | AP | Burst 2 |
| LtRail | 0 (Amb 150) | 60 | 6 | Invisible | RailShot2 | railgun |
| MechRailgun | 0 (Amb 200) | 60 | 8 | Invisible | RailShot | Mammoth MkII |
| Vulcan | 20 | 60 | 4 | Invisible | SA | Mutant |
| Vulcan3 | 10 | 30 | 4 | Invisible | SA | Burst 3, Cyborg |
| FireballLauncher | 0 (Amb 2) | 50 | 4.25 | Invisible | Fire | Burst 2 |
| Sniper | 150 | 120 | 6.75 | Invisible | HollowPoint | Umagon/SLAV |
| M1Carbine | 15 | 20 | 4 | Invisible | SA | E1 elite |
| Dragon | 30 | 50 | 6 | AAHeatSeeker2 | AP | Burst 2, STNK |
| Hellfire | 30 | 50 | 6 | AAHeatSeeker2 | ORCAAP | Burst 2, ORCA |
| Proton | 20 | 3 | 5 | ProtonTorpedo | AP | Banshee |
| Grenade | 40 | 80 | 4.5 | Lobbed | HE | E2 |
| 75mm | 35 | 40 | 6 | Cannon | AP | |
| 90mm | 36 | 50 | 6.75 | Cannon | AP | Tick Tank |
| 120mmx | 50 | 80 | 6.75 | Cannon | AP | Burst 2, Mammoth |
| 120mm | 70 | 80 | 6.75 | Cannon | AP | Titan |
| 140mm | 90 | 160 | 9 | Cannon | AP2 | Nod Arty |
| Bomb | 160 | 10 | 3 | Cannon2 | ORCAHE | Orca Bomber |
| SuicideBomb | 11000 | 1 | .5 | Invisible | SUPER | Hunter-Seeker |
| MammothTusk | 40 | 80 | 6 | AAHeatSeeker | HE | Burst 2 |
| 155mm | 120 | 110 | 18 | Ballistic | ARTYHEX | MinRange 5, ART2 |
| SonicZap | 1 (Amb 3) | 120 | 6 | Null | SonicWarhead | Disruptor |
| RepairBullet | −50 | 80 | 1.8 | Invisible | Mechanical | Repair |
| Heal | −50 | 80 | 7 | Invisible | Organic | Medic |
| Vulcan2 | 50 | 50 | 6 | Invisible | SA | Drop Pod |
| LaserFire | 250 | 120 | 10.5 | LLine | Super | Obelisk, charges |
| LaserFire2 | 30 | 40 | 5.5 | LLine2 | Super | Laser turret |
| EMPulseWeapon | 1200 (duration) | 1 | 40 | PulsPr | EMPuls | EMP cannon |
| SlimeAttack | 100 | 80 | 2 | Invisible | Slimer | Adult visceroid |
| ChemLauncher | 100 | 1 | 6 | ChemMissile | Gas | Chemical missile |
| FiendShard | 35 | 30 | 5 | DogShard | Shard | Burst 3 |
| MultiLauncher | 130 | 80 | 30 | MultiMissile | HE | Multi missile |
| Pistola | 2 | 20 | 3 | Invisible | SA | Technician |
| MultiCluster | 65 | 80 | 6 | HeatSeeker | HE | Burst 2, WEEDGUY |
| LIMP | 1 | 80 | 2 | LimpetBullet | LIMPY | Limpet |
| WebLauncher | 0 | 200 | 7 | WebCapsule | WebMass | Reaper |
| DualRockets | 5 | 180 | 6 | AAHeatSeeker2 | AP | Burst 2 |
| QuadLauncher | 0 | 180 | 7 | DualCluster | SA | MinRange 3, Burst 2 |
| Tentacle | 16 | 80 | 15 | Invisible | Stinger | Tiberium Floater |
| DEFOB | 350 | 20 | 10.5 | LLine | Super2 | Burst 2, Core Defender |
| MobileEMPulseWeapon | 1200 | 1 | 40 | PulsPr | MobileEMPulse | Mobile EMP |
| AALaserFire | 80 | 400 | 12 | AALLine | Super | Obelisk of Darkness (AA) |
| CABLaser | 100 | 70 | 10.5 | LLine | Super | CABAL Obelisk |
| Jugg90mm | 75 | 140 | 18 | Ballistic2 | ARTYHEX | MinRange 5, Burst 3 |

`[Warheads]`: EMPuls, SonicWarhead, TankOGas, SA, HE, AP, Gas, Fire, HollowPoint, Super, Organic,
Slimer, FirestormWH, IonCannonWH, RailShot, Mechanical, VeinholeWH, IonWH, ARTYHEX, PlasmaWH, SAMWH,
ORCAAP, RailShot2, ORCAHE, WebMass, LIMPY, CoreDefPlasmaWH, Super2, MobileEMPulse, WeakGass, Stinger,
MeteorWH, ARTYHEX, Gas2. `SA` is the standard small-arms warhead; `AP` anti-vehicle; `HE` explosive.
Warhead-vs-armour `Verses` multipliers are hardcoded for TS (not INI-exposed) — S10 documents the
RA2/YR system where `Verses` is editable.
**Kind.** combat data.
**Sources.** S1, S10.
**Confidence.** high (values), high (warhead names).

---

## Coverage Checklist

- [x] 1. Economy — Tiberium types/values (001); growth/spread (002); harvester logic (003);
      refinery dock/unload (004); silo + caps (005); crates (006); veins/veinholes (007);
      weed/chemical economy (008); harvester bombs (009); refund/repair (010).
- [x] 2. Construction & base — MCV deploy (011); placement/bibs (012); walls/gates/laser fence/
      firestorm wall (013); sell/repair/survivors (014); engineer capture (015); capturable/prebuilt/
      civilian (016).
- [x] 3. Production & tech — category queues (017); full prerequisite system + aliases (018);
      multiple-factory bonus (019); factory exits/rally (020); PowersUpBuilding (021);
      deploy-to-produce (022); build limits/cameos (023).
- [x] 4. Full rosters — GDI infantry (4.1), Nod infantry (4.2), special/civilian (4.3), GDI vehicles
      (4.4), Nod vehicles (4.5), aircraft (4.6), GDI structures (4.7), Nod structures (4.8), shared/
      civilian structures (4.9), defenses/superweapon hosts (4.10), weapons (058). Deploy units, EMP,
      cloak, subterranean, jumpjet all covered.
- [x] 5. Movement — locomotion table (024); movement zones (025); tunnel network (026); amphibious/
      hover (027); aircraft (028); jumpjet (029).
- [x] 6. Vision — radar (030); radar events (031); jammer/stealth generator/sensors (032);
      reveal (033).
- [x] 7. Special systems — full superweapon list + parameters (034); hunter-seeker (035); engineers
      (036); CABAL (037); veinhole monster (038); visceroids/mutants (039); ion storms (040);
      meteorites (041); combat/damage (042). Firestorm wall in 013/034; drop pod/EMP in 034/035.
- [x] 8. Skirmish AI — `[AI]` model (043); `[IQ]` (044); difficulty (045); AI scripting (046).
- [x] 9. Multiplayer/meta — defaults (047); modes/options (048); players/colors/houses (049).
- [x] 10. Data architecture — INI files (050); rules section catalogue (051); type lists (052);
      object schema (053); art schema (054); maps/overrides (055); MIX (056); tilesets/theaters (057).

## Open Questions / Top Uncertainties

1. **Tiberium credit values.** Harvester load ($700/$1120), full Ref ($2000/$3200), full Silo
   ($1500/$2400) come from one community guide (S19) and are internally inconsistent with its
   own "6×$125" figure. The engine's actual credit-per-bail is hardcoded in `TiberiumClass`/
   rules; not in `RULES.INI`. Needs disassembly (OpenTS/Vanilla Conquer) to confirm. **Confidence
   med-low.**
2. **Refinery unload timing.** S3/S19 imply ~0.96 s per bail; a 28-bail load would be ~27 s, but
   guide claims of 9.6 s for 10 bails conflict. Needs runtime measurement. **Confidence low.**
3. **Superweapon charge times.** `RULES.INI` has them commented out (`IonCannon=9`, `Nuke=11`,
   `EMPulse=5`, `FirestormDefense=4` minutes); the wiki/mod sources quote 10:00 for Ion and Multi.
   Were the commented values ever active? Needs binary confirmation. **Confidence low.**
4. **Chemical missile charge.** `WeedCapacity=56` is documented but the per-bail charge rate is
   hardcoded and not in `RULES.INI`. **Confidence low.**
5. **`MaximumQueuedObjects`.** FS rules say 25; the original in-file comment says 4(+1). Which is
   correct per version, and does the UI reflect it? **Confidence med.**
6. **Multiple-factory cap.** Community says the speed bonus caps around 14 structures; no INI value
   expresses the cap. Needs engine confirmation. **Confidence low.**
7. **`MultipleFactory` default.** The rules file value is `.5`, but the comment says `(def=1)`; which
   applies when the key is absent? **Confidence med.**
8. **Warhead `Verses` table.** TS hardcodes armour-vs-warhead multipliers; neither the values nor
   the exact armor classes' resistances are in `RULES.INI`. Needs the released source (`[Warhead]`
   tables in C++ `F_Warhead`-style code). **Confidence low.**
9. **`NAPULS EMP Cannon Owner=Nod,GDI`.** Written as both owners, but historically a Nod structure;
   GDI access may be campaign/Firestorm-only. **Confidence low.**
10. **Nuke in TS.** `NukeWarhead=Nuke` exists in `[SpecialWeapons]`, but no TS superweapon uses it;
    whether it is reachable without mods is unclear. **Confidence low.**
11. **Crate effect stacking / exact magnitudes.** Contents list is solid (S11) but magnitudes
    (e.g. armor/firepower/speed bonus values, superweapon-strike type) are not in `RULES.INI`.
    **Confidence med-low.**
12. **`aifs.ini` vs `ai.ini`.** Firestorm reportedly loads a separate `aifs.ini` (S16); the exact
    override/merge behaviour vs `ai.ini` needs confirmation. **Confidence med.**
13. **`[AIGenerals]` COM objects.** Listed but commented out in `RULES.INI`; whether the TS engine
    actually instantiates them is unknown. **Confidence low.**
14. **CABAL house implementation.** CABAL is not in `[Houses]`; how its ownership/SmartAI is wired
    (special `[Special]` house vs hardcoded) is not fully documented. **Confidence low.**
15. **Original 1999 vs Firestorm ruleset differences.** This doc is based on the Firestorm `RULES.INI`;
    pre-Firestorm values (e.g. `MaximumQueuedObjects=4`, no FS units, possibly different costs for
    4TNK/HVR) are not separately enumerated. Needs the original `rules.ini` for a baseline diff.
    **Confidence med.**
16. **MovementZone semantic labels** (which CLSID maps to tracked vs wheeled) is inferred from usage,
    not from a documented GUID table. **Confidence med.**
