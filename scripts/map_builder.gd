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

	# Nudge coplanar faces apart BEFORE anything is built from the list, so the
	# meshes and the collision shapes stay in agreement.
	var nudged: int = _deconflict(boxes)
	_validate(boxes, nudged)

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

	spawn_points = _usable_spawns(MapData.spawns(), boxes)
	_bake_nav()

## Drop any spawn point buried in geometry.
##
## Widening the perimeter towers silently swallowed four of the twelve spawns,
## and the only symptom was three bots sitting at 95% idle in the behaviour
## probe. Geometry and spawns are authored in different functions, so nothing
## connected them; this does, at load, every time.
func _usable_spawns(points: Array, boxes: Array) -> Array:
	var good: Array = []
	for pt in points:
		var lo := Vector3(pt.x - 0.45, pt.y + 0.05, pt.z - 0.45)
		var hi := Vector3(pt.x + 0.45, pt.y + Tuning.stand_height, pt.z + 0.45)
		var blocked := false
		for b in boxes:
			var bp: Vector3 = b["p"]
			var bs: Vector3 = b["s"]
			if lo.x < bp.x + bs.x and hi.x > bp.x \
					and lo.y < bp.y + bs.y and hi.y > bp.y \
					and lo.z < bp.z + bs.z and hi.z > bp.z:
				blocked = true
				break
		if blocked:
			push_warning("MapBuilder: spawn %s is inside geometry, dropped" % pt)
		else:
			good.append(pt)
	if good.is_empty():
		push_error("MapBuilder: every spawn point is blocked")
		return points
	print("SPAWNCHECK ", JSON.stringify({"total": points.size(), "usable": good.size()}))
	return good

## A spawn can be clear of geometry and still be a prison. One bot spawned in a
## sealed pocket about 9 m across and paced it for an entire match, never once
## seeing an enemy — the box test above passed it happily. Only the navmesh
## knows what is actually connected, and it does not exist until after the
## bake, so this is a second pass rather than part of _usable_spawns().
func validate_reachability() -> void:
	# The navigation map is not queryable the instant the region bakes; before
	# it syncs every path comes back empty, which reads exactly like "the whole
	# map is unreachable". Wait for a real answer instead of a fixed count.
	var map: RID = get_world_3d().navigation_map
	# The navigation map is not queryable the instant the region bakes, and
	# every proxy for "is it ready yet" lied: an unsynced map reports regions,
	# a non-zero iteration id, and answers closest-point queries with the zero
	# vector, which is indistinguishable from a real answer at the origin.
	# Waiting on the measurement itself is the only honest test.
	var reach: Array[int] = []
	var waited := 0
	for _i in 40:
		await get_tree().physics_frame
		waited += 1
		reach = _reach_counts(spawn_points, map)
		if reach.max() > 0:
			break

	var need: int = maxi(1, (spawn_points.size() - 1) / 2)
	var good: Array = []
	var bad: int = 0
	for i in spawn_points.size():
		if reach[i] >= need:
			good.append(spawn_points[i])
		else:
			bad += 1
			push_warning("MapBuilder: spawn %s reaches only %d others, relocating"
				% [spawn_points[i], reach[i]])
	if good.is_empty():
		push_error("MapBuilder: no spawn reaches any other")
		return

	# Repair rather than just drop. Hand-placed spawns have now been wrong
	# twice — once buried in a tower, once sealed in a pocket — so replacements
	# are chosen from the navmesh itself: on the main component, reachable, and
	# as far from the spawns we already have as possible.
	# Top the pool back up to the authored count, not just to however many
	# survived. _usable_spawns() DROPS spawns buried in geometry while this
	# pass RELOCATES unreachable ones, and that inconsistency quietly shrank
	# the lobby: adding the market district buried three spawns and the count
	# went 12 -> 9 with nothing failing. Both failure modes are repairable.
	# Standoff has a team-side invariant: repairs for the north (+z) and
	# south (-z) pools must stay on that side. The old global repair loop could
	# replace a dropped south spawn with a perfectly reachable north point;
	# `team_spawn_pool()` then silently had too few points for one team, and its
	# fallback to all spawns put that team on the wrong side (or at the wall).
	var authored: Array = MapData.spawns()
	var target: int = authored.size()
	var sides: Array = [0]
	if MapData.map_id == "standoff":
		sides = [-1, 1]
	for side in sides:
		var side_good: Array = good.filter(func(p): return _spawn_side(p) == side)
		var side_target: int = authored.filter(func(p): return _spawn_side(p) == side).size()
		var side_bad: int = 0
		for original in spawn_points:
			if _spawn_side(original) == side and not good.has(original):
				side_bad += 1
		for _r in maxi(side_bad, side_target - side_good.size()):
			var best := Vector3.INF
			var best_score: float = -1.0
			for gx in 30:
				for gz in 30:
					var c := _repair_candidate(gx, gz, side)
					if c == Vector3.INF:
						continue
					var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, c)
					if snapped.distance_to(c) > 0.6:
						continue                       # not standable ground
					if _spawn_side(snapped) != side or not _inside_spawn_bounds(snapped):
						continue
					if not _clear_spawn(snapped, MapData.boxes()):
						continue
					var anchor: Vector3 = side_good[0] if not side_good.is_empty() else good[0]
					var path: PackedVector3Array = NavigationServer3D.map_get_path(
						map, snapped, anchor, true)
					if path.is_empty() or path[path.size() - 1].distance_to(anchor) > 2.5:
						continue                       # in a pocket like the last one
					var score: float = 1e9
					for g in side_good:
						score = minf(score, snapped.distance_to(g))
					if score > best_score:
						best_score = score
						best = snapped
			if best == Vector3.INF:
				break
			side_good.append(best)
		good = good.filter(func(p): return _spawn_side(p) != side)
		good.append_array(side_good)
	spawn_points = good
	print("REACHCHECK ", JSON.stringify({
		"kept": spawn_points.size(), "authored": target, "relocated": bad,
		"frames_waited": waited,
		"min_separation_m": snappedf(_min_separation(spawn_points), 0.1)}))

func _spawn_side(point: Vector3) -> int:
	if MapData.map_id != "standoff":
		return 0
	return 1 if point.z > 0.0 else -1

func _repair_candidate(gx: int, gz: int, side: int) -> Vector3:
	var min_coord: float = -29.0
	var step: float = 2.0
	if MapData.map_id == "standoff":
		# Keep the candidate well inside the 1 m perimeter wall. In particular,
		# do not let NavigationServer pick the walkable lip beside that wall.
		min_coord = -20.0
		step = 1.25
	var c := Vector3(min_coord + float(gx) * step, 0.0,
		min_coord + float(gz) * step)
	if MapData.map_id == "standoff" and _spawn_side(c) != side:
		return Vector3.INF
	return c

func _inside_spawn_bounds(point: Vector3) -> bool:
	if MapData.map_id != "standoff":
		return true
	return absf(point.x) <= 20.0 and absf(point.z) <= 20.0

func _clear_spawn(point: Vector3, boxes: Array) -> bool:
	var lo := Vector3(point.x - 0.45, point.y + 0.05, point.z - 0.45)
	var hi := Vector3(point.x + 0.45, point.y + Tuning.stand_height, point.z + 0.45)
	for b in boxes:
		var bp: Vector3 = b["p"]
		var bs: Vector3 = b["s"]
		if lo.x < bp.x + bs.x and hi.x > bp.x \
				and lo.y < bp.y + bs.y and hi.y > bp.y \
				and lo.z < bp.z + bs.z and hi.z > bp.z:
			return false
	return true

func _reach_counts(points: Array, map: RID) -> Array[int]:
	var out: Array[int] = []
	for a in points:
		var n := 0
		for b in points:
			if a.distance_to(b) < 0.1:
				continue
			var path: PackedVector3Array = NavigationServer3D.map_get_path(map, a, b, true)
			if path.size() > 0 and path[path.size() - 1].distance_to(b) < 2.5:
				n += 1
		out.append(n)
	return out

func _min_separation(points: Array) -> float:
	var m: float = 1e9
	for i in points.size():
		for j in range(i + 1, points.size()):
			m = minf(m, points[i].distance_to(points[j]))
	return m if m < 1e8 else 0.0

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.45
	nm.agent_height = 1.8
	nm.agent_max_climb = 1.05   # matches Tuning.step_height, so bots use stairs too
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
	return _best_spawn(spawn_points, _living(away_from)) + Vector3(0, 0.2, 0)

## TDM: pick a spawn on the side a team owns — blue on +z (the north base),
## red on -z (the south base) — so each team starts on its half of the arena.
## Falls back to all spawns if a side is empty.
func random_team_spawn(team: int, away_from: Array = []) -> Vector3:
	var pool := team_spawn_pool(team)
	if pool.is_empty():
		push_error("MapBuilder: no valid spawn points for TDM team %d" % team)
		# Keep the side invariant even if a future map edit breaks validation.
		return Vector3(-10, 0.2, 5 if team == 0 else -5)
	return _best_spawn(pool, _living(away_from)) + Vector3(0, 0.2, 0)

## The spawn points a TDM team may use: blue (team 0) owns +z, red (team 1) -z.
func team_spawn_pool(team: int) -> Array:
	return spawn_points.filter(func(p):
		return _inside_spawn_bounds(p) and ((p.z > 0.0) if team == 0 else (p.z < 0.0)))

func _living(actors: Array) -> Array:
	var out: Array = []
	for a in actors:
		if is_instance_valid(a) and a.is_alive():
			out.append(a)
	return out

func _best_spawn(pool: Array, enemies: Array) -> Vector3:
	var space := get_world_3d().direct_space_state
	var best: Vector3 = pool[Game.rng.randi() % pool.size()]
	var best_score := -1e18
	for i in 6:
		var c: Vector3 = pool[Game.rng.randi() % pool.size()]
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
	return best

## A box with a zero or negative dimension renders with inverted winding, so
## backface culling makes it invisible from the outside — you look straight
## through what should be a solid wall. Cheap to check, impossible to spot by
## reading the layout code.
## Push coincident faces apart by a hair.
##
## Two faces at exactly the same depth pointing the same way make the depth
## buffer choose per pixel per frame, which is the flicker you see in motion.
## Hand-fixing each collision does not scale and regresses the moment the
## layout changes, so this runs over the finished box list and offsets the
## smaller box of every coplanar pair outward by EPS. Six millimetres is far
## below anything visible at this scale but is many times the depth precision,
## so the winner becomes deterministic.
const EPS := 0.006

func _deconflict(boxes: Array) -> int:
	var moved := 0
	# Two passes: moving a box can bring it flush with a third one.
	for _pass in 4:
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				var a: Dictionary = boxes[i]
				var b: Dictionary = boxes[j]
				if _coplanar_area(a, b) <= 0.01:
					continue
				var av: float = a["s"].x * a["s"].y * a["s"].z
				var bv: float = b["s"].x * b["s"].y * b["s"].z
				var small: Dictionary = a if av <= bv else b
				var big: Dictionary = b if av <= bv else a
				# A pair can share planes on more than one axis — a crenellation
				# meeting another crenellation at a corner shares two. Nudging
				# only the first one leaves the others still level.
				var np: Vector3 = small["p"]
				var did := false
				for axis in 3:
					if not _shares_plane(small, big, axis):
						continue
					var dir: float = 1.0
					if absf(small["p"][axis] - big["p"][axis]) < 0.001:
						dir = -1.0
					np[axis] += dir * EPS
					did = true
				if did:
					small["p"] = np
					moved += 1
	return moved

## Does this axis carry a shared face plane, with real overlap on the other two?
func _shares_plane(a: Dictionary, b: Dictionary, axis: int) -> bool:
	var ap: Vector3 = a["p"]
	var as_: Vector3 = a["s"]
	var bp: Vector3 = b["p"]
	var bs: Vector3 = b["s"]
	var same_min: bool = absf(ap[axis] - bp[axis]) < 0.001
	var same_max: bool = absf((ap[axis] + as_[axis]) - (bp[axis] + bs[axis])) < 0.001
	if not (same_min or same_max):
		return false
	for other in 3:
		if other == axis:
			continue
		var lo: float = maxf(ap[other], bp[other])
		var hi: float = minf(ap[other] + as_[other], bp[other] + bs[other])
		if hi - lo <= 0.001:
			return false
	return true

func _validate(boxes: Array, nudged: int = 0) -> void:
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
	# A critic measured "roughly the whole SE quadrant has nothing in it but
	# scattered crates" by eye. Nothing in the build could see that, so an
	# empty region could be reintroduced by any layout edit without a warning.
	# Report playable-height cover per 16x16 m cell instead.
	# Standoff is mirror-symmetric across z=0 and half the size (48 m), so the
	# Burg grid bounds/offset would put all its cells off-center and its
	# z-mirrored pairs in different rows — the probe could never confirm the
	# map's own "fair by construction" claim (round-2 TDM critic found the
	# rows reading unequal for exactly that reason). Grid per map.
	var half: float = 32.0 if MapData.map_id == "burg" else 24.0
	var cell_size: float = 16.0
	var n: int = int(half * 2.0 / cell_size)
	var cell := {}
	for b in boxes:
		var p: Vector3 = b["p"]
		var s: Vector3 = b["s"]
		if p.y > 6.0 or s.y < 0.6:
			continue                     # roofs and floor slabs are not cover
		var key := "%d,%d" % [floori((p.x + half) / cell_size), floori((p.z + half) / cell_size)]
		cell[key] = int(cell.get(key, 0)) + 1
	var counts: Array = []
	for gz in n:
		var row: Array = []
		for gx in n:
			row.append(int(cell.get("%d,%d" % [gx, gz], 0)))
		counts.append(row)
	# Mirror-symmetry check: for standoff, every cover box must have an exact
	# z-reflection partner in the list. (Comparing 16 m grid rows instead is
	# boundary-sensitive: a box sitting exactly on a cell edge flips rows after
	# the deconfliction nudge, so the grid reports asymmetry on a perfectly
	# mirrored list — this exact test is the honest one.)
	var mirror_ok: bool = true
	if MapData.map_id == "standoff":
		var keys := {}
		for b in boxes:
			if b["p"].y > 6.0 or b["s"].y < 0.6:
				continue
			var k := "%s|%s|%s" % [_snap_v(b["p"]), _snap_v(b["s"]), b["c"]]
			keys[k] = int(keys.get(k, 0)) + 1
		for b in boxes:
			if b["p"].y > 6.0 or b["s"].y < 0.6:
				continue
			var rp := Vector3(b["p"].x, b["p"].y, -(b["p"].z + b["s"].z))
			var k := "%s|%s|%s" % [_snap_v(rp), _snap_v(b["s"]), b["c"]]
			if int(keys.get(k, 0)) < 1:
				mirror_ok = false
				break
	print("MAPCHECK ", JSON.stringify({"boxes": boxes.size(), "degenerate": bad,
		"coplanar_face_pairs": overlaps.size(), "nudged": nudged,
		"cover_per_16m_cell": counts, "mirror_symmetric": mirror_ok}))

static func _snap_v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

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
