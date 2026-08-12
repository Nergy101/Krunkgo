class_name MapBuilder
extends Node3D
## Turns MapData boxes into merged meshes (one draw call per colour), exact box
## collision, and a baked navmesh for the bots.

var nav_region: NavigationRegion3D
var spawn_points: Array = []

func build() -> void:
	name = "Arena"
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)

	var boxes: Array = MapData.boxes()
	var by_color: Dictionary = {}
	for b in boxes:
		var key: String = b["c"]
		if not by_color.has(key):
			by_color[key] = []
		by_color[key].append(b)

	_validate(boxes)

	for key in by_color.keys():
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_" + key
		mi.mesh = _merge(by_color[key])
		mi.material_override = Palette.material(key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		nav_region.add_child(mi)

	var static_body := StaticBody3D.new()
	static_body.name = "Collision"
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	add_child(static_body)
	for b in boxes:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = b["s"]
		cs.shape = shape
		cs.position = b["p"] + b["s"] * 0.5
		static_body.add_child(cs)

	spawn_points = MapData.spawns()
	_bake_nav()

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.45
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.55
	nm.agent_max_slope = 46.0
	nm.cell_size = 0.2
	nm.cell_height = 0.1
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)

func _merge(boxes: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in boxes:
		_emit_box(st, b["p"], b["s"])
	st.index()
	return st.commit()

const FACES := [
	[Vector3(0, 0, 1), [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]],
	[Vector3(0, 0, -1), [Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)]],
	[Vector3(1, 0, 0), [Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)]],
	[Vector3(-1, 0, 0), [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)]],
	[Vector3(0, 1, 0), [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)]],
	[Vector3(0, -1, 0), [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]],
]

## UVs are derived from WORLD position, not from the box's own extents. Two
## consequences that matter: texel density is identical on every surface no
## matter how the box is proportioned, and the brick coursing lines up across
## the seam between two separate boxes instead of restarting at each one.
func _emit_box(st: SurfaceTool, p: Vector3, s: Vector3) -> void:
	for face in FACES:
		var n: Vector3 = face[0]
		var quad: Array = face[1]
		st.set_normal(n)
		var v: Array = []
		for corner in quad:
			v.append(p + Vector3(corner.x * s.x, corner.y * s.y, corner.z * s.z))
		# Godot treats CLOCKWISE-as-seen-from-the-front as the front face, which
		# is the opposite of the right-hand-rule order these quads are declared
		# in. Emitting [0,1,2,0,2,3] wound every face backwards: back-face
		# culling then removed the near side of every box, so you looked
		# straight through walls into buildings and through crates, and every
		# visible surface was lit by an inward-pointing normal.
		var order := [0, 2, 1, 0, 3, 2]
		for i in order:
			st.set_uv(_world_uv(v[i], n))
			st.add_vertex(v[i])

static func _world_uv(w: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.5:
		return Vector2(w.x, w.z)          # floors and roofs read from above
	if absf(n.x) > 0.5:
		return Vector2(w.z, -w.y)
	return Vector2(w.x, -w.y)

## Prefers a point no living enemy currently has line of sight to, so a
## respawn never drops you straight into someone's crosshair; distance is
## still the tiebreaker so the pick does not collapse to "any unseen corner"
## on a wide-open stretch of ground. `away_from` may hold dead actors (their
## corpses do not threaten anyone) — only Actor.is_alive() ones count.
func random_spawn(away_from: Array = []) -> Vector3:
	var enemies: Array = []
	for a in away_from:
		if is_instance_valid(a) and a.is_alive():
			enemies.append(a)
	var space := get_world_3d().direct_space_state
	var best: Vector3 = spawn_points[Game.rng.randi() % spawn_points.size()]
	var best_score := -1e18
	for i in 6:
		var c: Vector3 = spawn_points[Game.rng.randi() % spawn_points.size()]
		var eye: Vector3 = c + Vector3(0, Tuning.eye_height, 0)
		var min_dist := 1e9
		var seen := 0
		for enemy in enemies:
			min_dist = minf(min_dist, c.distance_to(enemy.global_position))
			var q := PhysicsRayQueryParameters3D.create(enemy.eye_position(), eye, Actor.WORLD_MASK)
			q.collide_with_areas = false
			if space.intersect_ray(q).is_empty():
				seen += 1
		var score: float = min_dist - float(seen) * 1000.0
		if score > best_score:
			best_score = score
			best = c
	return best + Vector3(0, 0.2, 0)

## A box with a zero or negative dimension renders with inverted winding, so
## backface culling makes it invisible from the outside — you look straight
## through what should be a solid wall. Cheap to check, impossible to spot by
## reading the layout code.
func _validate(boxes: Array) -> void:
	var bad := 0
	for b in boxes:
		var s: Vector3 = b["s"]
		if s.x <= 0.0 or s.y <= 0.0 or s.z <= 0.0:
			bad += 1
			push_warning("MapBuilder: degenerate box p=%s s=%s c=%s" % [b["p"], s, b["c"]])
	# Interpenetrating boxes that share a palette key put two coplanar faces at
	# the same depth, and the depth buffer then flickers between them. That is
	# the "geometry clipping through itself" you see in motion.
	var overlaps: Array = []
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var v: float = _coplanar_area(boxes[i], boxes[j])
			if v > 0.5:
				overlaps.append({"v": v, "a": i, "b": j,
					"ca": boxes[i]["c"], "cb": boxes[j]["c"],
					"pa": boxes[i]["p"], "sa": boxes[i]["s"],
					"pb": boxes[j]["p"], "sb": boxes[j]["s"]})
	overlaps.sort_custom(func(x, y): return x["v"] > y["v"])
	for k in mini(12, overlaps.size()):
		var o: Dictionary = overlaps[k]
		print("ZFIGHT %.2f m2  %s %s%s  vs  %s %s%s" % [o["v"], o["ca"], o["pa"], o["sa"],
			o["cb"], o["pb"], o["sb"]])
	print("MAPCHECK ", JSON.stringify({"boxes": boxes.size(), "degenerate": bad,
		"coplanar_face_pairs": overlaps.size()}))

## Area of any face plane the two boxes SHARE. Coincident faces at the same
## depth are what the depth buffer flickers between; a prop merely buried
## inside a wall has no shared plane and renders cleanly.
static func _coplanar_area(a: Dictionary, b: Dictionary) -> float:
	var ap: Vector3 = a["p"]
	var as_: Vector3 = a["s"]
	var bp: Vector3 = b["p"]
	var bs: Vector3 = b["s"]
	const EPS := 0.001
	var worst := 0.0
	for axis in 3:
		var a0: float = ap[axis]
		var a1: float = ap[axis] + as_[axis]
		var b0: float = bp[axis]
		var b1: float = bp[axis] + bs[axis]
		# do they share a plane on this axis, in the same direction?
		var shares: bool = absf(a0 - b0) < EPS or absf(a1 - b1) < EPS
		if not shares:
			continue
		# and do they actually overlap on the other two axes?
		var area := 1.0
		var ok := true
		for other in 3:
			if other == axis:
				continue
			var lo: float = maxf(ap[other], bp[other])
			var hi: float = minf(ap[other] + as_[other], bp[other] + bs[other])
			if hi - lo <= EPS:
				ok = false
				break
			area *= hi - lo
		if ok:
			worst = maxf(worst, area)
	return worst

static func _overlap_volume(a: Dictionary, b: Dictionary) -> float:
	var ap: Vector3 = a["p"]
	var as_: Vector3 = a["s"]
	var bp: Vector3 = b["p"]
	var bs: Vector3 = b["s"]
	var x: float = minf(ap.x + as_.x, bp.x + bs.x) - maxf(ap.x, bp.x)
	var y: float = minf(ap.y + as_.y, bp.y + bs.y) - maxf(ap.y, bp.y)
	var z: float = minf(ap.z + as_.z, bp.z + bs.z) - maxf(ap.z, bp.z)
	if x <= 0.001 or y <= 0.001 or z <= 0.001:
		return 0.0
	return x * y * z
