extends SubViewportContainer
class_name CombatArena

## Presentation only. The server owns movement limits, hits, health and respawns.
## The small amount of local prediction here never changes authoritative state.
const PLAYER_COLORS: Array[Color] = [Color("61e5d4"), Color("ffbb79"), Color("a9a2ff"), Color("f28bb6")]
const TEAM_COLORS: Array[Color] = [Color("ff6b6b"), Color("62a9ff")]
const MOVE_SPEED: float = 5.5
const BLOCK_SPEED: float = 2.5
const GRAVITY: float = 20.0
const WorldBuilder = preload("res://scripts/world_builder.gd")
const DEFAULT_GOD_OPTIONS := {
	"move_speed": 5.5, "jump_speed": 1.0, "jump_height": 1.225,
	"max_jumps": 1, "attack_range": 2.2, "max_health": 100,
	"sprint_speed": 9.0, "crouch_speed": 2.5, "gravity": 20.0, "max_fall_speed": 30.0,
	"block_speed_multiplier": 2.5 / 5.5
}

var snapshot: Dictionary = {}
var local_id: String = ""
var mode: String = "ffa"
var god_options: Dictionary = DEFAULT_GOD_OPTIONS.duplicate()
var camera_yaw: float = 0.0
var camera_pitch: float = deg_to_rad(55.0)
var camera_distance: float = 11.5
var mouse_sensitivity: float = 0.0028
var _viewport: SubViewport
var _world: Node3D
var _scenery: Node3D
var _objective: Node3D
var _objective_sword: Node3D
var zone: String = "arena"
var _round_id: int = -1
var _camera: Camera3D
var _overlay: Control
var _actors: Dictionary = {}
var _feedback: Array[Dictionary] = []
var _camera_target: Vector3 = Vector3(0, 1, 0)
var _camera_initialized: bool = false
var _local_axis: Vector2 = Vector2.ZERO
var _local_blocking: bool = false
var _local_sprinting: bool = false
var _local_crouching: bool = false
var _snapshot_age: float = 0.0
var _predicted_jump_velocity: float = 0.0
var _jump_prediction: float = 0.0
var _prediction_jump_count: int = 0
var _event_ids: Array[String] = []
var _elapsed: float = 0.0
var _health_style: StyleBoxFlat


class ArenaOverlay extends Control:
	var arena: Node

	func _draw() -> void:
		if is_instance_valid(arena):
			arena.draw_overlay(self)


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_viewport = SubViewport.new()
	_viewport.name = "ArenaViewport"
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.size = Vector2i(maxi(2, int(size.x)), maxi(2, int(size.y)))
	_viewport.gui_disable_input = true
	add_child(_viewport)
	_world = Node3D.new()
	_world.name = "ArenaWorld"
	_viewport.add_child(_world)
	_build_environment()
	_build_floor()
	_camera = Camera3D.new()
	_camera.name = "FollowCamera"
	_camera.fov = float(god_options.get("camera_fov", 55.0))
	_camera.near = 0.08
	_camera.far = 120.0
	_camera.current = true
	_world.add_child(_camera)
	var overlay: ArenaOverlay = ArenaOverlay.new()
	overlay.arena = self
	_overlay = overlay
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_update_camera(1.0)
	if not snapshot.is_empty():
		update_snapshot(snapshot, local_id)


func _exit_tree() -> void:
	release_mouse()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_mouse()
		_local_axis = Vector2.ZERO
		_local_blocking = false
		_local_sprinting = false
		_local_crouching = false


func capture_mouse() -> void:
	if is_inside_tree():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		camera_yaw = wrapf(camera_yaw - event.relative.x * mouse_sensitivity * (-1.0 if Prefs.invert_x else 1.0), -PI, PI)
		camera_pitch = clampf(camera_pitch + event.relative.y * mouse_sensitivity * (-1.0 if Prefs.invert_y else 1.0), deg_to_rad(35.0), deg_to_rad(75.0))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(8.0, camera_distance - 0.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(20.0, camera_distance + 0.1)


func get_world_movement(raw: Vector2) -> Vector2:
	# At yaw zero, W travels toward -Z and D toward +X.
	return Vector2(cos(camera_yaw) * raw.x + sin(camera_yaw) * raw.y, -sin(camera_yaw) * raw.x + cos(camera_yaw) * raw.y).limit_length()


func get_facing_yaw() -> float:
	return camera_yaw


func set_local_input(axis: Vector2, blocking: bool, sprinting: bool = false, crouching: bool = false) -> void:
	_local_axis = axis.limit_length()
	_local_blocking = blocking
	_local_sprinting = sprinting
	_local_crouching = crouching


func predict_jump() -> void:
	if not _actors.has(local_id):
		return
	var actor: Dictionary = _actors[local_id]
	var state: Dictionary = actor.get("state", {})
	# Called only after the input controller accepts a remaining jump request.
	if float(state.get("health", 100)) > 0.0:
		_predicted_jump_velocity = sqrt(2.0 * float(god_options.get("gravity", GRAVITY)) * float(god_options.get("jump_height", 1.225))) * float(god_options.get("jump_speed", 1.0))
		_prediction_jump_count = int(state.get("jumps_used", 0)) + 1
		_jump_prediction = 0.25


func update_snapshot(data: Dictionary, my_id: String) -> void:
	var next_zone: String = "town" if str(data.get("zone", "arena")) == "town" else "arena"
	var next_round: int = int(data.get("round_id", 0))
	var reset_positions: bool = next_zone != zone or next_round != _round_id
	var rebuild_world: bool = next_zone != zone
	zone = next_zone
	_round_id = next_round
	snapshot = data
	local_id = my_id
	mode = str(data.get("mode", mode)).to_lower()
	if data.get("god_options", {}) is Dictionary:
		god_options = DEFAULT_GOD_OPTIONS.duplicate()
		god_options.merge(data.get("god_options", {}), true)
	_snapshot_age = 0.0
	if not is_instance_valid(_world):
		return
	if rebuild_world:
		_build_floor()
	_refresh_objective(data.get("match", {}).get("objective", {}))
	if reset_positions:
		_camera_initialized = false
		_jump_prediction = 0.0
		_predicted_jump_velocity = 0.0
		_prediction_jump_count = 0
		_feedback.clear()
		_local_axis = Vector2.ZERO
		_local_blocking = false
		_local_sprinting = false
		_local_crouching = false
	var present: Dictionary = {}
	for player: Dictionary in data.get("players", []):
		var player_id: String = str(player.get("id", ""))
		if player_id.is_empty():
			continue
		present[player_id] = true
		var target: Vector3 = _position_of(player)
		if not _actors.has(player_id):
			_actors[player_id] = _create_actor(player)
		var actor: Dictionary = _actors[player_id]
		var root: Node3D = actor["root"]
		var old_state: Dictionary = actor.get("state", {})
		var was_defeated: bool = float(old_state.get("health", 100)) <= 0.0
		var just_respawned: bool = was_defeated and float(player.get("health", 100)) > 0.0
		if reset_positions or root.position.distance_to(target) > 4.0 or just_respawned:
			root.position = target
			root.rotation.y = float(player.get("yaw", 0.0))
			if player_id == local_id:
				_jump_prediction = 0.0
				_predicted_jump_velocity = 0.0
		actor["state"] = player.duplicate()
		actor["target"] = target
		_refresh_actor_color(actor, player)
		var ring: Node3D = actor["ring"]
		ring.visible = player_id == local_id
	for player_id: String in _actors.keys():
		if not present.has(player_id):
			var actor: Dictionary = _actors[player_id]
			actor["root"].queue_free()
			actor["shadow"].queue_free()
			_actors.erase(player_id)
	if reset_positions and is_instance_valid(_camera):
		_update_camera(0.0)


func handle_combat_event(data: Dictionary) -> void:
	var event_id: String = str(data.get("event_id", ""))
	if not event_id.is_empty():
		if _event_ids.has(event_id):
			return
		_event_ids.append(event_id)
		if _event_ids.size() > 100:
			_event_ids.pop_front()
	var kind: String = str(data.get("kind", "hit"))
	var target_id: String = str(data.get("target", data.get("target_id", "")))
	var attacker_id: String = str(data.get("attacker", data.get("attacker_id", "")))
	if kind == "jump":
		return
	if _actors.has(attacker_id) and kind in ["hit", "blocked", "miss"]:
		var swing_speed := float(god_options.get("sword_swing_speed", 1.0)) if str(data.get("weapon", "punch")) == "sword" else float(god_options.get("attack_speed", 2.0))
		_actors[attacker_id]["swing"] = minf(0.45, 0.15 / maxf(0.2, swing_speed))

	if kind == "blocked" and _actors.has(target_id):
		_actors[target_id]["block_flash"] = 0.3
	# Only a confirmed hit with positive damage creates a floating number.
	if kind != "hit" or float(data.get("damage", 0.0)) <= 0.0 or not _actors.has(target_id):
		return
	_actors[target_id]["flash"] = 0.20
	var damage: float = float(data.get("damage", 0))
	var number: String = str(int(damage)) if is_equal_approx(damage, roundf(damage)) else String.num(damage, 2).trim_suffix("0").trim_suffix(".")
	var critical: bool = bool(data.get("critical", false))
	var at: Vector3 = _actors[target_id]["root"].position
	_feedback.append({"text": number, "color": Color("ffd185") if critical else Color("fff4ee"), "at": at + Vector3(0, 2.6, 0), "life": 1.0, "critical": critical})
	if _feedback.size() > 24:
		_feedback.pop_front()


func _process(delta: float) -> void:
	_camera.fov = float(god_options.get("camera_fov", 55.0))
	camera_distance = clampf(float(Prefs.camera_distance), float(god_options.get("camera_zoom_min", 8.0)), float(god_options.get("camera_zoom_max", 20.0)))
	if not is_instance_valid(_camera):
		return
	_elapsed += delta
	_snapshot_age += delta
	var dt: float = minf(delta, 0.06)
	for player_id: String in _actors:
		var actor: Dictionary = _actors[player_id]
		var root: Node3D = actor["root"]
		var state: Dictionary = actor["state"]
		var target: Vector3 = actor["target"]
		var before: Vector3 = root.position
		var dead: bool = float(state.get("health", 100)) <= 0.0
		var local: bool = player_id == local_id
		if local and not dead:
			var base_speed: float = float(god_options.get("move_speed", MOVE_SPEED))
			var block_multiplier: float = float(god_options.get("block_speed_multiplier", BLOCK_SPEED / MOVE_SPEED))
			var can_sprint: bool = _local_sprinting and not bool(state.get("sprint_exhausted", false)) and float(state.get("stamina", 0.0)) > 0.0
			var speed: float = base_speed
			if _local_crouching:
				speed = float(god_options.get("crouch_speed", 2.5))
			elif _local_blocking:
				speed *= block_multiplier
			elif can_sprint:
				speed = float(god_options.get("sprint_speed", 9.0))
			var velocity: Vector3 = Vector3(_local_axis.x, 0, _local_axis.y) * speed
			root.position += velocity * dt
			var predicted_target: Vector3 = target + velocity * minf(_snapshot_age, 0.15)
			root.position.x = lerpf(root.position.x, predicted_target.x, 1.0 - exp(-10.0 * dt))
			root.position.z = lerpf(root.position.z, predicted_target.z, 1.0 - exp(-10.0 * dt))
			root.position.x = clampf(root.position.x, -18.0, 18.0)
			root.position.z = clampf(root.position.z, -18.0, 18.0)
			if _jump_prediction > 0.0:
				_jump_prediction -= dt
				var gravity: float = float(god_options.get("gravity", GRAVITY)) * pow(float(god_options.get("jump_speed", 1.0)), 2.0)
				var terminal: float = float(god_options.get("max_fall_speed", 30.0))
				_predicted_jump_velocity = maxf(-terminal, _predicted_jump_velocity)
				var accelerated_time: float = clampf((_predicted_jump_velocity + terminal) / gravity, 0.0, dt)
				root.position.y = maxf(0.0, root.position.y + _predicted_jump_velocity * accelerated_time - 0.5 * gravity * accelerated_time * accelerated_time - terminal * (dt - accelerated_time))
				_predicted_jump_velocity = maxf(-terminal, _predicted_jump_velocity - gravity * dt)
				if int(state.get("jumps_used", 0)) >= _prediction_jump_count and not bool(state.get("grounded", true)):
					_jump_prediction = 0.0
			else:
				root.position.y = lerpf(root.position.y, target.y, 1.0 - exp(-20.0 * dt))
		else:
			root.position = root.position.lerp(target, 1.0 - exp(-16.0 * dt))
		var model: Node3D = actor["model"]
		var crouched: bool = _local_crouching if local and not dead else bool(state.get("crouching", false))
		# Bend the upper body backward at the hips; limb proportions never change.
		var waist: Node3D = actor["waist"]
		waist.rotation.x = lerp_angle(waist.rotation.x, PI * 0.5 if crouched and not dead else 0.0, 1.0 - exp(-18.0 * dt))
		var desired_yaw: float = camera_yaw if local and not dead else float(state.get("yaw", 0.0))
		root.rotation.y = lerp_angle(root.rotation.y, desired_yaw, 1.0 - exp(-24.0 * dt))
		model.rotation.z = lerp_angle(model.rotation.z, PI * 0.5 if dead else 0.0, 1.0 - exp(-10.0 * dt))
		model.position.y = lerpf(model.position.y, 0.25 if dead else 0.0, 1.0 - exp(-10.0 * dt))
		model.visible = not bool(state.get("invulnerable", false)) or sin(_elapsed * 22.0) > -0.45
		var moved: float = Vector2(root.position.x - before.x, root.position.z - before.z).length()
		actor["walk"] = float(actor["walk"]) + moved * 0.30
		var walk: float = sin(float(actor["walk"]) * TAU)
		var motion: float = clampf(moved / maxf(0.001, dt) / maxf(0.001, float(god_options.get("move_speed", MOVE_SPEED))), 0.0, 1.0)
		var airborne: bool = root.position.y > 0.12
		var blocking: bool = bool(state.get("block", false)) or (local and _local_blocking)
		actor["swing"] = maxf(0.0, float(actor["swing"]) - dt)
		actor["flash"] = maxf(0.0, float(actor["flash"]) - dt)
		actor["block_flash"] = maxf(0.0, float(actor["block_flash"]) - dt)
		var punch: float = maxf(float(actor["swing"]), float(state.get("punch_t", 0.0)))
		_animate_actor(actor, walk, motion, airborne, blocking, punch > 0.0, dead, dt)
		var body_material: StandardMaterial3D = actor["material"]
		var base_color: Color = actor["color"]
		body_material.albedo_color = base_color.lerp(Color.WHITE, clampf(float(actor["flash"]) * 4.0, 0.0, 0.1))
		var shield: Node3D = actor["guard"]
		shield.visible = (blocking or float(actor["block_flash"]) > 0.0) and not dead
		var shadow: Node3D = actor["shadow"]
		shadow.position = Vector3(root.position.x, 0.015, root.position.z)
		var shadow_scale: float = clampf(1.0 - root.position.y * 0.1, 0.62, 1.0)
		shadow.scale = Vector3(shadow_scale, 1, shadow_scale)
	for i: int in range(_feedback.size() - 1, -1, -1):
		_feedback[i]["life"] = float(_feedback[i]["life"]) - dt
		if float(_feedback[i]["life"]) <= 0.0:
			_feedback.remove_at(i)
	if is_instance_valid(_objective_sword):
		var objective: Dictionary = snapshot.get("match", {}).get("objective", {})
		var owner_id := str(objective.get("sword_owner", ""))
		if _actors.has(owner_id):
			var owner_actor: Dictionary = _actors[owner_id]
			var hand: Node3D = owner_actor.get("right_arm")
			if is_instance_valid(hand):
				_objective_sword.global_position = hand.global_position + hand.global_basis * Vector3(0.0, -0.9, 0.15)
				_objective_sword.global_rotation = hand.global_rotation + Vector3(0.0, 0.0, -0.35)
			else:
				_objective_sword.global_position = owner_actor["root"].global_position + Vector3(0, 1.0, 0)
			_objective_sword.visible = true
		else:
			_objective_sword.visible = true
	_update_camera(dt)
	_overlay.queue_redraw()


func _update_camera(delta: float) -> void:
	var follow: Vector3 = Vector3(0, 1, 0)
	if _actors.has(local_id):
		var actor: Dictionary = _actors[local_id]
		follow = actor["root"].position + Vector3(0, 1.0, 0)
	if not _camera_initialized:
		_camera_target = follow
		_camera_initialized = _actors.has(local_id)
	else:
		_camera_target = _camera_target.lerp(follow, 1.0 - exp(-14.0 * delta))
	var horizontal: float = cos(camera_pitch) * camera_distance
	_camera.position = _camera_target + Vector3(sin(camera_yaw) * horizontal, sin(camera_pitch) * camera_distance, cos(camera_yaw) * horizontal)
	_camera.look_at(_camera_target, Vector3.UP)


func _animate_actor(actor: Dictionary, walk: float, motion: float, airborne: bool, blocking: bool, punching: bool, dead: bool, dt: float) -> void:
	var left_leg: Node3D = actor["left_leg"]
	var right_leg: Node3D = actor["right_leg"]
	var left_arm: Node3D = actor["left_arm"]
	var right_arm: Node3D = actor["right_arm"]
	var left_elbow: Node3D = actor["left_elbow"]
	var right_elbow: Node3D = actor["right_elbow"]
	var leg_angle: float = walk * motion * 0.55 if not airborne and not dead else 0.0
	left_leg.rotation.x = lerpf(left_leg.rotation.x, -0.38 if airborne else leg_angle, 1.0 - exp(-20.0 * dt))
	right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.42 if airborne else -leg_angle, 1.0 - exp(-20.0 * dt))
	var left_angle: float = -leg_angle * 0.7
	var right_angle: float = leg_angle * 0.7
	var elbow_angle: float = 0.20
	if blocking and not dead:
		left_angle = 1.05
		right_angle = 1.05
		elbow_angle = 1.3
	elif punching and not dead:
		right_angle = 1.70
		left_angle = 0.6
		elbow_angle = 0.04
	elif airborne:
		left_angle = 0.50
		right_angle = 0.50
	left_arm.rotation.x = lerpf(left_arm.rotation.x, left_angle, 1.0 - exp(-25.0 * dt))
	right_arm.rotation.x = lerpf(right_arm.rotation.x, right_angle, 1.0 - exp(-32.0 * dt))
	left_arm.rotation.z = 0.12 if blocking else -0.06
	right_arm.rotation.z = -0.12 if blocking else 0.06
	left_elbow.rotation.x = lerpf(left_elbow.rotation.x, elbow_angle, 1.0 - exp(-24.0 * dt))
	right_elbow.rotation.x = lerpf(right_elbow.rotation.x, elbow_angle, 1.0 - exp(-24.0 * dt))


func _position_of(player: Dictionary) -> Vector3:
	return Vector3(float(player.get("x", 0.0)), float(player.get("y", 0.0)), float(player.get("z", 0.0)))


func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("8c9ba6")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d9dee2")
	environment.ambient_light_energy = 0.35
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)
	var sunlight: DirectionalLight3D = DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-60, -35, 0)
	sunlight.light_color = Color("fff5df")
	sunlight.light_energy = 0.1
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 55.0
	_world.add_child(sunlight)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 145, 0)
	fill.light_color = Color("d8e1e8")
	fill.light_energy = 0.2
	_world.add_child(fill)


func _build_floor() -> void:
	if is_instance_valid(_scenery):
		_world.remove_child(_scenery)
		_scenery.queue_free()
	_scenery = WorldBuilder.build(zone)
	_world.add_child(_scenery)

func _refresh_objective(objective: Dictionary) -> void:
	if not is_instance_valid(_world): return
	if is_instance_valid(_objective):
		_objective.queue_free()
		_objective = null
	if zone != "arena" or not bool(objective.get("enabled", false)): return
	_objective = Node3D.new()
	_objective.name = "SwordObjective"
	var crystal := MeshInstance3D.new()
	var crystal_mesh := SphereMesh.new()
	crystal_mesh.radius = 1.8
	crystal_mesh.height = 3.6
	crystal.mesh = crystal_mesh
	var crystal_mat := StandardMaterial3D.new()
	crystal_mat.albedo_color = Color(0.35, 0.1, 1.0, 0.42)
	crystal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crystal_mat.emission_enabled = true
	crystal_mat.emission = Color(0.1, 0.35, 0.55)
	crystal.material_override = crystal_mat
	var stages := maxi(1, int(objective.get("crystal_break_stages", 4)))
	var stage := int(objective.get("break_stage", 0))
	crystal.scale = Vector3.ONE * maxf(0.35, 1.0 - float(stage) / float(stages) * 0.55)
	crystal.visible = not bool(objective.get("sword_accessible", false))
	_objective.add_child(crystal)
	var sword := MeshInstance3D.new()
	_objective_sword = sword
	var blade := BoxMesh.new()
	blade.size = Vector3(0.18, 2.8, 0.42)
	sword.mesh = blade
	sword.position.y = 0.2
	var sword_mat := StandardMaterial3D.new()
	sword_mat.albedo_color = Color("d9e5f2")
	sword.material_override = sword_mat
	_objective.add_child(sword)
	if bool(objective.get("sword_dropped", false)):
		sword.position = Vector3(float(objective.get("sword_x", 0)), 0.1, float(objective.get("sword_z", 0)))
	else:
		sword.position = Vector3(0, 0.2, 0)
	_world.add_child(_objective)


func _create_actor(player: Dictionary) -> Dictionary:
	var slot: int = int(player.get("slot", 0))
	var color: Color = _player_color(player)
	var root: Node3D = Node3D.new()
	root.name = "Player_%d" % (slot + 1)
	root.position = _position_of(player)
	root.rotation.y = float(player.get("yaw", 0.0))
	_world.add_child(root)
	var model: Node3D = Node3D.new()
	model.name = "Human"
	model.scale = Vector3.ONE * (1.8 / 1.97)
	root.add_child(model)
	var waist := Node3D.new()
	waist.name = "Waist"
	waist.position.y = 0.78
	model.add_child(waist)
	var body_material: StandardMaterial3D = _material(color)
	var limb_material: StandardMaterial3D = _material(color.darkened(0.20))
	var skin_material: StandardMaterial3D = _material(Color("e5dbcd"))
	var dark_material: StandardMaterial3D = _material(Color("263844"))
	_capsule(model, 0.26, 0.69, Vector3(0, 1.18, 0), body_material)
	_box(model, Vector3(0.43, 0.22, 0.29), Vector3(0, 0.12, 0), limb_material)
	_capsule(model, 0.095, 0.16, Vector3(0, 1.56, 0), skin_material)
	_sphere(model, 0.20, Vector3(0, 1.77, 0), skin_material)
	for eye_x: float in [-0.067, 0.067]:
		_sphere(model, 0.023, Vector3(eye_x, 1.80, -0.177), dark_material)
	_box(model, Vector3(0.055, 0.07, 0.045), Vector3(0, 1.75, -0.203), skin_material)
	var limbs: Dictionary = {}
	for side_index: int in range(2):
		var sign_x: float = -1.0 if side_index == 0 else 1.0
		var side: String = "left" if side_index == 0 else "right"
		var leg: Node3D = Node3D.new()
		leg.position = Vector3(sign_x * 0.145, 0.78, 0)
		model.add_child(leg)
		_capsule(leg, 0.11, 0.63, Vector3(0, -0.31, 0), dark_material)
		_box(leg, Vector3(0.20, 0.14, 0.32), Vector3(0, -0.70, -0.055), dark_material)
		limbs[side + "_leg"] = leg
		var arm: Node3D = Node3D.new()
		arm.position = Vector3(sign_x * 0.34, 1.43, 0)
		model.add_child(arm)
		_capsule(arm, 0.10, 0.34, Vector3(0, -0.15, 0), limb_material)
		var elbow: Node3D = Node3D.new()
		elbow.position = Vector3(0, -0.30, 0)
		arm.add_child(elbow)
		_capsule(elbow, 0.085, 0.31, Vector3(0, -0.145, 0), skin_material)
		_sphere(elbow, 0.11, Vector3(0, -0.30, 0), skin_material)
		limbs[side + "_arm"] = arm
		limbs[side + "_elbow"] = elbow
	var guard_material: StandardMaterial3D = _material(Color(0.50, 0.15, 1.0, 0.30))
	guard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	guard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var guard: MeshInstance3D = _box(model, Vector3(0.9, 0.13, 0.055), Vector3(0, 1.33, -0.60), guard_material, false)
	guard.visible = false
	var ring_material: StandardMaterial3D = _material(color.lightened(0.30))
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.60
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = ring_material
	ring.position.y = 0.028
	ring.scale.y = 0.25
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var shadow_material: StandardMaterial3D = _material(Color(0.09, 0.13, 0.16, 0.26))
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shadow: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 0.47
	disc.bottom_radius = 0.47
	disc.height = 0.005
	disc.radial_segments = 32
	shadow.mesh = disc
	shadow.material_override = shadow_material
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(shadow)
	var actor: Dictionary = {"root": root, "model": model, "shadow": shadow, "ring": ring, "guard": guard, "material": body_material, "limb_material": limb_material, "ring_material": ring_material, "color": color, "state": player.duplicate(), "target": root.position, "walk": 0.0, "swing": 0.0, "flash": 0.0, "block_flash": 0.0}
	actor.merge(limbs)
	# Upper body and arms share the hip pivot, with their original rest transforms.
	for part: Node in model.get_children():
		if part == waist or part == limbs.left_leg or part == limbs.right_leg:
			continue
		part.reparent(waist, true)
	actor["waist"] = waist
	return actor


func _player_color(player: Dictionary) -> Color:
	if mode == "teams":
		return TEAM_COLORS[clampi(int(player.get("party", 0)), 0, TEAM_COLORS.size() - 1)]
	return PLAYER_COLORS[posmod(int(player.get("slot", 0)), PLAYER_COLORS.size())]


func _refresh_actor_color(actor: Dictionary, player: Dictionary) -> void:
	var color: Color = _player_color(player)
	actor["color"] = color
	var body_material: StandardMaterial3D = actor.get("material")
	if is_instance_valid(body_material):
		body_material.albedo_color = color
	var limb_material: StandardMaterial3D = actor.get("limb_material")
	if is_instance_valid(limb_material):
		limb_material.albedo_color = color.darkened(0.2)
	var ring_material: StandardMaterial3D = actor.get("ring_material")
	if is_instance_valid(ring_material):
		ring_material.albedo_color = color.lightened(0.30)


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.15
	return material


func _box(parent: Node3D, dimensions: Vector3, at: Vector3, material: Material, cast_shadow: bool = true) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	return _mesh(parent, mesh, at, material, cast_shadow)


func _capsule(parent: Node3D, radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	return _mesh(parent, mesh, at, material)


func _sphere(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _mesh(parent, mesh, at, material)


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material, cast_shadow: bool = true) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	if not cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func draw_overlay(canvas: Control) -> void:
	if not is_instance_valid(_camera):
		return
	var font: Font = get_theme_default_font()
	var occupied_labels: Array[Rect2] = []
	for player_id: String in _actors:
		if player_id == local_id:
			continue
		var actor: Dictionary = _actors[player_id]
		var state: Dictionary = actor["state"]
		var model: Node3D = actor["model"]
		var world_at: Vector3 = actor["root"].position + Vector3(0, float(actor["state"].get("body_height", 1.8)) + 0.3, 0)
		if _camera.is_position_behind(world_at):
			continue
		var screen: Vector2 = _camera.unproject_position(world_at)
		if not Rect2(Vector2(-90, -50), canvas.size + Vector2(180, 100)).has_point(screen):
			continue
		var health: float = float(state.get("health", 100))
		var maximum: float = maxf(1.0, float(state.get("max_health", 100)))

		var color: Color = actor["color"]
		var caption: String = str(state.get("name", "Player %d" % (int(state.get("slot", 0)) + 1))).left(24)
		var anchor: Vector2 = screen
		var half_width: float = maxf(40.0, font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5 + 5.0)
		var label_bounds := Rect2(screen + Vector2(-half_width, -33), Vector2(half_width * 2, 50))
		for attempt: int in range(4):
			var overlaps: bool = false
			for occupied: Rect2 in occupied_labels:
				if occupied.intersects(label_bounds):
					overlaps = true
					break
			if not overlaps:
				break
			screen.y -= 34.0
			label_bounds.position.y -= 34.0
		occupied_labels.append(label_bounds)
		if screen != anchor:
			canvas.draw_line(anchor, screen, Color(0.05, 0.08, 0.1, 0.6), 1.5)
		var bar: Rect2 = Rect2(screen + Vector2(-45, -7), Vector2(90, 7))
		canvas.draw_style_box(_health_background(), Rect2(bar.position - Vector2(2, 2), bar.size + Vector2(4, 4)))
		if health > 0:
			canvas.draw_rect(Rect2(bar.position, Vector2(90.0 * clampf(float(health) / float(maximum), 0.0, 1.0), 7)), color)
		_text_center(canvas, font, caption, screen + Vector2(0, -16), 13, Color("f2f6f8"))
	for entry: Dictionary in _feedback:
		var life: float = float(entry["life"])
		var at: Vector3 = entry["at"] + Vector3(0, (1.0 - life) * 1.2, 0)
		if _camera.is_position_behind(at):
			continue
		var color: Color = entry["color"]
		color.a = clampf(life * 3.0, 0.0, 1.0)
		_text_center(canvas, font, str(entry["text"]), _camera.unproject_position(at) + Vector2(0, -45), 25 if bool(entry.get("critical", false)) else 21, color)


func _health_background() -> StyleBoxFlat:
	if _health_style == null:
		_health_style = StyleBoxFlat.new()
		_health_style.bg_color = Color(0.045, 0.065, 0.085, 0.13)
		_health_style.corner_radius_top_left = 3
		_health_style.corner_radius_top_right = 3
		_health_style.corner_radius_bottom_left = 3
		_health_style.corner_radius_bottom_right = 3
	return _health_style


func _text_center(canvas: Control, font: Font, value: String, at: Vector2, font_size: int, color: Color) -> void:
	var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin: Vector2 = at - Vector2(width * 0.5, 0)
	canvas.draw_string_outline(font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.035, 0.05, 0.07, color.a * 0.15))
	canvas.draw_string(font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
