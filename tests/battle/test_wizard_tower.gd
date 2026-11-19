extends SceneTree
## Wizard Tower (splash defense that hits air), plus the tower/cannon animations that hang off VisualEntity.

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_test_catalog_and_placement()
	await _test_splash_and_air()
	_test_animation_rigs()
	if failures == 0:
		print("Wizard tower checks passed.")
		quit(0)
	else:
		quit(1)


func _test_catalog_and_placement() -> void:
	var definition := BuildingCatalog.get_definition("wizard_tower")
	_check(not definition.is_empty() and str(definition["category"]) == "Defense", "the Wizard Tower is a Defense in the catalog")
	var village := VillageModel.new()
	village.create_starter_layout()
	village.refill_player_inventory()
	_check(village.try_place("wizard_tower", Vector2i(44, 44))["ok"], "a Wizard Tower can be built in the village")
	_check(BuildingCatalog.get_definition("town_hall")["accent"] == Color("ffd24a"), "the royal Town Hall carries its gold accent")
	_check(ResourceLoader.exists("res://assets/generated/town_hall_royal_sprite.png"), "the royal Town Hall art exists")
	_check(ResourceLoader.exists("res://assets/generated/wizard_tower_sprite.png"), "the Wizard Tower art exists")


func _test_splash_and_air() -> void:
	var village := VillageModel.new()
	village.grid.clear()
	village.structures.clear()
	village.add_layout_structure("town_hall", Vector2i(10, 10))
	village.add_layout_structure("wizard_tower", Vector2i(30, 30))
	var units_root := Node2D.new()
	var targets_root := Node2D.new()
	root.add_child(units_root)
	root.add_child(targets_root)
	var battle := BattleManager.new()
	root.add_child(battle)
	battle.begin_battle(village, units_root, targets_root)
	battle.set_process(false)
	var tower: BattleBuildingTarget
	for target in battle.building_targets.values():
		if target.building_type == "wizard_tower":
			tower = target
	_check(tower != null, "the battle builds a target for the Wizard Tower")
	for cell in [Vector2i(30, 8), Vector2i(31, 8), Vector2i(30, 9)]:
		battle.troop_stock["warrior"] = 5
	var a_cell := Vector2i(8, 36)
	_check(battle.deploy("warrior", a_cell) and battle.deploy("warrior", a_cell + Vector2i(1, 0)) and battle.deploy("warrior", a_cell + Vector2i(5, 0)), "three warriors deploy")
	for unit in battle.attacker_units:
		unit.set_process(false)
	var first: TroopActor = battle.attacker_units[0]
	var second: TroopActor = battle.attacker_units[1]
	var far: TroopActor = battle.attacker_units[2]
	# first and second are close together and close to the tower; the third is within range but far from them
	first.global_position = tower.global_position + Vector2(-110, 40)
	second.global_position = first.global_position + Vector2(30, 14)
	far.global_position = tower.global_position + Vector2(-120, 230)
	var before: Array[int] = [first.hp, second.hp, far.hp]
	battle._update_defenses(0.05)
	var hit_first: bool = first.hp < before[0]
	var hit_second: bool = second.hp < before[1]
	var hit_far: bool = far.hp < before[2]
	_check(hit_first and hit_second, "a Wizard Tower bolt hurts the troop it hits and the troop standing next to it")
	_check(not hit_far, "troops outside the splash radius are not hurt")
	_check(tower._charge >= 0.0, "the tower reports its charge to the animation")
	# a flying troop is a legal target
	for unit in battle.attacker_units:
		unit.hp = unit.max_hp
		unit.global_position = Vector2(-5000, -5000)
	_check(battle.deploy("dragon", Vector2i(8, 38)) if battle.troop_stock.get("dragon", 0) > 0 else true, "dragon deploy attempt")
	battle.troop_stock["dragon"] = 1
	_check(battle.deploy("dragon", Vector2i(8, 38)), "a dragon deploys")
	var dragon: TroopActor = battle.attacker_units[battle.attacker_units.size() - 1]
	dragon.set_process(false)
	dragon.global_position = tower.global_position + Vector2(-100, 60)
	battle.tower_cooldowns[tower.building_id] = 0.0
	battle.tower_targets.erase(tower.building_id)
	var dragon_hp := dragon.hp
	battle._update_defenses(0.05)
	_check(dragon.hp < dragon_hp, "the Wizard Tower can shoot a flying dragon")
	units_root.queue_free()
	targets_root.queue_free()
	battle.queue_free()


func _test_animation_rigs() -> void:
	var archer := VisualEntity.new()
	var archer_art: Texture2D = load("res://assets/buildings/archer_tower_sprite.png")
	archer.configure_structure("a1", "archer_tower", archer_art, Vector2(142, 201), Vector2(40, 18), Vector2.ZERO, false)
	_check(archer._archer_overlay != null and archer._banner_overlays.size() == 2, "the archer tower has an animated archer and two waving banners")
	archer.setup_decor(Vector2i(2, 2), 1, true, Vector2(142, 201))
	archer.set_cannon_aim(Vector2.LEFT)
	_check(archer._archer_overlay.flip_h, "the archer turns to face a target on his left")
	archer.set_cannon_aim(Vector2.RIGHT)
	_check(not archer._archer_overlay.flip_h, "and turns back for a target on his right")
	archer.set_charge(0.8)
	archer.play_fire()
	archer._process(0.016)
	_check(archer._recoil > 0.5, "firing gives the tower a recoil")
	var wizard := VisualEntity.new()
	wizard.configure_structure("w1", "wizard_tower", load("res://assets/generated/wizard_tower_sprite.png"), Vector2(142, 201), Vector2(40, 18), Vector2.ZERO, false)
	_check(wizard._banner_overlays.size() == 2 and wizard._archer_overlay == null, "the Wizard Tower has waving banners and no archer")
	# a lazy village cannon slowly looks around, then kicks back when it fires
	var cannon := VisualEntity.new()
	cannon.configure_structure("c1", "cannon", load("res://assets/buildings/cannon_sprite.png"), Vector2(140, 120), Vector2(40, 18), Vector2.ZERO, true)
	cannon.setup_decor(Vector2i(2, 2), 1, true, Vector2(140, 120))
	_check(cannon.idle_scan, "a village cannon is in lazy-lookout mode")
	var turned := 0.0
	for _i in range(900):
		cannon._process(0.016)
		turned = maxf(turned, absf(cannon._cannon_pivot.rotation))
	_check(turned > 0.2, "the idle cannon swings its barrel around (max %.2f rad)" % turned)
	cannon.play_fire()
	cannon._process(0.016)
	_check(cannon._cannon_gun.position != cannon._gun_rest, "the cannon kicks back when it fires")
	archer.free()
	wizard.free()
	cannon.free()
