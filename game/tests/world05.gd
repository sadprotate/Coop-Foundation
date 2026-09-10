extends SceneTree

const WorldBuilder = preload("res://scripts/world_builder.gd")
const Arena = preload("res://scripts/combat_arena.gd")
var checks: int = 0
var failures: int = 0
var screenshots: String = ""


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("WORLD PASS: " + label)
	else:
		failures += 1
		push_error("WORLD FAIL: " + label)


func state(zone: String, round_id: int, at: Vector3) -> Dictionary:
	return {"zone": zone, "round_id": round_id, "mode": "ffa", "players": [{"id": "local", "slot": 0, "name": "Town visitor", "x": at.x, "y": at.y, "z": at.z, "yaw": 0.0, "health": 100, "max_health": 100, "grounded": true}]}


func capture(view: Control, filename: String) -> void:
	if screenshots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(screenshots)
	var picture: Image = view.get_viewport().get_texture().get_image()
	check(picture.save_png(screenshots.path_join(filename)) == OK, "Rendered " + filename)


func run() -> void:
	var safe_root := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-user-root="):
			safe_root = argument.trim_prefix("--expected-user-root=").replace("\\", "/").to_lower()
		elif argument.begins_with("--screenshots="):
			screenshots = argument.trim_prefix("--screenshots=")
	if safe_root.is_empty() or not OS.get_user_data_dir().replace("\\", "/").to_lower().begins_with(safe_root + "/"):
		push_error("World test requires an isolated workspace profile.")
		quit(1)
		return
	var town: Node3D = WorldBuilder.build("town")
	var arena: Node3D = WorldBuilder.build("arena")
	check(town.name == "TownScenery" and arena.name == "ArenaScenery", "Town and arena build distinct scenery branches")
	var elder: Node3D = town.get_node_or_null("OldMan")
	check(is_instance_valid(elder) and elder.position == Vector3(0, 0, -5), "The town elder has a stable named interaction anchor at the agreed position")
	check(arena.get_node_or_null("OldMan") == null, "The battle field has no town NPC")
	var town_meshes: Array[Node] = town.find_children("*", "MeshInstance3D", true, false)
	var arena_meshes: Array[Node] = arena.find_children("*", "MeshInstance3D", true, false)
	check(town_meshes.size() > 200 and arena_meshes.size() < 40, "Town has castle scenery and the battle field remains simple")
	check(town.find_children("*", "CollisionObject3D", true, false).is_empty() and arena.find_children("*", "CollisionObject3D", true, false).is_empty(), "Scenery introduces no local-only movement collision")
	check(WorldBuilder.TOWN_SPAWNS == [Vector3(-3, 0, 2), Vector3(3, 0, 2), Vector3(-3, 0, 5), Vector3(3, 0, 5)], "Town spawn paving agrees with the shared spawn layout")
	town.free()
	arena.free()
	var view: Control = Arena.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(view)
	view.update_snapshot(state("town", 1, Vector3(-3, 0, 2)), "local")
	await process_frame
	check(view.zone == "town" and view._scenery.get_node_or_null("OldMan") != null, "The arena renderer displays the town from the snapshot zone")
	await capture(view, "town-spawn.png")
	view.camera_distance = 20.0
	view.camera_pitch = deg_to_rad(35.0)
	await capture(view, "town-castle-overview.png")
	view.camera_distance = 9.0
	view.camera_pitch = deg_to_rad(40.0)
	view.update_snapshot(state("town", 2, Vector3(0, 0, -2.5)), "local")
	await capture(view, "town-elder.png")
	view._jump_prediction = 0.2
	view._predicted_jump_velocity = 7.0
	view.update_snapshot(state("town", 3, Vector3(1, 0, -2.5)), "local")
	check(view._actors.local.root.position == Vector3(1, 0, -2.5), "A new round snaps even a one-metre teleport")
	check(view._camera_target == Vector3(1, 1, -2.5) and view._jump_prediction == 0.0 and view._predicted_jump_velocity == 0.0, "Round transitions snap camera follow and clear stale jump prediction")
	view.update_snapshot(state("town", 3, Vector3(1.2, 0, -2.5)), "local")
	check(view._actors.local.root.position == Vector3(1, 0, -2.5), "Normal small movement snapshots keep existing smoothing")
	view.update_snapshot(state("arena", 3, Vector3(2, 0, -2.5)), "local")
	check(view._scenery.name == "ArenaScenery" and view._scenery.get_node_or_null("OldMan") == null and view._actors.local.root.position == Vector3(2, 0, -2.5), "Zone transition replaces scenery and snaps actors even without a changed round number")
	check(view._world.get_node_or_null("TownScenery") == null and view._actors.size() == 1, "Old scenery is removed without duplicating or rebuilding players")
	view.camera_distance = 11.5
	view.camera_pitch = deg_to_rad(55.0)
	view.update_snapshot(state("arena", 4, Vector3(-4, 0, 0)), "local")
	await capture(view, "arena-field.png")
	view.queue_free()
	await process_frame
	# Exercise the real practice movement and HUD with the new scenery, without
	# teleporting a fixture player into the interaction area.
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var net: Node = root.get_node("Net")
	net.start_practice()
	main.set_process(false)
	net.set_process(false)
	for step in range(100):
		var player: Dictionary = net.local_player()
		var remaining := Vector2(-float(player.x), -3.0 - float(player.z))
		if remaining.length() < 0.15:
			break
		net.move_axis = remaining.normalized()
		net._step_practice(0.025)
	net.move_axis = Vector2.ZERO
	net._step_practice(0.05)
	main.arena.set_local_input(Vector2.ZERO, false)
	await create_timer(0.2).timeout
	check(net.near_old_man() and main.arena.zone == "town" and main.health_hud.protected, "The actual practice controller walks into the safe town's NPC interaction area")
	await capture(main, "actual-town-walking.png")
	net.crouching = true
	net._step_practice(0.05)
	main.arena.set_local_input(Vector2.ZERO, false, false, true)
	await create_timer(0.2).timeout
	var local_model: Node3D = main.arena._actors.local.model
	check(bool(net.local_player().crouching) and is_equal_approx(local_model.scale.x, local_model.scale.y) and main.arena._actors.local.waist.rotation.x > 1.5 and main.arena._scenery.get_node("OldMan").scale == Vector3.ONE, "Town crouching bends at the waist without changing proportions")
	await capture(main, "actual-town-crouching.png")
	net.leave()
	main.queue_free()
	root.get_node("Sound").shutdown()
	await create_timer(0.2).timeout
	print("WORLD RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
