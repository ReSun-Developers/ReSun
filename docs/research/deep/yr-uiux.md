# Yuri's Revenge — UI/UX, Presentation & Campaign/Meta Deltas vs Red Alert 2

> **Subject:** *Command & Conquer: Red Alert 2 — Yuri's Revenge* (Westwood Pacific / EA, NA 2001-10-09; latest patch 1.001).
> **Purpose:** Exhaustive, web-researched reference of every UI/UX, presentation, campaign and meta **addition or change** that YR introduces over base Red Alert 2 — for the unified ReSun engine (TS / Firestorm / RA2 / YR).
> **Method:** Web only. Authoritative + open-engine sources: ModEnc, cnc.fandom / cnc-central.fandom, CNCNZ, Project Perfect Mod, CnCNet forums, StrategyWiki, Ares docs, Wikipedia. Every claim cross-checked against ≥2 sources where possible; conflicts flagged.
> **Not read:** No local game files or prior local research docs were read for this document. All content is derived from the cited web sources.
> **Confidence legend:** **High** = ≥2 independent authoritative/modding sources agree; **Med** = single strong source, or agreement with a caveat; **Low** = inference or single circumstantial source.
> **Data keys** are modder-facing INI section/flag names (prose reference only; no code blocks), useful for the future data-driven port.

---

## 0. Packaging & Runtime Foundation (meta context for every later delta)

### YR-UI-001 Separate Executable and "md" Data Tree
**What:** YR is not a patch of RA2 — it ships as a separate executable (`ra2md.exe`) and a parallel data tree. Every RA2 file it reuses gets an `md` ("Mission Disk") suffix: `rules.ini` → `rulesmd.ini`, `art.ini` → `artmd.ini`, `ai.ini` → `aimd.ini`, and so on. YR's INI files are complete replacements, not overrides of RA2's.
**Data keys:** `rulesmd.ini`, `artmd.ini`, `aimd.ini`; autoload of `md`-suffixed MIX archives (`*MD.MIX`).
**Numbers:** YR requires RA2 patched to v1.006; YR latest patch 1.001; release NA 2001-10-09, AU 2001-10-10, EU 2001-10-19.
**Edge cases:** Because `md` files fully replace their RA2 counterparts, a modder must copy before editing; MIX loading prefers `*MD.MIX` so identical asset names resolve to the YR version when present.
**Kind:** Packaging / runtime.
**Sources:** https://modenc.renegadeprojects.com/Yuri%27s_Revenge ; https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge
**Confidence:** High.

### YR-UI-002 Campaign Game-Speed Slider
**What:** YR adds a `-SPEEDCONTROL` command-line switch that makes the Game Speed slider visible in the Game Controls (pause) window during **campaign** missions. In both RA2 and YR, that slider is normally only available outside campaign (skirmish/multiplayer).
**Data keys:** command-line `-SPEEDCONTROL`; Game Controls window "Game Speed".
**Numbers:** N/A (a UI unlock toggle).
**Edge cases:** Off by default; only affects the pause menu's control set, not per-mission scripting.
**Kind:** UI / options.
**Sources:** https://modenc.renegadeprojects.com/Yuri%27s_Revenge (Command Line Arguments)
**Confidence:** High.

---

## 1. UI Deltas vs RA2

### YR-UI-010 Third Sidebar / Yuri Side-Specific GUI
**What:** Yuri is the first fully distinct third faction in a C&C game and gets its own GUI treatment. In unmodded YR the game exposes (at most) **two** complete sidebar skins — the Allied sidebar and the Soviet sidebar — and Yuri **reuses the Soviet sidebar art** with a **distinct radar/minimap look**. Modders attempting a truly unique third sidebar in stock YR report that editing the Soviet sidebar (`sidec02`) also changes Yuri's, "except for the radar"; a genuinely separate third sidebar required external tools (RockPatch/NPSE/Ares) or an exe hack (as Tiberian Sun mods had done).
**Data keys:** side-specific GUI referenced by a country's `Side=` (GDI / Nod / ThirdSide); `sidec01` / `sidec02` sidebar graphics; Yuri radar variant.
**Numbers:** 3 sides (`GDI`, `Nod`, `ThirdSide`); 2 full sidebar skins in stock YR; Yuri = Soviet skin + unique radar.
**Edge cases:** The forum topic is titled "3 unique sidebars" but the thread's own findings contradict that for Yuri — treat "3 unique sidebars in vanilla YR" as **false**; Yuri is side-distinct but sidebar-art-sharing.
**Kind:** UI / art.
**Sources:** https://ppmforums.com/topic-40832/3-unique-sidebars-in-unmodded-yuris-revenge ; https://modenc.renegadeprojects.com/Countries
**Confidence:** Med (forum-confirmed, single community source; the negative claim is consistent with ModEnc's `Side=` model).

### YR-UI-011 New and Modified Cameos (all YR content)
**What:** Every YR unit, structure, support power and superweapon has a sidebar cameo. The wiki hosts dedicated cameo categories: **231** YR cameo files total, of which **50** are Yuri-faction cameos. New RA2-faction content, Yuri content, and support-power/superweapon icons all require new cameos. The Psychic Dominator and Genetic Mutator pages show localised icon variants (French, Korean, Chinese) — cameo strings/art are localisation-swapped like the rest of the UI.
**Data keys:** cameo field in `art(md).ini`; cameo `.shp` / `.pcx`; support-power and superweapon button art.
**Numbers:** ~231 YR cameos total; 50 Yuri cameos (wiki categories, includes multi-language duplicates).
**Edge cases:** The exact "new vs reused" split is not cleanly countable from the wiki because the category includes re-renders and localisations; treat 231/50 as asset-inventory counts, not a delta count.
**Kind:** UI / art.
**Sources:** https://cnc.fandom.com/wiki/Category:Yuri%27s_Revenge_cameos ; https://cnc.fandom.com/wiki/Category:Yuri%27s_Revenge_Yuri_cameos ; https://cnc-central.fandom.com/wiki/Psychic_dominator (icon gallery)
**Confidence:** High for "new cameos exist"; Med for the exact counts.

### YR-UI-012 Mind-Control Feedback (colour + pips)
**What:** YR formalises visual feedback for mind control. A new `PipScale=MindControl` value draws one pip per controlled object on the controller. Captured units are re-coloured/selected as belonging to the controlling player (standard house-colour and selection-box feedback), and a permanent `Type=PsychicDominator` capture is irreversible (the wiki states a Dominator-captured unit "can never be mind-controlled or released again"), which is not distinguishable in the UI from ordinary control except by provenance.
**Data keys:** `PipScale=MindControl`; `pips2.shp` (units) / `pips.shp` (buildings); warhead `MindControl=yes`; `InfiniteMindControl=`.
**Numbers:** Pips drawn = the **Damage** value of the firing unit's **Primary** mind-control weapon (Elite weapon Damage is ignored); Mastermind = 3; Psychic Tower = 3; Yuri Clone = 1; Yuri Prime = 1 (but can control buildings).
**Edge cases:** `PipScale=MindControl` with `Primary=none` → Internal Error `007162B6`. Very large `Damage`, `GuardRange`, `Range` or `SpawnsNumber` on a mind-control unit causes severe slowdowns. `PipScale=MindControl` cannot use `CellSpread`/sub-weapons. Mind-control parasites in YR draw a link from the target back to the **map point where the parasite entered**, not to the parasite (fixed only in Ares).
**Kind:** UI feedback / art.
**Sources:** https://modenc.renegadeprojects.com/PipScale ; https://modenc.renegadeprojects.com/MindControl ; https://cnc-central.fandom.com/wiki/Psychic_dominator
**Confidence:** High.

### YR-UI-013 Mind-Control Overload / Capacity Pips
**What:** When a controller with `InfiniteMindControl=yes` exceeds its declared pip capacity, YR draws an extra "overload" pip. Mastermind-style multiple control is the YR extension of RA2's one-target mind control (`Damage>1` preserves existing links after reaching the limit; at the limit no new target can be captured until one is freed).
**Data keys:** `PipScale=MindControl` + `InfiniteMindControl=yes`; `pips2.shp` frame 5 = overload pip (briefly frame 4 on `OverloadDamage`-specified hits, buildings use `pips.shp`).
**Numbers:** Overload pip = extra pip beyond the weapon's Damage; pips = capacity.
**Edge cases:** The Mastermind self-destructs if it exceeds its limit before the player disposes of a controlled unit — the pip count is the player's only capacity readout.
**Kind:** UI feedback.
**Sources:** https://modenc.renegadeprojects.com/PipScale ; https://cncnz.com/games/yuris-revenge/yuris-units (Master Mind)
**Confidence:** High.

### YR-UI-014 Passenger / Absorb Pips for Bunkers and Grinder
**What:** YR extends `PipScale=Passengers` to buildings using `UnitAbsorb=yes` / `InfantryAbsorb=yes` (e.g. Battle Bunker, Tank Bunker, Bio Reactor, Grinder-style storage). Absorbed vehicles use `pips.shp` frame 5, absorbed infantry frame 4; occupancy for garrisonable structures is a separate mechanism (`MaxNumberOccupants`).
**Data keys:** `PipScale=Passengers`; `UnitAbsorb=`, `InfantryAbsorb=`; `MaxNumberOccupants`; `pips.shp` / `pips2.shp`.
**Numbers:** Yuri Bio Reactor = 5 infantry slots (+100 power each); Battle Bunker = 5 infantry slots; Battle Fortress = 5 firing infantry slots.
**Edge cases:** Passenger pips override ammo pips; defining both distorts the pip row (ModEnc documents the exact failure). Occupancy pips ≠ passenger pips and use a different flag.
**Kind:** UI feedback.
**Sources:** https://modenc.renegadeprojects.com/PipScale ; https://cncnz.com/games/yuris-revenge/yuris-structures (Bio Reactor)
**Confidence:** High.

### YR-UI-015 Garrison / Bunker Enter-Exit Cursors and Orders
**What:** YR expands garrisoning. Civilian structures and the new **Battle Bunker** (infantry, fire from inside) and Yuri **Tank Bunker** (turreted non-artillery vehicles, +armour, +rate of fire, immobilised) are enterable. Hovering a garrisonable building shows an enter cursor; issuing the move onto it loads the occupant, and the standard ungarrison/deploy order ejects them. Yuri's `Tank Bunker` is the first structure that garrisons *vehicles*.
**Data keys:** building `CanBeOccupied=` / `MaxNumberOccupants=`; infantry `Occupier=yes`; `UnitAbsorb`/`InfantryAbsorb`; `UndeploysInto` interactions.
**Numbers:** Battle Bunker 5 infantry; Yuri Tank Bunker (turreted vehicles); Bio Reactor 5 infantry; Grinder recycles any controlled unit for a cost refund.
**Edge cases:** RA2 mind-controlled infantry could **not** garrison (`Occupier=yes` was rendered inert under control); YR retains that base behaviour. Garrisoned units are immune to both Psychic Dominator and Genetic Mutator. `MindControl` + `DeploysInto/UndeploysInto` can permanently change owner; YR 1.001 added a `ConstructionYard=yes` check to block mind-controlled MCV deploy/undeploy.
**Kind:** UI / controls.
**Sources:** https://modenc.renegadeprojects.com/MindControl ; https://cncnz.com/games/yuris-revenge/yuris-structures ; https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge (Battle Bunker)
**Confidence:** Med (exact cursor glyphs not found in a citable source; behaviour is well-sourced).

### YR-UI-016 Support-Power and Superweapon Sidebar Buttons
**What:** YR adds a class of **support powers** that appear as sidebar buttons with their own recharge timers (in addition to RA2's superweapons). These are what the sidebar shows beyond unit/structure cameos. All factions get Force Shield after a Battle Lab; Soviets get the Spy Plane (Radar Tower); Yuri gets Psychic Reveal, Mutation and Domination.
**Data keys:** `SuperWeaponTypes` section; `Type=` values; power recharge and prerequisites.
**Numbers:** Psychic Reveal 4:00; Force Shield 5:00; Mutation 5:00; Domination 10:00 (Psychic Dominator build 3:20, Genetic Mutator build 1:40). RA2 superweapons: Chronosphere / Weather Control / Iron Curtain / Nuclear Missile.
**Edge cases:** Force Shield and Psychic Dominator both cost the base its power temporarily when fired; Force Shield blocks even superweapon damage. A Spy can reset any superweapon timer.
**Kind:** UI / gameplay.
**Sources:** https://cncnz.com/games/yuris-revenge/yuris-structures ; https://cnc-central.fandom.com/wiki/Psychic_dominator ; https://cnc.fandom.com/wiki/Force_Shield
**Confidence:** High.

### YR-UI-017 Superweapon Global Reveal + Shared Timer
**What:** When a Yuri superweapon (Genetic Mutator or Psychic Dominator) finishes construction, **all players are notified** and the shroud above the device is removed, with a **timer visible to all players**. YR's Yuri superweapons are capped at one each per player ("only 1 may be built at a time").
**Data keys:** superweapon "detected" announcement + shroud removal + countdown; `Only 1 per player` cap on Genetic Mutator / Psychic Dominator (and Cloning Vat / Yuri Prime).
**Numbers:** Built-time and cooldown shown in sidebar; Genetic Mutator 5:00, Psychic Dominator 10:00.
**Edge cases:** Unlike other superweapons there is **no EVA announcement when the Psychic Dominator is fired** (wiki trivia) — the *detected* notification is distinct from the *fired* notification.
**Kind:** UI / meta.
**Sources:** https://cnc-central.fandom.com/wiki/Psychic_dominator ; https://cncnz.com/games/yuris-revenge/yuris-structures
**Confidence:** Med-High (explicit on the Psychic Dominator/Genetic Mutator pages; cross-referenced by CNCNZ).

### YR-UI-018 Skirmish Lobby: the 10th Country (Yuri)
**What:** YR adds a tenth playable skirmish/multiplayer country, `YuriCountry` (index 9, `Side=ThirdSide`, `Multiplay=yes`). The country-select list is built in the order of the `[Countries]` section (not hardcoded), with `Multiplay=yes` deciding visibility.
**Data keys:** `[Countries]` index 9 = `YuriCountry`; `[Sides]` `ThirdSide=YuriCountry`; `UIName` (CSF) tooltip; `Multiplay=`, `MultiplayPassive=`, `SmartAI=`.
**Numbers:** 9 RA2 countries + 1 Yuri = **10** multiplayer countries; `[Countries]` entries 0–13 include unplayable `GDI`/`Nod`/`Neutral`/`Special` placeholders.
**Edge cases:** The loader comments warn that the "major 9 houses" must stay first and uninterrupted or the game crashes; Yuri's country must follow the 9 Allied/Soviet entries.
**Kind:** UI / meta.
**Sources:** https://modenc.renegadeprojects.com/Countries
**Confidence:** High.

### YR-UI-019 Skirmish Team Setup (allies/teams in lobby)
**What:** YR's skirmish lobby adds the ability to set **teams / choose allies**; base RA2 skirmish did not offer the same team options. CnCNet's "RA2 mode" restores the older RA2 lobby behaviour for players who want it.
**Data keys:** multiplayer team/ally assignment in the game-mode setup (distinct from the `teamgame` mode flag).
**Numbers:** N/A.
**Edge cases:** Community guidance explicitly says "Play Yuri's Revenge for team options in skirmish," confirming the delta is YR-only.
**Kind:** UI / meta.
**Sources:** https://steamcommunity.com/app/2229850/discussions/0/4364628673434334025 ; https://cncnet.org/yuris-revenge
**Confidence:** Med.

### YR-UI-020 Country Loading Screens and Flags (index-bound)
**What:** Each country has a hardcoded flag and 800×600 loading screen bound to its **index** in `[Countries]`, plus a loading-screen text triplet (special-unit name, unit description, country name). YR adds index 9 (Yuri) with its own flag (`yrii.pcx`), loading screen (`ls800yuri.shp`) and palette (`mpyls.pal`). The wiki lists **18** YR mission loading screens in their own category.
**Data keys:** country `UIName`; CSF strings `stt:playerside*`, `name:*`, `loadbrief:*`, `name:<country>`; flag `.pcx` / loading `.shp` / `.pal`.
**Numbers:** YR country index table:

| Index | Country | Flag | Loading screen | Palette |
|---|---|---|---|---|
| 0 | Americans | usai.pcx | ls800ustates.shp | mplsu.pal |
| 1 | Alliance (Korea) | japi.pcx | ls800korea.shp | mplsk.pal |
| 2 | French | frai.pcx | ls800france.shp | mplsf.pal |
| 3 | Germans | geri.pcx | ls800germany.shp | mplsg.pal |
| 4 | British | gbri.pcx | ls800ukingdom.shp | mplsuk.pal |
| 5 | Africans (Libya) | djbi.pcx | ls800libya.shp | mplsl.pal |
| 6 | Arabs (Iraq) | arbi.pcx | ls800iraq.shp | mplsi.pal |
| 7 | Confederation (Cuba) | lati.pcx | ls800cuba.shp | mplsc.pal |
| 8 | Russians | rusi.pcx | ls800russia.shp | mplsr.pal |
| 9 (YR only) | YuriCountry | yrii.pcx | ls800yuri.shp | mpyls.pal |

**Edge cases:** Both art and text are index-bound, not name-bound — reordering `[Countries]` silently re-skins and re-labels every country. YR is the first game in the pair where the loading palette is per-country (RA2 shares `mpls.pal`).
**Kind:** UI / presentation.
**Sources:** https://modenc.renegadeprojects.com/Countries ; https://cnc.fandom.com/wiki/Category:Yuri%27s_Revenge_mission_loading_screens
**Confidence:** High.

### YR-UI-021 Game-Mode Selection: Team Alliance replaces Siege
**What:** YR's multiplayer mode list changes: the obsolete **Siege** mode is replaced by **Team Alliance** (`teamgame`). A `cooperative` token exists for Co-Op Campaign.
**Data keys:** map `GameModes=` list; supported tokens.
**Numbers:** supported modes and semantics:

| Token | Mode | Availability |
|---|---|---|
| standard | Normal "Battle" | RA2 + YR |
| teamgame | **Team Alliance** | **YR only** |
| megawealth | Megawealth | RA2 + YR |
| duel | Land Rush | RA2 + YR |
| meatgrind | Meat Grind | RA2 + YR |
| navalwar | Naval War | RA2 + YR |
| cooperative | Co-Op Campaign | RA2 + YR (may not work on standard MP maps) |
| siege | Siege | **Obsolete** — replaced by Team Alliance in YR |

**Edge cases:** The `GameModes=` flag itself was added for Final Alert 2 / RA2 v1.005+, so the token set is map metadata; "Team Alliance" maps (e.g. Turfwar) are flagged `teamgame`.
**Kind:** UI / meta.
**Sources:** https://modenc.renegadeprojects.com/GameModes ; https://cnc.fandom.com/wiki/Turfwar
**Confidence:** High.

### YR-UI-022 Tech-Building Capture UI Expansion
**What:** Capturable tech buildings are expanded, changing what the capture UI can grant. New/modified: Tech Hospital (now heals all friendly infantry on the map automatically), Tech Machine Shop (auto-repairs all friendly vehicles), Tech Civilian Power Plant, Tech Secret Lab (grants country-specific technology), plus the existing Tech Airport (paratroopers), oil derricks, etc.
**Data keys:** tech-building capture; country `TechLevel`; Secret Lab unlock table.
**Numbers:** Four new/modified categories per Wikipedia; RA2 already had tech buildings and oil derricks.
**Edge cases:** Tech Hospital changed from "enter to heal" to a global aura — a UI-behaviour change for the same building name.
**Kind:** UI / gameplay.
**Sources:** https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge ; https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge
**Confidence:** High.

### YR-UI-023 Psychic Radar / Attack-Order Reveal UI
**What:** Yuri's **Psychic Radar** replaces the Soviet Psychic Sensor's role and unlocks the radar display plus the Psychic Reveal support power. It shows the **orders/targets** of enemy units planning to attack friendly units within radius, and uncovers enemy Spies.
**Data keys:** building `PsychicDetectionRadius`-style behaviour; radar + reveal power; `Type=PsychicReveal`.
**Numbers:** Yuri Psychic Radar cost $1000, -50 power, requires Slave Miner; Psychic Reveal cooldown 4:00.
**Edge cases:** Disabled at low power (radar and reveal both); this is UI information, not a weapon.
**Kind:** UI / gameplay.
**Sources:** https://cncnz.com/games/yuris-revenge/yuris-structures ; https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge
**Confidence:** High.

---

## 2. EVA (Announcer) Deltas

### YR-UI-030 Third EVA Voice Set: the Yuri Announcer
**What:** YR introduces a **third EVA voice set** — the "Yuri Announcer" — used by the Yuri faction, voiced with a pronounced (East-European-inflected) accent. The comparison/video documentation groups EVAs as: Allied Lt. Eva Lee (RA2/YR), Soviet Lt. Zofia (RA2), and the **Yuri Announcer (YR)**.
**Data keys:** EVA line set selected by `Side=` (`GDI`/`Nod`/`ThirdSide`); per-side voice-sound bank.
**Numbers:** 3 side EVA identities in YR (Allied female, Soviet female, Yuri male-style announcer).
**Edge cases:** Community reaction to the strong Yuri accent is a known talking point; it is intentional characterisation, not a localisation glitch.
**Kind:** Audio / presentation.
**Sources:** https://www.youtube.com/watch?v=LMTpw5RUmaU (C&C EVA Voice Comparison — lists "Yuri Announcer (YR)") ; https://www.reddit.com/r/commandandconquer/comments/1bsbj8v/bruh_the_yuri_evas_accent_is_so_strong
**Confidence:** Med (video + community; no canonical line transcript found).

### YR-UI-031 Faction-Specific EVA Wording for Shared Powers
**What:** The same generic support power is announced differently per side EVA: the Allies call the Battle-Lab power "Force Shield," while the Soviet EVA calls it an "energy shield." The Yuri EVA has its own register. This is a presentation delta on top of the shared mechanic.
**Data keys:** per-side EVA string/sound overrides for the `ForceShield` type.
**Numbers:** N/A.
**Edge cases:** The underlying mechanic is identical for all three sides; only the announcement differs.
**Kind:** Audio / presentation.
**Sources:** https://en.namu.wiki/w/포스%20실드 (Force Shield — EVA naming per faction) ; https://cnc.fandom.com/wiki/Force_Shield
**Confidence:** Med (NamuWiki only; consistent with the known per-side EVA model).

### YR-UI-032 New EVA Warning Lines
**What:** YR adds EVA warnings for the new superweapons/powers, e.g. **"Warning — Genetic Mutator has been detected!"** New content therefore carries new announcer lines on top of the reused RA2 line set.
**Data keys:** EVA event hooks for new superweapon detection and support powers.
**Numbers:** Not enumerated in sources; the Genetic Mutator line is confirmed verbatim.
**Edge cases:** A *detected* warning fires on construction/reveal; a *fired* announcement is absent for the Psychic Dominator.
**Kind:** Audio / presentation.
**Sources:** https://cnc-central.fandom.com/wiki/Genetic_mutator ; https://cnc-central.fandom.com/wiki/Psychic_dominator
**Confidence:** Med (individual lines confirmed; full list not compiled by any single source).

### YR-UI-033 No Psychic-Dominator Firing Announcement
**What:** Trivia confirmed by the wiki: unlike other superweapons, **there is no EVA announcement when a Psychic Dominator is activated**.
**Data keys:** superweapon fire sound hook (absent).
**Numbers:** N/A.
**Edge cases:** The "Genetic Mutator detected" style warning still exists for *detection*; the firing silence is specific to the Dominator.
**Kind:** Audio / presentation.
**Sources:** https://cnc-central.fandom.com/wiki/Psychic_dominator
**Confidence:** Med.

---

## 3. Unit Voices / Voice Sets

### YR-UI-040 Unique Voice Sets for All Unit Classes
**What:** YR's headline voice change: **all unit types get unique voice lines**. In RA2, only infantry and aircraft had unique lines while ground vehicles shared per-faction voices. YR gives vehicles their own sets.
**Data keys:** per-unit sound/Voice entries in `rulesmd.ini`/`artmd.ini`; `VoiceSelect`, `VoiceMove`, `VoiceAttack`, `VoiceFeedback`.
**Numbers:** Applies across all three factions; a community "voice sets" gist enumerates RA2/YR sets.
**Edge cases:** Some lines persist from RA2; the change is broad rather than a complete re-record.
**Kind:** Audio.
**Sources:** https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge ; https://gist.github.com/5ca9bae13810a17536f195cecbfb30ff
**Confidence:** High.

### YR-UI-041 Yuri Faction Voice Identity
**What:** Yuri's roster has a distinct, often theatrical voice identity (Initiate chants, mind-control-themed unit lines), consistent with the faction's psychic theme. CNCNZ characterises the faction as mind control + genetic mutation; the voices sell that theme.
**Data keys:** per-unit voice sets for `Initiate`, `Brute`, `Virus`, `Yuri Clone`, `Yuri Prime`, `Slave`, etc.
**Numbers:** Yuri roster: 6 trainable infantry + Slaves + campaign Cosmonaut; 7 vehicles; 1 aircraft; 2 ships.
**Edge cases:** Slaves are not directly controllable and have limited/no command lines; Cosmonaut exists only in the Moon mission.
**Kind:** Audio.
**Sources:** https://cncnz.com/games/yuris-revenge/yuris-units ; https://www.101soundboards.com/boards/22412-red-alert-2-soundboard
**Confidence:** Med.

### YR-UI-042 Boris — Soviet Hero VO
**What:** New Soviet commando **Boris** has dedicated hero voice work and ability barks, including his AKM fire, his laser-designator lock-on, and the MiG airstrike call. He replaces Yuri (the Psi-Corps trooper) as the Soviet commando.
**Data keys:** Boris infantry type; primary AKM weapon; secondary designator `Type=` that calls a MiG strike; per-ability voice.
**Numbers:** Boris $1500, Battle Lab prerequisite; immune to mind control; can one-v-one most ground units.
**Edge cases:** Boris is completely vulnerable/stationary while designating a target until the MiGs destroy it or he is re-ordered.
**Kind:** Audio / presentation.
**Sources:** https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge ; https://cncnz.com/games/yuris-revenge/new-soviet-units
**Confidence:** Med-High.

### YR-UI-043 Yuri Prime — Hero VO
**What:** **Yuri Prime** (Yuri himself, on a hovering chariot) is Yuri's hero: a stronger Yuri Clone with an improved psychic blast (kills infantry in an AoE, damages units just outside, **spares friendly units**), immunity to mind control, uncrushable, auto-regen, and the ability to mind-control buildings and most units/structures.
**Data keys:** Yuri Prime infantry type; improved psychic-blast weapon; building-targeting `ImmuneToPsionic=no` handling.
**Numbers:** $1500, Battle Lab; only one at a time per player unless a Cloning Vat is built.
**Edge cases:** Clones still damage friendly infantry with their blast (Yuri Prime does not); RA2's Psi-Corps trooper is removed from the Soviets and becomes the Yuri Clone.
**Kind:** Audio / presentation.
**Sources:** https://cncnz.com/games/yuris-revenge/yuris-units ; https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge
**Confidence:** Med-High.

---

## 4. Music

### YR-UI-050 YR Soundtrack (full track list)
**What:** Frank Klepacki composed 10 YR tracks. YR had **no physical soundtrack disc**; the track "Yuri Trailer Remix" (01:11) was used only in the 2001 trailer and is a remix of Phat Attack, Drok and Trance L. Vania.

| # | Track | Length |
|---|---|---|
| 1 | Drok | 02:36 |
| 2 | Bully Kit | 04:15 |
| 3 | Brain Freeze | 04:01 |
| 4 | Defend the Base | 04:26 |
| 5 | Phat Attack | 03:54 |
| 6 | Tactics | 04:59 |
| 7 | Trance L. Vania | 03:28 |
| 8 | Deceiver | 03:58 |
| 9 | Yuri's Revenge Credits | 01:50 |
| 10 | Yuri's Revenge Score | 01:50 |
| — | Yuri Trailer Remix (trailer only) | 01:11 |

**Data keys:** `[Music]` / theme list in `rulesmd.ini`; jukebox track IDs; mission loading theme.
**Numbers:** 10 in-game tracks + 1 trailer-only remix.
**Edge cases:** **Conflict:** one fan catalogue lists additional YR menu entries ("Options Theme" 1:50; "Score Theme" 1:50) that overlap with "Yuri's Revenge Credits"/"Score". Treat those as naming variants of the menu/credits cues, not extra tracks.
**Kind:** Audio.
**Sources:** https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2_soundtrack ; https://gamicus.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2_-_Yuri%27s_Revenge/Soundtrack ; https://www.frankklepacki.com/ost/vg/cnc-ra2-yr
**Confidence:** High for the core 10; Med for the trailer remix/menu naming.

### YR-UI-051 Menu / Score / Credits Themes
**What:** YR ships a menu/score cue and a credits cue distinct from the in-game tracks. RA2's "Jank" was used as the mission-loading theme; the wiki notes RA2 unused-on-disc tracks (Ready the Army, Probing, C&C In the House). YR's loading/menu assignment is less clearly documented.
**Data keys:** menu/score/credits theme IDs; loading theme.
**Numbers:** Credits 1:50; Score 1:50.
**Edge cases:** RA2 and YR share a random "jukebox" model; exact per-screen assignment for YR is not fully documented on the wiki.
**Kind:** Audio.
**Sources:** https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2_soundtrack ; https://forums.cncnet.org/topic/10695-ra2-classic-soundtrack-in-yr
**Confidence:** Low-Med.

### YR-UI-052 Dynamic / Contextual Music Behaviour
**What:** No documented dynamic-music system beyond RA2's random track rotation and per-screen themes; community mods add RA2 tracks into YR because YR's base set is smaller (10 vs RA2's 16 + 3 unlisted). 
**Data keys:** theme list, random playback.
**Numbers:** RA2 disc 16 tracks + 3 unlisted; YR 10 tracks.
**Edge cases:** No adaptive/compositional layering found in sources; treat "dynamic music" as **not** a YR feature unless contradicted.
**Kind:** Audio.
**Sources:** https://forums.cncnet.org/topic/10695-ra2-classic-soundtrack-in-yr ; https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2_soundtrack
**Confidence:** Low (negative claim).

---

## 5. Cutscenes / FMV

### YR-UI-060 FMV Structure
**What:** YR keeps RA2's live-action FMV architecture: an intro movie, a briefing movie per mission, in-mission **sidebar videos** (EVA/commanders talking), plus an ending. Both campaigns share the same actors and timeline-reset framing.
**Data keys:** mission `Briefing=` video; sidebar-message videos triggered by map scripts; intro/ending movies.
**Numbers:** 7 Allied + 7 Soviet mission briefings; intro + ending; numerous sidebar videos (the wiki lists 4–5 sidebar videos per early mission).
**Edge cases:** Sidebar videos are map-script-triggered (e.g. "Tanya killed", "when going back in time") and can differ per outcome.
**Kind:** Presentation / narrative.
**Sources:** https://cnc-central.fandom.com/wiki/Red_Alert_2_cutscenes ; https://cnc.fandom.com/wiki/Category:Yuri%27s_Revenge_transcripts
**Confidence:** High.

### YR-UI-061 YR Intro Cutscene
**What:** The intro shows DEFCON 2 at the White House; Yuri hijacks the briefing to announce his psychic-dominator network; President Dugan orders the Alcatraz airstrike; the device is temporarily powered down but Yuri activates the rest of the network.
**Data keys:** intro movie.
**Numbers:** N/A.
**Edge cases:** Sets the "Allies won RA2" assumption that the whole expansion hangs on.
**Kind:** Presentation / narrative.
**Sources:** https://cnc.fandom.com/wiki/Transcript:Yuri%27s_Revenge_introduction ; https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge
**Confidence:** High.

### YR-UI-062 Allied Campaign Mission + Briefing Table
| # | Mission | Setting / FMV focus |
|---|---|---|
| 1 | Time Lapse | San Francisco; time machine; Yuri taunts |
| 2 | Hollywood and Vain | Los Angeles; Grinder slaughter; celebrity cameos |
| 3 | Power Play | Seattle/Massivesoft; nuclear silo vs Allied superweapon |
| 4 | Tomb Raided | Egypt; rescue Einstein from the Pyramid |
| 5 | Clones Down Under | Sydney; cloning facility |
| 6 | Trick or Treaty | London; defend treaty, Yuri mind-controls Eva |
| 7 | Brain Dead | Antarctica; final Psychic Dominator; Yuri captured |
**Data keys:** mission briefing videos; per-mission sidebar videos; ending.
**Numbers:** 7 Allied missions.
**Edge cases:** The Allied ending merges timelines and swaps Carville into Yuri's role at the White House.
**Kind:** Campaign / presentation.
**Sources:** https://cnc-central.fandom.com/wiki/Red_Alert_2_cutscenes ; https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge
**Confidence:** High.

### YR-UI-063 Soviet Campaign Mission + Briefing Table
| # | Mission | Setting / FMV focus |
|---|---|---|
| 1 | Time Shift | Cretaceous detour; T-Rex; then San Francisco |
| 2 | Deja Vu | Black Forest; destroy Chronosphere (RA2's Mirage reversed) |
| 3 | Brain Wash | London; destroy Psychic Beacon, free Allied base |
| 4 | Romanov on the Run | Casablanca; rescue Romanov |
| 5 | Escape Velocity | Pacific island; submarine base; discover Moon rocket |
| 6 | To the Moon | Lunar theater; destroy Yuri's Moon base |
| 7 | Head Games | Transylvania; castle; Yuri time-travels and is eaten by a T-Rex |
**Data keys:** mission briefing videos; per-mission sidebar videos; ending.
**Numbers:** 7 Soviet missions.
**Edge cases:** `Deja Vu` is explicitly the Soviet-side version of RA2's Allied mission "Mirage".
**Kind:** Campaign / presentation.
**Sources:** https://cnc-central.fandom.com/wiki/Red_Alert_2_cutscenes ; https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge
**Confidence:** High.

### YR-UI-064 Sidebar (In-Mission) Videos
**What:** YR continues RA2's in-mission FMV sidebar messages. The wiki catalogues side-bar videos per mission spoken by Eva, Tanya, Einstein, Carville, Zofia, Romanov, Bing, Yuri, etc., including failure/outcome variants ("Tanya was killed", "mission failed cinematic", "when the Psychic Beacon was destroyed").
**Data keys:** map-scripted message events that play a video keyed to a named actor/scene.
**Numbers:** e.g. Allied Mission 1 has 4 sidebar videos (Eva/time machine, Eva+Tanya+Yuri, going back in time, Tanya killed).
**Edge cases:** Some sidebar videos are outcome-conditional and thus mission-state UI, not just briefing UI.
**Kind:** Presentation.
**Sources:** https://cnc-central.fandom.com/wiki/Red_Alert_2_cutscenes
**Confidence:** Med-High.

### YR-UI-065 YR Live-Action Cast
| Character | Actor |
|---|---|
| Yuri | Udo Kier |
| President Michael Dugan | Ray Wise |
| General Ben Carville | Barry Corbin |
| Lieutenant Eva Lee | Athena Massey |
| Special Agent Tanya Adams | Kari Samantha Wührer |
| Albert Einstein | Larry Gelman |
| Chairman Bing | Rick Ginn |
| Premier Alexander Romanov | Nicholas Worth |
| Lieutenant Zofia | Aleksandra Kaniak |
**Data keys:** actor metadata not in INI; mission video mapping.
**Numbers:** 9 credited live-action characters.
**Edge cases:** No Yuri-campaign FMVs exist (Yuri is the antagonist in both campaigns).
**Kind:** Presentation / narrative.
**Sources:** https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge ; https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge
**Confidence:** High.

### YR-UI-066 No Yuri Single-Player Campaign
**What:** Yuri is playable in multiplayer/skirmish and in cooperative missions but has **no single-player campaign**; this was a noted review weakness. A cooperative multiplayer campaign exists for all factions including Yuri.
**Data keys:** faction playable flag; cooperative mission set.
**Numbers:** Yuri coop missions 1–3; Alliance Coop Mission shared.
**Edge cases:** Coop missions are RA2-era assets re-used plus YR-specific maps; they do not have the FMV briefing chain of the main campaigns.
**Kind:** Campaign / meta.
**Sources:** https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge ; https://cnc.fandom.com/wiki/Category:Yuri%27s_Revenge_missions
**Confidence:** High.

---

## 6. Theaters, Palettes and Tilesets

### YR-UI-070 Lunar Theater
**What:** YR introduces the **Lunar** theater (`L`/`LUN`), the only theater with no vegetation/ore and a unique look, used for the Soviet "To the Moon" mission and Moon-based custom maps. Only infantry like the Cosmonaut and the Desolator can operate in the lunar environment; the Cosmonaut is the only unit apart from the Desolator that survives there.
**Data keys:** theater letter `L`; tile filetypes `LUN`/`MML`; MIX archives `LUNARMD.MIX`, `LUN.MIX`, `ISOLUN.MIX`, `ISOLUNMD.MIX`; `NewTheater=yes` char `L`.
**Numbers:** 7 total theaters (Generic, Temperate, Snow, Urban, Desert, NewUrban, Lunar); Lunar is YR-era.
**Edge cases:** Lunar terrain changes pathing/movement expectations for infantry vs tracked units; the mission is scripted around it.
**Kind:** Terrain / presentation.
**Sources:** https://modenc.renegadeprojects.com/Theaters ; https://cncnz.com/games/yuris-revenge/yuris-units (Cosmonaut)
**Confidence:** Med-High (ModEnc lists Lunar/mixes; Moon-mission gameplay from CNCNZ/Wikipedia).

### YR-UI-071 NewUrban Theater
**What:** YR adds **NewUrban** (`N`/`UBN`), a second urban tileset distinct from the RA2 Urban set, used for urban campaign maps (LA, Seattle, London, etc.). MIX archives `URBANNMD.MIX`, `UBN.MIX`, `ISOUBN.MIX`, `ISOUBNMD.MIX`.
**Data keys:** theater letter `N`; `NewTheater=yes` char `N`; `UBN` tile filetype.
**Numbers:** NewTheater characters: Generic G, Temperate T, Snow A, Urban U, Desert D, NewUrban N, Lunar L.
**Edge cases:** Existing buildings use `NewTheater=yes` and fall back to the generic `g`-suffixed art if a theater-specific variant is missing.
**Kind:** Terrain / presentation.
**Sources:** https://modenc.renegadeprojects.com/Theaters
**Confidence:** Med-High.

### YR-UI-072 Snow-Theater Variants for Yuri Assets
**What:** Yuri structures have explicit **Snow theater** art variants (the wiki galleries show "passive/charged Genetic Mutator in Snow Theater", Psychic Dominator in Snow Theater, etc.), confirming YR ships theater-specific art for the new faction.
**Data keys:** `NewTheater=yes` on Yuri building art; Snow (`A`) variants.
**Numbers:** At minimum, superweapons and core Yuri structures have snow variants.
**Edge cases:** Generic fallback applies; modders can extend via the Terrain Expansion.
**Kind:** Terrain / presentation.
**Sources:** https://cnc-central.fandom.com/wiki/Genetic_mutator ; https://cnc-central.fandom.com/wiki/Psychic_dominator
**Confidence:** Med.

### YR-UI-073 Per-Country Palettes (YR-only)
**What:** Loading-screen palettes are **country-specific only in YR**; in RA2 all countries share `mpls.pal`. YR adds `mpyls.pal` for Yuri. Each country index maps to its own palette (see table in YR-UI-020), giving every country a distinct loading-screen tint.
**Data keys:** per-country `.pal` bound to `[Countries]` index; `mpls*.pal` / `mpyls.pal`.
**Numbers:** 9 RA2 palettes (mplsu/k/f/g/uk/l/i/c/r) + 1 YR (`mpyls.pal`).
**Edge cases:** Index-bound, so any reordering of `[Countries]` mis-assigns palettes.
**Kind:** Presentation.
**Sources:** https://modenc.renegadeprojects.com/Countries
**Confidence:** High.

---

## 7. New Visual FX

### YR-UI-080 Mind-Control Link Beam
**What:** A visible link/animation is drawn from a mind-controller to its target. In YR, mind-control *parasites* incorrectly draw the link to the map point where the parasite entered the unit rather than to the parasite — proving the link is a world-space beam effect tied to entry point.
**Data keys:** warhead `MindControl=yes`; link render; parasite entry point.
**Numbers:** One link per controlled object (Mastermind can hold links to multiple).
**Edge cases:** Link is severed on controller death or type conversion (deploy/undeploy is the classic bug).
**Kind:** VFX.
**Sources:** https://modenc.renegadeprojects.com/MindControl
**Confidence:** Med.

### YR-UI-081 Psychic Blast / Dominator Wave
**What:** Psychic effects use an expanding psychic-energy burst. The Psychic Dominator opens ("resembling a hand controlling a puppet") when nearly charged, then emits a wave with a small irreversible-control radius (Chronosphere/Iron-Curtain scale) plus a large destructive radius (nuclear/lightning-storm scale) that is harmless to units. Yuri Clones/Prime emit a close-range psychic blast that kills infantry.
**Data keys:** `Type=PsychicDominator`; psychic blast weapon; charged/passive building animations.
**Numbers:** Dominator blast: small control radius, large structural-damage radius; units in radius permanently controlled (irreversible); Iron-Curtained vehicles immune.
**Edge cases:** Friendly-fire immunity differs: Yuri Prime's blast spares friendlies, Yuri Clone's does not. No EVA line on activation.
**Kind:** VFX / gameplay.
**Sources:** https://cnc-central.fandom.com/wiki/Psychic_dominator ; https://cncnz.com/games/yuris-revenge/yuris-units
**Confidence:** Med-High.

### YR-UI-082 Genetic Mutation Effect
**What:** The Genetic Mutator fires a mutagenic energy burst that converts humanoid infantry (friendly or enemy) into the caster's **Brutes**; non-humanoids and animals are killed; vehicles/structures are unaffected; the burst is ground-focused so Rocketeers are immune. Only one Genetic Mutator per player; a warning EVA line fires on detection.
**Data keys:** `Type=GeneticConverter`/`GeneticMutator`; mutation weapon/warhead; Brute spawn.
**Numbers:** Cooldown 5:00; cost $2500; build 1:40; −200 power.
**Edge cases:** Garrisoned/in-vehicle infantry are protected; even Boris/Tanya mutate; Slaves (free) can be mutated into Brutes for Grinder profit. Brutes themselves get flipped to whichever side exposes them.
**Kind:** VFX / gameplay.
**Sources:** https://cnc-central.fandom.com/wiki/Genetic_mutator ; https://cncnz.com/games/yuris-revenge/yuris-structures
**Confidence:** High.

### YR-UI-083 Force Shield Bubble
**What:** A translucent energy field makes selected friendly structures invulnerable for a short time (even to superweapons), at the cost of the base's power for the duration. Available to All (after Battle Lab); introduced in YR.
**Data keys:** `Type=ForceShield`; reveal/shield art; temporary power-down hook.
**Numbers:** Cooldown ≈5:00; YR-only.
**Edge cases:** Faction EVA names it differently (Allied "Force Shield" vs Soviet "energy shield"); the power-down is a real temporary debuff, not just cosmetic.
**Kind:** VFX / gameplay.
**Sources:** https://cnc.fandom.com/wiki/Force_Shield ; https://en.namu.wiki/w/포스%20실드 ; https://cncnz.com/games/yuris-revenge/yuris-structures
**Confidence:** Med-High.

### YR-UI-084 Gattling Muzzle / Fire-Rate Ramp (3 stages)
**What:** YR's Gattling Weapon System ramps fire rate/damage over sustained fire in **3 stages** (six weapons: alternating AG/AA per stage). The spin-up is a timed state machine, visible as the barrels accelerate.
**Data keys:** `IsGattling=yes`; `TurretCount>=1`; `WeaponCount`; `WeaponStages`; `Stage1/2/3`; `RateUp`/`RateDown`; odd weapons = anti-ground, even = anti-air; `EliteStageX`.
**Numbers (Yuri Gattling Tank):** `WeaponStages=3`, `WeaponCount=6`, `Stage1=200`, `Stage2=400`, `Stage3=600`, `EliteStage1/2/3 = 100/200/300`, `RateUp=1`, `RateDown=50`. Gattling Tank $600; Gattling Cannon $1000, −50 power.
**Edge cases:** `RateDown=0` = instant reset (no permanent ramp-up); missing `StageX` bricks that weapon pair; `TurretCount=0` with gattling → EIP `0070DF8A`; `WeaponCount < WeaponStages*2` → EIP `0070DF8A`; Stages need not be ascending (can jump).
**Kind:** VFX / weapon logic.
**Sources:** https://modenc.renegadeprojects.com/Gattling_Weapon_System ; https://cnc.fandom.com/wiki/Gattling_tank_(Yuri%27s_Revenge)
**Confidence:** High.

### YR-UI-085 Magnetron Levitation Beam
**What:** The Magnetron's magnetic beam **levitates enemy vehicles/ships**, pulls them toward itself, and damages structures; it cannot target infantry and cannot crush them.
**Data keys:** Magnetron vehicle type; magnetic beam weapon; levitation/force-move effect.
**Numbers:** $1000; Psychic Radar prerequisite; no anti-infantry weapon.
**Edge cases:** Units it pulls can be destroyed by supporting units; poorly armoured itself.
**Kind:** VFX / gameplay.
**Sources:** https://cncnz.com/games/yuris-revenge/yuris-units
**Confidence:** Med-High.

### YR-UI-086 Floating Disc Power-Drain Beam
**What:** The Yuri Floating Disc lasers infantry, and when parked over an enemy power plant it **blackouts the base**; over a refinery/slave miner it **siphons credits**; over a powered defence it shuts that defence off.
**Data keys:** Floating Disc aircraft; drain beam behaviour; target-structure-type switch.
**Numbers:** $1750; Battle Lab; small laser vs infantry.
**Edge cases:** Drain effects depend on hover target type (power/refinery/defensive), so behaviour is context-sensitive.
**Kind:** VFX / gameplay.
**Sources:** https://cncnz.com/games/yuris-revenge/yuris-units
**Confidence:** Med.

### YR-UI-087 Chaos Drone Gas Cloud
**What:** The Chaos Drone deploys a hallucinatory toxin cloud that makes enemies **berserk** (increased attack, prioritising friendly targets), refreshing the timer on repeat contact. No conventional weapon.
**Data keys:** Chaos Drone vehicle; deploy-gas weapon/warhead; berserk status effect + timer refresh.
**Numbers:** $600; no prerequisite.
**Edge cases:** Berserk units target friends first; effect is temporary and resets on contact.
**Kind:** VFX / gameplay.
**Sources:** https://cncnz.com/games/yuris-revenge/yuris-units
**Confidence:** Med-High.

### YR-UI-088 Boomer Ballistic Missile
**What:** The Yuri Boomer submarine is radar-hidden, fires torpedoes at naval targets, and launches ballistic missiles at ground targets (interceptable by AA). Giant Squids cannot envelop it and must melee it.
**Data keys:** Boomer vessel; torpedo weapon + ballistic missile weapon; submerge/visibility.
**Numbers:** $2000; Psychic Radar; visible when attacked/damaged.
**Edge cases:** Missiles can be shot down mid-air like V3/Dreadnought rockets.
**Kind:** VFX / gameplay.
**Sources:** https://cncnz.com/games/yuris-revenge/yuris-units
**Confidence:** Med-High.

### YR-UI-089 Slave Miner Deploy / Slave Gathering
**What:** The Slave Miner drives to ore, deploys, releases up to 5 non-controllable Slaves, auto-repairs when mobile, is engineer-repairable when deployed, and auto-replaces dead Slaves for free. Destroyed Slave Miners free survivors to their liberators (or neutral on surrender).
**Data keys:** Slave Miner vehicle/structure; `DeploysInto`/`UndeploysInto`; slave spawn/replace logic.
**Numbers:** $1750; Bio Reactor prerequisite; up to 5 Slaves; buildable from ConYard **and** War Factory concurrently.
**Edge cases:** Deploy/undeploy type conversion + mind control is a known owner-transfer bug; Slaves can be mutated into Brutes or grinded for profit.
**Kind:** VFX / gameplay.
**Sources:** https://cncnz.com/games/yuris-revenge/yuris-units ; https://modenc.renegadeprojects.com/MindControl
**Confidence:** Med-High.

### YR-UI-090 Superweapon Charge / Active Building Animations
**What:** Yuri superweapons have distinct passive, buildup, charged and active animations (wiki galleries: "deployment/undeployment/active animation", "buildup animation", "passive/charged in Snow Theater"). This is the on-map feedback that pairs with the sidebar timer.
**Data keys:** building animation states (`ChargingAnimation`, `ActiveAnim`, etc.) in art(md).ini; charge phase tied to timer.
**Numbers:** Genetic Mutator build 1:40 / cooldown 5:00; Psychic Dominator build 3:20 / cooldown 10:00.
**Edge cases:** Charged state is visually distinct from active; shroud reveal happens on completion.
**Kind:** VFX.
**Sources:** https://cnc-central.fandom.com/wiki/Genetic_mutator ; https://cnc-central.fandom.com/wiki/Psychic_dominator
**Confidence:** Med.

---

## 8. Campaign Structure

### YR-UI-100 Allied Arc (7 missions)
**What:** The Allied campaign assumes the Allied RA2 victory. The Allies use Einstein's time machine to erase the Psychic Dominators before they come online, then fight Yuri across LA, Seattle, Egypt, Sydney and London, and finally Antarctica. It ends with Yuri imprisoned in a Psychic Isolation Chamber and the two timelines merging.
**Data keys:** mission chain; time-machine mission logic; per-mission briefing/sidebar videos.
**Numbers:** 7 missions (Time Lapse, Hollywood and Vain, Power Play, Tomb Raided, Clones Down Under, Trick or Treaty, Brain Dead).
**Edge cases:** The final cutscene has Carville (not Yuri) interrupt the White House meeting — the timeline-merge gag.
**Kind:** Campaign / narrative.
**Sources:** https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge ; https://cnc-central.fandom.com/wiki/Red_Alert_2_cutscenes
**Confidence:** High.

### YR-UI-101 Soviet Arc (7 missions)
**What:** The Soviets steal the time machine, overshoot into the Cretaceous, arrive at occupied San Francisco, destroy the under-construction Dominator, then prevent their historical defeat by destroying Einstein's Chronosphere (Black Forest), free London from a Psychic Beacon, rescue Romanov in Casablanca, raid the Pacific launch base, invade the Moon, and assault Yuri's Transylvanian castle. The ending strands Yuri in the Cretaceous, where a T-Rex eats him, and the USSR spreads communism worldwide.
**Data keys:** mission chain; time-machine mission logic; Psychic Beacon liberation scripting.
**Numbers:** 7 missions (Time Shift, Deja Vu, Brain Wash, Romanov on the Run, Escape Velocity, To the Moon, Head Games).
**Edge cases:** "Deja Vu" is the Soviet perspective of RA2's Allied "Mirage" mission — a deliberate reuse/reversal.
**Kind:** Campaign / narrative.
**Sources:** https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge ; https://cnc-central.fandom.com/wiki/Red_Alert_2_cutscenes
**Confidence:** High.

### YR-UI-102 Narrative Frame: Psychic Dominator Disaster + Timeline Reset
**What:** YR's premise is a third-world-war-adjacent "Psychic Dominator Disaster": Yuri's global Dominator network, the Allies' time-travel counter, and the split Allied/Soviet arcs. The expansion is a **continuation of RA2's Allied victory** (Allied campaign) and a **"prevent our defeat" retcon** (Soviet campaign).
**Data keys:** mission metadata; campaign start state.
**Numbers:** 2 campaigns × 7 missions.
**Edge cases:** Both campaigns end in timeline merges/erasure; no canonical single ending.
**Kind:** Narrative / meta.
**Sources:** https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge ; https://cnc-central.fandom.com/wiki/Third_World_War_(Yuri%27s_Revenge)
**Confidence:** High.

### YR-UI-103 Psychic Beacons
**What:** Psychic Beacons are Yuri's local mind-control emitters used as mission objectives: mind-controlled friendly garrisons/allied forces in **London** (Soviet "Brain Wash") and **Transylvania** (Soviet "Head Games"); Eva Lee is mind-controlled remotely via a Yuri satellite before the Battle of London.
**Data keys:** Psychic Beacon structure (campaign); mind-control radius; objective scripting.
**Numbers:** Campaign-only structure (alongside Yuri Statue and Moon rocket platform).
**Edge cases:** Destroying/blocking the beacon releases controlled units (and blowing Yuri's satellite releases Eva).
**Kind:** Campaign / gameplay.
**Sources:** https://cnc-central.fandom.com/wiki/Psychic_dominator ; https://cnc-central.fandom.com/wiki/Mind_control_(Red_Alert) ; https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge
**Confidence:** High.

### YR-UI-104 Gimmick Mission: Moon Base ("To the Moon")
**What:** Soviet Mission 6 is a no-atmosphere, Lunar-theater base-build and assault on Yuri's Moon bases and Lunar Command Center, launched via Yuri's own captured rocket. The Cosmonaut (airborne, laser) is the special infantry.
**Data keys:** Lunar theater; Cosmonaut infantry; Moon rocket platform (campaign structure).
**Numbers:** Mission 6 of 7; Cosmonaut $600 (campaign only); only Cosmonaut/Desolator survive lunar environment.
**Edge cases:** Standard infantry are unusable; unit composition is constrained by the environment.
**Kind:** Campaign / terrain.
**Sources:** https://cnc-central.fandom.com/wiki/To_the_Moon ; https://cncnz.com/games/yuris-revenge/yuris-units
**Confidence:** High.

### YR-UI-105 Gimmick Mission: Cretaceous / T-Rex
**What:** Soviet "Time Shift" begins in the early Cretaceous (defend the time machine from T-Rexes), and the Soviet ending ("Head Games") sends Yuri to the Cretaceous where a T-Rex eats him.
**Data keys:** prehistoric mission art/creatures; time-machine objective.
**Numbers:** 2 Cretaceous appearances (mission 1 + ending).
**Edge cases:** The dinosaur encounter is a scripted survival vignette, not a full faction.
**Kind:** Campaign / presentation.
**Sources:** https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge ; https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge
**Confidence:** High.

### YR-UI-106 Gimmick Mission: Hollywood Celebrities
**What:** Allied Mission 2 ("Hollywood and Vain") has the player rescue and use heavily armed celebrity units based on action-hero parodies (Arnie, Sly, Clint). A later patch replaced their names and voice lines with generic equivalents.
**Data keys:** celebrity infantry types/hero units; mission scripting; patched names/voices.
**Numbers:** 3 celebrity heroes; toned down in a later patch.
**Edge cases:** The censorship/rename is a presentation delta *within* YR's patch history.
**Kind:** Campaign / presentation.
**Sources:** https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge
**Confidence:** High.

### YR-UI-107 Gimmick Missions: No-Base / Commando / Escort
**What:** YR mixes mission types. Allied "Tomb Raided" is largely a Tanya infiltration (free Einstein, then use a captured Dominator); Soviet "Escape Velocity" is an island base-capture; "Romanov on the Run" is a search-and-escort. These variations are a stated modding selling point of YR campaigns.
**Data keys:** mission objective scripting; hero-only starts; capture mechanics.
**Numbers:** At least 3 mission archetypes (commando/infiltration, base-capture, escort).
**Edge cases:** Captured enemy superweapons (Egyptian Dominator) can be player-fired once before sabotage.
**Kind:** Campaign / gameplay.
**Sources:** https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge ; https://www.moddb.com/games/cc-red-alert-yuris-revenge/features/yuris-revenge-allied-retribution-campaign (context on YR campaign conventions)
**Confidence:** Med-High.

### YR-UI-108 Cooperative Campaign Missions
**What:** YR ships cooperative multiplayer missions for all sides (Allied Coop 1–3, Soviet Coop 1–3, Yuri Coop 1–3, plus a shared Alliance Coop Mission). The `cooperative` game-mode token exists for these. RA2 also had coop missions (Allied/Soviet Coop 1–3, 5 maps each).
**Data keys:** `GameModes=cooperative`; coop map set; players may choose any country except Yuri on some coop missions (Alliance Coop unlocks the Virus via Tech Secret Lab).
**Numbers:** RA2: 3 Allied + 2 Soviet coop mission groups; YR: 3 Allied + 3 Soviet + 3 Yuri + Alliance Coop.
**Edge cases:** `cooperative` "may not work in standard multiplayer maps"; coop maps are separate map files.
**Kind:** Meta / campaign.
**Sources:** https://modenc.renegadeprojects.com/GameModes ; https://cnc.fandom.com/wiki/Category:Yuri%27s_Revenge_missions ; https://cnc.fandom.com/wiki/Alliance_Coop_Mission
**Confidence:** Med-High.

---

## 9. Meta / Multiplayer

### YR-UI-110 Game Modes (post-YR)
See the table under **YR-UI-021**. Key meta fact: **Team Alliance replaced Siege** in YR; `cooperative` token is supported.

### YR-UI-111 Countries and Sides Roster
| Side | Countries (index) |
|---|---|
| GDI (Allies) | Americans (0), Alliance/Korea (1), French (2), Germans (3), British (4) |
| Nod (Soviets) | Africans/Libya (5), Arabs/Iraq (6), Confederation/Cuba (7), Russians (8) |
| ThirdSide (Yuri) | YuriCountry (9) — **YR only** |
| Civilian | Neutral (12) |
| Mutant | Special (13) |
| unused | GDI (10), Nod (11) placeholders |
**Numbers:** 9 playable in RA2, 10 in YR. Country `Multiplay=yes` gates lobby visibility; `Side=` selects EVA/GUI.
**Edge cases:** The commented "major 9 houses" ordering is mandatory to avoid crashes.
**Kind:** Meta.
**Sources:** https://modenc.renegadeprojects.com/Countries
**Confidence:** High.

### YR-UI-112 Ten-Country Skirmish
**What:** YR's skirmish supports all 10 countries including Yuri, and adds team/ally setup (see YR-UI-019). Country choice changes special units and bonuses via `VeteranXXX=` / `YYYZZZMult=` (armour/cost/speed/build-time and `IncomeMult`).
**Data keys:** `[Countries]`, `Multiplay=`, `Veteran*`, `*Mult=`, `SmartAI=`.
**Numbers:** 10 countries; bonuses are straight multipliers.
**Edge cases:** `SpeedBuildingsMult`-style nonsensical combos are ignored.
**Kind:** Meta.
**Sources:** https://modenc.renegadeprojects.com/Countries ; https://steamcommunity.com/app/2229850/discussions/0/4364628673434334025
**Confidence:** High.

### YR-UI-113 CnCNet YR Online
**What:** The community CnCNet client is the modern, free way to play YR online and offline skirmish, including the original campaigns; it packages the game for Windows and offers a "Legacy (Unsupported)" update channel to revert Ares/tools.
**Data keys:** CnCNet client/updater; update channels; online lobby.
**Numbers:** N/A.
**Edge cases:** CnCNet also ships an "RA2 mode" toggle to restore RA2 behaviour; the Ultimate Collection lacks valid CD keys for XWIS.
**Kind:** Meta / online.
**Sources:** https://cncnet.org/yuris-revenge ; https://github.com/CnCNet/cncnet-yr-client-package/releases ; https://steamcommunity.com/app/2229850/discussions/0/4299320351880428877
**Confidence:** High.

### YR-UI-114 XWIS (Westwood Online successor)
**What:** XWIS hosts the official-style YR/RA2 ladder/online service (forums, games, YR pages), distinct from CnCNet. It is the legacy multiplayer network.
**Data keys:** XWIS account/ladder; CD-key requirement.
**Numbers:** N/A.
**Edge cases:** Ultimate Collection CD keys are invalid on XWIS, pushing players to CnCNet.
**Kind:** Meta / online.
**Sources:** https://xwis.net/yr ; https://xwis.net/forums ; https://steamcommunity.com/app/2229850/discussions/0/4299320351880428877
**Confidence:** Med-High.

### YR-UI-115 Annex: New Units / Structures / Powers (delta inventory)
**What:** Full YR addition inventory, useful as the cameo/UI manifest.

**Allies (new):** Guardian GI ($400), Robot Tank ($600, needs powered Robot Control Center, immune to mind control, hovers), Battle Fortress ($2000, 5 firing infantry slots, crushes vehicles), Robot Control Center.
**Allies (modified):** Navy SEAL now skirmish/multiplayer ($1000); Tanya $1500, can C4 vehicles, uncrushable except by Battle Fortress, one-at-a-time; IFV weapon table extended (psychic blast for Yuri Clone, sniper/toxin, etc.).
**Soviets (new):** Boris ($1500, AKM + MiG laser designator, immune to mind control), Siege Chopper (MG in air, siege cannon deployed), Industrial Plant (−25% cost/build time for vehicles, aircraft, ships, refineries; replaces Cloning Vats), Battle Bunker (5 infantry, fire from inside), Spy Plane power.
**Soviets (removed/transferred):** Psi-Corps trooper → Yuri Clone; Cloning Vat → Yuri; Psychic Sensor → Psychic Radar.
**Yuri (infantry):** Initiate ($200), Engineer, Brute ($500), Virus ($700, toxic sniper), Yuri Clone ($800), Yuri Prime ($1500), Slave (free), Psi Commando (stolen tech), Cosmonaut (campaign only).
**Yuri (vehicles):** Slave Miner ($1750), Lasher Tank ($700), Gattling Tank ($600), Chaos Drone ($600), MCV ($3000), Magnetron ($1000), Mastermind ($1750, controls 3).
**Yuri (air/naval):** Floating Disc ($1750); Amphibious Transport ($900, 12 slots), Boomer ($2000).
**Yuri (structures):** Bio Reactor ($600, +150 power +100/infantry), Barracks, War Factory, Submarine Pen, Psychic Radar, Grinder, Battle Lab, Citadel Wall, Tank Bunker, Gattling Cannon, Psychic Tower (controls 3), Cloning Vats, Genetic Mutator ($2500), Psychic Dominator ($5000).
**Global (new):** Force Shield.
**Tech (new/modified):** Tech Hospital (global heal), Tech Machine Shop (global vehicle repair), Tech Civilian Power Plant, Tech Secret Lab (country tech).
**Numbers:** ~10 new Yuri buildings, ~15 new Yuri units, ~7 new/updated Allied+Soviet items, 1 global power.
**Edge cases:** Several Yuri structures disable at low power; Robot Tanks stop working if the Robot Control Center is destroyed/unpowered (and sink if over water); only one Yuri Prime / Cloning Vat / Genetic Mutator / Psychic Dominator per player.
**Kind:** Inventory.
**Sources:** https://cncnz.com/games/yuris-revenge/yuris-units ; https://cncnz.com/games/yuris-revenge/yuris-structures ; https://cncnz.com/games/yuris-revenge/new-allied-units ; https://cncnz.com/games/yuris-revenge/new-soviet-units ; https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge ; https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge
**Confidence:** High.

---

## 10. Other Presentation Deltas

### YR-UI-120 Box Art Censorship (post-9/11)
**What:** The 9/11 attacks delayed YR and forced a cover change: the original art featured annihilated civilian buildings and was replaced with the final design (destroyed buildings removed). Some later RA2 budget releases were also censored.
**Data keys:** N/A (packaging).
**Numbers:** NA release 2001-10-09, after the attacks.
**Edge cases:** The fandom infobox lists a placeholder NA date of 2001-08-30, conflicting with Wikipedia/I GN's October 9 — treat the October date as release, August as a prior listing error.
**Kind:** Presentation / packaging.
**Sources:** https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge ; https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge
**Confidence:** Med-High.

### YR-UI-121 Cast / Character Cameos Presentation
**What:** YR's FMV cast returns RA2 leads (Eva, Tanya, Carville, Dugan, Einstein, Romanov) and adds Zofia (Soviet Lt.) and Chairman Bing (Massivesoft parody), with Yuri (Udo Kier) as the central villain. Presentation of characters is otherwise RA2-style green-screen.
**Data keys:** N/A.
**Numbers:** 9 credited live-action characters.
**Edge cases:** Yuri was teased at the end of RA2's Soviet campaign before YR was announced.
**Kind:** Presentation.
**Sources:** https://cnc-central.fandom.com/wiki/Command_%26_Conquer:_Red_Alert_2:_Yuri%27s_Revenge ; https://en.wikipedia.org/wiki/Command_%26_Conquer:_Yuri%27s_Revenge
**Confidence:** High.

---

## Catalog A — YR Music Tracks
See **YR-UI-050** table. 10 in-game tracks + 1 trailer-only remix; no disc release.

## Catalog B — Country Index / Loading Assets
See **YR-UI-020** table. Index-bound flags + loading screens + YR-only per-country palettes.

## Catalog C — Missions & FMV
See **YR-UI-062/063** tables (Allied 7, Soviet 7) + intro/ending + sidebar videos.

## Catalog D — Game Modes
See **YR-UI-021** table (Team Alliance replaces Siege; cooperative supported).

## Catalog E — Theaters
| Theater | Char | Tile type | YR use |
|---|---|---|---|
| Generic | G | — | shared/generic art fallback |
| Temperate | T | TEM/MMT | standard ground |
| Snow (arctic) | A | SNO/MMS | winter maps; Yuri snow variants |
| Urban | U | URB/MMU | RA2 urban |
| Desert | D | DES/MMD | desert maps |
| NewUrban | N | UBN/MMT | **YR** second urban set |
| Lunar | L | LUN/MML | **YR** Moon mission |

---

## Coverage Checklist

| # | Scope item | Covered by | Status |
|---|---|---|---|
| 1 | New cameos/icons for all YR content | YR-UI-011, 115, Catalog A | ✔ (counts med) |
| 1 | Yuri sidebar art | YR-UI-010 | ✔ (med; shared-skin caveat) |
| 1 | Mind-control feedback (colour/pips/capacity) | YR-UI-012, 013, 080 | ✔ |
| 1 | Garrison/bunker cursors & orders | YR-UI-015, 014 | ◐ (cursor glyphs low) |
| 1 | Superweapon shared-countdown UI | YR-UI-016, 017 | ✔ (interpreted) |
| 1 | Lobby 10th country + team setup | YR-UI-018, 019, 111, 112 | ✔ |
| 1 | Loading screens bound to country index | YR-UI-020 | ✔ |
| 1 | Game-mode selection (Team Alliance) | YR-UI-021 | ✔ |
| 2 | Yuri EVA voice set | YR-UI-030 | ✔ (med) |
| 2 | New Allied/Soviet EVA line changes | YR-UI-031, 032, 033 | ◐ (partial line list) |
| 3 | Yuri unit voice sets | YR-UI-041 | ◐ |
| 3 | Hero VOs (Boris, Yuri Prime) | YR-UI-042, 043 | ✔ (med-high) |
| 4 | Full YR track list | YR-UI-050, Catalog A | ✔ |
| 4 | Dynamic music behaviour | YR-UI-052 | ◐ (negative claim) |
| 5 | Full YR FMV list | YR-UI-060–066, Catalog C | ✔ (mission-level) |
| 6 | Lunar theater | YR-UI-070, Catalog E | ✔ |
| 6 | New urban/snow art | YR-UI-071, 072 | ✔ |
| 6 | Per-country palettes | YR-UI-073 | ✔ |
| 7 | Mind-control links | YR-UI-080 | ✔ |
| 7 | Psychic blasts | YR-UI-081 | ✔ |
| 7 | Genetic mutation | YR-UI-082 | ✔ |
| 7 | Force shield | YR-UI-083 | ✔ |
| 7 | Gattling muzzle ramp | YR-UI-084 | ✔ |
| 7 | Other FX (Magnetron, Floating Disc, Chaos, Boomer, Slave Miner, superweapon anims) | YR-UI-085–090 | ✔ |
| 8 | Allied 7-mission arc | YR-UI-100 | ✔ |
| 8 | Soviet 7-mission arc | YR-UI-101 | ✔ |
| 8 | Narrative frame | YR-UI-102 | ✔ |
| 8 | Psychic beacons | YR-UI-103 | ✔ |
| 8 | Gimmick missions (Moon, T-Rex, Hollywood, no-base) | YR-UI-104–107 | ✔ |
| 9 | Modes (Team Alliance replacing Siege) | YR-UI-021, 110 | ✔ |
| 9 | 10-country skirmish | YR-UI-018, 112 | ✔ |
| 9 | `cooperative` token | YR-UI-021, 108 | ✔ |
| 9 | CnCNet / XWIS | YR-UI-113, 114 | ✔ |
| 10 | Any other UI/UX/presentation/meta change | YR-UI-001, 002, 022, 023, 012, 120, 121 | ✔ |

## Open Questions / Top Uncertainties
1. **Yuri sidebar uniqueness** — forums claim "3 unique sidebars" in the title but conclude Yuri shares the Soviet sidebar + unique radar. Needs verification from stock asset names (`sidec01`/`sidec02` + Yuri radar) or an asset-list source.
2. **Garrison/bunker cursor glyphs and ungarrison order bindings** — behaviour is well-sourced; the exact cursor art/order names are not. Needs an asset/INI source (e.g. `MouseCursor` / action tables).
3. **Complete YR EVA line list** — only individual lines ("Warning — Genetic Mutator has been detected!") and the per-faction Force Shield naming are documented; no canonical full transcript was found. The CnCNet "In-Game Audio Database & Transcript" thread and the archive.org dialogue PDF would close this.
4. **Full YR voice-set breakdown** — the "all unit classes unique voices" claim is high-confidence, but a per-unit select/move/attack mapping was not compiled from a citable source.
5. **Music dynamic behaviour** — no adaptive-music system found; confirm YR menu/loading theme assignment (Jank analogue) and whether `Score`/`Credits` duplicate the fan "Options/Score Theme" entries.
6. **"Superweapon shared-countdown UI"** — interpreted as YR support-power/superweapon sidebar timers + global detection reveal. If it means something more specific (e.g. shared timer across multiple superweapons), no source confirms it.
7. **Release date conflict** — fandom infobox "NA 2001-08-30" vs Wikipedia/IGN "2001-10-09"; October is corroborated by two sources, August is likely a stale listing.
8. **Exact YR cameo delta count** — wiki category counts (231 total / 50 Yuri) include localisations and re-renders; a true "new vs reused" count needs an asset manifest.
