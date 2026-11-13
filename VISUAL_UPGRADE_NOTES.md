# AI Village Wars — Visual upgrade handoff (2026-11-09)

This package is a modified **complete Godot project**, not isolated patches. Open **`al-lab/project.godot`** in Godot 4.7. The existing data models, 4 pathfinding strategies, 3 target-selection strategies, save format, army stock, and win/loss conditions have not been deliberately redesigned. No external assets, paid plugins, C#, GDExtension, or game modes were introduced.

## Step 0: confirmed highest-impact visual issues (from supplied source)

1. The tank is visually modern; the rest of the art is medieval-fantasy.
2. The wall reads like a tower, while troop/building art density and size vary.
3. The old `village_object_layer.gd` concentrated ~67 `draw_*` commands into custom presentation logic.
4. HUD, menu, button styling and colors were authored independently instead of using a shared Theme.
5. The original field has 3,600 logical grass cells and many repeated grass patterns.
6. Ground shadows did not consistently anchor the buildings to their footprints.
7. Combat relied heavily on small procedural rings, sparks, and basic attack cues.
8. Search statistics existed, but there was no visual trace of expanded cells or routes.
9. AI Arena pointed to placeholder content and Settings had no functional controls.
10. Troop rendering used different sizes, and the code had no central audio player.

## Phase-by-phase implementation and exact file manifest

### Phase 1 — visual world, low gameplay risk

**Changed:** `scripts/village/village_object_layer.gd`, `scripts/village/village_terrain.gd`, `scripts/village/village_grid_overlay.gd`, `scripts/village/village_controller.gd`.

**Created:** `scripts/village/visual_entity.gd`; `assets/generated/stone_wall.png`, `siege_wagon.png`, `gold_icon.png`, `elixir_icon.png`, `gems_icon.png`, and corresponding five `.png.import` files.

- Added `VisualEntity` Node2Ds with Sprite2D / AnimatedSprite2D art, Y-sort origins, shadows, HP bars when injured, hit flashes, selection outlines and pop-in.
- Replaced the old small tower-wall and modern tank imagery in the world with **original, simple procedurally illustrated** stone walls and a fantasy battering wagon. These are pragmatic placeholders, not professional pixel art.
- Added deterministic foliage, shrubs, rocks, flowers, dirt around Town Hall, darker outside ground. Decorations never edit grid occupancy, pathfinding or save data; they only visually skip occupied nearby cells.
- The build ghost is colored green/red with art preview; the placement animation plays after successful placement.
- Imported generated PNGs are also readable from raw image paths, avoiding `preload` on unimported assets. When first opened in Godot, let the Editor import all PNGs.

**Manual check:** Main menu → PLAY. Expect a textured, populated isometric field; no bright void at camera edge; tall Town Hall and smaller low walls. Click BUILD → select wall/cannon → mouse over an allowed (green) or invalid (red) tile → click to place → expect a small pop and gold decrement. Select the new building → upgrade; select a troop → click a new valid cell to move it. Press SAVE → MENU → PLAY and confirm positions/resources persist.

### Phase 2 — cohesive UI, transitions and AI Arena

**Changed:** `scripts/ui/main_menu.gd`, `scripts/core/scene_manager.gd`, `scripts/village/village_controller.gd`, `scripts/battle/battle_controller.gd`, `scenes/ai/AIArena.tscn`, `project.godot`.

**Created:** `themes/medieval_ui.tres`, `scripts/ui/ai_arena.gd`.

- Single dark-teal/wood/gold Theme resource, including hover/pressed/disabled buttons. Illustrative main menu, settings dialog, resource icons, build thumbnails/selection previews, larger battle cards, combat stats and result reveal tween.
- Navigation now fades between scenes. AI Arena describes the exact available strategies and links to the actual battle scene instead of a placeholder.
- Kept the 1280×720 base and existing `canvas_items` scaling; **small-window and ultrawide visual review remains necessary**.

**Manual check:** Run project → check menu, press SETTINGS and toggle music/SFX → CLOSE. Open AI LAB and start battle. Return via RETREAT. Confirm scene changes fade, buttons show hover/disabled states, and text does not clip at 1280×720. Resize to 1600×900 and ~960×540; note clipping/overlap if any.

### Phase 3 — battle feedback and synthesized audio

**Changed:** `scripts/battle/battle_manager.gd`, `scripts/battle/battle_controller.gd`, `scripts/units/troop_actor.gd`, `project.godot`.

**Created:** `scripts/battle/combat_fx.gd`, `scripts/core/audio_manager.gd`, and 10 files in `assets/audio/`: `ui_click.wav`, `build_place.wav`, `troop_deploy.wav`, `sword_hit.wav`, `arrow.wav`, `cannon.wav`, `destroy.wav`, `victory.wav`, `defeat.wav`, `village_ambient.wav`.

- Battle actors now use Sprite2D/AnimatedSprite2D children instead of procedural bodies. Existing provided sprite sheets animate warrior, archer and mage (idle/walk/attack/death). Goblin and tank still have static art and simple attack effects; producing matching original animation sheets remains optional future work.
- Added small damage numbers, tower-hit feedback, CPUParticles2D rubble, and battle result animation. Existing defense arrows/cannon projectiles still use the prior simple drawing cues.
- `AudioManager` is an autoload with 5 overlapping SFX voices and synthesized WAV ambience/music. All *new* audio was synthesized rather than downloaded.

**Manual check:** Select BATTLE, choose warrior/archer/mage/tank and deploy on the outer ring. Expect new medieval wagon instead of modern tank, visible character animation for sheet-backed troops, hit numbers on damage and particles when a building falls. Toggle PAUSE then RESUME; try 1×, 2×, 3× and 5×. Complete or retreat from battle and confirm save state persists. Toggle music and effects in menu settings.

### Phase 4 — actual AI instrumentation, observational only

**Changed:** `scripts/pathfinding/grid_pathfinder.gd` (only adds an **optional** 5th dictionary parameter and writes trace data if `trace["record"]` is true), `scripts/battle/battle_manager.gd`, `scripts/battle/battle_controller.gd`, `project.godot`.

**Created:** `scripts/battle/ai_path_overlay.gd`, `tests/pathfinding/test_path_visual_trace.gd`, `tools/run_all_tests.py`.

- Press **F3** in battle for the original AI metrics plus target, route cost and expanded node count. Use the dropdowns to choose BFS, A*, Greedy, Weighted or Minimax, Alpha-Beta, Expectimax.
- Press **F4** to draw real chosen routes and actual expanded search cells (not synthetic illustrations), and press again to hide. Search colors: BFS cyan; A* golden; Greedy green; Weighted violet. Draw calls cap at 1,000 visited nodes *per trace*, while full expanded counts remain in data.
- Changing only F4 runs a display-only observation of existing target choices, so it **does not** assign new targets. Choosing an algorithm via F3 does call the existing replanning method as before.

**Manual check:** BATTLE → F3 → set BFS → deploy warrior → F4 and check cyan visited diamonds plus selected route; switch A*, Greedy and Weighted and note color changes, node counts, target and route cost. Switch Minimax, Alpha-Beta and Expectimax to compare target choices. Check that F4 toggling does not teleport troops or alter target selections by itself.

## Verification status (important)

- **Godot not installed in the packaging environment.** Executing `python tools/run_all_tests.py` produced `Godot 4.7 executable not found`. Thus **neither the original tests nor the modified tests actually ran** here; editor import, engine parsing, gameplay, screenshots and 60-FPS performance are all **unverified** for this patch.
- `tools/run_all_tests.py` performs an Editor import, seven GDScript tests (including trace equivalence), and headless scene smoke checks of menu/village/battle/AI Arena. Invoke from Godot project folder:

  ```powershell
  py tools\run_all_tests.py --godot "C:\\path\\to\\Godot_v4.7.2-stable_win64_console.exe"
  ```

  If using the non-console executable, point to that instead. The `--godot` argument accepts full executable paths. Install Python 3 if absent; there are no third-party Python dependencies.
- To test manually, import `project.godot` in the Godot 4.7 editor, wait for the full initial asset import, open the remote Scene tree on game run, test the scenarios in each phase, and check the Debugger/Output for errors and Monitor for FPS.
- Prior handoff notes state earlier source revisions passed some Godot headless scene checks. That is not evidence for the upgraded code.

## Asset provenance and licenses

| Asset group | Source | License / status |
|---|---|---|
| `assets/generated/*.png` | Pixel-style primitives made procedurally for this patch | Original; offered under CC0-1.0 for reuse |
| `assets/audio/*.wav` | Programmatically synthesized tones/noise/melody for this patch | Original; offered under CC0-1.0 for reuse |
| `themes/medieval_ui.tres` and scripts | Created for this project | Included project source, no external paid dependency |
| Existing `assets/buildings`, `assets/troops`, `assets/terrain`, other original files | Supplied in `111.zip` | Attribution/license **not provided**; verify source rights before redistributing |
| Font | Godot's default UI font (no new external download) | Built into engine; no newly bundled font file |

Optional future font: **Silkscreen**, from <https://fonts.google.com/specimen/Silkscreen> (SIL Open Font License 1.1); download and import if a more pixel-specific UI typeface is preferred. No font downloaded or bundled with this patch.

## Known limitations / risk register

- No Godot 4.7 binary was accessible, so newly authored scripts, theme serialization and animation rendering still require actual engine loading and error checks.
- This package intentionally contains no screenshots showing verified live output and no made-up frame rate.
- Static goblin and siege-wagon art still lack dedicated multi-frame animations. Effects are lightweight basic procedural effects, not a full independent visual-effects package; no full day/night cycle or animated environmental wind.
- Building effects and target sprites keep their original world position conventions; inspect their muzzle/impact alignment visually.
- Full 3600-cell grass overlay remains a static canvas drawing. Monitor FPS on the user's target laptop (goal 60 FPS), especially with F4 activated and large armies.
- Settings are session-scoped and not persisted. All existing save/load data and catalogs are intentionally preserved.
