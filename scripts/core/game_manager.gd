extends Node
## Owns the top-level game state. Scene content must not create a second copy.

enum GameState {
	MAIN_MENU,
	VILLAGE,
	BUILD_MODE,
	ATTACK_PREPARATION,
	BATTLE_DEPLOYMENT,
	BATTLE_ACTIVE,
	BATTLE_PAUSED,
	BATTLE_RESULT,
	AI_ARENA,
	AI_ANALYSIS,
	SETTINGS,
}

signal state_changed(previous_state: GameState, new_state: GameState)

var current_state: GameState = GameState.MAIN_MENU


func set_state(new_state: GameState) -> void:
	if current_state == new_state:
		return
	var previous_state := current_state
	current_state = new_state
	state_changed.emit(previous_state, current_state)
