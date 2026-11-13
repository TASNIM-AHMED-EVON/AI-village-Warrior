extends Node
## Optional original synthesized WAV audio; direct raw-file loading prevents import race.
## The game remains playable if an audio file cannot be loaded.

var sfx_enabled := true
var music_enabled := true
var _music: AudioStreamPlayer
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _cache: Dictionary = {}


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	add_child(_music)
	for index in range(5):
		var player := AudioStreamPlayer.new()
		player.volume_db = -9.0
		add_child(player)
		_players.append(player)
	play_music()


func _stream(sound_name: String) -> AudioStreamWAV:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var path := ProjectSettings.globalize_path("res://assets/audio/%s.wav" % sound_name)
	var stream := AudioStreamWAV.load_from_file(path)
	if stream != null:
		_cache[sound_name] = stream
	return stream


func play_music() -> void:
	if not music_enabled or _music == null or _music.playing:
		return
	var stream := _stream("village_ambient")
	if stream == null:
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * float(stream.mix_rate))
	_music.stream = stream
	_music.play()


func play_sfx(sound_name: String) -> void:
	if not sfx_enabled or _players.is_empty():
		return
	var stream := _stream(sound_name)
	if stream == null:
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stop()
	player.stream = stream
	player.play()


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if _music == null:
		return
	if enabled:
		play_music()
	else:
		_music.stop()


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
