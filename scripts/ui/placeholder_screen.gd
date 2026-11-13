extends Control

@export var screen_title := ""
@export var screen_description := ""


func _ready() -> void:
	_build_screen()


func _build_screen() -> void:
	var background := ColorRect.new()
	background.color = Color("18262c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var layout := VBoxContainer.new()
	layout.anchor_left = 0.5
	layout.anchor_top = 0.5
	layout.anchor_right = 0.5
	layout.anchor_bottom = 0.5
	layout.offset_left = -260.0
	layout.offset_top = -100.0
	layout.offset_right = 260.0
	layout.offset_bottom = 100.0
	layout.add_theme_constant_override("separation", 18)
	add_child(layout)

	var title := Label.new()
	title.text = screen_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("75dca2"))
	layout.add_child(title)

	var description := Label.new()
	description.text = screen_description
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("d5e0df"))
	layout.add_child(description)

	var back_button := Button.new()
	back_button.text = "BACK TO MAIN MENU"
	back_button.custom_minimum_size = Vector2(0, 48)
	back_button.pressed.connect(_return_to_menu)
	layout.add_child(back_button)


func _return_to_menu() -> void:
	SceneManager.change_to(SceneManager.MAIN_MENU, GameManager.GameState.MAIN_MENU)
