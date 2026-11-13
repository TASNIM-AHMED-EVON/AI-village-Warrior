extends Control
## Functional AI lab briefing, connected to the real battle demo.

const UI_THEME := preload("res://themes/medieval_ui.tres")


func _ready() -> void:
	theme = UI_THEME
	_build()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("152932")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var centered := CenterContainer.new()
	centered.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centered)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 520)
	centered.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 15)
	panel.add_child(layout)
	var heading := Label.new()
	heading.text = "AI LAB  /  HOW THE GAME THINKS"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color("ffdd91"))
	layout.add_child(heading)
	var caption := Label.new()
	caption.text = "The battle uses your original algorithms. Choose them in the F3 panel, then press F4 to see real visited cells and paths."
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(caption)
	var divider := HSeparator.new()
	layout.add_child(divider)
	var path_title := Label.new()
	path_title.text = "PATHFINDING  ·  HOW TROOPS REACH TARGETS"
	path_title.add_theme_color_override("font_color", Color("d7b676"))
	layout.add_child(path_title)
	_add_info(layout, "BFS", "Expands cells in first-in, first-out order; shortest unweighted routes.")
	_add_info(layout, "A*", "Combines route cost g(n) and estimated remaining cost h(n).")
	_add_info(layout, "Greedy Best-First", "Prioritizes estimated distance h(n); can sacrifice path optimality.")
	_add_info(layout, "Weighted Best-First", "Scores g(n) + 1.5 × h(n), balancing speed and path length.")
	layout.add_child(HSeparator.new())
	var target_title := Label.new()
	target_title.text = "TARGET SELECTION  ·  WHICH BUILDING TO ATTACK"
	target_title.add_theme_color_override("font_color", Color("d7b676"))
	layout.add_child(target_title)
	_add_info(layout, "Minimax", "Chooses a target against the worst-case defensive response.")
	_add_info(layout, "Alpha-Beta", "Cuts unnecessary branches while keeping minimax's decision.")
	_add_info(layout, "Expectimax", "Includes hit probabilities in expected-utility decisions.")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	layout.add_child(actions)
	_button(actions, "START LIVE BATTLE DEMO", func() -> void: SceneManager.change_to(SceneManager.BATTLE, GameManager.GameState.BATTLE_DEPLOYMENT))
	_button(actions, "BACK TO MENU", func() -> void: SceneManager.change_to(SceneManager.MAIN_MENU, GameManager.GameState.MAIN_MENU))


func _add_info(parent: VBoxContainer, title: String, explanation: String) -> void:
	var label := Label.new()
	label.text = "•  %s — %s" % [title, explanation]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)


func _button(parent: Node, label: String, action: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(260, 48)
	button.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
	button.pressed.connect(action)
	parent.add_child(button)
