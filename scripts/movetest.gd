extends Node
## Headless movement probe. Movement cannot be judged from a screenshot, so it
## gets numbers instead.
##
##   godot --path . -- movetest
##
## Prints one JSON line prefixed MOVETEST so a critic can check our movement
## envelope against the claims in reference/krunker-movement.md.

enum Phase { WALK, HOP, STRAFE, TURN, WALL, STAIRS, EARLY, LATE, DONE }

var player: Player
var phase: int = Phase.WALK
var t: float = 0.0
var results: Dictionary = {}

var peak_walk: float = 0.0
var peak_hop: float = 0.0
var peak_strafe: float = 0.0
var hops: int = 0
var hops_to_peak: int = 0
var slides: int = 0
var speed_before_turn: float = 0.0
var speed_after_turn: float = 0.0
var start_pos := Vector3.ZERO
var walk_distance: float = 0.0
var hop_distance: float = 0.0
var apex: float = 0.0
var wall_jumps: int = 0
var wall_peak_y: float = 0.0
var wall_peak_speed: float = 0.0
var wall_start_y: float = 0.0
var stair_start_y: float = 0.0
var stair_climbed: float = 0.0
var stair_jumps: int = 0
var ground_y: float = 0.0
# slide_late_penalty had real code and no evidence it ever fired: every hop in
# the HOP phase lands and re-jumps on the same tick, so since_landing is always
# 0 there and the penalty branch is unreachable. These two phases jump out of a
# slide on purpose, once inside the re-jump window and once well outside it,
# and measure the speed ratio across the jump tick itself.
var early_ratio: float = -1.0
var late_ratio: float = -1.0
var early_since: float = -1.0
var late_since: float = -1.0

func _ready() -> void:
	name = "MoveTest"
	await get_tree().process_frame
	player = Game.local_player as Player
	if player == null:
		push_error("movetest: no local player")
		get_tree().quit(1)
		return
	# The player's own _physics_process also calls motor.step(). Leaving it
	# enabled would double-step the motor and apply a spurious tick of friction
	# every frame, which is exactly what made the first run report zero gain.
	player.input_enabled = false
	player.set_physics_process(false)
	# Run the probe on its own empty slab far above the arena. Measuring on the
	# map meant the first run walked straight into the centre building and
	# reported a 0.13 "gain ratio" that was really just a wall.
	_build_platform()
	player.global_position = Vector3(0, PLATFORM_Y + 1.2, 160.0)
	player.velocity = Vector3.ZERO
	start_pos = player.global_position
	ground_y = PLATFORM_Y + 1.0

const PLATFORM_Y := 500.0

func _build_platform() -> void:
	var slab := StaticBody3D.new()
	slab.collision_layer = 1
	slab.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 2, 400)
	cs.shape = box
	cs.position = Vector3(0, PLATFORM_Y, 0)
	slab.add_child(cs)
	# A vertical face to kick off. Wall-jump existed in motor.gd for a whole
	# round with no probe phase touching it, so its constants were unverified.
	var wall := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(2, 40, 40)
	wall.shape = wb
	wall.position = Vector3(-8, PLATFORM_Y + 20, 0)
	slab.add_child(wall)
	# Four 1-unit risers. A single map block is 1.0, and that must be walkable
	# without jumping or every staircase in the arena is a wall.
	for i in 4:
		var st := CollisionShape3D.new()
		var sb := BoxShape3D.new()
		sb.size = Vector3(8, 1.0 * float(i + 1), 2)
		st.shape = sb
		st.position = Vector3(20, PLATFORM_Y + 1.0 + sb.size.y * 0.5 - 1.0, -6.0 - float(i) * 2.0)
		slab.add_child(st)
	add_child(slab)

func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE:
		return
	t += delta
	var m: Motor = player.motor
	var fwd := Vector3(0, 0, -1)

	match phase:
		Phase.WALK:
			# Plain forward run, no jumping: the baseline. Discard the first
			# second so this measures three seconds at speed, exactly like the
			# hop phase — otherwise the distance ratio compares a 4 s window
			# against a 3 s one and flatters whichever is longer.
			m.step(fwd, false, false, delta)
			peak_walk = maxf(peak_walk, m.speed_flat)
			if t < 1.0:
				start_pos = player.global_position
			if t >= 4.0:
				walk_distance = start_pos.distance_to(player.global_position)
				_reset(Phase.HOP)
		Phase.HOP:
			# A real slide-hopper HOLDS crouch and HOLDS jump. Gating crouch on
			# "descending" never fired, because move_and_slide zeroes velocity.y
			# on the landing tick — exactly the tick the slide has to start.
			# Holding both lets the motor slide (banking a boost) and then
			# launch out of it in the same tick, which is the Krunker chain.
			# The first second is a ground run-up: you cannot slide below
			# slide_min_speed, so hopping from a standstill never starts a chain.
			var run_up: bool = t < 1.0
			m.step(fwd, not run_up, not run_up, delta)
			if run_up:
				start_pos = player.global_position
				return
			if m.jumped_this_tick:
				hops += 1
			if m.slid_this_tick:
				slides += 1
			if m.speed_flat > peak_hop + 0.01:
				peak_hop = m.speed_flat
				hops_to_peak = hops
			apex = maxf(apex, player.global_position.y - ground_y)
			if t >= 4.0:
				hop_distance = start_pos.distance_to(player.global_position)
				_reset(Phase.STRAFE)

		Phase.STRAFE:
			# hold two keys, which is Krunker's substitute for a sprint button
			m.step(Vector3(1, 0, -1), false, false, delta)
			peak_strafe = maxf(peak_strafe, m.speed_flat)
			if t >= 4.0:
				speed_before_turn = m.speed_flat
				_reset(Phase.TURN)

		Phase.TURN:
			# 90-degree direction change at speed: how much momentum survives
			m.step(Vector3(1, 0, 0), false, false, delta)
			if t >= 0.35:
				speed_after_turn = m.speed_flat
				_reset(Phase.WALL)
				player.global_position = Vector3(-4, PLATFORM_Y + 1.2, 0)
				player.velocity = Vector3.ZERO
				wall_start_y = player.global_position.y

		Phase.WALL:
			# Run at the wall and hold jump: on the ground that is a normal
			# jump, in the air against the face it should be a wall-kick.
			m.step(Vector3(-1, 0, 0), true, false, delta)
			if m.wall_jumped_this_tick:
				wall_jumps += 1
			wall_peak_y = maxf(wall_peak_y, player.global_position.y - wall_start_y)
			wall_peak_speed = maxf(wall_peak_speed, m.speed_flat)
			if t >= 3.0:
				_reset(Phase.STAIRS)
				player.global_position = Vector3(20, PLATFORM_Y + 1.2, 2.0)
				player.velocity = Vector3.ZERO
				stair_start_y = player.global_position.y

		Phase.STAIRS:
			# Walk into the risers with jump explicitly held OFF.
			m.step(Vector3(0, 0, -1), false, false, delta)
			if m.jumped_this_tick:
				stair_jumps += 1
			stair_climbed = maxf(stair_climbed, player.global_position.y - stair_start_y)
			if t >= 4.0:
				_reset(Phase.EARLY)

		Phase.EARLY:
			# Chain hops: each one lands and launches in the same tick, so
			# since_landing is ~0 and no penalty should apply.
			var warm: bool = t < 1.0
			_timed_step(m, fwd, not warm, not warm, delta)
			if t >= 3.0:
				_reset(Phase.LATE)

		Phase.LATE:
			# Run along the ground first. since_landing counts up the whole
			# time we stay grounded, so sliding out of a long ground run is
			# exactly the mistimed case the penalty is meant to punish.
			var late_jump: bool = t >= 1.4
			_timed_step(m, fwd, late_jump, late_jump, delta)
			if t >= 2.2:
				_finish()

## Step the motor while recording what the jump did to horizontal speed.
func _timed_step(m: Motor, dir: Vector3, jump: bool, crouch: bool, delta: float) -> void:
	var before: float = m.speed_flat
	m.step(dir, jump, crouch, delta)
	# Sampling m.sliding around the call caught nothing: the slide both starts
	# and ends inside step(), so it is false before and false after.
	if not m.slide_jumped_this_tick:
		return
	var ratio: float = m.speed_flat / maxf(0.001, before)
	# Read since_landing from where the branch actually evaluated it. Sampling
	# it before step() reported 1.467 s for a jump the motor correctly treated
	# as on-time, because the landing that zeroed it happened inside the step.
	if m.slide_jump_was_late:
		late_ratio = ratio
		late_since = m.slide_jump_since_landing
	elif early_ratio < 0.0:
		early_ratio = ratio
		early_since = m.slide_jump_since_landing

func _reset(next: int) -> void:
	phase = next
	t = 0.0
	# Each phase must measure itself, not inherit the previous phase's momentum.
	# Without this the strafe number was just the slide-hop peak carried over.
	player.global_position = Vector3(0, PLATFORM_Y + 1.2, 160.0)
	player.velocity = Vector3.ZERO
	player.motor.sliding = false
	player.motor.slide_cd = 0.0
	# Carry-over would fire a phantom jump on the first tick of the next phase:
	# the stairs phase held jump OFF and still recorded one, banked from the
	# wall phase before it.
	player.motor.jump_buffered = 0.0
	player.motor.coyote = 0.0
	start_pos = player.global_position

func _finish() -> void:
	phase = Phase.DONE
	var base: float = Tuning.max_ground_speed
	results = {
		"base_speed_mps": base,
		"peak_walk_mps": peak_walk,
		"peak_slidehop_mps": peak_hop,
		"peak_strafe_mps": peak_strafe,
		"slidehop_gain_ratio": peak_hop / maxf(0.001, peak_walk),
		"strafe_gain_ratio": peak_strafe / maxf(0.001, peak_walk),
		"hops_to_peak": hops_to_peak,
		"hops_total": hops,
		"slides_total": slides,
		"jump_apex_m": apex,
		"apex_from_constants_m": (Tuning.jump_velocity * Tuning.jump_velocity) / (2.0 * Tuning.gravity),
		"walk_dist_3s_m": walk_distance,
		"slidehop_dist_3s_m": hop_distance,
		"distance_gain_ratio": hop_distance / maxf(0.001, walk_distance),
		"speed_before_90deg_turn": speed_before_turn,
		"speed_after_90deg_turn": speed_after_turn,
		"turn_retention": speed_after_turn / maxf(0.001, speed_before_turn),
		"hard_cap_mps": Tuning.hard_speed_cap,
		"strafe_bonus_setting": Tuning.strafe_bonus,
		"wall_jumps_performed": wall_jumps,
		"wall_jump_charges_setting": Tuning.wall_jump_charges,
		"wall_peak_height_gain_m": wall_peak_y,
		"wall_peak_speed_mps": wall_peak_speed,
		"slide_rejump_window_s": Tuning.slide_rejump_window,
		"step_height_setting": Tuning.step_height,
		"stairs_climbed_m_no_jump": stair_climbed,
		"stairs_jumps_used": stair_jumps,
		"stairs_available_m": 3.0,   # four risers, top sits 3 m above the slab
		"slide_late_penalty_setting": Tuning.slide_late_penalty,
		"rejump_early_ratio": snappedf(early_ratio, 0.001),
		"rejump_early_since_landing_s": snappedf(early_since, 0.001),
		"rejump_late_ratio": snappedf(late_ratio, 0.001),
		"rejump_late_since_landing_s": snappedf(late_since, 0.001),
	}
	print("MOVETEST ", JSON.stringify(results))
	get_tree().quit(0)
