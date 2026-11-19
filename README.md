# AI Village Wars — Project Handoff

This README is the handoff note for continuing the Godot project across chats or accounts. **At the end of each project chat, update the “Progress log” and adjust “Current status” and “Next work”** so the next person can resume from the repository state. Record only changes that were actually made and validated; label anything unverified.

## Project

AI Village Wars is a 2D strategy and AI project being rebuilt in Godot 4. The active working copy in this workspace is:

`C:\Users\user\Downloads\AI_lab_fixed\godot_project`

Open this folder in Godot (it contains `project.godot`). A previous run copy was also synced to `C:\Users\user\OneDrive\Documents\al-lab`; that path may not be available on another account or machine. Treat the workspace copy above as the portable source of truth unless the user says otherwise.

## Current status

**2026-11-12 (latest) — Visible ranged attacks and building health bars (engine-tested headless, plus real software-rendered screenshots).** Archers now shoot visible arrows and mages visible magic bolts that fly to the building and burst on impact; every attacked building shows a health bar with its name and exact HP (e.g. "Cannon 290 / 420") that drains as each hit lands. Details in the "Attack visuals" progress entry at the bottom. Earlier status notes below still apply.

**2026-11-12 (later) — Wall-breach fix (engine-tested headless).** Troops no longer keep chewing on walls after a gap has opened or spread across many different walls: all troops share one breach wall, and anything bashing a wall re-plans the moment something falls. Details in the "Wall breach" progress entry at the bottom. Earlier 2026-11-12 and 2026-11-11 status notes below still apply.

**2026-11-12 — Hotfix for a runtime error found in the editor (engine-tested headless).** Deploying troops in a real game could raise `Invalid type in function '_queue_replan' ... (previously freed)` when the Clan Castle was triggered after an earlier troop had died and been freed; the editor debugger then paused the game. Fixed, covered by a new real-frame regression test, and all 16 editor warnings were cleared. See the 2026-11-12 progress entry. The 2026-11-11 status below still describes the feature itself.

**2026-11-11 — Clan Castle, adversarial Minimax and pathfinder speed-up (engine-tested headless).** Godot **4.7.2 was available** this session and the full runner (`python tools/run_all_tests.py --godot <godot>`) reported **PASS** for all 10 test scripts plus the 4 scene boots; a Clan Castle (CoC-style garrison that rushes out and fights) was added, the tactical search now models replies that depend on the chosen target, and the pathfinder was rewritten ~24x faster with provably identical routes. Not done: interactive play, screenshot review of the placeholder castle art, or FPS measurement on a real GPU. Details in the 2026-11-11 progress entry.

**2026-11-09 — Visual-upgrade source patch prepared; engine validation still required.** The supplied ZIP has been inspected and this copy now contains a unified medieval-styled Theme, redesigned title screen, village/battle HUD restyling, real Sprite2D/AnimatedSprite2D objects Y-sorted by footprint, dynamic grounding shadows and damaged-only health bars, deterministic non-blocking trees/shrubs/rocks, placement previews and animations, generated siege-wagon/wall graphics, resource icons, synthesized sound and music, fade scene transitions, combat damage and crumble effects, and F3/F4 pathfinding diagnostics. The AI Arena now offers a live demonstration entry point rather than the previous placeholder. The existing village, troop/building catalogs, save and battle algorithms are preserved; optional instrumentation was added to `grid_pathfinder.gd`, not a new routing algorithm.

**Validation boundary:** Godot 4.7 was **not installed** in the preparation environment; no editor import, headless tests, full interactive play, screenshot inspection, FPS measurements, or regression runs could be completed for this upgraded copy. The earlier 2026-10-30 test results below describe *different earlier revisions*, not this build. The shipped `tools/run_all_tests.py` is a repeatable Godot 4.7 test/smoke runner. Source/content checks and ZIP integrity checks are separately documented in `VISUAL_UPGRADE_NOTES.md`. **Do not describe this patch as fully tested or 60-FPS validated until you run it in Godot.**

### Work reported complete in prior chats

- Rebuilt and organized the project as a Godot 4 project (`project.godot`, `scenes/`, `scripts/`, `assets/`, `data/`, `tests/`).
- Added village model/grid/terrain/object layers, village controller and strategy camera, building catalog, and troop catalog.
- Added main menu, village, battle, and AI arena scenes, plus scene/game managers and save manager.
- Integrated provided troop and building images into the project and added sprite-frame/actor animation support. The user identified the red building as Barracks and the blue building as Town Hall.
- Added battle rules/management and an AI search module. Prior work notes mention A*, BFS, Greedy BFS, and Best-First Search route choices; minimax-style building target selection; tower aiming; troop deployment restrictions; and pause/speed handling for troop movement.
- Fixed a saved-state recovery case where an empty village/army could incorrectly appear to end in a victory, and synced several scripts/art files to the OneDrive run copy.
- Added GDScript test files under `tests/` for the battle rules, troop actor, AI search, pathfinding, save manager, and village model.

## Next work

1. Import **this ZIP's `al-lab/project.godot`**, not any previous run copy; allow the Godot 4.7 editor to import the generated PNGs, and run `python tools/run_all_tests.py --godot /path/to/godot` (or your Godot executable's Windows path). Report any parse or test failure before treating the build as stable.
2. Launch main menu, village, battle, and AI Arena. Inspect the Town Hall / wall / siege-wagon proportions, text/UI clipping at 1280×720 and smaller sizes, terrain edges, and actual 60-FPS performance using the Godot monitor. Fix any observed issues rather than assuming the static code is sufficient.
3. Regression-test save/load, placing and upgrading all building types, training and moving troops, deployment, pause/speed, win/lose, and all four pathfinders plus three target strategies. Press F3 for statistics and F4 for visited cells and paths. See the click-by-click checklist in `VISUAL_UPGRADE_NOTES.md`.
4. Optional artistic follow-up after live review: manually replace placeholder generated siege-wagon/wall art with matched professionally drawn pixel art, add dedicated goblin/tank animation sheets, polished projectile art and ambient motion, and optionally install an OFL licensed fantasy UI font. These were not claimed complete.

## Project map

- `project.godot` — Godot project settings and main scene configuration.
- `scenes/` — `main/Main.tscn`, `village/VillageScene.tscn`, `battle/BattleScene.tscn`, and `ai/AIArena.tscn`.
- `scripts/` — AI, battle, core, pathfinding, save, UI, units, and village logic.
- `assets/` — game art and source/reference assets.
- `data/` — project data/resources.
- `tests/` — GDScript test scripts; `python tools/run_all_tests.py --godot <godot>` runs them all.
- `scripts/village/clan_castle.gd` — Clan Castle rules: capacity, garrison presets, trigger/leash radius, sanitising saved garrisons.
- `scripts/ai/battle_search_ai.gd` — one Minimax / Alpha-Beta / Expectimax core used by attackers (pick a building or defending troop) and by Clan Castle defenders (pick an attacker).

## Handoff notes for the next chat

- Read this file first, then inspect the current workspace files and ask the user to clarify only requirements that cannot be inferred from the project or earlier notes.
- The workspace project is distinct from the old sibling `ai_village_fixed/` folder, whose README describes a browser dungeon game and is not documentation for this Godot project.
- Previous user feedback included “nothing is changed” and “the whole game is empty”; this was traced in prior work to running a different project copy and to an empty saved village state. Confirm which project path is open before diagnosing visual changes.
- At the end of every chat that changes this project, append a dated progress entry below, update the status and next steps, and mention verification performed and any failures.

## Progress log

### 2026-10-28 — Handoff documentation

- Added this project-specific README in the Godot project folder.
- Captured the implementation areas and follow-up items based on the current project layout and recent Codex project-chat notes.
- No game code was changed or newly validated as part of this documentation update.

### 2026-10-30 — Visual and movement presentation pass

- Reworked battle troop selection into taller cards with larger, centered troop art and readable troop names/counts.
- Changed battle building rendering to use the supplied cannon and archer tower artwork instead of primitive placeholder shapes; added a brief projectile effect while preserving the source sprites.
- Added art thumbnails for every build option and changed the selection preview to preserve the full building image.
- Removed the archer-sheet substitute for goblins so the game uses the supplied goblin sprite. Added subtle movement bob/lean to static tank and goblin art and continuous redraw so idle/attack/death sprite-sheet frames animate.
- Adjusted village unit motion rendering.
- No battle rules or AI logic were changed. The updated scripts were copied to `C:\Users\user\OneDrive\Documents\al-lab` to match the project shown in the user's screenshots. Runtime validation was not performed in this chat.

### 2026-10-30 — Inventory refill and visual fixes

- Refill gold, elixir, and gems to 999,999 and restore the configured full troop stock (8 Warriors, 3 Mages, 8 Goblins, 8 Archers, 2 Tanks) whenever the village or battle scene is entered. The battle deployment limit now matches the 29 available troops.
- Added the supplied wall sprite to the renderer and rotated wall segments to follow their wall runs.
- Repainted the field with the supplied grass tile variants to break up the repeated single-tile texture.
- Anchored every building sprite to the lower edge of its footprint to address the floating appearance. Kept supplied cannon and archer-tower art visible in battle.
- Found that the OneDrive copy had not contained all the latest renderer edits. Synced the complete updated script set and imported assets in that copy.
- Godot 4.7.2 editor import completed, and both VillageScene and BattleScene launched headlessly from the workspace and OneDrive copies without script errors. No gameplay test suite was run, and visual appearance still needs confirmation in the running game.

### 2026-10-30 — Combat facing and search accuracy

- Cannon sprites now rotate toward the currently selected attacker, with projectile trails starting from the aimed muzzle. Archer towers show a directional arrow cue and fire from the roof archer's position.
- Troop sprites turn toward movement and attack targets; archer, mage, and melee attack effects follow the facing direction.
- Attack planning now filters unreachable buildings, routes to valid attack-range cells, and ranks targets using actual path cost. If no building is reachable, attackers choose a reachable wall to breach.
- Path priorities now implement BFS (FIFO), A* (`g+h`), Greedy Best-First (`h` with a path-cost tie breaker), and Weighted Best-First (`g+1.5h`). Minimax/alpha-beta now model each in-range defense's hit/miss choices; Expectimax computes the independent hit probabilities across those defenses.
- Synced the updated scripts to the OneDrive game folder. Godot 4.7.2 loaded both village and battle scenes headlessly from that folder without script errors. No test suite or live visual review was run.

### 2026-10-30 — Battle sprite placement correction

- Reduced wall segment render size to fit its one-tile footprint and rotated each segment to follow the projected isometric direction of adjacent wall cells.
- A split-cannon asset experiment initially broke renderer loading due to missing PNG import metadata. The generated-image preloads were removed and the existing cannon sprite was restored; live cannon rotation remains unfinished.

### 2026-10-30 — Battle character and impact visuals

- Kept full-body troop sprites upright while changing facing with left/right mirroring, increased sprite-sheet walk animation to 10 frames per second, and enabled articulated limb motion during movement.
- Increased the archer tower's rendered size and changed equal-depth drawing so wall pieces render before buildings.
- Added short impact rings and sparks to troop and building damage, with effects positioned at the struck object's edge. Passed attacker/defender positions through existing damage calls; combat rules are unchanged.
- Inspected the current local village save: it has no archer tower, gold mine, or elixir pump, so those assets cannot render from this save. Did not modify the save; rebuild the tower from the village Build menu to include it in the next battle.
- Headless launch checks for BattleScene and VillageScene passed in both the workspace and OneDrive copies after syncing; SHA-256 checks matched the copied troop and battle-manager scripts. Live visual review is still pending. The supplied screenshot also shows the battle paused, so active walk cycles are frozen until Resume.

### 2026-11-09 — Coherent visual layer, AI traces, sound and packaged source (unverified in-engine)

- Replaced model-object drawing with Y-sorted sprite-based render entities; placed soft shadows, selective health bars, and small placement/hit feedback. Preserved model, building/troop catalogs and battle decision code; added an optional pathfinder trace argument for drawing real visits/paths.
- Added repeatable seeded decorative terrain and dirt paths that read occupancy without writing to the grid; generated low castle wall, medieval siege wagon, and gold/elixir/gem icons with PNG import metadata.
- Added shared `themes/medieval_ui.tres`, new menu and functional AI lab intro, scene fade, battle/village HUD improvements, audio hooks and original synthesized PCM WAV effects/music; introduced lightweight crumble particles and damage labels.
- Added path trace validation and a Python command-line runner for original GDScript tests plus headless scene launches. **Attempted runner: unavailable (Godot 4.7 executable not found).** No engine suite results or measured FPS can be reported; static file checks and ZIP verification only.
- Full list of changed/created files and manual verification steps: `VISUAL_UPGRADE_NOTES.md`. Do not discard future bug reports solely because the patch compiled as text.

### 2026-11-11 — Clan Castle defenders, target-dependent Minimax, 24x faster pathfinding (headless-tested on Godot 4.7.2)

**Clan Castle (new building, 3x3, 800 gold, 900 HP).** Holds up to 12 housing space of troops, set from the selection panel (GARRISON button cycles presets Balanced / Archers / Warriors / Tank Guard; presets live in `ClanCastle.PRESETS`). The starter village now contains one; an existing saved village does not, so build one from the menu or delete the save. Saves store the garrison on the structure and clamp it on load.
- **Battle behaviour:** any attacker within `ClanCastle.TRIGGER_RADIUS` (260 px) of the castle releases the whole garrison once. Defenders appear on free tiles beside the castle, chase attackers inside `LEASH_RADIUS` (420 px), fight them, and walk home and stand down when nobody is in reach. They re-engage if an attacker comes back. Defenders are blue-tinted with a small shield. A castle destroyed before it was triggered loses its garrison; destroying it afterwards leaves released defenders alive. The castle counts toward destruction %.
- **Attackers fight back:** defending troops are valid targets for attackers (squishy, high-damage ones are the best kills; Tanks are ignored), and attackers re-plan when a target dies.
- **Minimax now matters:** a defense only answers if it covers the spot the troop would stand at to hit the chosen target, so different targets draw different replies (a Warrior stays out of the castle's reach, a Tank dives in; a troop already under fire cannot "escape" by picking a far target). Castle troops are folded into one volley so the tree stays small. The same search core also drives the **defender side**: each defender picks which attacker to fight, modelling nearby attackers as retaliation (avoids diving into a pack, prefers weakened high-damage troops). Minimax, Alpha-Beta and Expectimax all work for both sides; the F3 inspector shows castle state and the defender decision.
- **Performance (needed for the above):** planning was ~1.4 s per troop in headless; it is now ~14 ms. `GridPathfinder` uses flat arrays plus a binary heap with the exact original tie-breaking (`tests/pathfinding/test_pathfinder_equivalence.gd` compares 480 random searches against the original implementation, kept as `reference_grid_pathfinder.gd`: 0 mismatches). Walled-off targets are skipped using a cached connected-region map instead of flooding the map, walls are only searched to breach a sealed base, and re-plans after a building falls are queued (1 per frame) and limited to troops that lost their target rather than re-planning every troop at once.
- **Bugs fixed on the way:** the HUD troop counter used a typed lambda over the unit list and threw an error each update once a dead troop had been freed (affected the original attacker counter too); `test_troop_actor.gd` asserted a one-frame ATTACK state that the game never had (the attack fires in the same frame as getting in range), and `test_village_model.gd` hard-coded 44 starter structures (now 45).
- **Verification:** full runner PASS on Godot 4.7.2 (including 68 new Clan Castle checks, 30+ adversarial-search checks, pathfinder equivalence); 12 pathfinder x strategy combinations and all four garrison presets simulated headless with no engine errors; real Village and Battle scenes driven through real frames (garrison UI, F3 inspector, defender release, battle to completion). Worst single frame during simulated battles was about 25-60 ms in headless on this machine.
- **Not verified / known limits:** no interactive play and no visual review (the castle sprite is procedurally generated placeholder art, `assets/buildings/clan_castle_sprite.png`); no GPU FPS measurement; garrison composition is preset-based (no per-troop donation UI); defenders walled inside a sealed base just hold their position. Balance numbers (trigger/leash radius, presets, defender hit probability 0.85, search values) are first-pass and easy to tune in `clan_castle.gd`, `battle_manager.gd` and `battle_search_ai.gd`.

### 2026-11-12 — Fix "previously freed" error when the Clan Castle triggers; clear editor warnings

- **Bug:** dead troops are freed by the engine after their fade-out, so `attacker_units` can hold freed objects. `BattleManager._queue_replan_all()` passed such an entry to the typed parameter of `_queue_replan()`, which is a runtime error (`Invalid type in function '_queue_replan' ... argument 1 (previously freed)`). It needs a troop to have died *before* a castle trigger or an algorithm switch, so the earlier headless tests (which never let the engine free a node) missed it. The Godot debugger pauses on a runtime error, which looked like the game freezing.
- **Fix:** `_queue_replan()` now takes an untyped argument and checks `is_instance_valid()` first; `_queue_replan_all()` iterates by index; every read of a possibly-freed `attacker.target` / `defender.target` goes through a `Variant` before any typed use.
- **New regression test:** `tests/battle/test_battle_frames.gd` drives a battle with real engine frames so dead troops really are freed, then triggers the castle, switches algorithms, changes speed and pauses. With the old code it fails with the exact error above; with the fix it passes. Registered in `tools/run_all_tests.py`.
- **Warnings cleared (16, all behaviour-neutral):** integer-division warnings (`clan_castle.gd`, `grid_pathfinder.gd`, `battle_manager.gd`, `battle_controller.gd`, `village_model.gd`), `range`/`name`/`units` shadowing (`battle_manager.gd`, `audio_manager.gd`, `battle_controller.gd`), unused parameter (`village_controller.gd`), incompatible ternaries (`visual_entity.gd`). Several of these were in the original project, not the Clan Castle work.
- **Verification:** full runner PASS on Godot 4.7.2 after the change. Not verified: warnings were fixed from the line numbers in your editor screenshots (headless Godot does not print editor warnings), so please confirm the Errors panel is clean on your machine.

### 2026-11-12 (later) — Wall breach: one shared breach wall, bashers re-plan when anything falls

- **Symptom:** in a walled base some troops kept destroying walls instead of going for the buildings, and after one troop made a gap the others kept hitting their own wall until it fell before heading for the target.
- **Cause (a regression from the Clan Castle work):** to keep planning cheap, re-planning after a building fell was limited to troops whose own target had been destroyed, so a troop attacking wall A never noticed that a gap had opened at wall B. On top of that every troop chose its own nearest wall, so many walls were destroyed instead of one gap.
- **Fix (`battle_manager.gd`):** (1) all troops share ONE breach wall (`_breach_wall_id`), chosen for being close to the troop *and* to the buildings behind it (`BREACH_GAP_WEIGHT`), reused while it stands and is reachable, cleared when it falls (a second wall layer simply picks a new shared wall); (2) when any building or wall is destroyed, every troop that is attacking a wall is re-planned at the front of the queue, so it drops its wall as soon as a real building is reachable.
- **Measured (headless, fully sealed base, 3 armies):** walls destroyed per battle 5-6 -> 1; battle time 25/13/16 s -> 19/12/13 s; troop-time spent targeting walls 53-62% -> 37-43% (the rest is the unavoidable walk to and break of the single breach wall).
- **Tests:** new `tests/battle/test_wall_breach.gd` (shared wall, everyone goes through the gap, a troop busy on a *different* wall switches, two wall layers, reachable buildings come before walls). With either half of the fix disabled it fails; both halves are registered in `tools/run_all_tests.py`.
- **Not verified:** interactive play; very irregular wall layouts (the breach wall is a distance heuristic, not an exhaustive "cheapest gap" search).

### 2026-11-12 (latest) — Attack visuals: archer arrows, mage bolts, building health bars

- **Why it was invisible before:** ranged troops only showed a short stub in front of themselves, and a building's HP was only drawn by a ground-level bar hidden *behind* the building sprite, so damage was never readable in battle.
- **Projectiles** (`combat_fx.gd`, `battle_manager.gd`, `battle_controller.gd`): `TroopCatalog` now marks the archer `"projectile": "arrow"` and the mage `"magic"`. Every ranged attack makes the manager emit `projectile_event(kind, from, to, flight_time)` just before `damage_event`; the controller spawns an arcing arrow (with a faint streak) or a glowing magic orb (with trail and orbiting sparks) that flies to the building and ends in an impact burst. The troop shows a release flash at the bow / a charging glow at the staff instead of the old stub. Defender archers and mages (Clan Castle) shoot visible projectiles too.
- **Building health bar** (`battle_building_target.gd`): shown above the building sprite as soon as it is attacked, with the building name and `hp / max`, colour by health (green / orange / red), a yellow "just lost" segment that drains away, and quarter ticks. Damage is still applied to the real HP immediately (simulation unchanged); the bar and hit flash drop when the arrow actually lands. Damage numbers and the hit sound wait for the landing too. Damaged non-wall buildings keep their bar; a wall's bar fades a few seconds after the last hit. The old hidden ground bar is switched off in battle (`VisualEntity.show_health_bar`).
- **Pause / speed:** projectiles, impact bursts and the bar animation follow the battle (frozen when paused, faster at 2-5x) via `BattleManager.visual_time_scale()`.
- **Zoom:** the battle camera defaults to a far zoom-out (0.42), so the bar, its text, arrows and bolts are enlarged by 1/zoom (capped) to stay readable at any zoom.
- **Bug found by the new test and fixed:** shots with different flight times can land out of order; the bar originally jumped to a stored HP value and could go back up. It now subtracts each shot's own damage when it lands, so it only ever goes down.
- **Tests:** new `tests/battle/test_attack_visuals.gd` (bar state, delayed and out-of-order hits, pause/speed, wall fade, projectile events for archer / mage / warrior / defender, effect-node lifecycle, and the real battle scene with real frames).
- **Verified visually:** screenshots were rendered with Godot under Xvfb software OpenGL at the default and a closer zoom (arrow in flight, magic bolt in flight, bar draining, bar settled); the bar text, arrows and bolts were legible. Not verified: interactive play on a real GPU, and sound balance (arrow hits use the existing `arrow.wav`; magic hits reuse the sword-hit sound).
- **Aside:** the faint white dashed box around the cannon is in the original project as well (it looks like an edge of the cannon sprite art); it was not changed.

## Progress log — AI Trial (AI vs AI), laboratory, dragon, bulk training (engine-tested headless on Godot 4.4.1)

- **AI Trial (new):** main menu "AI TRIAL · WATCH AI vs AI" and the village's blue "AI TRIAL" button open the battle scene with a fixed, hand-designed fortress (`scripts/village/trial_village.gd`, 14 buildings, walled core, strong east flank). The player's saved village is never read or written in a trial (`GameManager.trial_mode` is read once by `battle_controller.gd` and cleared).
- **Attack commander (new):** `scripts/ai/attack_commander.gd` plays the attacker with no input. It scores every deploy tile by expected damage on the way in (defense range/DPS, cannons cannot hit air, wall-crossing penalty, dwell damage), shows a heatmap of that analysis, picks the cheapest side to the Town Hall, then deploys in phases (tanks+warriors, archers+mages, dragons, adaptive reserves). Decisions are narrated live in the AI COMMANDER panel. The troops still choose targets/routes with the existing Minimax/A* code.
- **Measured:** 9 of 9 runs reached 3 stars at a fixed 60 FPS (6 at 2x, 3 at 5x; about 130 s left at 2x). A side-by-side sweep of all 8 sides showed N/NW/W/NE finish fastest and E/SE slowest (about 40 s apart); the commander picks N. A naive "everyone on the west side" drop also wins this fortress, so do **not** claim the AI beats a naive attacker here — only that it reliably 3-stars and explains its choices. Unverified: behaviour on a real GPU / at uncapped frame rates, and in the interactive editor.
- Also this round: Laboratory + troop levels, Dragon (flying, continuous fire), bulk training panel, building foundations/animations/level badges, RESET LEVELS, battle-on-a-copy so a saved layout survives attacks, building MOVE button. See the chat summaries; all covered by `tests/`.
- New test: `tests/battle/test_trial_commander.gd` (registered in `tools/run_all_tests.py`).

## Progress log — troop movement and spreading (engine-tested headless on Godot 4.4.1)

- **Walking:** `scripts/pathfinding/path_smoother.gd` turns the 4-direction grid route (a staircase) into straight shortcuts where the way is clear plus rounded corners where it is not; it never clips a wall and never moves the destination. Troops also accelerate/brake and each walks 94-106% of base speed (`troop_actor.gd`). Measured: heading change per 100 px walked fell from 215 to 90 degrees.
- **Spreading:** each ground troop claims its own attack spot around a building (`_slot_claims` in `battle_manager.gd`), walks to it before attacking, and big buildings give troops extra reach (`BattleBuildingTarget.reach_bonus`) so there are enough spots along the walls. A gentle separation pass keeps same-side troops from overlapping. Measured on the AI Trial: share of ground-troop pairs closer than 10 px went from 35% to 0.1% (worst moment 27 overlapping pairs to 1).
- Side effect to know about: melee reach against buildings grew by 8-24 px (footprint based), so combat is marginally easier. The AI Trial still reached 3 stars in 6 of 6 runs (2x and 5x, fixed 60 FPS).
- New tests: `tests/pathfinding/test_path_smoother.gd`, `tests/battle/test_troop_spreading.gd` (the latter fails with 80% overlap if claims/separation are switched off). Not verified on a real GPU or by hand in the editor.

## Progress log — defense animations, Wizard Tower, royal Town Hall (engine-tested headless on Godot 4.4.1)

- **Royal Town Hall:** `assets/generated/town_hall_royal_sprite.png` (recolour of the original: purple roof, gold ridges, red carpet, crown on the spire; 36 px of transparent padding on top, so its display size is 235x225). Village extras in `building_ambient_fx.gd`: two waving standards, a pulsing golden aura with rotating rays around the crown, glints along the ridge. Also used on the main menu.
- **Wizard Tower (new defense):** catalog entry `wizard_tower`, art `assets/generated/wizard_tower_sprite.png`. Hits ground AND air, 34 damage every 1.5 s, reach 300 px, splash 60 px (neighbours of the target take 70%). Defense numbers now live in one table, `BattleManager.DEFENSE_STATS` (cannon, archer tower, wizard tower); the troop-AI threat model and the attack commander read the wizard tower too, and the commander spreads troops out while one stands. Bolt/impact visuals: kind `"arcane"` in `combat_fx.gd`.
- **Tower animation:** `assets/shaders/region_wave.gdshader` animates cut-outs of the tower art that sit on top of it (waving banners; the archer breathes, turns to face his target, draws back as the shot charges and recoils). The battle now sends `charge_changed` and `fired` signals from `BattleBuildingTarget` through the object layer to `VisualEntity` (`set_charge`, `play_fire`). Torch glow/embers, the wizard's floating crystal and muzzle smoke also run in battle (lighter).
- **Lazy cannon:** the village cannon now uses the rotating-gun rig too and slowly looks around, with an occasional wisp of smoke; in battle it recoils and smokes when it fires. Its base art had a bite missing from the rim (visible once the barrel can turn), repaired by `tools/art/fix_cannon_base.py` into `assets/generated/cannon_base_fixed.png`.
- **Art scripts** (re-runnable, documented): `tools/art/make_royal_town_hall.py`, `make_wizard_tower.py` (also cuts the animation crops), `make_dragon.py`, `fix_cannon_base.py`.
- **Trial:** the fortress gained a Wizard Tower (15 buildings to destroy) and one more tank. Measured at a fixed 60 FPS: 3 stars in 12 of 12 final runs (2x and 5x). Earlier runs with the splash tower and the old commander dropped to ~75-90%, which is why the commander now clusters its spreading within 6 tiles of the best entry point.
- New test: `tests/battle/test_wizard_tower.gd` (splash, air targeting, animation rigs, lazy cannon). Not verified on a real GPU or by hand in the editor.

## Progress log — 8-direction movement (engine-tested headless on Godot 4.4.1)

- **What changed:** `GridPathfinder` now searches 8 directions (up, down, left, right and the four diagonals) instead of 4, so ground troops head toward their target instead of staircasing along the grid axes. All four algorithms (A*, BFS, Greedy, Weighted Best-First) use it; BFS stays unweighted (fewest moves, a diagonal is one move).
- **Costs are screen distance, not grid steps.** On the isometric map a grid-axis step is ~27 px, the diagonal that looks like straight up/down is 24 px, and the one that looks like straight left/right is 48 px (`_STEP_COST`). The heuristic is straight-line screen distance, which is consistent, so A* stays exact. An earlier version used a flat 10/14 cost and barely changed behaviour (non-axis walking 42% to 50%); screen-distance costs got it to about 62%.
- **No corner cutting:** a diagonal step needs both cells it passes between to be free, so troops never squeeze through the gap where two buildings touch. Because of that rule, reachability (the flood-fill regions in `_can_reach`) is unchanged.
- **AI distances:** route costs given to the Minimax/Alpha-Beta/Expectimax target choice and the wall-breach ranking now use `GridPathfinder.path_length()` (axis step = 1) instead of a step count.
- **Tests:** `reference_grid_pathfinder.gd` was updated the same way, and `test_pathfinder_equivalence.gd` still proves bit-for-bit identical routes and exploration order on 480 random searches. New `tests/battle/test_diagonal_movement.gd` (fails with 3 checks if the pathfinder is switched back to 4 directions).
- **Measured side effect:** the AI Trial reached 3 stars in 36 of 38 runs (95%) at a fixed 60 FPS; the two misses were 93% runs at 5x speed. It was 12 of 12 before this change, so the route change cost a little reliability; not investigated further. Not checked on a real GPU or by hand in the editor.

