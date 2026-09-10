extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("AUDIO FAIL: " + label)

func _run() -> void:
	await process_frame
	var sound := root.get_node("Sound")
	var prefs := root.get_node("Prefs")
	check(sound.context == "menu" and sound.music_player.playing, "menu music starts")
	check(sound.music_players.size() == 2 and sound.effect_players.size() == 16, "music and effects have independent players")
	for player: AudioStreamPlayer in sound.music_players:
		check(player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "music loops")
		check(player.stream.loop_end == player.stream.data.size() / 2, "loop includes every mono sample")
	var menu: AudioStreamPlayer = sound.music_player
	sound.set_context("game")
	var arena: AudioStreamPlayer = sound.music_player
	check(arena != menu and arena.playing, "game starts its own track")
	await create_timer(0.8).timeout
	check(not menu.playing and arena.playing and is_equal_approx(arena.volume_db, -3.0), "crossfade settles and stops old track")
	var before: float = arena.get_playback_position()
	sound.set_context("game")
	await create_timer(0.1).timeout
	check(arena.get_playback_position() >= before, "same context does not restart track")
	sound.set_context("menu")
	await create_timer(0.1).timeout
	sound.set_context("game")
	await create_timer(0.8).timeout
	check(arena.playing and not menu.playing, "rapid navigation cancels obsolete crossfade")
	var old_master: float = prefs.master
	var old_music: float = prefs.music
	var old_effects: float = prefs.effects
	prefs.master = 0.0
	prefs.music = 0.0
	prefs.effects = 0.0
	sound.apply()
	for bus_name in ["Master", "Music", "Effects"]:
		check(AudioServer.is_bus_mute(AudioServer.get_bus_index(bus_name)), bus_name + " respects mute")
	prefs.master = 0.6
	prefs.music = 0.4
	prefs.effects = 0.5
	sound.apply()
	for bus_name in ["Master", "Music", "Effects"]:
		check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(bus_name)), bus_name + " unmutes")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.4)), "music level applies independently")
	sound.combat_event({"kind": "punch", "attacker": "test"})
	var after_punch: int = sound.next_effect_voice
	sound.combat_event({"kind": "miss", "attacker": "test"})
	check(sound.next_effect_voice == after_punch, "punch followed by miss has one swing")
	for kind in ["jump", "hit", "blocked", "defeat", "respawn"]:
		sound.combat_event({"kind": kind, "attacker": "test"})
	sound.landing()
	sound.click()
	sound.success()
	var active_voices := 0
	for player: AudioStreamPlayer in sound.effect_players:
		if player.playing:
			active_voices += 1
	check(active_voices == 9, "nine effects play together without replacing one another")
	check(arena.playing, "effects do not interrupt music")
	prefs.master = old_master
	prefs.music = old_music
	prefs.effects = old_effects
	sound.apply()
	sound.shutdown()
	for player: AudioStreamPlayer in sound.music_players + sound.effect_players:
		check(not player.playing and player.stream == null, "shutdown releases player stream")
	await create_timer(0.1).timeout
	print("AUDIO RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
