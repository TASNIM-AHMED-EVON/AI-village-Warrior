extends Control
## One visual language across title, village, battle and AI arena.

const UI_THEME := preload("res://themes/medieval_ui.tres")
const HALL := preload("res://assets/buildings/town_hall_sprite.png")
const TOWER := preload("res://assets/buildings/archer_tower_sprite.png")

var _hero: TextureRect
var _settings: Control


func _ready() -> void:
	theme = UI_THEME
	_build_menu()
	GameManager.set_state(GameManager.GameState.MAIN_MENU)
	AudioManager.play_music()
	resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func _build_menu() -> void:
	var background := ColorRect.new()
	background.color = Color("182e35")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var deep := ColorRect.new()
	deep.color = Color("10232b", 0.62)
	deep.anchor_left = 0.47
	deep.anchor_right = 1.0
	deep.anchor_bottom = 1.0
	add_child(deep)
	var accent := ColorRect.new()
	accent.color = Color("b58b50", 0.8)
	accent.anchor_top = 0.0
	accent.anchor_bottom = 0.0
	accent.anchor_right = 1.0
	accent.offset_bottom = 5
	add_child(accent)

	_hero = TextureRect.new()
	_hero.texture = HALL
	_hero.anchor_left = 0.53
	_hero.anchor_right = 0.98
	_hero.anchor_top = 0.15
	_hero.anchor_bottom = 0.86
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero)
	var hero_caption := Label.new()
	hero_caption.text = "A KINGDOM BUILT ON STRATEGY"
	hero_caption.anchor_left = 0.52
	hero_caption.anchor_right = 0.97
	hero_caption.anchor_top = 0.86
	hero_caption.anchor_bottom = 0.95
	hero_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_caption.add_theme_color_override("font_color", Color("c7af80"))
	add_child(hero_caption)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.05
	panel.anchor_right = 0.05
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 0
	panel.offset_right = 548
	panel.offset_top = -290
	panel.offset_bottom = 290
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	panel.add_child(content)
	var eyebrow := _label("TACTICS  /  BUILD  /  CONQUER", 14, "d6b675")
	content.add_child(eyebrow)
	var title := _label("AI VILLAGE\nWARS", 47, "ffe5a5")
	content.add_child(title)
	var tagline := _label("Craft your village. Command your army.\nWatch intelligent search change every battle.", 16, "bed0c8")
	content.add_child(tagline)
	content.add_spacer(false)
	_add_button(content, "  PLAY  ·  ENTER VILLAGE", _open_village, 56)
	_add_button(content, "  BATTLE  ·  TEST YOUR TACTICS", _open_battle, 50)
	_add_button(content, "  AI TRIAL  ·  WATCH AI vs AI", _open_trial, 50)
	_add_button(content, "  AI LAB  ·  EXPLORE ALGORITHMS", _open_arena, 50)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	content.add_child(buttons)
	_add_button(buttons, "SETTINGS", _show_settings, 44)
	_add_button(buttons, "EXIT", _exit_game, 44)
	var foot := _label("BFS  •  A*  •  GREEDY  •  WEIGHTED  /  MINIMAX  •  ALPHA-BETA  •  EXPECTIMAX", 11, "90a39f")
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(foot)

	_settings = Control.new()
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings.visible = false
	add_child(_settings)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.025, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.add_child(dim)
	var settings_panel := PanelContainer.new()
	settings_panel.anchor_left = 0.5
	settings_panel.anchor_right = 0.5
	settings_panel.anchor_top = 0.5
	settings_panel.anchor_bottom = 0.5
	settings_panel.offset_left = -200
	settings_panel.offset_right = 200
	settings_panel.offset_top = -150
	settings_panel.offset_bottom = 150
	_settings.add_child(settings_panel)
	var setting_items := VBoxContainer.new()
	setting_items.add_theme_constant_override("separation", 16)
	settings_panel.add_child(setting_items)
	setting_items.add_child(_label("AUDIO SETTINGS", 24, "f5d387"))
	var music_check := CheckButton.new()
	music_check.text = "Background music"
	music_check.button_pressed = AudioManager.music_enabled
	music_check.toggled.connect(AudioManager.set_music_enabled)
	setting_items.add_child(music_check)
	var sfx_check := CheckButton.new()
	sfx_check.text = "Sound effects"
	sfx_check.button_pressed = AudioManager.sfx_enabled
	sfx_check.toggled.connect(AudioManager.set_sfx_enabled)
	setting_items.add_child(sfx_check)
	setting_items.add_child(_label("Tip: F3 = AI statistics, F4 = search paths in battle", 12, "afc9bb"))
	_add_button(setting_items, "CLOSE", func() -> void: _settings.visible = false, 42)


func _apply_responsive_layout() -> void:
	if _hero != null:
		_hero.visible = size.x >= 990


func _label(value: String, font_size: int, color: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(color))
	return label


func _add_button(parent: Node, caption: String, action: Callable, height: int) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = height
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
	button.pressed.connect(action)
	parent.add_child(button)


func _open_village() -> void:
	SceneManager.change_to(SceneManager.VILLAGE, GameManager.GameState.VILLAGE)


func _open_battle() -> void:
	SceneManager.change_to(SceneManager.BATTLE, GameManager.GameState.BATTLE_DEPLOYMENT)


func _open_trial() -> void:
	GameManager.trial_mode = true
	SceneManager.change_to(SceneManager.BATTLE, GameManager.GameState.BATTLE_DEPLOYMENT)


func _open_arena() -> void:
	SceneManager.change_to(SceneManager.AI_ARENA, GameManager.GameState.AI_ARENA)


func _show_settings() -> void:
	_settings.visible = true


func _exit_game() -> void:
	get_tree().quit()
