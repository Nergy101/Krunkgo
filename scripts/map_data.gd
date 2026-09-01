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
##   MARKET    south-east corner. A stall row under awnings and a two-storey
##             shop with an outside stair to its roof. Added because a cover
##             audit of the finished box list found this 16x16 cell held ONE
##             piece of playable-height cover against 69 in the west: it was
##             flat sand you crossed on the way somewhere else.
##   ALLEYS    3-wide gaps between the west terrace houses. Shotgun country.
##
## A box is {"p": min corner, "s": size, "c": palette key}.

## Which map the game plays. "burg" is the original village; "standoff" is the
## symmetric duel arena. Set before MapBuilder.build() — harness `map=standoff`
## or the in-game M key (which rebuilds the arena live). The three entry points
## dispatch on this so geometry, spawns and review cameras all describe the
## same arena.
static var map_id: String = "burg"

static func select_map(id: String) -> void:
	if id == "standoff" or id == "burg":
		map_id = id

static func cycle_map() -> void:
	map_id = "standoff" if map_id == "burg" else "burg"

static func map_display() -> String:
	return "STANDOFF" if map_id == "standoff" else "BURG"

## Which game mode a map is played as. The symmetric standoff arena is a Team
## Deathmatch; the burg village is Free For All. Game.is_tdm() reads this.
static func mode() -> String:
	return "tdm" if map_id == "standoff" else "ffa"

static func boxes() -> Array:
	return boxes_standoff() if map_id == "standoff" else boxes_burg()

static func spawns() -> Array:
	return spawns_standoff() if map_id == "standoff" else spawns_burg()

static func review_cameras() -> Array:
	return review_cameras_standoff() if map_id == "standoff" else review_cameras_burg()

const H := 9.0        # perimeter wall height
## Window aperture, in metres above the wall's own base. A 1 m slot whose sill
## sits above standing eye height (1.62) reads as a window from outside instead
## of a doorway you can shoot through.
const SILL := 2.1
const LINTEL := 3.1
const WINDOW_PERIOD := 6

static func boxes_burg() -> Array:
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
	_market(b)
	_clutter(b)
	return b

## Burg's wall is crenellated and broken by towers at several heights. A single
## constant-height flat-topped box running 64 units on all four sides was the
## flattest silhouette in the map.
static func _perimeter_detail(b: Array) -> void:
	# Merlon width and height step through a short cycle. One identical unit
	# repeated every 3 m read as a machine-made comb rather than masonry.
	const MERLON_W := [1.6, 2.1, 1.3, 1.8]
	const MERLON_H := [1.4, 1.0, 1.7, 1.2]
	var i := 0
	var x := -32.0
	while x < 32.0:
		var w: float = MERLON_W[i % 4]
		var mh: float = MERLON_H[i % 4]
		_box(b, Vector3(x, H, -32), Vector3(w, mh, 1), "wall_c")
		_box(b, Vector3(x, H, 31), Vector3(MERLON_W[(i + 2) % 4], MERLON_H[(i + 1) % 4], 1), "wall_c")
		x += 3.0
		i += 1
	i = 0
	var z := -32.0
	while z < 32.0:
		_box(b, Vector3(-32, H, z), Vector3(1, MERLON_H[i % 4], MERLON_W[i % 4]), "wall_c")
		_box(b, Vector3(31, H, z), Vector3(1, MERLON_H[(i + 3) % 4], MERLON_W[(i + 1) % 4]), "wall_c")
		z += 3.0
		i += 1
	# towers at three different heights so the skyline is not one flat line
	# Inset by the wall thickness so a tower ABUTS the ring instead of being
	# buried in it. Overlapping put 36 m3 of coplanar faces at identical depth
	# on six towers, and the depth buffer flickered between them whenever the
	# camera moved. Touching faces are fine: they point opposite ways, so only
	# one is ever front-facing.
	# Footprint AND depth vary, not just height. Six identical 4x4 stubs at one
	# depth gave the wall a flat, repeated silhouette from every angle; Burg's
	# towers overlap and step in and out.
	# Position, extra height, footprint. Every tower used to sit flush on the
	# ring line, so the wall read as one plane with bumps; Burg's step forward
	# and back. The corner four stay flush because a corner tower that pulls
	# inward leaves a visible notch in the wall behind it.
	const TOWERS := [
		[Vector3(-31, 0, -31), 4.0, 5.0], [Vector3(26, 0, -31), 2.0, 5.0],
		[Vector3(-31, 0, 26), 2.5, 5.0], [Vector3(27, 0, 27), 4.5, 4.0],
		[Vector3(-4, 0, -29.5), 3.0, 6.0], [Vector3(-29.5, 0, -4), 1.5, 3.0],
		[Vector3(12, 0, -30.6), 0.8, 3.0], [Vector3(-30.6, 0, 12), 2.2, 4.0],
		[Vector3(29.4, 0, -12), 3.4, 2.6], [Vector3(-8, 0, 29.4), 1.8, 2.6],
	]
	for t in TOWERS:
		var tp: Vector3 = t[0]
		var extra: float = t[1]
		var fp: float = t[2]
		# Burg's towers stack setback tiers; ours were a single box with a
		# crenellation ring on top, which is why they read as stubs however
		# much the footprint varied. Tall ones get a narrower second tier.
		var h1: float = H + extra
		_box(b, tp, Vector3(fp, h1, fp), "wall_b")
		var top: float = h1
		if fp >= 3.0 and extra >= 2.0:
			var inset: float = 0.5
			var fp2: float = fp - inset * 2.0
			_box(b, tp + Vector3(inset, h1, inset), Vector3(fp2, 1.6, fp2), "wall_a")
			_box(b, tp + Vector3(inset - 0.3, h1 + 1.6, inset - 0.3),
				Vector3(fp2 + 0.6, 0.4, fp2 + 0.6), "roof_alt")   # projecting cornice
			top = h1 + 2.0
			fp = fp2 + 0.6
			tp = tp + Vector3(inset - 0.3, 0.0, inset - 0.3)
		var step: float = fp - 1.0
		for ci in 2:
			for cj in 2:
				_box(b, tp + Vector3(ci * step, top, cj * step),
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
	# Cover down the lane is seeded by _clutter now. This used to add its own
	# set and dropped a crate at exactly the same coordinate as one of them.

static func _mid(b: Array) -> void:
	# raised plaza
	_box(b, Vector3(-7, 0, -7), Vector3(14, 3, 14), "wall_a")
	_box(b, Vector3(-7, 3, -7), Vector3(14, 1, 14), "kerb")
	# a small roofed shrine on top: cover, and a landmark you can call out
	_building(b, Vector3(-3, 4, -3), Vector3(6, 4, 6), "wall_a", "roof", 2, "z-")
	# stairs up from the west alley and the east courtyard
	_stairs(b, Vector3(-11, 0, -3), Vector3(1, 0, 0), 4, 5.0, "kerb")
	_stairs(b, Vector3(11, 0, -1), Vector3(-1, 0, 0), 4, 5.0, "kerb")
	# low lip so you can crouch-peek LONG from the plaza edge
	_box(b, Vector3(-7, 4, -8), Vector3(14, 1, 1), "kerb")

static func _a_site(b: Array) -> void:
	# tall guardhouse: three storeys, the only roof that sees the whole map
	_building(b, Vector3(14, 0, -14), Vector3(11, 9, 10), "wall_a", "roof", 3, "x-", "flat")
	_stairs(b, Vector3(11, 0, -6), Vector3(0, 0, -1), 5, 3.0, "wood")
	# courtyard wall with a gap, so A is enterable from two sides
	_wall_run(b, Vector3(12, 0, -2), Vector3(0, 0, 1), 14, 4.0, 1.0, "wall_b", [], 0)
	_building(b, Vector3(18, 0, 4), Vector3(9, 6, 9), "wall_b", "roof_alt", 2, "x-", "shed")

static func _b_site(b: Array) -> void:
	# warehouse: wide, low, two entrances, fightable interior
	_building(b, Vector3(-26, 0, 8), Vector3(16, 7, 14), "wall_b", "roof_alt", 2, "x+", "shed")
	# The north face already carries a doorway from _building; two extra boxes
	# here only duplicated wall that was already there.
	_stairs(b, Vector3(-9, 0, 12), Vector3(-1, 0, 0), 3, 4.0, "wood")

static func _west_terrace(b: Array) -> void:
	# three narrow houses with 3-wide alleys between them
	# Third house pulled back to z=2: at z=4 it ran into the B-site warehouse
	# footprint and their roofs shared a plane.
	# Three copies of one house is a row of clones. Vary depth, height, roof and
	# which side the door faces so each reads as its own dwelling.
	const HOUSES := [
		[-14.0, Vector3(8, 6, 6), "wall_a", "roof", "x+", "pitch"],
		[-6.0, Vector3(9, 7, 6), "wall_b", "roof_alt", "z+", "flat"],
		[2.0, Vector3(7, 5, 6), "wall_a", "roof", "x+", "shed"],
	]
	for h in HOUSES:
		_building(b, Vector3(-27, 0, float(h[0])), h[1], String(h[2]), String(h[3]), 2, String(h[4]), String(h[5]))
	# All three took the same stepped pyramid, so the rooflines were identical
	# even though the ground plans were not. The table now picks a style each.

static func _tunnel(b: Array) -> void:
	# covered flank: walls, roof, open at both ends
	_box(b, Vector3(-3, 0, 12), Vector3(1, 4, 19), "wall_c")
	_box(b, Vector3(4, 0, 12), Vector3(1, 4, 19), "wall_c")
	_box(b, Vector3(-3, 4, 12), Vector3(8, 1, 19), "dark")
	_box(b, Vector3(-3, 5, 12), Vector3(8, 2, 1), "wall_c")

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

static func _market(b: Array) -> void:
	# Two-storey shop, door facing the courtyard, with an outside stair onto a
	# roof that overlooks both the south wall and A-site's approach.
	_building(b, Vector3(17, 0, 17), Vector3(10, 7, 11), "wall_a", "roof_alt", 2, "z-", "flat")
	_stairs(b, Vector3(28, 0, 18), Vector3(0, 0, 1), 7, 3.0, "wood")
	# Stall row: four awnings on posts with goods stacked under them. This is
	# the head-height cover band the corner had none of.
	for i in 4:
		var x: float = 17.0 + float(i) * 3.5
		_awning(b, Vector3(x, 3.2, 29.0), Vector3(3.0, 0.4, 2.5))
		_pallet(b, Vector3(x, 0, 29.5), i % 2 == 0)
	# A low wall splits the corner so it is a fight, not a field.
	_wall_run(b, Vector3(16, 0, 24), Vector3(1, 0, 0), 12, 2.5, 1.0, "wall_b", [1], 5)
	_container(b, Vector3(20, 0, 21), true, "accent")
	_container(b, Vector3(28, 0, 25), false, "metal")
	for q in [Vector3(19, 0, 27), Vector3(26, 0, 20), Vector3(30, 0, 30)]:
		_barrel(b, q)
	_box(b, Vector3(24, 0, 30), Vector3(2, 2, 2), "crate")
	_wire_run(b, Vector3(16, 0, 30), Vector3(30, 0, 30))

static func _clutter(b: Array) -> void:
	# --- B-SITE warehouse interior: containers and pallets worth entering for
	_container(b, Vector3(-21, 0, 10), true, "metal")   # clear of the stairwell
	_container(b, Vector3(-22, 0, 17), true, "accent")
	_container(b, Vector3(-16, 0, 13), false, "metal")
	_container(b, Vector3(-21, 2.75, 10), true, "wood")   # clears the lid below
	for p in [Vector3(-13, 0, 10), Vector3(-13, 0, 19), Vector3(-19, 0, 20)]:
		_pallet(b, p, true)
	for p in [Vector3(-15, 0, 16), Vector3(-21, 0, 9), Vector3(-12, 0, 15)]:
		_barrel(b, p)
	# A critic called this interior "a bare gray corridor - two blank storage
	# container walls and a red door", and it was: the only things in it were
	# containers seen end-on. Add a mezzanine you can hold, the stair up to it,
	# and shelving along the blank west wall so the space has depth.
	_box(b, Vector3(-25, 3.5, 9), Vector3(6, 0.4, 5), "wood")          # mezzanine deck
	_ring(b, Vector3(-25, 3.9, 9), Vector3(6, 1.0, 5), "metal", 0.25)  # its railing
	_stairs(b, Vector3(-19, 0, 9), Vector3(-1, 0, 0), 4, 2.5, "metal") # up to it
	for sy in [0.0, 1.6, 3.2]:
		_box(b, Vector3(-25.6, sy, 15), Vector3(1.4, 0.3, 7), "wood")  # shelf boards
	_box(b, Vector3(-25.6, 0, 15), Vector3(0.35, 3.5, 0.35), "metal")  # uprights
	_box(b, Vector3(-25.6, 0, 21.6), Vector3(0.35, 3.5, 0.35), "metal")
	for q in [Vector3(-24, 1.9, 16), Vector3(-24, 3.5, 19), Vector3(-24, 0.3, 20)]:
		_box(b, q, Vector3(1.2, 1.2, 1.2), "crate")                    # stock on the shelves

	# --- LONG lane: staggered hard cover at three distinct heights so peeking,
	# vaulting and hard-blocking are all different decisions
	_container(b, Vector3(-12, 0, -22), true, "metal")
	_container(b, Vector3(4, 0, -23), true, "accent")
	_container(b, Vector3(18, 0, -21), true, "metal")
	_container(b, Vector3(-24, 0, -22), true, "accent")
	for p in [Vector3(-6, 0, -22), Vector3(14, 0, -23), Vector3(2, 0, -21)]:
		_barrel(b, p)
	_pallet(b, Vector3(-15, 0, -21), true)
	_pallet(b, Vector3(21, 0, -23), false)
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

	# Cover on the flat surfaces people actually fight on. Crates on a stepped
	# pyramid roof always ended up buried inside a step, sharing a face plane
	# with it and flickering.
	for p in [Vector3(-31, 7, -3), Vector3(26, 7, -3)]:
		_box(b, p, Vector3(2, 1.5, 2), "crate")
	for p in [Vector3(-5, 4, -6), Vector3(3, 4, 3)]:
		_box(b, p, Vector3(1.5, 1.2, 1.5), "wood")

	# --- telegraph runs across the open ground, breaking the empty skyline
	_wire_run(b, Vector3(-10, 0, -14), Vector3(-10, 0, 6))
	_wire_run(b, Vector3(10, 0, -14), Vector3(10, 0, 6))
	_wire_run(b, Vector3(-28, 0, 4), Vector3(-10, 0, 4))

	# --- levelling the thin cells. The occupancy grid in MapBuilder._validate
	# reports playable-height cover per 16 m cell; after MARKET landed, three
	# cells still sat at 5, 7 and 8 against a map average near 25, and all
	# three are ground you cross rather than fight over.
	# South-centre, between the tunnel mouth and the market.
	_container(b, Vector3(6, 0, 24), true, "metal")
	_awning(b, Vector3(2, 3.2, 27), Vector3(3.0, 0.4, 2.5))
	for q in [Vector3(1, 0, 22), Vector3(11, 0, 28), Vector3(6, 0, 30)]:
		_barrel(b, q)
	for q in [Vector3(9, 0, 19), Vector3(3, 0, 29)]:
		_pallet(b, q, true)
	_box(b, Vector3(13, 0, 26), Vector3(2, 2.4, 2), "crate")
	_wire_run(b, Vector3(2, 0, 18), Vector3(2, 0, 30))
	# East end of LONG: the sniper lane had cover along its length but ran out
	# before the east wall, so the last 16 m was a free kill.
	_container(b, Vector3(24, 0, -19), false, "accent")
	_box(b, Vector3(28, 0, -24), Vector3(2, 2.4, 2), "crate")
	_pallet(b, Vector3(27, 0, -20), true)
	for q in [Vector3(22, 0, -26), Vector3(30, 0, -21)]:
		_barrel(b, q)
	# Centre-east, the approach from MID to A-site. This block was written to
	# fix a thin cell and did not do enough: the cell was still 13 against a
	# map average near 31, the emptiest on the board. A walled well-head and a
	# stall give it something to fight around rather than four loose props.
	_container(b, Vector3(8, 0, 6), true, "metal")
	_pallet(b, Vector3(13, 0, 3), false)
	_barrel(b, Vector3(6, 0, 12))
	_box(b, Vector3(2, 0, 10), Vector3(2, 1.6, 2), "crate")
	# Well-head: a waist-high ring you can fight across but not through.
	_ring(b, Vector3(9, 0, 9), Vector3(5, 1.3, 5), "wall_b", 0.6)
	_box(b, Vector3(10, 1.3, 10), Vector3(3, 0.3, 3), "dark")
	_awning(b, Vector3(4, 3.2, 4), Vector3(3.0, 0.4, 2.5))
	for q in [Vector3(3, 0, 3), Vector3(14, 0, 9), Vector3(6, 0, 2)]:
		_barrel(b, q)
	for q in [Vector3(13, 0, 13), Vector3(4, 0, 14)]:
		_pallet(b, q, true)
	_box(b, Vector3(15, 0, 6), Vector3(2, 2.2, 2), "crate")
	_container(b, Vector3(2, 0, 12), false, "accent")

	# --- north-east: the last thin cell. The occupancy grid had it at 12
	# against the west's 69, and it is the corner where LONG's east end meets
	# A-site, so it was crossing ground between two fights rather than either.
	# A guard post with a stair to its roof gives the A-site approach something
	# to contest and gives LONG an east-end angle that is not just open wall.
	_building(b, Vector3(21, 0, -31), Vector3(8, 5, 7), "wall_b", "roof", 1, "z+", "shed")
	_stairs(b, Vector3(19, 0, -30), Vector3(1, 0, 0), 5, 2.5, "wood")
	_container(b, Vector3(17, 0, -28), true, "metal")
	_awning(b, Vector3(22, 3.4, -23), Vector3(3.0, 0.4, 2.5))
	for q in [Vector3(30, 0, -28), Vector3(19, 0, -25), Vector3(27, 0, -30)]:
		_barrel(b, q)
	_pallet(b, Vector3(25, 0, -27), true)
	_box(b, Vector3(29, 0, -18), Vector3(2, 2.2, 2), "crate")
	_wire_run(b, Vector3(18, 0, -30), Vector3(30, 0, -30))

	# --- MID plaza floor read flatter than the rooftops around it. Low walls
	# turn the top into a fight instead of a table you stand on.
	_wall_run(b, Vector3(-7, 4, -2), Vector3(1, 0, 0), 6, 1.4, 0.8, "wall_b", [], 0)
	_wall_run(b, Vector3(1, 4, 2), Vector3(0, 0, 1), 5, 1.4, 0.8, "wall_b", [], 0)
	_box(b, Vector3(-2, 4, -5), Vector3(1.6, 1.2, 1.6), "crate")

	# --- awnings off the terrace houses
	for i in 3:
		_awning(b, Vector3(-19, 4, -13.0 + i * 9.0), Vector3(2.5, 0.4, 4))

static func spawns_burg() -> Array:
	return [
		# Pulled in from +/-28: the perimeter towers were widened from a 4 to a
		# 5 and 6 footprint and swallowed all four corner spawns, so a third of
		# all spawns trapped the actor inside solid rock.
		Vector3(-23, 0, -23), Vector3(23, 0, 23), Vector3(-23, 0, 23),
		Vector3(20, 0, -8), Vector3(0, 0, 28), Vector3(-16, 0, -28),
		Vector3(20, 0, 20), Vector3(-22, 0, 0), Vector3(8, 0, 24),
		Vector3(29, 0, 0), Vector3(0, 4, 6), Vector3(-17, 0, 25),
	]

## Fixed angles so critics compare like with like every round. Each one is
## checked to sit in open air — an earlier set had two cameras buried inside
## solid boxes and produced five shots of the inside of a wall.
static func review_cameras_burg() -> Array:
	return [
		# Pulled in from (40,34,40). The arena occupied a fraction of the frame
		# while the reference render fills it, which made a density comparison
		# against Burg unfair to us in a way the map itself was not.
		{"name": "overview", "pos": Vector3(20, 17, 20), "look": Vector3(-2, 2, -2)},
		{"name": "long", "pos": Vector3(-18.5, 2.2, -21.5), "look": Vector3(28, 3.0, -21.0)},
		{"name": "mid", "pos": Vector3(-15, 2.2, 6), "look": Vector3(2, 5, -4)},
		{"name": "interior", "pos": Vector3(-12.5, 1.7, 11), "look": Vector3(-25, 1.9, 18)},
		{"name": "roof", "pos": Vector3(19, 14.0, -2), "look": Vector3(-2, 4, 0)},
		# Close on the west terrace. This is where three walls had a zero-width
		# pier and rendered as holes you could see straight through, so it earns
		# a permanent angle.
		{"name": "terrace", "pos": Vector3(-9, 2.0, -5), "look": Vector3(-27, 3.0, -5)},
	]

# ------------------------------------------------------------------ standoff
## The second map: a symmetric duel / standoff arena. Two identical starting
## bases face each other across an open middle that holds only a few boxes.
## Mirror-symmetric across z = 0 by construction: the approach cover is written
## once for +z and emitted again reflected, so the two sides cannot drift apart.
## (The bases are written per-side because the door must face the middle on both.)
static func boxes_standoff() -> Array:
	var b: Array = []
	_box(b, Vector3(-24, -1, -24), Vector3(48, 1, 48), "road")
	_ring(b, Vector3(-24, 0, -24), Vector3(48, 4.5, 48), "wall_c", 1.0)
	# four corner towers flush with the ring's inner face, crenellated tops
	for c in [Vector3(20, 4.5, 20), Vector3(20, 4.5, -23),
			Vector3(-23, 4.5, 20), Vector3(-23, 4.5, -23)]:
		_box(b, c, Vector3(3, 3, 3), "wall_b")
		for ci in 2:
			for cj in 2:
				_box(b, c + Vector3(ci * 2, 3, cj * 2), Vector3(1, 1, 1), "wall_c")
	_standoff_base(b, 1.0)      # north starting base
	_standoff_base(b, -1.0)     # south starting base
	var mid: Array = []
	_standoff_mid_plus(mid)
	for bx in mid:
		_box(b, bx["p"], bx["s"], bx["c"])
		_box(b, _ref_p(bx["p"], bx["s"]), bx["s"], bx["c"])
	_standoff_center(b)
	return b

## One starting base. `s` is +1 (north, z>0) or -1 (south, z<0). The north
## half is authored once and, for the south, every box is reflected across z=0
## so the two bases are exact mirrors. (Reflection also lands the south
## building's door on its center-facing z+ face, so no per-side door handling
## is needed.)
static func _standoff_base(b: Array, s: float) -> void:
	var half: Array = []
	# the "starting building": two floors, flat roof, door toward the middle
	_building(half, Vector3(-6, 0, 9), Vector3(12, 6, 8), "wall_a", "roof", 2, "z-", "flat")
	# a low fence on either side of the building, fencing in the spawn yard
	_wall_run(half, Vector3(-7.5, 0, 4), Vector3(0, 0, 1), 5, 1.4, 1.0, "wall_b", [], 0)
	_wall_run(half, Vector3(7.5, 0, 4), Vector3(0, 0, 1), 5, 1.4, 1.0, "wall_b", [], 0)
	# yard clutter: two crates flanking the door, pallets and barrels at the sides
	_box(half, Vector3(-3, 0, 6), Vector3(2, 2, 2), "crate")
	_box(half, Vector3(3, 0, 6), Vector3(2, 2, 2), "crate")
	_pallet(half, Vector3(-9, 0, 14), true)
	_pallet(half, Vector3(9, 0, 14), true)
	_barrel(half, Vector3(-9, 0, 11))
	_barrel(half, Vector3(9, 0, 11))
	_barrel(half, Vector3(-9, 0, 17))
	_barrel(half, Vector3(9, 0, 17))
	if s > 0.0:
		for bx in half:
			_box(b, bx["p"], bx["s"], bx["c"])
	else:
		for bx in half:
			_box(b, _ref_p(bx["p"], bx["s"]), bx["s"], bx["c"])

## Approach cover leading into the middle, all in z >= 0 so it reflects cleanly.
static func _standoff_mid_plus(b: Array) -> void:
	_wall_run(b, Vector3(-9, 0, 2), Vector3(1, 0, 0), 6, 1.6, 1.0, "wall_b", [], 0)
	_wall_run(b, Vector3(3, 0, 2), Vector3(1, 0, 0), 6, 1.6, 1.0, "wall_b", [], 0)

## The middle itself: just a few boxes, laid out symmetric across the z=0
## axis BY CONSTRUCTION — each +z piece is emitted again through _ref_p so
## the halves cannot drift (hand-writing the −z counterparts at "eyeballed"
## positions put crates/barrels/pallets at the wrong mirrored z and broke the
## map's own fairness claim; found by the round-2 symmetry probe).
static func _standoff_center(b: Array) -> void:
	_container(b, Vector3(-2.5, 0, -1), true, "metal")
	var half: Array = []
	_box(half, Vector3(6.0, 0, 2.0), Vector3(2, 2, 2), "crate")
	_barrel(half, Vector3(3.0, 0, 2.5))
	_pallet(half, Vector3(0, 0, 3.0), true)
	for bx in half:
		_box(b, bx["p"], bx["s"], bx["c"])
		_box(b, _ref_p(bx["p"], bx["s"]), bx["s"], bx["c"])

## Reflect a box's min corner across the z = 0 plane; size is unchanged.
static func _ref_p(p: Vector3, s: Vector3) -> Vector3:
	return Vector3(p.x, p.y, -(p.z + s.z))

static func spawns_standoff() -> Array:
	# Two earlier spawn sets read as "outside the map": (0,0,±6) sat in front of
	# the building's door and were path-pulled into its sealed interior (reach 0
	# → relocated to the side walls), and the back band (0,±19),(±12,±16) sat
	# between the building and the 4.5 m perimeter wall, so actors there looked
	# trapped against the map edge. All spawns are now on open, well-connected
	# ground in the front of each base (z within ±13, x within ±12), never in
	# front of the door and never in the tight band behind the building.
	return [
		Vector3(-9, 0, 5), Vector3(9, 0, 5),
		Vector3(-12, 0, 10), Vector3(12, 0, 10),
		Vector3(-9, 0, 13), Vector3(9, 0, 13),
		Vector3(-9, 0, -5), Vector3(9, 0, -5),
		Vector3(-12, 0, -10), Vector3(12, 0, -10),
		Vector3(-9, 0, -13), Vector3(9, 0, -13),
	]

static func review_cameras_standoff() -> Array:
	return [
		{"name": "overview", "pos": Vector3(20, 18, 20), "look": Vector3(0, 0, 0)},
		{"name": "northbase", "pos": Vector3(0, 2.2, 8), "look": Vector3(0, 3, -12)},
		{"name": "southbase", "pos": Vector3(0, 2.2, -8), "look": Vector3(0, 3, 12)},
		{"name": "mid", "pos": Vector3(12, 3, 0), "look": Vector3(-12, 1, 0)},
		{"name": "flank", "pos": Vector3(12, 1.6, 0), "look": Vector3(-6, 1.5, 0)},
	]

# ------------------------------------------------------------------ helpers
static func _box(b: Array, p: Vector3, s: Vector3, c: String) -> void:
	b.append({"p": p, "s": s, "c": c})

static func _ring(b: Array, p: Vector3, s: Vector3, c: String, t: float) -> void:
	_box(b, Vector3(p.x, p.y, p.z), Vector3(s.x, s.y, t), c)
	_box(b, Vector3(p.x, p.y, p.z + s.z - t), Vector3(s.x, s.y, t), c)
	# The two side piers must be mirror images of each other in z as well as x
	# (standoff's roof parapet sits at odd z, and an asymmetric pier pair broke
	# the z-mirror check). Emit the second pier as the z-mirror of the first.
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
		floors: int, door_side: String, roof_style: String = "pitch") -> void:
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
		# floor(), not ceil(): with ceil the top step ended level with the slab
		# above it, so two upward faces sat at identical depth and flickered.
		# Landing one step short leaves a lip you can still walk up.
		_stairs(b, Vector3(p.x + 1, y - storey, p.z + 1), Vector3(0, 0, 1),
			maxi(1, int(floor(storey))), well, "wood")
	var rp := Vector3(p.x, p.y + s.y, p.z)
	var rs := Vector3(s.x, 1, s.z)
	match roof_style:
		"flat":
			_flat_roof(b, rp, rs, roof)
		"shed":
			_shed_roof(b, rp, rs, roof)
		_:
			_pitched_roof(b, rp, rs, roof)
	# _pitched_roof is x/z-axis-ordered (it insets x first, z second), so the
	# north and south builds of the same building emit DIFFERENT box lists —
	# standoff's "mirror by construction" claim silently failed on 18 boxes
	# (found by the round-2 symmetry probe). Inset along the LARGER axis only,
	# so the box list is independent of which axis runs which way.
	_pitched_roof_xz(b, rp, rs, roof)

## Axis-stable pitched roof: insets along whichever of x/z is longer (ties go
## to x), so a box list generated for a building at (x,z) matches one
## generated for its z-mirror. Same silhouette as _pitched_roof.
static func _pitched_roof_xz(b: Array, p: Vector3, s: Vector3, key: String) -> void:
	var steps: int = int(minf(s.x, s.z) / 2.0)
	for i in steps:
		var inset := float(i)
		var w: float = s.x - inset * 2.0
		var d: float = s.z - inset * 2.0
		if w <= 0.0 or d <= 0.0:
			break
		var along_x: bool = s.x >= s.z
		var w2: float = w if along_x else w
		var d2: float = d if along_x else d
		_box(b, Vector3(p.x + inset, p.y + float(i), p.z + inset),
			Vector3(w2, 1, d2), key)

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
## Flat roof with a parapet you can stand behind. One of three roof styles:
## the map had exactly ONE roof generator and one building generator driving
## every structure, so the whole skyline was a single kit at four sizes.
static func _flat_roof(b: Array, p: Vector3, s: Vector3, key: String) -> void:
	_box(b, p, Vector3(s.x, 0.4, s.z), key)
	_ring(b, Vector3(p.x, p.y + 0.4, p.z), Vector3(s.x, 1.1, s.z), "wall_b", 0.4)

## Single-slope shed roof: steps up along x only, so it reads as a lean-to
## rather than a pyramid and gives the silhouette an asymmetric edge.
static func _shed_roof(b: Array, p: Vector3, s: Vector3, key: String) -> void:
	# Equal 0.6 m steps made this converge with _pitched_roof at oblique range:
	# both read as a stair of identical boxes. The run LENGTHENS as it climbs
	# and the top is one long low slab, so the profile is a shallow ramp into a
	# flat cap rather than another staircase.
	var steps: int = 3
	var total: float = 0.0
	var runs: Array = []
	for i in steps:
		var r: float = 1.0 + float(i) * 1.4
		runs.append(r)
		total += r
	var scale: float = s.x / total
	var x: float = 0.0
	for i in steps:
		var run: float = float(runs[i]) * scale
		_box(b, Vector3(p.x + x, p.y + float(i) * 0.5, p.z),
			Vector3(run, 0.5 + float(i) * 0.5, s.z), key)
		x += run
	# eaves overhang: a thin lip past the low edge, which no pyramid has
	_box(b, Vector3(p.x - 0.5, p.y, p.z - 0.4), Vector3(1.0, 0.3, s.z + 0.8), key)

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
