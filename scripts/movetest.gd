extends Node
## Headless movement probe. Movement cannot be judged from a screenshot, so it
## gets numbers instead.
##
##   godot --path . -- movetest
##
## Prints one JSON line prefixed MOVETEST so a critic can check our movement
## envelope against the claims in reference/krunker-movement.md.

enum Phase { WALK, HOP, STRAFE, TURN, WALL, DONE }

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
var ground_y: float = 0.0

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
	add_child(slab)

func _physics_process(delta: float) -> void:
	if player == null or phase == Phase.DONE:
		return
	t += delta
	var m: Motor = player.motor
	var fwd := Vector3(0, 0, -1)

	match phase:
		Phase.WALK:
			# plain forward run, no jumping: establishes the baseline
			m.step(fwd, false, false, delta)
			peak_walk = maxf(peak_walk, m.speed_flat)
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
				_finish()

func _reset(next: int) -> void:
	phase = next
	t = 0.0
	# Each phase must measure itself, not inherit the previous phase's momentum.
	# Without this the strafe number was just the slide-hop peak carried over.
	player.global_position = Vector3(0, PLATFORM_Y + 1.2, 160.0)
	player.velocity = Vector3.ZERO
	player.motor.sliding = false
	player.motor.slide_cd = 0.0
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
	}
	print("MOVETEST ", JSON.stringify(results))
	get_tree().quit(0)
