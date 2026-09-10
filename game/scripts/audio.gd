extends Node

# All sounds are original, pre-rendered synthesis. Playback does no sample generation.
const MENU_MUSIC: AudioStreamWAV = preload("res://assets/audio/menu.wav")
const GAME_MUSIC: AudioStreamWAV = preload("res://assets/audio/arena.wav")
const EFFECTS := {
	"click": preload("res://assets/audio/click.wav"),
	"success": preload("res://assets/audio/success.wav"),
	"jump": preload("res://assets/audio/jump.wav"),
	"land": preload("res://assets/audio/land.wav"),
	"swing": preload("res://assets/audio/swing.wav"),
	"hit": preload("res://assets/audio/hit.wav"),
	"blocked": preload("res://assets/audio/blocked.wav"),
	"defeat": preload("res://assets/audio/defeat.wav"),
	"respawn": preload("res://assets/audio/respawn.wav"),
}
const EFFECT_VOICES := 16

var music_player: AudioStreamPlayer
var effects_player: AudioStreamPlayer
var music_players: Array[AudioStreamPlayer] = []
var effect_players: Array[AudioStreamPlayer] = []
var context := ""
var music_transition: Tween
var next_effect_voice := 0
var last_swing: Dictionary = {}
var stopped := false

func _ready() -> void:
	for bus_name in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	for source: AudioStreamWAV in [MENU_MUSIC, GAME_MUSIC]:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		var loop := source.duplicate() as AudioStreamWAV
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin = 0
		loop.loop_end = loop.data.size() / (4 if loop.stereo else 2)
		player.stream = loop
		player.volume_db = -60.0
		add_child(player)
		music_players.append(player)
	for _voice in range(EFFECT_VOICES):
		var player := AudioStreamPlayer.new()
		player.bus = "Effects"
		add_child(player)
		effect_players.append(player)
	effects_player = effect_players[0]
	apply()
	set_context("menu")

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	stopped = true
	if is_instance_valid(music_transition):
		music_transition.kill()
	for player: AudioStreamPlayer in music_players + effect_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	last_swing.clear()

func apply() -> void:
	_set_volume("Master", Prefs.master)
	_set_volume("Music", Prefs.music)
	_set_volume("Effects", Prefs.effects)

func _set_volume(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
	AudioServer.set_bus_mute(index, value <= 0.001)

func set_context(value: String) -> void:
	var next_context := "game" if value == "game" else "menu"
	if stopped or next_context == context or music_players.size() < 2:
		return
	context = next_context
	if is_instance_valid(music_transition):
		music_transition.kill()
	music_player = music_players[1 if context == "game" else 0]
	if not music_player.playing:
		music_player.volume_db = -60.0
		music_player.play()
	music_transition = create_tween().set_parallel(true)
	for player: AudioStreamPlayer in music_players:
		music_transition.tween_property(player, "volume_db", -3.0 if player == music_player else -60.0, 0.65)
		if player != music_player:
			music_transition.tween_callback(player.stop).set_delay(0.65)

func click() -> void:
	_play("click", -4.0)

func success() -> void:
	_play("success", -3.0)

func landing(strength: float = 1.0) -> void:
	_play("land", lerpf(-14.0, -2.0, clampf(strength, 0.0, 1.0)))

func combat_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	match kind:
		"jump":
			_play("jump", -4.0)
		"punch", "miss":
			# Practice reports miss only; online reports punch followed by hit/miss.
			var attacker := str(event.get("attacker", ""))
			var now := Time.get_ticks_msec()
			if kind == "miss" and now - int(last_swing.get(attacker, -1000)) < 80:
				return
			last_swing[attacker] = now
			_play("swing", -8.0)
		"hit":
			_play("hit", 0.0 if bool(event.get("critical", false)) else -3.0,
				0.85 if bool(event.get("critical", false)) else 1.0)
		"blocked":
			_play("blocked", -5.0)
		"defeat":
			_play("defeat", -3.0)
		"respawn":
			_play("respawn", -3.0)

func _play(effect: String, volume: float = 0.0, pitch: float = 1.0) -> void:
	if stopped or effect_players.is_empty() or not EFFECTS.has(effect):
		return
	var selected := next_effect_voice
	for offset in range(effect_players.size()):
		var candidate := (next_effect_voice + offset) % effect_players.size()
		if not effect_players[candidate].playing:
			selected = candidate
			break
	var player := effect_players[selected]
	next_effect_voice = (selected + 1) % effect_players.size()
	player.stream = EFFECTS[effect]
	player.volume_db = volume
	player.pitch_scale = pitch
	player.play()
