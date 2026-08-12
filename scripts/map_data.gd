class_name MapData
extends RefCounted
## The arena, as pure box data. Everything is axis-aligned and integer-sized and
## ramps are stair stacks, never wedges — that constraint IS the art style.
##
## Layout: a walled sand-stone village in the shape Krunker's Burg inherits from
## de_dust2. Named lanes, because a map without names is a diagram:
##
##   LONG      z = -24 .. -18, running the full width. The sniper lane. Open,
##             flanked by high walls, punished by anyone holding MID.
##   MID       the raised plaza at the centre. Overlooks LONG and both sites,
##             reachable by two stair stacks. Holding it is the whole game.
##   A-SITE    north-east courtyard behind the tall guardhouse.
##   B-SITE    south-west warehouse, two entrances, tight interior.
##   TUNNEL    covered passage from the south wall to under MID. Flank route
##             that lets you leave LONG without crossing open ground.
##   ALLEYS    3-wide gaps between the west terrace houses. Shotgun country.
##
## A box is {"p": min corner, "s": size, "c": palette key}.

const H := 9.0        # perimeter wall height
## Window aperture, in metres above the wall's own base. A 1 m slot whose sill
## sits above standing eye height (1.62) reads as a window from outside instead
## of a doorway you can shoot through.
const SILL := 2.1
const LINTEL := 3.1
const WINDOW_PERIOD := 6

static func boxes() -> Array:
	var b: Array = []
	_box(b, Vector3(-32, -1, -32), Vector3(64, 1, 64), "road")
	_ring(b, Vector3(-32, 0, -32), Vector3(64, H, 64), "wall_c", 1.0)
	_perimeter_detail(b)

	_long_lane(b)
	_mid(b)
	_a_site(b)
	_b_site(b)
	_west_terrace(b)
	_tunnel(b)
	_clutter(b)
	return b

## Burg's wall is crenellated and broken by towers at several heights. A single
## constant-height flat-topped box running 64 units on all four sides was the
## flattest silhouette in the map.
static func _perimeter_detail(b: Array) -> void:
	var x := -32.0
	while x < 32.0:
		_box(b, Vector3(x, H, -32), Vector3(1.6, 1.4, 1), "wall_c")
		_box(b, Vector3(x, H, 31), Vector3(1.6, 1.4, 1), "wall_c")
		x += 3.0
	var z := -32.0
	while z < 32.0:
		_box(b, Vector3(-32, H, z), Vector3(1, 1.4, 1.6), "wall_c")
		_box(b, Vector3(31, H, z), Vector3(1, 1.4, 1.6), "wall_c")
		z += 3.0
	# towers at three different heights so the skyline is not one flat line
	const TOWERS := [
		[Vector3(-32, 0, -32), 4.0], [Vector3(28, 0, -32), 2.0],
		[Vector3(-32, 0, 28), 2.5], [Vector3(28, 0, 28), 4.5],
		[Vector3(-2, 0, -32), 3.0], [Vector3(-32, 0, -2), 1.5],
	]
	for t in TOWERS:
		var p: Vector3 = t[0]
		var extra: float = t[1]
		_box(b, p, Vector3(4, H + extra, 4), "wall_b")
		for i in 2:
			for j in 2:
				_box(b, p + Vector3(i * 3.0, H + extra, j * 3.0),
					Vector3(1, 1.6, 1), "wall_c")

# ------------------------------------------------------------------- regions
static func _long_lane(b: Array) -> void:
	# North wall of LONG: a long high face with window slots, so MID and the
	# guardhouse can contest it but it is not a naked corridor.
	_wall_run(b, Vector3(-31, 0, -18), Vector3(1, 0, 0), 40, 6.0, 1.0, "wall_b",
		[2], 7)
	# raised firing step at the west end, reachable from the terrace roofs
	_box(b, Vector3(-31, 0, -24), Vector3(7, 3, 6), "wall_a")
	_box(b, Vector3(-31, 3, -24), Vector3(7, 1, 6), "kerb")
	_stairs(b, Vector3(-24, 0, -21), Vector3(1, 0, 0), 3, 4.0, "kerb")
	# sandbag-height cover down the lane, so it is crossable under fire
	for x in [-14, -4, 8, 18]:
		_box(b, Vector3(x, 0, -23), Vector3(3, 1, 2), "crate")
		_box(b, Vector3(x + 4, 0, -20), Vector3(2, 2, 2), "crate")

static func _mid(b: Array) -> void:
	# raised plaza
	_box(b, Vector3(-7, 0, -7), Vector3(14, 3, 14), "wall_a")
	_box(b, Vector3(-7, 3, -7), Vector3(14, 1, 14), "kerb")
	# a small roofed shrine on top: cover, and a landmark you can call out
	_building(b, Vector3(-3, 4, -3), Vector3(6, 4, 6), "wall_a", "roof", 2, "z-")
	# stairs up from the west alley and the east courtyard
	_stairs(b, Vector3(-10, 0, -3), Vector3(1, 0, 0), 4, 5.0, "kerb")
	_stairs(b, Vector3(10, 0, -1), Vector3(-1, 0, 0), 4, 5.0, "kerb")
	# low lip so you can crouch-peek LONG from the plaza edge
	_box(b, Vector3(-7, 4, -8), Vector3(14, 1, 1), "kerb")

static func _a_site(b: Array) -> void:
	# tall guardhouse: three storeys, the only roof that sees the whole map
	_building(b, Vector3(14, 0, -14), Vector3(11, 9, 10), "wall_a", "roof", 3, "x-")
	_stairs(b, Vector3(13, 0, -6), Vector3(0, 0, -1), 5, 3.0, "wood")
	# courtyard wall with a gap, so A is enterable from two sides
	_wall_run(b, Vector3(12, 0, -2), Vector3(0, 0, 1), 14, 4.0, 1.0, "wall_b", [], 0)
	_box(b, Vector3(12, 0, 6), Vector3(1, 4, 4), "wall_b")
	_building(b, Vector3(18, 0, 4), Vector3(9, 6, 9), "wall_b", "roof_alt", 2, "x-")

static func _b_site(b: Array) -> void:
	# warehouse: wide, low, two entrances, fightable interior
	_building(b, Vector3(-26, 0, 8), Vector3(16, 7, 14), "wall_b", "roof_alt", 2, "x+")
	# second entrance punched in the north face
	_box(b, Vector3(-20, 0, 8), Vector3(4, 1, 1), "wall_b")
	_box(b, Vector3(-20, 4, 8), Vector3(4, 3, 1), "wall_b")
	_stairs(b, Vector3(-9, 0, 12), Vector3(-1, 0, 0), 4, 4.0, "wood")

static func _west_terrace(b: Array) -> void:
	# three narrow houses with 3-wide alleys between them
	for i in 3:
		var z: float = -14.0 + i * 9.0
		_building(b, Vector3(-27, 0, z), Vector3(8, 6, 6), "wall_a", "roof", 2, "x+")

static func _tunnel(b: Array) -> void:
	# covered flank: walls, roof, open at both ends
	_box(b, Vector3(-3, 0, 12), Vector3(1, 4, 19), "wall_c")
	_box(b, Vector3(4, 0, 12), Vector3(1, 4, 19), "wall_c")
	_box(b, Vector3(-3, 4, 12), Vector3(8, 1, 19), "dark")
	_box(b, Vector3(-3, 4, 12), Vector3(8, 2, 1), "wall_c")

## Prop vocabulary. The first pass had 25 boxes across 3844 square units — one
## prop per 154 units — and none of them indoors or on a roof. Every reference
## frame carries six to ten discrete props, which is what makes a blocky map
## read as a place instead of a diagram.
static func _container(b: Array, p: Vector3, along_x: bool, c: String) -> void:
	var s := Vector3(5, 2.5, 2) if along_x else Vector3(2, 2.5, 5)
	_box(b, p, s, c)
	_box(b, p + Vector3(0, 2.5, 0), Vector3(s.x, 0.25, s.z), "dark")

static func _barrel(b: Array, p: Vector3) -> void:
	_box(b, p, Vector3(1, 1.5, 1), "accent")
	_box(b, p + Vector3(0, 1.5, 0), Vector3(1, 0.2, 1), "metal")

static func _pallet(b: Array, p: Vector3, high: bool) -> void:
	_box(b, p, Vector3(2, 0.3, 2), "wood")
	_box(b, p + Vector3(0, 0.3, 0), Vector3(2, 1.2 if high else 0.7, 2), "crate")

## Pole pair with a wire strung between them. Telegraph runs are one of the
## strongest silhouette cues in the reference shots — they break up empty sky.
static func _wire_run(b: Array, from: Vector3, to: Vector3) -> void:
	_box(b, from, Vector3(0.4, 6, 0.4), "wood")
	_box(b, to, Vector3(0.4, 6, 0.4), "wood")
	var d: Vector3 = to - from
	var len_x: float = absf(d.x)
	var len_z: float = absf(d.z)
	var origin := Vector3(minf(from.x, to.x), from.y + 5.4, minf(from.z, to.z))
	_box(b, origin, Vector3(maxf(len_x, 0.15), 0.15, maxf(len_z, 0.15)), "dark")

## Cantilevered awning off a wall face. Adds an overhang at head height, which
## is a cover band the map had nothing in.
static func _awning(b: Array, p: Vector3, s: Vector3) -> void:
	_box(b, p, s, "accent")
	_box(b, p + Vector3(0, -0.9, 0), Vector3(0.2, 0.9, 0.2), "wood")

static func _clutter(b: Array) -> void:
	# --- B-SITE warehouse interior: containers and pallets worth entering for
	_container(b, Vector3(-24, 0, 10), true, "metal")
	_container(b, Vector3(-24, 0, 17), true, "accent")
	_container(b, Vector3(-16, 0, 13), false, "metal")
	_container(b, Vector3(-24, 2.5, 10), true, "wood")
	for p in [Vector3(-13, 0, 10), Vector3(-13, 0, 19), Vector3(-19, 0, 20)]:
		_pallet(b, p, true)
	for p in [Vector3(-15, 0, 16), Vector3(-21, 0, 9), Vector3(-12, 0, 15)]:
		_barrel(b, p)

	# --- LONG lane: staggered hard cover at three distinct heights so peeking,
	# vaulting and hard-blocking are all different decisions
	_container(b, Vector3(-12, 0, -22), true, "metal")
	_container(b, Vector3(4, 0, -23), true, "accent")
	_container(b, Vector3(18, 0, -21), true, "metal")
	for x in [-18.0, -2.0, 12.0, 24.0]:
		_box(b, Vector3(x, 0, -20), Vector3(2, 1.5, 2), "crate")     # chest
		_pallet(b, Vector3(x + 3, 0, -23), false)
	for x in [-8.0, 8.0, 22.0]:
		_box(b, Vector3(x, 0, -19), Vector3(1.5, 2.6, 1.5), "wall_c")  # over-head

	# --- MID plaza top: four props so holding it is not standing on a table
	for p in [Vector3(-6, 4, -6), Vector3(4, 4, -6), Vector3(-6, 4, 4), Vector3(4, 4, 4)]:
		_box(b, p, Vector3(2, 1.5, 2), "crate")
	_barrel(b, Vector3(5, 4, 0))
	_barrel(b, Vector3(-6, 4, 0))

	# --- A-SITE courtyard
	_container(b, Vector3(14, 0, 2), false, "accent")
	_container(b, Vector3(20, 0, -2), true, "metal")
	for p in [Vector3(26, 0, 10), Vector3(17, 0, 14), Vector3(28, 0, -6)]:
		_barrel(b, p)
	_pallet(b, Vector3(24, 0, 6), true)

	# --- alleys and open ground
	for p in [Vector3(-16, 0, 2), Vector3(6, 0, -12), Vector3(2, 0, 20),
			Vector3(-6, 0, -16), Vector3(9, 0, 8), Vector3(-12, 0, 24),
			Vector3(-18, 0, -4), Vector3(12, 0, 22)]:
		_box(b, p, Vector3(2, 2, 2), "crate")
		_pallet(b, p + Vector3(2.2, 0, 0), false)
	for p in [Vector3(-10, 0, 4), Vector3(8, 0, 16), Vector3(-2, 0, -8)]:
		_barrel(b, p)

	# --- roofs: give every one something to fight behind
	for p in [Vector3(-25, 6.5, 10), Vector3(-25, 6.5, 18), Vector3(-14, 6.5, 14)]:
		_box(b, p, Vector3(2, 1.5, 2), "crate")
	for p in [Vector3(16, 9.5, -12), Vector3(22, 9.5, -8), Vector3(19, 9.5, -6)]:
		_box(b, p, Vector3(2, 1.5, 2), "crate")

	# --- telegraph runs across the open ground, breaking the empty skyline
	_wire_run(b, Vector3(-10, 0, -14), Vector3(-10, 0, 6))
	_wire_run(b, Vector3(10, 0, -14), Vector3(10, 0, 6))
	_wire_run(b, Vector3(-28, 0, 4), Vector3(-10, 0, 4))

	# --- awnings off the terrace houses
	for i in 3:
		_awning(b, Vector3(-19, 4, -13.0 + i * 9.0), Vector3(2.5, 0.4, 4))

static func spawns() -> Array:
	return [
		Vector3(-28, 0, -28), Vector3(28, 0, 28), Vector3(-28, 0, 28),
		Vector3(28, 0, -28), Vector3(0, 0, 28), Vector3(-16, 0, -28),
		Vector3(20, 0, 20), Vector3(-22, 0, 0), Vector3(8, 0, 24),
		Vector3(24, 0, 0), Vector3(0, 4, 6), Vector3(-14, 0, 16),
	]

## Fixed angles so critics compare like with like every round. Each one is
## checked to sit in open air — an earlier set had two cameras buried inside
## solid boxes and produced five shots of the inside of a wall.
static func review_cameras() -> Array:
	return [
		{"name": "overview", "pos": Vector3(40, 34, 40), "look": Vector3(0, 3, 0)},
		{"name": "long", "pos": Vector3(-18.5, 2.2, -21.5), "look": Vector3(28, 3.0, -21.0)},
		{"name": "mid", "pos": Vector3(-15, 2.2, 6), "look": Vector3(2, 5, -4)},
		{"name": "interior", "pos": Vector3(-18, 1.7, 15), "look": Vector3(-8, 2.2, 15)},
		{"name": "roof", "pos": Vector3(19, 14.0, -2), "look": Vector3(-2, 4, 0)},
		# Close on the west terrace. This is where three walls had a zero-width
		# pier and rendered as holes you could see straight through, so it earns
		# a permanent angle.
		{"name": "terrace", "pos": Vector3(-9, 2.0, -5), "look": Vector3(-27, 3.0, -5)},
	]

# ------------------------------------------------------------------ helpers
static func _box(b: Array, p: Vector3, s: Vector3, c: String) -> void:
	b.append({"p": p, "s": s, "c": c})

static func _ring(b: Array, p: Vector3, s: Vector3, c: String, t: float) -> void:
	_box(b, Vector3(p.x, p.y, p.z), Vector3(s.x, s.y, t), c)
	_box(b, Vector3(p.x, p.y, p.z + s.z - t), Vector3(s.x, s.y, t), c)
	_box(b, Vector3(p.x, p.y, p.z + t), Vector3(t, s.y, s.z - 2 * t), c)
	_box(b, Vector3(p.x + s.x - t, p.y, p.z + t), Vector3(t, s.y, s.z - 2 * t), c)

## A straight wall along `dir` with regular window slots punched through it.
## `window_cols` lists which repeat-index columns get a slot; `period` is how
## often the pattern repeats. Built as bands so a wall costs ~4 boxes, not 70.
static func _wall_run(b: Array, origin: Vector3, dir: Vector3, length: float,
		height: float, thick: float, key: String, window_cols: Array, period: int) -> void:
	# A zero or negative run emits a box with a zero dimension, which renders
	# with inverted winding and disappears under backface culling — you end up
	# looking straight through a wall that reads as solid in the layout code.
	if length <= 0.0:
		return
	var across := Vector3(absf(dir.z) * thick, 0, absf(dir.x) * thick)
	if across.length() < 0.01:
		across = Vector3(thick, 0, 0)
	var seg := Vector3(absf(dir.x), 0, absf(dir.z))
	if window_cols.is_empty() or period <= 0 or height < SILL + LINTEL + 0.5:
		_box(b, origin, seg * length + across + Vector3(0, height, 0), key)
		return
	# Sill band, piers between the openings, then the lintel band above.
	#
	# The first version put a 1 x 2 m hole every 4 units, so a quarter of every
	# wall was missing at exactly eye height and you could see straight into
	# every building from outside. Krunker punches narrow slots, not arcades:
	# the aperture is now 1 m tall, sits above standing eye line, and repeats
	# far less often.
	_box(b, origin, seg * length + across + Vector3(0, SILL, 0), key)
	_box(b, origin + Vector3(0, LINTEL, 0),
		seg * length + across + Vector3(0, height - LINTEL, 0), key)
	var u := 0.0
	while u < length:
		var col: int = int(u) % period
		# never open a slot in the last column, so corners always read solid
		var edge: bool = u >= length - 1.0
		if edge or not window_cols.has(col):
			_box(b, origin + dir * u + Vector3(0, SILL, 0),
				seg + across + Vector3(0, LINTEL - SILL, 0), key)
		u += 1.0

## Four walls with a doorway on `door_side`, a floor slab per storey, and a
## stepped pitched roof. Interiors are hollow and fightable.
static func _building(b: Array, p: Vector3, s: Vector3, wall: String, roof: String,
		floors: int, door_side: String) -> void:
	var wins: Array = [1]   # one opening per WINDOW_PERIOD columns
	# long faces (x)
	_face(b, p, s, "z-", wall, wins, door_side)
	_face(b, p, s, "z+", wall, wins, door_side)
	_face(b, p, s, "x-", wall, wins, door_side)
	_face(b, p, s, "x+", wall, wins, door_side)
	# Every storey gets a slab with a stairwell punched in one corner and a
	# stair run climbing into it. Without this the upper floors and the roofs
	# were sealed boxes: the three-storey guardhouse billed as "the only roof
	# that sees the whole map" was literally unreachable.
	var storey: float = s.y / float(floors)
	for f in range(1, floors):
		var y: float = p.y + storey * float(f)
		var iw: float = s.x - 2.0
		var id: float = s.z - 2.0
		var well: float = minf(3.0, minf(iw, id) - 1.0)
		if well <= 0.5:
			_box(b, Vector3(p.x + 1, y, p.z + 1), Vector3(iw, 0.5, id), "wood")
			continue
		_box(b, Vector3(p.x + 1 + well, y, p.z + 1), Vector3(iw - well, 0.5, id), "wood")
		_box(b, Vector3(p.x + 1, y, p.z + 1 + well), Vector3(well, 0.5, id - well), "wood")
		_stairs(b, Vector3(p.x + 1, y - storey, p.z + 1), Vector3(0, 0, 1),
			int(ceil(storey)), well, "wood")
	_pitched_roof(b, Vector3(p.x, p.y + s.y, p.z), Vector3(s.x, 1, s.z), roof)

static func _face(b: Array, p: Vector3, s: Vector3, side: String, key: String,
		wins: Array, door_side: String) -> void:
	var has_door: bool = side == door_side
	var origin: Vector3
	var dir: Vector3
	var length: float
	match side:
		"z-":
			origin = p; dir = Vector3(1, 0, 0); length = s.x
		"z+":
			origin = Vector3(p.x, p.y, p.z + s.z - 1); dir = Vector3(1, 0, 0); length = s.x
		"x-":
			origin = Vector3(p.x, p.y, p.z + 1); dir = Vector3(0, 0, 1); length = s.z - 2
		_:
			origin = Vector3(p.x + s.x - 1, p.y, p.z + 1); dir = Vector3(0, 0, 1); length = s.z - 2
	if length <= 0.0:
		return
	if not has_door:
		_wall_run(b, origin, dir, length, s.y, 1.0, key, wins, WINDOW_PERIOD)
		return
	# Size the opening to the wall rather than always punching 3 units. On a
	# 4-long face a fixed 3-wide door left a 0-wide pier on one side, which is
	# both a degenerate box and a doorway wider than the wall it sits in.
	var door: float = clampf(length - 2.0, 0.0, 3.0)
	if door < 1.0:
		_wall_run(b, origin, dir, length, s.y, 1.0, key, wins, WINDOW_PERIOD)
		return
	var d0: float = floorf((length - door) * 0.5)
	_wall_run(b, origin, dir, d0, s.y, 1.0, key, wins, WINDOW_PERIOD)
	_wall_run(b, origin + dir * (d0 + door), dir, length - d0 - door, s.y, 1.0, key, wins, WINDOW_PERIOD)
	var seg := Vector3(absf(dir.x), 0, absf(dir.z))
	var across := Vector3(absf(dir.z), 0, absf(dir.x))
	# lintel over the opening, only if the wall is actually taller than the door
	if s.y > 3.0:
		_box(b, origin + dir * d0 + Vector3(0, 3, 0),
			seg * door + across + Vector3(0, s.y - 3.0, 0), key)

## Stepped pyramid roof. Flat roofs everywhere were a big part of why the first
## arena read as placeholder.
static func _pitched_roof(b: Array, p: Vector3, s: Vector3, key: String) -> void:
	var steps: int = int(minf(s.x, s.z) / 2.0)
	for i in steps:
		var inset := float(i)
		var w: float = s.x - inset * 2.0
		var d: float = s.z - inset * 2.0
		if w <= 0.0 or d <= 0.0:
			break
		_box(b, Vector3(p.x + inset, p.y + float(i), p.z + inset), Vector3(w, 1, d), key)

static func _stairs(b: Array, base: Vector3, dir: Vector3, steps: int, width: float,
		key: String) -> void:
	var side := Vector3(absf(dir.z), 0, absf(dir.x))
	for i in steps:
		var p: Vector3 = base + dir * float(i)
		var s: Vector3 = Vector3(absf(dir.x), 0, absf(dir.z)) + side * width
		s.y = float(i + 1)
		if dir.x < 0.0:
			p.x -= 1.0
		if dir.z < 0.0:
			p.z -= 1.0
		_box(b, Vector3(p.x, base.y, p.z), s, key)
