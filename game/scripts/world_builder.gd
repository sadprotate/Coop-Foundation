extends RefCounted

## Static scenery only. The shared simulation owns bounds, spawns and interaction.
const TOWN_NPC_POSITION := Vector3(0, 0, -5)
const TOWN_SPAWNS := [Vector3(-3, 0, 2), Vector3(3, 0, 2), Vector3(-3, 0, 5), Vector3(3, 0, 5)]


static func build(zone: String) -> Node3D:
	var world := Node3D.new()
	world.name = "TownScenery" if zone == "town" else "ArenaScenery"
	world.set_meta("zone", "town" if zone == "town" else "arena")
	if zone == "town":
		_build_town(world)
	else:
		_build_arena(world)
	return world


static func _build_town(world: Node3D) -> void:
	var grass := _material(Color("65835e"))
	var stone := _material(Color("757b76"))
	var pale := _material(Color("959b90"))
	var edge := _material(Color("697571"))
	var mortar := _material(Color("676e68"))
	var gold := _material(Color("a09375"))
	_box(world, Vector3(64, 0.2, 64), Vector3(0, -0.1, 0), grass)
	# Inlaid paving stays flush with the flat authoritative walking surface.
	_box(world, Vector3(21, 0.012, 28), Vector3(0, 0.002, 1), stone, false)
	_box(world, Vector3(36, 0.012, 4.4), Vector3(0, 0.003, 0), stone, false)
	_box(world, Vector3(4.4, 0.012, 36), Vector3(0, 0.004, 0), stone, false)
	for x in range(-10, 11, 2):
		_box(world, Vector3(0.035, 0.003, 28), Vector3(x, 0.01, 1), mortar, false)
	for z in range(-12, 16, 2):
		_box(world, Vector3(21, 0.003, 0.035), Vector3(0, 0.01, z), mortar, false)
	for side: float in [-1.0, 1.0]:
		_box(world, Vector3(0.16, 0.006, 28), Vector3(side * 10.35, 0.013, 1), pale, false)
		_box(world, Vector3(21, 0.006, 0.16), Vector3(0, 0.013, 1 + side * 13.85), pale, false)
	# A heraldic circle makes the elder's location clear without a floating sign.
	_disc(world, 3.0, Vector3(0, 0.018, -5), gold)
	_disc(world, 2.82, Vector3(0, 0.021, -5), pale)
	_disc(world, 2.35, Vector3(0, 0.024, -5), stone)
	for angle in range(0, 360, 45):
		var radians: float = deg_to_rad(float(angle))
		var mark := _box(world, Vector3(0.07, 0.004, 0.55), Vector3(sin(radians) * 2.56, 0.03, -5 + cos(radians) * 2.56), gold, false)
		mark.rotation.y = radians
	for at: Vector3 in TOWN_SPAWNS:
		_disc(world, 0.72, at + Vector3(0, 0.025, 0), pale)
		_disc(world, 0.57, at + Vector3(0, 0.027, 0), stone)
	# Walls and buildings sit outside the walking bounds, so visual obstacles
	# never imply a local-only collision that the shared simulation cannot honor.
	for side: float in [-1.0, 1.0]:
		_wall(world, Vector3(side * 19.4, 0, 0), true, edge, pale)
		_wall(world, Vector3(0, 0, side * 19.4), false, edge, pale)
		for other: float in [-1.0, 1.0]:
			_tower(world, Vector3(side * 19.8, 0, other * 19.8), edge, pale)
		for z: float in [-9.0, 2.0, 12.0]:
			_house(world, Vector3(side * 24.0, 0, z), side < 0)
		_banner(world, Vector3(side * 7.5, 4.3, -19.95), 1.3, 2.6)
	_build_keep(world, edge, pale)
	# Narrow heraldic pennants flank the elder; they have no collision bodies.
	_banner(world, Vector3(-2.35, 2.7, -6.15), 0.75, 1.45)
	_banner(world, Vector3(2.35, 2.7, -6.15), 0.75, 1.45)
	world.add_child(_old_man())


static func _build_arena(world: Node3D) -> void:
	var grass := _material(Color("64865a"))
	var grass_light := _material(Color("6b8c60"))
	var stone := _material(Color("b0b7a0"))
	_box(world, Vector3(60, 0.2, 60), Vector3(0, -0.1, 0), grass)
	for strip in range(-3, 4):
		_box(world, Vector3(5, 0.006, 36), Vector3(strip * 10, 0.002, 0), grass_light, false)
	for side: float in [-1.0, 1.0]:
		_box(world, Vector3(0.15, 0.015, 36.15), Vector3(side * 18, 0.011, 0), stone, false)
		_box(world, Vector3(36.15, 0.015, 0.15), Vector3(0, 0.011, side * 18), stone, false)
		_box(world, Vector3(0.35, 0.35, 37.5), Vector3(side * 18.7, 0.175, 0), stone)
		_box(world, Vector3(37.5, 0.35, 0.35), Vector3(0, 0.175, side * 18.7), stone)
	for at: Vector3 in [Vector3(-4, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, -5), Vector3(0, 0, 5)]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.64
		ring.outer_radius = 0.70
		ring.rings = 24
		ring.ring_segments = 6
		var marker := _mesh(world, ring, at + Vector3(0, 0.018, 0), stone, false)
		marker.scale.y = 0.1
	_box(world, Vector3(0.95, 0.008, 0.06), Vector3(0, 0.016, 0), stone, false)
	_box(world, Vector3(0.06, 0.008, 0.95), Vector3(0, 0.016, 0), stone, false)


static func _wall(parent: Node3D, at: Vector3, sideways: bool, stone: Material, trim: Material) -> void:
	var wall := Node3D.new()
	wall.position = at
	wall.rotation.y = PI / 2 if sideways else 0.0
	parent.add_child(wall)
	_box(wall, Vector3(38, 3.7, 1.25), Vector3(0, 1.85, 0), stone)
	_box(wall, Vector3(38, 0.25, 1.5), Vector3(0, 3.7, 0), trim)
	for x in range(-18, 19, 2):
		_box(wall, Vector3(1.05, 0.1, 1.4), Vector3(x, 4.2, 0), trim)
	for x: float in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		_box(wall, Vector3(0.75, 3.85, 1.85), Vector3(x, 1.93, 0), trim)
		_box(wall, Vector3(0.035, 2.9, 0.016), Vector3(x + 0.42, 1.7, 0.636), stone)


static func _tower(parent: Node3D, at: Vector3, stone: Material, trim: Material) -> void:
	_cylinder(parent, 2.15, 2.35, 6.2, at + Vector3(0, 3.1, 0), stone, 12)
	_cylinder(parent, 2.45, 2.45, 0.42, at + Vector3(0, 6.2, 0), trim, 12)
	for index in range(10):
		var angle: float = TAU * index / 10.0
		var block := _box(parent, Vector3(0.1, 0.9, 0.65), at + Vector3(sin(angle) * 2.13, 6.7, cos(angle) * 2.13), trim)
		block.rotation.y = angle


static func _build_keep(parent: Node3D, stone: Material, trim: Material) -> void:
	var roof := _material(Color("456076"))
	var dark := _material(Color("3b4646"))
	_box(parent, Vector3(12, 7.5, 7), Vector3(0, 3.75, -26), stone)
	_box(parent, Vector3(12.5, 0.4, 7.5), Vector3(0, 7.5, -26), trim)
	for x: float in [-4.0, 0.0, 4.0]:
		_box(parent, Vector3(0.1, 2.1, 0.08), Vector3(x, 5.4, -22.45), dark)
	for side: float in [-1.0, 1.0]:
		_cylinder(parent, 1.65, 1.85, 10.2, Vector3(side * 6.5, 5.1, -24.5), trim, 10)
		_cylinder(parent, 0.0, 2.15, 3.8, Vector3(side * 6.5, 12.0, -24.5), roof, 10)
	_banner(parent, Vector3(0, 8.2, -22.35), 1.5, 3.0)


static func _house(parent: Node3D, at: Vector3, reverse: bool) -> void:
	var house := Node3D.new()
	house.position = at
	house.rotation.y = PI / 2 if reverse else -PI / 2
	parent.add_child(house)
	var plaster := _material(Color("d1c1a1"))
	var timber := _material(Color("675447"))
	var roof := _material(Color("715b56"))
	_box(house, Vector3(5.4, 4.0, 5.0), Vector3(0, 2, 0), plaster)
	for x: float in [-2.65, 0.0, 2.65]:
		_box(house, Vector3(0.16, 4.05, 5.1), Vector3(x, 2, 0), timber)
	for y: float in [0.2, 2.2, 4.0]:
		_box(house, Vector3(5.5, 0.18, 5.1), Vector3(0, y, 0), timber)
	for side: float in [-1.0, 1.0]:
		var slope := _box(house, Vector3(3.65, 0.25, 5.65), Vector3(side * 1.35, 4.88, 0), roof)
		slope.rotation.z = -side * 0.63


static func _banner(parent: Node3D, top: Vector3, width: float, length: float) -> void:
	var brass := _material(Color("c5ae73"))
	var cloth := _material(Color("315f83"))
	var pale := _material(Color("eddfaa"))
	_cylinder(parent, 0.035, 0.035, top.y + 0.22, Vector3(top.x, (top.y + 0.22) / 2, top.z), brass, 8)
	_box(parent, Vector3(width + 0.2, 0.065, 0.065), top, brass)
	_box(parent, Vector3(width, length, 0.035), top - Vector3(0, length / 2 + 0.05, -0.045), cloth)
	for side: float in [-1.0, 1.0]:
		_box(parent, Vector3(0.035, length, 0.012), top + Vector3(side * (width / 2 - 0.07), -length / 2 - 0.05, 0.07), brass, false)
	var emblem := _box(parent, Vector3(width * 0.30, width * 0.30, 0.035), top + Vector3(0, -length * 0.45, 0.075), pale, false)
	emblem.rotation.z = PI / 4


static func _old_man() -> Node3D:
	var elder := Node3D.new()
	elder.name = "OldMan"
	elder.position = TOWN_NPC_POSITION
	var robe := _material(Color("425b78"))
	var robe_light := _material(Color("627d94"))
	var skin := _material(Color("d7bca2"))
	var beard := _material(Color("f0efdb"))
	var dark := _material(Color("393e46"))
	var gold := _material(Color("d3b975"))
	var wood := _material(Color("7b5940"))
	_cylinder(elder, 0.25, 0.43, 1.15, Vector3(0, 0.70, 0), robe, 12)
	_sphere(elder, 0.31, Vector3(0, 1.27, 0), robe_light)
	_sphere(elder, 0.23, Vector3(0, 1.67, 0.02), skin)
	_sphere(elder, 0.242, Vector3(0, 1.71, -0.045), beard)
	_sphere(elder, 0.22, Vector3(0, 1.66, 0.05), skin)
	# White tapered beard, swept brows and a bald crown distinguish the elder.
	_cylinder(elder, 0.22, 0.045, 0.64, Vector3(0, 1.28, 0.20), beard, 10)
	for side: float in [-1.0, 1.0]:
		_sphere(elder, 0.031, Vector3(side * 0.075, 1.70, 0.245), dark)
		var brow := _box(elder, Vector3(0.105, 0.03, 0.045), Vector3(side * 0.075, 1.76, 0.24), beard)
		brow.rotation.z = side * 0.12
		_sphere(elder, 0.072, Vector3(side * 0.226, 1.66, 0.04), skin)
		_box(elder, Vector3(0.18, 0.14, 0.29), Vector3(side * 0.19, 0.08, 0.08), dark)
		var sleeve := _cylinder(elder, 0.15, 0.11, 0.56, Vector3(side * 0.34, 1.04, 0.07), robe_light, 10)
		sleeve.rotation.z = side * 0.20
		_sphere(elder, 0.09, Vector3(side * 0.40, 0.11, 0.10), skin)
	_sphere(elder, 0.065, Vector3(0, 1.62, 0.27), skin)
	_box(elder, Vector3(0.065, 0.7, 0.04), Vector3(0, 0.59, 0.36), gold, false)
	_cylinder(elder, 0.045, 0.05, 2.22, Vector3(0.51, 1.11, 0.12), wood, 8)
	_sphere(elder, 0.115, Vector3(0.51, 2.22, 0.12), gold)
	return elder


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material


static func _box(parent: Node3D, dimensions: Vector3, at: Vector3, material: Material, shadows: bool = true) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = dimensions
	return _mesh(parent, box, at, material, shadows)


static func _disc(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	return _cylinder(parent, radius, radius, 0.003, at, material, 48, false)


static func _sphere(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	return _mesh(parent, sphere, at, material)


static func _cylinder(parent: Node3D, top: float, bottom: float, height: float, at: Vector3, material: Material, segments: int = 12, shadows: bool = true) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.radial_segments = segments
	return _mesh(parent, cylinder, at, material, shadows)


static func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material, shadows: bool = true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
