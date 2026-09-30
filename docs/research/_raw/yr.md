# Command & Conquer: Yuri's Revenge — Complete Feature Inventory

Research target: everything **Yuri's Revenge (2001)** ADDS or CHANGES relative to *Red Alert 2*,
focused on data-driven re-implementation in a unified RTS engine shared with a Tiberian Sun remake.

**Status:** first-pass raw research. Items not corroborated by a source below are marked `[uncertain]`.
**Companion docs:** mirror the RA2 domain list; TS/FS comparison table at the end.

**Primary sources used:**
- ModEnc: [Yuri's Revenge](https://modenc.renegadeprojects.com/Yuri%27s_Revenge),
  [MindControl](https://modenc.renegadeprojects.com/MindControl),
  [Gattling Weapon System](https://modenc.renegadeprojects.com/Gattling_Weapon_System),
  [Bunker](https://modenc.renegadeprojects.com/Bunker),
  [Countries](https://modenc.renegadeprojects.com/Countries),
  [GameModes](https://modenc.renegadeprojects.com/GameModes)
- CNCNZ arsenal pages: [Yuri units](https://cncnz.com/games/yuris-revenge/yuris-units),
  [Yuri structures](https://cncnz.com/games/yuris-revenge/yuris-structures),
  [Allied units](https://cncnz.com/games/yuris-revenge/new-allied-units),
  [Allied structures](https://cncnz.com/games/yuris-revenge/new-allied-structures),
  [Soviet units](https://cncnz.com/games/yuris-revenge/new-soviet-units),
  [Soviet structures](https://cncnz.com/games/yuris-revenge/new-soviet-structures),
  [Tech buildings](https://cncnz.com/games/yuris-revenge/new-tech-buildings)
- C&C Fandom: [YR game page](https://cnc.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2_-_Yuri%27s_Revenge)
- Wikipedia: [Command & Conquer: Yuri's Revenge](https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge)
- Soundtrack list: [Gamicus YR soundtrack](https://gamicus.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2_-_Yuri%27s_Revenge/Soundtrack)

---

## A. YR full feature inventory by domain

### A1. Core engine / simulation

- **Third side (ThirdSide)** — `[Sides]` gains `ThirdSide=YuriCountry`; the first C&C game with three fully distinct playable factions. Engine-side this is a side registry, not hardcoded logic.
- **YR executable split (`ra2md.exe`)** — YR ships a separate exe + "Mission Disk" data files; all INI names gain `md` (`rulesmd.ini`, `artmd.ini`, `aimd.ini`, `mapsmd.ini`, `uimd.ini`, etc.). INI files are complete replacements, not overlay overrides. Big modding delta vs RA2.
- **Extended mind-control model** — Primary weapon `Damage` = control capacity; supports multi-target control, one link set per firer. `InfiniteMindControl` on the warhead lifts the cap. See B/C.
- **Permanent mind control** — `Type=PsychicDominator` superweapon permanently converts units; once dominated they can never be re-controlled or released. Distinct from temporary warhead control.
- **New superweapon behaviours** — `Type=` gains `PsychicDominator`, `GeneticMutator`, `ForceShield` alongside RA2's Nuke/IronCurtain/Chronosphere/WeatherStorm/SpyPlane/ParaDrop.
- **Entity conversion / mutation** — Genetic Mutator (and Mutation power) converts infantry into Brutes owned by the caster; animals are killed instead. Uses the same type-conversion primitive as `DeploysInto`.
- **Power-gated mobile units** — Robot Tank becomes inert at low base power or if the Robot Control Center is lost; Psychic Tower and Gattling Cannon deactivate on low power.
- **Per-country bonus model** — `[Country]` sections can carry `VeteranXxx=` (build at veteran) and `YYYZZZMult=` (Armor/Cost/Speed/BuildTime x Aircraft/Units/Infantry/Buildings/Defenses, plus `IncomeMult=`) multipliers.
- **10 multiplayer houses** — the 9 RA2 countries + `YuriCountry`, indices 0–9 (all hardcoded in exe array order). `[Countries]` must keep the 9 major houses contiguous first or the game crashes.
- **Patch 1.001 balance** — Rhino build speed up; Service Depot can no longer sell vehicles; MCV/ConYard deploy-under-mind-control exploit guarded with a `ConstructionYard=yes` check.
- **`-SPEEDCONTROL`** — YR exe switch now allows the game-speed slider in campaign mode (was non-campaign only).

### A2. Economy

- **Slave Miner replaces ore miner + refinery** — Yuri's only economy unit. `$1750`, deploys in the field, releases up to 5 Slaves that gather and return ore. Auto-repairs while mobile; an Engineer can repair it when deployed. Buildable from both Construction Yard and War Factory.
- **Slaves** — free, uncontrollable, weak melee infantry; killed Slaves are replaced free by the parent Slave Miner. If the miner dies, surviving Slaves join the "liberator" as weak melee units (or go neutral if the owner surrendered).
- **Credit siphon (Floating Disc)** — parked over an enemy Refinery/Slave Miner, it drains credits to Yuri's owner. New resource-theft mechanic.
- **Grinder recycle** — any controlled vehicle/infantry sent into the Grinder is destroyed and refunds a percentage of build cost (commonly cited ~50% `[uncertain]`). The capture-and-recycle economy loop is Yuri-specific.
- **Industrial Plant (Soviet)** — `$2500`, one per player: −25% cost and build time on vehicles and ore refineries.
- **Bio Reactor (Yuri power/economy hybrid)** — garrison up to 5 infantry for +100 power each (`$600`, +150 base); mind-controlled units can also be interned there.
- **Tech Civilian Power Plant (neutral)** — capturable `+200` power, equivalent to a faction power plant.
- **Oil Derrick / income** — retained from RA2; per-country `IncomeMult` is new in YR's data model.

### A3. Construction / base

- **Yuri Construction Yard** — deployed from Yuri MCV (`$3000`); no Service Depot, no Ore Refinery (Slave Miner instead).
- **Buildable faction structures** — Yuri: Bio Reactor, Barracks, War Factory, Sub Pen, Psychic Radar, Grinder, Battle Lab, Citadel Wall, Tank Bunker, Gattling Cannon, Psychic Tower, Cloning Vats, Genetic Mutator, Psychic Dominator.
- **Tank Bunker (Yuri)** — `$400`; garrison one turreted non-artillery vehicle for damage / rate-of-fire / range bonuses, at the cost of immobility. Engine flag `Bunker=yes`, entry gate `Bunkerable`. Foundation must have a side >1 cell to accept a vehicle.
- **Battle Bunker (Soviet)** — `$400`; buildable infantry garrison (5 slots), behaves like a player-owned garrisonable building and can be repaired like any structure (unlike neutral civilian garrisons).
- **Citadel Wall (Yuri)** — Yuri's wall; 4 segments placeable at once when adjacent to existing wall.
- **Cloning Vats (moved to Yuri)** — `$2500`, one per player; duplicates any Barracks-produced infantry for free. YR version cannot recycle infantry for credits (that moved to the Grinder).
- **Superweapon notice contract** — when a superweapon structure completes, all players are notified and the shroud over it is lifted with a global timer.

### A4. Production / tech

- **Yuri production line** — Barracks (infantry), War Factory (vehicles + the one aircraft, Floating Disc), Sub Pen (navy). No Aircraft-type producer beyond the War Factory.
- **Tech gating** — Yuri: Barracks needs Bio Reactor; War Factory needs Slave Miner + Barracks; Psychic Radar needs Slave Miner; Battle Lab needs War Factory + Psychic Radar; MCV needs Grinder; Yuri Clone/Virus need Psychic Radar; Yuri Prime/Mastermind/Floating Disc/Boomer need Battle Lab or Psychic Radar as listed.
- **Robot Control Center (Allied)** — `$1000`; unlocks Robot Tank production and keeps existing Robot Tanks online. Losing it or dropping to low power disables all Robot Tanks.
- **Cloning duplication** — free duplicate infantry from Cloning Vats; interacts with one-at-a-time hero limits (a Cloning Vat allows a second Tanya/Boris/Yuri Prime `[uncertain for Yuri Prime specifically]`).
- **Hero single-build limits** — Tanya, Boris, Yuri Prime: one per player at a time unless a Cloning Vat exists.
- **Spy infiltration unlocks** — Psi Commando ($1000) via any Spy into a Yuri Battle Lab; Chrono Ivan prerequisites changed.

### A5. Units & combat

- **Yuri roster** — Infantry: Initiate, Engineer, Brute, Virus, Yuri Clone, Yuri Prime, Slave, Cosmonaut (campaign). Vehicles: Slave Miner, Lasher Light Tank, Gattling Tank, Chaos Drone, Magnetron, MCV, Mastermind. Aircraft: Floating Disc. Ships: Amphibious Transport, Boomer.
- **Allied additions** — Guardian GI (deploy to rocket AT/AA, uncrushable when deployed, cannot garrison), Robot Tank (amphibious, mind-control immune, power-dependent), Battle Fortress (5 passenger slots, passengers fire, can crush normally-uncrushable units), Robot Control Center.
- **Soviet additions** — Boris (designates a structure → 2–4 MiG strikers scale with veterancy; vulnerable while designating), Siege Chopper (MG in air, deploys into long-range artillery on ground), Battle Bunker, Industrial Plant, Spy Plane.
- **Removed from Soviets** — Psi-Corps Trooper/Soviet Yuri (→ Yuri Clone), Cloning Vats, Psychic Sensor (→ Yuri Psychic Radar).
- **Tanya modified** — `$1500`, C4 now works on vehicles, immune to mind control, uncrushable except by Battle Fortress.
- **Navy SEAL promoted** — campaign-only in RA2, skirmish/MP-buildable in YR.
- **IFV weapon table extended** — new passenger→weapon mappings for Initiate (pyrokinetic dome), Guardian GI (advanced missiles), Virus (toxic sniper), Slave (missiles), Boris (advanced MG), plus existing units.
- **Mind-control immunity set** — Attack Dogs, war miners, aircraft, other mind-control units, Robot Tank, heroes (Tanya/Boris/Yuri Prime), and buildings by default (`ImmuneToPsionics=yes`); Yuri Prime alone can control buildings because vanilla YR sets `ImmuneToPsionics=no` on structures for him.
- **Berserk (Chaos Drone)** — gas cloud makes enemies fire on friends with boosted attack; timer refreshes on re-contact.
- **Virus poison cloud** — sniper victim leaves a toxic cloud that damages other infantry; Virus herself is immune.
- **Magnetron** — artillery analogue that levitates/pulls enemy vehicles toward itself and damages structures; no effective anti-infantry weapon and cannot crush.
- **Mastermind** — controls up to 3 units, but auto-controls any extra enemy in range; exceeding capacity self-destructs and releases all controlled units.
- **Floating Disc** — laser vs infantry/vehicles/structures; over an enemy power plant it powers the whole base down; over a refinery it siphons credits; over a powered defense it disables it.
- **Boomer** — submarine with torpedoes vs ships and destructible ballistic missiles vs ground (interceptable by AA; Giant Squid cannot envelop it).
- **Brute** — melee anti-armour infantry; Attack Dogs refuse to attack it.
- **Cosmonaut** — campaign-only Soviet infantry (mission 6), jetpack like Rocketeer, laser vs vehicles/structures, survives the lunar map.
- **Gattling spin-up** — Gattling Tank/Cannon ramp through 3 damage stages the longer they fire; see C for the system.

### A6. Movement

- **Amphibious/hover units** — Robot Tank hovers (crosses water, sinks if unpowered); Yuri Amphibious Transport (12 slots, carries vehicles + infantry, land + water).
- **Air/ground dual-state** — Siege Chopper toggles air ↔ deployed artillery.
- **Submersible** — Boomer submerges; visible when attacked or badly damaged.
- **Forced displacement** — Magnetron pulls enemy vehicles (engine-side a movement override, not pathing).
- **Jetpack / low gravity** — Cosmonaut and Rocketeer in the lunar theater `[uncertain whether gravity physics differ]`.
- **No core pathfinding overhaul vs RA2** — YR movement is RA2's cell/path system plus new movement zones and unit states.

### A7. Vision & fog

- **Psychic Radar (Yuri)** — merges RA2's Soviet Psychic Sensor + radar: enables radar display, reveals the attack target of enemies within radius, uncovers Spies, and charges Psychic Reveal.
- **Psychic Reveal** — free support power, 4:00, reveals a large shroud radius.
- **Spy Plane (Soviet)** — free support power from Radar Tower, 4:00; flies a line across the map revealing shroud; replaces the lost Psychic Sensor utility.
- **Reveal-on-build** — completed superweapons expose their own shroud tile with a visible timer to all players.
- **Black shroud + fog retained** — RA2's two-layer vision model unchanged; Gap Generator still present.

### A8. Special / superweapon systems

- **Force Shield** — all sides once a Battle Lab exists; free, 5:00; makes friendly structures in an area invulnerable to all damage including superweapons, at the cost of a temporary base-wide power-down.
- **Psychic Dominator (Yuri)** — `$5000`, 10:00 "Domination": AoE permanent mind control + considerable structure damage; immune and garrisoned units unaffected.
- **Genetic Mutator (Yuri)** — `$2500`, "Mutation" 5:00: converts all infantry in the target area (friend and foe) into player-owned Brutes; animals die.
- **Psychic Tower (Yuri)** — `$1500` defense; automatically mind-controls up to 3 units entering range; deactivates on low power, releasing them.
- **Cloning Vats** — passive duplicate-infantry superstructure.
- **Spy Plane / Psychic Reveal / Paratroopers** — support-power framework additions; Paratroopers drop 6 GI / 9 Conscripts / 6 Initiates depending on side.
- **Iron Curtain, Chronosphere, Weather Storm, Nuclear Missile** — retained from RA2 unchanged in role `[balance tweaks uncertain]`.

### A9. UI/UX

- **Mostly RA2 UI** — sidebar/tabs, radar, cameos, veterancy pips retained.
- **New cameos/icons** for all YR units/structures; Yuri sidebar has its own art and EVA voice.
- **Mind-control feedback** — controlled units change to the controller's colour and show `PipScale` pips; Psychic Tower/Mastermind capacity is readable via pips.
- **Garrison/Bunker cursors and enter/exit orders** — new interaction affordances for foot and vehicle garrisons.
- **Superweapon shared countdown UI** — global timer displayed on the structure and to all players.
- **Skirmish/MP lobby** — 10th country (Yuri) and team setup; new game-mode selection (Team Alliance).
- **Loading screens bound to country index** — YR gives each country its own palette (`mpyls.pal`, etc.); RA2 shared one palette.

### A10. Presentation / audio

- **New Frank Klepacki soundtrack** — ~10 YR tracks: Brain Freeze, Bully Kit, Deceiver, Defend the Base, Drok, Options Theme, Phat Attack, Score Theme, Tactics, Trance L Vania.
- **Yuri EVA + unit voice sets** — distinct adviser/unit VO for the third faction; new score/theme per faction.
- **New cutscenes** — live-action missions with Udo Kier (Yuri), Hollywood/Bing, dinosaur prologue, etc.
- **New theaters/palettes/tilesets** — Lunar theater for the Moon mission, plus new urban/snow art; per-country loading palettes.
- **New visual FX** — mind-control link visuals, psychic blasts, genetic mutation, force shield, gattling muzzle ramp.

### A11. Campaign & scripting

- **Two campaigns only** — Allied and Soviet, 7 missions each (RA2 had 12 each); **no playable Yuri campaign** (Yuri is MP/skirmish only).
- **Time-travel frame** — both campaigns replay the Third World War to stop Yuri; the Soviet route has a dinosaur prologue and ends in Transylvania.
- **One-off gimmick missions** — commando/no-base levels, timed holds, mind-controlled friendly bases, the Moon (low-gravity/lunar theater, no conventional air), and a scripted T-Rex encounter.
- **Psychic Beacon** — campaign structure/trigger that mind-controls whole pre-built Allied/Soviet bases (Transylvania); the player must destroy it to regain control.
- **Scripting deltas vs RA2** — same trigger/teamtype/taskforce system as RA2 extended with YR superweapon types and mind-control/ownership actions; missions lean harder on scripted ownership changes and timer holds.
- **No official campaign co-op** — engine has a `cooperative` GameMode token, but shipped YR campaigns are single-player; online co-op is community/CnCNet `[uncertain/community]`.

### A12. Skirmish / multiplayer / meta

- **Team Alliance** — YR's new official mode, replacing RA2's obsolete Siege mode.
- **Retained modes** — Battle (standard), Megawealth, Land Rush (`duel`), Meat Grind (`meatgrind`), Naval War (`navalwar`), plus `cooperative` co-op token for FA2 maps.
- **Unholy Alliance** — popular community 2v2 mixed-faction format/map family, not an engine `GameModes` entry `[uncertain — treated here as community]`.
- **10 countries** with country-specific units/bonuses, plus Yuri as the third side.
- **CnCNet/XWIS** — modern online revival targets `ra2md.exe`; official WOL was shut down.
- **Map format** — YR skirmish maps `.yrm` (RA2 `.map`), `GameModes=` key in map INIs; Final Alert 2 support.

### A13. Modding / data architecture

- **`md` INI family is a full replacement** — modding targets `rulesmd.ini` / `artmd.ini` / `aimd.ini`; RA2 and YR content are separate baselines.
- **New INI flags introduced in YR** (partial): `MindControl`, `InfiniteMindControl`, `ImmuneToPsionics`, `Bunker`, `Bunkerable`, `IsGattling`, `WeaponStages`, `StageX`/`EliteStageX`, `RateUp`, `RateDown`, `WeaponCount`, `TurretCount`, new `Type=` superweapons, `Grinder`, `Reselectable`, per-country `VeteranXxx`/`YYYZZZMult`/`IncomeMult`, `BunkerDamageMultiplier`/`BunkerROFMultiplier`/`BunkerWeaponRangeBonus` under `[CombatDamage]`.
- **`[Countries]` / `[Sides]`** — new `ThirdSide` grouping; house array order is executable-sensitive.
- **Per-country art binding** — flags and loading screens are indexed to the `[Countries]` order, not the name; YR adds country palettes.
- **Later community engines** — RockPatch and Ares extend YR (Ares adds `MindControl.Permanent`, gattling cycle, customizable bunkers); vanilla YR is the baseline.
- **Theater/registry** — `Lunar` theater plus per-map `Theater=`; new tilesets/palettes loaded from YR data.

---

## B. The Yuri faction (Psychic / Third Side)

Identity: mind control, genetic engineering, psychic technology, slavery, and recycling of captured enemies.
Conventional firepower is low; mobility is mixed; air is deliberately weak.

### B1. Structures

- **Construction Yard** — heart of the base; deployed from Yuri MCV (`$3000`), required for all building.
- **Bio Reactor** — `$600`, `+150` power; 5 infantry slots, `+100` power each; interning mind-controlled units is legal and they release to their owner if the controller dies.
- **Barracks** — `$500`, −10 power; trains Initiate → Yuri Clone.
- **War Factory** — `$2000`, −25 power; all ground vehicles plus the Floating Disc.
- **Sub Pen** — `$1000`, −25 power; builds and repairs Yuri's two naval units, must be placed wholly in water.
- **Psychic Radar** — `$1000`, −50 power; radar + attack-order sensor + spy reveal + enables Psychic Reveal.
- **Grinder** — `$1000`, −50 power; recycles any owned/controlled unit into credits.
- **Battle Lab** — `$2000`, −100 power; unlocks Yuri advanced units/defenses/superweapons.
- **Citadel Wall** — `$100`, Yuri's wall segment.
- **Tank Bunker** — `$400`; one-vehicle garrison with combat bonuses, immobilizing.
- **Gattling Cannon** — `$1000`, −50 power; anti-infantry/anti-air, 3-stage spin-up, deactivates on low power.
- **Psychic Tower** — `$1500`, −100 power; auto mind-controls up to 3 units, defenseless at cap, releases on low power.
- **Cloning Vats** — `$2500`, −200 power, one per player; free duplicate infantry (no recycle).
- **Genetic Mutator** — `$2500`, −200 power, one per player; Mutation superweapon.
- **Psychic Dominator** — `$5000`, −200 power, one per player; Domination superweapon (permanent capture).
- **Psychic Beacon** (campaign) — scripted structure that permanently mind-controls whole bases.

### B2. Infantry

- **Initiate** — `$200`; psychic-bolt base infantry, strong vs infantry, can garrison civilian buildings.
- **Engineer** — `$500`; capture/repair/defuse, bridge repair via bridge huts, lost on use (except defuse).
- **Brute** — `$500`; genetically engineered melee anti-armour monster; dogs avoid it.
- **Virus** — `$700`, Psychic Radar; one-shot sniper; victim leaves a lingering toxic cloud vs infantry; Virus immune to own toxin.
- **Yuri Clone** — `$800`, Psychic Radar; controls one organic/vehicle target (not miners/dogs/aircraft/other controllers); psychic blast kills surrounding infantry (friendly included).
- **Yuri Prime** — `$1500`, Battle Lab; hero. Controls vehicles, infantry, **and structures**; uncrushable, self-healing, mind-control immune; psychic blast with no friendly fire. One at a time (Cloning Vats may lift the limit `[uncertain]`).
- **Slave** — free, from Slave Miner; uncontrollable ore gatherer; auto-replaced; becomes weak melee on miner death.
- **Cosmonaut** — `$600` campaign-only (Soviet mission 6); jetpack, laser vs vehicles/structures, lunar-capable.

### B3. Vehicles

- **Slave Miner** — `$1750`, Bio Reactor; mobile/deployable economy; 5 Slaves; auto-repair mobile; Engineer repair deployed; ConYard + War Factory build.
- **Lasher Light Tank** — `$700`; standard Yuri tank, weakest armour of the MBTs, crushes infantry.
- **Gattling Tank** — `$600`; dual 50-cal spin-up, anti-infantry/anti-air, 3 stages.
- **Chaos Drone** — `$600`; deploy releases berserk gas (enemies attack friends, boosted damage, refresh on contact).
- **Magnetron** — `$1000`, Psychic Radar; magnetic beam levitates/pulls vehicles and damages structures; no anti-infantry, cannot crush.
- **MCV** — `$3000`, needs Grinder; deploys into Construction Yard.
- **Mastermind** — `$1750`, Battle Lab; controls 3 units but auto-grabs extras in range; overflow self-destructs and frees all controlled units.

### B4. Aircraft

- **Floating Disc** — `$1750`, Battle Lab; laser vs infantry/vehicles/structures; drains base power over a power plant, siphons credits over a refinery, disables a powered defense it sits over.

### B5. Ships

- **Amphibious Transport** — `$900`; 12 slots, carries vehicles + infantry, land + water, no weapon, heavy armour.
- **Boomer** — `$2000`, Psychic Radar; sub with torpedoes vs navy and interceptable ballistic missiles vs ground; revealed when attacked/damaged.

### B6. Support powers

- **Psychic Reveal** — 4:00, Psychic Radar; large shroud reveal.
- **Force Shield** — 5:00, Battle Lab; invulnerable structures AoE + base power-down (all sides get it).
- **Mutation** — 5:00, Genetic Mutator; AoE infantry → Brutes, animals killed.
- **Domination** — 10:00, Psychic Dominator; AoE permanent mind control + structure damage; immune/garrisoned unaffected.

---

## C. New mechanics YR adds engine-wide

### C1. Mind control

- **Temporary (warhead) control** — weapon `Primary` warhead `MindControl=yes`; target is controlled instead of damaged, instant, ignores actual hit. Capacity = `Primary.Damage`; `ElitePrimary` Damage is **ignored** even at elite.
- **Multi-target** — `Damage>1` holds multiple links; links are not dropped when a new target is acquired until capacity is reached. `InfiniteMindControl=yes` removes the cap entirely.
- **Emitter profiles** — Yuri Clone: 1 link; Mastermind: 3 links (auto-grabs extras, self-destructs on overflow); Psychic Tower: 3 links (powered, releases on power loss); Yuri Prime: controls buildings.
- **Permanent (superweapon) control** — `Type=PsychicDominator` captures permanently; dominated units can't be released nor re-controlled and count as the caster's.
- **Immunity & targeting** — `ImmuneToPsionics=yes` units are untargetable by control. Buildings are immune by default; YR flips them to `no` for Yuri Prime. Mind-controlled units cannot garrison (`Occupier` inert).
- **Link lifecycle bugs to avoid** — control links are severed by `DeploysInto`/`UndeploysInto` (vanilla exploits free MCVs); YR 1.001 adds a `ConstructionYard=yes` guard. A controlled unit whose original owner is defeated goes neutral if released.
- **Release triggers** — controller death, capacity overflow (Mastermind), power loss (Tower), or explicit release. Dominator captures never release.

### C2. Garrison / occupancy expansions

- **Buildable garrisons** — Battle Bunker (infantry, repairable) and Tank Bunker (vehicle, combat bonuses) are new building classes; `Bunker=yes` + `Bunkerable`, with `[CombatDamage]` `BunkerDamageMultiplier`, `BunkerROFMultiplier`, `BunkerWeaponRangeBonus`.
- **Fire-from-transport** — Battle Fortress lets each of 5 passengers fire its own weapon; IFV weapon table is passenger-driven.
- **Civilian garrisoning** retained from RA2 (no fire-from-inside for most, but YR adds Yuri-faction access and bunker interactions).
- **Bio Reactor internment** — infantry-as-power-fuel is a garrison subtype with a power hook.

### C3. Gattling weapon system

- **Staged weapons** — `IsGattling=yes`, `TurretCount>=1`, `WeaponCount = WeaponStages*2`; odd weapons AG, even weapons AA; `StageX`/`EliteStageX` are ascending timer thresholds; `RateUp`/`RateDown` per-frame timer deltas; `RateDown=0` resets instantly.
- **Vanilla profile** — Gattling Tank/Cannon: `WeaponStages=3`, `WeaponCount=6`, `Stage1=200/Stage2=400/Stage3=600`, `RateUp=1`, `RateDown=50`.
- **Emergent uses** — dummy first-stage weapons, `FireOnce`/`RateDown=0` for charge-and-release cannons (Ares adds `Gattling.Cycle` to loop stages).

### C4. Superweapon / support-power framework

- **New `Type=` behaviours** — `PsychicDominator` (capture AoE + damage), `GeneticMutator` (convert AoE), `ForceShield` (invuln AoE + self power-down).
- **Global notification contract** — building a superweapon reveals its tile and starts a publicly visible timer.
- **Targeting modes** — area-target powers (Psychic Reveal, Force Shield, Domination, Mutation, Chronosphere, Weather Storm), line/auto powers (Spy Plane, Paratroopers), and no-target powers.
- **Cooldowns as first-class data** — 4:00–10:00 support-power charge times per power.

### C5. Side / country system

- **ThirdSide** — a third entry in `[Sides]`, new `YuriCountry` in `[Countries]` index 9; per-country flags `Multiplay`, `SmartAI`, `Color`, `ParentCountry`.
- **Country bonus data** — `VeteranInfantry/Units/Aircraft` and the `YYYZZZMult` family + `IncomeMult`.
- **Country-indexed art/text** — flags, loading screens, palettes (YR adds per-country `.pal`), CSF tooltips bound to list position; reordering countries breaks visuals unless art/text are remapped.

### C6. Power, auras, and status effects

- **Negative power / drain** — Floating Disc powers down enemy bases and disables individual powered defenses; Force Shield powers down the caster centrally.
- **Power-gated units** — Robot Tank (RCC + power), Psychic Tower/Cannon (power loss disables).
- **Credit siphon** — per-tick resource transfer from victim refinery to attacker.
- **Berserk status** — temporary allegiance override (attack own side) with damage buff and refresh-on-contact.
- **Poison residue** — persistent damaging area left by Virus kills.
- **Heal/repair auras** — Tech Hospital auto-heals infantry and Tech Machine Shop auto-repairs vehicles map-wide (RA2 required entry). Yuris's Slave Miner self-repair while mobile.

### C7. Terrain, weather, lighting

- **Lunar theater** — Moon mission tileset/palette, low gravity `[uncertain physics]`, no conventional aircraft, Cosmonaut-only infantry presence.
- **Retained theaters** — temperate, snow, urban, desert; YR adds new urban/snow art and per-map `Theater=`.
- **Cinematic scripting** — mission-specific lighting/weather and cutscene triggers (RA2 primitive, reused in YR).
- **No dynamic day/night cycle** in gameplay.

### C8. Game modes & meta

- **Team Alliance** added; Siege removed; Battle/Megawealth/Land Rush/Meat Grind/Naval War retained; `cooperative` token added.
- **Unholy Alliance** community 2v2 format.
- **10-country skirmish** with side mixing.

### C9. Balance / rebalance deltas

- Tanya `$1000`→`$1500` + C4-on-vehicles + mind-control immune; Navy SEAL to MP; Rhino build speed buff; Service Depot sell removed; `Industrial Plant` discount; Yuri's weak air and average armour as explicit faction weaknesses.

---

## D. Campaign structure

- **Two campaigns, 7 missions each** — Allied and Soviet. No Yuri campaign.
- **Allied arc** — time-travel back to WWIII → destroy the Alcatraz Dominator under construction → Hollywood (Grinder funding) → Seattle (nuclear silo/genetics) → Egypt (rescue Einstein) → Sydney (clone facility) → London (treaty defense) → Antarctica final (capture Soviet base, radar, Chronosphere MCV in, destroy final Dominator).
- **Soviet arc** — hijack the time machine (dinosaur prologue) → San Francisco Dominator → "Operation: Deja Vu" (Black Forest, destroy Einstein lab/Chronosphere) → London → Morocco (rescue Romanov) → South Pacific submarine/rocket base → "To the Moon" (lunar base) → Transylvania castle (destroy Psychic Beacons, liberate mind-controlled Allied+Soviet bases) → Yuri escapes into time, stranded in the Cretaceous.
- **Mission scripting deltas from RA2**
  - Same trigger/teamtype/taskforce/script INI model, extended with YR superweapon effects and mind-control/ownership changes.
  - Whole-base mind control via Psychic Beacons; the player reclaims pre-built bases.
  - Vehicle/hero set-pieces (Boris/MiGs, Tanya), timed defense holds, and no-base commando missions.
  - One-off units and map rules: T-Rex scripted encounter, Cosmonaut + lunar map (no air), low gravity.
  - Objectives delivered via EVA and cinematic briefings; new Yuri EVA/hero VO.
- **Objectives/triggers/taskforces** — YR missions are denser in scripted events per minute than RA2 (shorter campaigns), with more `owned-by-change` actions and fewer build-and-destroy-only objectives.
- **No campaign co-op shipped**; the `cooperative` mode token exists for map authors/CnCNet.

---

## E. YR vs RA2 delta list

- **Factions**: 2 sides / 9 countries → 3 sides / 10 countries (`ThirdSide`, `YuriCountry`).
- **Playable campaigns**: RA2 12+12 → YR 7+7; Yuri has no campaign.
- **New side roster**: full Yuri structure/unit/infantry/naval/air set (Section B).
- **New Allied items**: Guardian GI, Robot Tank, Robot Control Center, Battle Fortress; Navy SEAL MP; Tanya buff; Force Shield; IFV table.
- **New Soviet items**: Boris, Siege Chopper, Industrial Plant, Battle Bunker, Spy Plane; lost Psi-Corps, Cloning Vats, Psychic Sensor.
- **Mind control**: single-target RA2 (Psi-Corps, Psi Commando, Psychic Beacon) → multi-target, permanent Dominator, building control, Tower auto-control, Mastermind overflow.
- **Gattling weapon system**: absent → added (Tank + Cannon).
- **Tank Bunker / Battle Bunker**: absent → added (`Bunker=yes`).
- **Economy**: ore miner + refinery → slave-based economy, Grinder recycling, credit siphon, Industrial Plant discount, `IncomeMult`.
- **Superweapons**: Nuke/Iron Curtain/Chronosphere/Weather Storm/Spy Plane/ParaDrop → adds Psychic Dominator, Genetic Mutator, Force Shield, Psychic Reveal; YR adds global build notification contract.
- **Tech buildings**: Hospital/Machine Shop effects globalized; Civilian Power Plant + Secret Lab (+ random special unit) formalized.
- **Power model**: adds negative power/drain (Floating Disc), power-gated mobile units, Force Shield self-power-down.
- **Status effects**: adds berserk gas, poison residue, genetic mutation/capture.
- **Multiplayer modes**: Siege → Team Alliance; `cooperative` token added.
- **Data/modding**: single exe+INI → `ra2md.exe` + `md` INI family (full replacements); new flags; per-country palettes; `Lunar` theater; `.yrm` map format.
- **Audio**: new Klepacki tracks, Yuri EVA/unit VO.
- **Patch 1.001**: balance + deploy-exploit guard + Service Depot sell removal.

---

## F. Unified-engine implications

**Generic systems vs YR data**
- Mind control, garrisoning, superweapons, power, economy hooks, status effects, faction/side registry, and multi-stage weapons are **generic systems**; the specific values (Psychic Tower range, Dominator cooldown, Grinder refund, Slave Miner slots, country multipliers) are **YR data**.
- Yuri's "psychic" flavour is entirely data: a `MindControl` ability + a `Type=PsychicDominator` superweapon + auras. No YR-only engine concept is needed beyond the generic abilities.
- TS/FS must be expressible with the same primitives: Ion Cannon/EMP/Firestorm/Drop Pod map onto the superweapon framework; GDI/Nod onto the side registry; Tiberium harvesting onto the same economy component as Slaves.

**What the engine must abstract**
- **Side/house registry** — N sides, country→side mapping, per-country bonus data, colour/icon/voice binding.
- **Ownership override subsystem** — a control-link manager (capacity, immunity, permanent vs temporary, release on death/power-loss/overflow, neutral fallback) with a serializable graph.
- **Garrison/occupancy subsystem** — occupants in buildings and transports, fire-from-inside, bunker stat bonuses, power hook (Bio Reactor), repair/enter/exit orders.
- **Superweapon/support-power framework** — per-player charging, area/line/no-target modes, global reveal+timer contract, pluggable type behaviours (Damage, Capture, Convert, Invulnerable, Reveal, Paradrop).
- **Weapon state machine** — staged/gattling weapons, elite variants, target-type filtering, dummy stages.
- **Resource/economy hooks** — refund/recycle, per-tick siphon, cost/build-time modifiers, income multipliers, discount auras.
- **Power system extensions** — negative power, per-unit power dependency, forced blackout from an external source.
- **Entity conversion/transform** — deploy/undeploy, mutate unit→unit, with ownership and control-link transfer.
- **Aura/radius system** — heal, repair, sensor/reveal, mind control, berserk, slow/status, applied per tick.
- **Status-effect framework** — timed allegiance overrides, damage-over-time residue, immunity flags.
- **Theater/terrain registry** — theater definition (tileset, palette, hazards, gravity/air rules), per-map override.
- **Veterancy/rank promotion** — shared across titles (RA2/YR ranks; TS/FS ranks).
- **Mission script runtime** — triggers, taskforces, teamtypes, ownership/objective actions, cinematic control.
- **Game-mode registry** — skirmish modes, team setups, optional co-op flag, map `GameModes` metadata.

**Migration notes for ReSun**
- Existing `FactionCatalog`/`GameContext` must grow from "one house" to "side → countries → bonuses".
- Existing Transport/Dock components are the seed for the garrison subsystem (Battle Fortress, Bunkers, Bio Reactor).
- `ProductionManager`/`PrerequisiteSystem`/`PowerGrid`/`RadarSystem`/`ShroudSystem` are the hosts for the superweapon framework, power gating, Psychic Radar, and reveal powers.
- `EconomyManager` needs refund/siphon/modifier hooks for Grinder/Floating Disc/Industrial Plant.
- A new **controller/control-link manager** and a **weapon state machine** are the only genuinely new subsystems.

---

## Three-way comparison (mechanism | TS/FS | RA2 | YR)

| Mechanism | TS/FS | RA2 | YR |
|---|---|---|---|
| Sides | 2 (GDI/Nod) + mutants | 2 sides / 9 countries | 3 sides / 10 countries (ThirdSide) |
| Mind control | none | single-target (Psi-Corps, Beacon) | multi-target, permanent Dominator, building control, Tower, Mastermind overflow |
| Garrison | none | civilian buildings only | + buildable Battle/Tank Bunkers, fire-from-transport |
| Superweapons | Ion Cannon, EMP, Multi-Missile, Hunter-Seeker, Firestorm | Nuke, Iron Curtain, Chronosphere, Weather Storm, Spy Plane, Paradrop | + Psychic Dominator, Genetic Mutator, Force Shield, Psychic Reveal |
| Economy | Tiberium harvester/refinery | ore miner/refinery, oil derrick | + Slave Miner/slaves, credit siphon, Grinder recycle, Industrial Plant discount |
| Power | plants, base blackout | plants, base blackout | + negative/drain power, power-gated units, Bio Reactor garrison fuel |
| Multi-stage weapons | none | charge-turret only | Gattling spin-up system |
| Aircraft | Orca/Banshee/Carryall | jets + helis | + Floating Disc, Siege Chopper, MiG strike |
| Terrain | temperate/snow + tiberium | temperate/snow/urban/desert | + Lunar theater |
| Status effects | EMP, tiberium | none major | berserk gas, poison residue, mutation, mind control |
| Conversion | cyborgs/CABAL (FS lore) | deploy/undeploy | + mutate infantry→Brute, permanent capture |
| Data files | rules.ini/art.ini | rules.ini/art.ini | separate `ra2md.exe` + `rulesmd.ini`/`artmd.ini` (full replacements) |
| Game modes | skirmish | Battle/Team/Siege/Megawealth/LandRush/MeatGrind/NavalWar | replaces Siege with Team Alliance; adds co-op token |

---

## Systems that MUST be generic engine subsystems

1. **Side/faction registry** with side→country→bonus data (not per-game code).
2. **Ownership-override / mind-control link manager** (capacity, immunity, permanent, release).
3. **Garrison/occupancy subsystem** (buildings, transports, bunkers, fire-from-inside, power hook).
4. **Superweapon/support-power framework** (charge, targeting modes, pluggable effects, global timer).
5. **Weapon state machine** (staged/gattling, elite variants, target-type filters).
6. **Power system** (supply/demand, negative power, per-unit dependency, forced blackout).
7. **Economy hooks** (refund, siphon, cost/build/income modifiers, discount auras).
8. **Entity conversion/transform** (deploy/undeploy/mutate) with control-link and ownership transfer.
9. **Aura/radius system** (heal, repair, reveal, control, status).
10. **Status-effect framework** (timed allegiance override, DoT residue, immunities).
11. **Theater/terrain registry** (tileset, palette, gravity/air rules, per-map override).
12. **Veterancy/rank promotion** shared across all titles.
13. **Mission script runtime** (triggers, taskforces, ownership/objective actions, cinematics).
14. **Game-mode registry** (skirmish modes, teams, co-op flag, map metadata).
