#!/usr/bin/env python3
"""Engine-dependent smoke/test runner. Requires an installed Godot 4.7 executable.
Does not modify project settings or the source save. Run from the project root.
"""
from pathlib import Path
import argparse, shutil, subprocess, sys

BASE = Path(__file__).resolve().parents[1]
TESTS = [
    'tests/pathfinding/test_grid_pathfinder.gd',
    'tests/pathfinding/test_path_smoother.gd',
    'tests/pathfinding/test_path_sweep.gd',
    'tests/pathfinding/test_path_visual_trace.gd',
    'tests/pathfinding/test_pathfinder_equivalence.gd',
    'tests/ai/test_battle_search_ai.gd',
    'tests/ai/test_adversarial_search.gd',
    'tests/battle/test_battle_rules.gd',
    'tests/battle/test_clan_castle.gd',
    'tests/battle/test_trial_commander.gd',
    'tests/battle/test_troop_spreading.gd',
    'tests/battle/test_diagonal_movement.gd',
    'tests/battle/test_planning_budget.gd',
    'tests/battle/test_wizard_tower.gd',
    'tests/battle/test_wall_breach.gd',
    'tests/battle/test_attack_visuals.gd',
    'tests/battle/test_battle_frames.gd',
    'tests/battle/test_troop_actor.gd',
    'tests/village/test_save_manager.gd',
    'tests/village/test_village_model.gd',
]
SCENES = ['scenes/main/Main.tscn', 'scenes/village/VillageScene.tscn',
          'scenes/battle/BattleScene.tscn', 'scenes/ai/AIArena.tscn']


def run(command, timeout=75):
    print('>', ' '.join(map(str, command)), flush=True)
    try:
        p = subprocess.run(command, cwd=BASE, text=True, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired:
        print('TIMEOUT', flush=True)
        return False
    print(p.stdout[-18000:], flush=True)
    if p.returncode != 0 or 'SCRIPT ERROR' in p.stdout or 'Parse Error' in p.stdout:
        return False
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=None, help='path to Godot 4.7 binary')
    parser.add_argument('--no-scenes', action='store_true')
    args = parser.parse_args()
    exe = args.godot or next((shutil.which(n) for n in ('godot', 'godot4', 'Godot_v4.7.2-stable_win64.exe') if shutil.which(n)), None)
    if not exe:
        print('Godot 4.7 executable not found. Run from a machine with Godot installed.')
        return 2
    print('PROJECT:', BASE)
    # Import on first use to generate `.godot/imported` for PNGs before any preload.
    if not run([exe, '--headless', '--editor', '--path', str(BASE), '--import', '--quit'], 120):
        print('IMPORT FAILED')
        return 1
    failures = []
    for test in TESTS:
        if not run([exe, '--headless', '--path', str(BASE), '--script', test]):
            failures.append(test)
    if not args.no_scenes:
        for scene in SCENES:
            if not run([exe, '--headless', '--path', str(BASE), '--scene', scene, '--quit-after', '3'], 30):
                failures.append(scene)
    print('RESULT:', 'PASS' if not failures else 'FAIL: ' + ', '.join(failures))
    return 0 if not failures else 1

if __name__ == '__main__':
    sys.exit(main())
