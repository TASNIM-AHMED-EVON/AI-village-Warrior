extends Node
## Centralized, non-blocking fade between playable scenes.

const MAIN_MENU := "res://scenes/main/Main.tscn"
const VILLAGE := "res://scenes/village/VillageScene.tscn"
const BATTLE := "res://scenes/battle/BattleScene.tscn"
const AI_ARENA := "res://scenes/ai/AIArena.tscn"

var _transitioning := false


func change_to(scene_path: String, next_state: GameManager.GameState) -> void:
	if _transitioning:
		return
	_transitioning = true
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var curtain := ColorRect.new()
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color("101b23")
	curtain.modulate.a = 0.0
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(curtain)
	var fade_in := create_tween()
	fade_in.tween_property(curtain, "modulate:a", 1.0, 0.18)
	await fade_in.finished
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Could not load scene '%s' (error %d)." % [scene_path, error])
	else:
		GameManager.set_state(next_state)
	await get_tree().process_frame
	var fade_out := create_tween()
	fade_out.tween_property(curtain, "modulate:a", 0.0, 0.24)
	await fade_out.finished
	layer.queue_free()
	_transitioning = false
