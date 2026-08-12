class_name Bot
extends Actor
## AI opponent. Runs the exact same Motor and Weapon as the player, so it
## slides, bhops, misses, reloads and dies by the same rules.

var brain := BotBrain.new()
var agent: NavigationAgent3D
var roam_target := Vector3.ZERO
var repath_timer: float = 0.0
var stuck_time: float = 0.0
var hop_route: bool = false   # decided per route, not per tick
var preferred_range: float = 9.0
var loadout_index: int = -1        # set by main so the lobby has a real mix

## How far this bot wants to fight from, by the gun it is holding.
const RANGE_BY_WEAPON := {
	"shotgun": 4.0, "smg": 7.0, "pistol": 9.0, "assault": 13.0, "sniper": 26.0,
}

func _ready() -> void:
	super._ready()
	brain.bot = self
	brain.skill = Game.rng.randf_range(0.7, 1.25)
	brain.burst_left = Game.rng.randi_range(4, 9)

	agent = NavigationAgent3D.new()
	agent.radius = 0.42
	agent.height = Tuning.stand_height
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 1.1
	agent.path_max_distance = 4.0
	agent.avoidance_enabled = false
	add_child(agent)

	# A lobby of random guns produces mush. Deal from the loadout in order so a
	# match reliably contains snipers holding lanes and SMGs rushing.
	var pool := ["assault", "smg", "sniper", "assault", "shotgun", "smg", "sniper", "pistol"]
	var key: String = pool[(loadout_index if loadout_index >= 0 else Game.rng.randi()) % pool.size()]
	weapon.equip(key)
	preferred_range = float(RANGE_BY_WEAPON.get(key, 9.0))
	# Snipers hold still and aim; brawlers churn. Skill scales reaction too.
	if key == "sniper":
		brain.skill = maxf(brain.skill, 1.0)
	weapon.fired.connect(_on_fired)
	weapon.landed.connect(_on_landed)
	weapon.missed.connect(_on_missed)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	brain.think(delta, Game.actors)
	_steer(delta)
	_aim(delta)
	_shoot()
	_place_hitboxes()
	_animate_body(delta)
	_regen(delta)

func _steer(delta: float) -> void:
	repath_timer -= delta
	stuck_time = stuck_time + delta if motor.grounded and motor.speed_flat < 1.0 else 0.0
	var wish := Vector3.ZERO
	var want_jump := false
	var want_crouch := false

	match brain.state:
		BotBrain.State.ENGAGE:
			var t: Actor = brain.target
			if is_instance_valid(t):
				var to: Vector3 = t.global_position - global_position
				to.y = 0.0
				var dist := to.length()
				var fwd := to.normalized()
				var side := Vector3(-fwd.z, 0, fwd.x) * brain.strafe_dir
				# Preferred range depends on the gun this bot spawned with: a
				# shotgun bot that holds an angle is useless, and so is a
				# sniper bot that walks into your face.
				var approach: float = clampf((dist - preferred_range) / 9.0, -1.0, 1.0)
				var hurt: float = health / maxf(1.0, Tuning.max_health)
				# Break line of sight properly rather than backpedalling in the
				# open. bot_leave_cover_chance decides how willing this bot is
				# to pop back out once it has healed or reloaded.
				if brain.in_cover:
					var to_cover: Vector3 = brain.cover_point - global_position
					to_cover.y = 0.0
					if to_cover.length() > 1.2:
						wish = to_cover.normalized() * 1.3
						motor.step(wish, false, false, delta)
						return
					if brain.cover_hold <= 0.0 \
							and (hurt > Tuning.bot_retreat_health or weapon.mag > 0) \
							and Game.rng.randf() < Tuning.bot_leave_cover_chance:
						brain.in_cover = false
				if hurt < Tuning.bot_retreat_health and not brain.in_cover:
					var spot := _find_cover(t)
					if spot != Vector3.INF:
						brain.in_cover = true
						brain.cover_point = spot
						brain.cover_hold = Game.rng.randf_range(0.8, 2.0)
				if hurt < Tuning.bot_retreat_health:
					# Break contact when losing. Without this a bot at 15 HP
					# walks into a shotgun exactly like a bot at 100, which is
					# the single most obviously non-human thing they did.
					approach = -1.0
					brain.retreating = true
					if weapon.mag < int(weapon.def["mag"]) / 2:
						weapon.start_reload()
				else:
					brain.retreating = false
				# A sniper holding an angle should hold still; a brawler churns.
				var strafe_weight: float = 0.35 if preferred_range > 20.0 and dist > 15.0 else 1.0
				wish = fwd * approach + side * strafe_weight
				# Was a jump roughly every second per bot, so the whole lobby
				# read as popcorn. Now an occasional dodge.
				if brain.jump_timer <= 0.0 and dist < 22.0 and Game.rng.randf() < 0.0035:
					brain.jump_timer = Game.rng.randf_range(1.8, 3.6)
					want_jump = true
				# slide to break aim when strafing at speed, and always slide
				# when running away — it is the fastest way out of a sightline
				var slide_roll: float = 0.02 if brain.retreating else 0.004
				if motor.speed_flat > Tuning.slide_min_speed and Game.rng.randf() < slide_roll:
					want_crouch = true
		_:
			if repath_timer <= 0.0 or global_position.distance_to(roam_target) < 2.5:
				_repath()
			var next: Vector3 = agent.get_next_path_position()
			var d: Vector3 = next - global_position
			d.y = 0.0
			if d.length() > 0.35:
				wish = d.normalized()
			else:
				# The navmesh agent can return our own position when the target
				# is unreachable or the path has not solved yet. Steering
				# straight at the goal beats standing still and hopping.
				var straight := roam_target - global_position
				straight.y = 0.0
				if straight.length() > 1.0:
					wish = straight.normalized()
			if agent.is_navigation_finished():
				repath_timer = 0.0
			# Cross open ground the way a player does: chain slide-hops — but
			# only on some routes. Every bot hopping every transit looked
			# ridiculous and made them hard to read.
			if hop_route and wish.length_squared() > 0.5 \
					and motor.speed_flat > Tuning.slide_min_speed:
				want_jump = true
				want_crouch = true

	# Genuinely stuck: wedged on a corner or pathing into a wall. The previous
	# version rolled a 25% jump chance EVERY TICK, so any blocked bot hopped
	# 120 times a second and never went anywhere — that, not spawning, was why
	# bots were airborne 90% of the time and idle 97%.
	if stuck_time > 0.5:
		want_jump = true
		if stuck_time > 1.1:
			stuck_time = 0.0
			_repath()
			# sidestep whatever we are caught on
			brain.strafe_dir = -brain.strafe_dir
			wish = (wish + Vector3(-wish.z, 0, wish.x) * 0.8).normalized() \
				if wish.length_squared() > 0.01 else _random_dir()

	motor.step(wish, want_jump, want_crouch, delta)

func _repath() -> void:
	repath_timer = Game.rng.randf_range(1.5, 3.5)
	hop_route = Game.rng.randf() < 0.35
	roam_target = _pick_roam_point()
	agent.target_position = roam_target

func _random_dir() -> Vector3:
	var a := Game.rng.randf_range(0.0, TAU)
	return Vector3(cos(a), 0, sin(a))

## Find a standing position near us that breaks line of sight to `t`.
## Samples a ring of candidates and returns the closest one the target cannot
## see. Vector3.INF means nowhere nearby works, so keep fighting.
func _find_cover(t: Actor) -> Vector3:
	if not is_instance_valid(t):
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	var eye_h := Vector3(0, Tuning.eye_height, 0)
	var best := Vector3.INF
	var best_d := 1e9
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		for r in [3.5, 7.0]:
			var c: Vector3 = global_position + Vector3(cos(a), 0, sin(a)) * r
			var q := PhysicsRayQueryParameters3D.create(c + eye_h, t.eye_position(),
				WORLD_MASK, exclude_rids)
			q.collide_with_areas = false
			if space.intersect_ray(q).is_empty():
				continue                      # target can still see this spot
			var d: float = global_position.distance_to(c)
			if d < best_d:
				best_d = d
				best = c
	return best

func _pick_roam_point() -> Vector3:
	if brain.state == BotBrain.State.HUNT:
		return brain.last_seen_pos
	# Half the time head toward another player. Two of seven bots spent an
	# entire 14-second measurement at 0% engagement wandering spawn points,
	# which no populated lobby looks like.
	if Game.rng.randf() < 0.5:
		var live: Array = Game.actors.filter(func(a): return a != self and a.alive)
		if not live.is_empty():
			var other: Actor = live[Game.rng.randi() % live.size()]
			return other.global_position
	var arena := Game.arena as MapBuilder
	if arena and arena.spawn_points.size() > 0:
		return arena.spawn_points[Game.rng.randi() % arena.spawn_points.size()]
	return global_position

func _aim(delta: float) -> void:
	var t: Actor = brain.target
	var desired_yaw := yaw
	var desired_pitch := pitch
	if brain.state == BotBrain.State.ENGAGE and is_instance_valid(t):
		var aim_at: Vector3 = t.eye_position()
		# lead the target a little: bots that ignore movement never hit a slider
		aim_at += t.velocity * 0.045 * brain.skill
		var err := brain.aim_error()
		if err > 0.001:
			aim_at += Vector3(
				Game.rng.randfn(0.0, err * 0.03),
				Game.rng.randfn(0.0, err * 0.02),
				Game.rng.randfn(0.0, err * 0.03))
		var to: Vector3 = aim_at - eye_position()
		desired_yaw = atan2(-to.x, -to.z)
		desired_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	elif motor.speed_flat > 0.5:
		desired_yaw = atan2(-velocity.x, -velocity.z)
		desired_pitch = 0.0

	var speed: float = Tuning.bot_aim_speed * brain.skill
	yaw = lerp_angle(yaw, desired_yaw, clampf(delta * speed, 0.0, 1.0))
	pitch = lerpf(pitch, clampf(desired_pitch, -Tuning.pitch_limit, Tuning.pitch_limit),
		clampf(delta * speed, 0.0, 1.0))

func _shoot() -> void:
	if weapon.mag <= 0:
		weapon.start_reload()
		return
	if not brain.wants_to_shoot():
		return
	if weapon.try_fire():
		brain.note_shot(weapon.def)

# ------------------------------------------------------------------ feedback
func _on_fired(d: Dictionary, muzzle: Vector3, _dir: Vector3) -> void:
	# Past about 22 m the high transient is gone and you hear the tail, so a
	# firefight across the map sounds different from one in your face.
	var tone: String = String(d["tone"])
	if is_instance_valid(Game.local_player) \
			and muzzle.distance_to(Game.local_player.global_position) > 22.0:
		tone += "_far"
	Audio.play_at(tone, muzzle, float(d["pitch"]) * randf_range(0.96, 1.04), -6.0)
	if Game.fx:
		Game.fx.muzzle_flash(muzzle, float(d["muzzle_flash"]) * 0.6)
		Game.fx.eject_shell(muzzle - aim_dir() * 0.25, aim_basis(),
			d.get("shell_color", Color8(200, 158, 76)), float(d.get("shell_scale", 1.0)))

func _on_landed(_zone: int, _dmg: float, pos: Vector3, normal: Vector3, _v: Actor, _k: bool) -> void:
	if Game.fx:
		Game.fx.tracer(weapon.muzzle_position(), pos, 0.8)
		Game.fx.impact(pos, normal, Color8(240, 90, 80))

func _on_missed(pos: Vector3, normal: Vector3) -> void:
	if Game.fx:
		Game.fx.tracer(weapon.muzzle_position(), pos, 0.8)
		Game.fx.impact(pos, normal, Color8(210, 205, 195))
	Audio.play_at("impact", pos, randf_range(0.9, 1.15), -20.0)
